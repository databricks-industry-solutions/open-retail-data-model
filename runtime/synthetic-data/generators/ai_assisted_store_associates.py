# ============================================================
# ORDM · Synthetic data · AI-Assisted Store Associates generator
# Version: 0.5
# Generated: 2026-08-11
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-08-11
# ============================================================
# Populates the Real-Time Data Access extension tables (associate_context_event,
# associate_fulfillment_status, associate_lookup_audit) and the Next Best Action
# tables: associate (projected from labor.employee), suggested_action,
# action_response_log and outcome_resolution, anchored to the UTC run date.
# Requires the product, store, inventory, labor and customer upstreams.
# ============================================================

import hashlib
import os
import sys
from datetime import datetime, timedelta, timezone
from decimal import Decimal as D

# PySpark imports guarded: pure-Python builders can run without Spark
try:
    from pyspark.sql import functions as F
except ImportError:
    F = None


def _dec(v):
    """Bind DECIMAL-typed values as Decimal, never Python float: Spark Connect (the
    serverless deploy runtime) rejects a float bound to a DECIMAL createDataFrame field
    (same rule the SDI generator follows; see test_generator_runtime_regressions). `str(v)`
    preserves the literal scale; None passes through for nullable columns."""
    return D(str(v)) if v is not None else None

try:
    from _common import RECORD_SOURCE, get_param, load_domain_config, _write
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import RECORD_SOURCE, get_param, load_domain_config, _write

ASSOCIATE_CONTEXT_EVENT_COLUMNS = [
    "associate_context_event_id", "event_domain", "event_type",
    "store_sk", "store_id", "product_sk", "product_id", "order_id", "promo_id", "equipment_id",
    "quantity_on_hand", "quantity_available", "quantity_reserved", "quantity_in_transit",
    "unit_price_amount", "currency_code", "status_code", "location_code", "event_payload_summary",
    "source_system", "event_timestamp", "ingest_timestamp", "processed_timestamp", "latency_seconds",
    "record_source", "load_timestamp",
]

ASSOCIATE_FULFILLMENT_STATUS_COLUMNS = [
    "associate_fulfillment_status_id", "order_id", "store_sk", "store_id",
    "fulfillment_type", "order_status", "pickup_readiness", "pickup_location_code",
    "exception_state", "last_event_timestamp", "source_system",
    "requires_customer_verification", "data_freshness_timestamp",
    "record_source", "load_timestamp",
]

ASSOCIATE_LOOKUP_AUDIT_COLUMNS = [
    "associate_lookup_audit_id", "request_id", "correlation_id",
    "request_timestamp", "generated_at",
    "associate_id", "associate_role", "channel", "store_id",
    "capability", "access_decision", "access_reason_code", "response_status",
    "latency_ms", "domains_accessed", "data_classification",
    "product_id_hash", "order_id_hash",
    "record_source", "load_timestamp",
]


# ============================================================
# Constants for associate, suggested_action, action_response_log, outcome_resolution
# ============================================================

# Associate table columns (excluding identity _sk)
ASSOCIATE_COLUMNS = [
    "associate_id", "store_sk", "store_id", "role", "skill_tags",
    "employment_type", "primary_department", "is_active", "hire_date",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]

# Suggested action table columns (excluding identity _sk)
SUGGESTED_ACTION_COLUMNS = [
    "suggested_action_id", "generated_timestamp", "associate_sk", "associate_id",
    "store_sk", "store_id", "store_zone_id", "profile_sk", "profile_id",
    "product_sk", "product_id", "action_type", "trigger_source",
    "base_score", "priority_score", "decay_type", "context_payload",
    "expiration_timestamp", "record_source", "load_timestamp",
]

# Action response log table columns (excluding identity _sk)
ACTION_RESPONSE_LOG_COLUMNS = [
    "action_response_log_id", "suggested_action_sk", "suggested_action_id",
    "associate_sk", "associate_id", "response_timestamp", "response_type",
    "reason_code", "record_source", "load_timestamp",
]

# Outcome resolution table columns (excluding identity _sk)
OUTCOME_RESOLUTION_COLUMNS = [
    "outcome_resolution_id", "suggested_action_sk", "suggested_action_id",
    "resolution_timestamp", "outcome_type", "outcome_value_amount",
    "currency_code", "units_affected", "record_source", "load_timestamp",
]

# Enums
ACTION_TYPES = ["customer_assist", "restock_shelf", "bopis_fulfill", "safety_loss_prevention",
                "maintenance_cleaning", "price_check", "queue_bust", "clienteling"]
TRIGGER_SOURCES = ["ble_beacon_dwell", "pos_inventory_decrement", "order_management_system",
                   "sensor_event", "digital_interaction", "schedule", "manual"]
DECAY_TYPES = ["linear", "exponential", "immediate_nullification", "none"]
RESPONSE_TYPES = ["accepted", "rejected", "deferred", "completed", "expired", "reassigned"]
TERMINAL_RESPONSE_TYPES = ["completed", "expired", "rejected"]
OUTCOME_TYPES = ["sale_closed", "item_restocked", "customer_assisted", "issue_resolved", "task_abandoned", "no_outcome"]
ASSOCIATE_ROLES = ["sales_associate", "cashier", "stock_associate", "team_lead"]
EMPLOYMENT_TYPES = ["full_time", "part_time", "seasonal", "contractor"]

# Role mapping: labor.employee.primary_role_code → associate.role
ROLE_MAP = {
    "cashier": "cashier",
    "sales_associate": "sales_associate",
    "fulfillment": "stock_associate",
    "inventory": "stock_associate",
    "supervisor": "team_lead",
}

# Store zone suffixes (the deterministic id pattern connected_store_signals uses)
ZONE_SUFFIXES = ["AISLE-01", "AISLE-02", "AISLE-03", "AISLE-04", "CHECKOUT", "BACKROOM", "FITTING", "AREA-GROCERY", "ENTRANCE", "PERIMETER"]

# Zone for action mapping
ZONE_FOR_ACTION = {
    "queue_bust": ["CHECKOUT"],
    "restock_shelf": ["AISLE-01", "AISLE-02", "AISLE-03", "AISLE-04"],
    "price_check": ["AISLE-01", "AISLE-02", "AISLE-03", "AISLE-04"],
    "bopis_fulfill": ["BACKROOM"],
    "customer_assist": ["AISLE-01", "AISLE-02", "AISLE-03", "AISLE-04", "FITTING", "AREA-GROCERY"],
    "clienteling": ["AISLE-01", "AISLE-02", "AISLE-03", "AISLE-04", "FITTING", "AREA-GROCERY"],
    "safety_loss_prevention": ["ENTRANCE", "PERIMETER"],
    "maintenance_cleaning": ZONE_SUFFIXES,  # any zone
}

# Base scores by action type
BASE_SCORES = {
    "safety_loss_prevention": 90,
    "bopis_fulfill": 75,
    "customer_assist": 60,
    "queue_bust": 60,
    "clienteling": 70,
    "restock_shelf": 40,
    "maintenance_cleaning": 20,
    "price_check": 50,
}

# Decay types by action type
DECAY_BY_TYPE = {
    "safety_loss_prevention": "none",
    "bopis_fulfill": "exponential",
    "customer_assist": "exponential",
    "queue_bust": "linear",
    "clienteling": "linear",
    "restock_shelf": "linear",
    "maintenance_cleaning": "linear",
    "price_check": "exponential",
}


def load_config():
    c = load_domain_config("ai_assisted_store_associates")
    vols = c.get("volumes", {}) or {}
    return {
        "seed": c.get("seed", 15015),
        "events": int(vols.get("events", 40)),
        "orders": int(vols.get("orders", 12)),
        "audits": int(vols.get("audits", 20)),
        "action_history_days": int(vols.get("action_history_days", 14)),
        "actions_per_store_day": int(vols.get("actions_per_store_day", 4)),
        "open_actions_per_associate_max": int(vols.get("open_actions_per_associate_max", 5)),
    }


def _sha(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _md5_hash(value: str, length: int = 12) -> str:
    """Deterministic hash truncated to specified length."""
    return hashlib.md5(value.encode("utf-8")).hexdigest()[:length]


def _fixed_now():
    # Deterministic "now" for synthetic fixtures (UTC).
    return datetime(2026, 8, 11, 15, 0, 0, tzinfo=timezone.utc)


def _py_hash(seed: int, salt: str, *keys) -> int:
    """Stable 64-bit hash of (keys, salt, seed). Python's built-in hash() is salted per
    process (PYTHONHASHSEED), so it would make every run different; sha256 is stable."""
    raw = "|".join([str(k) for k in keys] + [salt, str(seed)]).encode("utf-8")
    return int.from_bytes(hashlib.sha256(raw).digest()[:8], "big")


def _py_frac(seed: int, salt: str, *keys) -> float:
    """Pure Python deterministic fraction in [0, 1) for builders."""
    return (_py_hash(seed, salt, *keys) % 10000) / 10000.0


def _py_pick(arr: list, seed: int, salt: str, *keys):
    """Pure Python deterministic pick from array."""
    if not arr:
        return None
    return arr[_py_hash(seed, salt, *keys) % len(arr)]


def resolve_anchor(value: str = None) -> datetime:
    """Resolve anchor date: parse YYYY-MM-DD string or return today at 00:00 UTC.

    The anchor is UTC midnight of the run date, overridable via AASA_ANCHOR_DATE or
    --aasa_anchor_date (read through _common.get_param).
    """
    if value:
        # Parse YYYY-MM-DD
        d = datetime.strptime(value, "%Y-%m-%d").date()
        return datetime.combine(d, datetime.min.time(), tzinfo=timezone.utc)
    # Default: today at 00:00 UTC
    today = datetime.now(tz=timezone.utc).date()
    return datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)


def build_associate_rows(employees: list, skills: list, anchor: datetime | None = None) -> list:
    """Pure Python builder for associate rows from labor.employee and labor.employee_skill.

    Args:
        employees: list of dicts from labor.employee (is_current=TRUE)
        skills: list of dicts from labor.employee_skill (skill_code, employee_id, is_active)

    Returns:
        list of dicts ready for Spark DataFrame (excluding associate_sk identity column)
    """
    # audit timestamps follow the run-date anchor, like the action tables built from these rows
    now = (anchor or _fixed_now()).replace(tzinfo=None)
    rows = []

    # Build skills map: employee_id -> [skill_codes]
    skills_by_emp = {}
    for skill in skills:
        emp_id = skill.get("employee_id")
        if emp_id and skill.get("is_active", True):  # the Spark read already filters is_active
            skills_by_emp.setdefault(emp_id, []).append(skill.get("skill_code"))

    for emp in employees:
        emp_id = emp.get("employee_id")
        if not emp_id:
            continue

        # Map role
        role_code = emp.get("primary_role_code")
        role = ROLE_MAP.get(role_code)
        if role is None:
            print(f"[ordm] WARNING: unmapped labor role {role_code!r} for {emp_id}; using sales_associate")
            role = "sales_associate"

        # Collect skills
        emp_skills = skills_by_emp.get(emp_id, [])
        skill_tags = "|".join(sorted(emp_skills)) if emp_skills else None

        # Determine is_active
        is_active = emp.get("employment_status") == "active"

        rows.append({
            "associate_id": emp_id,
            "store_sk": emp.get("home_store_sk"),
            "store_id": emp.get("home_store_id"),
            "role": role,
            "skill_tags": skill_tags,
            "employment_type": emp.get("employment_type"),
            "primary_department": None,  # Not available in labor domain for MVP
            "is_active": is_active,
            "hire_date": emp.get("hire_date"),
            "effective_from_date": emp.get("hire_date"),
            "effective_to_date": None,  # MVP: all current versions
            "is_current": True,
            "created_timestamp": now,
            "source_updated_timestamp": now,
            "record_source": "synthetic",
            "load_timestamp": now,
        })

    return rows


def build_action_rows(associates: list, stores: list, products: list, profiles: list,
                      anchor: datetime, cfg: dict, seed: int, base_currency: str) -> tuple:
    """Pure Python builder for suggested_action, action_response_log, outcome_resolution rows.

    History slice (anchor-14d .. anchor-1d) with a full lifecycle ending in a terminal response.
    Open slice [anchor-12h, anchor) with no terminal response; expiration anchor+7..30d for decay
    'none', anchor+2..7d for decaying actions.

    Args:
        associates: list of dicts from associate table with associate_sk, associate_id
        stores: list of dicts from store table with store_sk, store_id
        products: list of dicts from product table with product_sk, product_id
        profiles: list of dicts from customer.profile with profile_sk, profile_id
        anchor: datetime, UTC midnight of the run date
        cfg: config dict with action_history_days, actions_per_store_day, open_actions_per_associate_max
        seed: random seed
        base_currency: currency code (e.g., "USD")

    Returns:
        tuple (actions_list, responses_list, outcomes_list) of dicts
    """
    # load_timestamp = the anchor: every business timestamp in these rows is before it
    now = anchor
    actions = []
    responses = []
    outcomes = []

    if not associates or not stores:
        return actions, responses, outcomes

    history_days = cfg.get("action_history_days", 14)
    actions_per_store_day = cfg.get("actions_per_store_day", 4)
    open_max_per_assoc = cfg.get("open_actions_per_associate_max", 5)

    action_counter = 0

    # HISTORY SLICE: anchor-14d .. anchor-1d (exclude anchor day itself)
    # sort every input by its durable key: the counter and index picks below must not depend on
    # the order a Delta scan happens to return rows in
    associates = sorted(associates, key=lambda r: r["associate_id"])
    stores = sorted(stores, key=lambda r: r["store_id"])
    products = sorted(products, key=lambda r: r["product_id"])
    profiles = sorted(profiles, key=lambda r: r["profile_id"])
    store_by_id = {st["store_id"]: st for st in stores}
    associates_by_store = {}
    # only rostered associates (is_active) receive actions; terminated or on-leave staff keep
    # their associate row but are never routed work
    active = [_a for _a in associates if _a.get("is_active", True)]
    for _a in active:
        associates_by_store.setdefault(_a.get("store_id"), []).append(_a)
    for day_offset in range(history_days, 0, -1):  # 14, 13, ..., 1 (NOT 0)
        gen_date = anchor - timedelta(days=day_offset)

        for store in stores:
            store_id = store["store_id"]
            store_sk = store["store_sk"]

            for action_idx in range(actions_per_store_day):
                action_counter += 1

                # Deterministic timestamp within store hours (08:00-21:00, no microseconds)
                frac_hour = _py_frac(seed, f"hhist_{action_counter}", day_offset, store_id)
                hour = int(frac_hour * 13) + 8  # [8, 20]
                minute = int(_py_frac(seed, f"mhist_{action_counter}", day_offset, store_id) * 60)
                gen_ts = gen_date.replace(hour=hour, minute=minute, second=0, microsecond=0)

                # Pick action type
                action_type = _py_pick(ACTION_TYPES, seed, f"athist_{action_counter}", store_id)

                # Route to an associate of the same store; 10% stay unrouted (broadcast, nobody
                # picked it up), as do actions in a store with no associates
                candidates = associates_by_store.get(store_id, [])
                unrouted_frac = _py_frac(seed, f"unroute_{action_counter}", store_id)
                if unrouted_frac < 0.10 or not candidates:
                    assoc_sk = None
                    assoc_id = None
                else:
                    assoc = _py_pick(candidates, seed, f"asochist_{action_counter}", store_id)
                    assoc_sk = assoc["associate_sk"]
                    assoc_id = assoc["associate_id"]

                # Optional profile/product
                profile_sk = None
                profile_id = None
                if _py_frac(seed, f"pfhist_{action_counter}", store_id) < 0.4 and profiles:
                    p = _py_pick(profiles, seed, f"profhist_{action_counter}", store_id)
                    profile_sk = p.get("profile_sk")
                    profile_id = p.get("profile_id")

                product_sk = None
                product_id = None
                if _py_frac(seed, f"pdhist_{action_counter}", store_id) < 0.6 and products:
                    p = _py_pick(products, seed, f"prodhist_{action_counter}", store_id)
                    product_sk = p.get("product_sk")
                    product_id = p.get("product_id")

                trigger_source = _py_pick(TRIGGER_SOURCES, seed, f"trghist_{action_counter}", store_id) if _py_frac(seed, f"trigfrac_{action_counter}", store_id) >= 0.7 else None

                base_score = BASE_SCORES.get(action_type, 50)
                decay_type = DECAY_BY_TYPE.get(action_type, "linear")

                priority_mult = 0.7 + _py_frac(seed, f"multhist_{action_counter}", store_id, action_type) * 0.6
                priority_score = base_score * priority_mult

                zone_suffix = _py_pick(ZONE_FOR_ACTION.get(action_type, ZONE_SUFFIXES), seed, f"zhist_{action_counter}", store_id)
                store_zone_id = f"SZ-{store_id}-{zone_suffix}"

                # HISTORY EXPIRATION: generated + 5min .. 24h (whole minutes, no microseconds)
                exp_min_frac = _py_frac(seed, f"exphist_{action_counter}", store_id)
                exp_minutes = 5 + int(exp_min_frac * (24 * 60 - 5))  # [5 min, 24 h]
                # the whole history lifecycle (responses, outcomes) ends before the anchor, so a
                # history row never carries a timestamp later than the run that generated it
                exp_minutes = max(5, min(exp_minutes, int((anchor - gen_ts).total_seconds() / 60) - 180))
                expiration_ts = gen_ts + timedelta(minutes=exp_minutes)

                action_id = f"action-{_md5_hash(store_id + (assoc_id or 'unrouted') + str(gen_ts) + action_type + str(action_counter))}"

                action_row = {
                    "suggested_action_id": action_id,
                    "generated_timestamp": gen_ts.replace(tzinfo=None),
                    "associate_sk": assoc_sk,
                    "associate_id": assoc_id,
                    "store_sk": store_sk,
                    "store_id": store_id,
                    "store_zone_id": store_zone_id,
                    "profile_sk": profile_sk,
                    "profile_id": profile_id,
                    "product_sk": product_sk,
                    "product_id": product_id,
                    "action_type": action_type,
                    "trigger_source": trigger_source,
                    "base_score": base_score,
                    "priority_score": round(float(priority_score), 4),
                    "decay_type": decay_type,
                    "expiration_timestamp": expiration_ts.replace(tzinfo=None),
                    "context_payload": None,
                    "record_source": "synthetic",
                    "load_timestamp": now.replace(tzinfo=None),
                }
                actions.append(action_row)

                # HISTORY LIFECYCLE. First response: accepted 60%, rejected 25%, deferred 10%,
                # expired 5%. Accepted actions are completed 75% of the time and otherwise expire
                # (abandoned); deferred actions expire. Every response is after generation and the
                # terminal response (completed / rejected / expired) is the last one.
                def _resp(ts, rtype, reason=None):
                    responses.append({
                        "action_response_log_id": f"response-{_md5_hash(action_id + str(ts) + rtype)}",
                        "suggested_action_sk": None,
                        "suggested_action_id": action_id,
                        "associate_sk": assoc_sk,
                        "associate_id": assoc_id,
                        "response_timestamp": ts.replace(tzinfo=None),
                        "response_type": rtype,
                        "reason_code": reason,
                        "record_source": "synthetic",
                        "load_timestamp": now.replace(tzinfo=None),
                    })

                init_frac = _py_frac(seed, f"initresp_{action_counter}", store_id)
                first = ("accepted" if init_frac < 0.60 else "rejected" if init_frac < 0.85
                         else "deferred" if init_frac < 0.95 else "expired")
                if assoc_sk is None:
                    first = "expired"  # an unrouted action is never accepted or completed
                # first-response latency is skewed short (median about 15 min, capped at an hour or
                # the expiry window): floor associates act on most prompts within minutes
                resp_minutes = 1 + int(_py_frac(seed, f"respmin_{action_counter}", store_id) ** 2 * max(min(exp_minutes - 2, 60), 1))
                resp_ts = gen_ts + timedelta(minutes=resp_minutes)
                reason = (_py_pick(["too_busy", "wrong_zone", "not_qualified", "customer_left", "out_of_stock"],
                                   seed, f"reason_{action_counter}", store_id)
                          if first in ("rejected", "deferred") else None)
                if first == "expired":
                    _resp(max(expiration_ts, gen_ts + timedelta(minutes=1)), "expired")
                else:
                    _resp(resp_ts, first, reason)

                completed_ts = None
                if first == "accepted":
                    if _py_frac(seed, f"maketerm_{action_counter}", store_id) < 0.75:
                        completed_ts = resp_ts + timedelta(minutes=1 + int(_py_frac(seed, f"fumin_{action_counter}", store_id) * 20))
                        completed_ts = max(min(completed_ts, expiration_ts), resp_ts + timedelta(minutes=1))
                        _resp(completed_ts, "completed")
                    else:
                        _resp(max(expiration_ts, resp_ts + timedelta(minutes=1)), "expired")
                elif first == "deferred":
                    _resp(max(expiration_ts, resp_ts + timedelta(minutes=1)), "expired")

                # HISTORY OUTCOME: every completed action gets one, typed by what the action was for.
                # sale_closed only follows a completed customer_assist or clienteling action and is the
                # only outcome with a monetary value (amount and currency_code always paired).
                if completed_ts is not None:
                    outcome_ts = completed_ts + timedelta(minutes=2 + int(_py_frac(seed, f"outmin_{action_counter}", store_id) * 118))
                    ofrac = _py_frac(seed, f"otype_{action_counter}", store_id)
                    amount = currency = units = None
                    if action_type in ("customer_assist", "clienteling"):
                        if ofrac < 0.65:
                            outcome_type = "sale_closed"
                            amount = _dec(round(15 + _py_frac(seed, f"amount_{action_counter}", store_id) * 235, 2))
                            currency = base_currency
                            units = 1 + int(_py_frac(seed, f"units_{action_counter}", store_id) * 4)
                        else:
                            outcome_type = "customer_assisted"
                    elif action_type == "restock_shelf":
                        outcome_type = "item_restocked"
                        units = 6 + int(_py_frac(seed, f"units_{action_counter}", store_id) * 43)
                    elif action_type == "bopis_fulfill":
                        outcome_type = "customer_assisted" if ofrac < 0.85 else "issue_resolved"
                    else:
                        outcome_type = "issue_resolved" if ofrac < 0.80 else "no_outcome"
                    outcomes.append({
                        "outcome_resolution_id": f"outcome-{_md5_hash(action_id + outcome_type + str(outcome_ts))}",
                        "suggested_action_sk": None,
                        "suggested_action_id": action_id,
                        "resolution_timestamp": outcome_ts.replace(tzinfo=None),
                        "outcome_type": outcome_type,
                        "outcome_value_amount": amount,
                        "currency_code": currency,
                        "units_affected": units,
                        "record_source": "synthetic",
                        "load_timestamp": now.replace(tzinfo=None),
                    })
                elif first == "accepted":
                    # accepted, then left to expire: the work was started and abandoned
                    outcomes.append({
                        "outcome_resolution_id": f"outcome-{_md5_hash(action_id + 'task_abandoned')}",
                        "suggested_action_sk": None,
                        "suggested_action_id": action_id,
                        "resolution_timestamp": (max(expiration_ts, resp_ts + timedelta(minutes=1)) + timedelta(minutes=1)).replace(tzinfo=None),
                        "outcome_type": "task_abandoned",
                        "outcome_value_amount": None,
                        "currency_code": None,
                        "units_affected": None,
                        "record_source": "synthetic",
                        "load_timestamp": now.replace(tzinfo=None),
                    })

    # OPEN SLICE: [anchor-12h, anchor), 2-5 actions per associate
    for assoc in active:
        assoc_id = assoc["associate_id"]
        assoc_sk = assoc["associate_sk"]

        # 2-5 actions per associate (deterministic)
        open_count_frac = _py_frac(seed, f"opencount_{assoc_id}", "open")
        open_count = 2 + int(open_count_frac * (open_max_per_assoc - 2 + 1))  # [2, open_max_per_assoc]

        for open_idx in range(open_count):
            action_counter += 1

            # Generated in [anchor-12h, anchor)
            open_frac = _py_frac(seed, f"opengen_{action_counter}", assoc_id)
            gen_ts = anchor - timedelta(hours=12 - int(open_frac * 12))  # [anchor-12h, anchor)
            gen_ts = gen_ts.replace(minute=int(_py_frac(seed, f"openmin_{action_counter}", assoc_id) * 60), second=0, microsecond=0)

            # the associate's own store (an open action is on that associate's floor)
            store = store_by_id.get(assoc.get("store_id"))
            if store is None:
                continue
            store_id = store["store_id"]
            store_sk = store["store_sk"]

            action_type = _py_pick(ACTION_TYPES, seed, f"opatype_{action_counter}", assoc_id)

            # Optional profile/product
            profile_sk = None
            profile_id = None
            if _py_frac(seed, f"oppf_{action_counter}", assoc_id) < 0.4 and profiles:
                p = _py_pick(profiles, seed, f"opprof_{action_counter}", assoc_id)
                profile_sk = p.get("profile_sk")
                profile_id = p.get("profile_id")

            product_sk = None
            product_id = None
            if _py_frac(seed, f"oppd_{action_counter}", assoc_id) < 0.6 and products:
                p = _py_pick(products, seed, f"opprod_{action_counter}", assoc_id)
                product_sk = p.get("product_sk")
                product_id = p.get("product_id")

            trigger_source = _py_pick(TRIGGER_SOURCES, seed, f"optrg_{action_counter}", assoc_id) if _py_frac(seed, f"optrgf_{action_counter}", assoc_id) >= 0.7 else None

            base_score = BASE_SCORES.get(action_type, 50)

            # Decay mix for open: none 70%, linear 20%, exponential 10%
            decay_frac = _py_frac(seed, f"opdecay_{action_counter}", assoc_id)
            if decay_frac < 0.70:
                decay_type = "none"
            elif decay_frac < 0.90:
                decay_type = "linear"
            else:
                decay_type = "exponential"

            priority_mult = 0.7 + _py_frac(seed, f"opmult_{action_counter}", assoc_id, action_type) * 0.6
            priority_score = base_score * priority_mult

            zone_suffix = _py_pick(ZONE_FOR_ACTION.get(action_type, ZONE_SUFFIXES), seed, f"opz_{action_counter}", assoc_id)
            store_zone_id = f"SZ-{store_id}-{zone_suffix}"

            # OPEN EXPIRATION: whole days after the anchor. Persistent tasks (decay none) stay open
            # 7..30 days so the queue survives a quiet week without a redeploy; decaying asks
            # expire 2..7 days out.
            exp_day_frac = _py_frac(seed, f"opexpd_{action_counter}", assoc_id)
            exp_days = (7 + int(exp_day_frac * 24)) if decay_type == "none" else (2 + int(exp_day_frac * 6))
            expiration_ts = anchor + timedelta(days=exp_days)

            action_id = f"action-{_md5_hash(store_id + assoc_id + str(gen_ts) + action_type + str(action_counter))}"

            action_row = {
                "suggested_action_id": action_id,
                "generated_timestamp": gen_ts.replace(tzinfo=None),
                "associate_sk": assoc_sk,
                "associate_id": assoc_id,
                "store_sk": store_sk,
                "store_id": store_id,
                "store_zone_id": store_zone_id,
                "profile_sk": profile_sk,
                "profile_id": profile_id,
                "product_sk": product_sk,
                "product_id": product_id,
                "action_type": action_type,
                "trigger_source": trigger_source,
                "base_score": base_score,
                "priority_score": round(float(priority_score), 4),
                "decay_type": decay_type,
                "expiration_timestamp": expiration_ts.replace(tzinfo=None),
                "context_payload": None,
                "record_source": "synthetic",
                "load_timestamp": now.replace(tzinfo=None),
            }
            actions.append(action_row)

            # OPEN RESPONSE: No terminal, ~40% get one non-terminal (accepted/deferred)
            has_response_frac = _py_frac(seed, f"ophasresp_{action_counter}", assoc_id)
            if has_response_frac < 0.4:
                # One non-terminal response
                resp_type_frac = _py_frac(seed, f"opresptype_{action_counter}", assoc_id)
                response_type = "accepted" if resp_type_frac < 0.7 else "deferred"

                # Response timestamp between generated and anchor
                resp_offset_frac = _py_frac(seed, f"oprespoff_{action_counter}", assoc_id)
                # strictly after generation and before the anchor (open actions answered so far)
                window = max(1, min(int((anchor - gen_ts).total_seconds() / 60) - 1, 60))
                minutes_after = 1 + int(resp_offset_frac ** 2 * window)
                resp_ts = min(gen_ts + timedelta(minutes=minutes_after), anchor - timedelta(minutes=1))

                response_id = f"response-{_md5_hash(action_id + str(resp_ts) + response_type)}"
                responses.append({
                    "action_response_log_id": response_id,
                    "suggested_action_sk": None,
                    "suggested_action_id": action_id,
                    "associate_sk": assoc_sk,
                    "associate_id": assoc_id,
                    "response_timestamp": resp_ts.replace(tzinfo=None),
                    "response_type": response_type,
                    "reason_code": None,
                    "record_source": "synthetic",
                    "load_timestamp": now.replace(tzinfo=None),
                })

    return actions, responses, outcomes


def generate_associates(ctx, cfg):
    """Spark writer: generate associate master from labor.employee.

    Reads labor.employee (is_current=TRUE) and labor.employee_skill (active),
    writes to aasa.associate table.
    """
    spark = ctx.spark
    # always overwrite: ids are deterministic per run date, so append would duplicate keys
    if ctx.mode != "overwrite":
        print(f"[ordm] WARNING: aasa associates tables are overwrite-only; ignoring --mode {ctx.mode}")

    # Read upstream
    try:
        employees_df = spark.table(ctx.fq("labor", "employee")).filter("is_current = true").select(
            "employee_id", "primary_role_code", "employment_status", "employment_type",
            "hire_date", "home_store_sk", "home_store_id"
        ).collect()
        employees = [row.asDict() for row in employees_df]
    except Exception as exc:
        print(f"[ordm] WARNING: aasa associate generation skipped: cannot read {ctx.fq('labor', 'employee')}: {exc}")
        employees = []

    try:
        skills_df = spark.table(ctx.fq("labor", "employee_skill")).filter("is_active = true").select(
            "employee_id", "skill_code"
        ).collect()
        skills = [row.asDict() for row in skills_df]
    except Exception as exc:
        print(f"[ordm] WARNING: aasa associates get no skill_tags: cannot read {ctx.fq('labor', 'employee_skill')}: {exc}")
        skills = []

    if not employees:
        # leave associate untouched; generate_actions then reuses whatever rows it already holds
        print("[ordm] WARNING: labor.employee is empty or unreadable; aasa.associate not rewritten "
              "(actions are routed to the existing associate rows, if any)")
        return

    # Use pure Python builder
    rows = build_associate_rows(employees, skills, resolve_anchor(get_param("aasa_anchor_date", None)))

    if not rows:
        return

    # Create DataFrame
    schema_def = (
        "associate_id STRING, store_sk LONG, store_id STRING, role STRING, skill_tags STRING, "
        "employment_type STRING, primary_department STRING, is_active BOOLEAN, hire_date DATE, "
        "effective_from_date DATE, effective_to_date DATE, is_current BOOLEAN, "
        "created_timestamp TIMESTAMP, source_updated_timestamp TIMESTAMP, "
        "record_source STRING, load_timestamp TIMESTAMP"
    )
    df = spark.createDataFrame(rows, schema=schema_def)
    _write(spark, df, ctx.fq("aasa", "associate"), ASSOCIATE_COLUMNS, "overwrite")


def generate_actions(ctx, cfg):
    """Spark writer: generate suggested_action, action_response_log, outcome_resolution.

    Reads associate, store, product, customer.profile; writes three tables in order.
    """
    spark = ctx.spark
    # always overwrite: ids are deterministic per run date, so append would duplicate keys
    if ctx.mode != "overwrite":
        print(f"[ordm] WARNING: aasa actions tables are overwrite-only; ignoring --mode {ctx.mode}")

    # anchor: UTC midnight of the run date unless overridden
    anchor_date = get_param("aasa_anchor_date", None)
    anchor = resolve_anchor(anchor_date)

    # Read upstream
    def _collect(fq, cols, order_by=None, limit=None):
        # current SCD2 versions only: a new action references the version in force now
        try:
            df = spark.table(fq).filter("is_current = true").select(*cols)
            if order_by:
                df = df.orderBy(order_by)
            if limit:
                df = df.limit(limit)
            return [row.asDict() for row in df.collect()]
        except Exception as exc:
            print(f"[ordm] WARNING: aasa action generation cannot read {fq}: {exc}")
            return []

    associates = _collect(ctx.fq("aasa", "associate"), ["associate_sk", "associate_id", "store_id", "is_active"])
    stores = _collect(ctx.fq("store", "store"), ["store_sk", "store_id"])
    # optional FK pools: a bounded, deterministic sample (first N by durable id), so the driver
    # never collects a full master table at large scale factors
    products = _collect(ctx.fq("product", "product"), ["product_sk", "product_id"], order_by="product_id", limit=2000)
    profiles = _collect(ctx.fq("customer", "profile"), ["profile_sk", "profile_id"], order_by="profile_id", limit=5000)

    if not associates or not stores:
        # associate may just have been rewritten with new associate_sk values, so old action rows
        # would point at keys that no longer exist: clear the action tables rather than keep them
        print("[ordm] WARNING: aasa action generation skipped (no associates or no stores); "
              "clearing suggested_action, action_response_log and outcome_resolution")
        for t in ("outcome_resolution", "action_response_log", "suggested_action"):
            spark.sql(f"DELETE FROM {ctx.fq('aasa', t)}")
        return

    # Use pure Python builder
    base_currency = ctx.base_currency if hasattr(ctx, "base_currency") else "USD"
    actions, responses, outcomes = build_action_rows(
        associates, stores, products, profiles,
        anchor, cfg, cfg["seed"], base_currency
    )

    if not actions:
        print("[ordm] WARNING: aasa action generation built no actions; action tables left unchanged")
        return

    # Write actions
    action_schema = (
        "suggested_action_id STRING, generated_timestamp TIMESTAMP, associate_sk LONG, associate_id STRING, "
        "store_sk LONG, store_id STRING, store_zone_id STRING, profile_sk LONG, profile_id STRING, "
        "product_sk LONG, product_id STRING, action_type STRING, trigger_source STRING, "
        "base_score INT, priority_score DOUBLE, decay_type STRING, expiration_timestamp TIMESTAMP, "
        "context_payload STRING, record_source STRING, load_timestamp TIMESTAMP"
    )
    action_df = spark.createDataFrame(actions, schema=action_schema)
    _write(spark, action_df, ctx.fq("aasa", "suggested_action"), SUGGESTED_ACTION_COLUMNS, "overwrite")

    # Read back actions to get identity _sk values for FK resolution
    action_map = {}
    # no try/except: a failed read-back would write every response and outcome with a NULL
    # suggested_action_sk, so fail the run instead
    action_rows = spark.table(ctx.fq("aasa", "suggested_action")).select(
        "suggested_action_sk", "suggested_action_id"
    ).collect()
    for row in action_rows:
        action_map[row["suggested_action_id"]] = row["suggested_action_sk"]

    # Resolve FK for responses
    for response in responses:
        action_id = response["suggested_action_id"]
        response["suggested_action_sk"] = action_map.get(action_id)

    # Write responses
    if responses:
        response_schema = (
            "action_response_log_id STRING, suggested_action_sk LONG, suggested_action_id STRING, "
            "associate_sk LONG, associate_id STRING, response_timestamp TIMESTAMP, response_type STRING, "
            "reason_code STRING, record_source STRING, load_timestamp TIMESTAMP"
        )
        response_df = spark.createDataFrame(responses, schema=response_schema)
        _write(spark, response_df, ctx.fq("aasa", "action_response_log"), ACTION_RESPONSE_LOG_COLUMNS, "overwrite")

    # Resolve FK for outcomes
    for outcome in outcomes:
        action_id = outcome["suggested_action_id"]
        outcome["suggested_action_sk"] = action_map.get(action_id)

    # Write outcomes
    if outcomes:
        outcome_schema = (
            "outcome_resolution_id STRING, suggested_action_sk LONG, suggested_action_id STRING, "
            "resolution_timestamp TIMESTAMP, outcome_type STRING, outcome_value_amount DECIMAL(18,2), "
            "currency_code STRING, units_affected INT, record_source STRING, load_timestamp TIMESTAMP"
        )
        outcome_df = spark.createDataFrame(outcomes, schema=outcome_schema)
        _write(spark, outcome_df, ctx.fq("aasa", "outcome_resolution"), OUTCOME_RESOLUTION_COLUMNS, "overwrite")


def generate_events(spark, catalog, schema, products, stores, mode, cfg):
    now = _fixed_now()
    rows = []
    # Scenario-rich deterministic fixtures (see package README).
    fixtures = [
        # In stock at associate store
        ("EVT-INV-001", "inventory", "stock_adjustment", "STORE-01", "PROD-01",
         24.0, 20.0, 4.0, 6.0, None, "IN_STOCK", "A-12-B", 5),
        # Low stock with backroom / replenishment signal
        ("EVT-INV-002", "inventory", "stock_adjustment", "STORE-01", "PROD-02",
         3.0, 2.0, 1.0, 0.0, None, "LOW_STOCK", "BACKROOM-3", 5),
        # Out of stock locally (nearby handled in gold from other stores)
        ("EVT-INV-003", "inventory", "stock_adjustment", "STORE-01", "PROD-03",
         0.0, 0.0, 0.0, 12.0, None, "OUT_OF_STOCK", None, 5),
        # Duplicate of EVT-INV-001 (idempotency)
        ("EVT-INV-001", "inventory", "stock_adjustment", "STORE-01", "PROD-01",
         24.0, 20.0, 4.0, 6.0, None, "IN_STOCK", "A-12-B", 5),
        # Late-arriving older event (should not win current state)
        ("EVT-INV-004", "inventory", "stock_adjustment", "STORE-01", "PROD-01",
         99.0, 99.0, 0.0, 0.0, None, "IN_STOCK", "A-12-B", 5),
        # Fresh price
        ("EVT-PRICE-001", "price", "price_update", "STORE-01", "PROD-01",
         None, None, None, None, 12.9900, None, None, 3),
        # Stale price event (old ingest)
        ("EVT-PRICE-002", "price", "price_update", "STORE-01", "PROD-02",
         None, None, None, None, 8.5000, None, None, 3),
        # Order ready
        ("EVT-ORD-001", "order", "fulfillment_update", "STORE-01", None,
         None, None, None, None, None, "ready_for_pickup", "PU-DESK-1", 2),
        # Order exception
        ("EVT-ORD-002", "order", "fulfillment_update", "STORE-01", None,
         None, None, None, None, None, "exception", "PU-DESK-1", 2),
        # Operations alert
        ("EVT-OPS-001", "operations", "equipment_alert", "STORE-01", None,
         None, None, None, None, None, "high", None, 8),
    ]

    # Map fixture store/product to real ids when available.
    store_ids = [r["store_id"] for r in stores] or ["STORE-01"]
    product_ids = [r["product_id"] for r in products] or ["PROD-01", "PROD-02", "PROD-03"]
    store_sk = {r["store_id"]: r.get("store_sk") for r in stores}
    product_sk = {r["product_id"]: r.get("product_sk") for r in products}

    def _sid(i):
        return store_ids[i % len(store_ids)]

    def _pid(i):
        return product_ids[i % len(product_ids)]

    # Remap scenario keys onto real synthetic ids.
    remap_store = {"STORE-01": _sid(0), "STORE-02": _sid(1 if len(store_ids) > 1 else 0)}
    remap_prod = {
        "PROD-01": _pid(0),
        "PROD-02": _pid(1 if len(product_ids) > 1 else 0),
        "PROD-03": _pid(2 if len(product_ids) > 2 else 0),
    }

    for i, fx in enumerate(fixtures):
        eid, domain, etype, sid, pid, qoh, qav, qrs, qit, price, status, loc, lag = fx
        sid = remap_store.get(sid, sid)
        pid = remap_prod.get(pid, pid) if pid else None
        if eid == "EVT-INV-004":
            event_ts = now - timedelta(hours=6)
            ingest_ts = now - timedelta(minutes=1)  # late ingest of older event
        elif eid == "EVT-PRICE-002":
            event_ts = now - timedelta(hours=30)
            ingest_ts = now - timedelta(hours=30)
        else:
            event_ts = now - timedelta(minutes=10 + i)
            ingest_ts = event_ts + timedelta(seconds=lag)
        order_id = None
        if domain == "order":
            order_id = "ORD-READY-001" if eid.endswith("001") else "ORD-EXC-002"
        equipment_id = "EQ-001" if domain == "operations" else None
        rows.append((
            eid, domain, etype,
            store_sk.get(sid), sid,
            product_sk.get(pid) if pid else None, pid,
            order_id, None, equipment_id,
            _dec(qoh), _dec(qav), _dec(qrs), _dec(qit),
            _dec(price), "USD", status, loc,
            f"{domain} event {eid}",
            f"synth_{domain}",
            event_ts.replace(tzinfo=None),
            ingest_ts.replace(tzinfo=None),
            ingest_ts.replace(tzinfo=None),
            int((ingest_ts - event_ts).total_seconds()),
            RECORD_SOURCE,
            now.replace(tzinfo=None),
        ))

    # Pad to configured volume with deterministic extras (unique ids).
    n_extra = max(0, cfg["events"] - len({r[0] for r in rows}))
    seen = {r[0] for r in rows}
    for i in range(n_extra):
        eid = f"EVT-PAD-{i:04d}"
        if eid in seen:
            continue
        sid = _sid(i)
        pid = _pid(i)
        event_ts = now - timedelta(minutes=20 + i)
        ingest_ts = event_ts + timedelta(seconds=5)
        rows.append((
            eid, "inventory", "stock_adjustment",
            store_sk.get(sid), sid, product_sk.get(pid), pid,
            None, None, None,
            _dec((i % 20) + 1), _dec((i % 20) + 1), _dec(0), _dec(0),
            None, "USD", "IN_STOCK", f"LOC-{i % 5}",
            f"pad inventory {eid}",
            "synth_inventory",
            event_ts.replace(tzinfo=None),
            ingest_ts.replace(tzinfo=None),
            ingest_ts.replace(tzinfo=None),
            5,
            RECORD_SOURCE,
            now.replace(tzinfo=None),
        ))

    schema_def = (
        "associate_context_event_id STRING, event_domain STRING, event_type STRING, "
        "store_sk LONG, store_id STRING, product_sk LONG, product_id STRING, "
        "order_id STRING, promo_id STRING, equipment_id STRING, "
        "quantity_on_hand DECIMAL(12,3), quantity_available DECIMAL(12,3), "
        "quantity_reserved DECIMAL(12,3), quantity_in_transit DECIMAL(12,3), "
        "unit_price_amount DECIMAL(18,4), currency_code STRING, status_code STRING, "
        "location_code STRING, event_payload_summary STRING, source_system STRING, "
        "event_timestamp TIMESTAMP, ingest_timestamp TIMESTAMP, processed_timestamp TIMESTAMP, "
        "latency_seconds INT, record_source STRING, load_timestamp TIMESTAMP"
    )
    # Deduplicate by event id keeping first (fixtures encode the intended payload).
    dedup = {}
    for r in rows:
        dedup.setdefault(r[0], r)
    df = spark.createDataFrame(list(dedup.values()), schema=schema_def)
    _write(spark, df, f"{catalog}.{schema}.associate_context_event",
           ASSOCIATE_CONTEXT_EVENT_COLUMNS, mode)
    return df


def generate_fulfillment(spark, catalog, schema, stores, mode, cfg):
    now = _fixed_now().replace(tzinfo=None)
    store_ids = [r["store_id"] for r in stores] or ["STORE-01"]
    store_sk = {r["store_id"]: r.get("store_sk") for r in stores}
    sid = store_ids[0]
    other = store_ids[1] if len(store_ids) > 1 else store_ids[0]

    rows = [
        ("ORD-READY-001", "ORD-READY-001", store_sk.get(sid), sid,
         "bopis", "ready_for_pickup", "ready", "PU-DESK-1", "none",
         now - timedelta(minutes=8), "synth_oms", False, now - timedelta(minutes=5)),
        ("ORD-NOTREADY-001", "ORD-NOTREADY-001", store_sk.get(sid), sid,
         "bopis", "picking", "not_ready", "PU-DESK-1", "none",
         now - timedelta(minutes=20), "synth_oms", False, now - timedelta(minutes=15)),
        ("ORD-EXC-002", "ORD-EXC-002", store_sk.get(sid), sid,
         "curbside", "exception", "not_ready", "CURB-2", "missing_item",
         now - timedelta(minutes=12), "synth_oms", False, now - timedelta(minutes=10)),
        ("ORD-VERIFY-003", "ORD-VERIFY-003", store_sk.get(sid), sid,
         "bopis", "ready_for_pickup", "ready", "PU-DESK-1", "none",
         now - timedelta(minutes=6), "synth_oms", True, now - timedelta(minutes=4)),
        ("ORD-OTHER-STORE", "ORD-OTHER-STORE", store_sk.get(other), other,
         "bopis", "ready_for_pickup", "ready", "PU-DESK-9", "none",
         now - timedelta(minutes=9), "synth_oms", False, now - timedelta(minutes=7)),
    ]
    # Pad
    for i in range(max(0, cfg["orders"] - len(rows))):
        oid = f"ORD-PAD-{i:04d}"
        rows.append((
            oid, oid, store_sk.get(sid), sid,
            "ship_to_home", "shipped", "not_applicable", None, "none",
            now - timedelta(hours=1, minutes=i), "synth_oms", False,
            now - timedelta(minutes=30 + i),
        ))

    schema_def = (
        "associate_fulfillment_status_id STRING, order_id STRING, store_sk LONG, store_id STRING, "
        "fulfillment_type STRING, order_status STRING, pickup_readiness STRING, "
        "pickup_location_code STRING, exception_state STRING, last_event_timestamp TIMESTAMP, "
        "source_system STRING, requires_customer_verification BOOLEAN, "
        "data_freshness_timestamp TIMESTAMP, record_source STRING, load_timestamp TIMESTAMP"
    )
    enriched = [r + (RECORD_SOURCE, now) for r in rows]
    df = spark.createDataFrame(enriched, schema=schema_def)
    _write(spark, df, f"{catalog}.{schema}.associate_fulfillment_status",
           ASSOCIATE_FULFILLMENT_STATUS_COLUMNS, mode)
    return df


def generate_audit(spark, catalog, schema, stores, mode, cfg):
    now = _fixed_now().replace(tzinfo=None)
    sid = ([r["store_id"] for r in stores] or ["STORE-01"])[0]
    rows = [
        ("AUD-001", "REQ-001", "CORR-001", now, now, "EMP-001", "sales_associate", "mobile",
         sid, "get_product_availability", "allow", "STORE_SCOPE_ALLOWED", "SUCCESS",
         12, "inventory", "associate_ops", _sha("PROD-01"), None),
        ("AUD-002", "REQ-002", "CORR-002", now, now, "EMP-001", "sales_associate", "mobile",
         "STORE-UNAUTHORIZED", "get_product_availability", "deny", "STORE_SCOPE_DENIED",
         "ACCESS_DENIED", 4, "", "associate_ops", _sha("PROD-01"), None),
        ("AUD-003", "REQ-003", "CORR-003", now, now, "EMP-002", "fulfillment", "pos",
         sid, "get_order_fulfillment_status", "deny", "ORDER_REQUIRES_CUSTOMER_VERIFICATION",
         "ACCESS_DENIED", 6, "order", "associate_ops", None, _sha("ORD-VERIFY-003")),
    ]
    for i in range(max(0, cfg["audits"] - len(rows))):
        rows.append((
            f"AUD-PAD-{i:04d}", f"REQ-PAD-{i:04d}", f"CORR-PAD-{i:04d}", now, now,
            f"EMP-{(i % 5) + 1:03d}", "sales_associate", "api", sid,
            "get_store_operations_context", "allow", "STORE_SCOPE_ALLOWED", "SUCCESS",
            8 + i, "operations", "associate_ops", None, None,
        ))
    schema_def = (
        "associate_lookup_audit_id STRING, request_id STRING, correlation_id STRING, "
        "request_timestamp TIMESTAMP, generated_at TIMESTAMP, associate_id STRING, "
        "associate_role STRING, channel STRING, store_id STRING, capability STRING, "
        "access_decision STRING, access_reason_code STRING, response_status STRING, "
        "latency_ms INT, domains_accessed STRING, data_classification STRING, "
        "product_id_hash STRING, order_id_hash STRING, record_source STRING, load_timestamp TIMESTAMP"
    )
    enriched = [r + (RECORD_SOURCE, now) for r in rows]
    df = spark.createDataFrame(enriched, schema=schema_def)
    _write(spark, df, f"{catalog}.{schema}.associate_lookup_audit",
           ASSOCIATE_LOOKUP_AUDIT_COLUMNS, mode)
    return df


def run(ctx):
    cfg = load_config()
    spark = ctx.spark
    catalog = ctx.catalog
    schema = ctx.schemas["aasa"]
    mode = ctx.mode

    # Read upstream masters when present; fall back to empty for isolated runs.
    def _collect(fq, cols):
        try:
            return [row.asDict() for row in spark.table(fq).select(*cols).limit(50).collect()]
        except Exception:
            return []

    products = _collect(ctx.fq("product", "product"), ["product_sk", "product_id"])
    stores = _collect(ctx.fq("store", "store"), ["store_sk", "store_id"])

    # associates and the NBA action tables (overwrite-only: ids are deterministic per run date)
    generate_associates(ctx, cfg)
    generate_actions(ctx, cfg)

    # context events, fulfillment status, lookup audit
    generate_events(spark, catalog, schema, products, stores, mode, cfg)
    generate_fulfillment(spark, catalog, schema, stores, mode, cfg)
    generate_audit(spark, catalog, schema, stores, mode, cfg)


if __name__ == "__main__":
    from pyspark.sql import SparkSession
    try:
        from _context import DeployContext
    except ImportError:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from _context import DeployContext
    spark = SparkSession.builder.getOrCreate()
    run(DeployContext.from_params(spark))
