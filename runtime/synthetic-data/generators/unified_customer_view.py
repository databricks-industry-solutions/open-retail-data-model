# ============================================================
# ORDM · Synthetic data · Unified Customer View (CDP) generator
# Version: 0.5
# Generated: 2026-10-12
# LLM-generated: true (maintainer-reviewed before release)
# ============================================================
# Populates the CDP activation layer tables: activation_destination (reference),
# activation_job (append-only fact), and campaign_touch (append-only fact).
# Closure: describes where audiences publish, what jobs ran, and which customer
# touches resulted from campaigns. Requires upstreams: marketing.audience,
# marketing.promotion, customer.profile.
# ============================================================

import os
import sys
from pyspark.sql import SparkSession, functions as F
from pyspark.sql.window import Window

try:
    from _common import RECORD_SOURCE, load_domain_config, _pick, _write
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import RECORD_SOURCE, load_domain_config, _pick, _write

# ============================================================
# Column contracts -- MUST match the DDL (minus IDENTITY _sk)
# ============================================================

ACTIVATION_DESTINATION_COLUMNS = [
    "activation_destination_id", "destination_name", "destination_platform",
    "connector_kind", "match_key_type", "required_consent_purpose",
    "required_channel", "data_residency_region", "is_addressable_flag",
    "owner_team", "created_timestamp", "source_updated_timestamp",
    "record_source", "load_timestamp",
]

ACTIVATION_JOB_COLUMNS = [
    "activation_job_id", "audience_sk", "audience_id",
    "activation_destination_sk", "activation_destination_id",
    "membership_as_of_date", "job_run_ts", "job_run_date", "job_status",
    "purpose_code", "channel_code", "jurisdiction_code",
    "requested_member_count", "eligible_member_count", "blocked_member_count",
    "exported_member_count", "match_rate", "sync_mode", "removed_member_count",
    "delivered_member_count", "rejected_member_count",
    "job_started_ts", "job_completed_ts",
    "is_consent_enforced_flag", "is_suppression_applied_flag",
    "destination_audience_ref", "failure_reason_code", "model_version",
    "record_source", "load_timestamp",
]

CAMPAIGN_TOUCH_COLUMNS = [
    "campaign_touch_id", "profile_sk", "profile_id",
    "audience_sk", "audience_id", "promo_sk", "promo_id",
    "activation_job_sk", "activation_job_id",
    "external_campaign_id", "touch_ts", "touch_date",
    "touch_direction", "touch_type", "channel_code",
    "delivery_status_code", "destination_delivery_status",
    "consent_status", "message_ref", "record_source", "load_timestamp",
]

# Domain enums (MUST be subsets of DDL CHECK constraints)
CONNECTOR_KINDS = ["reverse_etl", "api_push", "file_export"]
MATCH_KEY_TYPES = ["email_hash", "phone_hash", "people_based_id", "platform_user_id"]
# A destination's (required_consent_purpose, required_channel, match_key_type) is drawn as
# one pair that respects the eligibility gate (ADR 0028): marketing is a purpose x owned
# channel compound (email / sms), every other purpose is channel-agnostic (NULL channel) and
# matches on a people-based id. Destinations cycle through these in order.
DESTINATION_PROFILES = [
    ("marketing", "email", "email_hash"),
    ("marketing", "sms", "phone_hash"),
    ("personalization", None, "people_based_id"),
]
# The purposes and owned channels DESTINATION_PROFILES uses (kept as literals for the tests).
PURPOSES = ["marketing", "personalization"]
CHANNELS = ["email", "sms"]
REGIONS = ["US", "EU", "CA"]

JOB_STATUSES = ["succeeded", "partial"]
SYNC_MODES = ["full_refresh", "incremental_upsert"]
FAILURE_REASONS = ["none"]

TOUCH_DIRECTIONS = ["outbound"]
TOUCH_TYPES = ["send", "delivery", "click"]
DELIVERY_STATUSES = ["sent", "delivered", "suppressed"]
# Consent at touch time: the runs are consent-enforced (the gate is opt-in, ADR 0028), so
# every contact they produce was made with consent granted.
CONSENT_STATUSES = ["granted"]
# Jurisdictions the runs are scoped to, a subset of the ones the eligibility gate resolves.
JURISDICTIONS = ["US", "US-CA", "CA", "EU", "GB"]

# ============================================================
# Configuration and helper functions
# ============================================================

def load_config():
    c = load_domain_config("unified_customer_view") or {}
    vols = c.get("volumes", {}) or {}
    return {
        "seed": c.get("seed", 17017),
        "destinations": vols.get("destinations", 5),
        "jobs_per_destination": vols.get("jobs_per_destination", 4),
        "touches_per_job": vols.get("touches_per_job", 10),
    }


def _audiences(spark, catalog, marketing_schema):
    """Load audience list with surrogate key and deterministic index."""
    a = spark.table(f"{catalog}.{marketing_schema}.audience")
    a = a.select(F.col("audience_sk"), F.col("audience_id"))
    a = a.withColumn("_a_idx", F.row_number().over(Window.orderBy("audience_sk")) - F.lit(1))
    return a, a.count()


def _promotions(spark, catalog, marketing_schema):
    """Load promotion list with deterministic index."""
    p = spark.table(f"{catalog}.{marketing_schema}.promotion")
    p = p.select(F.col("promo_sk"), F.col("promo_id"))
    p = p.withColumn("_pr_idx", F.row_number().over(Window.orderBy("promo_sk")) - F.lit(1))
    return p, p.count()


def _profiles(spark, catalog, customer_schema, cap=5000):
    """A bounded, deterministic sample of current profiles with a dense index. The cap keeps
    the index window small at any customer-base size (touches need only a few hundred)."""
    prof = spark.table(f"{catalog}.{customer_schema}.profile").filter("is_current = TRUE")
    prof = prof.select(F.col("profile_sk"), F.col("profile_id")).orderBy("profile_sk").limit(cap)
    prof = prof.withColumn("_p_idx", F.row_number().over(Window.orderBy("profile_sk")) - F.lit(1))
    return prof, prof.count()


def generate_destinations(spark, catalog, schema, cfg, now):
    """Generate activation_destination reference table (static lookup, Type 1)."""
    dest_conn_kinds = F.array(*[F.lit(k) for k in CONNECTOR_KINDS])
    prof_purpose = F.array(*[F.lit(p) for p, _, _ in DESTINATION_PROFILES])
    prof_channel = F.array(*[F.lit(c).cast("string") for _, c, _ in DESTINATION_PROFILES])
    prof_match_key = F.array(*[F.lit(m) for _, _, m in DESTINATION_PROFILES])
    dest_regions = F.array(*[F.lit(r) for r in REGIONS])
    # 1-based position in DESTINATION_PROFILES, cycling by destination index
    pick = (F.col("id") % F.lit(len(DESTINATION_PROFILES))).cast("int") + F.lit(1)

    dest = spark.range(cfg["destinations"]).withColumn(
        "activation_destination_id",
        F.concat(F.lit("dest_"), F.format_string("%02d", F.col("id") + F.lit(1))))
    dest = (dest
            .withColumn("destination_name",
                       F.concat(F.lit("Destination "), F.col("id") + F.lit(1)))
            .withColumn("destination_platform",
                       _pick(["dsp", "esp", "crm", "cdn"], cfg["seed"], "plat", F.col("activation_destination_id")))
            .withColumn("connector_kind",
                       F.element_at(dest_conn_kinds, (F.abs(F.hash(F.col("activation_destination_id"), F.lit(cfg["seed"]))) % F.lit(len(CONNECTOR_KINDS))).cast("int") + F.lit(1)))
            .withColumn("match_key_type", F.element_at(prof_match_key, pick))
            .withColumn("required_consent_purpose", F.element_at(prof_purpose, pick))
            .withColumn("required_channel", F.element_at(prof_channel, pick))
            .withColumn("data_residency_region",
                       F.element_at(dest_regions, (F.abs(F.hash(F.col("activation_destination_id"), F.lit(cfg["seed"] + 4))) % F.lit(len(REGIONS))).cast("int") + F.lit(1)))
            .withColumn("is_addressable_flag", F.lit(True))
            .withColumn("owner_team", F.lit("marketing_ops"))
            .withColumn("created_timestamp", F.lit("2025-01-01 00:00:00").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.lit("2025-01-01 00:00:00").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", now)
            .drop("id"))

    fqtn = f"{catalog}.{schema}.activation_destination"
    return _write(spark, dest, fqtn, ACTIVATION_DESTINATION_COLUMNS, "overwrite")


def generate_jobs(spark, catalog, schema, customer_schema, marketing_schema, dest_df, cfg, now):
    """Generate activation_job fact table (append-only).

    Purpose/channel codes are pulled from destination requirements to satisfy
    aj_destination_purpose_channel_match DQ check.
    """
    audiences, n_aud = _audiences(spark, catalog, marketing_schema)
    dest_with_idx = dest_df.withColumn("_d_idx", F.row_number().over(Window.orderBy("activation_destination_id")) - F.lit(1))

    # jobs_per_destination runs per destination, cycling through the destinations
    jobs_base = spark.range(cfg["destinations"] * cfg["jobs_per_destination"]).withColumn(
        "_d_id", (F.col("id") % F.lit(cfg["destinations"])).cast("int"))
    jobs_base = jobs_base.join(
        F.broadcast(dest_with_idx),
        jobs_base["_d_id"] == dest_with_idx["_d_idx"],
        "inner")

    # Select audiences for jobs
    jobs_base = jobs_base.withColumn("_a_idx", (F.abs(F.hash(F.col("id"), F.lit(cfg["seed"]))) % F.lit(max(1, n_aud))).cast("int"))
    jobs_base = jobs_base.join(F.broadcast(audiences), jobs_base["_a_idx"] == audiences["_a_idx"], "left")

    # Generate job details
    statuses = F.array(*[F.lit(s) for s in JOB_STATUSES])
    sync_modes_arr = F.array(*[F.lit(m) for m in SYNC_MODES])

    jobs_base = jobs_base.withColumn(
        "activation_job_id",
        F.concat(F.col("audience_id"), F.lit("|"), F.col("activation_destination_id"),
                 F.lit("|"), F.format_string("%04d", F.col("id") + F.lit(1))))

    # Each run publishes the audience membership as of its run date, at 06:00-17:00 that
    # day, so job_run_date is always the date of job_run_ts.
    jobs = (jobs_base
            .withColumn("membership_as_of_date",
                       F.date_add(F.lit("2025-06-01").cast("date"), (F.col("id") % F.lit(30)).cast("int")))
            .withColumn("job_run_ts",
                       F.to_timestamp(F.col("membership_as_of_date"))
                       + F.expr("INTERVAL '1' HOUR") * (F.lit(6) + F.col("id") % F.lit(12)).cast("int"))
            .withColumn("job_run_date", F.to_date(F.col("job_run_ts")))
            .withColumn("job_status",
                       F.element_at(statuses, (F.abs(F.hash(F.col("id"), F.lit(cfg["seed"] + 5))) % F.lit(len(JOB_STATUSES))).cast("int") + F.lit(1)))
            # Purpose and channel MUST match destination requirements (aj_destination_purpose_channel_match)
            .withColumn("purpose_code", F.col("required_consent_purpose"))
            .withColumn("channel_code", F.col("required_channel"))
            .withColumn("jurisdiction_code",
                       F.element_at(F.array(*[F.lit(j) for j in JURISDICTIONS]),
                                    (F.col("id") % F.lit(len(JURISDICTIONS))).cast("int") + F.lit(1)))
            # Member counts: satisfy exported <= eligible <= requested, blocked = requested - eligible
            # Requested members stay within the synthetic customer base (100-899 of ~1,000
            # profiles); 40-80% pass the gate and 85-95% of those export, so the CDP
            # metric views show plausible export and block rates.
            .withColumn("_base_requested", ((F.abs(F.hash(F.col("id"), F.lit(cfg["seed"] + 8))) % F.lit(800)) + F.lit(100)).cast("long"))
            .withColumn("_eligible_pct", F.lit(0.40) + (F.abs(F.hash(F.col("id"), F.lit(cfg["seed"] + 9))) % F.lit(41)) / F.lit(100.0))
            .withColumn("eligible_member_count",
                       (F.col("_base_requested") * F.col("_eligible_pct")).cast("long"))
            .withColumn("blocked_member_count",
                       F.col("_base_requested") - F.col("eligible_member_count"))
            .withColumn("requested_member_count", F.col("_base_requested"))
            .withColumn("_export_pct", F.lit(0.85) + (F.abs(F.hash(F.col("id"), F.lit(cfg["seed"] + 10))) % F.lit(11)) / F.lit(100.0))
            .withColumn("exported_member_count",
                       (F.col("eligible_member_count") * F.col("_export_pct")).cast("long"))
            .withColumn("match_rate", F.lit(0.85).cast("decimal(5,4)"))
            .withColumn("sync_mode",
                       F.element_at(sync_modes_arr, (F.abs(F.hash(F.col("id"), F.lit(cfg["seed"] + 11))) % F.lit(len(SYNC_MODES))).cast("int") + F.lit(1)))
            .withColumn("removed_member_count", F.lit(None).cast("long"))
            .withColumn("delivered_member_count",
                       (F.col("exported_member_count") * F.lit(0.95)).cast("long"))
            .withColumn("rejected_member_count",
                       F.col("exported_member_count") - F.col("delivered_member_count"))
            .withColumn("job_started_ts", F.col("job_run_ts"))
            .withColumn("job_completed_ts",
                       F.col("job_run_ts") + F.expr("INTERVAL '1' SECOND") * ((F.abs(F.hash(F.col("id"), F.lit(cfg["seed"] + 12))) % F.lit(300)) + F.lit(10)).cast("long"))
            .withColumn("is_consent_enforced_flag", F.lit(True))
            .withColumn("is_suppression_applied_flag", F.lit(True))
            .withColumn("destination_audience_ref",
                       F.concat(F.lit("aud_"), F.format_string("%08d", F.col("id") + F.lit(1))))
            .withColumn("failure_reason_code", F.lit("none"))
            .withColumn("model_version", F.lit("1.0"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", now)
            .drop("id", "_d_id", "_a_idx", "_d_idx", "_base_requested", "_eligible_pct",
                  "_export_pct"))

    fqtn = f"{catalog}.{schema}.activation_job"
    return _write(spark, jobs, fqtn, ACTIVATION_JOB_COLUMNS, "overwrite")


def generate_touches(spark, catalog, schema, customer_schema, marketing_schema, jobs_df, cfg, now):
    """Generate campaign_touch fact table (append-only)."""
    profiles, n_prof = _profiles(spark, catalog, customer_schema)
    promotions, n_promo = _promotions(spark, catalog, marketing_schema)

    # Campaign touches are contacts over an owned channel, so only runs with a channel
    # (the marketing destinations) produce them; a touch inherits its run's channel.
    jobs_df = jobs_df.filter(F.col("channel_code").isNotNull())
    jobs_with_idx = jobs_df.withColumn("_j_idx", F.row_number().over(Window.orderBy("activation_job_id")) - F.lit(1))

    # Generate touches
    n_jobs = jobs_df.count()
    touches_base = spark.range(n_jobs * cfg["touches_per_job"]).withColumn(
        "_j_id", (F.col("id") % F.lit(max(1, n_jobs))).cast("int"))
    touches_base = touches_base.join(
        F.broadcast(jobs_with_idx.select("_j_idx", "activation_job_sk", "activation_job_id",
                                         "audience_sk", "audience_id", "exported_member_count",
                                         "job_completed_ts", "channel_code")),
        touches_base["_j_id"] == jobs_with_idx["_j_idx"],
        "left")

    # Select profiles, promotions
    touches_base = touches_base.withColumn("_p_idx", (F.abs(F.hash(F.col("id"), F.lit(cfg["seed"] + 13))) % F.lit(max(1, n_prof))).cast("int"))
    touches_base = touches_base.join(F.broadcast(profiles), touches_base["_p_idx"] == profiles["_p_idx"], "left")

    touches_base = touches_base.withColumn("_pr_idx", (F.abs(F.hash(F.col("id"), F.lit(cfg["seed"] + 14))) % F.lit(max(1, n_promo))).cast("int"))
    touches_base = touches_base.join(F.broadcast(promotions), touches_base["_pr_idx"] == promotions["_pr_idx"], "left")

    touches_types = F.array(*[F.lit(t) for t in TOUCH_TYPES])

    touches = (touches_base
               .withColumn("campaign_touch_id",
                          F.concat(F.col("activation_job_id"), F.lit("|"), F.format_string("%04d", F.col("id") + F.lit(1))))
               .withColumn("external_campaign_id",
                          F.concat(F.lit("camp_"), F.format_string("%08d", F.col("id") + F.lit(1))))
               # A touch happens AFTER the run that produced it: 1 hour plus one minute per
               # touch after the job completed (unique per touch, so the grain guard holds).
               .withColumn("touch_ts",
                          F.col("job_completed_ts")
                          + F.expr("INTERVAL '1' MINUTE") * (F.lit(60) + F.col("id")).cast("int"))
               .withColumn("touch_date", F.to_date(F.col("touch_ts")))
               .withColumn("touch_direction", F.lit("outbound"))
               .withColumn("touch_type",
                          F.element_at(touches_types, (F.abs(F.hash(F.col("id"), F.lit(cfg["seed"] + 15))) % F.lit(len(TOUCH_TYPES))).cast("int") + F.lit(1)))
               # The delivery outcome fits the touch: a send is sent or suppressed, a delivery
               # is delivered, and only a delivered message can be clicked.
               .withColumn("delivery_status_code",
                          F.when(F.col("touch_type") == "send",
                                 F.when((F.abs(F.hash(F.col("id"), F.lit(cfg["seed"] + 16))) % F.lit(10)) == 0,
                                        F.lit("suppressed")).otherwise(F.lit("sent")))
                           .otherwise(F.lit("delivered")))
               .withColumn("destination_delivery_status",
                          F.concat(F.lit("provider_status_"), F.format_string("%02d", (F.abs(F.hash(F.col("id"), F.lit(cfg["seed"] + 17))) % F.lit(10)).cast("int"))))
               .withColumn("consent_status", F.lit(CONSENT_STATUSES[0]))
               .withColumn("message_ref",
                          F.concat(F.lit("msg_"), F.format_string("%08d", F.col("id") + F.lit(1))))
               .withColumn("record_source", F.lit(RECORD_SOURCE))
               .withColumn("load_timestamp", now)
               .drop("id", "_j_id", "_p_idx", "_pr_idx", "_j_idx", "exported_member_count",
                     "job_completed_ts"))

    fqtn = f"{catalog}.{schema}.campaign_touch"
    return _write(spark, touches, fqtn, CAMPAIGN_TOUCH_COLUMNS, "overwrite")


# ============================================================
# Entry point
# ============================================================

def run(ctx):
    spark, catalog = ctx.spark, ctx.catalog
    cfg = load_config()
    now = F.current_timestamp()

    ucv_schema = ctx.schemas["ucv"]
    customer_schema = ctx.schemas["customer"]
    marketing_schema = ctx.schemas["marketing"]

    # Each step reads the table the previous one WROTE, not the DataFrame it built: Delta
    # assigns the IDENTITY surrogates (activation_destination_sk, activation_job_sk) on
    # write, and the next table carries them as its FKs.
    generate_destinations(spark, catalog, ucv_schema, cfg, now)
    dest_df = spark.table(f"{catalog}.{ucv_schema}.activation_destination")
    generate_jobs(spark, catalog, ucv_schema, customer_schema, marketing_schema, dest_df, cfg, now)
    jobs_df = spark.table(f"{catalog}.{ucv_schema}.activation_job")
    generate_touches(spark, catalog, ucv_schema, customer_schema, marketing_schema,
                     jobs_df, cfg, now)

    print("Unified Customer View (CDP activation layer) generation complete.")


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
