# ============================================================
# ORDM · Synthetic data · Labor generator
# Version: 0.5
# Generated: 2026-08-10
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-08-10
# ============================================================
# Populates the canonical-core labor tables: employee, employee_skill,
# employee_availability, employee_store_eligibility, labor_schedule,
# labor_actuals. Requires canonical-core store tables (run the
# trade_promotion generator first, which provides stores).
# Pseudonymous IDs only (EMP-00001) — no personal names or contact PII.
# Shared helpers come from _common (extended, not forked).
# Volumes come from runtime/synthetic-data/seeds.yaml.
# ============================================================

import os
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

try:
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _pick, _frac, _write)
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _pick, _frac, _write)

# ------------------------------------------------------------
# Column contracts -- MUST match the DDL (minus IDENTITY *_sk).
# ------------------------------------------------------------
EMPLOYEE_COLUMNS = [
    "employee_id", "home_store_sk", "home_store_id",
    "primary_role_code", "employment_status", "employment_type",
    "hourly_labor_cost", "currency_code",
    "max_daily_hours", "max_weekly_hours", "min_rest_hours",
    "preferred_shift_start_local", "preferred_shift_end_local",
    "hire_date", "termination_date",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
EMPLOYEE_SKILL_COLUMNS = [
    "employee_skill_id", "employee_sk", "employee_id",
    "skill_code", "proficiency_level", "is_active",
    "effective_from_date", "effective_to_date",
    "record_source", "load_timestamp",
]
EMPLOYEE_AVAILABILITY_COLUMNS = [
    "employee_availability_id", "employee_sk", "employee_id",
    "availability_date", "available_start_ts", "available_end_ts",
    "is_available", "availability_type",
    "record_source", "load_timestamp",
]
EMPLOYEE_STORE_ELIGIBILITY_COLUMNS = [
    "employee_store_eligibility_id", "employee_sk", "employee_id",
    "store_sk", "store_id", "is_primary", "is_active",
    "effective_from_date", "effective_to_date",
    "record_source", "load_timestamp",
]
LABOR_SCHEDULE_COLUMNS = [
    "labor_schedule_id", "employee_sk", "employee_id",
    "store_sk", "store_id", "role_code", "department_or_zone",
    "business_date", "shift_start_ts", "shift_end_ts", "scheduled_hours",
    "schedule_status", "schedule_source",
    "record_source", "load_timestamp",
]
LABOR_ACTUALS_COLUMNS = [
    "labor_actuals_id", "employee_sk", "employee_id",
    "store_sk", "store_id", "labor_schedule_sk", "labor_schedule_id",
    "role_code", "department_or_zone", "business_date",
    "clock_in_ts", "clock_out_ts", "worked_hours", "actuals_status",
    "record_source", "load_timestamp",
]

# Closed enums — values must be subsets of DDL "Allowed values" comments.
PRIMARY_ROLE_CODES = ["cashier", "sales_associate", "fulfillment", "inventory", "supervisor"]
ROLE_CODES = ["cashier", "sales_associate", "fulfillment", "inventory", "supervisor"]
EMPLOYMENT_STATUS = ["active", "leave", "terminated"]
EMPLOYMENT_TYPES = ["full_time", "part_time", "seasonal", "contractor"]
SKILL_CODES = [
    "cashier", "sales_associate", "fulfillment", "inventory",
    "supervisor", "food_handler", "pharmacy_tech",
]
PROFICIENCY_LEVELS = ["trainee", "qualified", "expert"]
AVAILABILITY_TYPES = ["preferred", "available", "unavailable", "time_off"]
SCHEDULE_STATUS = ["draft", "published", "cancelled"]
SCHEDULE_SOURCES = ["workforce_system", "manager", "recommendation_accepted", "other"]
ACTUALS_STATUS = ["approved", "pending", "rejected", "adjusted"]
ZONES = ["storewide", "front_end", "grocery", "general_merchandise", "backroom"]

# Weighted picks for generation (still closed-enum members).
EMPLOYMENT_STATUS_WEIGHTED = [
    "active", "active", "active", "active", "active", "active", "leave", "terminated",
]
EMPLOYMENT_TYPES_WEIGHTED = [
    "full_time", "full_time", "full_time", "part_time", "part_time", "seasonal", "contractor",
]
SCHEDULE_STATUS_WEIGHTED = ["published", "published", "published", "draft", "cancelled"]
ACTUALS_STATUS_WEIGHTED = ["approved", "approved", "approved", "pending", "adjusted", "rejected"]


def load_config():
    c = load_domain_config("labor")
    vols = c.get("volumes", {}) or {}
    return {
        "seed": c.get("seed", 14014),
        "employees": vols.get("employees", 60),
        "schedules_per_employee": vols.get("schedules_per_employee", 4),
        "availability_days": vols.get("availability_days", 14),
    }


def generate_employees(spark, catalog, schema, store_schema, cfg, mode):
    """Generate pseudonymous associate master rows (SCD2, all current)."""
    seed = cfg["seed"]
    n = cfg["employees"]
    now = F.current_timestamp()
    today = F.current_date()
    from pyspark.sql.window import Window

    store_df = spark.table(f"{catalog}.{store_schema}.store").filter("is_current = TRUE")
    store_count = store_df.count()
    if store_count == 0:
        raise RuntimeError(
            f"no current stores in {catalog}.{store_schema}.store — "
            "run the trade_promotion generator first"
        )
    store_indexed = store_df.select(
        F.col("store_sk").alias("_st_sk"), F.col("store_id").alias("_st_id")
    ).withColumn("_st_idx", F.row_number().over(Window.orderBy("_st_sk")) - F.lit(1))

    ids = spark.range(n).withColumn(
        "employee_id",
        F.concat(F.lit("EMP-"), F.format_string("%05d", F.col("id") + F.lit(1))),
    )

    df = ids.withColumn(
        "_st_idx",
        (F.abs(F.hash(F.col("employee_id"), F.lit(seed))) % F.lit(store_count)).cast("int"),
    )
    df = df.join(F.broadcast(store_indexed), "_st_idx", "left").drop("_st_idx")
    df = df.withColumnRenamed("_st_sk", "home_store_sk").withColumnRenamed("_st_id", "home_store_id")

    df = (
        df
        .withColumn("primary_role_code", _pick(PRIMARY_ROLE_CODES, seed, "role", F.col("employee_id")))
        .withColumn("employment_status", _pick(EMPLOYMENT_STATUS_WEIGHTED, seed, "estatus", F.col("employee_id")))
        .withColumn("employment_type", _pick(EMPLOYMENT_TYPES_WEIGHTED, seed, "etype", F.col("employee_id")))
        .withColumn(
            "hourly_labor_cost",
            (
                F.lit(12.0)
                + (F.abs(F.hash(F.col("employee_id"), F.lit(seed + 1))) % F.lit(1600)).cast("double") / F.lit(100.0)
            ).cast("decimal(18,4)"),
        )
        .withColumn("currency_code", F.lit("USD"))
        .withColumn(
            "max_daily_hours",
            F.when(F.col("employment_type") == "full_time", F.lit(8.0))
             .when(F.col("employment_type") == "part_time", F.lit(6.0))
             .otherwise(F.lit(8.0))
             .cast("decimal(6,2)"),
        )
        .withColumn(
            "max_weekly_hours",
            F.when(F.col("employment_type") == "full_time", F.lit(40.0))
             .when(F.col("employment_type") == "part_time", F.lit(24.0))
             .otherwise(F.lit(32.0))
             .cast("decimal(6,2)"),
        )
        .withColumn("min_rest_hours", F.lit(8.0).cast("decimal(6,2)"))
        .withColumn("preferred_shift_start_local", F.lit("09:00"))
        .withColumn("preferred_shift_end_local", F.lit("17:00"))
        .withColumn(
            "hire_date",
            F.date_sub(
                today,
                (F.abs(F.hash(F.col("employee_id"), F.lit(seed + 2))) % F.lit(1500) + F.lit(30)).cast("int"),
            ),
        )
        .withColumn(
            "termination_date",
            F.when(
                F.col("employment_status") == "terminated",
                F.date_sub(today, (F.abs(F.hash(F.col("employee_id"), F.lit(seed + 3))) % F.lit(90)).cast("int")),
            ).otherwise(F.lit(None).cast("date")),
        )
        .withColumn("effective_from_date", F.col("hire_date"))
        .withColumn("effective_to_date", F.lit(None).cast("date"))
        .withColumn("is_current", F.lit(True))
        .withColumn("created_timestamp", now)
        .withColumn("source_updated_timestamp", now)
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn("load_timestamp", now)
        .drop("id")
    )

    fqtn = f"{catalog}.{schema}.employee"
    return _write(spark, df, fqtn, EMPLOYEE_COLUMNS, mode)


def generate_employee_skills(spark, catalog, schema, cfg, mode, employee_df):
    """One primary-role skill plus a deterministic optional secondary skill."""
    seed = cfg["seed"]
    now = F.current_timestamp()

    base = employee_df.select("employee_sk", "employee_id", "primary_role_code", "hire_date")

    primary = (
        base
        .withColumn("skill_code", F.col("primary_role_code"))
        .withColumn("proficiency_level", _pick(PROFICIENCY_LEVELS, seed, "prof", F.col("employee_id")))
        .withColumn("is_active", F.lit(True))
        .withColumn("effective_from_date", F.col("hire_date"))
        .withColumn("effective_to_date", F.lit(None).cast("date"))
        .withColumn(
            "employee_skill_id",
            F.concat(F.col("employee_id"), F.lit("|"), F.col("skill_code")),
        )
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn("load_timestamp", now)
        .drop("primary_role_code", "hire_date")
    )

    # ~40% of associates get a secondary skill (food_handler / pharmacy_tech / cross-role).
    secondary_pool = ["food_handler", "pharmacy_tech", "fulfillment", "inventory", "cashier"]
    secondary = (
        base
        .filter(_frac(seed, "secskill", F.col("employee_id")) < F.lit(0.40))
        .withColumn("skill_code", _pick(secondary_pool, seed, "sec", F.col("employee_id")))
        .filter(F.col("skill_code") != F.col("primary_role_code"))
        .withColumn("proficiency_level", _pick(PROFICIENCY_LEVELS, seed, "secprof", F.col("employee_id")))
        .withColumn("is_active", F.lit(True))
        .withColumn("effective_from_date", F.col("hire_date"))
        .withColumn("effective_to_date", F.lit(None).cast("date"))
        .withColumn(
            "employee_skill_id",
            F.concat(F.col("employee_id"), F.lit("|"), F.col("skill_code")),
        )
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn("load_timestamp", now)
        .drop("primary_role_code", "hire_date")
    )

    df = primary.unionByName(secondary)
    fqtn = f"{catalog}.{schema}.employee_skill"
    return _write(spark, df, fqtn, EMPLOYEE_SKILL_COLUMNS, mode)


def generate_employee_availability(spark, catalog, schema, cfg, mode, employee_df):
    """Availability windows for the next N days (UTC daytime blocks)."""
    seed = cfg["seed"]
    days = cfg["availability_days"]
    now = F.current_timestamp()
    today = F.current_date()

    active = employee_df.filter("employment_status = 'active'").select(
        "employee_sk", "employee_id"
    )
    day_idx = spark.range(days).withColumnRenamed("id", "day_offset")
    df = active.crossJoin(day_idx)

    df = (
        df
        .withColumn("availability_date", F.date_add(today, F.col("day_offset").cast("int")))
        .withColumn(
            "is_time_off",
            _frac(seed, "pto", F.col("employee_id"), F.col("day_offset")) < F.lit(0.08),
        )
        .withColumn(
            "available_start_ts",
            F.to_timestamp(F.concat(F.col("availability_date").cast("string"), F.lit(" 08:00:00"))),
        )
        .withColumn(
            "available_end_ts",
            F.to_timestamp(F.concat(F.col("availability_date").cast("string"), F.lit(" 20:00:00"))),
        )
        .withColumn(
            "is_available",
            F.when(F.col("is_time_off"), F.lit(False)).otherwise(F.lit(True)),
        )
        .withColumn(
            "availability_type",
            F.when(F.col("is_time_off"), F.lit("time_off"))
             .when(_frac(seed, "pref", F.col("employee_id"), F.col("day_offset")) < F.lit(0.25), F.lit("preferred"))
             .otherwise(F.lit("available")),
        )
        .withColumn(
            "employee_availability_id",
            F.concat(
                F.col("employee_id"), F.lit("|"),
                F.col("availability_date").cast("string"), F.lit("|"),
                F.date_format(F.col("available_start_ts"), "HHmm"),
            ),
        )
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn("load_timestamp", now)
        .drop("day_offset", "is_time_off")
    )

    fqtn = f"{catalog}.{schema}.employee_availability"
    return _write(spark, df, fqtn, EMPLOYEE_AVAILABILITY_COLUMNS, mode)


def generate_employee_store_eligibility(spark, catalog, schema, cfg, mode, employee_df):
    """Home-store eligibility row per associate (is_primary = TRUE)."""
    now = F.current_timestamp()
    df = (
        employee_df.select(
            "employee_sk", "employee_id",
            F.col("home_store_sk").alias("store_sk"),
            F.col("home_store_id").alias("store_id"),
            "hire_date",
        )
        .withColumn("is_primary", F.lit(True))
        .withColumn("is_active", F.lit(True))
        .withColumn("effective_from_date", F.col("hire_date"))
        .withColumn("effective_to_date", F.lit(None).cast("date"))
        .withColumn(
            "employee_store_eligibility_id",
            F.concat(F.col("employee_id"), F.lit("|"), F.col("store_id")),
        )
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn("load_timestamp", now)
        .drop("hire_date")
    )
    fqtn = f"{catalog}.{schema}.employee_store_eligibility"
    return _write(spark, df, fqtn, EMPLOYEE_STORE_ELIGIBILITY_COLUMNS, mode)


def generate_labor_schedules(spark, catalog, schema, cfg, mode, employee_df):
    """Published / draft / cancelled shifts over the availability horizon."""
    seed = cfg["seed"]
    n_sched = cfg["schedules_per_employee"]
    days = cfg["availability_days"]
    now = F.current_timestamp()
    today = F.current_date()

    active = employee_df.filter("employment_status = 'active'").select(
        "employee_sk", "employee_id", "home_store_sk", "home_store_id", "primary_role_code"
    )
    sched_idx = spark.range(n_sched).withColumnRenamed("id", "sched_idx")
    df = active.crossJoin(sched_idx)

    df = (
        df
        .withColumn(
            "day_offset",
            (F.abs(F.hash(F.col("employee_id"), F.col("sched_idx"), F.lit(seed))) % F.lit(days)).cast("int"),
        )
        .withColumn("business_date", F.date_add(today, F.col("day_offset")))
        .withColumn(
            "shift_start_hour",
            (F.abs(F.hash(F.col("employee_id"), F.col("sched_idx"), F.lit(seed + 1))) % F.lit(4) + F.lit(8)).cast("int"),
        )
        .withColumn(
            "shift_len_hours",
            F.when(
                (F.abs(F.hash(F.col("employee_id"), F.col("sched_idx"), F.lit(seed + 2))) % F.lit(2)) == F.lit(0),
                F.lit(4),
            ).otherwise(F.lit(8)),
        )
        .withColumn(
            "shift_start_ts",
            F.to_timestamp(
                F.concat(
                    F.col("business_date").cast("string"), F.lit(" "),
                    F.lpad(F.col("shift_start_hour").cast("string"), 2, "0"), F.lit(":00:00"),
                )
            ),
        )
        .withColumn(
            "shift_end_ts",
            F.col("shift_start_ts") + F.expr("INTERVAL 1 HOUR") * F.col("shift_len_hours"),
        )
        .withColumn("scheduled_hours", F.col("shift_len_hours").cast("decimal(8,2)"))
        .withColumn("store_sk", F.col("home_store_sk"))
        .withColumn("store_id", F.col("home_store_id"))
        .withColumn("role_code", F.col("primary_role_code"))
        .withColumn("department_or_zone", _pick(ZONES, seed, "zone", F.col("employee_id"), F.col("sched_idx")))
        .withColumn("schedule_status", _pick(SCHEDULE_STATUS_WEIGHTED, seed, "sstat", F.col("employee_id"), F.col("sched_idx")))
        .withColumn("schedule_source", _pick(SCHEDULE_SOURCES, seed, "ssrc", F.col("employee_id"), F.col("sched_idx")))
        .withColumn(
            "labor_schedule_id",
            F.concat(
                F.col("employee_id"), F.lit("|"),
                F.col("business_date").cast("string"), F.lit("|"),
                F.lpad(F.col("shift_start_hour").cast("string"), 2, "0"), F.lit("|"),
                F.col("sched_idx").cast("string"),
            ),
        )
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn("load_timestamp", now)
        .drop(
            "home_store_sk", "home_store_id", "primary_role_code",
            "sched_idx", "day_offset", "shift_start_hour", "shift_len_hours",
        )
    )

    fqtn = f"{catalog}.{schema}.labor_schedule"
    return _write(spark, df, fqtn, LABOR_SCHEDULE_COLUMNS, mode)


def generate_labor_actuals(spark, catalog, schema, cfg, mode, schedule_df):
    """Timecard actuals mapped to published schedules (with small clock drift)."""
    seed = cfg["seed"]
    now = F.current_timestamp()

    published = schedule_df.filter("schedule_status = 'published'").select(
        "labor_schedule_sk", "labor_schedule_id",
        "employee_sk", "employee_id", "store_sk", "store_id",
        "role_code", "department_or_zone", "business_date",
        "shift_start_ts", "shift_end_ts", "scheduled_hours",
    )

    df = (
        published
        .withColumn(
            "drift_in_min",
            (F.abs(F.hash(F.col("labor_schedule_id"), F.lit(seed + 5))) % F.lit(11) - F.lit(5)).cast("int"),
        )
        .withColumn(
            "drift_out_min",
            (F.abs(F.hash(F.col("labor_schedule_id"), F.lit(seed + 6))) % F.lit(11) - F.lit(5)).cast("int"),
        )
        .withColumn(
            "clock_in_ts",
            F.col("shift_start_ts") + F.expr("INTERVAL 1 MINUTE") * F.col("drift_in_min"),
        )
        .withColumn(
            "clock_out_ts",
            F.col("shift_end_ts") + F.expr("INTERVAL 1 MINUTE") * F.col("drift_out_min"),
        )
        # Ensure end after start even with adverse drift.
        .withColumn(
            "clock_out_ts",
            F.when(F.col("clock_out_ts") <= F.col("clock_in_ts"),
                   F.col("clock_in_ts") + F.expr("INTERVAL 1 HOUR") * F.col("scheduled_hours"))
             .otherwise(F.col("clock_out_ts")),
        )
        .withColumn(
            "worked_hours",
            (
                (F.unix_timestamp(F.col("clock_out_ts")) - F.unix_timestamp(F.col("clock_in_ts")))
                / F.lit(3600.0)
            ).cast("decimal(8,2)"),
        )
        .withColumn("actuals_status", _pick(ACTUALS_STATUS_WEIGHTED, seed, "astat", F.col("labor_schedule_id")))
        .withColumn(
            "labor_actuals_id",
            F.concat(F.lit("ACT|"), F.col("labor_schedule_id")),
        )
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn("load_timestamp", now)
        .drop("shift_start_ts", "shift_end_ts", "scheduled_hours", "drift_in_min", "drift_out_min")
    )

    fqtn = f"{catalog}.{schema}.labor_actuals"
    return _write(spark, df, fqtn, LABOR_ACTUALS_COLUMNS, mode)


# ---- entry point ----

def run(ctx):
    spark, catalog, mode = ctx.spark, ctx.catalog, ctx.mode
    labor_schema = ctx.schemas["labor"]
    store_schema = ctx.schemas["store"]
    cfg = load_config()

    employee_df = generate_employees(spark, catalog, labor_schema, store_schema, cfg, mode)
    generate_employee_skills(spark, catalog, labor_schema, cfg, mode, employee_df)
    generate_employee_availability(spark, catalog, labor_schema, cfg, mode, employee_df)
    generate_employee_store_eligibility(spark, catalog, labor_schema, cfg, mode, employee_df)
    schedule_df = generate_labor_schedules(spark, catalog, labor_schema, cfg, mode, employee_df)
    generate_labor_actuals(spark, catalog, labor_schema, cfg, mode, schedule_df)
    print("Labor generation complete.")


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
