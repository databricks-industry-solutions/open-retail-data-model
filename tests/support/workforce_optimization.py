"""Deterministic Workforce Optimization reference implementation for unit tests.

Stdlib + datetime by default. OR-Tools is an optional dependency: when installed,
`ortools_schedule` / `optimize_schedule(..., method='ortools')` solve the same
output contract as the greedy heuristic. Same inputs always produce the same
outputs. Mirrors ADR 0043 and the Predictive Operations Workforce Optimization
tables/gold views.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from math import ceil
from typing import Callable, Dict, Iterable, List, Optional, Sequence, Set, Tuple


UTC = timezone.utc

try:
    from ortools.sat.python import cp_model as _cp_model
    _HAS_ORTOOLS = True
except ImportError:  # pragma: no cover - exercised when ortools absent
    _cp_model = None
    _HAS_ORTOOLS = False


def has_ortools() -> bool:
    """True when ortools is importable in this environment."""
    return _HAS_ORTOOLS


def _ensure_aware(ts: datetime) -> datetime:
    if ts.tzinfo is None:
        return ts.replace(tzinfo=UTC)
    return ts.astimezone(UTC)


# ---------------------------------------------------------------------------
# Typed records
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Employee:
    employee_id: str
    store_id: str
    role_code: str
    skills: frozenset
    hourly_cost: float
    max_daily_hours: float
    max_weekly_hours: float
    min_rest_hours: float

    def __post_init__(self):
        object.__setattr__(self, "skills", frozenset(self.skills))


@dataclass(frozen=True)
class AvailabilityWindow:
    employee_id: str
    start: datetime
    end: datetime
    is_available: bool


@dataclass(frozen=True)
class DemandInterval:
    store_id: str
    zone: str
    role_code: str
    start: datetime
    end: datetime
    required_headcount: float
    required_hours: float


@dataclass(frozen=True)
class ExistingShift:
    employee_id: str
    store_id: str
    role_code: str
    start: datetime
    end: datetime


@dataclass(frozen=True)
class Recommendation:
    employee_id: str
    store_id: str
    zone: str
    role_code: str
    start: datetime
    end: datetime
    assigned_hours: float
    estimated_labor_cost: float
    is_availability_ok: bool = True
    is_skill_ok: bool = True
    is_store_eligible_ok: bool = True
    is_hours_cap_ok: bool = True
    is_min_rest_ok: bool = True


@dataclass(frozen=True)
class CoverageException:
    store_id: str
    zone: str
    role_code: str
    start: datetime
    end: datetime
    required_headcount: float
    scheduled_headcount: float
    shortfall_headcount: float
    severity: str
    exception_explanation: str
    suggested_action: str


@dataclass(frozen=True)
class RunMetrics:
    recommended_shift_count: int
    exception_count: int
    scheduled_hours_total: float
    required_hours_total: float
    coverage_pct: float
    unfilled_demand_hours: float
    estimated_labor_cost: float
    fairness_score: float
    optimization_status: str  # success | success_partial | infeasible
    input_employee_count: int = 0
    input_demand_intervals: int = 0


# ---------------------------------------------------------------------------
# Forecast + signal preference
# ---------------------------------------------------------------------------


def _avg(values: Sequence[float]) -> Optional[float]:
    if not values:
        return None
    return sum(values) / len(values)


def _bucket_minute(ts: datetime, interval_minutes: int) -> int:
    return (ts.minute // interval_minutes) * interval_minutes


def build_interval_history_from_orders(
    order_lines: Sequence[dict],
    interval_minutes: int = 30,
    role_code: str = "cashier",
) -> List[dict]:
    """Bucket order event_timestamp rows into per-day interval slots.

    Each order_line dict: store_id, event_timestamp (aware UTC), units (optional).
    Optional dow (Spark dayofweek) overrides the derived day-of-week.
    Grain includes business_date so seasonal_rolling_forecast can average
    across days for the same (store, role, dow, hour).
    """
    if interval_minutes <= 0:
        raise ValueError("interval_minutes must be positive")
    buckets: Dict[Tuple[str, str, str, int, int, int], float] = defaultdict(float)
    for row in order_lines:
        ts = _ensure_aware(row["event_timestamp"])
        units = float(row.get("units", 1) or 1)
        if "dow" in row:
            spark_dow = int(row["dow"])
        else:
            spark_dow = ((ts.weekday() + 1) % 7) + 1
        business_date = ts.date().isoformat()
        key = (
            row["store_id"],
            role_code,
            business_date,
            spark_dow,
            ts.hour,
            _bucket_minute(ts, interval_minutes),
        )
        buckets[key] += units
    return [
        {
            "store_id": k[0],
            "role_code": k[1],
            "business_date": k[2],
            "dow": k[3],
            "hour": k[4],
            "minute": k[5],
            "units": v,
            "signal_source": "orders",
        }
        for k, v in sorted(buckets.items())
    ]


def build_interval_history_from_css(
    css_intervals: Sequence[dict],
    interval_minutes: int = 30,
    role_code: str = "sales_associate",
) -> List[dict]:
    """Bucket CSS site-level footfall into per-day interval slots.

    Each css_intervals dict: store_id, interval_start_ts, footfall_count,
    optional aggregation_level (only 'site' rows are used when present).
    """
    if interval_minutes <= 0:
        raise ValueError("interval_minutes must be positive")
    buckets: Dict[Tuple[str, str, str, int, int, int], float] = defaultdict(float)
    for row in css_intervals:
        level = row.get("aggregation_level")
        if level is not None and level != "site":
            continue  # never sum across CSS aggregation levels
        ts = _ensure_aware(row["interval_start_ts"])
        units = float(row.get("footfall_count", 0) or 0)
        spark_dow = int(row["dow"]) if "dow" in row else ((ts.weekday() + 1) % 7) + 1
        business_date = ts.date().isoformat()
        key = (
            row["store_id"],
            role_code,
            business_date,
            spark_dow,
            ts.hour,
            _bucket_minute(ts, interval_minutes),
        )
        buckets[key] += units
    return [
        {
            "store_id": k[0],
            "role_code": k[1],
            "business_date": k[2],
            "dow": k[3],
            "hour": k[4],
            "minute": k[5],
            "units": v,
            "signal_source": "css_foot_traffic",
        }
        for k, v in sorted(buckets.items())
    ]


def prefer_demand_signals(
    css_history: Sequence[dict],
    order_history: Sequence[dict],
    sales_history: Sequence[dict],
) -> List[dict]:
    """Prefer CSS foot traffic, then order timestamps, then sales day-grain history.

    Preference is per (store_id, role_code, dow, hour[, minute]) slot: the highest
    priority source that has any rows for that slot contributes *all* of its
    per-day rows for the slot. Rows keep a signal_source label.
    """
    def _slot_key(r: dict) -> Tuple:
        return (
            r["store_id"],
            r["role_code"],
            int(r["dow"]),
            int(r["hour"]),
            int(r.get("minute", 0)),
        )

    by_source = [
        ("css_foot_traffic", list(css_history)),
        ("orders", list(order_history)),
        ("sales", list(sales_history)),
    ]
    claimed: Set[Tuple] = set()
    out: List[dict] = []
    for default_source, rows in by_source:
        # Group this source's rows by slot; emit only for unclaimed slots.
        slots_this_source: Dict[Tuple, List[dict]] = defaultdict(list)
        for row in rows:
            slots_this_source[_slot_key(row)].append(row)
        for key, group in sorted(slots_this_source.items()):
            if key in claimed:
                continue
            claimed.add(key)
            for row in group:
                out_row = dict(row)
                out_row.setdefault("signal_source", default_source)
                out.append(out_row)
    return out

def seasonal_rolling_forecast(
    history: Sequence[dict],
    target_slots: Sequence[dict],
    fallback_levels: bool = True,
) -> List[dict]:
    """Seasonal same-(dow, hour) rolling average with hierarchical fallback.

    History / target slot dicts use keys: store_id, role_code, dow, hour, and
    (history only) units. Grain of the forecast is store × role × dow × hour.

    Hierarchy when sparse (fallback_levels=True):
      store × role × slot  ->  role × slot  ->  global slot
    Methods: seasonal_rolling_avg | hierarchical_fallback.
    """
    by_store_role: Dict[Tuple[str, str, int, int], List[float]] = defaultdict(list)
    by_role: Dict[Tuple[str, int, int], List[float]] = defaultdict(list)
    by_slot: Dict[Tuple[int, int], List[float]] = defaultdict(list)
    source_by_store_role: Dict[Tuple[str, str, int, int], str] = {}

    for row in history:
        store_id = row["store_id"]
        role_code = row["role_code"]
        dow = int(row["dow"])
        hour = int(row["hour"])
        units = float(row["units"])
        by_store_role[(store_id, role_code, dow, hour)].append(units)
        by_role[(role_code, dow, hour)].append(units)
        by_slot[(dow, hour)].append(units)
        source_by_store_role.setdefault(
            (store_id, role_code, dow, hour), row.get("signal_source", "sales")
        )

    store_role_avg = {k: _avg(v) for k, v in by_store_role.items()}
    role_avg = {k: _avg(v) for k, v in by_role.items()}
    slot_avg = {k: _avg(v) for k, v in by_slot.items()}

    out: List[dict] = []
    # Stable iteration order for determinism even if caller passes an unordered view.
    ordered_targets = sorted(
        enumerate(target_slots),
        key=lambda iv: (
            iv[1]["store_id"],
            iv[1]["role_code"],
            int(iv[1]["dow"]),
            int(iv[1]["hour"]),
            iv[0],
        ),
    )
    for _, slot in ordered_targets:
        store_id = slot["store_id"]
        role_code = slot["role_code"]
        dow = int(slot["dow"])
        hour = int(slot["hour"])
        primary = store_role_avg.get((store_id, role_code, dow, hour))
        if primary is not None:
            units = primary
            method = "seasonal_rolling_avg"
            signal = source_by_store_role.get((store_id, role_code, dow, hour), "sales")
        elif fallback_levels:
            fb = role_avg.get((role_code, dow, hour))
            if fb is None:
                fb = slot_avg.get((dow, hour))
            units = 0.0 if fb is None else fb
            method = "hierarchical_fallback"
            signal = "fallback"
        else:
            units = 0.0
            method = "hierarchical_fallback"
            signal = "fallback"
        out.append(
            {
                "store_id": store_id,
                "role_code": role_code,
                "dow": dow,
                "hour": hour,
                "forecast_driver_units": float(units),
                "forecast_method": method,
                "signal_source": signal,
            }
        )
    # Return in the same relative order as sorted targets (deterministic).
    return out


def compute_forecast_mape_bias(
    forecasts: Sequence[dict],
    actuals: Sequence[dict],
) -> dict:
    """Compute MAPE and bias when actuals exist for forecast slots.

    Forecast / actual dicts join on (store_id, role_code, dow, hour) or
    (store_id, role_code, business_date, interval_start) when present.
    Rows without a matching actual are ignored (NULL actual ≠ zero).
    Returns forecast_mape, forecast_bias, n_pairs (None metrics when n_pairs=0).
    """
    def _key(r: dict) -> Tuple:
        if "interval_start" in r or "interval_start_ts" in r:
            start = r.get("interval_start", r.get("interval_start_ts"))
            return (
                r["store_id"],
                r["role_code"],
                str(r.get("business_date", "")),
                str(start),
            )
        return (r["store_id"], r["role_code"], int(r["dow"]), int(r["hour"]))

    actual_by_key = {_key(a): float(a["actual_units"]) for a in actuals if a.get("actual_units") is not None}
    errors = []
    apes = []
    for f in forecasts:
        key = _key(f)
        if key not in actual_by_key:
            continue
        actual = actual_by_key[key]
        pred = float(f["forecast_driver_units"])
        errors.append(pred - actual)
        if actual != 0:
            apes.append(abs(pred - actual) / abs(actual))
    n = len(errors)
    if n == 0:
        return {"forecast_mape": None, "forecast_bias": None, "n_pairs": 0}
    return {
        "forecast_mape": (sum(apes) / len(apes)) if apes else None,
        "forecast_bias": sum(errors) / n,
        "n_pairs": n,
    }


# ---------------------------------------------------------------------------
# Labor standard
# ---------------------------------------------------------------------------


def apply_labor_standard(
    driver_units: float,
    hours_per_unit: float,
    minimum_headcount: int,
    interval_minutes: int,
) -> Tuple[float, float]:
    """Translate driver units through a labor standard into hours + headcount.

    Mirrors gold_workforce_labor_requirement:
      required_hours = max(units * hours_per_unit,
                           minimum_headcount * interval_hours)
      required_headcount = max(units * hours_per_unit / interval_hours,
                               minimum_headcount)
    """
    if interval_minutes <= 0:
        raise ValueError("interval_minutes must be positive")
    interval_hours = interval_minutes / 60.0
    raw_hours = float(driver_units) * float(hours_per_unit)
    floor_hours = float(minimum_headcount) * interval_hours
    required_hours = max(raw_hours, floor_hours)
    required_headcount = max(raw_hours / interval_hours, float(minimum_headcount))
    return required_hours, required_headcount


# ---------------------------------------------------------------------------
# Schedule helpers
# ---------------------------------------------------------------------------


def _hours(start: datetime, end: datetime) -> float:
    return (_ensure_aware(end) - _ensure_aware(start)).total_seconds() / 3600.0


def _overlaps(a_start: datetime, a_end: datetime, b_start: datetime, b_end: datetime) -> bool:
    a_start, a_end = _ensure_aware(a_start), _ensure_aware(a_end)
    b_start, b_end = _ensure_aware(b_start), _ensure_aware(b_end)
    return a_start < b_end and b_start < a_end


def _utc_date(ts: datetime):
    return _ensure_aware(ts).date()


def _week_start_monday(ts: datetime):
    d = _utc_date(ts)
    return d - timedelta(days=d.weekday())  # Monday


def _skill_eligible(
    emp: Employee,
    role_code: str,
    skills_required_by_role: Dict[str, Set[str]],
) -> bool:
    if emp.role_code == role_code or role_code in emp.skills:
        return True
    required = skills_required_by_role.get(role_code)
    if required is None:
        return False
    return bool(emp.skills.intersection(required))


def _availability_ok(
    emp_id: str,
    start: datetime,
    end: datetime,
    windows_by_emp: Dict[str, List[AvailabilityWindow]],
) -> bool:
    start, end = _ensure_aware(start), _ensure_aware(end)
    windows = windows_by_emp.get(emp_id, [])
    day = _utc_date(start)
    day_windows = [w for w in windows if _utc_date(w.start) == day or _overlaps(w.start, w.end, start, end)]
    # DDL: hard constraint only when availability rows exist for the date.
    if not day_windows:
        return True
    for w in day_windows:
        if not w.is_available and _overlaps(w.start, w.end, start, end):
            return False
    for w in day_windows:
        if w.is_available and _ensure_aware(w.start) <= start and end <= _ensure_aware(w.end):
            return True
    return False


def _rest_ok(
    emp: Employee,
    start: datetime,
    end: datetime,
    shifts: Sequence[Tuple[datetime, datetime]],
) -> bool:
    start, end = _ensure_aware(start), _ensure_aware(end)
    min_rest = timedelta(hours=float(emp.min_rest_hours))
    for s, e in shifts:
        s, e = _ensure_aware(s), _ensure_aware(e)
        if _overlaps(start, end, s, e):
            return False
        # Gap between end of earlier and start of later.
        if e <= start:
            if start - e < min_rest:
                return False
        elif end <= s:
            if s - end < min_rest:
                return False
    return True


def _hours_on_day(shifts: Sequence[Tuple[datetime, datetime]], day) -> float:
    total = 0.0
    for s, e in shifts:
        if _utc_date(s) == day:
            total += _hours(s, e)
    return total


def _hours_in_week(shifts: Sequence[Tuple[datetime, datetime]], week_start) -> float:
    total = 0.0
    week_end = week_start + timedelta(days=7)
    for s, e in shifts:
        d = _utc_date(s)
        if week_start <= d < week_end:
            total += _hours(s, e)
    return total


def _choose_shift_end(
    demand: DemandInterval,
    templates_hours: Sequence[float],
) -> datetime:
    demand_hours = _hours(demand.start, demand.end)
    templates = sorted(float(t) for t in templates_hours)
    chosen = None
    for t in templates:
        if t + 1e-9 >= demand_hours:
            chosen = t
            break
    if chosen is None:
        chosen = demand_hours if demand_hours > 0 else (templates[0] if templates else 4.0)
    return _ensure_aware(demand.start) + timedelta(hours=chosen)


def _severity(shortfall: float, required: float) -> str:
    if required <= 0:
        return "low"
    ratio = shortfall / required
    if ratio >= 0.75:
        return "critical"
    if ratio >= 0.5:
        return "high"
    if ratio >= 0.25:
        return "medium"
    return "low"


def _fairness_score(assigned_hours: Dict[str, float]) -> float:
    vals = list(assigned_hours.values())
    if len(vals) < 2:
        return 1.0
    mean = sum(vals) / len(vals)
    if mean <= 0:
        return 1.0
    var = sum((v - mean) ** 2 for v in vals) / len(vals)
    cv = (var ** 0.5) / mean
    return max(0.0, 1.0 - cv)


def greedy_schedule(
    employees: Sequence[Employee],
    availability: Sequence[AvailabilityWindow],
    skills_required_by_role: Dict[str, Set[str]],
    demand: Sequence[DemandInterval],
    existing_shifts: Sequence[ExistingShift],
    shift_templates_hours: Sequence[float] = (4, 8),
) -> Tuple[List[Recommendation], List[CoverageException], RunMetrics]:
    """Deterministic greedy scheduler with hard constraint enforcement.

    Sort order: employees by employee_id; demand by start/store/role/zone.
    Among feasible candidates: lower hourly_cost, then fewer assigned hours so
    far, then employee_id. Unfilled demand emits CoverageException rows.
    """
    employees_sorted = sorted(employees, key=lambda e: e.employee_id)
    demand_sorted = sorted(
        demand,
        key=lambda d: (_ensure_aware(d.start), d.store_id, d.role_code, d.zone, _ensure_aware(d.end)),
    )
    windows_by_emp: Dict[str, List[AvailabilityWindow]] = defaultdict(list)
    for w in availability:
        windows_by_emp[w.employee_id].append(
            AvailabilityWindow(w.employee_id, _ensure_aware(w.start), _ensure_aware(w.end), w.is_available)
        )

    # Working shift ledger per employee (existing + newly assigned).
    shifts_by_emp: Dict[str, List[Tuple[datetime, datetime]]] = defaultdict(list)
    for sh in existing_shifts:
        shifts_by_emp[sh.employee_id].append((_ensure_aware(sh.start), _ensure_aware(sh.end)))

    assigned_hours: Dict[str, float] = defaultdict(float)
    for emp in employees_sorted:
        for s, e in shifts_by_emp[emp.employee_id]:
            assigned_hours[emp.employee_id] += _hours(s, e)

    recommendations: List[Recommendation] = []
    exceptions: List[CoverageException] = []
    required_hours_total = 0.0
    unfilled_hours = 0.0

    for dem in demand_sorted:
        required_hours_total += float(dem.required_hours)
        need = int(ceil(float(dem.required_headcount)))
        if need <= 0 and float(dem.required_hours) <= 0:
            continue
        if need <= 0:
            need = 1
        filled = 0
        shift_start = _ensure_aware(dem.start)
        shift_end = _choose_shift_end(dem, shift_templates_hours)
        # Cover at least the demand interval.
        if shift_end < _ensure_aware(dem.end):
            shift_end = _ensure_aware(dem.end)
        shift_hours = _hours(shift_start, shift_end)

        for _slot in range(need):
            candidates = []
            for emp in employees_sorted:
                if emp.store_id != dem.store_id:
                    continue
                if not _skill_eligible(emp, dem.role_code, skills_required_by_role):
                    continue
                if not _availability_ok(emp.employee_id, shift_start, shift_end, windows_by_emp):
                    continue
                existing = list(shifts_by_emp[emp.employee_id])
                if not _rest_ok(emp, shift_start, shift_end, existing):
                    continue
                day = _utc_date(shift_start)
                week = _week_start_monday(shift_start)
                day_h = _hours_on_day(existing, day) + shift_hours
                week_h = _hours_in_week(existing, week) + shift_hours
                if day_h - 1e-9 > float(emp.max_daily_hours):
                    continue
                if week_h - 1e-9 > float(emp.max_weekly_hours):
                    continue
                candidates.append(emp)

            if not candidates:
                break

            candidates.sort(
                key=lambda e: (
                    float(e.hourly_cost),
                    float(assigned_hours[e.employee_id]),
                    e.employee_id,
                )
            )
            chosen = candidates[0]
            cost = shift_hours * float(chosen.hourly_cost)
            recommendations.append(
                Recommendation(
                    employee_id=chosen.employee_id,
                    store_id=dem.store_id,
                    zone=dem.zone,
                    role_code=dem.role_code,
                    start=shift_start,
                    end=shift_end,
                    assigned_hours=shift_hours,
                    estimated_labor_cost=cost,
                )
            )
            shifts_by_emp[chosen.employee_id].append((shift_start, shift_end))
            assigned_hours[chosen.employee_id] += shift_hours
            filled += 1

        shortfall = need - filled
        if shortfall > 0:
            unfilled_hours += float(dem.required_hours) * (shortfall / need)
            exceptions.append(
                CoverageException(
                    store_id=dem.store_id,
                    zone=dem.zone,
                    role_code=dem.role_code,
                    start=_ensure_aware(dem.start),
                    end=_ensure_aware(dem.end),
                    required_headcount=float(need),
                    scheduled_headcount=float(filled),
                    shortfall_headcount=float(shortfall),
                    severity=_severity(float(shortfall), float(need)),
                    exception_explanation=(
                        f"Unable to fill {shortfall} of {need} required headcount for "
                        f"{dem.role_code} at {dem.store_id}/{dem.zone}"
                    ),
                    suggested_action="call_in" if shortfall < need else "hire_temp",
                )
            )

    scheduled_hours_total = sum(r.assigned_hours for r in recommendations)
    labor_cost = sum(r.estimated_labor_cost for r in recommendations)
    if required_hours_total > 0:
        coverage_pct = scheduled_hours_total / required_hours_total
    else:
        coverage_pct = 1.0 if not exceptions else 0.0

    if exceptions and not recommendations:
        status = "infeasible"
    elif exceptions:
        status = "success_partial"
    else:
        status = "success"

    # Fairness over employees who received any hours (existing or new).
    fairness_hours = {k: v for k, v in assigned_hours.items() if v > 0}
    metrics = RunMetrics(
        recommended_shift_count=len(recommendations),
        exception_count=len(exceptions),
        scheduled_hours_total=scheduled_hours_total,
        required_hours_total=required_hours_total,
        coverage_pct=coverage_pct,
        unfilled_demand_hours=unfilled_hours,
        estimated_labor_cost=labor_cost,
        fairness_score=_fairness_score(fairness_hours),
        optimization_status=status,
        input_employee_count=len(employees_sorted),
        input_demand_intervals=len(demand_sorted),
    )
    return recommendations, exceptions, metrics


# ---------------------------------------------------------------------------
# OR-Tools exact / CP-SAT scheduler (same output contract as greedy)
# ---------------------------------------------------------------------------


# Understaffing penalty must dominate ordinary labor-cost terms.
_UNDERSTAFF_PENALTY = 1_000_000
_FAIRNESS_PENALTY = 10  # soft: discourage concentrating hours on few employees


def ortools_schedule(
    employees: Sequence[Employee],
    availability: Sequence[AvailabilityWindow],
    skills_required_by_role: Dict[str, Set[str]],
    demand: Sequence[DemandInterval],
    existing_shifts: Sequence[ExistingShift],
    shift_templates_hours: Sequence[float] = (4, 8),
    understaff_penalty: int = _UNDERSTAFF_PENALTY,
) -> Tuple[List[Recommendation], List[CoverageException], RunMetrics]:
    """CP-SAT schedule optimizer with the same outputs as greedy_schedule.

    Decision variables: assign employee i to demand interval j (binary).
    Objective: minimize labor cost + understaff_penalty * shortfall
               + fairness_penalty * max_assigned_hours (workload balance proxy).
    Hard constraints: store, skill, availability, rest, daily/weekly caps,
    no overlapping assignments. Deterministic via fixed search seed + sorted ids.
    Falls back to greedy_schedule when ortools is not installed.
    """
    if not _HAS_ORTOOLS:
        recs, exc, metrics = greedy_schedule(
            employees, availability, skills_required_by_role, demand,
            existing_shifts, shift_templates_hours,
        )
        # Annotate status path for diagnostics without changing contract fields.
        return recs, exc, metrics

    employees_sorted = sorted(employees, key=lambda e: e.employee_id)
    demand_sorted = sorted(
        demand,
        key=lambda d: (_ensure_aware(d.start), d.store_id, d.role_code, d.zone, _ensure_aware(d.end)),
    )
    if not demand_sorted:
        empty = RunMetrics(
            recommended_shift_count=0, exception_count=0, scheduled_hours_total=0.0,
            required_hours_total=0.0, coverage_pct=1.0, unfilled_demand_hours=0.0,
            estimated_labor_cost=0.0, fairness_score=1.0, optimization_status="success",
            input_employee_count=len(employees_sorted), input_demand_intervals=0,
        )
        return [], [], empty

    windows_by_emp: Dict[str, List[AvailabilityWindow]] = defaultdict(list)
    for w in availability:
        windows_by_emp[w.employee_id].append(
            AvailabilityWindow(w.employee_id, _ensure_aware(w.start), _ensure_aware(w.end), w.is_available)
        )
    existing_by_emp: Dict[str, List[Tuple[datetime, datetime]]] = defaultdict(list)
    for sh in existing_shifts:
        existing_by_emp[sh.employee_id].append((_ensure_aware(sh.start), _ensure_aware(sh.end)))

    # Precompute shift window + hours per demand (same template rule as greedy).
    dem_meta = []
    for dem in demand_sorted:
        start = _ensure_aware(dem.start)
        end = _choose_shift_end(dem, shift_templates_hours)
        if end < _ensure_aware(dem.end):
            end = _ensure_aware(dem.end)
        need = int(ceil(float(dem.required_headcount)))
        if need <= 0 and float(dem.required_hours) <= 0:
            need = 0
        elif need <= 0:
            need = 1
        dem_meta.append((dem, start, end, _hours(start, end), need))

    model = _cp_model.CpModel()
    # x[e_idx, d_idx] = assign employee e to demand d
    x = {}
    for ei, emp in enumerate(employees_sorted):
        for di, (dem, start, end, shift_h, need) in enumerate(dem_meta):
            if need <= 0:
                continue
            feasible = True
            if emp.store_id != dem.store_id:
                feasible = False
            elif not _skill_eligible(emp, dem.role_code, skills_required_by_role):
                feasible = False
            elif not _availability_ok(emp.employee_id, start, end, windows_by_emp):
                feasible = False
            elif not _rest_ok(emp, start, end, existing_by_emp.get(emp.employee_id, [])):
                feasible = False
            else:
                day = _utc_date(start)
                week = _week_start_monday(start)
                existing = existing_by_emp.get(emp.employee_id, [])
                if _hours_on_day(existing, day) + shift_h - 1e-9 > float(emp.max_daily_hours):
                    feasible = False
                if _hours_in_week(existing, week) + shift_h - 1e-9 > float(emp.max_weekly_hours):
                    feasible = False
            if feasible:
                x[(ei, di)] = model.NewBoolVar(f"x_{emp.employee_id}_{di}")

    # Coverage / shortfall per demand
    shortfall_vars = []
    for di, (dem, start, end, shift_h, need) in enumerate(dem_meta):
        if need <= 0:
            continue
        assigned = [x[(ei, di)] for ei in range(len(employees_sorted)) if (ei, di) in x]
        # shortfall >= need - sum(assigned); shortfall >= 0
        sf = model.NewIntVar(0, need, f"sf_{di}")
        model.Add(sum(assigned) + sf == need)
        shortfall_vars.append((sf, need, dem, start, end))

    # No overlapping assignments for the same employee across demand intervals.
    for ei, emp in enumerate(employees_sorted):
        for di1, (d1, s1, e1, h1, n1) in enumerate(dem_meta):
            if n1 <= 0 or (ei, di1) not in x:
                continue
            for di2, (d2, s2, e2, h2, n2) in enumerate(dem_meta):
                if di2 <= di1 or n2 <= 0 or (ei, di2) not in x:
                    continue
                if _overlaps(s1, e1, s2, e2) or not _rest_ok(emp, s2, e2, [(s1, e1)]):
                    model.AddBoolOr([x[(ei, di1)].Not(), x[(ei, di2)].Not()])

    # Daily / weekly caps across newly assigned shifts (+ existing already filtered).
    for ei, emp in enumerate(employees_sorted):
        # Scale hours * 100 to keep ints.
        day_loads: Dict[object, list] = defaultdict(list)
        week_loads: Dict[object, list] = defaultdict(list)
        for di, (dem, start, end, shift_h, need) in enumerate(dem_meta):
            if need <= 0 or (ei, di) not in x:
                continue
            cents = int(round(shift_h * 100))
            day_loads[_utc_date(start)].append((x[(ei, di)], cents))
            week_loads[_week_start_monday(start)].append((x[(ei, di)], cents))
        for day, terms in day_loads.items():
            existing_cents = int(round(_hours_on_day(existing_by_emp.get(emp.employee_id, []), day) * 100))
            model.Add(
                sum(var * cents for var, cents in terms) + existing_cents
                <= int(round(float(emp.max_daily_hours) * 100))
            )
        for week, terms in week_loads.items():
            existing_cents = int(round(_hours_in_week(existing_by_emp.get(emp.employee_id, []), week) * 100))
            model.Add(
                sum(var * cents for var, cents in terms) + existing_cents
                <= int(round(float(emp.max_weekly_hours) * 100))
            )

    # Objective: cost + understaff + fairness (max assigned hours among employees).
    cost_terms = []
    assigned_hours_expr = []
    for ei, emp in enumerate(employees_sorted):
        emp_hours_terms = []
        for di, (dem, start, end, shift_h, need) in enumerate(dem_meta):
            if need <= 0 or (ei, di) not in x:
                continue
            cents = int(round(shift_h * float(emp.hourly_cost) * 100))
            cost_terms.append(x[(ei, di)] * cents)
            emp_hours_terms.append(x[(ei, di)] * int(round(shift_h * 100)))
        if emp_hours_terms:
            eh = model.NewIntVar(0, int(round(float(emp.max_weekly_hours) * 100)), f"eh_{ei}")
            model.Add(eh == sum(emp_hours_terms))
            assigned_hours_expr.append(eh)

    understaff_cost = []
    for sf, need, dem, start, end in shortfall_vars:
        understaff_cost.append(sf * int(understaff_penalty))

    max_hours = model.NewIntVar(0, 100000, "max_hours")
    if assigned_hours_expr:
        model.AddMaxEquality(max_hours, assigned_hours_expr)
    else:
        model.Add(max_hours == 0)

    model.Minimize(
        sum(cost_terms) + sum(understaff_cost) + _FAIRNESS_PENALTY * max_hours
    )

    solver = _cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = 10.0
    solver.parameters.random_seed = 42
    solver.parameters.num_search_workers = 1
    status = solver.Solve(model)

    recommendations: List[Recommendation] = []
    exceptions: List[CoverageException] = []
    assigned_hours: Dict[str, float] = defaultdict(float)
    for sh in existing_shifts:
        assigned_hours[sh.employee_id] += _hours(sh.start, sh.end)

    if status in (_cp_model.OPTIMAL, _cp_model.FEASIBLE):
        for (ei, di), var in sorted(x.items(), key=lambda kv: (kv[0][1], kv[0][0])):
            if solver.Value(var) != 1:
                continue
            emp = employees_sorted[ei]
            dem, start, end, shift_h, need = dem_meta[di]
            cost = shift_h * float(emp.hourly_cost)
            recommendations.append(
                Recommendation(
                    employee_id=emp.employee_id,
                    store_id=dem.store_id,
                    zone=dem.zone,
                    role_code=dem.role_code,
                    start=start,
                    end=end,
                    assigned_hours=shift_h,
                    estimated_labor_cost=cost,
                )
            )
            assigned_hours[emp.employee_id] += shift_h
        for sf, need, dem, start, end in shortfall_vars:
            shortfall = int(solver.Value(sf))
            filled = need - shortfall
            if shortfall > 0:
                exceptions.append(
                    CoverageException(
                        store_id=dem.store_id,
                        zone=dem.zone,
                        role_code=dem.role_code,
                        start=start,
                        end=end,
                        required_headcount=float(need),
                        scheduled_headcount=float(filled),
                        shortfall_headcount=float(shortfall),
                        severity=_severity(float(shortfall), float(need)),
                        exception_explanation=(
                            f"Unable to fill {shortfall} of {need} required headcount for "
                            f"{dem.role_code} at {dem.store_id}/{dem.zone}"
                        ),
                        suggested_action="call_in" if shortfall < need else "hire_temp",
                    )
                )
    else:
        # Model infeasible or search failed — emit full shortfall exceptions.
        for dem, start, end, shift_h, need in dem_meta:
            if need <= 0:
                continue
            exceptions.append(
                CoverageException(
                    store_id=dem.store_id,
                    zone=dem.zone,
                    role_code=dem.role_code,
                    start=start,
                    end=end,
                    required_headcount=float(need),
                    scheduled_headcount=0.0,
                    shortfall_headcount=float(need),
                    severity=_severity(float(need), float(need)),
                    exception_explanation=(
                        f"OR-Tools status={solver.StatusName(status)}; unmet demand for "
                        f"{dem.role_code} at {dem.store_id}/{dem.zone}"
                    ),
                    suggested_action="hire_temp",
                )
            )

    required_hours_total = sum(float(d.required_hours) for d, *_ in dem_meta)
    scheduled_hours_total = sum(r.assigned_hours for r in recommendations)
    unfilled_hours = 0.0
    for e in exceptions:
        for dem, start, end, shift_h, need in dem_meta:
            if (dem.store_id == e.store_id and dem.role_code == e.role_code
                    and dem.zone == e.zone and start == e.start and need > 0):
                unfilled_hours += float(dem.required_hours) * (e.shortfall_headcount / need)
                break

    labor_cost = sum(r.estimated_labor_cost for r in recommendations)
    coverage_pct = (
        scheduled_hours_total / required_hours_total if required_hours_total > 0
        else (1.0 if not exceptions else 0.0)
    )
    if exceptions and not recommendations:
        opt_status = "infeasible"
    elif exceptions:
        opt_status = "success_partial"
    else:
        opt_status = "success"

    fairness_hours = {k: v for k, v in assigned_hours.items() if v > 0}
    metrics = RunMetrics(
        recommended_shift_count=len(recommendations),
        exception_count=len(exceptions),
        scheduled_hours_total=scheduled_hours_total,
        required_hours_total=required_hours_total,
        coverage_pct=coverage_pct,
        unfilled_demand_hours=unfilled_hours,
        estimated_labor_cost=labor_cost,
        fairness_score=_fairness_score(fairness_hours),
        optimization_status=opt_status,
        input_employee_count=len(employees_sorted),
        input_demand_intervals=len(demand_sorted),
    )
    # Stable recommendation order for determinism.
    recommendations.sort(key=lambda r: (r.start, r.store_id, r.role_code, r.zone, r.employee_id))
    exceptions.sort(key=lambda e: (e.start, e.store_id, e.role_code, e.zone))
    return recommendations, exceptions, metrics


def optimize_schedule(
    employees: Sequence[Employee],
    availability: Sequence[AvailabilityWindow],
    skills_required_by_role: Dict[str, Set[str]],
    demand: Sequence[DemandInterval],
    existing_shifts: Sequence[ExistingShift],
    shift_templates_hours: Sequence[float] = (4, 8),
    method: str = "ortools",
) -> Tuple[List[Recommendation], List[CoverageException], RunMetrics]:
    """Dispatch to OR-Tools or greedy behind the same output contract.

    method: 'ortools' (default; falls back to greedy if ortools missing) |
            'greedy_heuristic'
    """
    if method == "greedy_heuristic":
        return greedy_schedule(
            employees, availability, skills_required_by_role, demand,
            existing_shifts, shift_templates_hours,
        )
    if method == "ortools":
        return ortools_schedule(
            employees, availability, skills_required_by_role, demand,
            existing_shifts, shift_templates_hours,
        )
    raise ValueError(f"unknown schedule method: {method}")


# ---------------------------------------------------------------------------
# Idempotent merge
# ---------------------------------------------------------------------------


def merge_upsert_keys(rows: Iterable[dict], key_fn: Callable[[dict], object]) -> List[dict]:
    """Last-write-wins upsert by business key. Deterministic for a given row order."""
    merged: Dict[object, dict] = {}
    for row in rows:
        merged[key_fn(row)] = row
    return list(merged.values())
