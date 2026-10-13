# ============================================================
# ORDM · Synthetic data · Logistics generator
# Version: 0.5
# Generated: 2026-07-01
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-07-01
# ============================================================
# Populates the canonical-core logistics tables: lane, shipment,
# shipment_line, and shipment_tracking. Reuses supplier, product,
# and store dimensions (run the supplier_monitoring generator first).
# Shared helpers come from _common (extended, not forked).
# Volumes come from runtime/synthetic-data/seeds.yaml.
# ============================================================

import os
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

try:
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _pick, _frac,
                         _write, attach_random_dim)
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _pick, _frac,
                         _write, attach_random_dim)

# ------------------------------------------------------------
# Column contracts -- MUST match the DDL (minus IDENTITY *_sk).
# ------------------------------------------------------------
LANE_COLUMNS = [
    "lane_id", "origin_location_id", "origin_location_name",
    "origin_country_code", "origin_location_type",
    "destination_location_id", "destination_location_name",
    "destination_country_code", "destination_location_type",
    "transport_mode", "planned_transit_days", "distance_km", "is_active",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
SHIPMENT_COLUMNS = [
    "shipment_id", "po_id", "supplier_sk", "supplier_id", "lane_sk", "lane_id",
    "destination_store_sk", "destination_store_id",
    "carrier_name", "transport_mode", "shipment_status",
    "ship_date", "estimated_arrival_date", "original_eta_date", "actual_arrival_date",
    "record_source", "load_timestamp",
]
SHIPMENT_LINE_COLUMNS = [
    "shipment_line_id", "shipment_sk", "shipment_id", "product_sk", "product_id",
    "po_line_sk", "po_line_id", "shipped_quantity", "received_quantity", "damaged_quantity",
    "unit_weight_kg", "line_weight_kg",
    "record_source", "load_timestamp",
]
SHIPMENT_TRACKING_COLUMNS = [
    "shipment_tracking_id", "shipment_sk", "shipment_id",
    "carrier_code", "carrier_name", "tracking_number", "carrier_service_level",
    "checkpoint_type", "checkpoint_status_code", "checkpoint_message",
    "facility_name", "city", "state_province", "country_code", "postal_code",
    "latitude", "longitude",
    "signed_by", "is_signature_required", "delivery_location_type",
    "scanned_weight_kg", "piece_count",
    "exception_code", "exception_reason",
    "carrier_eta_date",
    "event_timestamp", "ingest_timestamp", "latency_seconds",
    "record_source", "load_timestamp",
]

TRANSPORT_MODES = ["road", "rail", "ocean", "air", "intermodal"]
SHIPMENT_STATUSES = ["planned", "in_transit", "delivered", "cancelled"]
CARRIER_NAMES = ["Carrier A", "Carrier B", "Carrier C", "Carrier D", "Carrier E"]
CARRIER_CODES = ["CRA1", "CRB2", "CRC3", "CRD4", "CRE5"]
SERVICE_LEVELS = ["express", "standard", "economy", "ltl", "ftl", "ocean_fcl"]
CHECKPOINT_TYPES = ["pickup", "hub_scan", "in_transit", "out_for_delivery", "delivered"]
# Extended types for exception/disruption scenarios
EXCEPTION_CHECKPOINT_TYPES = ["pickup", "hub_scan", "in_transit", "exception", "in_transit"]
CITIES = [
    ("Chicago", "IL", "US", "60601"), ("Los Angeles", "CA", "US", "90001"),
    ("New York", "NY", "US", "10001"), ("Dallas", "TX", "US", "75201"),
    ("Atlanta", "GA", "US", "30301"), ("Seattle", "WA", "US", "98101"),
    ("Toronto", "ON", "CA", "M5H"), ("Vancouver", "BC", "CA", "V6B"),
    ("London", "ENG", "GB", "EC1A"), ("Frankfurt", "HE", "DE", "60311"),
]
FACILITY_NAMES = ["Hub Alpha", "Hub Bravo", "Hub Charlie", "Distribution Center 1",
                   "Distribution Center 2", "Sort Facility North", "Sort Facility South"]
DELIVERY_LOCATION_TYPES = ["dock", "front_door", "mailroom", "locker"]


def load_config():
    c = load_domain_config("logistics")
    vols = c.get("volumes", {}) or {}
    return {
        "seed": c.get("seed", 6006),
        "lanes": vols.get("lanes", 20),
        "shipments": vols.get("shipments", 200),
        "lines_per_shipment": vols.get("lines_per_shipment", 3),
        "tracking_per_shipment": vols.get("tracking_per_shipment", 5),
    }


def generate_lanes(spark, catalog, schema, cfg, mode):
    """Generate lane dimension rows."""
    seed = cfg["seed"]
    n = cfg["lanes"]
    now = F.current_timestamp()

    origin_types = ["supplier_site", "distribution_center", "port", "warehouse"]
    dest_types = ["distribution_center", "store", "port", "warehouse"]

    rows = []
    for i in range(n):
        o = CITIES[i % len(CITIES)]
        d = CITIES[(i + 3) % len(CITIES)]
        rows.append((
            f"LANE-{i+1:04d}",
            f"LOC-O-{i+1:04d}", f"{o[0]} {origin_types[i % len(origin_types)].replace('_', ' ').title()}",
            o[2], origin_types[i % len(origin_types)],
            f"LOC-D-{i+1:04d}", f"{d[0]} {dest_types[i % len(dest_types)].replace('_', ' ').title()}",
            d[2], dest_types[i % len(dest_types)],
            TRANSPORT_MODES[i % len(TRANSPORT_MODES)],
        ))

    schema_def = "lane_id STRING, origin_location_id STRING, origin_location_name STRING, " \
                 "origin_country_code STRING, origin_location_type STRING, " \
                 "destination_location_id STRING, destination_location_name STRING, " \
                 "destination_country_code STRING, destination_location_type STRING, " \
                 "transport_mode STRING"
    df = spark.createDataFrame(rows, schema=schema_def)
    df = (df
          .withColumn("planned_transit_days", (F.abs(F.hash(F.col("lane_id"), F.lit(seed + 1))) % F.lit(14) + F.lit(1)).cast("int"))
          .withColumn("distance_km", (F.abs(F.hash(F.col("lane_id"), F.lit(seed))) % F.lit(4000) + F.lit(100)).cast("decimal(10,2)"))
          .withColumn("is_active", F.lit(True))
          .withColumn("effective_from_date", F.lit("2024-01-01").cast("date"))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))

    fqtn = f"{catalog}.{schema}.lane"
    return _write(spark, df, fqtn, LANE_COLUMNS, mode)


def generate_shipments(spark, catalog, schema, cfg, mode, lane_df, supplier_df, store_df):
    """Generate shipment dimension rows."""
    seed = cfg["seed"]
    n = cfg["shipments"]
    now = F.current_timestamp()

    ids = spark.range(n).withColumn("shipment_id", F.concat(F.lit("SHP-"), F.format_string("%06d", F.col("id") + F.lit(1))))

    # Attach lane, supplier, store
    lane_count = lane_df.count()
    sup_count = supplier_df.count()
    store_count = store_df.count()

    df = attach_random_dim(ids, lane_df.select("lane_sk", "lane_id", "transport_mode"), lane_count, "lane", seed, F.col("shipment_id"))
    df = attach_random_dim(df, supplier_df.select("supplier_sk", "supplier_id"), sup_count, "sup", seed, F.col("shipment_id"))
    df = attach_random_dim(df, store_df.select(F.col("store_sk").alias("destination_store_sk"), F.col("store_id").alias("destination_store_id")), store_count, "store", seed, F.col("shipment_id"))

    df = (df
          .withColumn("po_id", F.concat(F.lit("PO-"), F.format_string("%06d", F.col("id") + F.lit(1))))
          .withColumn("carrier_name", _pick(CARRIER_NAMES, seed, "carrier", F.col("shipment_id")))
          .withColumn("shipment_status", _pick(SHIPMENT_STATUSES[:3], seed, "status", F.col("shipment_id")))  # no cancelled
          .withColumn("ship_date", F.date_sub(F.current_date(), (F.abs(F.hash(F.col("shipment_id"), F.lit(seed))) % F.lit(90) + F.lit(1)).cast("int")))
          .withColumn("original_eta_date", F.date_add(F.col("ship_date"), (F.abs(F.hash(F.col("shipment_id"), F.lit(seed + 2))) % F.lit(14) + F.lit(2)).cast("int")))
          # ~20% of shipments get a revised (later) estimated arrival date
          .withColumn("estimated_arrival_date",
                      F.when(_frac(seed, "eta_rev", F.col("shipment_id")) < F.lit(0.2),
                             F.date_add(F.col("original_eta_date"), (F.abs(F.hash(F.col("shipment_id"), F.lit(seed + 20))) % F.lit(5) + F.lit(1)).cast("int")))
                       .otherwise(F.col("original_eta_date")))
          .withColumn("actual_arrival_date",
                      F.when(F.col("shipment_status") == "delivered",
                             F.date_add(F.col("original_eta_date"), (F.abs(F.hash(F.col("shipment_id"), F.lit(seed + 3))) % F.lit(5) - F.lit(2)).cast("int")))
                       .otherwise(F.lit(None).cast("date")))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))

    fqtn = f"{catalog}.{schema}.shipment"
    return _write(spark, df, fqtn, SHIPMENT_COLUMNS, mode)


def generate_shipment_lines(spark, catalog, schema, cfg, mode, shipment_df, product_df, po_line_df):
    """Generate shipment line facts."""
    seed = cfg["seed"]
    lines_per = cfg["lines_per_shipment"]
    now = F.current_timestamp()
    prod_count = product_df.count()
    po_line_count = po_line_df.count()

    base = shipment_df.select("shipment_sk", "shipment_id")
    # Explode each shipment into N lines
    df = base.withColumn("line_num", F.explode(F.array(*[F.lit(i + 1) for i in range(lines_per)])))
    df = df.withColumn("shipment_line_id", F.concat(F.col("shipment_id"), F.lit("-L"), F.format_string("%02d", F.col("line_num"))))

    df = attach_random_dim(df, product_df.select("product_sk", "product_id"), prod_count, "prod_line", seed, F.col("shipment_line_id"))
    # Attach a REAL purchase_order_line the shipment line fulfills, so po_line_sk is a
    # valid FK to procurement.purchase_order_line.po_line_sk and po_line_id is the
    # matching durable business key. purchase_order_line is an append-only transactional
    # fact (NOT SCD2), so this is a straight surrogate pick with no version ambiguity.
    df = attach_random_dim(df, po_line_df.select("po_line_sk", "po_line_id"), po_line_count, "po_line", seed, F.col("shipment_line_id"))

    df = (df
          .withColumn("shipped_quantity", (F.abs(F.hash(F.col("shipment_line_id"), F.lit(seed))) % F.lit(100) + F.lit(1)).cast("int"))
          .withColumn("received_quantity",
                      F.when(_frac(seed, "recv", F.col("shipment_line_id")) < F.lit(0.9), F.col("shipped_quantity"))
                       .otherwise((F.col("shipped_quantity") * _frac(seed, "recv_pct", F.col("shipment_line_id"))).cast("int")))
          .withColumn("damaged_quantity",
                      F.when(_frac(seed, "dmg", F.col("shipment_line_id")) < F.lit(0.05),
                             (F.abs(F.hash(F.col("shipment_line_id"), F.lit(seed + 10))) % F.lit(3) + F.lit(1)).cast("int"))
                       .otherwise(F.lit(0).cast("int")))
          .withColumn("unit_weight_kg", (F.abs(F.hash(F.col("shipment_line_id"), F.lit(seed + 11))) % F.lit(50) + F.lit(1)).cast("decimal(10,3)"))
          .withColumn("line_weight_kg", (F.col("unit_weight_kg") * F.col("shipped_quantity")).cast("decimal(12,3)"))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))

    fqtn = f"{catalog}.{schema}.shipment_line"
    return _write(spark, df.drop("line_num"), fqtn, SHIPMENT_LINE_COLUMNS, mode)


def generate_shipment_tracking(spark, catalog, schema, cfg, mode, shipment_df):
    """Generate shipment tracking messages."""
    seed = cfg["seed"]
    events_per = cfg["tracking_per_shipment"]
    now = F.current_timestamp()

    base = shipment_df.select("shipment_sk", "shipment_id", "carrier_name", "ship_date")
    df = base.withColumn("seq", F.explode(F.array(*[F.lit(i + 1) for i in range(events_per)])))
    df = (df
          .withColumn("shipment_tracking_id",
                      F.concat(F.col("shipment_id"), F.lit("-T"), F.format_string("%02d", F.col("seq"))))
          .withColumn("carrier_code", _pick(CARRIER_CODES, seed, "cc", F.col("shipment_id")))
          .withColumn("tracking_number", F.concat(F.lit("TRK"), F.abs(F.hash(F.col("shipment_id"), F.lit(seed))).cast("string")))
          .withColumn("carrier_service_level", _pick(SERVICE_LEVELS, seed, "svc", F.col("shipment_id")))
          # ~15% of shipments get exception checkpoints
          .withColumn("_is_exception", _frac(seed, "exc", F.col("shipment_id")) < F.lit(0.15))
          # Checkpoint type progresses through the sequence
          .withColumn("checkpoint_type",
                      F.when(F.col("_is_exception"),
                             F.element_at(
                                 F.array(*[F.lit(cp) for cp in EXCEPTION_CHECKPOINT_TYPES]),
                                 F.least(F.col("seq"), F.lit(len(EXCEPTION_CHECKPOINT_TYPES)))))
                       .otherwise(
                             F.element_at(
                                 F.array(*[F.lit(cp) for cp in CHECKPOINT_TYPES]),
                                 F.least(F.col("seq"), F.lit(len(CHECKPOINT_TYPES))))))
          .withColumn("checkpoint_status_code", F.concat(F.lit("STS-"), F.col("seq").cast("string")))
          .withColumn("checkpoint_message", F.concat(F.lit("Checkpoint "), F.col("seq").cast("string"), F.lit(" reached")))
          .withColumn("facility_name", _pick(FACILITY_NAMES, seed, "fac", F.col("shipment_tracking_id")))
          .withColumn("city", _pick([c[0] for c in CITIES], seed, "city", F.col("shipment_tracking_id")))
          .withColumn("state_province", _pick([c[1] for c in CITIES], seed, "state", F.col("shipment_tracking_id")))
          .withColumn("country_code", _pick([c[2] for c in CITIES], seed, "cc2", F.col("shipment_tracking_id")))
          .withColumn("postal_code", _pick([c[3] for c in CITIES], seed, "pc", F.col("shipment_tracking_id")))
          .withColumn("latitude",
                      (F.abs(F.hash(F.col("shipment_tracking_id"), F.lit(seed))) % F.lit(18000) - F.lit(9000)).cast("double") / F.lit(100.0))
          .withColumn("longitude",
                      (F.abs(F.hash(F.col("shipment_tracking_id"), F.lit(seed + 1))) % F.lit(36000) - F.lit(18000)).cast("double") / F.lit(100.0))
          # Delivery fields only on the last checkpoint
          .withColumn("signed_by", F.when(F.col("checkpoint_type") == "delivered", F.lit("J. Doe")).otherwise(F.lit(None)))
          .withColumn("is_signature_required", F.when(F.col("checkpoint_type") == "delivered", F.lit(True)).otherwise(F.lit(None).cast("boolean")))
          .withColumn("delivery_location_type",
                      F.when(F.col("checkpoint_type") == "delivered", _pick(DELIVERY_LOCATION_TYPES, seed, "dlt", F.col("shipment_tracking_id")))
                       .otherwise(F.lit(None)))
          .withColumn("scanned_weight_kg",
                      (F.abs(F.hash(F.col("shipment_tracking_id"), F.lit(seed + 12))) % F.lit(500) + F.lit(10)).cast("decimal(10,3)"))
          .withColumn("piece_count", (F.abs(F.hash(F.col("shipment_tracking_id"), F.lit(seed + 13))) % F.lit(20) + F.lit(1)).cast("int"))
          # Exception fields populated only for exception checkpoints
          .withColumn("exception_code",
                      F.when(F.col("checkpoint_type") == "exception",
                             _pick(["WEATHER", "MECH_DELAY", "ADDR_UNKNOWN", "REFUSED", "DAMAGED"], seed, "exc_c", F.col("shipment_tracking_id")))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("exception_reason",
                      F.when(F.col("checkpoint_type") == "exception",
                             _pick(["weather_delay", "mechanical_failure", "address_unknown", "refused", "damaged_in_transit"], seed, "exc_r", F.col("shipment_tracking_id")))
                       .otherwise(F.lit(None).cast("string")))
          # ~20% of shipments get a carrier-revised ETA on their latest checkpoint
          .withColumn("carrier_eta_date",
                      F.when((F.col("seq") >= F.lit(3)) & (_frac(seed, "ceta", F.col("shipment_id")) < F.lit(0.2)),
                             F.date_add(F.col("ship_date"), (F.abs(F.hash(F.col("shipment_id"), F.lit(seed + 21))) % F.lit(10) + F.lit(5)).cast("int")))
                       .otherwise(F.lit(None).cast("date")))
          # Timestamps: each checkpoint a few hours after the previous, clamped to <= now
          .withColumn("_raw_event_ts",
                      (F.col("ship_date").cast("timestamp") + F.expr("INTERVAL '1' HOUR") * F.col("seq") * F.lit(8)))
          .withColumn("event_timestamp", F.least(F.col("_raw_event_ts"), F.current_timestamp()))
          .withColumn("latency_seconds", (F.abs(F.hash(F.col("shipment_tracking_id"), F.lit(seed + 14))) % F.lit(300) + F.lit(5)).cast("int"))
          .withColumn("ingest_timestamp",
                      F.least(
                          F.col("event_timestamp") + F.expr("INTERVAL '1' SECOND") * F.col("latency_seconds"),
                          F.current_timestamp()))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))

    fqtn = f"{catalog}.{schema}.shipment_tracking"
    return _write(spark, df.drop("seq", "ship_date", "_is_exception", "_raw_event_ts"), fqtn, SHIPMENT_TRACKING_COLUMNS, mode)


# ---- entry point ----

def run(ctx):
    spark, catalog, mode = ctx.spark, ctx.catalog, ctx.mode
    schema = ctx.schemas["logistics"]
    cfg = load_config()

    # Conformed dims (must already exist — run supplier_monitoring + trade_promotion first).
    supplier_df = spark.table(f"{catalog}.{ctx.schemas['supplier']}.supplier").filter("is_current = TRUE")
    product_df = spark.table(f"{catalog}.{ctx.schemas['product']}.product").filter("is_current = TRUE")
    store_df = spark.table(f"{catalog}.{ctx.schemas['store']}.store").filter("is_current = TRUE")
    # purchase_order_line (procurement fact) — the PO lines shipment lines fulfill.
    # Written by supplier_monitoring, which the docstring above already requires first.
    po_line_df = spark.table(f"{catalog}.{ctx.schemas['procurement']}.purchase_order_line")

    # Generate in dependency order
    lane_df = generate_lanes(spark, catalog, schema, cfg, mode)
    shipment_df = generate_shipments(spark, catalog, schema, cfg, mode, lane_df, supplier_df, store_df)
    generate_shipment_lines(spark, catalog, schema, cfg, mode, shipment_df, product_df, po_line_df)
    generate_shipment_tracking(spark, catalog, schema, cfg, mode, shipment_df)
    print("Logistics generation complete.")


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
