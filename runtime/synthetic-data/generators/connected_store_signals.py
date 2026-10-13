# ============================================================
# ORDM · Synthetic data · Connected Store Signals generator
# Version: 0.5
# Generated: 2026-07-28
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-07-28
# ============================================================
# Populates the connected-store-signals package: shared spatial/device foundations,
# Foot Traffic + IoT interval/control-loop data, RFID evidence, and Smart Shelf expected,
# observed, and ESL display state. Smart Shelf stays inside this sole css provider.
#
# Runs BEFORE commerce_media_networks, which now reads this package's shared surface
# through cmn_schema.store_zone_interval (ADR 0033). The ordering is enforced by
# _registry.py, not by comments.
#
# Reads canonical-core store, product, calendar and equipment.
#
# THE DATA IS SHAPED TO EXERCISE THE CHECKS, not merely to fill columns. Specifically:
#   * trading_date is drawn FROM fiscal_calendar, so sri_calendar_orphan is a real test
#     rather than one that passes because both sides happen to be empty;
#   * site and area rows are generated independently, never by summing zones;
#   * each series uses one canonical, non-overlapping cadence. Vendor-native rollups
#     remain Bronze/reconciliation inputs and are never unioned into this additive fact;
#   * low and zero counts remain complete operational truth. Disclosure control is
#     applied only by explicitly shared gold views;
#   * a slice of devices is non-directional and those rows carry exit_count = NULL, not
#     0 -- the distinction ftid_nondirectional_exits_null enforces;
#   * gs1:Temperature rows prove that the shared envelope is reusable without inheriting
#     traffic-only measures.
# ============================================================

import os
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window

try:
    from _common import RECORD_SOURCE, load_domain_config, _pick, _frac, _write
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import RECORD_SOURCE, load_domain_config, _pick, _frac, _write

# ------------------------------------------------------------
# Column contracts -- MUST match the DDL.
# store_zone / sensing_deployment / sensor_device omit their IDENTITY *_sk.
# sensor_report_interval INCLUDES its _sk: that key is xxhash64 of the durable id, not
# an identity column (ADR 0028), so the generator supplies it.
# Checked against the DDL by tests/test_connected_store_signals.py.
# ------------------------------------------------------------
STORE_ZONE_COLUMNS = [
    "store_zone_id", "store_sk", "store_id", "zone_code", "zone_name", "zone_type",
    "parent_zone_sk", "parent_zone_id", "hierarchy_depth", "hierarchy_path",
    "area_sqm", "capacity_persons", "is_sales_floor", "is_countable",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
SENSING_DEPLOYMENT_COLUMNS = [
    "sensing_deployment_id", "store_sk", "store_id", "deployment_name",
    "sensing_method_code", "sensing_purpose_code", "lawful_basis_code", "jurisdiction_code",
    "dpia_completed_flag", "dpia_reference", "dpia_covers_employees_flag", "dpia_review_due_date",
    "signage_posted_flag", "ai_act_notice_status", "works_council_consulted_flag",
    "consultation_reference", "consent_required_flag", "optout_mechanism_code",
    "retention_days_max", "retention_basis", "staff_exclusion_method", "staff_exclusion_stage",
    "external_disclosure_policy_sk", "external_disclosure_policy_id",
    "deployment_status", "deployed_date", "decommissioned_date",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
SENSING_DISCLOSURE_POLICY_COLUMNS = [
    "sensing_disclosure_policy_id", "audience_code", "k_threshold",
    "suppress_zero_flag", "minimum_interval_minutes",
    "effective_from_date", "effective_to_date",
    "is_current", "policy_basis", "record_source", "load_timestamp",
]
SENSOR_DEVICE_COLUMNS = [
    "sensor_device_id", "store_sk", "store_id", "store_zone_sk", "store_zone_id",
    "device_type", "sensing_technology", "device_role", "manufacturer", "model",
    "serial_number", "firmware_version", "is_directional", "supports_dwell",
    "supports_occupancy", "is_mobile_platform", "detection_limit_count", "battery_powered",
    "brick_class_iri", "unit_iri", "uom_code",
    "bacnet_device_id", "bacnet_object_ref", "bacnet_out_of_service",
    "opc_ua_node_id", "sparkplug_edge_node_id",
    "calibration_certificate_id", "calibration_valid_from", "calibration_valid_to",
    "accuracy_tolerance", "probe_type", "is_backup_device",
    "sensing_deployment_sk", "sensing_deployment_id", "equipment_sk", "equipment_id",
    "device_status", "installed_date", "decommissioned_date",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
SENSOR_REPORT_INTERVAL_COLUMNS = [
    "sensor_report_interval_sk", "sensor_report_interval_id",
    "subject_type", "subject_id", "store_sk", "store_id", "store_zone_sk", "store_zone_id",
    "product_sk", "product_id",
    "equipment_sk", "equipment_id",
    "report_type",
    "value", "min_value", "max_value", "mean_value", "s_dev", "perc_rank", "perc_value",
    "string_value", "boolean_value",
    "uom", "unit_iri",
    "aggregation_level", "source_observation_count", "expected_observation_count",
    "interval_start_ts", "interval_end_ts", "interval_minutes", "store_timezone",
    "utc_offset_minutes", "trading_date", "trading_day_offset", "hour_of_day", "day_part",
    "is_partial_interval", "is_dst_transition", "time_mode",
    "measurement_validity", "arrival_completeness", "is_imputed",
    "uptime_ratio", "coverage_ratio", "confidence_score", "sensor_online_flag",
    "is_capped", "capped_count_limit", "ingest_timestamp", "latency_seconds",
    "restatement_version", "restated_at_timestamp",
    "sensor_device_sk", "sensor_device_id", "sensing_deployment_sk", "sensing_deployment_id",
    "device_metadata_uri", "raw_data_uri", "data_processing_method_uri", "biz_rules_uri",
    "source_session_id", "source_message_count", "sequence_gap_count",
    "duplicate_delivery_count", "historical_message_count", "bad_quality_message_count",
    "record_source", "load_timestamp",
]
FOOT_TRAFFIC_INTERVAL_DETAIL_COLUMNS = [
    "sensor_report_interval_sk",
    "footfall_count", "entry_count", "exit_count", "passersby_count", "unique_visitor_count",
    "is_zero_observed",
    "counting_unit", "group_counting_enabled", "unique_visitor_enabled",
    "child_counting_enabled", "child_height_threshold_cm", "staff_exclusion_enabled",
    "directionality", "count_divisor", "passby_convention",
    "visitor_count_raw", "staff_count", "child_count", "visitor_count_adjusted",
    "staff_adjustment_applied", "staff_exclusion_method", "staff_exclusion_stage",
    "staff_exclusion_grade",
    "occupancy_snapshot_end", "occupancy_min", "occupancy_max", "occupancy_avg",
    "cumulative_entries", "cumulative_exits", "occupancy_adjustment", "adjustment_source",
    "last_reset_local_ts",
    "dwell_seconds_total", "dwell_count", "engaged_count", "passing_count",
    "engagement_threshold_seconds",
]

# Automation loop (IoT Sensor Monitoring). All four keep an IDENTITY *_sk, so the
# generator omits it: actuator_capability / evaluation_rule / automation_action are
# low-volume SCD2 masters, and execution_log is a moderate-volume append-only fact where
# the ADR 0028 concurrency caveat that pushed sensor_report_interval to a hash key does
# not bite (ADR 0004 applies as written). Checked against the DDL by
# tests/test_connected_store_signals.py.
ACTUATOR_CAPABILITY_COLUMNS = [
    "actuator_capability_id", "sensor_device_sk", "sensor_device_id",
    "equipment_sk", "equipment_id", "command_type", "acceptable_value_range",
    "unit_iri", "uom_code", "actuator_status", "installed_date", "decommissioned_date",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
EVALUATION_RULE_COLUMNS = [
    "evaluation_rule_id", "sensor_device_sk", "sensor_device_id", "rule_name",
    "report_type", "condition_operator", "threshold_value_numeric", "threshold_value_upper",
    "unit_iri", "uom_code", "time_window_seconds", "severity", "is_enabled",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
AUTOMATION_ACTION_COLUMNS = [
    "automation_action_id", "evaluation_rule_sk", "evaluation_rule_id", "action_type",
    "target_entity_type", "target_entity_id", "actuator_capability_sk", "actuator_capability_id",
    "payload_template", "is_enabled",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
EXECUTION_LOG_COLUMNS = [
    "execution_log_id", "automation_action_sk", "automation_action_id",
    "actuator_capability_sk", "actuator_capability_id", "evaluation_rule_sk", "evaluation_rule_id",
    "sensor_report_interval_sk", "triggered_at_timestamp", "execution_status",
    "response_payload", "latency_ms", "record_source", "load_timestamp",
]

# The zone taxonomy. These came across from the CMN generator's bare ZONE_CODES with
# the fact (ADR 0033); here they seed a real dimension, so each carries the area,
# capacity and countability that a bare code could not.
#   (zone_code, zone_name, zone_type, area_sqm, capacity, is_sales_floor, is_countable)
ZONES = [
    ("entrance",   "Front Entrance",     "entrance",      60.0,  120, True,  True),
    ("checkout",   "Checkout Lanes",     "queue",         90.0,  100, True,  True),
    ("aisle_end",  "Aisle End Caps",     "bay",           45.0,   60, True,  True),
    ("aisle",      "Main Aisles",        "aisle",        320.0,  400, True,  True),
    ("perimeter",  "Perimeter Fresh",    "department",   280.0,  350, True,  True),
    ("fitting",    "Fitting Rooms",      "fitting_room",  40.0,   30, True,  True),
    ("backroom",   "Back of House",      "back_of_house",150.0,   40, False, False),
]

# Neutral synthetic labels, not real manufacturers: A.14 forbids brand names anywhere in
# the model, and generated rows land in the published sample data.
COUNTER_MANUFACTURERS = ["MFR-A", "MFR-B", "MFR-C", "MFR-D", "MFR-E"]
FIRMWARES = ["4.2.1", "4.3.0", "5.0.2", "5.1.0"]
# Deliberately mixed technologies: the accuracy and privacy profiles differ, and the
# gold device-health view groups by this.
COUNTER_TECHNOLOGIES = ["thermal", "stereo_vision", "time_of_flight", "ir_beam"]
DAY_PARTS = ["pre_open", "morning", "midday", "afternoon", "evening", "late"]

BRICK_OCCUPANCY_COUNT = "https://brickschema.org/schema/Brick#Occupancy_Count_Sensor"
BRICK_AIR_TEMP = "https://brickschema.org/schema/Brick#Air_Temperature_Sensor"
QUDT_DEG_C = "http://qudt.org/vocab/unit/DEG_C"
# A person count is dimensionless, which is why sri_uom_present exempts gs1:Count.
QUDT_UNITLESS = "http://qudt.org/vocab/unit/UNITLESS"


def load_config():
    c = load_domain_config("connected_store_signals")
    vols = c.get("volumes", {}) or {}
    return {
        "seed": c.get("seed", 12012),
        "days": int(vols.get("days", 14)),
        "intervals_per_day": int(vols.get("intervals_per_day", 12)),
        "interval_minutes": int(vols.get("interval_minutes", 60)),
        "env_devices": int(vols.get("env_devices", 20)),
        "env_intervals_per_device": int(vols.get("env_intervals_per_device", 24)),
        "rfid_products": int(vols.get("rfid_products", 20)),
        "rfid_items_per_product_store": int(vols.get("rfid_items_per_product_store", 4)),
        "rfid_events_per_item": int(vols.get("rfid_events_per_item", 6)),
        "rfid_sessions_per_store": int(vols.get("rfid_sessions_per_store", 3)),
        "positions_per_store": int(vols.get("positions_per_store", 24)),
        "products_per_position": int(vols.get("products_per_position", 1)),
        "captures_per_day_per_platform": int(vols.get("captures_per_day_per_platform", 6)),
        "price_change_observations": int(vols.get("price_change_observations", 5)),
    }


# ------------------------------------------------------------
# Masters
# ------------------------------------------------------------

def generate_store_zone(spark, catalog, css_schema, store_schema, cfg, mode):
    """The recursive zone hierarchy: one site row per store (depth 0, no parent) plus
    one row per zone (depth 1, parent = the site).

    The site row is what makes footfall additivity work. Per ADR 0032 a store total
    must come from aggregation_level = 'site', so the site zone has to EXIST as a
    first-class row -- there is no such thing as a store total synthesised by summing
    zones. The operational gold views enforce that level boundary explicitly.
    """
    now = F.current_timestamp()
    stores = (spark.table(f"{catalog}.{store_schema}.store")
              .filter("is_current = TRUE")
              .select("store_sk", "store_id"))

    site = (stores
            .withColumn("store_zone_id", F.concat(F.lit("SZ-"), F.col("store_id"), F.lit("-SITE")))
            .withColumn("zone_code", F.lit("site"))
            .withColumn("zone_name", F.concat(F.lit("Store "), F.col("store_id"), F.lit(" (whole site)")))
            .withColumn("zone_type", F.lit("site"))
            .withColumn("parent_zone_id", F.lit(None).cast("string"))
            .withColumn("hierarchy_depth", F.lit(0))
            .withColumn("hierarchy_path", F.concat(F.lit("/"), F.col("store_id")))
            .withColumn("area_sqm", F.lit(1200.00).cast("decimal(12,2)"))
            .withColumn("capacity_persons", F.lit(900))
            .withColumn("is_sales_floor", F.lit(True))
            .withColumn("is_countable", F.lit(True)))

    zone_rows = F.array(*[
        F.struct(F.lit(code).alias("zone_code"), F.lit(name).alias("zone_name"),
                 F.lit(ztype).alias("zone_type"), F.lit(area).alias("area_sqm"),
                 F.lit(cap).alias("capacity_persons"), F.lit(floor).alias("is_sales_floor"),
                 F.lit(countable).alias("is_countable"))
        for code, name, ztype, area, cap, floor, countable in ZONES
    ])
    children = (stores
                .withColumn("_z", F.explode(zone_rows))
                .withColumn("zone_code", F.col("_z.zone_code"))
                .withColumn("zone_name", F.col("_z.zone_name"))
                .withColumn("zone_type", F.col("_z.zone_type"))
                .withColumn("area_sqm", F.col("_z.area_sqm").cast("decimal(12,2)"))
                .withColumn("capacity_persons", F.col("_z.capacity_persons").cast("int"))
                .withColumn("is_sales_floor", F.col("_z.is_sales_floor"))
                .withColumn("is_countable", F.col("_z.is_countable"))
                .withColumn("store_zone_id",
                            F.concat(F.lit("SZ-"), F.col("store_id"), F.lit("-"), F.upper(F.col("zone_code"))))
                .withColumn("parent_zone_id", F.concat(F.lit("SZ-"), F.col("store_id"), F.lit("-SITE")))
                .withColumn("hierarchy_depth", F.lit(1))
                .withColumn("hierarchy_path",
                            F.concat(F.lit("/"), F.col("store_id"), F.lit("/"), F.col("zone_code")))
                .drop("_z"))

    zones = (site.unionByName(children)
             # parent_zone_sk is NULL on first write: the IDENTITY _sk does not exist
             # until Delta assigns it, so the durable parent_zone_id is what carries
             # the hierarchy and resolve_parent_sks() backfills the surrogate after.
             # This is why ADR 0025 makes the durable id the join key consumers use.
             .withColumn("parent_zone_sk", F.lit(None).cast("bigint"))
             .withColumn("effective_from_date", F.lit("2024-01-01").cast("date"))
             .withColumn("effective_to_date", F.lit(None).cast("date"))
             .withColumn("is_current", F.lit(True))
             .withColumn("created_timestamp", now)
             .withColumn("source_updated_timestamp", now)
             .withColumn("record_source", F.lit(RECORD_SOURCE))
             .withColumn("load_timestamp", now))

    _write(spark, zones, f"{catalog}.{css_schema}.store_zone", STORE_ZONE_COLUMNS, mode)
    _resolve_parent_sks(spark, catalog, css_schema)
    return spark.table(f"{catalog}.{css_schema}.store_zone")


def _resolve_parent_sks(spark, catalog, css_schema):
    """Backfill parent_zone_sk from parent_zone_id, now that Delta has assigned the
    IDENTITY surrogates. Two-pass because the self-FK cannot be satisfied in one write.
    Resolves against the CURRENT parent version specifically, which is the condition
    sz_parent_resolves_current asserts."""
    spark.sql(f"""
        MERGE INTO {catalog}.{css_schema}.store_zone t
        USING (
          SELECT c.store_zone_sk AS _sk, p.store_zone_sk AS _parent_sk
          FROM {catalog}.{css_schema}.store_zone c
          JOIN {catalog}.{css_schema}.store_zone p
            ON c.parent_zone_id = p.store_zone_id AND p.is_current = TRUE
          WHERE c.parent_zone_id IS NOT NULL
        ) s
        ON t.store_zone_sk = s._sk
        WHEN MATCHED THEN UPDATE SET t.parent_zone_sk = s._parent_sk
    """)


def generate_sensing_disclosure_policy(spark, catalog, css_schema, mode):
    """Seed the adopter-overridable external disclosure default.

    k=10 is configuration for this external audience, not a legal universal and not a
    base-fact invariant. Operational data remains complete regardless of this row.
    """
    df = (
        spark.range(1)
        .select(
            F.lit("external_default").alias("sensing_disclosure_policy_id"),
            F.lit("external").alias("audience_code"),
            F.lit(10).cast("int").alias("k_threshold"),
            F.lit(True).alias("suppress_zero_flag"),
            F.lit(15).cast("int").alias("minimum_interval_minutes"),
            F.lit("2024-01-01").cast("date").alias("effective_from_date"),
            F.lit(None).cast("date").alias("effective_to_date"),
            F.lit(True).alias("is_current"),
            F.lit("External aggregate disclosure default; adopter review required.")
             .alias("policy_basis"),
            F.lit(RECORD_SOURCE).alias("record_source"),
            F.current_timestamp().alias("load_timestamp"),
        )
    )
    return _write(
        spark,
        df,
        f"{catalog}.{css_schema}.sensing_disclosure_policy",
        SENSING_DISCLOSURE_POLICY_COLUMNS,
        mode,
    )


def generate_sensing_deployment(spark, catalog, css_schema, store_schema, cfg, mode):
    """One people-counting deployment per store, plus one environmental deployment.

    Every governance flag is populated affirmatively. That is a deliberate choice, not
    laziness: the sdep_* checks are error-severity, so synthetic data that failed them
    would make `make check` red for every contributor and the checks would get muted.
    A future negative-case fixture belongs in a test, not in the deploy dataset.
    """
    now = F.current_timestamp()
    seed = cfg["seed"]
    stores = (spark.table(f"{catalog}.{store_schema}.store")
              .filter("is_current = TRUE")
              .select("store_sk", "store_id"))

    counting = (stores
                .withColumn("sensing_deployment_id", F.concat(F.lit("SDEP-"), F.col("store_id"), F.lit("-COUNT")))
                .withColumn("deployment_name",
                            F.concat(F.lit("People counting, store "), F.col("store_id")))
                .withColumn("sensing_method_code", _pick(COUNTER_TECHNOLOGIES, seed, "sm", F.col("store_id")))
                .withColumn("sensing_purpose_code", F.lit("people_counting"))
                # Anonymous counting that never retains an identifier is outside the
                # personal-data perimeter -- which is precisely the claim the EDPB says
                # is not a one-time determination, hence dpia_review_due_date below.
                .withColumn("lawful_basis_code", F.lit("legitimate_interest"))
                .withColumn("consent_required_flag", F.lit("not_required"))
                .withColumn("optout_mechanism_code", F.lit("signage_contact"))
                .withColumn("staff_exclusion_method", F.lit("exclusion_line"))
                .withColumn("staff_exclusion_stage", F.lit("at_aggregation"))
                .withColumn("retention_days_max", F.lit(90))
                .withColumn("retention_basis", F.lit("Operational reporting window; aggregate-only tier."))
                .withColumn("ai_act_notice_status", F.lit("not_applicable")))

    environmental = (stores
                     .withColumn("sensing_deployment_id", F.concat(F.lit("SDEP-"), F.col("store_id"), F.lit("-ENV")))
                     .withColumn("deployment_name",
                                 F.concat(F.lit("Environmental and cold chain, store "), F.col("store_id")))
                     .withColumn("sensing_method_code", F.lit("environmental"))
                     .withColumn("sensing_purpose_code", F.lit("cold_chain_compliance"))
                     # Equipment temperature is not personal data, and saying so
                     # explicitly is what exempts it from the DPIA/signage/retention
                     # checks rather than leaving them silently unsatisfied.
                     .withColumn("lawful_basis_code", F.lit("not_personal_data"))
                     .withColumn("consent_required_flag", F.lit("not_required"))
                     .withColumn("optout_mechanism_code", F.lit("not_applicable"))
                     .withColumn("staff_exclusion_method", F.lit("none"))
                     .withColumn("staff_exclusion_stage", F.lit("none"))
                     .withColumn("retention_days_max", F.lit(1095))
                     .withColumn("retention_basis", F.lit("CDC/VFC retains calibration and temperature records 3 years."))
                     .withColumn("ai_act_notice_status", F.lit("not_applicable")))

    rfid = (stores
            .withColumn("sensing_deployment_id", F.concat(F.lit("SDEP-"), F.col("store_id"), F.lit("-RFID")))
            .withColumn("deployment_name", F.concat(F.lit("RFID item visibility, store "), F.col("store_id")))
            .withColumn("sensing_method_code", F.lit("rfid"))
            .withColumn("sensing_purpose_code", F.lit("asset_tracking"))
            .withColumn("lawful_basis_code", F.lit("not_personal_data"))
            .withColumn("consent_required_flag", F.lit("not_required"))
            .withColumn("optout_mechanism_code", F.lit("not_applicable"))
            .withColumn("staff_exclusion_method", F.lit("none"))
            .withColumn("staff_exclusion_stage", F.lit("none"))
            .withColumn("retention_days_max", F.lit(395))
            .withColumn("retention_basis", F.lit("Operational item-visibility history; adopter review required."))
            .withColumn("ai_act_notice_status", F.lit("not_applicable"))
            .withColumn("external_disclosure_policy_sk", F.lit(None).cast("bigint"))
            .withColumn("external_disclosure_policy_id", F.lit(None).cast("string")))

    disclosure_policy = (
        spark.table(f"{catalog}.{css_schema}.sensing_disclosure_policy")
        .filter(
            "sensing_disclosure_policy_id = 'external_default' AND is_current = TRUE"
        )
        .select(
            F.col("sensing_disclosure_policy_sk").alias(
                "external_disclosure_policy_sk"
            ),
            F.col("sensing_disclosure_policy_id").alias(
                "external_disclosure_policy_id"
            ),
        )
    )

    counting = counting.crossJoin(F.broadcast(disclosure_policy))
    environmental = (
        environmental
        .withColumn("external_disclosure_policy_sk", F.lit(None).cast("bigint"))
        .withColumn("external_disclosure_policy_id", F.lit(None).cast("string"))
    )

    df = (counting.unionByName(environmental).unionByName(rfid)
          .withColumn("jurisdiction_code", F.lit("US"))
          .withColumn("dpia_completed_flag", F.lit(True))
          .withColumn("dpia_reference", F.concat(F.lit("DPIA-"), F.col("sensing_deployment_id")))
          .withColumn("dpia_covers_employees_flag", F.lit(True))
          # EDPB 02/2026: anonymity is a claim that has to be re-tested, so the review
          # date is a real column value rather than a policy sentence in a wiki.
          .withColumn("dpia_review_due_date", F.date_add(F.current_date(), 365))
          .withColumn("signage_posted_flag", F.lit(True))
          .withColumn("works_council_consulted_flag", F.lit(True))
          .withColumn("consultation_reference", F.concat(F.lit("WC-"), F.col("sensing_deployment_id")))
          .withColumn("deployment_status", F.lit("active"))
          .withColumn("deployed_date", F.lit("2024-01-01").cast("date"))
          .withColumn("decommissioned_date", F.lit(None).cast("date"))
          .withColumn("effective_from_date", F.lit("2024-01-01").cast("date"))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))

    return _write(spark, df, f"{catalog}.{css_schema}.sensing_deployment",
                  SENSING_DEPLOYMENT_COLUMNS, mode)


def generate_sensor_device(spark, catalog, css_schema, equipment_schema, cfg, mode):
    """One people counter per countable zone, plus a site-level entrance counter, plus
    a set of temperature probes attached to refrigeration equipment.

    A deterministic slice of counters is NON-DIRECTIONAL. That matters: a
    non-directional device cannot measure exits, so its fact rows must carry
    exit_count = NULL rather than 0, and sd_directionality_consistent /
    ftid_nondirectional_exits_null are only real tests if such devices exist.
    """
    now = F.current_timestamp()
    seed = cfg["seed"]

    zones = (spark.table(f"{catalog}.{css_schema}.store_zone")
             .filter("is_current = TRUE")
             .select("store_zone_sk", "store_zone_id", "store_sk", "store_id",
                     "zone_code", "zone_type", "is_countable"))
    deployments = (spark.table(f"{catalog}.{css_schema}.sensing_deployment")
                   .filter("is_current = TRUE")
                   .select(F.col("sensing_deployment_sk").alias("_dep_sk"),
                           F.col("sensing_deployment_id").alias("_dep_id"),
                           F.col("store_id").alias("_dep_store_id")))
    count_dep = deployments.filter(F.col("_dep_id").endswith("-COUNT"))
    env_dep = deployments.filter(F.col("_dep_id").endswith("-ENV"))

    counters = (zones.filter("is_countable = TRUE")
                .withColumn("sensor_device_id",
                            F.concat(F.lit("SDV-"), F.col("store_zone_id"), F.lit("-PC")))
                .withColumn("device_type", F.lit("people_counter"))
                .withColumn("sensing_technology", _pick(COUNTER_TECHNOLOGIES, seed, "tech", F.col("sensor_device_id")))
                .withColumn("device_role", F.lit("sense"))
                .withColumn("manufacturer", _pick(COUNTER_MANUFACTURERS, seed, "mfr", F.col("sensor_device_id")))
                .withColumn("model",
                            F.concat(F.lit("PC-"), F.upper(F.substring(F.col("sensing_technology"), 1, 3)),
                                     F.lit("-"), F.format_string("%03d", (F.abs(F.hash(F.col("sensor_device_id"), F.lit(seed))) % F.lit(900) + F.lit(100)).cast("int"))))
                # ir_beam devices count a crossing without direction. Deriving this
                # from the technology rather than picking it at random is what keeps
                # the device row and its fact rows consistent.
                .withColumn("is_directional", F.col("sensing_technology") != F.lit("ir_beam"))
                .withColumn("supports_dwell", F.col("sensing_technology").isin("stereo_vision", "time_of_flight", "video_cv"))
                .withColumn("supports_occupancy", F.col("sensing_technology") != F.lit("ir_beam"))
                .withColumn("is_mobile_platform", F.lit(False))
                .withColumn("detection_limit_count", F.lit(250))
                .withColumn("battery_powered", F.col("sensing_technology") == F.lit("ir_beam"))
                .withColumn("brick_class_iri", F.lit(BRICK_OCCUPANCY_COUNT))
                .withColumn("unit_iri", F.lit(QUDT_UNITLESS))
                .withColumn("uom_code", F.lit("H87"))  # UN/CEFACT: piece
                .withColumn("accuracy_tolerance", F.lit(None).cast("double"))
                .withColumn("probe_type", F.lit("none"))
                .withColumn("is_backup_device", F.lit(False))
                .withColumn("equipment_sk", F.lit(None).cast("bigint"))
                .withColumn("equipment_id", F.lit(None).cast("string"))
                .withColumn("_dep_suffix", F.lit("-COUNT"))
                .drop("is_countable"))

    counters = (counters.join(F.broadcast(count_dep),
                             counters.store_id == count_dep._dep_store_id, "left")
                .drop("_dep_store_id"))

    # Temperature probes on refrigeration assets: the IoT seam, and the reason
    # sensor_device carries an equipment FK at all.
    equipment = (spark.table(f"{catalog}.{equipment_schema}.equipment")
                 .filter("is_current = TRUE AND equipment_type = 'refrigeration'")
                 .select("equipment_sk", "equipment_id", "store_sk", "store_id")
                 .withColumn("_r", F.row_number().over(Window.orderBy("equipment_sk")))
                 .filter(F.col("_r") <= F.lit(cfg["env_devices"]))
                 .drop("_r"))
    site_zone = (spark.table(f"{catalog}.{css_schema}.store_zone")
                 .filter("is_current = TRUE AND zone_type = 'site'")
                 .select(F.col("store_zone_sk"), F.col("store_zone_id"),
                         F.col("zone_code"), F.col("zone_type"),
                         F.col("store_id").alias("_sz_store_id")))

    probes = (equipment
              .join(F.broadcast(site_zone), equipment.store_id == site_zone._sz_store_id, "left")
              .drop("_sz_store_id")
              .withColumn("sensor_device_id",
                          F.concat(F.lit("SDV-"), F.col("equipment_id"), F.lit("-TEMP")))
              .withColumn("device_type", F.lit("temperature"))
              .withColumn("sensing_technology", F.lit("thermistor"))
              # A refrigeration probe both observes temperature AND drives the compressor
              # relay exposed as its actuator_capability, so its role is 'both', not 'sense'
              # -- honouring the actuator_capability invariant that an actuator is a
              # capability of a device whose device_role is 'actuate' or 'both'.
              .withColumn("device_role", F.lit("both"))
              .withColumn("manufacturer", _pick(["MFR-F", "MFR-G", "MFR-H", "MFR-J"], seed, "emfr", F.col("sensor_device_id")))
              .withColumn("model", F.lit("TP-BUF-100"))
              .withColumn("is_directional", F.lit(None).cast("boolean"))
              .withColumn("supports_dwell", F.lit(False))
              .withColumn("supports_occupancy", F.lit(False))
              .withColumn("is_mobile_platform", F.lit(False))
              .withColumn("detection_limit_count", F.lit(None).cast("int"))
              .withColumn("battery_powered", F.lit(True))
              .withColumn("brick_class_iri", F.lit(BRICK_AIR_TEMP))
              .withColumn("unit_iri", F.lit(QUDT_DEG_C))
              .withColumn("uom_code", F.lit("CEL"))
              # CDC/VFC requires +/-0.5 degC AND a BUFFERED probe: an air probe reacts
              # to door openings and manufactures false excursions. sd_vaccine_probe_buffered
              # is the check that would catch getting this pair wrong.
              .withColumn("accuracy_tolerance", F.lit(0.5))
              .withColumn("probe_type", F.lit("buffered"))
              .withColumn("is_backup_device", _frac(seed, "backup", F.col("sensor_device_id")) < F.lit(0.2))
              .withColumn("_dep_suffix", F.lit("-ENV")))

    probes = (probes.join(F.broadcast(env_dep),
                          probes.store_id == env_dep._dep_store_id, "left")
              .drop("_dep_store_id"))

    rfid_dep = deployments.filter(F.col("_dep_id").endswith("-RFID"))
    fixed_rfid = (zones.filter(F.col("zone_code").isin("entrance", "backroom"))
                  .withColumn("sensor_device_id",
                              F.concat(F.lit("SDV-"), F.col("store_zone_id"), F.lit("-RFID")))
                  .withColumn("device_type", F.lit("rfid_reader"))
                  .withColumn("sensing_technology", F.lit("rfid_uhf"))
                  .withColumn("device_role", F.lit("sense"))
                  .withColumn("manufacturer", F.lit("MFR-R"))
                  .withColumn("model", F.concat(F.lit("RFID-FIXED-"), F.upper(F.col("zone_code"))))
                  .withColumn("is_directional", F.col("zone_code") == F.lit("entrance"))
                  .withColumn("supports_dwell", F.lit(False))
                  .withColumn("supports_occupancy", F.lit(False))
                  .withColumn("is_mobile_platform", F.lit(False))
                  .withColumn("detection_limit_count", F.lit(None).cast("int"))
                  .withColumn("battery_powered", F.lit(False))
                  .withColumn("brick_class_iri", F.lit(None).cast("string"))
                  .withColumn("unit_iri", F.lit(None).cast("string"))
                  .withColumn("uom_code", F.lit("H87"))
                  .withColumn("accuracy_tolerance", F.lit(None).cast("double"))
                  .withColumn("probe_type", F.lit("none"))
                  .withColumn("is_backup_device", F.lit(False))
                  .withColumn("equipment_sk", F.lit(None).cast("bigint"))
                  .withColumn("equipment_id", F.lit(None).cast("string"))
                  .withColumn("_dep_suffix", F.lit("-RFID"))
                  .drop("is_countable"))

    mobile_kinds = F.array(F.lit("HANDHELD"), F.lit("ROBOT"))
    mobile_rfid = (zones.filter(F.col("zone_type") == F.lit("site"))
                   .withColumn("_mobile_kind", F.explode(mobile_kinds))
                   .withColumn("sensor_device_id",
                               F.concat(F.lit("SDV-"), F.col("store_id"), F.lit("-RFID-"), F.col("_mobile_kind")))
                   .withColumn("device_type", F.lit("rfid_reader"))
                   .withColumn("sensing_technology", F.lit("rfid_uhf"))
                   .withColumn("device_role", F.lit("sense"))
                   .withColumn("manufacturer", F.lit("MFR-R"))
                   .withColumn("model", F.concat(F.lit("RFID-MOBILE-"), F.col("_mobile_kind")))
                   .withColumn("is_directional", F.lit(False))
                   .withColumn("supports_dwell", F.lit(False))
                   .withColumn("supports_occupancy", F.lit(False))
                   .withColumn("is_mobile_platform", F.lit(True))
                   .withColumn("detection_limit_count", F.lit(None).cast("int"))
                   .withColumn("battery_powered", F.lit(True))
                   .withColumn("brick_class_iri", F.lit(None).cast("string"))
                   .withColumn("unit_iri", F.lit(None).cast("string"))
                   .withColumn("uom_code", F.lit("H87"))
                   .withColumn("accuracy_tolerance", F.lit(None).cast("double"))
                   .withColumn("probe_type", F.lit("none"))
                   .withColumn("is_backup_device", F.lit(False))
                   .withColumn("equipment_sk", F.lit(None).cast("bigint"))
                   .withColumn("equipment_id", F.lit(None).cast("string"))
                   .withColumn("_dep_suffix", F.lit("-RFID"))
                   .drop("is_countable", "_mobile_kind"))

    rfid_base = fixed_rfid.unionByName(mobile_rfid)
    rfid_devices = (rfid_base
                    .join(F.broadcast(rfid_dep),
                          rfid_base.store_id == rfid_dep._dep_store_id, "left")
                    .drop("_dep_store_id"))

    df = (counters.unionByName(probes).unionByName(rfid_devices)
          .withColumn("firmware_version", _pick(FIRMWARES, seed, "fw", F.col("sensor_device_id")))
          .withColumn("serial_number",
                      F.concat(F.lit("SN"), F.format_string("%08d", F.abs(F.hash(F.col("sensor_device_id"), F.lit(seed + 1))) % F.lit(99999999))))
          .withColumn("bacnet_device_id",
                      F.concat(F.lit("bacnet:"), F.format_string("%06d", F.abs(F.hash(F.col("sensor_device_id"), F.lit(seed + 2))) % F.lit(999999))))
          .withColumn("bacnet_object_ref",
                      F.when(F.col("device_type") == F.lit("people_counter"), F.lit("access-zone,1:present-value"))
                       .otherwise(F.lit("analog-input,1:present-value")))
          # FALSE on purpose. Out_Of_Service TRUE means Present_Value is SIMULATED, so
          # a device flagged TRUE that still emits valid rows is exactly the fault
          # sd_out_of_service_not_reporting looks for -- it must not be the default.
          .withColumn("bacnet_out_of_service", F.lit(False))
          .withColumn("opc_ua_node_id",
                      F.concat(F.lit("ns=2;s="), F.col("sensor_device_id")))
          .withColumn("sparkplug_edge_node_id",
                      F.concat(F.lit("edge-"), F.col("store_id")))
          .withColumn("calibration_certificate_id",
                      F.concat(F.lit("CAL-"), F.col("sensor_device_id")))
          .withColumn("calibration_valid_from", F.date_sub(F.current_date(), 180))
          .withColumn("calibration_valid_to", F.date_add(F.current_date(), 185))
          .withColumnRenamed("_dep_sk", "sensing_deployment_sk")
          .withColumnRenamed("_dep_id", "sensing_deployment_id")
          .withColumn("device_status", F.lit("active"))
          .withColumn("installed_date", F.lit("2024-01-01").cast("date"))
          .withColumn("decommissioned_date", F.lit(None).cast("date"))
          .withColumn("effective_from_date", F.lit("2024-01-01").cast("date"))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("_dep_suffix", "zone_code", "zone_type"))

    return _write(spark, df, f"{catalog}.{css_schema}.sensor_device",
                  SENSOR_DEVICE_COLUMNS, mode)


# ------------------------------------------------------------
# Fact
# ------------------------------------------------------------

def _grain_key_and_sk(df):
    """Build the durable grain key exactly as sri_grain_key_wellformed reconstructs it,
    then derive the surrogate as xxhash64 of it (ADR 0028).

    The interval component is unix_timestamp(), NOT interval_start_ts.cast("string").
    Databricks TIMESTAMP is TIMESTAMP_LTZ, so a cast to STRING renders in whatever
    spark.sql.session.timeZone the WRITER happened to have -- which would make the durable
    id a property of the session rather than of the row, and a restatement under a
    different timezone would insert a new row instead of updating the existing one.
    """
    return (df
            .withColumn("sensor_report_interval_id",
                        F.concat_ws("|",
                                    F.col("subject_type"),
                                    F.col("subject_id"),
                                    F.col("report_type"),
                                    F.col("aggregation_level"),
                                    F.col("interval_minutes").cast("string"),
                                    F.unix_timestamp(F.col("interval_start_ts")).cast("string"),
                                    F.col("sensor_device_id")))
            .withColumn("sensor_report_interval_sk", F.xxhash64(F.col("sensor_report_interval_id"))))


def _epcis_and_session_block(df, seed):
    """EPCIS provenance plus interval-grain source-message summaries.

    Raw message sequence, birth-death sequence, history, and quality codes belong to
    Bronze. Carrying one arbitrary raw value on an aggregate interval creates a false
    grain. The summaries below are additive and match this table's interval grain.
    """
    return (df
            .withColumn("min_value", F.lit(None).cast("double"))
            .withColumn("max_value", F.lit(None).cast("double"))
            .withColumn("mean_value", F.lit(None).cast("double"))
            # sDev is meaningful ONLY alongside meanValue per the EPCIS spec, and
            # sri_epcis_field_pairing enforces the pair. NULL both rather than emit a
            # dangling deviation.
            .withColumn("s_dev", F.lit(None).cast("double"))
            .withColumn("perc_rank", F.lit(None).cast("double"))
            .withColumn("perc_value", F.lit(None).cast("double"))
            .withColumn("string_value", F.lit(None).cast("string"))
            .withColumn("boolean_value", F.lit(None).cast("boolean"))
            .withColumn("device_metadata_uri",
                        F.concat(F.lit("urn:ordm:device-metadata:"), F.col("sensor_device_id")))
            .withColumn("raw_data_uri",
                        F.concat(F.lit("s3://ordm-bronze/sensing/"), F.col("sensor_device_id"),
                                 F.lit("/"), F.col("trading_date").cast("string")))
            .withColumn("data_processing_method_uri",
                        F.lit("urn:ordm:dpm:interval-aggregate:v1"))
            .withColumn(
                "source_session_id",
                F.concat(
                    F.lit("SESSION-"),
                    F.col("sensor_device_id"),
                    F.lit("-"),
                    F.col("trading_date").cast("string"),
                ),
            )
            # This synthetic source emits one usable observation per unique message.
            # Transport sequence gaps are a separate concern: a missing scheduled
            # observation is not automatically proof that a message sequence skipped.
            .withColumn("source_message_count", F.col("source_observation_count"))
            .withColumn("sequence_gap_count", F.lit(0).cast("bigint"))
            .withColumn("duplicate_delivery_count", F.lit(0).cast("bigint"))
            .withColumn("historical_message_count", F.lit(0).cast("bigint"))
            .withColumn("bad_quality_message_count", F.lit(0).cast("bigint"))
            .withColumn("restatement_version", F.lit(1))
            .withColumn("restated_at_timestamp", F.lit(None).cast("timestamp")))


def generate_sensor_report_interval(spark, catalog, css_schema, store_schema,
                                    calendar_schema, cfg, mode):
    seed = cfg["seed"]
    n_days = cfg["days"]
    n_intervals = cfg["intervals_per_day"]
    minutes = cfg["interval_minutes"]
    now = F.current_timestamp()

    # Trading dates come FROM fiscal_calendar. sri_calendar_orphan is error-severity,
    # and inventing dates would either fail it or (worse) pass it vacuously if the
    # ranges happened to overlap.
    dates = (spark.table(f"{catalog}.{calendar_schema}.fiscal_calendar")
             .select(F.col("date_key").alias("trading_date"))
             .filter(F.col("trading_date") <= F.current_date())
             .orderBy(F.col("trading_date").desc())
             .limit(n_days))

    devices = (spark.table(f"{catalog}.{css_schema}.sensor_device")
               .filter("is_current = TRUE AND device_type = 'people_counter'")
               .select("sensor_device_sk", "sensor_device_id", "store_sk", "store_id",
                       "store_zone_sk", "store_zone_id", "is_directional",
                       "supports_dwell", "detection_limit_count",
                       "sensing_deployment_sk", "sensing_deployment_id"))

    zone_types = (spark.table(f"{catalog}.{css_schema}.store_zone")
                  .filter("is_current = TRUE")
                  .select(F.col("store_zone_id").alias("_z_id"),
                          F.col("zone_type").alias("_z_type")))
    devices = (devices.join(F.broadcast(zone_types),
                            devices.store_zone_id == zone_types._z_id, "left")
               .drop("_z_id"))

    # Opening hours start at 08:00 local; interval i covers [08:00 + i*minutes, +minutes).
    intervals = spark.range(n_intervals).withColumnRenamed("id", "slot")

    # ---- area-level rows: one per device per interval ----
    area = (devices.crossJoin(dates).crossJoin(intervals)
            .withColumn("subject_type", F.lit("space"))
            .withColumn("subject_id", F.col("store_zone_id"))
            .withColumn("aggregation_level", F.lit("area"))
            .withColumn("product_sk", F.lit(None).cast("bigint"))
            .withColumn("product_id", F.lit(None).cast("string"))
            # A space subject has no asset: footfall is about the zone, not about a
            # maintained unit standing in it.
            .withColumn("equipment_sk", F.lit(None).cast("bigint"))
            .withColumn("equipment_id", F.lit(None).cast("string")))

    # ---- site-level rows: one per store per interval, measured at the entrance ----
    # Generated INDEPENDENTLY of the area rows, never as their sum. A site total that
    # equalled the zone sum would violate the serving contract because a shopper
    # traversing five zones is counted five times.
    site_devices = (devices.filter(F.col("_z_type") == F.lit("entrance"))
                    .withColumn("subject_id", F.concat(F.lit("SZ-"), F.col("store_id"), F.lit("-SITE"))))
    site_zone = (spark.table(f"{catalog}.{css_schema}.store_zone")
                 .filter("is_current = TRUE AND zone_type = 'site'")
                 .select(F.col("store_zone_sk").alias("_site_zone_sk"),
                         F.col("store_zone_id").alias("_site_zone_id"),
                         F.col("store_id").alias("_site_store_id")))
    site = (site_devices
            .join(F.broadcast(site_zone), site_devices.store_id == site_zone._site_store_id, "left")
            .withColumn("store_zone_sk", F.col("_site_zone_sk"))
            .withColumn("store_zone_id", F.col("_site_zone_id"))
            .drop("_site_zone_sk", "_site_zone_id", "_site_store_id")
            .crossJoin(dates).crossJoin(intervals)
            .withColumn("subject_type", F.lit("space"))
            .withColumn("aggregation_level", F.lit("site"))
            .withColumn("product_sk", F.lit(None).cast("bigint"))
            .withColumn("product_id", F.lit(None).cast("string"))
            .withColumn("equipment_sk", F.lit(None).cast("bigint"))
            .withColumn("equipment_id", F.lit(None).cast("string")))

    counts = area.unionByName(site)

    counts = (counts
              .withColumn("report_type", F.lit("gs1:Count"))
              .withColumn("interval_minutes", F.lit(minutes))
              # Store-local wall clock is 08:00 + slot*minutes; the STORED value is the
              # UTC instant, and utc_offset_minutes is what lets a consumer recover the
              # local time unambiguously across the DST fold (ADR: CSS-INTERVAL-CONTRACT).
              .withColumn("utc_offset_minutes", F.lit(-300).cast("smallint"))
              .withColumn("store_timezone", F.lit("America/New_York"))
              .withColumn("hour_of_day", (F.lit(8) + F.col("slot") * F.lit(minutes) / F.lit(60)).cast("int"))
              .withColumn("interval_start_ts",
                          F.col("trading_date").cast("timestamp")
                          + F.expr("INTERVAL '1' MINUTE") * (F.lit(8 * 60) - F.col("utc_offset_minutes") + F.col("slot") * F.lit(minutes)))
              .withColumn("interval_end_ts",
                          F.col("interval_start_ts") + F.expr("INTERVAL '1' MINUTE") * F.lit(minutes))
              .withColumn("trading_day_offset", F.lit(0).cast("smallint"))
              .withColumn("day_part",
                          F.when(F.col("hour_of_day") < 8, F.lit("pre_open"))
                           .when(F.col("hour_of_day") < 11, F.lit("morning"))
                           .when(F.col("hour_of_day") < 14, F.lit("midday"))
                           .when(F.col("hour_of_day") < 17, F.lit("afternoon"))
                           .when(F.col("hour_of_day") < 21, F.lit("evening"))
                           .otherwise(F.lit("late")))
              .withColumn("is_partial_interval", F.lit(False))
              .withColumn("is_dst_transition", F.lit(False))
              .withColumn("time_mode", F.lit("within_operating_hours")))

    counts = _grain_key_and_sk(counts)

    # Raw shopper count. Site traffic is scaled up and given its own hash salt, so it
    # is arithmetically unrelated to the zone rows.
    base = F.when(F.col("aggregation_level") == F.lit("site"),
                  F.lit(60) + (F.abs(F.hash(F.col("sensor_report_interval_id"), F.lit(seed + 3))) % F.lit(240)))\
            .otherwise(F.lit(4) + (F.abs(F.hash(F.col("sensor_report_interval_id"), F.lit(seed + 4))) % F.lit(90)))

    counts = (counts
              .withColumn("visitor_count_raw", base.cast("bigint"))
              # Staff are a fraction of raw, and visitor_count_adjusted must equal
              # raw - staff exactly: ftid_staff_adjustment_balances is error-severity.
              .withColumn("staff_count",
                          F.least(F.col("visitor_count_raw") - F.lit(1),
                                  (F.col("visitor_count_raw") * F.lit(0.08)).cast("bigint")).cast("bigint"))
              .withColumn("visitor_count_adjusted",
                          (F.col("visitor_count_raw") - F.col("staff_count")).cast("bigint"))
              .withColumn("footfall_count", F.col("visitor_count_adjusted"))
              .withColumn("entry_count", F.col("visitor_count_adjusted"))
              # Directional devices measure exits independently, so entries and exits
              # never match exactly -- a vendor worked example returns 173 in /
              # 174 out. Kept inside the 5% band ftid_entry_exit_reconciliation allows.
              .withColumn("exit_count",
                          F.when(F.col("is_directional") == True,
                                 (F.col("visitor_count_adjusted")
                                  + (F.abs(F.hash(F.col("sensor_report_interval_id"), F.lit(seed + 5))) % F.lit(3)) - F.lit(1)).cast("bigint"))
                           .otherwise(F.lit(None).cast("bigint")))
              .withColumn("directionality",
                          F.when(F.col("is_directional") == True, F.lit("bidirectional"))
                           .otherwise(F.lit("none")))
              .withColumn("count_divisor",
                          F.when(F.col("is_directional") == True, F.lit(1)).otherwise(F.lit(2)))
              .withColumn("child_count",
                          (F.col("footfall_count") * F.lit(0.12)).cast("bigint"))
              .withColumn("passersby_count",
                          (F.col("visitor_count_raw") * F.lit(4)).cast("bigint"))
              .withColumn("unique_visitor_count", F.lit(None).cast("bigint")))

    counts = (counts
              # Uniform across a store-day-level, because rows that get summed must
              # share a convention or the sum is meaningless (sri_counting_convention_uniform).
              .withColumn("counting_unit", F.lit("person"))
              .withColumn("group_counting_enabled", F.lit(False))
              .withColumn("unique_visitor_enabled", F.lit(False))
              .withColumn("child_counting_enabled", F.lit(True))
              .withColumn("child_height_threshold_cm", F.lit(130))
              .withColumn("staff_exclusion_enabled", F.lit(True))
              .withColumn("staff_adjustment_applied", F.lit(True))
              .withColumn("staff_exclusion_method", F.lit("exclusion_line"))
              .withColumn("staff_exclusion_stage", F.lit("at_aggregation"))
              .withColumn("staff_exclusion_grade", F.lit("high"))
              # One vendor includes entrants in pass-by, another excludes them --
              # a factor-of-the-capture-rate difference, so the convention travels.
              .withColumn("passby_convention", F.lit("excludes_entrants")))

    counts = (counts
              .withColumn("cumulative_entries",
                          F.sum("entry_count").over(
                              Window.partitionBy("sensor_device_id", "trading_date", "aggregation_level")
                                    .orderBy("interval_start_ts")).cast("bigint"))
              .withColumn("cumulative_exits",
                          F.coalesce(F.sum("exit_count").over(
                              Window.partitionBy("sensor_device_id", "trading_date", "aggregation_level")
                                    .orderBy("interval_start_ts")), F.lit(0)).cast("bigint"))
              .withColumn("occupancy_adjustment", F.lit(0))
              .withColumn("adjustment_source", F.lit(None).cast("string"))
              # occupancy = entries - exits + adjustment, exactly as
              # sri_occupancy_balance reconstructs it. Negative values are LEFT ALONE:
              # drift is the signal, and clamping it here would hide the only evidence
              # the balance has broken.
              .withColumn("occupancy_snapshot_end",
                          (F.col("cumulative_entries") - F.col("cumulative_exits")
                           + F.col("occupancy_adjustment")).cast("bigint"))
              .withColumn("occupancy_min",
                          F.greatest(F.lit(0), F.col("occupancy_snapshot_end") - F.lit(5)).cast("bigint"))
              .withColumn("occupancy_max",
                          F.least(F.col("occupancy_snapshot_end") + F.lit(5), F.lit(880)).cast("bigint"))
              .withColumn("occupancy_avg",
                          ((F.col("occupancy_min") + F.col("occupancy_max")) / F.lit(2.0)).cast("double"))
              .withColumn("last_reset_local_ts",
                          F.col("trading_date").cast("timestamp")))

    counts = (counts
              # Stored as SUM + COUNT so it re-aggregates: a pre-computed average
              # cannot be rolled up without its denominator.
              .withColumn("dwell_count",
                          F.when(F.col("supports_dwell") == True, F.col("footfall_count")).otherwise(F.lit(None).cast("bigint")))
              .withColumn("dwell_seconds_total",
                          F.when(F.col("supports_dwell") == True,
                                 (F.col("footfall_count") * (F.lit(45) + (F.abs(F.hash(F.col("sensor_report_interval_id"), F.lit(seed + 6))) % F.lit(200)))).cast("bigint"))
                           .otherwise(F.lit(None).cast("bigint")))
              .withColumn("engagement_threshold_seconds",
                          F.when(F.col("supports_dwell") == True, F.lit(30)).otherwise(F.lit(None).cast("int")))
              .withColumn("engaged_count",
                          F.when(F.col("supports_dwell") == True,
                                 (F.col("dwell_count") * F.lit(0.6)).cast("bigint")).otherwise(F.lit(None).cast("bigint")))
              .withColumn("passing_count",
                          F.when(F.col("supports_dwell") == True,
                                 (F.col("dwell_count") - (F.col("dwell_count") * F.lit(0.6)).cast("bigint")).cast("bigint"))
                           .otherwise(F.lit(None).cast("bigint"))))

    counts = (counts
              .withColumn("value", F.col("footfall_count").cast("double"))
              .withColumn("is_zero_observed", F.col("footfall_count") == F.lit(0))
              # A person count is dimensionless, which is why sri_uom_present exempts
              # gs1:Count from needing a unit.
              .withColumn("uom", F.lit(None).cast("string"))
              .withColumn("unit_iri", F.lit(None).cast("string")))

    counts = _quality_block(counts, seed)
    counts = _epcis_and_session_block(counts, seed)
    counts = (counts
              .withColumn("biz_rules_uri", F.lit(None).cast("string")))

    # ---- environmental rows ----
    env = _generate_env_rows(spark, catalog, css_schema, calendar_schema, dates, cfg, minutes)

    fact = (counts.select(*SENSOR_REPORT_INTERVAL_COLUMNS[:-2],
                          F.lit(RECORD_SOURCE).alias("record_source"),
                          now.alias("load_timestamp"))
            .unionByName(env.select(*SENSOR_REPORT_INTERVAL_COLUMNS[:-2],
                                    F.lit(RECORD_SOURCE).alias("record_source"),
                                    now.alias("load_timestamp"))))

    traffic_detail = counts.select(*FOOT_TRAFFIC_INTERVAL_DETAIL_COLUMNS)

    _write(spark, fact, f"{catalog}.{css_schema}.sensor_report_interval",
           SENSOR_REPORT_INTERVAL_COLUMNS, mode)
    return _write(
        spark,
        traffic_detail,
        f"{catalog}.{css_schema}.foot_traffic_interval_detail",
        FOOT_TRAFFIC_INTERVAL_DETAIL_COLUMNS,
        mode,
    )


def _quality_block(df, seed):
    """Validity and completeness as TWO ORTHOGONAL axes, not one score.

    That separation is the point: a sensor with its batteries pulled for 15 minutes
    produces an interval that is INVALID BUT COMPLETE, and a still-open current interval
    is VALID BUT INCOMPLETE. Collapsing them into a single quality score makes those two
    situations indistinguishable, which is the defect the CSS-QUALITY-CONTRACT fixes.
    """
    degraded = _frac(seed, "degraded", F.col("sensor_report_interval_id")) < F.lit(0.04)
    late = _frac(seed, "late", F.col("sensor_report_interval_id")) < F.lit(0.03)
    return (df
            .withColumn("measurement_validity",
                        F.when(degraded, F.lit("degraded")).otherwise(F.lit("valid")))
            .withColumn("arrival_completeness",
                        F.when(late, F.lit("late_arrived")).otherwise(F.lit("complete")))
            .withColumn("is_imputed", F.lit(False))
            # The one-minute source cadence is a synthetic-fixture assumption only.
            # Production pipelines derive both fields from effective-dated source
            # cadence and delivery metadata, never from the measured value.
            .withColumn(
                "expected_observation_count",
                F.col("interval_minutes").cast("bigint"),
            )
            .withColumn(
                "source_observation_count",
                F.when(
                    F.col("arrival_completeness") == F.lit("complete"),
                    F.col("expected_observation_count"),
                ).otherwise(
                    F.greatest(F.col("expected_observation_count") - F.lit(1), F.lit(0))
                ).cast("bigint"),
            )
            .withColumn("uptime_ratio",
                        F.when(degraded, F.lit(0.6) + _frac(seed, "up", F.col("sensor_report_interval_id")) * F.lit(0.3))
                         .otherwise(F.lit(1.0)))
            .withColumn("coverage_ratio",
                        F.lit(0.9) + _frac(seed, "cov", F.col("sensor_report_interval_id")) * F.lit(0.1))
            .withColumn("confidence_score",
                        F.lit(0.8) + _frac(seed, "conf", F.col("sensor_report_interval_id")) * F.lit(0.2))
            .withColumn("sensor_online_flag", ~degraded)
            .withColumn("is_capped", F.lit(False))
            .withColumn("capped_count_limit", F.lit(None).cast("int"))
            .withColumn("latency_seconds",
                        (F.lit(30) + (F.abs(F.hash(F.col("sensor_report_interval_id"), F.lit(seed + 7))) % F.lit(240))).cast("int"))
            .withColumn("ingest_timestamp",
                        F.col("interval_end_ts") + F.expr("INTERVAL '1' SECOND") * F.col("latency_seconds")))


def _generate_env_rows(spark, catalog, css_schema, calendar_schema, dates, cfg, minutes):
    """gs1:Temperature rows proving that the shared envelope serves another vertical.

    Environmental compliance measures will use their own keyed extension when that
    solution is completed; the reusable interval and value fields already belong here.
    """
    seed = cfg["seed"]
    n_int = cfg["env_intervals_per_device"]

    probes = (spark.table(f"{catalog}.{css_schema}.sensor_device")
              .filter("is_current = TRUE AND device_type = 'temperature'")
              .select("sensor_device_sk", "sensor_device_id", "store_sk", "store_id",
                      "store_zone_sk", "store_zone_id", "equipment_sk", "equipment_id",
                      "sensing_deployment_sk", "sensing_deployment_id"))
    intervals = spark.range(n_int).withColumnRenamed("id", "slot")

    df = (probes.crossJoin(dates.limit(2)).crossJoin(intervals)
          .withColumn("subject_type", F.lit("point"))
          .withColumn("subject_id", F.col("equipment_id"))
          .withColumn("product_sk", F.lit(None).cast("bigint"))
          .withColumn("product_id", F.lit(None).cast("string"))
          # equipment_sk and equipment_id come STRAIGHT THROUGH from the probe here, but
          # they are carried on the fact rather than looked up through the device because
          # the reading is about the refrigeration case: re-pointing the probe at another
          # case must not rewrite either case's temperature history.
          .withColumn("report_type", F.lit("gs1:Temperature"))
          .withColumn("aggregation_level", F.lit("device"))
          .withColumn("interval_minutes", F.lit(minutes))
          .withColumn("utc_offset_minutes", F.lit(-300).cast("smallint"))
          .withColumn("store_timezone", F.lit("America/New_York"))
          .withColumn("hour_of_day", F.col("slot").cast("int"))
          .withColumn("interval_start_ts",
                      F.col("trading_date").cast("timestamp")
                      + F.expr("INTERVAL '1' MINUTE") * (F.lit(0) - F.col("utc_offset_minutes") + F.col("slot") * F.lit(minutes)))
          .withColumn("interval_end_ts",
                      F.col("interval_start_ts") + F.expr("INTERVAL '1' MINUTE") * F.lit(minutes))
          .withColumn("trading_day_offset", F.lit(0).cast("smallint"))
          .withColumn("day_part",
                      F.when(F.col("hour_of_day") < 8, F.lit("pre_open"))
                       .when(F.col("hour_of_day") < 11, F.lit("morning"))
                       .when(F.col("hour_of_day") < 14, F.lit("midday"))
                       .when(F.col("hour_of_day") < 17, F.lit("afternoon"))
                       .when(F.col("hour_of_day") < 21, F.lit("evening"))
                       .otherwise(F.lit("late")))
          .withColumn("is_partial_interval", F.lit(False))
          .withColumn("is_dst_transition", F.lit(False))
          # Cold chain runs regardless of trading hours, which is exactly why time_mode
          # is per-row rather than per-feed.
          .withColumn("time_mode", F.lit("all_day")))

    df = _grain_key_and_sk(df)

    # Baseline cold-hold readings sit in range (1.5-5.9 degC). Without any excursion the
    # 8 degC evaluation rule could never fire, execution_log would stay empty and every
    # IoT Sensor Monitoring surface would be empty on the demo. So roughly one device-day
    # in three carries ONE contiguous excursion: a run of 2-4 hourly intervals at
    # 8.5-10.9 degC starting between 09:00 and 16:00 local. Deterministic (seeded hash on
    # device + trading_date), so episodes are reproducible run to run.
    day_hash = F.abs(F.hash(F.col("sensor_device_id"), F.col("trading_date"), F.lit(seed + 21)))
    exc_start = F.lit(9) + day_hash % F.lit(8)
    exc_len = F.lit(2) + (day_hash / F.lit(8)).cast("bigint") % F.lit(3)
    in_excursion = ((day_hash % F.lit(3)) == F.lit(0)) \
        & (F.col("slot") >= exc_start) & (F.col("slot") < exc_start + exc_len)
    baseline = (F.lit(1.5)
                + (F.abs(F.hash(F.col("sensor_report_interval_id"), F.lit(seed + 8))) % F.lit(45)).cast("double") / F.lit(10.0))
    excursion = (F.lit(8.5)
                 + (F.abs(F.hash(F.col("sensor_report_interval_id"), F.lit(seed + 22))) % F.lit(25)).cast("double") / F.lit(10.0))
    reading = F.when(in_excursion, excursion).otherwise(baseline)
    df = (df
          .withColumn("value", reading)
          .withColumn("uom", F.lit("CEL"))
          .withColumn("unit_iri", F.lit(QUDT_DEG_C)))

    df = _quality_block(df, seed)
    df = _epcis_and_session_block(df, seed)
    return df.withColumn("biz_rules_uri", F.lit("urn:ordm:biz-rules:cold-hold-v1"))


# ---- entry point ----

# ------------------------------------------------------------
# Automation loop (IoT Sensor Monitoring): sense -> evaluate -> act -> log
# ------------------------------------------------------------

def generate_actuator_capability(spark, catalog, css_schema, equipment_schema, cfg, mode):
    """One compressor-relay actuator per refrigeration probe's asset.

    The actuator is a capability of the temperature device (whose device_role is 'both' --
    it senses temperature and, through this capability, actuates the compressor relay),
    driving the same refrigeration equipment the probe monitors -- which is why equipment_sk
    is populated for the cold-chain case.
    """
    now = F.current_timestamp()
    probes = (spark.table(f"{catalog}.{css_schema}.sensor_device")
              .filter("is_current = TRUE AND device_type = 'temperature'")
              .select("sensor_device_sk", "sensor_device_id", "equipment_sk", "equipment_id"))

    df = (probes
          .withColumn("actuator_capability_id",
                      F.concat(F.lit("ACT-"), F.col("sensor_device_id"), F.lit("-COMP")))
          .withColumn("command_type", F.lit("toggle_power"))
          .withColumn("acceptable_value_range", F.lit("0,1"))
          .withColumn("unit_iri", F.lit(None).cast("string"))
          .withColumn("uom_code", F.lit(None).cast("string"))
          .withColumn("actuator_status", F.lit("active"))
          .withColumn("installed_date", F.lit("2024-01-01").cast("date"))
          .withColumn("decommissioned_date", F.lit(None).cast("date"))
          .withColumn("effective_from_date", F.lit("2024-01-01").cast("date"))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))

    return _write(spark, df, f"{catalog}.{css_schema}.actuator_capability",
                  ACTUATOR_CAPABILITY_COLUMNS, mode)


def generate_evaluation_rule(spark, catalog, css_schema, cfg, mode):
    """One cold-chain over-temperature rule per environmental probe.

    report_type = gs1:Temperature matches the readings the rule evaluates, and the 8 degC
    / 600 s threshold mirrors a vaccine cold-hold excursion definition.
    """
    now = F.current_timestamp()
    probes = (spark.table(f"{catalog}.{css_schema}.sensor_device")
              .filter("is_current = TRUE AND device_type = 'temperature'")
              .select("sensor_device_sk", "sensor_device_id"))

    df = (probes
          .withColumn("evaluation_rule_id",
                      F.concat(F.lit("RULE-"), F.col("sensor_device_id"), F.lit("-HITEMP")))
          .withColumn("rule_name",
                      F.concat(F.lit("Over-temperature excursion, device "), F.col("sensor_device_id")))
          .withColumn("report_type", F.lit("gs1:Temperature"))
          .withColumn("condition_operator", F.lit("greater_than"))
          .withColumn("threshold_value_numeric", F.lit(8.0).cast("double"))
          .withColumn("threshold_value_upper", F.lit(None).cast("double"))
          .withColumn("unit_iri", F.lit(QUDT_DEG_C))
          .withColumn("uom_code", F.lit("CEL"))
          .withColumn("time_window_seconds", F.lit(600))
          .withColumn("severity", F.lit("critical"))
          .withColumn("is_enabled", F.lit(True))
          .withColumn("effective_from_date", F.lit("2024-01-01").cast("date"))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))

    return _write(spark, df, f"{catalog}.{css_schema}.evaluation_rule",
                  EVALUATION_RULE_COLUMNS, mode)


def generate_automation_action(spark, catalog, css_schema, cfg, mode):
    """Each rule fans out to TWO actions: a system_command that toggles the matching
    compressor actuator, AND a notification to the store-manager role.

    The two-action fan-out is deliberate. It is the exact multi-action case the model is
    built for ("notify a manager AND toggle a compressor"), and generating only the single
    actuator action would leave that fan-out -- and the durable-key grain that depends on
    it -- untested: el_grain_unique only becomes a real test once one breaching interval
    drives more than one firing. It also exercises BOTH branches of
    chk_automation_action_actuator_target / aa_actuator_target_consistent: the actuator
    action carries the typed actuator_capability_sk (target_entity_type = actuator), and
    the notification carries a NULL actuator key against a polymorphic role target.

    The rule, its device and the actuator share the sensor_device_id stem, so the join
    that pairs them is deterministic.
    """
    now = F.current_timestamp()
    rules = (spark.table(f"{catalog}.{css_schema}.evaluation_rule")
             .filter("is_current = TRUE")
             .select("evaluation_rule_sk", "evaluation_rule_id",
                     # RULE-<device>-HITEMP -> <device>
                     F.regexp_replace(F.regexp_replace(F.col("evaluation_rule_id"),
                                                       r"^RULE-", ""),
                                      r"-HITEMP$", "").alias("_device_id")))
    actuators = (spark.table(f"{catalog}.{css_schema}.actuator_capability")
                 .filter("is_current = TRUE")
                 .select(F.col("actuator_capability_sk"), F.col("actuator_capability_id"),
                         F.col("sensor_device_id").alias("_act_device_id")))

    paired = (rules.join(F.broadcast(actuators),
                         rules._device_id == actuators._act_device_id, "left")
              .drop("_device_id", "_act_device_id"))

    # Action 1 -- the physical command. Typed actuator target, so it carries the
    # actuator_capability_sk/_id resolved by the join above.
    cool = (paired
            .withColumn("automation_action_id",
                        F.concat(F.lit("AA-"), F.col("evaluation_rule_id"), F.lit("-COOL")))
            .withColumn("action_type", F.lit("system_command"))
            .withColumn("target_entity_type", F.lit("actuator"))
            .withColumn("target_entity_id", F.col("actuator_capability_id"))
            .withColumn("payload_template",
                        F.lit('{"command": "start_cooling", "power_level": "max"}')))

    # Action 2 -- the manager notification. Polymorphic role target with NO typed actuator
    # key: this is the non-actuator branch of chk_automation_action_actuator_target, and
    # the second firing per breach that turns el_grain_unique into a real fan-out test.
    notify = (paired
              .withColumn("actuator_capability_sk", F.lit(None).cast("bigint"))
              .withColumn("actuator_capability_id", F.lit(None).cast("string"))
              .withColumn("automation_action_id",
                          F.concat(F.lit("AA-"), F.col("evaluation_rule_id"), F.lit("-NOTIFY")))
              .withColumn("action_type", F.lit("notification"))
              .withColumn("target_entity_type", F.lit("role"))
              .withColumn("target_entity_id", F.lit("ROLE-store-manager"))
              .withColumn("payload_template",
                          F.lit('{"channel": "ops_alert", "message": "Cold-chain over-temperature excursion"}')))

    df = (cool.unionByName(notify)
          .withColumn("is_enabled", F.lit(True))
          .withColumn("effective_from_date", F.lit("2024-01-01").cast("date"))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now))

    return _write(spark, df, f"{catalog}.{css_schema}.automation_action",
                  AUTOMATION_ACTION_COLUMNS, mode)


def generate_execution_log(spark, catalog, css_schema, cfg, mode):
    """One realised firing per (breaching interval x action that fires off it).

    Closes the loop to the observation: the log row carries the
    sensor_report_interval_sk whose value exceeded the 8 degC threshold, so
    el_interval_fk_orphan is a real test. Because each rule now owns two actions
    (generate_automation_action), a single breaching interval produces TWO firings, which
    is exactly the fan-out el_grain_unique has to survive. Append-only, so mode is forced
    to append.
    """
    now = F.current_timestamp()
    seed = cfg["seed"]
    breaches = (spark.table(f"{catalog}.{css_schema}.sensor_report_interval")
                .filter("report_type = 'gs1:Temperature' AND measurement_validity = 'valid' AND value > 8.0")
                .select("sensor_report_interval_sk", "sensor_device_id",
                        "interval_end_ts"))
    rules = (spark.table(f"{catalog}.{css_schema}.evaluation_rule")
             .filter("is_current = TRUE")
             .select(F.col("evaluation_rule_sk"), F.col("evaluation_rule_id"),
                     F.col("sensor_device_id").alias("_rule_device_id")))
    actions = (spark.table(f"{catalog}.{css_schema}.automation_action")
               .filter("is_current = TRUE")
               .select(F.col("automation_action_sk"), F.col("automation_action_id"),
                       F.col("actuator_capability_sk"), F.col("actuator_capability_id"),
                       F.col("evaluation_rule_sk").alias("_act_rule_sk")))

    df = (breaches
          .join(F.broadcast(rules), breaches.sensor_device_id == rules._rule_device_id, "inner")
          .join(F.broadcast(actions), F.col("evaluation_rule_sk") == actions._act_rule_sk, "inner")
          .drop("_rule_device_id", "_act_rule_sk", "sensor_device_id")
          # The durable key must identify the FIRING, not just the interval. Keying on the
          # interval alone collides the moment a rule owns more than one action (it now
          # owns two), silently violating el_grain_unique. automation_action_id is what
          # distinguishes the compressor firing from the notification off the same breach.
          .withColumn("execution_log_id",
                      F.concat(F.lit("EXEC-"), F.col("automation_action_id"), F.lit("-"),
                               F.col("sensor_report_interval_sk").cast("string")))
          .withColumn("triggered_at_timestamp",
                      F.coalesce(F.col("interval_end_ts"), now))
          # Mostly successful, with a deterministic minority of failures and timeouts so the
          # rule-effectiveness and excursion-response surfaces have something to measure.
          .withColumn("_exec_bucket",
                      F.abs(F.hash(F.col("execution_log_id"), F.lit(seed + 23))) % F.lit(20))
          .withColumn("execution_status",
                      F.when(F.col("_exec_bucket") < F.lit(2), F.lit("failure"))
                       .when(F.col("_exec_bucket") == F.lit(2), F.lit("timeout"))
                       .otherwise(F.lit("success")))
          .withColumn("response_payload",
                      F.when(F.col("execution_status") == F.lit("failure"),
                             F.lit('{"status_code": 502, "message": "Actuator did not acknowledge"}'))
                       .when(F.col("execution_status") == F.lit("timeout"),
                             F.lit('{"status_code": 504, "message": "Actuator response timed out"}'))
                       .otherwise(F.lit('{"status_code": 200, "message": "Actuator triggered successfully"}')))
          .drop("_exec_bucket")
          # A synthesised automation-RESPONSE latency (ms from the breaching observation to
          # this firing), NOT the interval's ingest lag. execution_log.latency_ms measures
          # actuator/notification responsiveness -- a different quantity from
          # sensor_report_interval.latency_seconds (seconds from interval end to ingest),
          # so reusing that would make the numbers read as real responsiveness when they
          # are not. A small hash-derived value (50-1500 ms) keeps them plausible.
          .withColumn("latency_ms",
                      (F.lit(50) + (F.abs(F.hash(F.col("execution_log_id"), F.lit(seed + 9))) % F.lit(1450))).cast("bigint"))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("interval_end_ts"))

    # Append-only fact: never INSERT OVERWRITE. On a re-run the deterministic
    # execution_log_id keeps the reload idempotent under overwrite semantics upstream,
    # but the table's own contract is append, matching its transactional tag.
    return _write(spark, df, f"{catalog}.{css_schema}.execution_log",
                  EXECUTION_LOG_COLUMNS, "append" if mode == "append" else mode)


def run(ctx):
    spark, catalog, mode = ctx.spark, ctx.catalog, ctx.mode
    css_schema = ctx.schemas["css"]
    store_schema = ctx.schemas["store"]
    calendar_schema = ctx.schemas["calendar"]
    equipment_schema = ctx.schemas["equipment"]
    cfg = load_config()

    from _smart_shelf import (
        generate_smart_shelf,
        generate_smart_shelf_deployments,
        generate_smart_shelf_devices,
        generate_smart_shelf_zones,
        validate_smart_shelf_config,
    )

    validate_smart_shelf_config(cfg)
    generate_store_zone(spark, catalog, css_schema, store_schema, cfg, mode)
    generate_smart_shelf_zones(ctx, cfg, STORE_ZONE_COLUMNS)
    generate_sensing_disclosure_policy(spark, catalog, css_schema, mode)
    generate_sensing_deployment(spark, catalog, css_schema, store_schema, cfg, mode)
    generate_smart_shelf_deployments(ctx, cfg, SENSING_DEPLOYMENT_COLUMNS)
    generate_sensor_device(spark, catalog, css_schema, equipment_schema, cfg, mode)
    generate_smart_shelf_devices(ctx, cfg, SENSOR_DEVICE_COLUMNS)
    generate_sensor_report_interval(spark, catalog, css_schema, store_schema,
                                    calendar_schema, cfg, mode)
    # Automation loop (IoT Sensor Monitoring), in dependency order: actuator + rule ->
    # action -> log. execution_log reads sensor_report_interval, so it must run last.
    generate_actuator_capability(spark, catalog, css_schema, equipment_schema, cfg, mode)
    generate_evaluation_rule(spark, catalog, css_schema, cfg, mode)
    generate_automation_action(spark, catalog, css_schema, cfg, mode)
    generate_execution_log(spark, catalog, css_schema, cfg, mode)
    from _rfid import generate_rfid
    generate_rfid(ctx, cfg)
    generate_smart_shelf(ctx, cfg)
    print("[ordm] connected-store-signals generation complete.")


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
