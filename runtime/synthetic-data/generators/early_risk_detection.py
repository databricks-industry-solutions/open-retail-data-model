# ============================================================
# ORDM · Synthetic data · Early Risk Detection generator
# Version: 0.5
# Generated: 2026-07-04
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-07-04
# ============================================================
# Populates the outcome-package extension tables: disruption_rule,
# disruption_event, and disruption_alert. Requires canonical-core
# logistics tables (run the logistics generator first).
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
DISRUPTION_RULE_COLUMNS = [
    "disruption_rule_id", "rule_name", "rule_description", "disruption_type",
    "default_severity", "metric_name", "threshold_operator", "threshold_value",
    "is_enabled", "evaluation_interval",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
DISRUPTION_EVENT_COLUMNS = [
    "disruption_event_id", "disruption_rule_sk", "disruption_rule_id",
    "disruption_type", "severity",
    "shipment_sk", "shipment_id", "supplier_sk", "supplier_id",
    "product_sk", "product_id", "store_sk", "store_id",
    "lane_sk", "lane_id",
    "event_description", "metric_name", "metric_value", "threshold_value",
    "event_timestamp", "ingest_timestamp", "latency_seconds",
    "record_source", "load_timestamp",
]
DISRUPTION_ALERT_COLUMNS = [
    "disruption_alert_id", "disruption_event_sk", "disruption_event_id",
    "disruption_rule_sk", "disruption_rule_id",
    "alert_type", "severity", "alert_status",
    "alert_title", "alert_description", "assigned_to",
    "shipment_id", "supplier_id", "product_id", "store_id",
    "created_timestamp", "acknowledged_timestamp", "resolved_timestamp", "resolution_notes",
    "record_source", "load_timestamp",
]

# Seeded rule definitions
RULES = [
    ("RULE-ETA-SLIP-3D", "ETA Slip > 3 Days", "Fires when a shipment's ETA slips by more than 3 days.",
     "shipment_delay", "critical", "eta_slip_days", "gt", 3.0, "5m"),
    ("RULE-ETA-SLIP-1D", "ETA Slip > 1 Day", "Fires when a shipment's ETA slips by more than 1 day.",
     "shipment_delay", "warning", "eta_slip_days", "gt", 1.0, "5m"),
    ("RULE-STOCKOUT", "Stockout Detected", "Fires when a product x store is stocked out.",
     "stockout_risk", "critical", "days_of_supply", "lte", 0.0, "1h"),
    ("RULE-DOS-LOW", "Days of Supply < 3", "Fires when days of supply drops below 3.",
     "stockout_risk", "warning", "days_of_supply", "lt", 3.0, "1h"),
    ("RULE-FEED-STALE", "Feed Stale > 24h", "Fires when a data feed has no new events for 24+ hours.",
     "feed_outage", "critical", "feed_age_minutes", "gt", 1440.0, "15m"),
    ("RULE-QUALITY-DEFECT", "High Defect Rate", "Fires when defect rate exceeds 5%.",
     "quality_issue", "warning", "defect_rate", "gt", 0.05, "1d"),
]

ALERT_STATUSES = ["open", "acknowledged", "resolved"]
ASSIGNEES = ["ops-team-alpha", "ops-team-bravo", "supply-chain-lead"]
DISRUPTION_TYPES = ["shipment_delay", "stockout_risk", "quality_issue", "feed_outage"]


def load_config():
    c = load_domain_config("early_risk_detection")
    vols = c.get("volumes", {}) or {}
    return {
        "seed": c.get("seed", 7007),
        "events": vols.get("events", 50),
        "alerts": vols.get("alerts", 20),
    }


def generate_disruption_rules(spark, catalog, schema, mode):
    """Generate seeded disruption rule reference rows."""
    now = F.current_timestamp()
    rows = []
    for r in RULES:
        rows.append(r)

    schema_def = ("disruption_rule_id STRING, rule_name STRING, rule_description STRING, "
                  "disruption_type STRING, default_severity STRING, metric_name STRING, "
                  "threshold_operator STRING, threshold_value DOUBLE, evaluation_interval STRING")
    df = spark.createDataFrame(rows, schema=schema_def)
    df = (df
          .withColumn("is_enabled", F.lit(True))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))

    fqtn = f"{catalog}.{schema}.disruption_rule"
    return _write(spark, df, fqtn, DISRUPTION_RULE_COLUMNS, mode)


def generate_disruption_events(spark, catalog, schema, logistics_schema, cfg, mode, rule_df, shipment_df, product_df):
    """Generate disruption event rows linked to rules and shipments."""
    seed = cfg["seed"]
    n = cfg["events"]
    now = F.current_timestamp()

    ids = spark.range(n).withColumn("disruption_event_id",
                                     F.concat(F.lit("DE-"), F.format_string("%06d", F.col("id") + F.lit(1))))

    # Assign a random rule to each event
    rule_count = rule_df.count()

    # Assign each event a rule via a broadcast join on a dense modular index.
    from pyspark.sql.window import Window
    rules_with_idx = rule_df.select(
        "disruption_rule_sk", "disruption_rule_id", "disruption_type",
        "default_severity", "metric_name", "threshold_value"
    ).withColumn("_rule_idx", F.row_number().over(Window.orderBy("disruption_rule_sk")) - F.lit(1))

    df = ids.withColumn("_rule_idx", (F.abs(F.hash(F.col("disruption_event_id"), F.lit(seed))) % F.lit(rule_count)).cast("int"))
    df = df.join(F.broadcast(rules_with_idx), "_rule_idx", "left").drop("_rule_idx")

    df = df.withColumnRenamed("default_severity", "severity")

    # Attach a random shipment for shipment_delay events
    shipment_count = shipment_df.count()
    shp = shipment_df.select(
        F.col("shipment_sk").alias("_shp_sk"), F.col("shipment_id").alias("_shp_id"),
        F.col("supplier_sk").alias("_sup_sk"), F.col("supplier_id").alias("_sup_id"),
        F.col("lane_sk").alias("_lane_sk"), F.col("lane_id").alias("_lane_id"),
        F.col("destination_store_sk").alias("_store_sk"), F.col("destination_store_id").alias("_store_id")
    ).withColumn("_shp_idx", F.row_number().over(Window.orderBy("_shp_sk")) - F.lit(1))

    df = df.withColumn("_shp_idx", (F.abs(F.hash(F.col("disruption_event_id"), F.lit(seed + 1))) % F.lit(shipment_count)).cast("int"))
    df = df.join(F.broadcast(shp), "_shp_idx", "left").drop("_shp_idx")

    # Attach a random product for stockout_risk events
    prod_count = product_df.count()
    prod = product_df.select(
        F.col("product_sk").alias("_prod_sk"), F.col("product_id").alias("_prod_id")
    ).withColumn("_prod_idx", F.row_number().over(Window.orderBy("_prod_sk")) - F.lit(1))

    df = df.withColumn("_prod_idx", (F.abs(F.hash(F.col("disruption_event_id"), F.lit(seed + 7))) % F.lit(prod_count)).cast("int"))
    df = df.join(F.broadcast(prod), "_prod_idx", "left").drop("_prod_idx")

    df = (df
          .withColumn("shipment_sk", F.when(F.col("disruption_type") == "shipment_delay", F.col("_shp_sk")).otherwise(F.lit(None).cast("bigint")))
          .withColumn("shipment_id", F.when(F.col("disruption_type") == "shipment_delay", F.col("_shp_id")).otherwise(F.lit(None).cast("string")))
          .withColumn("supplier_sk", F.when(F.col("disruption_type").isin("shipment_delay", "quality_issue"), F.col("_sup_sk")).otherwise(F.lit(None).cast("bigint")))
          .withColumn("supplier_id", F.when(F.col("disruption_type").isin("shipment_delay", "quality_issue"), F.col("_sup_id")).otherwise(F.lit(None).cast("string")))
          .withColumn("product_sk", F.when(F.col("disruption_type") == "stockout_risk", F.col("_prod_sk")).otherwise(F.lit(None).cast("bigint")))
          .withColumn("product_id", F.when(F.col("disruption_type") == "stockout_risk", F.col("_prod_id")).otherwise(F.lit(None).cast("string")))
          .withColumn("store_sk", F.when(F.col("disruption_type") == "stockout_risk", F.col("_store_sk")).otherwise(F.lit(None).cast("bigint")))
          .withColumn("store_id", F.when(F.col("disruption_type") == "stockout_risk", F.col("_store_id")).otherwise(F.lit(None).cast("string")))
          .withColumn("lane_sk", F.when(F.col("disruption_type") == "shipment_delay", F.col("_lane_sk")).otherwise(F.lit(None).cast("bigint")))
          .withColumn("lane_id", F.when(F.col("disruption_type") == "shipment_delay", F.col("_lane_id")).otherwise(F.lit(None).cast("string")))
          .withColumn("metric_value",
                      (F.col("threshold_value") + (F.abs(F.hash(F.col("disruption_event_id"), F.lit(seed + 2))) % F.lit(100)).cast("double") / F.lit(10.0)))
          .withColumn("event_description",
                      F.concat(F.lit("Detected "), F.col("disruption_type"), F.lit(": "),
                               F.col("metric_name"), F.lit(" = "), F.round(F.col("metric_value"), 1).cast("string"),
                               F.lit(" (threshold: "), F.col("threshold_value").cast("string"), F.lit(")")))
          # Timestamps: events spread over last 30 days, clamped to <= now
          .withColumn("event_timestamp",
                      F.least(
                          F.current_timestamp() - F.expr("INTERVAL '1' HOUR") * (F.abs(F.hash(F.col("disruption_event_id"), F.lit(seed + 3))) % F.lit(720) + F.lit(1)).cast("int"),
                          F.current_timestamp()))
          .withColumn("latency_seconds", (F.abs(F.hash(F.col("disruption_event_id"), F.lit(seed + 4))) % F.lit(120) + F.lit(5)).cast("int"))
          .withColumn("ingest_timestamp",
                      F.least(
                          F.col("event_timestamp") + F.expr("INTERVAL '1' SECOND") * F.col("latency_seconds"),
                          F.current_timestamp()))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("_shp_sk", "_shp_id", "_sup_sk", "_sup_id", "_lane_sk", "_lane_id", "_store_sk", "_store_id", "_prod_sk", "_prod_id", "id"))

    fqtn = f"{catalog}.{schema}.disruption_event"
    return _write(spark, df, fqtn, DISRUPTION_EVENT_COLUMNS, mode)


def generate_disruption_alerts(spark, catalog, schema, cfg, mode, event_df, rule_df):
    """Generate disruption alert rows from a subset of events."""
    seed = cfg["seed"]
    n = cfg["alerts"]
    now = F.current_timestamp()
    from pyspark.sql.window import Window

    # Take the first N events as alert triggers
    events = (event_df
              .withColumn("_evt_rank", F.row_number().over(Window.orderBy("disruption_event_sk")))
              .filter(F.col("_evt_rank") <= n))

    df = (events
          .withColumn("disruption_alert_id",
                      F.concat(F.lit("DA-"), F.format_string("%06d", F.col("_evt_rank"))))
          .withColumn("disruption_event_sk", F.col("disruption_event_sk"))
          .withColumn("disruption_event_id", F.col("disruption_event_id"))
          .withColumn("alert_type", F.col("disruption_type"))
          # Mix of statuses: ~50% open, ~30% acknowledged, ~20% resolved
          .withColumn("alert_status",
                      F.when(_frac(seed, "astatus", F.col("disruption_alert_id")) < F.lit(0.5), F.lit("open"))
                       .when(_frac(seed, "astatus", F.col("disruption_alert_id")) < F.lit(0.8), F.lit("acknowledged"))
                       .otherwise(F.lit("resolved")))
          .withColumn("alert_title",
                      F.concat(F.upper(F.col("severity")), F.lit(": "), F.col("disruption_type"),
                               F.lit(" detected")))
          .withColumn("alert_description", F.col("event_description"))
          .withColumn("assigned_to",
                      F.when(F.col("alert_status") != "open", _pick(ASSIGNEES, seed, "assign", F.col("disruption_alert_id")))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("created_timestamp", F.col("event_timestamp"))
          .withColumn("acknowledged_timestamp",
                      F.when(F.col("alert_status").isin("acknowledged", "resolved"),
                             F.col("event_timestamp") + F.expr("INTERVAL '1' HOUR") * (F.abs(F.hash(F.col("disruption_alert_id"), F.lit(seed + 5))) % F.lit(12) + F.lit(1)).cast("int"))
                       .otherwise(F.lit(None).cast("timestamp")))
          .withColumn("resolved_timestamp",
                      F.when(F.col("alert_status") == "resolved",
                             F.col("acknowledged_timestamp") + F.expr("INTERVAL '1' HOUR") * (F.abs(F.hash(F.col("disruption_alert_id"), F.lit(seed + 6))) % F.lit(24) + F.lit(1)).cast("int"))
                       .otherwise(F.lit(None).cast("timestamp")))
          .withColumn("resolution_notes",
                      F.when(F.col("alert_status") == "resolved", F.lit("Issue resolved per standard operating procedure."))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("_evt_rank", "event_description", "disruption_type", "metric_name",
                "metric_value", "threshold_value", "event_timestamp",
                "ingest_timestamp", "latency_seconds",
                "shipment_sk", "supplier_sk", "product_sk", "store_sk",
                "lane_sk", "lane_id"))

    fqtn = f"{catalog}.{schema}.disruption_alert"
    return _write(spark, df, fqtn, DISRUPTION_ALERT_COLUMNS, mode)


# ---- entry point ----

def run(ctx):
    spark, catalog, mode = ctx.spark, ctx.catalog, ctx.mode
    risk_schema = ctx.schemas["risk"]
    logistics_schema = ctx.schemas["logistics"]
    cfg = load_config()

    # Reads the canonical-core logistics shipment (run the logistics generator first).
    shipment_df = spark.table(f"{catalog}.{logistics_schema}.shipment")
    product_df = spark.table(f"{catalog}.{ctx.schemas['product']}.product").filter("is_current = TRUE")

    # Generate in dependency order
    rule_df = generate_disruption_rules(spark, catalog, risk_schema, mode)
    event_df = generate_disruption_events(spark, catalog, risk_schema, logistics_schema, cfg, mode, rule_df, shipment_df, product_df)
    generate_disruption_alerts(spark, catalog, risk_schema, cfg, mode, event_df, rule_df)
    print("Early Risk Detection generation complete.")


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
