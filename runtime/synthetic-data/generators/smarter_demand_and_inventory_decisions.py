# ============================================================
# ORDM · Synthetic data · Smarter Demand and Inventory Decisions
# Version: 0.5
# Generated: 2026-07-21
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-07-21
# ============================================================
# Populates extension tables for demand forecasting, inventory
# optimization, and out-of-stocks optimization. Requires canonical-core
# product, store, sales (transaction), and inventory domains.
# Schema access goes through ctx.fq(<key>, <table>) so the registry's
# declared provides/depends_on is validated against real I/O.
# ============================================================

import os
import sys
from decimal import Decimal as D

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window

try:
    from _common import RECORD_SOURCE, get_param, load_domain_config, _write, _pick
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import RECORD_SOURCE, get_param, load_domain_config, _write, _pick

# ------------------------------------------------------------
# Column contracts -- MUST match the DDL (minus IDENTITY *_sk).
# ------------------------------------------------------------
PLANNING_UNIT_COLUMNS = [
    "planning_unit_id", "grain_type", "product_sk", "product_id", "store_sk", "store_id",
    "account_sk", "account_id", "planning_hierarchy_level", "is_active",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
PLANNING_UNIT_SEGMENT_COLUMNS = [
    "segment_id", "planning_unit_sk", "planning_unit_id", "fiscal_period_key",
    "abc_class", "xyz_class", "volume_tier", "cluster_id",
    "cumulative_volume_pct", "coefficient_of_variation",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
FORECAST_MODEL_RUN_COLUMNS = [
    "model_run_id", "model_name", "model_version", "hierarchy_level",
    "training_start_date", "training_end_date", "scored_at_timestamp",
    "is_champion", "accuracy_score", "bias_pct",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
DEMAND_FORECAST_COLUMNS = [
    "demand_forecast_id", "model_run_sk", "model_run_id", "planning_unit_sk", "planning_unit_id",
    "forecast_date_key", "forecast_horizon_type", "forecast_lag_weeks", "forecast_origin_date_key",
    "forecast_quantity", "forecast_lower_bound", "forecast_upper_bound", "unit_of_measure",
    "record_source", "load_timestamp",
]
FORECAST_COMPONENT_COLUMNS = [
    "forecast_component_id", "demand_forecast_sk", "demand_forecast_id",
    "component_type", "component_quantity",
    "record_source", "load_timestamp",
]
FORECAST_ADJUSTMENT_COLUMNS = [
    "forecast_adjustment_id", "planning_unit_sk", "planning_unit_id", "forecast_date_key",
    "adjustment_quantity", "adjustment_method", "adjustment_reason_code",
    "adjusted_by", "adjusted_at_timestamp", "approval_status",
    "record_source", "load_timestamp",
]
FORECAST_ACCURACY_COLUMNS = [
    "forecast_accuracy_id", "planning_unit_sk", "planning_unit_id", "forecast_date_key",
    "actual_quantity", "forecast_quantity", "effective_forecast_quantity", "lag_weeks",
    "accuracy_pct", "bias_pct", "mape", "is_stockout_censored",
    "record_source", "load_timestamp",
]
SERVICE_LEVEL_TARGET_COLUMNS = [
    "service_level_target_id", "abc_class", "xyz_class", "service_measure_type",
    "target_service_level_pct", "target_fill_rate_pct",
    "target_days_of_supply", "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
SERVICE_LEVEL_Z_COLUMNS = [
    "service_level_z_id", "service_level_pct", "z_score", "loss_function_l_z",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
INVENTORY_POLICY_COLUMNS = [
    "inventory_policy_id", "planning_unit_sk", "planning_unit_id", "policy_type",
    "safety_stock_quantity", "reorder_point_quantity", "min_quantity", "max_quantity",
    "order_up_to_quantity", "review_period_days", "lead_time_days",
    "service_level_target_sk", "service_level_target_id", "policy_source",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
INVENTORY_RECOMMENDATION_COLUMNS = [
    "inventory_recommendation_id", "planning_unit_sk", "planning_unit_id",
    "recommendation_date_key", "recommended_order_quantity", "recommended_order_date_key",
    "projected_days_of_supply", "projected_days_of_supply_after",
    "recommendation_reason", "recommendation_status",
    "inventory_policy_sk", "inventory_policy_id",
    "record_source", "load_timestamp",
]
OOS_EVENT_COLUMNS = [
    "oos_event_id", "product_sk", "product_id", "store_sk", "store_id",
    "oos_start_date_key", "oos_end_date_key", "oos_duration_days",
    "detection_method", "oos_cause", "oos_severity", "is_promo_period",
    "stockout_pct_total", "competitor_spillover_flag", "data_quality_flag",
    "is_preventable", "linked_disruption_event_id",
    "record_source", "load_timestamp",
]
LOST_SALES_COLUMNS = [
    "lost_sales_estimate_id", "oos_event_sk", "oos_event_id", "estimate_date_key",
    "actual_units_sold", "expected_units_demand", "lost_units", "estimation_method",
    "censoring_adjusted", "lost_revenue", "lost_margin", "currency_code", "confidence_score",
    "record_source", "load_timestamp",
]
ORDER_FORECAST_COLUMNS = [
    "order_forecast_id", "planning_unit_sk", "planning_unit_id", "order_date_key",
    "need_by_date_key", "order_forecast_quantity", "order_type", "source_location_id",
    "destination_store_sk", "destination_store_id", "demand_forecast_sk", "demand_forecast_id",
    "inventory_policy_sk", "inventory_policy_id",
    "record_source", "load_timestamp",
]
INVENTORY_POLICY_CALC_COLUMNS = [
    "policy_calculation_id", "inventory_policy_sk", "inventory_policy_id",
    "calculated_at_timestamp", "avg_daily_demand", "demand_std_dev", "forecast_bias_pct",
    "lead_time_days", "lead_time_std_dev", "safety_stock_formula", "z_score",
    "supplier_reliability_multiplier",
    "record_source", "load_timestamp",
]
DEMAND_SENSING_COLUMNS = [
    "demand_sensing_signal_id", "planning_unit_sk", "planning_unit_id", "product_sk", "product_id",
    "store_sk", "store_id", "signal_timestamp", "signal_category", "signal_type",
    "signal_description", "severity", "resolved_flag", "resolved_at_timestamp",
    "linked_oos_event_sk",
    "record_source", "load_timestamp",
]
OOS_RECOVERY_COLUMNS = [
    "oos_recovery_action_id", "oos_event_sk", "oos_event_id", "action_type",
    "recommended_quantity", "recommended_action_date_key", "estimated_recovery_date_key",
    "estimated_revenue_recovery", "estimated_margin_recovery", "recoverability_probability",
    "actual_revenue_recovered", "time_to_recover_days", "currency_code", "action_status",
    "inventory_recommendation_sk", "inventory_recommendation_id", "linked_po_line_sk",
    "record_source", "load_timestamp",
]

ABC = ["A", "B", "C"]
ADJUSTMENT_REASONS = ["promo_not_in_model", "new_listing", "supply_constraint"]
SENSING_CATEGORIES = ["supply", "promo", "transport", "weather"]
XYZ = ["X", "Y", "Z"]
HORIZONS = ["short_term", "mid_term", "backtest"]
COMPONENTS = ["base", "promo", "price", "holiday", "residual"]
MODELS = ["lightgbm", "prophet", "arima"]


def load_config():
    c = load_domain_config("smarter_demand_and_inventory_decisions")
    vols = c.get("volumes", {}) or {}
    return {
        "seed": c.get("seed", 11011),
        "planning_units": vols.get("planning_units", 200),
        "forecasts": vols.get("forecasts", 500),
        "oos_events": vols.get("oos_events", 30),
    }


def generate_planning_units(ctx, prod_df, store_df, cfg, seed):
    n = min(cfg["planning_units"], prod_df.count() * store_df.count())
    pairs = (prod_df.crossJoin(store_df)
             .withColumn("_rank", F.row_number().over(
                 Window.orderBy(F.hash(F.col("product_id"), F.col("store_id")))))
             .filter(F.col("_rank") <= n)
             .drop("_rank"))
    df = (pairs
          .withColumn("planning_unit_id",
                      F.concat(F.lit("PU-"), F.col("product_id"), F.lit("-"), F.col("store_id")))
          .withColumn("grain_type", F.lit("store_sku"))
          .withColumn("account_sk", F.lit(None).cast("bigint"))
          .withColumn("account_id", F.lit(None).cast("string"))
          .withColumn("planning_hierarchy_level", F.lit("store_sku"))
          .withColumn("is_active", F.lit(True))
          .withColumn("created_timestamp", F.current_timestamp())
          .withColumn("source_updated_timestamp", F.current_timestamp())
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.current_timestamp()))
    return _write(ctx.spark, df, ctx.fq("sdi", "planning_unit"), PLANNING_UNIT_COLUMNS, ctx.mode)


def generate_segments(ctx, pu_df, seed):
    df = (pu_df
          .withColumn("segment_id", F.concat(F.col("planning_unit_id"), F.lit("|202628")))
          .withColumn("fiscal_period_key", F.lit(202628))
          .withColumn("abc_class", _pick(ABC, seed, "abc", F.col("planning_unit_id")))
          .withColumn("xyz_class", _pick(XYZ, seed, "xyz", F.col("planning_unit_id")))
          .withColumn("volume_tier", F.lit("medium"))
          .withColumn("cluster_id", F.concat(F.col("abc_class"), F.lit("_"), F.col("xyz_class")))
          .withColumn("cumulative_volume_pct",
                      (F.abs(F.hash(F.col("planning_unit_id"))) % 100) / 100.0)
          .withColumn("coefficient_of_variation",
                      (F.abs(F.hash(F.col("planning_unit_id"), F.lit("cv"))) % 150) / 100.0)
          .withColumn("created_timestamp", F.current_timestamp())
          .withColumn("source_updated_timestamp", F.current_timestamp())
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.current_timestamp()))
    return _write(ctx.spark, df, ctx.fq("sdi", "planning_unit_segment"),
                  PLANNING_UNIT_SEGMENT_COLUMNS, ctx.mode)


def generate_model_runs(ctx):
    now = F.current_timestamp()
    rows = [(f"MR-{m.upper()}", m, "1.0.0", "store_sku") for m in MODELS]
    df = ctx.spark.createDataFrame(
        rows, "model_run_id STRING, model_name STRING, model_version STRING, hierarchy_level STRING")
    df = (df
          .withColumn("training_start_date", F.lit("2024-01-01").cast("date"))
          .withColumn("training_end_date", F.lit("2025-12-31").cast("date"))
          .withColumn("scored_at_timestamp", now)
          .withColumn("is_champion", F.when(F.col("model_name") == "lightgbm", True).otherwise(False))
          .withColumn("accuracy_score", F.lit(0.78))
          .withColumn("bias_pct", F.lit(1.5))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))
    return _write(ctx.spark, df, ctx.fq("sdi", "forecast_model_run"),
                  FORECAST_MODEL_RUN_COLUMNS, ctx.mode)


def generate_demand_forecasts(ctx, pu_df, mr_df, cfg, seed):
    n = cfg["forecasts"]
    champion = mr_df.filter("is_champion = true").first()
    mr_sk, mr_id = champion["model_run_sk"], champion["model_run_id"]
    pu_count = pu_df.count()
    base = (ctx.spark.range(n)
            .withColumn("demand_forecast_id",
                        F.concat(F.lit("DF-"), F.format_string("%06d", F.col("id") + 1)))
            .withColumn("_pu_idx", (F.abs(F.hash(F.col("id"))) % pu_count).cast("int")))
    pu_indexed = pu_df.withColumn("_pu_idx", F.row_number().over(Window.orderBy("planning_unit_sk")) - 1)
    df = (base.join(pu_indexed, "_pu_idx", "inner")
          .withColumn("model_run_sk", F.lit(mr_sk))
          .withColumn("model_run_id", F.lit(mr_id))
          .withColumn("forecast_date_key",
                      F.date_add(F.lit("2026-01-01").cast("date"), (F.col("id") % 90).cast("int")))
          .withColumn("forecast_horizon_type", _pick(HORIZONS, seed, "hz", F.col("id")))
          .withColumn("forecast_lag_weeks", F.lit(4))
          .withColumn("forecast_origin_date_key", F.date_sub(F.col("forecast_date_key"), 28))
          .withColumn("forecast_quantity", (F.abs(F.hash(F.col("id"))) % 500 + 10).cast("decimal(12,3)"))
          .withColumn("forecast_lower_bound", (F.col("forecast_quantity") * 0.9).cast("decimal(12,3)"))
          .withColumn("forecast_upper_bound", (F.col("forecast_quantity") * 1.1).cast("decimal(12,3)"))
          .withColumn("unit_of_measure", F.lit("each"))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.current_timestamp())
          .drop("id", "_pu_idx"))
    return _write(ctx.spark, df, ctx.fq("sdi", "demand_forecast"), DEMAND_FORECAST_COLUMNS, ctx.mode)


def generate_forecast_components(ctx, df_df):
    exploded = df_df.select("demand_forecast_sk", "demand_forecast_id", "forecast_quantity")
    parts = []
    for ct in COMPONENTS:
        parts.append(exploded
                     .withColumn("forecast_component_id",
                                 F.concat(F.col("demand_forecast_id"), F.lit(f"|{ct}")))
                     .withColumn("component_type", F.lit(ct))
                     .withColumn("component_quantity",
                                 (F.col("forecast_quantity") / len(COMPONENTS)).cast("decimal(12,3)"))
                     .withColumn("record_source", F.lit(RECORD_SOURCE))
                     .withColumn("load_timestamp", F.current_timestamp()))
    out = parts[0]
    for p in parts[1:]:
        out = out.unionByName(p)
    return _write(ctx.spark, out, ctx.fq("sdi", "forecast_component"),
                  FORECAST_COMPONENT_COLUMNS, ctx.mode)


def generate_forecast_accuracy(ctx, pu_df, seed):
    """Backtest-style accuracy rows joining a synthetic actual to the forecast.

    Emits a SERIES of weekly periods per planning unit (not a single date), spaced so
    that the matched-lag naive baseline in gold_forecast_value_added resolves: with
    lag_weeks = 4 and a weekly cadence, each period after the fourth has a prior actual
    exactly lag_weeks*7 days earlier, so fva_model_vs_naive is non-NULL and the A11 fix
    is demonstrable on the generated data."""
    n_periods = 12
    lag_weeks = 4
    # explode each planning unit into n_periods consecutive weeks from a fixed anchor
    periods = ctx.spark.range(n_periods).withColumnRenamed("id", "wk")
    df = (pu_df.crossJoin(periods)
          .withColumn("forecast_date_key",
                      F.date_add(F.lit("2026-01-05").cast("date"), (F.col("wk") * 7).cast("int")))
          .withColumn("forecast_accuracy_id",
                      F.concat(F.lit("FACC-"), F.col("planning_unit_id"), F.lit("-"),
                               F.date_format(F.col("forecast_date_key"), "yyyyMMdd")))
          # base demand per unit, with a mild per-week ripple so periods differ
          .withColumn("forecast_quantity",
                      ((F.abs(F.hash(F.col("planning_unit_id"))) % 500 + 10)
                       * (1 + 0.05 * F.sin(F.col("wk")))).cast("decimal(12,3)"))
          .withColumn("actual_quantity", (F.col("forecast_quantity") * 0.95).cast("decimal(12,3)"))
          # planner enrichment nudges the forecast slightly closer to actual
          .withColumn("effective_forecast_quantity",
                      (F.col("forecast_quantity") * 0.98).cast("decimal(12,3)"))
          .withColumn("lag_weeks", F.lit(lag_weeks))
          .withColumn("accuracy_pct", F.lit(0.78))
          # Spread bias across the points scale so downstream thresholds are exercised on
          # the sample: one bucket is a strong under-forecast (< -5 pts), which drives the
          # partially_preventable branch in gold_oos_preventability. Whole percentage POINTS.
          .withColumn("bias_pct",
                      F.element_at(F.array(F.lit(1.5), F.lit(3.0), F.lit(-8.0)),
                                   (F.abs(F.hash(F.col("planning_unit_id"))) % 3 + 1).cast("int")))
          .withColumn("mape", F.lit(0.12))
          .withColumn("is_stockout_censored", F.lit(False))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.current_timestamp())
          .drop("wk"))
    return _write(ctx.spark, df, ctx.fq("sdi", "forecast_accuracy"),
                  FORECAST_ACCURACY_COLUMNS, ctx.mode)


def generate_service_level_targets(ctx):
    now = F.current_timestamp()
    # (id, abc, xyz, service_measure_type, target_service_level_pct, target_fill_rate_pct, target_dos)
    rows = [
        ("SLT-DEFAULT", None, None, "cycle_service_level", D("0.9500"), D("0.9500"), D("7.0")),
        ("SLT-AX", "A", "X", "cycle_service_level", D("0.9800"), D("0.9800"), D("3.0")),
        ("SLT-CZ", "C", "Z", "fill_rate", D("0.8500"), D("0.8500"), D("14.0")),
    ]
    df = ctx.spark.createDataFrame(
        rows,
        "service_level_target_id STRING, abc_class STRING, xyz_class STRING, "
        "service_measure_type STRING, target_service_level_pct DECIMAL(5,4), "
        "target_fill_rate_pct DECIMAL(5,4), target_days_of_supply DECIMAL(8,2)")
    df = (df
          .withColumn("effective_from_date", F.lit("2026-01-01").cast("date"))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))
    return _write(ctx.spark, df, ctx.fq("sdi", "service_level_target"),
                  SERVICE_LEVEL_TARGET_COLUMNS, ctx.mode)


def generate_service_level_z(ctx):
    """Seed the service-level -> z-score and unit-normal loss lookup.
    Values are the standard-normal inverse CDF and loss integral L(z) = phi(z) - z*(1-Phi(z))
    at common service levels; deterministic reference data."""
    now = F.current_timestamp()
    # (service_level_pct, z_score, L(z))
    rows = [
        (D("0.5000"), 0.0000, 0.3989),
        (D("0.8000"), 0.8416, 0.1120),
        (D("0.8500"), 1.0364, 0.0833),
        (D("0.9000"), 1.2816, 0.0561),
        (D("0.9500"), 1.6449, 0.0293),
        (D("0.9750"), 1.9600, 0.0167),
        (D("0.9800"), 2.0537, 0.0139),
        (D("0.9900"), 2.3263, 0.0077),
        (D("0.9950"), 2.5758, 0.0042),
        (D("0.9990"), 3.0902, 0.0011),
    ]
    df = ctx.spark.createDataFrame(
        rows, "service_level_pct DECIMAL(6,5), z_score DOUBLE, loss_function_l_z DOUBLE")
    df = (df
          .withColumn("service_level_z_id",
                      F.concat(F.lit("SLZ-"), (F.col("service_level_pct") * 10000).cast("int").cast("string")))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))
    return _write(ctx.spark, df, ctx.fq("sdi", "service_level_z"),
                  SERVICE_LEVEL_Z_COLUMNS, ctx.mode)


def generate_inventory_policies(ctx, pu_df, slt_df):
    now = F.current_timestamp()
    default_slt = slt_df.filter("service_level_target_id = 'SLT-DEFAULT'").first()
    df = (pu_df
          .withColumn("inventory_policy_id", F.concat(F.lit("IP-"), F.col("planning_unit_id")))
          .withColumn("policy_type", F.lit("reorder_point"))
          .withColumn("safety_stock_quantity", F.lit(20).cast("decimal(12,3)"))
          .withColumn("reorder_point_quantity", F.lit(50).cast("decimal(12,3)"))
          .withColumn("min_quantity", F.lit(30).cast("decimal(12,3)"))
          .withColumn("max_quantity", F.lit(200).cast("decimal(12,3)"))
          .withColumn("order_up_to_quantity", F.lit(200).cast("decimal(12,3)"))
          .withColumn("review_period_days", F.lit(7))
          .withColumn("lead_time_days", F.lit(5))
          .withColumn("service_level_target_sk", F.lit(default_slt["service_level_target_sk"]))
          .withColumn("service_level_target_id", F.lit(default_slt["service_level_target_id"]))
          .withColumn("policy_source", F.lit("abc_xyz_template"))
          .withColumn("effective_from_date", F.lit("2026-01-01").cast("date"))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))
    return _write(ctx.spark, df, ctx.fq("sdi", "inventory_policy"),
                  INVENTORY_POLICY_COLUMNS, ctx.mode)


def generate_recommendations(ctx, ip_df):
    df = (ip_df
          .withColumn("inventory_recommendation_id",
                      F.concat(F.lit("REC-"), F.col("planning_unit_id")))
          .withColumn("recommendation_date_key", F.lit("2026-01-01").cast("date"))
          .withColumn("recommended_order_quantity", F.lit(120).cast("decimal(12,3)"))
          .withColumn("recommended_order_date_key", F.lit("2026-01-02").cast("date"))
          .withColumn("projected_days_of_supply", F.lit(2.5).cast("decimal(8,2)"))
          .withColumn("projected_days_of_supply_after", F.lit(9.0).cast("decimal(8,2)"))
          .withColumn("recommendation_reason", F.lit("below_rop"))
          .withColumn("recommendation_status", F.lit("open"))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.current_timestamp())
          .select("inventory_recommendation_id", "planning_unit_sk", "planning_unit_id",
                  "recommendation_date_key", "recommended_order_quantity",
                  "recommended_order_date_key", "projected_days_of_supply",
                  "projected_days_of_supply_after", "recommendation_reason",
                  "recommendation_status", "inventory_policy_sk", "inventory_policy_id",
                  "record_source", "load_timestamp"))
    return _write(ctx.spark, df, ctx.fq("sdi", "inventory_recommendation"),
                  INVENTORY_RECOMMENDATION_COLUMNS, ctx.mode)


def generate_oos_events(ctx, stockout_df, cfg):
    n = min(cfg["oos_events"], stockout_df.count())
    base = (stockout_df
            .withColumn("_rank", F.row_number().over(
                Window.orderBy(F.hash(F.col("product_id"), F.col("store_id")))))
            .filter(F.col("_rank") <= n)
            .drop("_rank"))
    df = (base
          .withColumn("oos_event_id",
                      F.concat(F.lit("OOS-"), F.col("product_id"), F.lit("-"), F.col("store_id")))
          .withColumn("oos_start_date_key", F.col("date_key"))
          .withColumn("oos_end_date_key", F.lit(None).cast("date"))
          .withColumn("oos_duration_days", F.lit(1))
          .withColumn("detection_method", F.lit("inventory_snapshot"))
          # Spread causes across system-availability, on-shelf-availability (phantom_stock
          # is the A14 phantom/OSA gap where system on-hand > 0 but the shelf is empty), and
          # a demand_spike so gold_oos_preventability's not_preventable branch is exercised.
          .withColumn("_cause_bucket", (F.abs(F.hash(F.col("product_id"), F.col("store_id"))) % 3).cast("int"))
          .withColumn("oos_cause",
                      F.element_at(F.array(F.lit("replenishment_miss"), F.lit("phantom_stock"),
                                           F.lit("demand_spike")),
                                   F.col("_cause_bucket") + 1))
          .withColumn("oos_severity", F.lit("high"))
          .withColumn("is_promo_period", F.lit(False))
          .withColumn("stockout_pct_total", F.lit(1.0).cast("decimal(5,4)"))
          .withColumn("competitor_spillover_flag", F.lit(False))
          .withColumn("data_quality_flag", F.lit(False))
          # demand_spike episodes are the source-labelled not-preventable case
          .withColumn("is_preventable", F.col("oos_cause") != F.lit("demand_spike"))
          .drop("_cause_bucket")
          .withColumn("linked_disruption_event_id", F.lit(None).cast("string"))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.current_timestamp()))
    return _write(ctx.spark, df, ctx.fq("sdi", "oos_event"), OOS_EVENT_COLUMNS, ctx.mode)


def generate_lost_sales(ctx, oos_df):
    df = (oos_df
          .withColumn("lost_sales_estimate_id",
                      F.concat(F.lit("LSE-"), F.col("oos_event_id")))
          .withColumn("estimate_date_key", F.col("oos_start_date_key"))
          .withColumn("actual_units_sold", F.lit(0))
          .withColumn("expected_units_demand", F.lit(30).cast("decimal(12,3)"))
          .withColumn("lost_units", F.lit(30).cast("decimal(12,3)"))
          .withColumn("estimation_method", F.lit("trailing_average"))
          .withColumn("censoring_adjusted", F.lit(True))
          .withColumn("lost_revenue", F.lit(150.00).cast("decimal(18,2)"))
          # gross margin is a plausible ~35% of lost revenue for the synthetic sample
          .withColumn("lost_margin", F.lit(52.50).cast("decimal(18,2)"))
          .withColumn("currency_code", F.lit(ctx.base_currency))
          .withColumn("confidence_score", F.lit(0.7))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.current_timestamp())
          .select("lost_sales_estimate_id", "oos_event_sk", "oos_event_id", "estimate_date_key",
                  "actual_units_sold", "expected_units_demand", "lost_units", "estimation_method",
                  "censoring_adjusted", "lost_revenue", "lost_margin", "currency_code", "confidence_score",
                  "record_source", "load_timestamp"))
    return _write(ctx.spark, df, ctx.fq("sdi", "lost_sales_estimate"),
                  LOST_SALES_COLUMNS, ctx.mode)


def generate_forecast_adjustments(ctx, df_df, seed):
    """Planner overrides on a subset of forecast periods (approved + pending mix)."""
    # Dedupe to the adjustment grain (planning_unit x forecast_date) first: a
    # planning unit can have several demand_forecast rows for one date (different
    # horizons), but at most one adjustment, so the FADJ business key stays unique.
    deduped = (df_df
               .groupBy("planning_unit_sk", "planning_unit_id", "forecast_date_key")
               .agg(F.first("forecast_quantity").alias("forecast_quantity")))
    base = (deduped
            .withColumn("_r", F.row_number().over(
                Window.orderBy(F.hash(F.col("planning_unit_sk"), F.col("forecast_date_key")))))
            .filter(F.col("_r") % 5 == 0)  # ~20% of forecast periods get an adjustment
            .drop("_r"))
    df = (base
          .withColumn("forecast_adjustment_id",
                      F.concat(F.lit("FADJ-"), F.col("planning_unit_id"), F.lit("-"),
                               F.date_format(F.col("forecast_date_key"), "yyyyMMdd")))
          .withColumn("adjustment_quantity", (F.col("forecast_quantity") * 0.1).cast("decimal(12,3)"))
          .withColumn("adjustment_method", F.lit("delta"))
          .withColumn("adjustment_reason_code", _pick(ADJUSTMENT_REASONS, seed, "reason", F.col("planning_unit_sk")))
          .withColumn("adjusted_by", F.concat(F.lit("planner-"),
                                              (F.abs(F.hash(F.col("planning_unit_sk"))) % 5).cast("string")))
          .withColumn("adjusted_at_timestamp", F.current_timestamp())
          .withColumn("approval_status",
                      F.when(F.abs(F.hash(F.col("forecast_date_key"))) % 2 == 0, F.lit("approved"))
                       .otherwise(F.lit("pending")))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.current_timestamp())
          .select("forecast_adjustment_id", "planning_unit_sk", "planning_unit_id", "forecast_date_key",
                  "adjustment_quantity", "adjustment_method", "adjustment_reason_code",
                  "adjusted_by", "adjusted_at_timestamp", "approval_status",
                  "record_source", "load_timestamp"))
    return _write(ctx.spark, df, ctx.fq("sdi", "forecast_adjustment"),
                  FORECAST_ADJUSTMENT_COLUMNS, ctx.mode)


def generate_order_forecasts(ctx, ir_df):
    """Translate open replenishment recommendations into order forecasts."""
    df = (ir_df
          .withColumn("order_forecast_id",
                      F.concat(F.lit("OF-"), F.col("planning_unit_id")))
          .withColumn("order_date_key", F.col("recommended_order_date_key"))
          .withColumn("need_by_date_key", F.date_add(F.col("recommended_order_date_key"), 5))
          .withColumn("order_forecast_quantity", F.col("recommended_order_quantity"))
          .withColumn("order_type", F.lit("replenishment"))
          .withColumn("source_location_id", F.lit("DC-001"))
          .withColumn("destination_store_sk", F.lit(None).cast("bigint"))
          .withColumn("destination_store_id", F.lit(None).cast("string"))
          .withColumn("demand_forecast_sk", F.lit(None).cast("bigint"))
          .withColumn("demand_forecast_id", F.lit(None).cast("string"))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.current_timestamp())
          .select("order_forecast_id", "planning_unit_sk", "planning_unit_id", "order_date_key",
                  "need_by_date_key", "order_forecast_quantity", "order_type", "source_location_id",
                  "destination_store_sk", "destination_store_id", "demand_forecast_sk",
                  "demand_forecast_id", "inventory_policy_sk", "inventory_policy_id",
                  "record_source", "load_timestamp"))
    return _write(ctx.spark, df, ctx.fq("sdi", "order_forecast"),
                  ORDER_FORECAST_COLUMNS, ctx.mode)


def generate_policy_calculations(ctx, ip_df):
    """Audit rows explaining how each inventory policy was derived."""
    df = (ip_df
          .withColumn("policy_calculation_id",
                      F.concat(F.lit("IPC-"), F.col("inventory_policy_id")))
          .withColumn("calculated_at_timestamp", F.current_timestamp())
          .withColumn("avg_daily_demand", F.lit(10).cast("decimal(12,3)"))
          .withColumn("demand_std_dev", F.lit(3).cast("decimal(12,3)"))
          .withColumn("forecast_bias_pct", F.lit(1.5))
          .withColumn("lead_time_days", F.lit(5))
          .withColumn("lead_time_std_dev", F.lit(1.0))
          .withColumn("safety_stock_formula", F.lit("z_score * sqrt(lt) * sigma_d"))
          .withColumn("z_score", F.lit(1.65))
          .withColumn("supplier_reliability_multiplier", F.lit(1.0))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.current_timestamp())
          .select("policy_calculation_id", "inventory_policy_sk", "inventory_policy_id",
                  "calculated_at_timestamp", "avg_daily_demand", "demand_std_dev", "forecast_bias_pct",
                  "lead_time_days", "lead_time_std_dev", "safety_stock_formula", "z_score",
                  "supplier_reliability_multiplier",
                  "record_source", "load_timestamp"))
    return _write(ctx.spark, df, ctx.fq("sdi", "inventory_policy_calculation"),
                  INVENTORY_POLICY_CALC_COLUMNS, ctx.mode)


def generate_demand_sensing_signals(ctx, oos_df, seed):
    """Short-horizon signals; some promoted from OOS events."""
    df = (oos_df
          .withColumn("demand_sensing_signal_id", F.concat(F.lit("DSS-"), F.col("oos_event_id")))
          .withColumn("planning_unit_sk", F.lit(None).cast("bigint"))
          .withColumn("planning_unit_id", F.lit(None).cast("string"))
          .withColumn("signal_timestamp", F.current_timestamp())
          .withColumn("signal_category", _pick(SENSING_CATEGORIES, seed, "cat", F.col("oos_event_sk")))
          .withColumn("signal_type", F.lit("retail_stockout"))
          .withColumn("signal_description", F.lit("Velocity collapse detected at product x store."))
          .withColumn("severity", F.lit("high"))
          .withColumn("resolved_flag", F.lit(False))
          .withColumn("resolved_at_timestamp", F.lit(None).cast("timestamp"))
          .withColumn("linked_oos_event_sk", F.col("oos_event_sk"))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.current_timestamp())
          .select("demand_sensing_signal_id", "planning_unit_sk", "planning_unit_id", "product_sk", "product_id",
                  "store_sk", "store_id", "signal_timestamp", "signal_category", "signal_type",
                  "signal_description", "severity", "resolved_flag", "resolved_at_timestamp",
                  "linked_oos_event_sk",
                  "record_source", "load_timestamp"))
    return _write(ctx.spark, df, ctx.fq("sdi", "demand_sensing_signal"),
                  DEMAND_SENSING_COLUMNS, ctx.mode)


def generate_recovery_actions(ctx, oos_df):
    """One recommended recovery action per OOS event."""
    df = (oos_df
          .withColumn("oos_recovery_action_id", F.concat(F.lit("ORA-"), F.col("oos_event_id")))
          .withColumn("action_type", F.lit("emergency_order"))
          .withColumn("recommended_quantity", F.lit(60).cast("decimal(12,3)"))
          .withColumn("recommended_action_date_key", F.col("oos_start_date_key"))
          .withColumn("estimated_recovery_date_key", F.date_add(F.col("oos_start_date_key"), 3))
          .withColumn("estimated_revenue_recovery", F.lit(120.00).cast("decimal(18,2)"))
          .withColumn("estimated_margin_recovery", F.lit(42.00).cast("decimal(18,2)"))
          .withColumn("recoverability_probability", F.lit(0.75))
          .withColumn("actual_revenue_recovered", F.lit(None).cast("decimal(18,2)"))
          .withColumn("time_to_recover_days", F.lit(None).cast("int"))
          .withColumn("currency_code", F.lit(ctx.base_currency))
          .withColumn("action_status", F.lit("recommended"))
          .withColumn("inventory_recommendation_sk", F.lit(None).cast("bigint"))
          .withColumn("inventory_recommendation_id", F.lit(None).cast("string"))
          .withColumn("linked_po_line_sk", F.lit(None).cast("bigint"))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.current_timestamp())
          .select("oos_recovery_action_id", "oos_event_sk", "oos_event_id", "action_type",
                  "recommended_quantity", "recommended_action_date_key", "estimated_recovery_date_key",
                  "estimated_revenue_recovery", "estimated_margin_recovery", "recoverability_probability",
                  "actual_revenue_recovered", "time_to_recover_days", "currency_code", "action_status",
                  "inventory_recommendation_sk", "inventory_recommendation_id", "linked_po_line_sk",
                  "record_source", "load_timestamp"))
    return _write(ctx.spark, df, ctx.fq("sdi", "oos_recovery_action"),
                  OOS_RECOVERY_COLUMNS, ctx.mode)


def run(ctx):
    cfg = load_config()
    seed = int(get_param("seed", cfg["seed"]))

    prod_df = ctx.spark.table(ctx.fq("product", "product")).filter("is_current = TRUE")
    store_df = ctx.spark.table(ctx.fq("store", "store")).filter("is_current = TRUE")
    # trailing velocity comes from the transaction (sales) domain; read to assert the
    # dependency edge and to keep parity with the gold-view inputs.
    _ = ctx.spark.table(ctx.fq("transaction", "sales")).select("product_id").limit(1)
    stockout_df = (ctx.spark.table(ctx.fq("inventory", "inventory_position"))
                   .filter("is_stockout = TRUE")
                   .select("product_sk", "product_id", "store_sk", "store_id", "date_key")
                   .dropDuplicates(["product_id", "store_id"]))

    prod_sel = prod_df.select("product_sk", "product_id")
    store_sel = store_df.select("store_sk", "store_id")

    generate_planning_units(ctx, prod_sel, store_sel, cfg, seed)
    pu_df = ctx.spark.table(ctx.fq("sdi", "planning_unit"))
    generate_segments(ctx, pu_df, seed)

    generate_model_runs(ctx)
    mr_df = ctx.spark.table(ctx.fq("sdi", "forecast_model_run"))
    generate_demand_forecasts(ctx, pu_df, mr_df, cfg, seed)
    df_df = ctx.spark.table(ctx.fq("sdi", "demand_forecast"))
    generate_forecast_components(ctx, df_df)
    generate_forecast_adjustments(ctx, df_df, seed)
    generate_forecast_accuracy(ctx, pu_df, seed)

    generate_service_level_targets(ctx)
    generate_service_level_z(ctx)
    slt_df = ctx.spark.table(ctx.fq("sdi", "service_level_target"))
    generate_inventory_policies(ctx, pu_df, slt_df)
    ip_df = ctx.spark.table(ctx.fq("sdi", "inventory_policy"))
    generate_policy_calculations(ctx, ip_df)
    generate_recommendations(ctx, ip_df)
    ir_df = ctx.spark.table(ctx.fq("sdi", "inventory_recommendation"))
    generate_order_forecasts(ctx, ir_df)

    if stockout_df.count() > 0:
        generate_oos_events(ctx, stockout_df, cfg)
        oos_df = ctx.spark.table(ctx.fq("sdi", "oos_event"))
        generate_lost_sales(ctx, oos_df)
        generate_demand_sensing_signals(ctx, oos_df, seed)
        generate_recovery_actions(ctx, oos_df)

    print("Smarter Demand and Inventory Decisions generation complete.")


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
