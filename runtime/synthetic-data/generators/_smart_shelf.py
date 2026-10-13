# ============================================================
# ORDM · Synthetic data · Connected Store Signals · Smart Shelf helper
# Version: 0.5
# Generated: 2026-08-21
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-08-21
# ============================================================
# Plain helper invoked by connected_store_signals.py. It deliberately has no run(ctx):
# the generator registry permits exactly one provider for the css schema key.
# ============================================================

import os
import sys

import dbldatagen as dg
from pyspark.sql import functions as F
from pyspark.sql.window import Window

try:
    from _common import RECORD_SOURCE, _frac, _write
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from _common import RECORD_SOURCE, _frac, _write


SHELF_POSITION_ASSIGNMENT_COLUMNS = [
    "shelf_position_assignment_id", "store_sk", "store_id", "store_zone_sk",
    "store_zone_id", "product_sk", "product_id", "expected_facing_count",
    "min_facing_count", "facing_sequence", "assignment_source", "planogram_id",
    "assignment_status", "valid_from_ts", "valid_to_ts", "effective_from_date",
    "effective_to_date", "is_current", "created_timestamp",
    "source_updated_timestamp", "record_source", "load_timestamp",
]

SHELF_STATE_OBSERVATION_COLUMNS = [
    "shelf_state_observation_sk", "shelf_state_observation_id", "source_capture_id",
    "shelf_position_assignment_sk", "shelf_position_assignment_id", "store_sk",
    "store_id", "store_zone_sk", "store_zone_id", "product_sk", "product_id",
    "sensor_device_sk", "sensor_device_id", "sensing_deployment_sk",
    "sensing_deployment_id", "observation_ts", "store_timezone",
    "utc_offset_minutes", "trading_date", "hour_of_day", "shelf_state",
    "observed_facing_count", "min_facing_threshold", "estimated_unit_count",
    "estimated_weight_grams", "pick_count_since_prior", "put_count_since_prior",
    "is_gap_detected", "is_misplaced_detected", "is_price_tag_mismatch_detected",
    "zone_source", "attribution_confidence", "measurement_validity",
    "arrival_completeness", "confidence_score", "is_occluded", "coverage_ratio",
    "restatement_version", "restated_at_timestamp", "raw_data_uri",
    "ingest_timestamp", "record_source", "load_timestamp",
]

ESL_LABEL_COLUMNS = [
    "esl_label_id", "store_sk", "store_id", "sensor_device_sk", "sensor_device_id",
    "display_technology", "display_model", "display_size_inches",
    "battery_life_class", "is_nfc_capable", "is_qr_capable", "label_status",
    "commissioned_date", "decommissioned_date", "effective_from_date",
    "effective_to_date", "is_current", "created_timestamp",
    "source_updated_timestamp", "record_source", "load_timestamp",
]

ESL_LABEL_ASSIGNMENT_COLUMNS = [
    "esl_label_assignment_id", "esl_label_sk", "esl_label_id", "product_sk",
    "product_id", "store_sk", "store_id", "store_zone_sk", "store_zone_id",
    "encoded_gtin", "encoded_digital_link_uri", "binding_source",
    "is_binding_verified", "binding_status", "valid_from_ts", "valid_to_ts",
    "effective_from_date", "effective_to_date", "is_current", "created_timestamp",
    "source_updated_timestamp", "record_source", "load_timestamp",
]

ESL_PRICE_OBSERVATION_COLUMNS = [
    "esl_price_observation_sk", "esl_price_observation_id", "source_observation_id",
    "esl_label_sk", "esl_label_id", "esl_label_assignment_sk",
    "esl_label_assignment_id", "product_sk", "product_id", "store_sk", "store_id",
    "store_zone_sk", "store_zone_id", "observed_at_ts", "store_timezone",
    "utc_offset_minutes", "trading_date", "hour_of_day", "observation_source",
    "displayed_price", "displayed_currency_code", "displayed_unit_price",
    "unit_price_uom", "displayed_promo_indicator", "displayed_disclosure_indicator",
    "displayed_disclosure_text", "price_of_record", "price_of_record_currency_code",
    "price_of_record_source", "price_of_record_price_type",
    "price_of_record_effective_ts", "is_price_match",
    "display_sync_latency_seconds", "sensing_derived_input_flag", "raw_data_uri",
    "ingest_timestamp", "record_source", "load_timestamp",
]


# Generator-owned enum contracts. Tests compare these lists with the deployed Delta
# CHECK constraints using set equality, not subset containment: Phase 5 requires the
# default dataset to exercise every Smart Shelf enum value.
ASSIGNMENT_SOURCES = ["planogram", "manual", "vendor"]
ASSIGNMENT_STATUSES = ["active", "suspended", "retired"]
SHELF_STATES = ["in_stock", "low_stock", "out_of_stock", "misplaced", "unknown"]
SHELF_ZONE_SOURCES = ["device_placement", "operator_declared", "platform_localization"]
MEASUREMENT_VALIDITIES = ["valid", "degraded", "invalid", "imputed"]
ARRIVAL_COMPLETENESS_VALUES = ["complete", "incomplete", "late_arrived", "precheck"]
DISPLAY_TECHNOLOGIES = ["eink_mono", "eink_multicolor", "lcd", "segment"]
BATTERY_LIFE_CLASSES = ["under_3y", "y3_to_5", "y5_to_10", "over_10y"]
LABEL_STATUSES = ["active", "inactive", "faulty", "retired"]
BINDING_SOURCES = ["platform", "manual"]
BINDING_STATUSES = ["active", "suspended", "retired"]
PRICE_OBSERVATION_SOURCES = ["platform_ack", "shelf_cv", "manual_audit"]
PRICE_OF_RECORD_SOURCES = [
    "pricing_platform", "product_price", "pos_system", "scale_plu", "manual",
]


_MIN_SCENARIO_VOLUMES = {
    "positions_per_store": 3,
    "products_per_position": 1,
    "captures_per_day_per_platform": 6,
    "price_change_observations": 5,
}


_AUDIT_TS = "2024-01-01 00:00:00"


def _fixed_ts():
    return F.lit(_AUDIT_TS).cast("timestamp")


def validate_smart_shelf_config(cfg):
    """Reject seed volumes too small to preserve the mandatory Phase 5 scenarios."""
    violations = {
        key: (cfg.get(key), minimum)
        for key, minimum in _MIN_SCENARIO_VOLUMES.items()
        if int(cfg.get(key, 0)) < minimum
    }
    if violations:
        detail = ", ".join(
            f"{key}={actual!r} (minimum {minimum})"
            for key, (actual, minimum) in sorted(violations.items())
        )
        raise ValueError(f"Smart Shelf seed volumes cannot cover required scenarios: {detail}")


def _resolve_zone_parent_sks(spark, fq_zone):
    spark.sql(f"""
        MERGE INTO {fq_zone} t
        USING (
          SELECT c.store_zone_sk AS child_sk, p.store_zone_sk AS parent_sk
          FROM {fq_zone} c
          JOIN {fq_zone} p
            ON c.parent_zone_id = p.store_zone_id AND p.is_current = TRUE
          WHERE c.parent_zone_id IS NOT NULL
        ) s
        ON t.store_zone_sk = s.child_sk
        WHEN MATCHED THEN UPDATE SET t.parent_zone_sk = s.parent_sk
    """)


def generate_smart_shelf_zones(ctx, cfg, store_zone_columns):
    """Append area → aisle → bay → shelf-position rows below each store site."""
    spark, catalog = ctx.spark, ctx.catalog
    css_schema, store_schema = ctx.schemas["css"], ctx.schemas["store"]
    n_positions = cfg["positions_per_store"]
    n_parts = max(1, min(16, n_positions))

    stores = (spark.table(f"{catalog}.{store_schema}.store")
              .filter("is_current = TRUE")
              .select("store_sk", "store_id"))
    idx = spark.range(n_positions, numPartitions=n_parts).withColumnRenamed("id", "_position_idx")
    keys = (stores.crossJoin(idx)
            .withColumn("_aisle_num", (F.floor(F.col("_position_idx") / F.lit(6)) + 1).cast("int"))
            .withColumn("_bay_num", (F.floor((F.col("_position_idx") % F.lit(6)) / F.lit(2)) + 1).cast("int"))
            .withColumn("_position_num", ((F.col("_position_idx") % F.lit(2)) + 1).cast("int"))
            .withColumn("_area_id", F.concat(F.lit("SZ-"), "store_id", F.lit("-AREA-GROCERY")))
            .withColumn("_aisle_id", F.concat(
                F.lit("SZ-"), "store_id", F.lit("-AISLE-"), F.lpad("_aisle_num", 2, "0")))
            .withColumn("_bay_id", F.concat(
                F.col("_aisle_id"), F.lit("-BAY-"), F.lpad("_bay_num", 2, "0")))
            .withColumn("_position_id", F.concat(
                F.col("_bay_id"), F.lit("-SHELF-01-POS-"), F.lpad("_position_num", 2, "0"))))

    area = (keys.select("store_sk", "store_id", "_area_id").distinct()
            .withColumn("store_zone_id", F.col("_area_id"))
            .withColumn("zone_code", F.lit("area_grocery"))
            .withColumn("zone_name", F.lit("Grocery Sales Area"))
            .withColumn("zone_type", F.lit("area"))
            .withColumn("parent_zone_id", F.concat(F.lit("SZ-"), "store_id", F.lit("-SITE")))
            .withColumn("hierarchy_depth", F.lit(1))
            .withColumn("hierarchy_path", F.concat(F.lit("/"), "store_id", F.lit("/area-grocery")))
            .withColumn("area_sqm", F.lit(480.0).cast("decimal(12,2)"))
            .withColumn("capacity_persons", F.lit(500).cast("int"))
            .withColumn("is_sales_floor", F.lit(True))
            .withColumn("is_countable", F.lit(False)))

    aisle = (keys.select("store_sk", "store_id", "_area_id", "_aisle_id", "_aisle_num").distinct()
             .withColumn("store_zone_id", F.col("_aisle_id"))
             .withColumn("zone_code", F.concat(F.lit("aisle_"), F.lpad("_aisle_num", 2, "0")))
             .withColumn("zone_name", F.concat(F.lit("Aisle "), "_aisle_num"))
             .withColumn("zone_type", F.lit("aisle"))
             .withColumn("parent_zone_id", F.col("_area_id"))
             .withColumn("hierarchy_depth", F.lit(2))
             .withColumn("hierarchy_path", F.concat(
                 F.lit("/"), "store_id", F.lit("/area-grocery/aisle-"), F.lpad("_aisle_num", 2, "0")))
             .withColumn("area_sqm", F.lit(60.0).cast("decimal(12,2)"))
             .withColumn("capacity_persons", F.lit(80).cast("int"))
             .withColumn("is_sales_floor", F.lit(True))
             .withColumn("is_countable", F.lit(False)))

    bay = (keys.select("store_sk", "store_id", "_aisle_id", "_bay_id", "_aisle_num", "_bay_num").distinct()
           .withColumn("store_zone_id", F.col("_bay_id"))
           .withColumn("zone_code", F.concat(
               F.lit("aisle_"), F.lpad("_aisle_num", 2, "0"),
               F.lit("_bay_"), F.lpad("_bay_num", 2, "0")))
           .withColumn("zone_name", F.concat(F.lit("Aisle "), "_aisle_num", F.lit(" Bay "), "_bay_num"))
           .withColumn("zone_type", F.lit("bay"))
           .withColumn("parent_zone_id", F.col("_aisle_id"))
           .withColumn("hierarchy_depth", F.lit(3))
           .withColumn("hierarchy_path", F.concat(
               F.lit("/"), "store_id", F.lit("/area-grocery/aisle-"), F.lpad("_aisle_num", 2, "0"),
               F.lit("/bay-"), F.lpad("_bay_num", 2, "0")))
           .withColumn("area_sqm", F.lit(8.0).cast("decimal(12,2)"))
           .withColumn("capacity_persons", F.lit(12).cast("int"))
           .withColumn("is_sales_floor", F.lit(True))
           .withColumn("is_countable", F.lit(False)))

    position = (keys
                .withColumn("store_zone_id", F.col("_position_id"))
                .withColumn("zone_code", F.concat(
                    F.lit("a"), F.lpad("_aisle_num", 2, "0"), F.lit("_b"),
                    F.lpad("_bay_num", 2, "0"), F.lit("_p"), F.lpad("_position_num", 2, "0")))
                .withColumn("zone_name", F.concat(
                    F.lit("Aisle "), "_aisle_num", F.lit(" Bay "), "_bay_num",
                    F.lit(" Shelf 1 Position "), "_position_num"))
                .withColumn("zone_type", F.lit("shelf_position"))
                .withColumn("parent_zone_id", F.col("_bay_id"))
                .withColumn("hierarchy_depth", F.lit(4))
                .withColumn("hierarchy_path", F.concat(
                    F.lit("/"), "store_id", F.lit("/area-grocery/aisle-"), F.lpad("_aisle_num", 2, "0"),
                    F.lit("/bay-"), F.lpad("_bay_num", 2, "0"),
                    F.lit("/shelf-01-pos-"), F.lpad("_position_num", 2, "0")))
                .withColumn("area_sqm", F.lit(0.25).cast("decimal(12,2)"))
                .withColumn("capacity_persons", F.lit(None).cast("int"))
                .withColumn("is_sales_floor", F.lit(True))
                .withColumn("is_countable", F.lit(False)))

    common = ["store_sk", "store_id", "store_zone_id", "zone_code", "zone_name", "zone_type",
              "parent_zone_id", "hierarchy_depth", "hierarchy_path", "area_sqm",
              "capacity_persons", "is_sales_floor", "is_countable"]
    zones = area.select(*common).unionByName(aisle.select(*common)).unionByName(
        bay.select(*common)).unionByName(position.select(*common))
    zones = (zones
             .withColumn("parent_zone_sk", F.lit(None).cast("bigint"))
             .withColumn("effective_from_date", F.lit("2024-01-01").cast("date"))
             .withColumn("effective_to_date", F.lit(None).cast("date"))
             .withColumn("is_current", F.lit(True))
             .withColumn("created_timestamp", _fixed_ts())
             .withColumn("source_updated_timestamp", _fixed_ts())
             .withColumn("record_source", F.lit(RECORD_SOURCE))
             .withColumn("load_timestamp", _fixed_ts()))
    fq_zone = f"{catalog}.{css_schema}.store_zone"
    _write(spark, zones, fq_zone, store_zone_columns, "append")
    _resolve_zone_parent_sks(spark, fq_zone)


def generate_smart_shelf_deployments(ctx, cfg, deployment_columns):
    """Append weight and CV shelf-availability governance deployments per store."""
    spark, catalog = ctx.spark, ctx.catalog
    css_schema = ctx.schemas["css"]
    base = (spark.table(f"{catalog}.{css_schema}.sensing_deployment")
            .filter("is_current = TRUE AND sensing_deployment_id LIKE '%-ENV'")
            .select(*deployment_columns))
    variants = F.array(
        F.struct(F.lit("WEIGHT").alias("suffix"), F.lit("weight").alias("method")),
        F.struct(F.lit("CV").alias("suffix"), F.lit("video_cv").alias("method")),
    )
    deployments = (base.withColumn("_variant", F.explode(variants))
                   .withColumn("sensing_deployment_id", F.concat(
                       F.regexp_replace("sensing_deployment_id", r"-ENV$", ""),
                       F.lit("-SHELF-"), F.col("_variant.suffix")))
                   .withColumn("deployment_name", F.concat(
                       F.lit("Smart Shelf "), F.lower(F.col("_variant.suffix")),
                       F.lit(" sensing, store "), "store_id"))
                   .withColumn("sensing_method_code", F.col("_variant.method"))
                   .withColumn("sensing_purpose_code", F.lit("shelf_availability"))
                   .withColumn("lawful_basis_code", F.lit("not_personal_data"))
                   .withColumn("ai_act_notice_status", F.lit("not_applicable"))
                   .withColumn("consent_required_flag", F.lit("not_required"))
                   .withColumn("optout_mechanism_code", F.lit("not_applicable"))
                   .withColumn("staff_exclusion_method", F.lit("none"))
                   .withColumn("staff_exclusion_stage", F.lit("none"))
                   .withColumn("record_source", F.lit(RECORD_SOURCE))
                   .withColumn("load_timestamp", _fixed_ts())
                   .drop("_variant"))
    _write(spark, deployments, f"{catalog}.{css_schema}.sensing_deployment",
           deployment_columns, "append")


def _complete_device(df):
    return (df
            .withColumn("manufacturer", F.lit("MFR-SMART-SHELF"))
            .withColumn("serial_number", F.col("sensor_device_id"))
            .withColumn("firmware_version", F.lit("1.0.0"))
            .withColumn("is_directional", F.lit(False))
            .withColumn("supports_dwell", F.lit(False))
            .withColumn("supports_occupancy", F.lit(False))
            .withColumn("detection_limit_count", F.lit(None).cast("int"))
            .withColumn("battery_powered", F.col("device_type") == F.lit("shelf_sensor"))
            .withColumn("brick_class_iri", F.lit(None).cast("string"))
            .withColumn("unit_iri", F.when(F.col("sensing_technology") == "load_cell",
                                            F.lit("http://qudt.org/vocab/unit/GM")))
            .withColumn("uom_code", F.when(F.col("sensing_technology") == "load_cell", F.lit("GRM")))
            .withColumn("bacnet_device_id", F.lit(None).cast("string"))
            .withColumn("bacnet_object_ref", F.lit(None).cast("string"))
            .withColumn("bacnet_out_of_service", F.lit(None).cast("boolean"))
            .withColumn("opc_ua_node_id", F.lit(None).cast("string"))
            .withColumn("sparkplug_edge_node_id", F.lit(None).cast("string"))
            .withColumn("calibration_certificate_id", F.when(
                F.col("sensing_technology") == "load_cell", F.concat(F.lit("CAL-"), "sensor_device_id")))
            .withColumn("calibration_valid_from", F.when(
                F.col("sensing_technology") == "load_cell", F.lit("2024-01-01").cast("date")))
            .withColumn("calibration_valid_to", F.when(
                F.col("sensing_technology") == "load_cell", F.lit("2030-01-01").cast("date")))
            .withColumn("accuracy_tolerance", F.when(
                F.col("sensing_technology") == "load_cell", F.lit(5.0)).cast("double"))
            .withColumn("probe_type", F.lit("none"))
            .withColumn("is_backup_device", F.lit(False))
            .withColumn("equipment_sk", F.lit(None).cast("bigint"))
            .withColumn("equipment_id", F.lit(None).cast("string"))
            .withColumn("device_status", F.lit("active"))
            .withColumn("installed_date", F.lit("2024-01-01").cast("date"))
            .withColumn("decommissioned_date", F.lit(None).cast("date"))
            .withColumn("effective_from_date", F.lit("2024-01-01").cast("date"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", _fixed_ts())
            .withColumn("source_updated_timestamp", _fixed_ts())
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", _fixed_ts()))


def generate_smart_shelf_devices(ctx, cfg, sensor_device_columns):
    """Append fixed load cells, one mobile CV platform, and one ESL gateway per store."""
    spark, catalog = ctx.spark, ctx.catalog
    css_schema = ctx.schemas["css"]
    zones = (spark.table(f"{catalog}.{css_schema}.store_zone")
             .filter("is_current = TRUE")
             .select("store_zone_sk", "store_zone_id", "store_sk", "store_id", "zone_type"))
    deps = (spark.table(f"{catalog}.{css_schema}.sensing_deployment")
            .filter("is_current = TRUE AND sensing_purpose_code = 'shelf_availability'")
            .select("sensing_deployment_sk", "sensing_deployment_id", "store_id", "sensing_method_code"))
    weight_dep = deps.filter(F.col("sensing_method_code") == "weight").drop("sensing_method_code")
    cv_dep = deps.filter(F.col("sensing_method_code") == "video_cv").drop("sensing_method_code")

    fixed = (zones.filter(F.col("zone_type") == "shelf_position")
             .join(F.broadcast(weight_dep), "store_id", "inner")
             .withColumn("sensor_device_id", F.concat(F.lit("SDV-"), "store_zone_id", F.lit("-LOAD")))
             .withColumn("device_type", F.lit("shelf_sensor"))
             .withColumn("sensing_technology", F.lit("load_cell"))
             .withColumn("device_role", F.lit("sense"))
             .withColumn("model", F.lit("LOAD-CELL-01"))
             .withColumn("is_mobile_platform", F.lit(False)))

    area = zones.filter(F.col("zone_type") == "area")
    robot = (area.join(F.broadcast(cv_dep), "store_id", "inner")
             .withColumn("sensor_device_id", F.concat(F.lit("SDV-"), "store_id", F.lit("-SHELF-ROBOT")))
             .withColumn("device_type", F.lit("camera"))
             .withColumn("sensing_technology", F.lit("video_cv"))
             .withColumn("device_role", F.lit("sense"))
             .withColumn("model", F.lit("MOBILE-CV-01"))
             .withColumn("is_mobile_platform", F.lit(True)))
    gateway = (area.join(F.broadcast(cv_dep), "store_id", "inner")
               .withColumn("sensor_device_id", F.concat(F.lit("SDV-"), "store_id", F.lit("-ESL-GATEWAY")))
               .withColumn("device_type", F.lit("esl_gateway"))
               .withColumn("sensing_technology", F.lit(None).cast("string"))
               .withColumn("device_role", F.lit("actuate"))
               .withColumn("model", F.lit("ESL-GATEWAY-01"))
               .withColumn("is_mobile_platform", F.lit(False)))

    devices = _complete_device(fixed).unionByName(_complete_device(robot)).unionByName(
        _complete_device(gateway))
    _write(spark, devices, f"{catalog}.{css_schema}.sensor_device",
           sensor_device_columns, "append")


def _active_assignment_seed(ctx, cfg):
    spark, catalog = ctx.spark, ctx.catalog
    css_schema, product_schema = ctx.schemas["css"], ctx.schemas["product"]
    positions = (spark.table(f"{catalog}.{css_schema}.store_zone")
                 .filter("is_current = TRUE AND zone_type = 'shelf_position'")
                 .select("store_zone_sk", "store_zone_id", "store_sk", "store_id"))
    products = (spark.table(f"{catalog}.{product_schema}.product")
                .filter("is_current = TRUE")
                .select("product_sk", "product_id", "gtin"))
    # Rank products once per position, then retain the configured number. This makes
    # product choices distinct within a position and avoids multiplying the candidate
    # frame by products_per_position before the window.
    candidates = positions.crossJoin(products)
    rank_w = Window.partitionBy("store_zone_id").orderBy(
        F.abs(F.xxhash64("store_zone_id", "product_id")), "product_id")
    return (candidates.withColumn("_product_rank", F.row_number().over(rank_w))
            .filter(F.col("_product_rank") <= F.lit(cfg["products_per_position"]))
            .withColumn("_product_slot", F.col("_product_rank") - F.lit(1))
            .drop("_product_rank"))


def generate_shelf_position_assignment(ctx, cfg):
    spark, catalog = ctx.spark, ctx.catalog
    css_schema = ctx.schemas["css"]
    seed = cfg["seed"]
    source_w = Window.partitionBy("store_id").orderBy("shelf_position_assignment_id")
    base = (_active_assignment_seed(ctx, cfg)
            .withColumn("shelf_position_assignment_id", F.concat_ws("|", "store_zone_id", "product_id"))
            .withColumn("_enum_rank", F.row_number().over(source_w) - F.lit(1))
            .withColumn("expected_facing_count", (F.lit(4) + (F.abs(F.hash(
                "shelf_position_assignment_id", F.lit(seed))) % F.lit(5))).cast("int"))
            .withColumn("min_facing_count", F.greatest(
                F.lit(2), (F.col("expected_facing_count") / F.lit(2)).cast("int")))
            .withColumn("facing_sequence", (F.col("_product_slot") + 1).cast("int"))
            .withColumn("assignment_source", F.element_at(
                F.array(*[F.lit(value) for value in ASSIGNMENT_SOURCES]),
                F.pmod(F.col("_enum_rank"), F.lit(len(ASSIGNMENT_SOURCES))) + F.lit(1)))
            .withColumn("planogram_id", F.when(
                F.col("assignment_source") == "planogram",
                F.concat(F.lit("PG-"), "store_id", F.lit("-"), "product_id")))
            .withColumn("assignment_status", F.lit(ASSIGNMENT_STATUSES[0]))
            .withColumn("valid_from_ts", F.lit("2024-03-01 00:00:00").cast("timestamp"))
            .withColumn("valid_to_ts", F.lit(None).cast("timestamp"))
            .withColumn("effective_from_date", F.lit("2024-03-01").cast("date"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", _fixed_ts())
            .withColumn("source_updated_timestamp", F.col("valid_from_ts"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", _fixed_ts())
            .drop("_enum_rank"))

    first_w = Window.partitionBy("store_id").orderBy("shelf_position_assignment_id")
    history_seed = base.withColumn("_rn", F.row_number().over(first_w)).filter("_rn = 1").drop("_rn")
    retired = (history_seed
               .withColumn("assignment_status", F.lit(ASSIGNMENT_STATUSES[2]))
               .withColumn("valid_from_ts", F.lit("2024-01-01 00:00:00").cast("timestamp"))
               .withColumn("valid_to_ts", F.lit("2024-02-01 00:00:00").cast("timestamp"))
               .withColumn("effective_from_date", F.lit("2024-01-01").cast("date"))
               .withColumn("effective_to_date", F.lit("2024-02-01").cast("date"))
               .withColumn("is_current", F.lit(False)))
    suspended = (history_seed
                 .withColumn("assignment_status", F.lit(ASSIGNMENT_STATUSES[1]))
                 .withColumn("valid_from_ts", F.lit("2024-02-01 00:00:00").cast("timestamp"))
                 .withColumn("valid_to_ts", F.lit("2024-03-01 00:00:00").cast("timestamp"))
                 .withColumn("effective_from_date", F.lit("2024-02-01").cast("date"))
                 .withColumn("effective_to_date", F.lit("2024-03-01").cast("date"))
                 .withColumn("is_current", F.lit(False)))
    assignments = base.unionByName(retired).unionByName(suspended)
    return _write(spark, assignments, f"{catalog}.{css_schema}.shelf_position_assignment",
                  SHELF_POSITION_ASSIGNMENT_COLUMNS, ctx.mode)


def generate_esl_label(ctx, cfg):
    spark, catalog = ctx.spark, ctx.catalog
    css_schema = ctx.schemas["css"]
    seed = cfg["seed"]
    assignments = (spark.table(f"{catalog}.{css_schema}.shelf_position_assignment")
                   .filter("is_current = TRUE AND assignment_status = 'active'")
                   .select("store_sk", "store_id", "shelf_position_assignment_id"))
    gateways = (spark.table(f"{catalog}.{css_schema}.sensor_device")
                .filter("is_current = TRUE AND device_type = 'esl_gateway'")
                .select("sensor_device_sk", "sensor_device_id", "store_id"))
    assigned = (assignments.join(F.broadcast(gateways), "store_id", "inner")
                .withColumn("esl_label_id", F.concat(F.lit("ESL-"), F.sha2(
                    "shelf_position_assignment_id", 256).substr(1, 20)))
                .withColumn("label_status", F.lit(LABEL_STATUSES[0])))
    spares = (gateways.join(
        spark.table(f"{catalog}.{ctx.schemas['store']}.store").filter("is_current = TRUE")
             .select("store_sk", "store_id"), "store_id", "inner")
              .crossJoin(spark.range(3).withColumnRenamed("id", "_spare_idx"))
              .withColumn("esl_label_id", F.concat(
                  F.lit("ESL-"), "store_id", F.lit("-SPARE-"), F.col("_spare_idx")))
              .withColumn("label_status", F.element_at(
                  F.array(*[F.lit(value) for value in LABEL_STATUSES[1:]]),
                  F.col("_spare_idx").cast("int") + 1))
              .withColumn("shelf_position_assignment_id", F.lit(None).cast("string")))
    enum_w = Window.partitionBy("store_id").orderBy("esl_label_id")
    labels = (assigned.unionByName(spares, allowMissingColumns=True)
              .withColumn("_enum_rank", F.row_number().over(enum_w) - F.lit(1)))
    labels = (labels
              .withColumn("display_technology", F.element_at(
                  F.array(*[F.lit(value) for value in DISPLAY_TECHNOLOGIES]),
                  F.pmod(F.col("_enum_rank"), F.lit(len(DISPLAY_TECHNOLOGIES))) + F.lit(1)))
              .withColumn("display_model", F.concat(F.lit("DISPLAY-"),
                                                     F.upper(F.col("display_technology"))))
              .withColumn("display_size_inches", (F.lit(2.1) + _frac(
                  seed, "display_size", F.col("esl_label_id")) * F.lit(3.9)).cast("double"))
              .withColumn("battery_life_class", F.element_at(
                  F.array(*[F.lit(value) for value in BATTERY_LIFE_CLASSES]),
                  F.pmod(F.col("_enum_rank") + F.lit(1), F.lit(len(BATTERY_LIFE_CLASSES)))
                  + F.lit(1)))
              .withColumn("is_nfc_capable", _frac(
                  seed, "nfc", F.col("esl_label_id")) < F.lit(0.35))
              .withColumn("is_qr_capable", _frac(
                  seed, "qr", F.col("esl_label_id")) < F.lit(0.75))
              .withColumn("commissioned_date", F.lit("2024-03-01").cast("date"))
              .withColumn("decommissioned_date", F.when(
                  F.col("label_status") == "retired", F.lit("2025-03-01").cast("date")))
              .withColumn("effective_from_date", F.lit("2024-03-01").cast("date"))
              .withColumn("effective_to_date", F.lit(None).cast("date"))
              .withColumn("is_current", F.lit(True))
              .withColumn("created_timestamp", _fixed_ts())
              .withColumn("source_updated_timestamp", _fixed_ts())
              .withColumn("record_source", F.lit(RECORD_SOURCE))
              .withColumn("load_timestamp", _fixed_ts())
              .drop("_enum_rank", "_spare_idx"))
    return _write(spark, labels, f"{catalog}.{css_schema}.esl_label",
                  ESL_LABEL_COLUMNS, ctx.mode)


def generate_esl_label_assignment(ctx, cfg):
    spark, catalog = ctx.spark, ctx.catalog
    css_schema, product_schema = ctx.schemas["css"], ctx.schemas["product"]
    assignments = (spark.table(f"{catalog}.{css_schema}.shelf_position_assignment")
                   .filter("is_current = TRUE AND assignment_status = 'active'")
                   .select("store_sk", "store_id", "store_zone_sk", "store_zone_id",
                           "product_sk", "product_id", "shelf_position_assignment_id"))
    labels = (spark.table(f"{catalog}.{css_schema}.esl_label")
              .filter("is_current = TRUE AND label_status = 'active'")
              .select("esl_label_sk", "esl_label_id"))
    products = (spark.table(f"{catalog}.{product_schema}.product")
                .filter("is_current = TRUE")
                .select(F.col("product_sk").alias("_product_sk"), F.col("gtin").alias("_gtin")))
    source_w = Window.partitionBy("store_id").orderBy("esl_label_assignment_id")
    base = (assignments
            .withColumn("esl_label_id", F.concat(F.lit("ESL-"), F.sha2(
                "shelf_position_assignment_id", 256).substr(1, 20)))
            .join(labels, "esl_label_id", "inner")
            .join(F.broadcast(products), F.col("product_sk") == F.col("_product_sk"), "left")
            .drop("_product_sk")
            .withColumn("esl_label_assignment_id", F.concat_ws(
                "|", "esl_label_id", "product_id", "store_zone_id"))
            .withColumn("_enum_rank", F.row_number().over(source_w) - F.lit(1))
            .withColumn("encoded_gtin", F.col("_gtin"))
            .withColumn("encoded_digital_link_uri", F.when(
                F.col("_gtin").isNotNull(), F.concat(F.lit("https://id.gs1.org/01/"), F.col("_gtin"))))
            .withColumn("binding_source", F.element_at(
                F.array(*[F.lit(value) for value in BINDING_SOURCES]),
                F.pmod(F.col("_enum_rank"), F.lit(len(BINDING_SOURCES))) + F.lit(1)))
            .withColumn("is_binding_verified", F.lit(True))
            .withColumn("binding_status", F.lit(BINDING_STATUSES[0]))
            .withColumn("valid_from_ts", F.lit("2024-03-01 00:00:00").cast("timestamp"))
            .withColumn("valid_to_ts", F.lit(None).cast("timestamp"))
            .withColumn("effective_from_date", F.lit("2024-03-01").cast("date"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", _fixed_ts())
            .withColumn("source_updated_timestamp", F.col("valid_from_ts"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", _fixed_ts())
            .drop("_gtin", "shelf_position_assignment_id", "_enum_rank"))

    first_w = Window.partitionBy("store_id").orderBy("esl_label_assignment_id")
    history_seed = base.withColumn("_rn", F.row_number().over(first_w)).filter("_rn = 1").drop("_rn")
    retired = (history_seed
               .withColumn("binding_status", F.lit(BINDING_STATUSES[2]))
               .withColumn("valid_from_ts", F.lit("2024-01-01 00:00:00").cast("timestamp"))
               .withColumn("valid_to_ts", F.lit("2024-02-01 00:00:00").cast("timestamp"))
               .withColumn("effective_from_date", F.lit("2024-01-01").cast("date"))
               .withColumn("effective_to_date", F.lit("2024-02-01").cast("date"))
               .withColumn("is_current", F.lit(False)))
    suspended = (history_seed
                 .withColumn("binding_status", F.lit(BINDING_STATUSES[1]))
                 .withColumn("valid_from_ts", F.lit("2024-02-01 00:00:00").cast("timestamp"))
                 .withColumn("valid_to_ts", F.lit("2024-03-01 00:00:00").cast("timestamp"))
                 .withColumn("effective_from_date", F.lit("2024-02-01").cast("date"))
                 .withColumn("effective_to_date", F.lit("2024-03-01").cast("date"))
                 .withColumn("is_current", F.lit(False)))
    bindings = base.unionByName(retired).unionByName(suspended)
    return _write(spark, bindings, f"{catalog}.{css_schema}.esl_label_assignment",
                  ESL_LABEL_ASSIGNMENT_COLUMNS, ctx.mode)


def _latest_calendar_date(ctx):
    return (ctx.spark.table(f"{ctx.catalog}.{ctx.schemas['calendar']}.fiscal_calendar")
            .agg(F.max("date_key").alias("_max_date")))


def _observation_key(df):
    return (df.withColumn("shelf_state_observation_id", F.concat_ws(
                "|", "store_zone_id", "product_id", "sensor_device_id", "source_capture_id"))
            .withColumn("shelf_state_observation_sk", F.xxhash64("shelf_state_observation_id")))


def generate_shelf_state_observation(ctx, cfg):
    """Generate the high-volume fact with dbldatagen offsets and coherent story arcs."""
    spark, catalog = ctx.spark, ctx.catalog
    css_schema, product_schema = ctx.schemas["css"], ctx.schemas["product"]
    seed = cfg["seed"]
    captures = cfg["captures_per_day_per_platform"]
    rows = cfg["days"] * 2 * captures
    offsets = (dg.DataGenerator(
        spark, name="smart_shelf_capture_offsets", rows=rows,
        partitions=max(1, min(16, rows)), randomSeedMethod="fixed", randomSeed=seed)
        .withIdOutput().build().withColumnRenamed("id", "_capture_offset")
        .withColumn("_day_idx", F.floor(F.col("_capture_offset") / F.lit(2 * captures)).cast("int"))
        .withColumn("_platform_idx", F.floor(
            (F.col("_capture_offset") % F.lit(2 * captures)) / F.lit(captures)).cast("int"))
        .withColumn("_capture_idx", (F.col("_capture_offset") % F.lit(captures)).cast("int")))
    assignments = (spark.table(f"{catalog}.{css_schema}.shelf_position_assignment")
                   .filter("is_current = TRUE AND assignment_status = 'active'")
                   .select("shelf_position_assignment_sk", "shelf_position_assignment_id",
                           "store_sk", "store_id", "store_zone_sk", "store_zone_id",
                           "product_sk", "product_id", "expected_facing_count", "min_facing_count"))
    frame = (assignments.crossJoin(offsets).crossJoin(_latest_calendar_date(ctx))
             .withColumn("trading_date", F.date_sub("_max_date", F.col("_day_idx"))))
    fixed_devices = (spark.table(f"{catalog}.{css_schema}.sensor_device")
                     .filter("is_current = TRUE AND device_type = 'shelf_sensor'")
                     .select("sensor_device_sk", "sensor_device_id", "sensing_deployment_sk",
                             "sensing_deployment_id", F.col("store_zone_id").alias("_device_zone")))
    robot_devices = (spark.table(f"{catalog}.{css_schema}.sensor_device")
                     .filter("is_current = TRUE AND device_type = 'camera' AND is_mobile_platform = TRUE")
                     .select("sensor_device_sk", "sensor_device_id", "sensing_deployment_sk",
                             "sensing_deployment_id", F.col("store_id").alias("_device_store")))
    fixed = (frame.filter("_platform_idx = 0")
             .join(F.broadcast(fixed_devices), F.col("store_zone_id") == F.col("_device_zone"), "inner")
             .drop("_device_zone"))
    robot = (frame.filter("_platform_idx = 1")
             .join(F.broadcast(robot_devices), F.col("store_id") == F.col("_device_store"), "inner")
             .drop("_device_store"))
    obs = fixed.unionByName(robot)

    sequence = F.col("_capture_idx") % F.lit(6)
    obs = (obs
           .withColumn("source_capture_id", F.concat(
               F.lit("CAP-"), "store_zone_id", F.lit("-"), F.col("trading_date").cast("string"),
               F.lit("-P"), "_platform_idx", F.lit("-C"), "_capture_idx"))
           .withColumn("utc_offset_minutes", F.lit(-300).cast("smallint"))
           .withColumn("store_timezone", F.lit("America/New_York"))
           .withColumn("observation_ts", F.col("trading_date").cast("timestamp")
                       + F.expr("INTERVAL '1' MINUTE") * (
                           F.lit(13 * 60) + F.col("_platform_idx") * F.lit(180)
                           + F.col("_capture_idx") * F.lit(30)))
           .withColumn("hour_of_day", (F.lit(8) + F.col("_platform_idx") * F.lit(3)
                                       + F.floor(F.col("_capture_idx") / F.lit(2))).cast("tinyint"))
           .withColumn("shelf_state",
               F.when(sequence == 0, F.lit(SHELF_STATES[0]))
                .when(sequence == 1, F.lit(SHELF_STATES[1]))
                .when(sequence.isin(2, 3), F.lit(SHELF_STATES[2]))
                .when(sequence == 4, F.lit(SHELF_STATES[0]))
                .otherwise(F.lit(SHELF_STATES[4])))
           .withColumn("min_facing_threshold", F.col("min_facing_count"))
           .withColumn("observed_facing_count",
               F.when(F.col("shelf_state") == "in_stock", F.col("expected_facing_count"))
                .when(F.col("shelf_state") == "low_stock", F.greatest(
                    F.lit(1), F.col("min_facing_count") - F.lit(1)))
                .when(F.col("shelf_state") == "out_of_stock", F.lit(0).cast("int"))
                .otherwise(F.lit(None).cast("int")))
           .withColumn("estimated_unit_count", F.when(
               (F.col("_platform_idx") == 0) & (F.col("shelf_state") != "unknown"),
               (F.col("observed_facing_count") * F.lit(3.0)).cast("double")))
           .withColumn("estimated_weight_grams", F.when(
               F.col("estimated_unit_count").isNotNull(),
               (F.col("estimated_unit_count") * F.lit(500.0)).cast("double")))
           .withColumn("pick_count_since_prior", F.when(
               F.col("shelf_state") != "unknown", (F.col("_capture_idx") % F.lit(3)).cast("int")))
           .withColumn("put_count_since_prior", F.when(
               F.col("shelf_state") != "unknown", ((F.col("_capture_idx") + 1) % F.lit(2)).cast("int")))
           .withColumn("is_gap_detected", F.col("shelf_state").isin("low_stock", "out_of_stock"))
           .withColumn("is_misplaced_detected", F.lit(False))
           .withColumn("is_price_tag_mismatch_detected", sequence == 2)
           .withColumn("zone_source", F.when(
               (F.col("_platform_idx") == 1) & (F.col("_capture_idx") == 0),
               F.lit(SHELF_ZONE_SOURCES[1]))
                .when(F.col("_platform_idx") == 1, F.lit(SHELF_ZONE_SOURCES[2]))
                .otherwise(F.lit(SHELF_ZONE_SOURCES[0])))
           .withColumn("attribution_confidence", F.when(
               F.col("_platform_idx") == 0, F.lit(1.0)).otherwise(F.lit(0.92)))
           .withColumn("measurement_validity",
               F.when(sequence == 1, F.lit(MEASUREMENT_VALIDITIES[1]))
                .when(sequence == 2, F.lit(MEASUREMENT_VALIDITIES[3]))
                .when(sequence == 5, F.lit(MEASUREMENT_VALIDITIES[2]))
                .otherwise(F.lit(MEASUREMENT_VALIDITIES[0])))
           .withColumn("arrival_completeness",
               F.when((F.col("_capture_idx") % 4) == 0, F.lit(ARRIVAL_COMPLETENESS_VALUES[0]))
                .when((F.col("_capture_idx") % 4) == 1, F.lit(ARRIVAL_COMPLETENESS_VALUES[1]))
                .when((F.col("_capture_idx") % 4) == 2, F.lit(ARRIVAL_COMPLETENESS_VALUES[2]))
                .otherwise(F.lit(ARRIVAL_COMPLETENESS_VALUES[3])))
           .withColumn("confidence_score", F.when(
               F.col("shelf_state") == "unknown", F.lit(0.20)).otherwise(
               F.lit(0.80) + _frac(seed, "shelf_conf", "source_capture_id") * F.lit(0.19)))
           .withColumn("is_occluded", sequence == 5)
           .withColumn("coverage_ratio", F.when(
               F.col("_platform_idx") == 0, F.lit(1.0)).otherwise(
               F.lit(0.55) + _frac(seed, "robot_coverage", "source_capture_id") * F.lit(0.40)))
           .withColumn("restatement_version", F.when(sequence == 2, F.lit(2)).otherwise(F.lit(1)))
           .withColumn("restated_at_timestamp", F.when(
               sequence == 2, F.col("observation_ts") + F.expr("INTERVAL 2 HOURS")))
           .withColumn("raw_data_uri", F.concat(
               F.lit("s3://ordm-bronze/smart-shelf/"), "source_capture_id"))
           .withColumn("ingest_timestamp", F.col("observation_ts") + F.expr("INTERVAL 2 MINUTES"))
           .withColumn("record_source", F.lit(RECORD_SOURCE))
           .withColumn("load_timestamp", F.col("ingest_timestamp")))
    obs = _observation_key(obs)

    # Mandatory two-row misplacement capture: one expected-product absence plus one
    # detected wrong product, sharing source_capture_id and the violated assignment.
    first_w = Window.partitionBy("store_id").orderBy("shelf_position_assignment_id")
    scenario = (obs.filter("_day_idx = 0 AND _platform_idx = 1 AND _capture_idx = 4")
                .withColumn("_rn", F.row_number().over(first_w)).filter("_rn = 1").drop("_rn")
                .withColumn("source_capture_id", F.concat(F.lit("CAP-MISPLACED-"), "store_id"))
                .withColumn("shelf_state", F.lit(SHELF_STATES[2]))
                .withColumn("observed_facing_count", F.lit(0).cast("int"))
                .withColumn("estimated_unit_count", F.lit(None).cast("double"))
                .withColumn("estimated_weight_grams", F.lit(None).cast("double"))
                .withColumn("pick_count_since_prior", F.lit(0).cast("int"))
                .withColumn("put_count_since_prior", F.lit(0).cast("int"))
                .withColumn("is_gap_detected", F.lit(True))
                .withColumn("is_misplaced_detected", F.lit(True))
                .withColumn("is_price_tag_mismatch_detected", F.lit(False))
                .withColumn("measurement_validity", F.lit(MEASUREMENT_VALIDITIES[0]))
                .withColumn("arrival_completeness", F.lit(ARRIVAL_COMPLETENESS_VALUES[0]))
                .withColumn("is_occluded", F.lit(False)))
    products = (spark.table(f"{catalog}.{product_schema}.product").filter("is_current = TRUE")
                .select(F.col("product_sk").alias("_wrong_product_sk"),
                        F.col("product_id").alias("_wrong_product_id")))
    wrong_w = Window.partitionBy("store_id", "store_zone_id").orderBy(
        F.abs(F.xxhash64("store_zone_id", "_wrong_product_id")))
    wrong = (scenario.crossJoin(products)
             .filter(F.col("_wrong_product_id") != F.col("product_id"))
             .withColumn("_wrong_rank", F.row_number().over(wrong_w))
             .filter("_wrong_rank = 1")
             .withColumn("product_sk", F.col("_wrong_product_sk"))
             .withColumn("product_id", F.col("_wrong_product_id"))
             .withColumn("shelf_state", F.lit(SHELF_STATES[3]))
             .withColumn("observed_facing_count", F.lit(2).cast("int"))
             .withColumn("is_gap_detected", F.lit(False))
             .drop("_wrong_product_sk", "_wrong_product_id", "_wrong_rank"))
    expected = _observation_key(scenario)
    wrong = _observation_key(wrong)
    fact = (obs.select(*SHELF_STATE_OBSERVATION_COLUMNS)
            .unionByName(expected.select(*SHELF_STATE_OBSERVATION_COLUMNS))
            .unionByName(wrong.select(*SHELF_STATE_OBSERVATION_COLUMNS)))
    return _write(spark, fact, f"{catalog}.{css_schema}.shelf_state_observation",
                  SHELF_STATE_OBSERVATION_COLUMNS, ctx.mode)


def generate_esl_price_observation(ctx, cfg):
    spark, catalog = ctx.spark, ctx.catalog
    css_schema = ctx.schemas["css"]
    n_obs = cfg["price_change_observations"]
    bindings = (spark.table(f"{catalog}.{css_schema}.esl_label_assignment")
                .filter("is_current = TRUE AND binding_status = 'active'")
                .select("esl_label_assignment_sk", "esl_label_assignment_id", "esl_label_sk",
                        "esl_label_id", "product_sk", "product_id", "store_sk", "store_id",
                        "store_zone_sk", "store_zone_id"))
    events = spark.range(n_obs).withColumnRenamed("id", "_price_event_idx")
    df = (bindings.crossJoin(events).crossJoin(_latest_calendar_date(ctx))
          .withColumn("trading_date", F.col("_max_date"))
          .withColumn("observation_source", F.element_at(
              F.array(*[F.lit(value) for value in PRICE_OBSERVATION_SOURCES]),
              (F.col("_price_event_idx") % len(PRICE_OBSERVATION_SOURCES)).cast("int") + 1))
          .withColumn("price_of_record_source", F.element_at(
              F.array(*[F.lit(value) for value in PRICE_OF_RECORD_SOURCES]),
              (F.col("_price_event_idx") % len(PRICE_OF_RECORD_SOURCES)).cast("int") + 1))
          .withColumn("source_observation_id", F.concat(
              F.lit("ESL-OBS-"), "esl_label_id", F.lit("-"), "_price_event_idx"))
          .withColumn("observed_at_ts", F.col("trading_date").cast("timestamp")
                      + F.expr("INTERVAL '1' HOUR") * (F.lit(14) + F.col("_price_event_idx")))
          .withColumn("store_timezone", F.lit("America/New_York"))
          .withColumn("utc_offset_minutes", F.lit(-300).cast("smallint"))
          .withColumn("hour_of_day", (F.lit(9) + F.col("_price_event_idx")).cast("tinyint"))
          .withColumn("price_of_record", (F.lit(5.0) +
              (F.abs(F.xxhash64("product_id")) % F.lit(2000)) / F.lit(100.0)).cast("decimal(18,4)"))
          .withColumn("price_of_record_currency_code", F.lit("USD"))
          .withColumn("displayed_price",
              F.when(F.col("_price_event_idx") == 0, F.col("price_of_record") + F.lit(1.0))
               .when(F.col("_price_event_idx") == 1, F.greatest(
                   F.lit(0.01), F.col("price_of_record") - F.lit(0.5)))
               .when((F.col("_price_event_idx") % 5) == 4, F.col("price_of_record") + F.lit(0.25))
               .otherwise(F.col("price_of_record")).cast("decimal(18,4)"))
          .withColumn("displayed_currency_code", F.lit("USD"))
          .withColumn("displayed_unit_price", F.when(
              F.col("price_of_record_source") == "scale_plu",
              (F.col("displayed_price") / F.lit(0.453592)).cast("decimal(18,4)")))
          .withColumn("unit_price_uom", F.when(
              F.col("price_of_record_source") == "scale_plu", F.lit("LBR")))
          .withColumn("displayed_promo_indicator", (F.col("_price_event_idx") % 2) == 1)
          .withColumn("displayed_disclosure_indicator", (F.col("_price_event_idx") % 2) == 0)
          .withColumn("displayed_disclosure_text", F.when(
              F.col("displayed_disclosure_indicator"), F.lit("Price shown may reflect a promotional offer.")))
          .withColumn("price_of_record_price_type", F.when(
              F.col("displayed_promo_indicator"), F.lit("promotional")).otherwise(F.lit("list")))
          .withColumn("price_of_record_effective_ts", F.col("trading_date").cast("timestamp")
                      + F.expr("INTERVAL 13 HOURS"))
          .withColumn("is_price_match", F.col("displayed_price") == F.col("price_of_record"))
          .withColumn("display_sync_latency_seconds", F.when(
              F.col("observation_source") == "platform_ack",
              F.unix_timestamp("observed_at_ts") - F.unix_timestamp("price_of_record_effective_ts")).cast("bigint"))
          .withColumn("sensing_derived_input_flag", F.lit(False))
          .withColumn("raw_data_uri", F.concat(
              F.lit("s3://ordm-bronze/esl/"), "source_observation_id"))
          .withColumn("ingest_timestamp", F.col("observed_at_ts") + F.expr("INTERVAL 1 MINUTE"))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", F.col("ingest_timestamp"))
          .withColumn("esl_price_observation_id", F.concat_ws(
              "|", "esl_label_id", "observation_source", "source_observation_id"))
          .withColumn("esl_price_observation_sk", F.xxhash64("esl_price_observation_id")))
    return _write(spark, df, f"{catalog}.{css_schema}.esl_price_observation",
                  ESL_PRICE_OBSERVATION_COLUMNS, ctx.mode)


def generate_smart_shelf(ctx, cfg):
    """Write the five Smart Shelf tables in FK order; called by the sole CSS GenSpec."""
    generate_shelf_position_assignment(ctx, cfg)
    generate_esl_label(ctx, cfg)
    generate_esl_label_assignment(ctx, cfg)
    generate_shelf_state_observation(ctx, cfg)
    generate_esl_price_observation(ctx, cfg)
