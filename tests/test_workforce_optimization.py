"""Unit tests for the Workforce Optimization pure-Python reference.

No Spark / Databricks connection required. Covers forecast grain, labor
standards, greedy schedule constraints, determinism, idempotency, and
DQ-style assertions on recommendation outputs.
"""

from datetime import datetime, timedelta, timezone

import pytest

from tests.support.workforce_optimization import (
    AvailabilityWindow,
    CoverageException,
    DemandInterval,
    Employee,
    ExistingShift,
    Recommendation,
    apply_labor_standard,
    build_interval_history_from_css,
    build_interval_history_from_orders,
    compute_forecast_mape_bias,
    greedy_schedule,
    has_ortools,
    merge_upsert_keys,
    optimize_schedule,
    ortools_schedule,
    prefer_demand_signals,
    seasonal_rolling_forecast,
)

UTC = timezone.utc


def _ts(y, m, d, hh, mm=0):
    return datetime(y, m, d, hh, mm, tzinfo=UTC)


# ---------- fixtures ----------

SKILLS = {
    "cashier": {"cashier"},
    "sales_associate": {"sales_associate"},
    "fulfillment": {"fulfillment"},
    "inventory": {"inventory"},
    "supervisor": {"supervisor", "cashier"},
}


def _emp(
    eid,
    store="ST-01",
    role="cashier",
    skills=None,
    cost=15.0,
    max_daily=8.0,
    max_weekly=40.0,
    min_rest=8.0,
):
    return Employee(
        employee_id=eid,
        store_id=store,
        role_code=role,
        skills=frozenset(skills if skills is not None else {role}),
        hourly_cost=cost,
        max_daily_hours=max_daily,
        max_weekly_hours=max_weekly,
        min_rest_hours=min_rest,
    )


def _avail(eid, start, end, ok=True):
    return AvailabilityWindow(employee_id=eid, start=start, end=end, is_available=ok)


def _demand(store, zone, role, start, end, headcount=1, hours=None):
    h = hours if hours is not None else (end - start).total_seconds() / 3600.0 * headcount
    return DemandInterval(
        store_id=store,
        zone=zone,
        role_code=role,
        start=start,
        end=end,
        required_headcount=headcount,
        required_hours=h,
    )


# ---------- 1. Forecast grain ----------

def test_forecast_grain_store_role_dow_hour():
    history = [
        {"store_id": "ST-01", "role_code": "cashier", "dow": 1, "hour": 9, "units": 10},
        {"store_id": "ST-01", "role_code": "cashier", "dow": 1, "hour": 9, "units": 14},
        {"store_id": "ST-01", "role_code": "cashier", "dow": 1, "hour": 10, "units": 20},
        {"store_id": "ST-02", "role_code": "cashier", "dow": 1, "hour": 9, "units": 8},
    ]
    targets = [
        {"store_id": "ST-01", "role_code": "cashier", "dow": 1, "hour": 9},
        {"store_id": "ST-01", "role_code": "cashier", "dow": 1, "hour": 10},
        {"store_id": "ST-02", "role_code": "cashier", "dow": 1, "hour": 9},
    ]
    forecasts = seasonal_rolling_forecast(history, targets)
    assert len(forecasts) == 3
    by_key = {(f["store_id"], f["role_code"], f["dow"], f["hour"]): f for f in forecasts}
    assert set(by_key) == {
        ("ST-01", "cashier", 1, 9),
        ("ST-01", "cashier", 1, 10),
        ("ST-02", "cashier", 1, 9),
    }
    assert by_key[("ST-01", "cashier", 1, 9)]["forecast_driver_units"] == pytest.approx(12.0)
    assert by_key[("ST-01", "cashier", 1, 9)]["forecast_method"] == "seasonal_rolling_avg"
    assert by_key[("ST-01", "cashier", 1, 10)]["forecast_driver_units"] == pytest.approx(20.0)


# ---------- 2. Sparse history fallback ----------

def test_forecast_hierarchical_fallback_when_sparse():
    # Only ST-02 has history for (cashier, dow=2, hour=11); ST-01 must fall back.
    history = [
        {"store_id": "ST-02", "role_code": "cashier", "dow": 2, "hour": 11, "units": 30},
        {"store_id": "ST-02", "role_code": "cashier", "dow": 2, "hour": 11, "units": 40},
    ]
    targets = [
        {"store_id": "ST-01", "role_code": "cashier", "dow": 2, "hour": 11},
        {"store_id": "ST-02", "role_code": "cashier", "dow": 2, "hour": 11},
    ]
    forecasts = seasonal_rolling_forecast(history, targets, fallback_levels=True)
    by_store = {f["store_id"]: f for f in forecasts}
    assert by_store["ST-02"]["forecast_method"] == "seasonal_rolling_avg"
    assert by_store["ST-02"]["forecast_driver_units"] == pytest.approx(35.0)
    assert by_store["ST-01"]["forecast_method"] == "hierarchical_fallback"
    assert by_store["ST-01"]["forecast_driver_units"] == pytest.approx(35.0)


# ---------- 3. Labor-hours calculation ----------

def test_labor_standard_known_inputs():
    # 100 units * 0.02 h/unit = 2.0 hours over a 30-min interval => headcount 4
    hours, headcount = apply_labor_standard(
        driver_units=100.0,
        hours_per_unit=0.02,
        minimum_headcount=1,
        interval_minutes=30,
    )
    assert hours == pytest.approx(2.0)
    assert headcount == pytest.approx(4.0)

    # Minimum headcount floors both hours and headcount
    hours2, hc2 = apply_labor_standard(
        driver_units=1.0,
        hours_per_unit=0.01,
        minimum_headcount=2,
        interval_minutes=60,
    )
    assert hours2 == pytest.approx(2.0)  # max(0.01, 2*1.0)
    assert hc2 == pytest.approx(2.0)


# ---------- 4. Availability ----------

def test_availability_constraint_enforced():
    start = _ts(2026, 8, 10, 9)
    end = _ts(2026, 8, 10, 13)
    employees = [_emp("EMP-00001"), _emp("EMP-00002")]
    # Only EMP-00001 is available for the window.
    availability = [
        _avail("EMP-00001", start, end, True),
        _avail("EMP-00002", start, end, False),
    ]
    demand = [_demand("ST-01", "front_end", "cashier", start, end, headcount=1)]
    recs, exc, metrics = greedy_schedule(
        employees, availability, SKILLS, demand, existing_shifts=[], shift_templates_hours=(4,)
    )
    assert len(recs) == 1
    assert recs[0].employee_id == "EMP-00001"
    assert metrics.optimization_status == "success"


# ---------- 5. Skills / role eligibility ----------

def test_skills_role_eligibility_enforced():
    start = _ts(2026, 8, 10, 9)
    end = _ts(2026, 8, 10, 13)
    employees = [
        _emp("EMP-00001", role="cashier", skills={"cashier"}),
        _emp("EMP-00002", role="fulfillment", skills={"fulfillment"}),
    ]
    availability = [
        _avail("EMP-00001", start, end),
        _avail("EMP-00002", start, end),
    ]
    demand = [_demand("ST-01", "backroom", "fulfillment", start, end, headcount=1)]
    recs, _, _ = greedy_schedule(
        employees, availability, SKILLS, demand, existing_shifts=[], shift_templates_hours=(4,)
    )
    assert len(recs) == 1
    assert recs[0].employee_id == "EMP-00002"
    assert recs[0].role_code == "fulfillment"


# ---------- 6. Daily / weekly max hours ----------

def test_daily_and_weekly_max_hours_enforced():
    start = _ts(2026, 8, 10, 8)  # Monday
    employees = [
        _emp("EMP-00001", max_daily=4.0, max_weekly=40.0, cost=10.0),
        _emp("EMP-00002", max_daily=8.0, max_weekly=8.0, cost=10.0),
    ]
    # Day 1: 4h demand — EMP-00001 can take it (hits daily max); EMP-00002 also can.
    d1_start, d1_end = start, start + timedelta(hours=4)
    # Day 1 afternoon: another 4h — EMP-00001 blocked by daily max.
    d2_start, d2_end = start + timedelta(hours=4), start + timedelta(hours=8)
    # Later in week: EMP-00002 already at weekly max after first assignment if chosen twice...
    availability = [
        _avail("EMP-00001", d1_start, d2_end),
        _avail("EMP-00002", d1_start, d2_end),
    ]
    demand = [
        _demand("ST-01", "front_end", "cashier", d1_start, d1_end, headcount=1),
        _demand("ST-01", "front_end", "cashier", d2_start, d2_end, headcount=1),
    ]
    recs, exc, _ = greedy_schedule(
        employees, availability, SKILLS, demand, existing_shifts=[], shift_templates_hours=(4,)
    )
    by_emp = {}
    for r in recs:
        by_emp.setdefault(r.employee_id, 0.0)
        by_emp[r.employee_id] += r.assigned_hours
    assert by_emp.get("EMP-00001", 0.0) <= 4.0 + 1e-9
    # EMP-00002 weekly cap 8: at most two 4h shifts
    assert by_emp.get("EMP-00002", 0.0) <= 8.0 + 1e-9
    # Both demand slots should be coverable between the two employees
    assert len(recs) == 2
    assert not exc


def test_weekly_max_blocks_additional_shift():
    monday = _ts(2026, 8, 10, 9)
    emp = _emp("EMP-00001", max_daily=8.0, max_weekly=4.0)
    existing = [
        ExistingShift(
            employee_id="EMP-00001",
            store_id="ST-01",
            role_code="cashier",
            start=monday,
            end=monday + timedelta(hours=4),
        )
    ]
    # Same week, next day — weekly cap already exhausted.
    tue = monday + timedelta(days=1)
    availability = [_avail("EMP-00001", tue, tue + timedelta(hours=4))]
    demand = [_demand("ST-01", "front_end", "cashier", tue, tue + timedelta(hours=4), headcount=1)]
    recs, exc, metrics = greedy_schedule(
        [emp], availability, SKILLS, demand, existing_shifts=existing, shift_templates_hours=(4,)
    )
    assert recs == []
    assert len(exc) == 1
    assert metrics.optimization_status == "infeasible"


# ---------- 7. Minimum rest ----------

def test_minimum_rest_enforced():
    morning_end = _ts(2026, 8, 10, 12)
    emp = _emp("EMP-00001", min_rest=10.0, max_daily=12.0)
    existing = [
        ExistingShift(
            employee_id="EMP-00001",
            store_id="ST-01",
            role_code="cashier",
            start=_ts(2026, 8, 10, 8),
            end=morning_end,
        )
    ]
    # Only 2 hours rest — below min_rest_hours=10
    late_start = _ts(2026, 8, 10, 14)
    late_end = _ts(2026, 8, 10, 18)
    availability = [_avail("EMP-00001", late_start, late_end)]
    demand = [_demand("ST-01", "front_end", "cashier", late_start, late_end, headcount=1)]
    recs, exc, metrics = greedy_schedule(
        [emp], availability, SKILLS, demand, existing_shifts=existing, shift_templates_hours=(4,)
    )
    assert recs == []
    assert len(exc) == 1
    assert metrics.optimization_status == "infeasible"


# ---------- 8. Infeasible -> coverage exceptions ----------

def test_infeasible_scheduling_emits_coverage_exceptions():
    start = _ts(2026, 8, 10, 9)
    end = _ts(2026, 8, 10, 13)
    # Wrong store + wrong skill => no feasible worker
    employees = [_emp("EMP-00001", store="ST-99", role="inventory", skills={"inventory"})]
    availability = [_avail("EMP-00001", start, end)]
    demand = [_demand("ST-01", "front_end", "cashier", start, end, headcount=2, hours=8.0)]
    recs, exc, metrics = greedy_schedule(
        employees, availability, SKILLS, demand, existing_shifts=[], shift_templates_hours=(4,)
    )
    assert recs == []
    assert len(exc) == 1
    assert isinstance(exc[0], CoverageException)
    assert exc[0].shortfall_headcount == pytest.approx(2.0)
    assert exc[0].severity in {"low", "medium", "high", "critical"}
    assert metrics.optimization_status == "infeasible"


# ---------- 9. Determinism ----------

def test_determinism_same_input_same_schedule():
    start = _ts(2026, 8, 11, 10)
    end = _ts(2026, 8, 11, 14)
    employees = [
        _emp("EMP-00003", cost=18.0),
        _emp("EMP-00001", cost=12.0),
        _emp("EMP-00002", cost=12.0),
    ]
    availability = [_avail(e.employee_id, start, end) for e in employees]
    demand = [
        _demand("ST-01", "front_end", "cashier", start, end, headcount=2),
    ]
    a = greedy_schedule(employees, availability, SKILLS, demand, [], (4,))
    b = greedy_schedule(employees, availability, SKILLS, demand, [], (4,))
    assert a[0] == b[0]
    assert a[1] == b[1]
    assert a[2] == b[2]
    # Lower cost preferred; among equal cost, fewer hours then employee_id
    assert [r.employee_id for r in a[0]] == ["EMP-00001", "EMP-00002"]


# ---------- 10. Idempotent merge ----------

def test_idempotent_output_merge():
    rows = [
        {"recommendation_id": "R1", "employee_id": "EMP-00001", "v": 1},
        {"recommendation_id": "R2", "employee_id": "EMP-00002", "v": 1},
        {"recommendation_id": "R1", "employee_id": "EMP-00001", "v": 2},  # update
    ]
    merged = merge_upsert_keys(rows, key_fn=lambda r: r["recommendation_id"])
    by_id = {r["recommendation_id"]: r for r in merged}
    assert set(by_id) == {"R1", "R2"}
    assert by_id["R1"]["v"] == 2  # last write wins
    # Re-merge is idempotent
    again = merge_upsert_keys(merged + merged, key_fn=lambda r: r["recommendation_id"])
    assert {r["recommendation_id"]: r["v"] for r in again} == {"R1": 2, "R2": 1}


# ---------- 11. DQ-style assertions ----------

def test_dq_style_assertions_on_recommendations():
    start = _ts(2026, 8, 12, 9)
    end = _ts(2026, 8, 12, 17)
    employees = [_emp("EMP-00001", cost=15.0), _emp("EMP-00002", cost=16.0)]
    availability = [_avail(e.employee_id, start, end) for e in employees]
    demand = [_demand("ST-01", "storewide", "cashier", start, end, headcount=2)]
    recs, exc, metrics = greedy_schedule(
        employees, availability, SKILLS, demand, [], shift_templates_hours=(8,)
    )
    assert metrics.optimization_status == "success"
    assert not exc

    keys = []
    for r in recs:
        assert isinstance(r, Recommendation)
        assert r.end > r.start, "shift end must be after start"
        assert r.assigned_hours >= 0, "hours must be non-negative"
        assert r.estimated_labor_cost >= 0
        key = (r.employee_id, r.store_id, r.role_code, r.start, r.end)
        keys.append(key)
    assert len(keys) == len(set(keys)), "duplicate business keys in recommendations"


# ---------- 12. Prefer CSS / orders over sales ----------

def test_prefer_demand_signals_css_over_orders_over_sales():
    css = build_interval_history_from_css(
        [
            {
                "store_id": "ST-01",
                "interval_start_ts": _ts(2026, 8, 10, 9, 0),
                "footfall_count": 50,
                "aggregation_level": "site",
                "dow": 2,
            }
        ],
        role_code="sales_associate",
    )
    orders = build_interval_history_from_orders(
        [
            {
                "store_id": "ST-01",
                "event_timestamp": _ts(2026, 8, 10, 9, 5),
                "units": 12,
                "dow": 2,
            }
        ],
        role_code="cashier",
    )
    sales = [
        {"store_id": "ST-01", "role_code": "cashier", "dow": 2, "hour": 9, "units": 3, "signal_source": "sales"},
        {"store_id": "ST-01", "role_code": "sales_associate", "dow": 2, "hour": 9, "units": 3, "signal_source": "sales"},
    ]
    preferred = prefer_demand_signals(css, orders, sales)
    by_role = {r["role_code"]: r for r in preferred}
    assert by_role["sales_associate"]["signal_source"] == "css_foot_traffic"
    assert by_role["sales_associate"]["units"] == 50
    assert by_role["cashier"]["signal_source"] == "orders"
    assert by_role["cashier"]["units"] == 12


def test_order_interval_history_feeds_seasonal_forecast():
    history = build_interval_history_from_orders(
        [
            {"store_id": "ST-01", "event_timestamp": _ts(2026, 8, 3, 10, 0), "units": 10, "dow": 2},
            {"store_id": "ST-01", "event_timestamp": _ts(2026, 8, 10, 10, 15), "units": 14, "dow": 2},
        ],
        interval_minutes=30,
        role_code="cashier",
    )
    targets = [{"store_id": "ST-01", "role_code": "cashier", "dow": 2, "hour": 10}]
    forecasts = seasonal_rolling_forecast(history, targets)
    assert forecasts[0]["forecast_method"] == "seasonal_rolling_avg"
    assert forecasts[0]["forecast_driver_units"] == 12.0
    assert forecasts[0]["signal_source"] == "orders"


# ---------- 13. MAPE / bias when actuals exist ----------

def test_forecast_mape_bias_when_actuals_exist():
    forecasts = [
        {"store_id": "ST-01", "role_code": "cashier", "dow": 1, "hour": 9, "forecast_driver_units": 10},
        {"store_id": "ST-01", "role_code": "cashier", "dow": 1, "hour": 10, "forecast_driver_units": 20},
        {"store_id": "ST-01", "role_code": "cashier", "dow": 1, "hour": 11, "forecast_driver_units": 5},
    ]
    actuals = [
        {"store_id": "ST-01", "role_code": "cashier", "dow": 1, "hour": 9, "actual_units": 8},
        {"store_id": "ST-01", "role_code": "cashier", "dow": 1, "hour": 10, "actual_units": 20},
    ]
    metrics = compute_forecast_mape_bias(forecasts, actuals)
    assert metrics["n_pairs"] == 2
    assert metrics["forecast_bias"] == pytest.approx(1.0)
    assert metrics["forecast_mape"] == pytest.approx(0.125)


def test_forecast_mape_bias_none_without_actuals():
    forecasts = [{"store_id": "ST-01", "role_code": "cashier", "dow": 1, "hour": 9, "forecast_driver_units": 10}]
    metrics = compute_forecast_mape_bias(forecasts, [])
    assert metrics == {"forecast_mape": None, "forecast_bias": None, "n_pairs": 0}


# ---------- 14. OR-Tools behind same contracts ----------

def test_ortools_schedule_respects_availability_and_emits_exceptions():
    start = _ts(2026, 8, 12, 9)
    end = _ts(2026, 8, 12, 13)
    employees = [_emp("EMP-00001")]
    availability = [_avail("EMP-00001", start, end)]
    demand = [_demand("ST-01", "storewide", "cashier", start, end, headcount=2)]
    recs, exc, metrics = optimize_schedule(
        employees, availability, SKILLS, demand, [], shift_templates_hours=(4,), method="ortools"
    )
    assert len(recs) == 1
    assert len(exc) == 1
    assert metrics.optimization_status == "success_partial"
    assert recs[0].employee_id == "EMP-00001"
    assert exc[0].shortfall_headcount == 1


def test_ortools_deterministic_same_input():
    start = _ts(2026, 8, 12, 9)
    end = _ts(2026, 8, 12, 17)
    employees = [_emp("EMP-00002", cost=20.0), _emp("EMP-00001", cost=15.0)]
    availability = [_avail(e.employee_id, start, end) for e in employees]
    demand = [_demand("ST-01", "storewide", "cashier", start, end, headcount=1)]
    a = optimize_schedule(employees, availability, SKILLS, demand, [], (8,), method="ortools")
    b = optimize_schedule(employees, availability, SKILLS, demand, [], (8,), method="ortools")
    assert [(r.employee_id, r.start, r.end, r.assigned_hours) for r in a[0]] == [
        (r.employee_id, r.start, r.end, r.assigned_hours) for r in b[0]
    ]
    assert a[0][0].employee_id == "EMP-00001"


@pytest.mark.skipif(not has_ortools(), reason="ortools not installed")
def test_ortools_backend_is_cp_sat_when_installed():
    start = _ts(2026, 8, 12, 9)
    end = _ts(2026, 8, 12, 13)
    employees = [_emp("EMP-00001")]
    availability = [_avail("EMP-00001", start, end)]
    demand = [_demand("ST-01", "storewide", "cashier", start, end, headcount=1)]
    recs, exc, metrics = ortools_schedule(
        employees, availability, SKILLS, demand, [], shift_templates_hours=(4,)
    )
    assert metrics.optimization_status == "success"
    assert len(recs) == 1 and not exc
