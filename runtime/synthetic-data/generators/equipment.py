# ============================================================
# ORDM · Synthetic data · Equipment generator
# Version: 0.5
# Generated: 2026-07-15
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-07-15
# ============================================================
# Populates the canonical-core equipment tables: equipment and
# equipment_reading. Requires canonical-core store tables (run
# the trade_promotion generator first, which provides stores).
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
EQUIPMENT_COLUMNS = [
    "equipment_id", "equipment_name", "equipment_type", "manufacturer",
    "model_number", "serial_number",
    "store_sk", "store_id", "installation_zone",
    "install_date", "warranty_expiry_date", "expected_lifespan_years",
    "equipment_status", "criticality", "asset_tag",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
EQUIPMENT_READING_COLUMNS = [
    "equipment_reading_id", "equipment_sk", "equipment_id",
    "reading_type", "reading_value", "reading_unit",
    "error_code", "error_message", "is_anomaly", "threshold_breached",
    "event_timestamp", "ingest_timestamp", "latency_seconds",
    "record_source", "load_timestamp",
]

EQUIPMENT_TYPES = ["refrigeration", "hvac", "pos_terminal", "self_checkout", "oven", "lighting", "shelving", "security"]
MANUFACTURERS = ["Carrier", "Hussmann", "Trane", "NCR", "Diebold Nixdorf", "Middleby", "Emerson", "Honeywell"]
ZONES = ["sales_floor", "backroom", "exterior", "loading_dock", "office", "kitchen"]
CRITICALITIES = ["critical", "high", "medium", "low"]
STATUSES = ["operational", "operational", "operational", "operational", "degraded", "out_of_service"]
READING_TYPES = ["temperature", "humidity", "power_kw", "vibration", "runtime_hours", "error_code"]
READING_UNITS = {"temperature": "celsius", "humidity": "percent", "power_kw": "kw", "vibration": "mm_s", "runtime_hours": "hours", "error_code": "code"}
ERROR_CODES = ["E001", "E002", "E003", "E004", "E005"]
ERROR_MESSAGES = [
    "Compressor overload detected",
    "Sensor communication failure",
    "Temperature threshold exceeded",
    "Power fluctuation detected",
    "Filter maintenance overdue",
]


def load_config():
    c = load_domain_config("equipment")
    vols = c.get("volumes", {}) or {}
    return {
        "seed": c.get("seed", 9009),
        "assets": vols.get("assets", 80),
        "readings_per_asset": vols.get("readings_per_asset", 20),
    }


def generate_equipment(spark, catalog, schema, store_schema, cfg, mode):
    """Generate in-store equipment master rows (SCD2, all current)."""
    seed = cfg["seed"]
    n = cfg["assets"]
    now = F.current_timestamp()
    today = F.current_date()
    from pyspark.sql.window import Window

    # Get stores to assign equipment
    store_df = spark.table(f"{catalog}.{store_schema}.store").filter("is_current = TRUE")
    store_count = store_df.count()
    store_indexed = store_df.select(
        F.col("store_sk").alias("_st_sk"), F.col("store_id").alias("_st_id")
    ).withColumn("_st_idx", F.row_number().over(Window.orderBy("_st_sk")) - F.lit(1))

    ids = spark.range(n).withColumn("equipment_id",
                                     F.concat(F.lit("EQ-"), F.format_string("%05d", F.col("id") + F.lit(1))))

    # Assign store
    df = ids.withColumn("_st_idx", (F.abs(F.hash(F.col("equipment_id"), F.lit(seed))) % F.lit(store_count)).cast("int"))
    df = df.join(F.broadcast(store_indexed), "_st_idx", "left").drop("_st_idx")
    df = df.withColumnRenamed("_st_sk", "store_sk").withColumnRenamed("_st_id", "store_id")

    df = (df
          .withColumn("equipment_type", _pick(EQUIPMENT_TYPES, seed, "etype", F.col("equipment_id")))
          .withColumn("equipment_name",
                      F.concat(F.initcap(F.col("equipment_type")), F.lit(" Unit "), F.col("id") + F.lit(1)))
          .withColumn("manufacturer", _pick(MANUFACTURERS, seed, "mfr", F.col("equipment_id")))
          .withColumn("model_number",
                      F.concat(F.lit("MDL-"), F.upper(F.substring(F.col("equipment_type"), 1, 3)),
                               F.lit("-"), F.format_string("%03d", (F.abs(F.hash(F.col("equipment_id"), F.lit(seed + 1))) % F.lit(100)).cast("int"))))
          .withColumn("serial_number",
                      F.concat(F.lit("SN"), F.format_string("%08d", F.abs(F.hash(F.col("equipment_id"), F.lit(seed + 2))) % F.lit(99999999))))
          .withColumn("installation_zone", _pick(ZONES, seed, "zone", F.col("equipment_id")))
          .withColumn("install_date",
                      F.date_sub(today, (F.abs(F.hash(F.col("equipment_id"), F.lit(seed + 3))) % F.lit(1800) + F.lit(180)).cast("int")))
          .withColumn("warranty_expiry_date",
                      F.date_add(F.col("install_date"), F.lit(1095)))  # 3 years
          .withColumn("expected_lifespan_years",
                      (F.abs(F.hash(F.col("equipment_id"), F.lit(seed + 4))) % F.lit(10) + F.lit(5)).cast("int"))
          .withColumn("equipment_status", _pick(STATUSES, seed, "status", F.col("equipment_id")))
          .withColumn("criticality", _pick(CRITICALITIES, seed, "crit", F.col("equipment_id")))
          .withColumn("asset_tag",
                      F.concat(F.lit("AT-"), F.format_string("%06d", F.col("id") + F.lit(1))))
          .withColumn("effective_from_date", F.col("install_date"))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("id"))

    fqtn = f"{catalog}.{schema}.equipment"
    return _write(spark, df, fqtn, EQUIPMENT_COLUMNS, mode)


def generate_equipment_readings(spark, catalog, schema, cfg, mode, equipment_df):
    """Generate equipment sensor reading rows."""
    seed = cfg["seed"]
    readings_per = cfg["readings_per_asset"]
    now = F.current_timestamp()
    from pyspark.sql.window import Window

    # Explode each equipment into multiple readings
    equip = equipment_df.select("equipment_sk", "equipment_id", "equipment_type")
    reading_ids = spark.range(readings_per).withColumnRenamed("id", "reading_idx")
    df = equip.crossJoin(reading_ids)

    df = (df
          .withColumn("equipment_reading_id",
                      F.concat(F.col("equipment_id"), F.lit("|"),
                               _pick(READING_TYPES, seed, "rtype", F.col("equipment_id"), F.col("reading_idx")),
                               F.lit("|"), F.col("reading_idx")))
          .withColumn("reading_type", _pick(READING_TYPES, seed, "rtype", F.col("equipment_id"), F.col("reading_idx")))
          .withColumn("reading_value",
                      F.when(F.col("reading_type") == "temperature",
                             F.lit(2.0) + (F.abs(F.hash(F.col("equipment_reading_id"), F.lit(seed + 5))) % F.lit(100)).cast("double") / F.lit(10.0))
                       .when(F.col("reading_type") == "humidity",
                             F.lit(30.0) + (F.abs(F.hash(F.col("equipment_reading_id"), F.lit(seed + 6))) % F.lit(500)).cast("double") / F.lit(10.0))
                       .when(F.col("reading_type") == "power_kw",
                             F.lit(0.5) + (F.abs(F.hash(F.col("equipment_reading_id"), F.lit(seed + 7))) % F.lit(100)).cast("double") / F.lit(10.0))
                       .when(F.col("reading_type") == "vibration",
                             (F.abs(F.hash(F.col("equipment_reading_id"), F.lit(seed + 8))) % F.lit(50)).cast("double") / F.lit(10.0))
                       .when(F.col("reading_type") == "runtime_hours",
                             (F.abs(F.hash(F.col("equipment_reading_id"), F.lit(seed + 9))) % F.lit(50000)).cast("double"))
                       .otherwise(F.lit(None).cast("double")))
          .withColumn("reading_unit",
                      F.when(F.col("reading_type") == "temperature", F.lit("celsius"))
                       .when(F.col("reading_type") == "humidity", F.lit("percent"))
                       .when(F.col("reading_type") == "power_kw", F.lit("kw"))
                       .when(F.col("reading_type") == "vibration", F.lit("mm_s"))
                       .when(F.col("reading_type") == "runtime_hours", F.lit("hours"))
                       .otherwise(F.lit("code")))
          .withColumn("error_code",
                      F.when(F.col("reading_type") == "error_code",
                             _pick(ERROR_CODES, seed, "ecode", F.col("equipment_reading_id")))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("error_message",
                      F.when(F.col("reading_type") == "error_code",
                             _pick(ERROR_MESSAGES, seed, "emsg", F.col("equipment_reading_id")))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("is_anomaly",
                      _frac(seed, "anomaly", F.col("equipment_reading_id")) < F.lit(0.08))
          .withColumn("threshold_breached",
                      F.when(F.col("is_anomaly") == True,
                             _pick(["low", "high", "critical_low", "critical_high"], seed, "thresh", F.col("equipment_reading_id")))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("event_timestamp",
                      F.least(
                          F.current_timestamp() - F.expr("INTERVAL '1' HOUR") * (F.abs(F.hash(F.col("equipment_reading_id"), F.lit(seed + 10))) % F.lit(720) + F.lit(1)).cast("int"),
                          F.current_timestamp()))
          .withColumn("latency_seconds", (F.abs(F.hash(F.col("equipment_reading_id"), F.lit(seed + 11))) % F.lit(60) + F.lit(2)).cast("int"))
          .withColumn("ingest_timestamp",
                      F.least(
                          F.col("event_timestamp") + F.expr("INTERVAL '1' SECOND") * F.col("latency_seconds"),
                          F.current_timestamp()))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("reading_idx", "equipment_type"))

    fqtn = f"{catalog}.{schema}.equipment_reading"
    return _write(spark, df, fqtn, EQUIPMENT_READING_COLUMNS, mode)


# ---- entry point ----

def run(ctx):
    spark, catalog, mode = ctx.spark, ctx.catalog, ctx.mode
    equipment_schema = ctx.schemas["equipment"]
    store_schema = ctx.schemas["store"]
    cfg = load_config()

    equipment_df = generate_equipment(spark, catalog, equipment_schema, store_schema, cfg, mode)
    generate_equipment_readings(spark, catalog, equipment_schema, cfg, mode, equipment_df)
    print("Equipment generation complete.")


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
