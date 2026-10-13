# ============================================================
# ORDM · Synthetic data · Predictive Operations generator
# Version: 0.5
# Generated: 2026-07-27
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-08-10
# ============================================================
# Populates every Predictive Operations extension table, across three use cases
# (all in the single `predictive_operations` schema — see ADR 0028 / ADR 0043):
#   In-Store Equipment Maintenance: work_order, work_order_line, maintenance_schedule
#   Store Performance:              store_risk_score
#   Workforce Optimization:         labor_standard, workforce_demand_forecast,
#                                   workforce_labor_requirement,
#                                   workforce_schedule_recommendation,
#                                   workforce_coverage_exception,
#                                   workforce_optimization_run
# Requires the canonical-core equipment + store dimensions (run those first).
#
# store_risk_score is an APPEND-ONLY store x as_of_date snapshot of the Store
# Operational Risk Score. In production a scoring pipeline writes it from
# gold_store_operational_risk; for synthetic data we seed it self-contained
# from the store dimension so the generator has no cross-package dependency.
# The rows are HONEST to the DDL contract and the design spec:
#   - five data-backed domain sub-scores (0-100) including labor_risk (ADR 0043);
#     cx_risk remains NULL (still deferred);
#   - the composite is the SAME weighted, denominator-of-present-weights,
#     non-compensatory computation the gold view ships
#     (weights 35/25/25/15/15 for inv/sup/sales/equip/labor);
#   - score_method = 'heuristic'; predicted_impact_amount / currency_code NULL
#     (reserved for a model-backed pipeline).
# Shared helpers come from _common (extended, not forked).
# Volumes come from runtime/synthetic-data/seeds.yaml.
# ============================================================

import os
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

try:
    from _common import (RECORD_SOURCE, load_domain_config, _pick, _frac, _write)
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import (RECORD_SOURCE, load_domain_config, _pick, _frac, _write)

# ------------------------------------------------------------
# Column contracts -- MUST match the DDL (minus IDENTITY *_sk).
# ------------------------------------------------------------
STORE_RISK_SCORE_COLUMNS = [
    "store_risk_score_id", "store_sk", "store_id", "as_of_date", "horizon_days",
    "operational_risk_score", "operational_risk_tier", "domains_scored", "top_risk_domains",
    "inventory_risk", "supply_chain_risk", "sales_margin_risk", "equipment_risk",
    "labor_risk", "cx_risk",
    "score_method", "model_version", "predicted_impact_amount", "currency_code",
    "record_source", "load_timestamp",
]
WORK_ORDER_COLUMNS = [
    "work_order_id", "equipment_sk", "equipment_id", "store_sk", "store_id",
    "work_order_type", "priority", "work_order_status",
    "title", "description", "failure_code", "assigned_to", "vendor_name",
    "created_date", "scheduled_date", "started_date", "completed_date",
    "estimated_duration_hours", "actual_duration_hours",
    "estimated_cost", "actual_cost", "currency_code",
    "downtime_hours", "root_cause",
    "record_source", "load_timestamp",
]
WORK_ORDER_LINE_COLUMNS = [
    "work_order_line_id", "work_order_sk", "work_order_id",
    "line_type", "part_number", "part_description", "quantity", "unit_cost", "line_total",
    "currency_code",
    "record_source", "load_timestamp",
]
MAINTENANCE_SCHEDULE_COLUMNS = [
    "maintenance_schedule_id", "equipment_sk", "equipment_id",
    "schedule_name", "task_description", "frequency", "interval_days",
    "next_due_date", "last_completed_date", "is_active",
    "estimated_duration_hours", "estimated_cost", "currency_code",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp",
    "record_source", "load_timestamp",
]
LABOR_STANDARD_COLUMNS = [
    "labor_standard_id", "standard_version", "role_code", "demand_driver",
    "department_or_zone", "interval_minutes",
    "driver_units_per_labor_hour", "labor_hours_per_driver_unit",
    "minimum_headcount", "coverage_rationale",
    "is_active", "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp",
    "record_source", "load_timestamp",
]
WORKFORCE_DEMAND_FORECAST_COLUMNS = [
    "workforce_demand_forecast_id", "workforce_optimization_run_id",
    "store_sk", "store_id", "business_date",
    "interval_start_ts", "interval_end_ts", "interval_minutes",
    "department_or_zone", "role_code", "demand_driver",
    "forecast_driver_units", "forecast_lower_bound", "forecast_upper_bound",
    "forecast_method", "model_version", "forecast_horizon_days", "forecast_origin_ts",
    "record_source", "load_timestamp",
]
WORKFORCE_LABOR_REQUIREMENT_COLUMNS = [
    "workforce_labor_requirement_id", "workforce_optimization_run_id",
    "store_sk", "store_id", "business_date",
    "interval_start_ts", "interval_end_ts", "interval_minutes",
    "department_or_zone", "role_code", "demand_driver",
    "forecast_driver_units", "labor_standard_id", "labor_standard_version",
    "applied_labor_standard", "required_labor_hours", "required_headcount",
    "minimum_headcount", "coverage_rationale",
    "record_source", "load_timestamp",
]
WORKFORCE_SCHEDULE_RECOMMENDATION_COLUMNS = [
    "workforce_schedule_recommendation_id", "workforce_optimization_run_id",
    "employee_sk", "employee_id", "store_sk", "store_id",
    "department_or_zone", "role_code",
    "shift_start_ts", "shift_end_ts", "assigned_hours",
    "estimated_labor_cost", "currency_code",
    "is_availability_ok", "is_skill_ok", "is_store_eligible_ok",
    "is_hours_cap_ok", "is_min_rest_ok",
    "recommendation_status", "optimizer_status",
    "record_source", "load_timestamp",
]
WORKFORCE_COVERAGE_EXCEPTION_COLUMNS = [
    "workforce_coverage_exception_id", "workforce_optimization_run_id",
    "store_sk", "store_id", "business_date",
    "interval_start_ts", "interval_end_ts",
    "department_or_zone", "role_code",
    "required_headcount", "scheduled_headcount", "shortfall_headcount",
    "severity", "exception_explanation", "suggested_action",
    "record_source", "load_timestamp",
]
WORKFORCE_OPTIMIZATION_RUN_COLUMNS = [
    "workforce_optimization_run_id", "forecast_horizon_days", "interval_minutes",
    "forecast_method", "optimizer_method",
    "input_employee_count", "input_demand_intervals", "rejected_quality_count",
    "forecast_line_count", "requirement_line_count",
    "recommended_shift_count", "exception_count",
    "scheduled_hours_total", "required_hours_total", "coverage_pct",
    "unfilled_demand_hours", "estimated_labor_cost", "currency_code",
    "fairness_score", "forecast_mape", "forecast_bias",
    "optimization_status", "diagnostics_json", "data_version",
    "run_started_ts", "run_completed_ts", "stage_durations_json",
    "record_source", "load_timestamp",
]

# Role -> demand_driver mapping mirrors gold_workforce_demand_forecast.
# (role_code, demand_driver, driver_units_per_labor_hour, minimum_headcount, rationale)
ROLE_LABOR_STANDARDS = [
    ("cashier", "transaction_count", 30.0, 0,
     "Cashier hours scale with POS transaction volume."),
    ("sales_associate", "foot_traffic", 25.0, 0,
     "Floor coverage scales with in-store foot traffic."),
    ("fulfillment", "pickup_orders", 12.0, 0,
     "Fulfillment labor scales with BOPIS/pickup order volume."),
    ("inventory", "receiving_units", 40.0, 0,
     "Inventory labor scales with receiving units."),
    ("supervisor", "store_open_coverage", 1.0, 1,
     "At least one supervisor whenever the store is open."),
]
WOR_RUN_ID = "WOR-SYN-001"
WF_INTERVAL_MINUTES = 30
WF_FORECAST_METHOD = "seasonal_rolling_avg"
WF_OPTIMIZER_METHOD = "greedy_heuristic"
WF_ROLES = ["cashier", "sales_associate", "fulfillment", "inventory", "supervisor"]
WF_SEVERITIES = ["low", "medium", "high", "high", "critical"]
WF_ACTIONS = ["call_in", "transfer", "overtime", "accept_risk", "hire_temp"]

# --- In-Store Equipment Maintenance seeded value sets ---
WO_TYPES = ["preventive", "preventive", "preventive", "corrective", "corrective", "emergency", "inspection"]
PRIORITIES = ["critical", "high", "medium", "medium", "low"]
WO_STATUSES = ["completed", "completed", "completed", "in_progress", "open"]
FAILURE_CODES = ["compressor_failure", "sensor_malfunction", "wear_and_tear", "power_surge", "filter_clog", "belt_slip"]
ASSIGNEES = ["tech-team-alpha", "tech-team-bravo", "tech-team-charlie", "vendor-hvac-pro", "vendor-refrigtech"]
VENDORS = ["HVAC Pro Services", "RefrigTech Inc", "POS Repair Co", "General Maintenance LLC"]
PART_NUMBERS = ["P-COMP-100", "P-FILT-200", "P-BELT-300", "P-SENS-400", "P-VALVE-500", "P-BOARD-600"]
PART_DESCS = ["Compressor unit", "Air filter", "Drive belt", "Temperature sensor", "Expansion valve", "Control board"]
FREQUENCIES = ["weekly", "monthly", "quarterly", "semi_annual", "annual"]
INTERVAL_MAP = {"weekly": 7, "monthly": 30, "quarterly": 90, "semi_annual": 182, "annual": 365}
SCHEDULE_NAMES = [
    "Filter replacement", "Coil cleaning", "Refrigerant check",
    "Belt inspection", "Sensor calibration", "Full service",
]
SCHEDULE_DESCS = [
    "Replace air filters per manufacturer spec",
    "Clean condenser and evaporator coils",
    "Check refrigerant levels and top up if needed",
    "Inspect and replace worn drive belts",
    "Calibrate temperature and humidity sensors",
    "Full preventive maintenance service",
]

# Weights mirror gold_store_operational_risk.sql (denominator-of-present-weights).
W_INV, W_SUP, W_SALES, W_EQUIP, W_LABOR = 35.0, 25.0, 25.0, 15.0, 15.0
# Tier thresholds + the worst-domain floor, identical to the gold view.
T_MED, T_HIGH, T_CRIT = 25.0, 50.0, 75.0
DOMAIN_CRITICAL = 75.0
HORIZON_DAYS = 7


def load_config():
    c = load_domain_config("predictive_operations")
    vols = c.get("volumes", {}) or {}
    return {
        "seed": c.get("seed", 12012),
        # Store Performance
        "snapshots": vols.get("snapshots", 5),          # daily snapshots per store
        "snapshot_stride_days": vols.get("snapshot_stride_days", 7),
        # In-Store Equipment Maintenance
        "work_orders": vols.get("work_orders", 120),
        "lines_per_wo": vols.get("lines_per_wo", 2),
        "schedules_per_equipment": vols.get("schedules_per_equipment", 1),
        # Workforce Optimization
        "forecast_lines": vols.get("forecast_lines", 48),
        "recommendations": vols.get("recommendations", 20),
        "exceptions": vols.get("exceptions", 5),
    }


def _subscore(seed, salt, store_id, as_of):
    """A deterministic 0-100 sub-score per (store, date, domain). Pure function of
    keys+seed, so a re-run reproduces identical data (guardrail: reproducibility)."""
    return F.round(_frac(seed, salt, store_id, as_of) * F.lit(100.0), 1)


def generate_store_risk_scores(spark, catalog, schema, cfg, mode, store_df):
    seed = cfg["seed"]
    n_snap = cfg["snapshots"]
    stride = cfg["snapshot_stride_days"]
    now = F.current_timestamp()
    today = F.current_date()

    stores = store_df.select("store_sk", "store_id")

    # One row per store per snapshot date. Snapshot k is `today - k*stride` days back,
    # so the newest snapshot is today and history trends backward.
    snap_idx = spark.range(n_snap).withColumnRenamed("id", "snap_k")
    df = stores.crossJoin(snap_idx)
    df = df.withColumn("as_of_date", F.date_sub(today, (F.col("snap_k") * F.lit(stride)).cast("int")))

    as_of_str = F.col("as_of_date").cast("string")

    # --- five data-backed domain sub-scores (0-100); cx_risk still deferred (NULL) ---
    # Base sub-scores are independent per (store, date, domain). On top of that, a
    # deterministic ~20% of stores are "hotspot" stores biased toward ONE dominant
    # domain (chosen stably per store): that domain's sub-score is lifted into the
    # critical band (>= 85) for the store's snapshots. This makes the seed data
    # DEMONSTRABLE — top_risk_domains names a real dominant driver for hotspot
    # stores, and those stores trip the worst-domain floor to HIGH/CRITICAL — while
    # the other ~80% stay realistic uncorrelated noise. The composite/tier math
    # still mirrors the gold view exactly; only the inputs are shaped.
    # (The gold view's sales-trend escalator has no analog here — the fact carries
    # no sales_trend_risk column — so the trend path is exercised in the view, not
    # the seed; the worst-domain floor is exercised by these hotspots.)
    # labor_risk is populated (ADR 0043); cx_risk remains NULL.
    is_hotspot = _frac(seed, "hotspot", F.col("store_id")) < F.lit(0.20)
    dom_pick = (F.abs(F.hash(F.col("store_id"), F.lit("dompick"), F.lit(seed))) % F.lit(5)).cast("int")

    def _biased(salt, domain_idx):
        base = _subscore(seed, salt, F.col("store_id"), as_of_str)
        # Lift the chosen domain of a hotspot store into the critical band [85, 100].
        lifted = F.round(F.lit(85.0) + _frac(seed, salt + "_lift", F.col("store_id"), as_of_str) * F.lit(15.0), 1)
        return F.when(is_hotspot & (dom_pick == F.lit(domain_idx)), lifted).otherwise(base)

    df = (df
          .withColumn("inventory_risk",    _biased("inv",   0))
          .withColumn("supply_chain_risk", _biased("sup",   1))
          .withColumn("sales_margin_risk", _biased("sales", 2))
          .withColumn("equipment_risk",    _biased("equip", 3))
          .withColumn("labor_risk",        _biased("labor", 4))
          .withColumn("cx_risk",    F.lit(None).cast("double")))

    # A deterministic fraction of store/date rows have a MISSING data-backed domain
    # (e.g. no equipment installed), to exercise the "missing = excluded from the
    # denominator, not scored 0" contract. ~15% drop their equipment sub-score.
    df = df.withColumn(
        "equipment_risk",
        F.when(_frac(seed, "equip_missing", F.col("store_id"), as_of_str) < F.lit(0.15),
               F.lit(None).cast("double"))
         .otherwise(F.col("equipment_risk")))

    # --- composite: SUM(w_i * score_i) / SUM(w_i over PRESENT domains) ---
    def present(col, w):
        return F.when(F.col(col).isNotNull(), F.lit(w)).otherwise(F.lit(0.0))

    def contrib(col, w):
        return F.when(F.col(col).isNotNull(), F.lit(w) * F.col(col)).otherwise(F.lit(0.0))

    df = (df
          .withColumn("_c_inv",   contrib("inventory_risk", W_INV))
          .withColumn("_c_sup",   contrib("supply_chain_risk", W_SUP))
          .withColumn("_c_sales", contrib("sales_margin_risk", W_SALES))
          .withColumn("_c_equip", contrib("equipment_risk", W_EQUIP))
          .withColumn("_c_labor", contrib("labor_risk", W_LABOR))
          .withColumn("_w_present",
                      present("inventory_risk", W_INV) + present("supply_chain_risk", W_SUP)
                      + present("sales_margin_risk", W_SALES) + present("equipment_risk", W_EQUIP)
                      + present("labor_risk", W_LABOR))
          .withColumn("domains_scored",
                      (F.col("inventory_risk").isNotNull().cast("int")
                       + F.col("supply_chain_risk").isNotNull().cast("int")
                       + F.col("sales_margin_risk").isNotNull().cast("int")
                       + F.col("equipment_risk").isNotNull().cast("int")
                       + F.col("labor_risk").isNotNull().cast("int")))
          .withColumn("operational_risk_score",
                      F.when(F.col("_w_present") > 0,
                             F.round((F.col("_c_inv") + F.col("_c_sup")
                                      + F.col("_c_sales") + F.col("_c_equip")
                                      + F.col("_c_labor")) / F.col("_w_present"), 1))
                       .otherwise(F.lit(None).cast("double"))))

    # worst-domain floor (non-compensatory): any PRESENT sub-score >= DOMAIN_CRITICAL forces >= HIGH.
    any_critical = (
        (F.coalesce(F.col("inventory_risk"),    F.lit(0.0)) >= F.lit(DOMAIN_CRITICAL))
        | (F.coalesce(F.col("supply_chain_risk"), F.lit(0.0)) >= F.lit(DOMAIN_CRITICAL))
        | (F.coalesce(F.col("sales_margin_risk"), F.lit(0.0)) >= F.lit(DOMAIN_CRITICAL))
        | (F.coalesce(F.col("equipment_risk"),    F.lit(0.0)) >= F.lit(DOMAIN_CRITICAL))
        | (F.coalesce(F.col("labor_risk"),        F.lit(0.0)) >= F.lit(DOMAIN_CRITICAL))
    )

    df = df.withColumn(
        "operational_risk_tier",
        # No present domain (score NULL) -> UNKNOWN, not LOW (missing = unknown, not safe).
        F.when(F.col("operational_risk_score").isNull(), F.lit("UNKNOWN"))
         .when(F.col("operational_risk_score") >= F.lit(T_CRIT), F.lit("CRITICAL"))
         .when((F.col("operational_risk_score") >= F.lit(T_HIGH)) | any_critical, F.lit("HIGH"))
         .when(F.col("operational_risk_score") >= F.lit(T_MED), F.lit("MEDIUM"))
         .otherwise(F.lit("LOW")))

    # top_risk_domains: the up-to-3 highest weighted contributions, comma-joined,
    # matching the gold view's up-to-3 ranking. Built with SQL higher-order functions
    # via F.expr (the repo's idiom) rather than Python-lambda HOFs, for unambiguous
    # support across Spark versions: sort the (contribution, domain) structs
    # descending, keep the positive ones, take the top 3 names.
    df = df.withColumn(
        "top_risk_domains",
        F.expr(
            "concat_ws(', ', slice(transform("
            "  filter("
            "    sort_array(array("
            "      named_struct('c', _c_inv,   'd', 'inventory'),"
            "      named_struct('c', _c_sup,   'd', 'supply_chain'),"
            "      named_struct('c', _c_sales, 'd', 'sales_margin'),"
            "      named_struct('c', _c_equip, 'd', 'equipment'),"
            "      named_struct('c', _c_labor, 'd', 'labor')"
            "    ), false),"
            "    x -> x.c > 0"
            "  ), x -> x.d), 1, 3))"
        ))

    # honesty columns + keys + audit
    df = (df
          .withColumn("horizon_days", F.lit(HORIZON_DAYS))
          .withColumn("score_method", F.lit("heuristic"))
          # Business key is unique at the table grain (store x as_of_date x score_method),
          # so a future score_method='model' row does not collide with the heuristic row.
          .withColumn("store_risk_score_id",
                      F.concat_ws("|", F.col("store_id"), as_of_str, F.col("score_method")))
          .withColumn("model_version", F.lit(None).cast("string"))
          .withColumn("predicted_impact_amount", F.lit(None).cast("decimal(18,2)"))
          .withColumn("currency_code", F.lit(None).cast("string"))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("snap_k", "_c_inv", "_c_sup", "_c_sales", "_c_equip", "_c_labor", "_w_present"))

    fqtn = f"{catalog}.{schema}.store_risk_score"
    return _write(spark, df, fqtn, STORE_RISK_SCORE_COLUMNS, mode)


# ------------------------------------------------------------
# In-Store Equipment Maintenance tables (work_order, work_order_line,
# maintenance_schedule). Deployed into the same predictive_operations schema.
# ------------------------------------------------------------

def generate_work_orders(spark, catalog, schema, cfg, mode, equipment_df, base_currency):
    """Generate maintenance work order rows."""
    seed = cfg["seed"]
    n = cfg["work_orders"]
    now = F.current_timestamp()
    today = F.current_date()
    from pyspark.sql.window import Window

    equip_count = equipment_df.count()
    equip = equipment_df.select(
        F.col("equipment_sk").alias("_eq_sk"), F.col("equipment_id").alias("_eq_id"),
        F.col("store_sk").alias("_st_sk"), F.col("store_id").alias("_st_id")
    ).withColumn("_eq_idx", F.row_number().over(Window.orderBy("_eq_sk")) - F.lit(1))

    ids = spark.range(n).withColumn("work_order_id",
                                     F.concat(F.lit("WO-"), F.format_string("%06d", F.col("id") + F.lit(1))))

    # Assign equipment
    df = ids.withColumn("_eq_idx", (F.abs(F.hash(F.col("work_order_id"), F.lit(seed))) % F.lit(equip_count)).cast("int"))
    df = df.join(F.broadcast(equip), "_eq_idx", "left").drop("_eq_idx")
    df = (df
          .withColumnRenamed("_eq_sk", "equipment_sk")
          .withColumnRenamed("_eq_id", "equipment_id")
          .withColumnRenamed("_st_sk", "store_sk")
          .withColumnRenamed("_st_id", "store_id"))

    df = (df
          .withColumn("work_order_type", _pick(WO_TYPES, seed, "wotype", F.col("work_order_id")))
          .withColumn("priority", _pick(PRIORITIES, seed, "prio", F.col("work_order_id")))
          .withColumn("work_order_status", _pick(WO_STATUSES, seed, "wostatus", F.col("work_order_id")))
          .withColumn("failure_code",
                      F.when(F.col("work_order_type").isin("corrective", "emergency"),
                             _pick(FAILURE_CODES, seed, "fcode", F.col("work_order_id")))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("title",
                      F.concat(F.initcap(F.col("work_order_type")), F.lit(": "),
                               F.coalesce(F.col("failure_code"), F.lit("scheduled maintenance"))))
          .withColumn("description",
                      F.concat(F.col("title"), F.lit(" for equipment "), F.col("equipment_id")))
          .withColumn("assigned_to",
                      F.when(F.col("work_order_status") != "open",
                             _pick(ASSIGNEES, seed, "assign", F.col("work_order_id")))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("vendor_name",
                      F.when(_frac(seed, "vendor", F.col("work_order_id")) < F.lit(0.3),
                             _pick(VENDORS, seed, "vname", F.col("work_order_id")))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("created_date",
                      F.date_sub(today, (F.abs(F.hash(F.col("work_order_id"), F.lit(seed + 1))) % F.lit(180) + F.lit(1)).cast("int")))
          .withColumn("scheduled_date",
                      F.date_add(F.col("created_date"), (F.abs(F.hash(F.col("work_order_id"), F.lit(seed + 2))) % F.lit(14) + F.lit(1)).cast("int")))
          .withColumn("started_date",
                      F.when(F.col("work_order_status").isin("in_progress", "completed"),
                             F.date_add(F.col("created_date"), (F.abs(F.hash(F.col("work_order_id"), F.lit(seed + 3))) % F.lit(7) + F.lit(1)).cast("int")))
                       .otherwise(F.lit(None).cast("date")))
          .withColumn("completed_date",
                      F.when(F.col("work_order_status") == "completed",
                             F.date_add(F.col("started_date"), (F.abs(F.hash(F.col("work_order_id"), F.lit(seed + 4))) % F.lit(5)).cast("int")))
                       .otherwise(F.lit(None).cast("date")))
          .withColumn("estimated_duration_hours",
                      ((F.abs(F.hash(F.col("work_order_id"), F.lit(seed + 5))) % F.lit(40) + F.lit(5)).cast("double") / F.lit(10.0)).cast("decimal(6,1)"))
          .withColumn("actual_duration_hours",
                      F.when(F.col("work_order_status") == "completed",
                             (F.col("estimated_duration_hours") * (F.lit(0.7) + _frac(seed, "dur", F.col("work_order_id")) * F.lit(0.6))).cast("decimal(6,1)"))
                       .otherwise(F.lit(None).cast("decimal(6,1)")))
          .withColumn("estimated_cost",
                      ((F.abs(F.hash(F.col("work_order_id"), F.lit(seed + 6))) % F.lit(5000) + F.lit(100)).cast("double")).cast("decimal(12,2)"))
          .withColumn("actual_cost",
                      F.when(F.col("work_order_status") == "completed",
                             (F.col("estimated_cost") * (F.lit(0.8) + _frac(seed, "cost", F.col("work_order_id")) * F.lit(0.5))).cast("decimal(12,2)"))
                       .otherwise(F.lit(None).cast("decimal(12,2)")))
          .withColumn("currency_code", F.lit(base_currency))
          .withColumn("downtime_hours",
                      F.when(F.col("work_order_type").isin("corrective", "emergency"),
                             ((F.abs(F.hash(F.col("work_order_id"), F.lit(seed + 7))) % F.lit(48) + F.lit(1)).cast("double")).cast("decimal(8,2)"))
                       .otherwise(F.lit(None).cast("decimal(8,2)")))
          .withColumn("root_cause",
                      F.when(F.col("work_order_status") == "completed",
                             F.concat(F.lit("Root cause: "), F.coalesce(F.col("failure_code"), F.lit("routine wear"))))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("id"))

    fqtn = f"{catalog}.{schema}.work_order"
    return _write(spark, df, fqtn, WORK_ORDER_COLUMNS, mode)


def generate_work_order_lines(spark, catalog, schema, cfg, mode, wo_df, base_currency):
    """Generate work order line items."""
    seed = cfg["seed"]
    lines_per = cfg["lines_per_wo"]
    now = F.current_timestamp()

    wo = wo_df.select("work_order_sk", "work_order_id")
    line_ids = spark.range(lines_per).withColumnRenamed("id", "line_idx")
    df = wo.crossJoin(line_ids)

    df = (df
          .withColumn("work_order_line_id",
                      F.concat(F.col("work_order_id"), F.lit("-L"), F.format_string("%02d", F.col("line_idx") + F.lit(1))))
          .withColumn("line_type",
                      F.when(F.col("line_idx") == 0, F.lit("part"))
                       .otherwise(_pick(["labor", "service", "part"], seed, "ltype", F.col("work_order_line_id"))))
          .withColumn("part_number",
                      F.when(F.col("line_type") == "part",
                             _pick(PART_NUMBERS, seed, "pnum", F.col("work_order_line_id")))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("part_description",
                      F.when(F.col("line_type") == "part",
                             _pick(PART_DESCS, seed, "pdesc", F.col("work_order_line_id")))
                       .when(F.col("line_type") == "labor", F.lit("Technician labor"))
                       .otherwise(F.lit("Service charge")))
          .withColumn("quantity",
                      F.when(F.col("line_type") == "labor",
                             ((F.abs(F.hash(F.col("work_order_line_id"), F.lit(seed + 8))) % F.lit(40) + F.lit(5)).cast("double") / F.lit(10.0)).cast("decimal(10,2)"))
                       .otherwise(((F.abs(F.hash(F.col("work_order_line_id"), F.lit(seed + 9))) % F.lit(5) + F.lit(1)).cast("double")).cast("decimal(10,2)")))
          .withColumn("unit_cost",
                      ((F.abs(F.hash(F.col("work_order_line_id"), F.lit(seed + 10))) % F.lit(500) + F.lit(20)).cast("double")).cast("decimal(12,2)"))
          .withColumn("line_total", (F.col("quantity") * F.col("unit_cost")).cast("decimal(12,2)"))
          .withColumn("currency_code", F.lit(base_currency))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("line_idx"))

    fqtn = f"{catalog}.{schema}.work_order_line"
    return _write(spark, df, fqtn, WORK_ORDER_LINE_COLUMNS, mode)


def generate_maintenance_schedules(spark, catalog, schema, cfg, mode, equipment_df, base_currency):
    """Generate maintenance schedule entries for equipment."""
    seed = cfg["seed"]
    now = F.current_timestamp()
    today = F.current_date()

    equip = equipment_df.select("equipment_sk", "equipment_id")

    df = (equip
          .withColumn("maintenance_schedule_id",
                      F.concat(F.lit("MS-"), F.col("equipment_id")))
          .withColumn("frequency", _pick(FREQUENCIES, seed, "freq", F.col("equipment_id")))
          .withColumn("interval_days",
                      F.when(F.col("frequency") == "weekly", F.lit(7))
                       .when(F.col("frequency") == "monthly", F.lit(30))
                       .when(F.col("frequency") == "quarterly", F.lit(90))
                       .when(F.col("frequency") == "semi_annual", F.lit(182))
                       .otherwise(F.lit(365)))
          .withColumn("schedule_name", _pick(SCHEDULE_NAMES, seed, "sname", F.col("equipment_id")))
          .withColumn("task_description", _pick(SCHEDULE_DESCS, seed, "sdesc", F.col("equipment_id")))
          .withColumn("last_completed_date",
                      F.date_sub(today, (F.abs(F.hash(F.col("equipment_id"), F.lit(seed + 11))) % F.lit(60) + F.lit(1)).cast("int")))
          .withColumn("next_due_date",
                      F.date_add(F.col("last_completed_date"), F.col("interval_days")))
          .withColumn("is_active", F.lit(True))
          .withColumn("estimated_duration_hours",
                      ((F.abs(F.hash(F.col("equipment_id"), F.lit(seed + 12))) % F.lit(20) + F.lit(5)).cast("double") / F.lit(10.0)).cast("decimal(6,1)"))
          .withColumn("estimated_cost",
                      ((F.abs(F.hash(F.col("equipment_id"), F.lit(seed + 13))) % F.lit(1000) + F.lit(50)).cast("double")).cast("decimal(12,2)"))
          .withColumn("currency_code", F.lit(base_currency))
          .withColumn("effective_from_date",
                      F.date_sub(today, (F.abs(F.hash(F.col("equipment_id"), F.lit(seed + 14))) % F.lit(365) + F.lit(90)).cast("int")))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", F.to_timestamp(F.col("effective_from_date")))
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))

    fqtn = f"{catalog}.{schema}.maintenance_schedule"
    return _write(spark, df, fqtn, MAINTENANCE_SCHEDULE_COLUMNS, mode)


# ------------------------------------------------------------
# Workforce Optimization tables (labor_standard, demand forecast,
# labor requirement, schedule recommendation, coverage exception,
# optimization run). Deployed into the same predictive_operations schema.
# ------------------------------------------------------------

def generate_labor_standards(spark, catalog, schema, cfg, mode):
    """One current labor_standard row per role matching gold role->driver mapping."""
    now = F.current_timestamp()
    today = F.current_date()
    rows = [
        (f"LS-{role.upper()}", "v1", role, driver, None, WF_INTERVAL_MINUTES,
         float(units), float(1.0 / units), int(min_hc), rationale)
        for role, driver, units, min_hc, rationale in ROLE_LABOR_STANDARDS
    ]
    df = spark.createDataFrame(
        rows,
        "labor_standard_id STRING, standard_version STRING, role_code STRING, "
        "demand_driver STRING, department_or_zone STRING, interval_minutes INT, "
        "driver_units_per_labor_hour DOUBLE, labor_hours_per_driver_unit DOUBLE, "
        "minimum_headcount INT, coverage_rationale STRING")
    df = (df
          .withColumn("driver_units_per_labor_hour",
                      F.col("driver_units_per_labor_hour").cast("decimal(18,4)"))
          .withColumn("labor_hours_per_driver_unit",
                      F.col("labor_hours_per_driver_unit").cast("decimal(18,6)"))
          .withColumn("is_active", F.lit(True))
          .withColumn("effective_from_date", F.date_sub(today, F.lit(90)))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", F.to_timestamp(F.col("effective_from_date")))
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))
    fqtn = f"{catalog}.{schema}.labor_standard"
    return _write(spark, df, fqtn, LABOR_STANDARD_COLUMNS, mode)


def generate_workforce_optimization_run(spark, catalog, schema, cfg, mode, base_currency):
    """One synthetic optimization run (success_partial) for Workforce Optimization."""
    now = F.current_timestamp()
    n_forecast = cfg["forecast_lines"]
    n_rec = cfg["recommendations"]
    n_exc = cfg["exceptions"]
    scheduled_hours = float(n_rec) * 4.0
    required_hours = scheduled_hours + float(n_exc) * 1.5
    coverage = scheduled_hours / required_hours if required_hours > 0 else 1.0
    rows = [(
        WOR_RUN_ID,
        HORIZON_DAYS,
        WF_INTERVAL_MINUTES,
        WF_FORECAST_METHOD,
        WF_OPTIMIZER_METHOD,
        40,                          # input_employee_count
        n_forecast,                  # input_demand_intervals
        0,                           # rejected_quality_count
        n_forecast,                  # forecast_line_count
        n_forecast,                  # requirement_line_count (1:1 with forecast)
        n_rec,                       # recommended_shift_count
        n_exc,                       # exception_count
        scheduled_hours,             # scheduled_hours_total
        required_hours,              # required_hours_total
        coverage,                    # coverage_pct
        float(n_exc) * 1.5,          # unfilled_demand_hours
        scheduled_hours * 18.50,     # estimated_labor_cost
        base_currency,
        0.82,                        # fairness_score
        None,                        # forecast_mape
        None,                        # forecast_bias
        "success_partial",
        '{"note":"synthetic seed; partial coverage by design"}',
        "syn-v1",
    )]
    df = spark.createDataFrame(
        rows,
        "workforce_optimization_run_id STRING, forecast_horizon_days INT, interval_minutes INT, "
        "forecast_method STRING, optimizer_method STRING, "
        "input_employee_count INT, input_demand_intervals INT, rejected_quality_count INT, "
        "forecast_line_count INT, requirement_line_count INT, "
        "recommended_shift_count INT, exception_count INT, "
        "scheduled_hours_total DOUBLE, required_hours_total DOUBLE, coverage_pct DOUBLE, "
        "unfilled_demand_hours DOUBLE, estimated_labor_cost DOUBLE, currency_code STRING, "
        "fairness_score DOUBLE, forecast_mape DOUBLE, forecast_bias DOUBLE, "
        "optimization_status STRING, diagnostics_json STRING, data_version STRING")
    df = (df
          .withColumn("scheduled_hours_total", F.col("scheduled_hours_total").cast("decimal(18,2)"))
          .withColumn("required_hours_total", F.col("required_hours_total").cast("decimal(18,2)"))
          .withColumn("unfilled_demand_hours", F.col("unfilled_demand_hours").cast("decimal(18,2)"))
          .withColumn("estimated_labor_cost", F.col("estimated_labor_cost").cast("decimal(18,2)"))
          .withColumn("run_started_ts", F.expr("current_timestamp() - INTERVAL 15 MINUTES"))
          .withColumn("run_completed_ts", now)
          .withColumn("stage_durations_json",
                      F.lit('{"forecast":4.2,"requirements":1.1,"schedule":8.5,"exceptions":0.4}'))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))
    fqtn = f"{catalog}.{schema}.workforce_optimization_run"
    return _write(spark, df, fqtn, WORKFORCE_OPTIMIZATION_RUN_COLUMNS, mode)


def generate_workforce_demand_forecast(spark, catalog, schema, cfg, mode, store_df):
    """A few dozen forecast lines for a couple stores/roles/intervals."""
    seed = cfg["seed"]
    n = cfg["forecast_lines"]
    now = F.current_timestamp()
    today = F.current_date()

    stores = store_df.select("store_sk", "store_id").orderBy("store_id").limit(2)
    role_rows = [(r, d) for r, d, *_ in ROLE_LABOR_STANDARDS[:2]]  # cashier + sales_associate
    roles = spark.createDataFrame(role_rows, "role_code STRING, demand_driver STRING")
    # 2 stores x 2 roles x slots ~= forecast_lines (48 -> 12 slots)
    n_slots = max(1, n // max(1, stores.count() * roles.count()))
    slots = spark.range(n_slots).withColumnRenamed("id", "slot")

    df = stores.crossJoin(roles).crossJoin(slots)
    df = (df
          .withColumn("business_date", F.date_add(today, F.lit(1)))
          .withColumn(
              "_base_ts",
              F.to_timestamp(F.concat(F.col("business_date").cast("string"), F.lit(" 09:00:00"))))
          .withColumn(
              "interval_start_ts",
              F.col("_base_ts")
              + F.expr("INTERVAL 1 MINUTE") * (F.col("slot") * F.lit(WF_INTERVAL_MINUTES)))
          .withColumn(
              "interval_end_ts",
              F.col("interval_start_ts")
              + F.expr("INTERVAL 1 MINUTE") * F.lit(WF_INTERVAL_MINUTES))
          .withColumn("interval_minutes", F.lit(WF_INTERVAL_MINUTES))
          .withColumn("department_or_zone", F.lit("storewide"))
          .withColumn("forecast_driver_units",
                      (F.lit(5.0) + _frac(seed, "fcst", F.col("store_id"), F.col("role_code"),
                                          F.col("slot").cast("string")) * F.lit(40.0))
                      .cast("decimal(18,4)"))
          .withColumn("forecast_lower_bound",
                      (F.col("forecast_driver_units") * F.lit(0.8)).cast("decimal(18,4)"))
          .withColumn("forecast_upper_bound",
                      (F.col("forecast_driver_units") * F.lit(1.2)).cast("decimal(18,4)"))
          .withColumn("forecast_method", F.lit(WF_FORECAST_METHOD))
          # Reserved column: NULL for heuristic rows (ADR 0028 §4); forecast_method
          # here is seasonal_rolling_avg, not 'model'.
          .withColumn("model_version", F.lit(None).cast("string"))
          .withColumn("forecast_horizon_days", F.lit(HORIZON_DAYS))
          .withColumn("forecast_origin_ts", now)
          .withColumn("workforce_optimization_run_id", F.lit(WOR_RUN_ID))
          .withColumn("workforce_demand_forecast_id",
                      F.concat_ws("|", F.col("store_id"), F.col("business_date").cast("string"),
                                  F.date_format(F.col("interval_start_ts"), "HHmm"),
                                  F.col("role_code")))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("slot", "_base_ts")
          .limit(n))

    fqtn = f"{catalog}.{schema}.workforce_demand_forecast"
    return _write(spark, df, fqtn, WORKFORCE_DEMAND_FORECAST_COLUMNS, mode)


def generate_workforce_labor_requirement(spark, catalog, schema, cfg, mode, forecast_df, standard_df):
    """Derive labor requirements simply as forecast_units * hours_per_unit."""
    now = F.current_timestamp()
    std = (standard_df
           .select(
               F.col("labor_standard_id"),
               F.col("standard_version").alias("labor_standard_version"),
               F.col("role_code"),
               F.col("demand_driver"),
               F.col("driver_units_per_labor_hour"),
               F.col("labor_hours_per_driver_unit"),
               F.col("minimum_headcount"),
               F.col("coverage_rationale"))
           .filter("is_current = TRUE"))

    df = (forecast_df
          .join(std, ["role_code", "demand_driver"], "inner")
          .withColumn("applied_labor_standard",
                      F.coalesce(
                          F.col("labor_hours_per_driver_unit"),
                          (F.lit(1.0) / F.col("driver_units_per_labor_hour")).cast("decimal(18,6)"))
                      .cast("decimal(18,6)"))
          .withColumn("required_labor_hours",
                      (F.col("forecast_driver_units") * F.col("applied_labor_standard"))
                      .cast("decimal(18,4)"))
          .withColumn("required_headcount",
                      F.greatest(
                          F.col("minimum_headcount").cast("decimal(18,4)"),
                          (F.col("required_labor_hours")
                           / (F.col("interval_minutes").cast("double") / F.lit(60.0)))
                          .cast("decimal(18,4)"))
                      .cast("decimal(18,4)"))
          .withColumn("workforce_labor_requirement_id",
                      F.concat(F.lit("WLR-"), F.col("workforce_demand_forecast_id")))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("driver_units_per_labor_hour", "labor_hours_per_driver_unit",
                "workforce_demand_forecast_id", "forecast_lower_bound",
                "forecast_upper_bound", "forecast_method", "model_version",
                "forecast_horizon_days", "forecast_origin_ts"))

    fqtn = f"{catalog}.{schema}.workforce_labor_requirement"
    return _write(spark, df, fqtn, WORKFORCE_LABOR_REQUIREMENT_COLUMNS, mode)


def generate_workforce_schedule_recommendation(spark, catalog, schema, cfg, mode,
                                               store_df, employee_df, base_currency):
    """A few proposed shifts resolved against the canonical-core labor employees."""
    seed = cfg["seed"]
    n = cfg["recommendations"]
    now = F.current_timestamp()
    today = F.current_date()
    from pyspark.sql.window import Window

    stores = store_df.select("store_sk", "store_id").orderBy("store_id").limit(2)
    store_count = stores.count()
    store_idx = stores.withColumn(
        "_st_idx", F.row_number().over(Window.orderBy("store_id")) - F.lit(1))

    ids = spark.range(n).withColumn(
        "workforce_schedule_recommendation_id",
        F.concat(F.lit("WSR-"), F.format_string("%05d", F.col("id") + F.lit(1))))
    df = (ids
          .withColumn("_st_idx",
                      (F.abs(F.hash(F.col("workforce_schedule_recommendation_id"), F.lit(seed)))
                       % F.lit(max(store_count, 1))).cast("int"))
          .join(F.broadcast(store_idx), "_st_idx", "left")
          .drop("_st_idx")
          .withColumn("workforce_optimization_run_id", F.lit(WOR_RUN_ID))
          .withColumn("employee_id",
                      F.concat(F.lit("EMP-"), F.format_string("%05d", F.col("id") + F.lit(1))))
          # Resolve employee_sk from the real labor.employee surrogate via the left join
          # below, so wsr_employee_fk_orphan actually asserts (a hardcoded NULL would leave
          # the check dormant-green). The join is left, so a proposed employee_id with no
          # current employee row still lands employee_sk NULL -- the conditional orphan check
          # (nullable _sk + an IS NOT NULL guard) tolerates exactly that shape. Do NOT also
          # add a placeholder employee_sk column before this join: employee_df already carries
          # employee_sk, so a second one makes the later select(*columns) AMBIGUOUS_REFERENCE.
          .join(F.broadcast(employee_df.select(
              F.col("employee_sk"), F.col("employee_id"))), "employee_id", "left")
          .withColumn("department_or_zone", F.lit("storewide"))
          .withColumn("role_code", _pick(WF_ROLES, seed, "wsr_role",
                                         F.col("workforce_schedule_recommendation_id")))
          .withColumn("business_date", F.date_add(today, F.lit(1)))
          .withColumn(
              "_base_ts",
              F.to_timestamp(F.concat(F.col("business_date").cast("string"), F.lit(" 09:00:00"))))
          .withColumn(
              "shift_start_ts",
              F.col("_base_ts")
              + F.expr("INTERVAL 1 MINUTE") * ((F.col("id") % F.lit(4)) * F.lit(120)))
          .withColumn(
              "shift_end_ts",
              F.col("shift_start_ts") + F.expr("INTERVAL 1 HOUR") * F.lit(4))
          .withColumn("assigned_hours", F.lit(4.0).cast("decimal(8,2)"))
          .withColumn("estimated_labor_cost",
                      (F.col("assigned_hours") * F.lit(18.50)).cast("decimal(18,2)"))
          .withColumn("currency_code", F.lit(base_currency))
          .withColumn("is_availability_ok", F.lit(True))
          .withColumn("is_skill_ok", F.lit(True))
          .withColumn("is_store_eligible_ok", F.lit(True))
          .withColumn("is_hours_cap_ok", F.lit(True))
          .withColumn("is_min_rest_ok", F.lit(True))
          .withColumn("recommendation_status", F.lit("proposed"))
          .withColumn("optimizer_status", F.lit("heuristic"))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("id", "business_date", "_base_ts"))

    fqtn = f"{catalog}.{schema}.workforce_schedule_recommendation"
    return _write(spark, df, fqtn, WORKFORCE_SCHEDULE_RECOMMENDATION_COLUMNS, mode)


def generate_workforce_coverage_exception(spark, catalog, schema, cfg, mode, store_df):
    """Coverage exceptions including at least one high-severity understaffed interval."""
    seed = cfg["seed"]
    n = cfg["exceptions"]
    now = F.current_timestamp()
    from pyspark.sql.window import Window

    stores = store_df.select("store_sk", "store_id").orderBy("store_id").limit(2)
    store_count = max(stores.count(), 1)
    store_idx = stores.withColumn(
        "_st_idx", F.row_number().over(Window.orderBy("store_id")) - F.lit(1))

    ids = spark.range(n).withColumn(
        "workforce_coverage_exception_id",
        F.concat(F.lit("WCE-"), F.format_string("%05d", F.col("id") + F.lit(1))))
    df = (ids
          .withColumn("_st_idx",
                      (F.abs(F.hash(F.col("workforce_coverage_exception_id"), F.lit(seed)))
                       % F.lit(store_count)).cast("int"))
          .join(F.broadcast(store_idx), "_st_idx", "left")
          .drop("_st_idx")
          .withColumn("workforce_optimization_run_id", F.lit(WOR_RUN_ID))
          .withColumn("business_date", F.date_add(F.current_date(), F.lit(1)))
          .withColumn(
              "_base_ts",
              F.to_timestamp(F.concat(F.col("business_date").cast("string"), F.lit(" 12:00:00"))))
          .withColumn(
              "interval_start_ts",
              F.col("_base_ts")
              + F.expr("INTERVAL 1 MINUTE") * (F.col("id") * F.lit(WF_INTERVAL_MINUTES)))
          .withColumn(
              "interval_end_ts",
              F.col("interval_start_ts")
              + F.expr("INTERVAL 1 MINUTE") * F.lit(WF_INTERVAL_MINUTES))
          .withColumn("department_or_zone", F.lit("storewide"))
          .withColumn("role_code", _pick(WF_ROLES, seed, "wce_role",
                                         F.col("workforce_coverage_exception_id")))
          # Force row 0 to high severity understaffing so demos always have a hotspot.
          .withColumn("severity",
                      F.when(F.col("id") == 0, F.lit("high"))
                       .otherwise(_pick(WF_SEVERITIES, seed, "wce_sev",
                                        F.col("workforce_coverage_exception_id"))))
          .withColumn("required_headcount",
                      (F.lit(3.0) + _frac(seed, "wce_req",
                                          F.col("workforce_coverage_exception_id")) * F.lit(2.0))
                      .cast("decimal(18,4)"))
          .withColumn("scheduled_headcount",
                      F.greatest(
                          F.lit(0.0),
                          F.col("required_headcount")
                          - (F.lit(1.0) + _frac(seed, "wce_short",
                                                F.col("workforce_coverage_exception_id")))
                      ).cast("decimal(18,4)"))
          .withColumn("shortfall_headcount",
                      (F.col("required_headcount") - F.col("scheduled_headcount"))
                      .cast("decimal(18,4)"))
          .withColumn("exception_explanation",
                      F.concat(F.lit("Understaffed "), F.col("role_code"),
                               F.lit(" interval; shortfall="),
                               F.col("shortfall_headcount").cast("string")))
          .withColumn("suggested_action",
                      _pick(WF_ACTIONS, seed, "wce_act",
                            F.col("workforce_coverage_exception_id")))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("id", "_base_ts"))

    fqtn = f"{catalog}.{schema}.workforce_coverage_exception"
    return _write(spark, df, fqtn, WORKFORCE_COVERAGE_EXCEPTION_COLUMNS, mode)


# ---- entry point ----

def run(ctx):
    # The registry declares a `labor` dependency (GenSpec depends_on) even though this
    # function never reads a labor table directly. The dependency is for WAVE ORDERING:
    # the workforce gold views and this package's DQ checks resolve against
    # canonical-core labor (employee, labor_schedule, labor_actuals), so labor must be
    # populated before anything downstream of this generator runs. Dropping it from the
    # registry would let predictive_operations schedule into an earlier wave and leave
    # those gold reads and checks against empty labor tables (a vacuous pass).
    spark, catalog, mode = ctx.spark, ctx.catalog, ctx.mode
    predops_schema = ctx.schemas["predops"]
    equipment_schema = ctx.schemas["equipment"]
    store_schema = ctx.schemas["store"]
    labor_schema = ctx.schemas["labor"]
    base_currency = ctx.base_currency
    cfg = load_config()

    # Reads the canonical-core equipment + store + labor dimensions (run those generators first).
    equipment_df = spark.table(f"{catalog}.{equipment_schema}.equipment").filter("is_current = TRUE")
    store_df = spark.table(f"{catalog}.{store_schema}.store").filter("is_current = TRUE")
    employee_df = spark.table(f"{catalog}.{labor_schema}.employee").filter("is_current = TRUE")

    # In-Store Equipment Maintenance use case
    wo_df = generate_work_orders(spark, catalog, predops_schema, cfg, mode, equipment_df, base_currency)
    generate_work_order_lines(spark, catalog, predops_schema, cfg, mode, wo_df, base_currency)
    generate_maintenance_schedules(spark, catalog, predops_schema, cfg, mode, equipment_df, base_currency)

    # Store Performance use case
    generate_store_risk_scores(spark, catalog, predops_schema, cfg, mode, store_df)

    # Workforce Optimization use case (ADR 0043)
    ls_df = generate_labor_standards(spark, catalog, predops_schema, cfg, mode)
    generate_workforce_optimization_run(spark, catalog, predops_schema, cfg, mode, base_currency)
    fcst_df = generate_workforce_demand_forecast(
        spark, catalog, predops_schema, cfg, mode, store_df)
    generate_workforce_labor_requirement(
        spark, catalog, predops_schema, cfg, mode, fcst_df, ls_df)
    generate_workforce_schedule_recommendation(
        spark, catalog, predops_schema, cfg, mode, store_df, employee_df, base_currency)
    generate_workforce_coverage_exception(
        spark, catalog, predops_schema, cfg, mode, store_df)
    print("Predictive Operations generation complete "
          "(equipment maintenance + store performance + workforce optimization).")


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
