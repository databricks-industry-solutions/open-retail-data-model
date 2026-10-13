# ============================================================
# ORDM · Synthetic data · Connected Store Signals · RFID submodule
# Version: 0.5
# Generated: 2026-08-18
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: pending
# ============================================================
# Invoked by connected_store_signals.py. It is deliberately not a GenSpec: the
# registry has one provider per schema and connected_store_signals already owns css.
# ============================================================

import os
import sys

import dbldatagen as dg
from pyspark.sql import functions as F
from pyspark.sql.window import Window

try:
    from _common import RECORD_SOURCE, _write
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from _common import RECORD_SOURCE, _write


TAGGED_ITEM_COLUMNS = [
    "tagged_item_sk", "tagged_item_id", "epc_scheme", "gtin", "serial_number",
    "current_tid_hex", "product_sk", "product_id", "lot_number", "expiry_date",
    "tag_privacy_state", "commissioned_at_ts", "decommissioned_at_ts",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]

RFID_COUNT_SESSION_COLUMNS = [
    "rfid_count_session_id", "source_session_id", "store_sk", "store_id",
    "primary_sensor_device_sk", "primary_sensor_device_id", "count_method", "scope_type",
    "started_at_ts", "ended_at_ts", "store_timezone", "utc_offset_minutes",
    "trading_date", "hour_of_day", "raw_data_uri", "ingest_timestamp",
    "record_source", "load_timestamp",
]

RFID_READ_EVENT_COLUMNS = [
    "rfid_read_event_sk", "rfid_read_event_id", "tagged_item_sk", "tagged_item_id",
    "is_unregistered_epc", "product_sk", "product_id", "store_sk", "store_id",
    "store_zone_sk", "store_zone_id", "sensor_device_sk", "sensor_device_id",
    "sensing_deployment_sk", "sensing_deployment_id", "rfid_count_session_sk",
    "rfid_count_session_id", "shipment_line_sk", "shipment_line_id", "event_ts",
    "first_seen_ts", "last_seen_ts", "store_timezone", "utc_offset_minutes",
    "trading_date", "hour_of_day", "biz_step_uri", "disposition_uri", "zone_source",
    "direction_code", "direction_confidence", "attribution_confidence",
    "is_stray_suspect", "antenna_id", "read_count", "duplicate_delivery_count",
    "rssi_peak_dbm", "raw_data_uri", "ingest_timestamp", "record_source", "load_timestamp",
]

_BIZ = "https://ref.gs1.org/cbv/BizStep-"
_DISP = "https://ref.gs1.org/cbv/Disp-"


def _base_dates(spark, catalog, inventory_schema):
    return (
        spark.table(f"{catalog}.{inventory_schema}.inventory_position")
        .groupBy("store_sk", "store_id")
        .agg(F.max("date_key").alias("_base_date"))
    )


def _generate_items(ctx, cfg):
    spark, catalog = ctx.spark, ctx.catalog
    css_schema = ctx.schemas["css"]
    product_schema = ctx.schemas["product"]
    inventory_schema = ctx.schemas["inventory"]
    seed = cfg["seed"]

    products = (
        spark.table(f"{catalog}.{product_schema}.product")
        .filter("is_current = TRUE AND gtin IS NOT NULL")
        .select("product_sk", "product_id", "gtin")
        .orderBy("product_sk")
        .limit(cfg["rfid_products"])
    )
    base_dates = _base_dates(spark, catalog, inventory_schema)
    slots = spark.range(cfg["rfid_items_per_product_store"]).withColumnRenamed("id", "_item_slot")

    items = (
        products.crossJoin(base_dates).crossJoin(slots)
        .withColumn(
            "serial_number",
            F.format_string(
                "%012d",
                F.abs(F.hash("product_id", "store_id", "_item_slot", F.lit(seed)))
                % F.lit(999999999999),
            ),
        )
        .withColumn(
            "epc_scheme",
            F.when(
                (F.col("_item_slot") == 0)
                & ((F.abs(F.hash("product_id", F.lit(seed))) % F.lit(20)) == 0),
                F.lit("grai"),
            ).otherwise(F.lit("sgtin")),
        )
        .withColumn(
            "tagged_item_id",
            F.when(
                F.col("epc_scheme") == "grai",
                F.concat(F.lit("urn:epc:id:grai:0614141."),
                         F.abs(F.hash("product_id")), F.lit("."), F.col("serial_number")),
            ).otherwise(
                F.concat(F.lit("urn:epc:id:sgtin:"), F.col("gtin"), F.lit("."), F.col("serial_number"))
            ),
        )
        .withColumn("tagged_item_sk", F.xxhash64("tagged_item_id"))
        .withColumn(
            "current_tid_hex",
            F.upper(F.substring(F.sha2(F.concat("tagged_item_id", F.lit("|carrier-v2")), 256), 1, 24)),
        )
        .withColumn(
            "tag_privacy_state",
            F.element_at(
                F.array(F.lit("active"), F.lit("protected"), F.lit("killed"), F.lit("detached")),
                (F.pmod(F.col("_item_slot"), F.lit(4)) + 1).cast("int"),
            ),
        )
        .withColumn("commissioned_at_ts", F.date_sub("_base_date", 90).cast("timestamp"))
        .withColumn(
            "decommissioned_at_ts",
            F.when(
                F.col("tag_privacy_state").isin("killed", "detached"),
                (F.col("_base_date").cast("timestamp") + F.expr("INTERVAL 1 DAY")),
            ).otherwise(F.lit(None).cast("timestamp")),
        )
        .withColumn("lot_number", F.when(F.col("_item_slot") == 0, F.concat(F.lit("LOT-"), F.col("product_id"))))
        .withColumn("expiry_date", F.when(F.col("_item_slot") == 0, F.date_add("_base_date", 60)))
        .withColumn("product_sk", F.when(F.col("epc_scheme") == "sgtin", F.col("product_sk")))
        .withColumn("product_id", F.when(F.col("epc_scheme") == "sgtin", F.col("product_id")))
        .withColumn("gtin", F.when(F.col("epc_scheme") == "sgtin", F.col("gtin")))
        .withColumn("created_timestamp", F.col("commissioned_at_ts"))
        .withColumn("source_updated_timestamp", F.col("_base_date").cast("timestamp"))
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn("load_timestamp", F.current_timestamp())
    )

    _write(
        spark,
        items.select(*TAGGED_ITEM_COLUMNS),
        f"{catalog}.{css_schema}.tagged_item",
        TAGGED_ITEM_COLUMNS,
        ctx.mode,
    )
    return items


def _generate_sessions(ctx, cfg):
    spark, catalog = ctx.spark, ctx.catalog
    css_schema = ctx.schemas["css"]
    inventory_schema = ctx.schemas["inventory"]

    devices = (
        spark.table(f"{catalog}.{css_schema}.sensor_device")
        .filter("is_current = TRUE AND device_type = 'rfid_reader'")
        .withColumn(
            "count_method",
            F.when(F.col("model").contains("HANDHELD"), F.lit("handheld_sweep"))
            .when(F.col("model").contains("ROBOT"), F.lit("robot_sweep"))
            .otherwise(F.lit("fixed_window")),
        )
        .withColumn(
            "_device_rank",
            F.row_number().over(Window.partitionBy("store_id", "count_method").orderBy("sensor_device_id")),
        )
        .filter("_device_rank = 1")
        .select(
            "store_id", "count_method",
            F.col("sensor_device_sk").alias("primary_sensor_device_sk"),
            F.col("sensor_device_id").alias("primary_sensor_device_id"),
        )
    )
    slots = spark.range(cfg["rfid_sessions_per_store"]).withColumnRenamed("id", "_session_idx")
    sessions = (
        _base_dates(spark, catalog, inventory_schema).crossJoin(slots)
        .withColumn(
            "count_method",
            F.element_at(
                F.array(F.lit("fixed_window"), F.lit("handheld_sweep"), F.lit("robot_sweep")),
                (F.pmod(F.col("_session_idx"), F.lit(3)) + 1).cast("int"),
            ),
        )
        .join(F.broadcast(devices), ["store_id", "count_method"], "left")
        .withColumn("scope_type", F.when(F.col("_session_idx") == 1, F.lit("partial")).otherwise(F.lit("full_store")))
        .withColumn("hour_of_day", F.when(F.col("_session_idx") == 0, F.lit(21)).otherwise(F.lit(12)).cast("tinyint"))
        .withColumn(
            "started_at_ts",
            F.col("_base_date").cast("timestamp")
            + F.expr("INTERVAL 1 HOUR") * (F.col("hour_of_day") + F.lit(5)),
        )
        .withColumn("ended_at_ts", F.col("started_at_ts") + F.expr("INTERVAL 90 MINUTES"))
        .withColumn(
            "source_session_id",
            F.concat(F.lit("SYN-RFID-"), F.col("count_method"), F.lit("-"),
                     F.col("store_id"), F.lit("-"), F.col("_session_idx")),
        )
        .withColumn("rfid_count_session_id", F.concat_ws("|", "store_id", "source_session_id"))
        .withColumn("store_timezone", F.lit("America/New_York"))
        .withColumn("utc_offset_minutes", F.lit(-300).cast("smallint"))
        .withColumn("trading_date", F.col("_base_date"))
        .withColumn("raw_data_uri", F.concat(F.lit("/synthetic/rfid/sessions/"), F.col("source_session_id")))
        # The header must land before linked events. Generated events begin ten minutes
        # into the session, so this remains true for fixed, handheld, and robot sessions.
        .withColumn("ingest_timestamp", F.col("started_at_ts") + F.expr("INTERVAL 30 SECONDS"))
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn("load_timestamp", F.current_timestamp())
    )
    _write(
        spark,
        sessions.select(*RFID_COUNT_SESSION_COLUMNS),
        f"{catalog}.{css_schema}.rfid_count_session",
        RFID_COUNT_SESSION_COLUMNS,
        ctx.mode,
    )
    return (
        spark.table(f"{catalog}.{css_schema}.rfid_count_session")
        .withColumn("_session_idx", F.regexp_extract("source_session_id", r"-(\d+)$", 1).cast("long"))
        .select(
            "rfid_count_session_sk", "rfid_count_session_id", "store_id",
            "started_at_ts", "ended_at_ts", "trading_date", "hour_of_day",
            "count_method", "_session_idx",
        )
    )


def _generate_events(ctx, cfg, items, sessions):
    spark, catalog = ctx.spark, ctx.catalog
    css_schema = ctx.schemas["css"]
    logistics_schema = ctx.schemas["logistics"]
    seed = cfg["seed"]

    offsets = (
        dg.DataGenerator(
            spark,
            name="rfid_event_offsets",
            rows=cfg["rfid_events_per_item"],
            partitions=1,
            randomSeedMethod="fixed",
            randomSeed=seed,
        )
        .withIdOutput()
        .build()
        .withColumnRenamed("id", "_event_idx")
    )

    device_lookup = (
        spark.table(f"{catalog}.{css_schema}.sensor_device")
        .filter("is_current = TRUE AND device_type = 'rfid_reader'")
        .withColumn(
            "_device_kind",
            F.when(F.col("model").contains("BACKROOM"), F.lit("fixed_backroom"))
            .when(F.col("model").contains("ENTRANCE"), F.lit("fixed_entrance"))
            .when(F.col("model").contains("HANDHELD"), F.lit("handheld"))
            .when(F.col("model").contains("ROBOT"), F.lit("robot")),
        )
        .filter("_device_kind IS NOT NULL")
        .select(
            "store_id", "_device_kind", "sensor_device_sk", "sensor_device_id",
            "sensing_deployment_sk", "sensing_deployment_id",
            F.col("store_zone_sk").alias("_device_zone_sk"),
            F.col("store_zone_id").alias("_device_zone_id"),
            "is_directional",
        )
    )
    zone_lookup = (
        spark.table(f"{catalog}.{css_schema}.store_zone")
        .filter("is_current = TRUE")
        .groupBy("store_id")
        .agg(
            F.max(F.when(F.col("zone_code") == "backroom", F.col("store_zone_sk"))).alias("_backroom_sk"),
            F.max(F.when(F.col("zone_code") == "backroom", F.col("store_zone_id"))).alias("_backroom_id"),
            F.max(F.when(F.col("zone_code") == "aisle", F.col("store_zone_sk"))).alias("_aisle_sk"),
            F.max(F.when(F.col("zone_code") == "aisle", F.col("store_zone_id"))).alias("_aisle_id"),
        )
    )
    shipment_lookup = (
        spark.table(f"{catalog}.{logistics_schema}.shipment_line").alias("sl")
        .join(
            spark.table(f"{catalog}.{logistics_schema}.shipment").alias("s"),
            F.col("sl.shipment_sk") == F.col("s.shipment_sk"),
            "inner",
        )
        .select(
            F.col("s.destination_store_id").alias("store_id"),
            F.col("sl.product_id").alias("product_id"),
            F.col("sl.shipment_line_sk"),
            F.col("sl.shipment_line_id"),
        )
        .withColumn(
            "_shipment_rank",
            F.row_number().over(Window.partitionBy("store_id", "product_id").orderBy("shipment_line_sk")),
        )
        .filter("_shipment_rank = 1")
        .drop("_shipment_rank")
    )

    events = (
        items.crossJoin(offsets)
        .withColumn(
            "_session_idx",
            F.when(
                F.col("_event_idx") == 3,
                F.pmod(F.abs(F.hash("tagged_item_id", F.lit(seed))), F.lit(cfg["rfid_sessions_per_store"])),
            ).otherwise(F.lit(None).cast("long")),
        )
        .join(F.broadcast(sessions), ["store_id", "_session_idx"], "left")
        .withColumn(
            "_device_kind",
            F.when(F.col("_event_idx") == 0, F.lit("fixed_backroom"))
            .when(F.col("_event_idx") == 1, F.lit("handheld"))
            .when(F.col("_event_idx") == 2, F.lit("robot"))
            .when(
                F.col("_event_idx") == 3,
                F.when(F.col("count_method") == "fixed_window", F.lit("fixed_backroom"))
                .when(F.col("count_method") == "handheld_sweep", F.lit("handheld"))
                .otherwise(F.lit("robot")),
            )
            .otherwise(F.lit("fixed_entrance")),
        )
        .join(F.broadcast(device_lookup), ["store_id", "_device_kind"], "left")
        .join(F.broadcast(zone_lookup), "store_id", "left")
        .join(F.broadcast(shipment_lookup), ["store_id", "product_id"], "left")
        .withColumn(
            "event_ts",
            F.when(F.col("rfid_count_session_sk").isNotNull(),
                   F.col("started_at_ts") + F.expr("INTERVAL 10 MINUTES"))
            .otherwise(
                F.col("_base_date").cast("timestamp")
                + F.expr("INTERVAL 1 HOUR") * (F.lit(5) + F.col("_event_idx") * F.lit(4))
            ),
        )
        .withColumn("first_seen_ts", F.col("event_ts") - F.expr("INTERVAL 2 SECONDS"))
        .withColumn("last_seen_ts", F.col("event_ts"))
        .withColumn(
            "zone_source",
            F.when(F.col("_device_kind").startswith("fixed"), F.lit("device_placement"))
            .when(F.col("_device_kind") == "handheld", F.lit("operator_declared"))
            .otherwise(F.lit("platform_localization")),
        )
        .withColumn(
            "store_zone_sk",
            F.when(F.col("_device_kind").startswith("fixed"), F.col("_device_zone_sk"))
            .when(F.col("_device_kind") == "handheld", F.col("_backroom_sk"))
            .otherwise(F.col("_aisle_sk")),
        )
        .withColumn(
            "store_zone_id",
            F.when(F.col("_device_kind").startswith("fixed"), F.col("_device_zone_id"))
            .when(F.col("_device_kind") == "handheld", F.col("_backroom_id"))
            .otherwise(F.col("_aisle_id")),
        )
        .withColumn("_unaccounted", (F.abs(F.hash("tagged_item_id", F.lit(seed + 9))) % F.lit(10)) == 0)
        .withColumn(
            "biz_step_uri",
            F.when(F.col("_event_idx") == 0, F.lit(_BIZ + "receiving"))
            .when(F.col("_event_idx") == 1, F.lit(_BIZ + "storing"))
            .when(F.col("_event_idx") == 2, F.lit(_BIZ + "stocking"))
            .when(F.col("_event_idx") == 3, F.lit(_BIZ + "cycle_counting"))
            .when((F.col("_event_idx") == 4) & (F.col("tag_privacy_state") == "killed"), F.lit(_BIZ + "killing"))
            .when((F.col("_event_idx") == 4) & ~F.col("_unaccounted"), F.lit(_BIZ + "retail_selling"))
            .otherwise(F.lit(_BIZ + "inspecting")),
        )
        .withColumn(
            "disposition_uri",
            F.when(F.col("_event_idx") == 0, F.lit(_DISP + "sellable_not_accessible"))
            .when(F.col("_event_idx").isin(1, 2, 3), F.lit(_DISP + "sellable_accessible"))
            .when((F.col("_event_idx") == 4) & ~F.col("_unaccounted"), F.lit(_DISP + "retail_sold"))
            .otherwise(F.lit(_DISP + "unknown")),
        )
        .withColumn("direction_code", F.when(F.col("_event_idx") == 5, F.lit("out")).otherwise(F.lit("not_applicable")))
        .withColumn("direction_confidence", F.when(F.col("_event_idx") == 5, F.lit(0.96)).otherwise(F.lit(None).cast("double")))
        .withColumn("attribution_confidence", F.when(F.col("_event_idx") == 2, F.lit(0.82)).otherwise(F.lit(0.97)))
        .withColumn("is_stray_suspect", (F.col("_event_idx") == 2) & ((F.abs(F.hash("tagged_item_id")) % F.lit(25)) == 0))
        .withColumn("_unregistered", (F.col("_event_idx") == 0) & ((F.abs(F.hash("tagged_item_id")) % F.lit(50)) == 0))
        .withColumn(
            "tagged_item_id",
            F.when(F.col("_unregistered"), F.concat(F.lit("urn:epc:id:sgtin:9999999.99999."), F.col("serial_number")))
            .otherwise(F.col("tagged_item_id")),
        )
        .withColumn("is_unregistered_epc", F.col("_unregistered"))
        .withColumn("tagged_item_sk", F.when(~F.col("_unregistered"), F.xxhash64("tagged_item_id")))
        .withColumn("product_sk", F.when(~F.col("_unregistered"), F.col("product_sk")))
        .withColumn("product_id", F.when(~F.col("_unregistered"), F.col("product_id")))
        .withColumn("_linked_receiving", (F.col("_event_idx") == 0) & ~F.col("_unregistered") & ((F.abs(F.hash("tagged_item_id")) % F.lit(2)) == 0))
        .withColumn("shipment_line_sk", F.when(F.col("_linked_receiving"), F.col("shipment_line_sk")))
        .withColumn("shipment_line_id", F.when(F.col("_linked_receiving"), F.col("shipment_line_id")))
        .withColumn("store_timezone", F.lit("America/New_York"))
        .withColumn("utc_offset_minutes", F.lit(-300).cast("smallint"))
        .withColumn("trading_date", F.to_date(F.col("event_ts") - F.expr("INTERVAL 5 HOURS")))
        .withColumn("hour_of_day", F.hour(F.col("event_ts") - F.expr("INTERVAL 5 HOURS")).cast("tinyint"))
        .withColumn("antenna_id", F.when(F.col("_device_kind").startswith("fixed"), F.lit("ANT-1")))
        .withColumn("read_count", (F.lit(2) + F.pmod(F.abs(F.hash("tagged_item_id", "_event_idx")), F.lit(8))).cast("bigint"))
        .withColumn("duplicate_delivery_count", F.when((F.abs(F.hash("tagged_item_id", "_event_idx")) % F.lit(100)) == 0, F.lit(1)).otherwise(F.lit(0)).cast("bigint"))
        .withColumn("rssi_peak_dbm", (F.lit(-72.0) + F.pmod(F.abs(F.hash("tagged_item_id")), F.lit(30))).cast("double"))
        .withColumn("raw_data_uri", F.concat(F.lit("/synthetic/rfid/events/"), F.col("tagged_item_id")))
        .withColumn(
            "ingest_timestamp",
            F.when(F.col("_device_kind") == "handheld", F.col("event_ts") + F.expr("INTERVAL 1 DAY"))
            .otherwise(F.col("event_ts") + F.expr("INTERVAL 30 SECONDS")),
        )
        .withColumn("rfid_read_event_id", F.concat_ws("|", "tagged_item_id", F.unix_timestamp("event_ts"), "sensor_device_id"))
        .withColumn("rfid_read_event_sk", F.xxhash64("rfid_read_event_id"))
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn("load_timestamp", F.current_timestamp())
    )

    return _write(
        spark,
        events.select(*RFID_READ_EVENT_COLUMNS),
        f"{catalog}.{css_schema}.rfid_read_event",
        RFID_READ_EVENT_COLUMNS,
        ctx.mode,
    )


def generate_rfid(ctx, cfg):
    items = _generate_items(ctx, cfg)
    sessions = _generate_sessions(ctx, cfg)
    _generate_events(ctx, cfg, items, sessions)
    print("[ordm] connected-store-signals RFID generation complete.")
