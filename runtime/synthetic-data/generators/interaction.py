# ============================================================
# ORDM · Synthetic data · Interaction generator
# Version: 0.5
# Generated: 2026-07-27
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-07-27
# ============================================================
# Populates the canonical-core interaction domain: touchpoint (the conformed
# omnichannel customer-interaction fact). Anonymous-first digital sessions —
# each session explodes into a short sessionized sequence — plus a slice of
# offline touches; a deterministic fraction of sessions is stitched to an
# existing customer.profile (the rest stay anonymous, profile_id NULL) so the
# anonymous->known path is exercised. Requires the customer, product and store
# generators to have run. Volumes come from runtime/synthetic-data/seeds.yaml.
# ============================================================

import os
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window

try:
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _pick, _frac, _write)
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _pick, _frac, _write)

# ------------------------------------------------------------
# Column contract -- MUST match the DDL (minus the IDENTITY touchpoint_sk).
# ------------------------------------------------------------
TOUCHPOINT_COLUMNS = [
    "touchpoint_id", "device_id_hash", "session_id",
    "identity_link_sk", "identity_link_id", "profile_sk", "profile_id",
    "interaction_type", "channel_code", "source_application", "touch_origin",
    "event_timestamp", "event_date", "ingest_timestamp", "latency_seconds",
    "product_sk", "product_id", "store_sk", "store_id",
    "page_type", "page_url", "referrer_url", "search_term_text", "dwell_seconds",
    "cart_id", "order_id", "event_value_amount", "currency_code",
    "consent_status", "record_source", "load_timestamp",
]

# Digital sessionized sequence: index i within a session maps to a verb + page_type.
# Covers all 11 declared digital interaction_type enum values (m1) so the fact's coverage
# is self-demonstrating: session_start opens, browse/search/cart verbs in the middle,
# checkout_start + session_end close. Longer sessions reach later verbs.
DIGITAL_SEQ = ["session_start", "app_open", "page_view", "product_view", "search",
               "wishlist_add", "add_to_cart", "cart_view", "remove_from_cart",
               "checkout_start", "session_end"]
DIGITAL_PAGE = {"session_start": "home", "app_open": "home", "page_view": "home",
                "product_view": "product", "search": "search", "wishlist_add": "product",
                "add_to_cart": "cart", "cart_view": "cart", "remove_from_cart": "cart",
                "checkout_start": "checkout", "session_end": "home"}
DIGITAL_CHANNELS = ["web", "web", "mobile_app"]  # weighted toward web
OFFLINE = [("store_visit", "in_store"), ("call_center_contact", "call_center"),
           ("kiosk_session", "kiosk"), ("offline_marketing_response", "direct_mail"),
           ("phone_activation", "call_center")]
CONSENT_STATUS = ["granted", "granted", "granted", "unknown", "denied"]


def load_config():
    c = load_domain_config("interaction")
    vols = c.get("volumes", {}) or {}
    fan = c.get("fanout", {}) or {}
    return {
        "seed": c.get("seed", 12012),
        "sessions": vols.get("sessions", 400),
        "events_per_session_max": vols.get("events_per_session_max", 11),
        "offline_touches": vols.get("offline_touches", 120),
        "resolved_session_pct": fan.get("resolved_session_pct", 0.6),
    }


def _profiles(spark, catalog, customer_schema):
    """Resolvable actors for the anonymous->known stitch: one current, ACTIVE
    identity_link per profile, carrying the link assertion keys (identity_link_sk/_id)
    alongside the resolved profile keys. A resolved touch is stitched *via* this link, so
    the fk_touchpoint_identity_link FK + its DQ checks get real sample coverage. Falls back
    to bare profiles if identity_link is unpopulated (keeps the generator robust)."""
    il = (spark.table(f"{catalog}.{customer_schema}.identity_link")
          .filter("is_current = TRUE AND link_status = 'active'")
          .select(F.col("identity_link_sk").alias("_il_sk"), F.col("identity_link_id").alias("_il_id"),
                  F.col("profile_sk").alias("_p_sk"), F.col("profile_id").alias("_p_id")))
    # one link per profile (deterministic: lowest identity_link_sk)
    il = (il.withColumn("_rn", F.row_number().over(Window.partitionBy("_p_id").orderBy("_il_sk")))
          .filter("_rn = 1").drop("_rn"))
    if il.count() == 0:
        p = (spark.table(f"{catalog}.{customer_schema}.profile").filter("is_current = TRUE")
             .select(F.lit(None).cast("bigint").alias("_il_sk"), F.lit(None).cast("string").alias("_il_id"),
                     F.col("profile_sk").alias("_p_sk"), F.col("profile_id").alias("_p_id")))
        il = p
    il = il.withColumn("_p_idx", F.row_number().over(Window.orderBy("_p_sk")) - F.lit(1))
    return il, il.count()


def _products(spark, catalog, product_schema):
    p = (spark.table(f"{catalog}.{product_schema}.product").filter("is_current = TRUE")
         .select(F.col("product_sk").alias("_pr_sk"), F.col("product_id").alias("_pr_id")))
    p = p.withColumn("_pr_idx", F.row_number().over(Window.orderBy("_pr_sk")) - F.lit(1))
    return p, p.count()


def _stores(spark, catalog, store_schema):
    s = (spark.table(f"{catalog}.{store_schema}.store").filter("is_current = TRUE")
         .select(F.col("store_sk").alias("_st_sk"), F.col("store_id").alias("_st_id")))
    s = s.withColumn("_st_idx", F.row_number().over(Window.orderBy("_st_sk")) - F.lit(1))
    return s, s.count()


def generate_touchpoints(spark, catalog, schema, customer_schema, product_schema, store_schema, calendar_schema, cfg, mode):
    seed = cfg["seed"]
    now = F.current_timestamp()
    prof, n_prof = _profiles(spark, catalog, customer_schema)
    prod, n_prod = _products(spark, catalog, product_schema)
    stores, n_store = _stores(spark, catalog, store_schema)
    # Calendar window: event_date MUST land on a fiscal_calendar.date_key (natural date key;
    # touchpoint_calendar_coverage enforces it), so draw dates from the actual calendar span
    # rather than relative to now (which would fall outside the seeded 2024-based window).
    cal = spark.table(f"{catalog}.{calendar_schema}.fiscal_calendar").select("date_key")
    cal_row = cal.agg(F.min("date_key").alias("lo"), F.max("date_key").alias("hi")).first()
    cal_lo, cal_span = cal_row["lo"], max(1, (cal_row["hi"] - cal_row["lo"]).days)

    # ---- 1. Digital: sessions exploded into sessionized sequences ----
    sess = spark.range(cfg["sessions"]).withColumn(
        "session_id", F.concat(F.lit("SES-"), F.format_string("%06d", F.col("id") + F.lit(1))))
    # Per-session length in 1..events_per_session_max (deterministic), then explode by position.
    sess = sess.withColumn(
        "_len", (F.abs(F.hash(F.col("session_id"), F.lit(seed))) % F.lit(cfg["events_per_session_max"])).cast("int") + F.lit(1))
    sess = sess.withColumn("_pos", F.explode(F.sequence(F.lit(0), F.col("_len") - F.lit(1))))

    # The sequence verb for this position (capped at the sequence length).
    seq_arr = F.array(*[F.lit(v) for v in DIGITAL_SEQ])
    seq_n = F.lit(len(DIGITAL_SEQ))
    dig = (sess
           .withColumn("interaction_type", F.element_at(seq_arr, F.least(F.col("_pos"), seq_n - F.lit(1)) + F.lit(1)))
           .withColumn("touchpoint_id", F.concat(F.col("session_id"), F.lit("|"), F.col("_pos")))
           .withColumn("device_id_hash",
                       F.sha2(F.concat(F.lit("dev|"), F.col("session_id"), F.lit(seed)), 256))
           .withColumn("channel_code", _pick(DIGITAL_CHANNELS, seed, "chan", F.col("session_id")))
           # source_application: the specific app/property that pairs with channel_code (the
           # medium). web -> web_desktop/web_mobile, mobile_app -> ios_app/android_app; a
           # deterministic per-session split so the enum's digital values are all exercised.
           .withColumn("source_application",
                       F.when(F.col("channel_code") == "mobile_app",
                              F.when(_frac(seed, "srcapp", F.col("session_id")) < F.lit(0.5), F.lit("ios_app")).otherwise(F.lit("android_app")))
                        .otherwise(
                              F.when(_frac(seed, "srcapp", F.col("session_id")) < F.lit(0.7), F.lit("web_desktop")).otherwise(F.lit("web_mobile"))))
           .withColumn("touch_origin", F.lit("inbound"))
           .withColumn("page_type",
                       F.element_at(F.create_map(*sum([[F.lit(k), F.lit(v)] for k, v in DIGITAL_PAGE.items()], [])),
                                    F.col("interaction_type")))
           .withColumn("store_sk", F.lit(None).cast("bigint")).withColumn("store_id", F.lit(None).cast("string")))

    # Product context for product_view / cart verbs; NULL otherwise.
    dig = dig.withColumn("_pr_idx", (F.abs(F.hash(F.col("touchpoint_id"), F.lit(seed + 1))) % F.lit(max(1, n_prod))).cast("int"))
    dig = dig.join(F.broadcast(prod), dig["_pr_idx"] == prod["_pr_idx"], "left").drop("_pr_idx")
    needs_prod = F.col("interaction_type").isin("product_view", "add_to_cart", "remove_from_cart", "cart_view")
    dig = (dig
           .withColumn("product_sk", F.when(needs_prod, F.col("_pr_sk")))
           .withColumn("product_id", F.when(needs_prod, F.col("_pr_id")))
           .withColumn("page_url",
                       F.concat(F.lit("/"), F.col("page_type"),
                                F.when(needs_prod, F.concat(F.lit("/"), F.col("_pr_id"))).otherwise(F.lit(""))))
           .withColumn("referrer_url", F.lit("/"))
           .withColumn("search_term_text",
                       F.when(F.col("interaction_type") == "search",
                              _pick(["shoes", "coffee", "jacket", "tv", "snacks", "gift card"], seed, "q", F.col("touchpoint_id"))))
           .withColumn("cart_id",
                       F.when(F.col("interaction_type").isin("add_to_cart", "remove_from_cart", "cart_view", "checkout_start"),
                              F.concat(F.lit("CART-"), F.col("session_id"))))
           .withColumn("order_id",
                       F.when(F.col("interaction_type") == "checkout_start",
                              F.concat(F.lit("ORD-"), F.col("session_id"))))
           .withColumn("event_value_amount",
                       F.when(F.col("interaction_type").isin("cart_view", "checkout_start"),
                              F.round((F.abs(F.hash(F.col("session_id"), F.lit(seed + 2))) % F.lit(20000)).cast("decimal(18,2)") / F.lit(100.0), 2)))
           .drop("_pr_sk", "_pr_id", "_pr_idx"))

    # Anonymous->known stitch: a deterministic fraction of SESSIONS resolves to a profile.
    dig = dig.withColumn("_resolved",
                         _frac(seed, "resolve", F.col("session_id")) < F.lit(float(cfg["resolved_session_pct"])))
    dig = dig.withColumn("_p_idx", (F.abs(F.hash(F.col("session_id"), F.lit(seed + 3))) % F.lit(max(1, n_prof))).cast("int"))
    dig = dig.join(F.broadcast(prof), dig["_p_idx"] == prof["_p_idx"], "left").drop("_p_idx")
    dig = (dig
           .withColumn("profile_sk", F.when(F.col("_resolved"), F.col("_p_sk")))
           .withColumn("profile_id", F.when(F.col("_resolved"), F.col("_p_id")))
           # A resolved touch is stitched VIA the identity_link assertion (real FK coverage);
           # anonymous touches leave both the link and the profile NULL.
           .withColumn("identity_link_sk", F.when(F.col("_resolved"), F.col("_il_sk")))
           .withColumn("identity_link_id", F.when(F.col("_resolved"), F.col("_il_id")))
           .drop("_p_sk", "_p_id", "_il_sk", "_il_id", "_resolved", "_len", "_pos"))

    dig_cols = dig  # digital frame; timestamps + tails added by _finalize

    # ---- 2. Offline touches (identity-first: profile known, device NULL) ----
    off = spark.range(cfg["offline_touches"]).withColumn(
        "touchpoint_id", F.concat(F.lit("OFF-"), F.format_string("%06d", F.col("id") + F.lit(1))))
    off_type = F.array(*[F.lit(t) for t, _ in OFFLINE])
    off_chan = F.create_map(*sum([[F.lit(t), F.lit(c)] for t, c in OFFLINE], []))
    off = (off
           .withColumn("interaction_type",
                       F.element_at(off_type, (F.abs(F.hash(F.col("touchpoint_id"), F.lit(seed + 4))) % F.lit(len(OFFLINE))).cast("int") + F.lit(1)))
           .withColumn("channel_code", F.element_at(off_chan, F.col("interaction_type")))
           # source_application pairs with the offline medium: in_store -> in_store_pos,
           # kiosk -> loyalty_kiosk, call_center -> call_center_app. direct_mail (postal) has no
           # matching source in the enum (email_platform would be wrong — postal is not email), so
           # it maps to 'other' rather than a mislabeled app (m1).
           .withColumn("source_application",
                       F.element_at(F.create_map(
                           F.lit("in_store"), F.lit("in_store_pos"),
                           F.lit("kiosk"), F.lit("loyalty_kiosk"),
                           F.lit("call_center"), F.lit("call_center_app"),
                           F.lit("direct_mail"), F.lit("other")),
                           F.col("channel_code")))
           .withColumn("touch_origin",
                       F.when(F.col("interaction_type") == "offline_marketing_response", F.lit("outbound")).otherwise(F.lit("inbound")))
           .withColumn("device_id_hash", F.lit(None).cast("string"))
           .withColumn("session_id", F.lit(None).cast("string"))
           .withColumn("page_type", F.lit(None).cast("string"))
           .withColumn("page_url", F.lit(None).cast("string"))
           .withColumn("referrer_url", F.lit(None).cast("string"))
           .withColumn("search_term_text", F.lit(None).cast("string"))
           .withColumn("cart_id", F.lit(None).cast("string"))
           .withColumn("order_id", F.lit(None).cast("string"))
           .withColumn("event_value_amount", F.lit(None).cast("decimal(18,2)"))
           .withColumn("product_sk", F.lit(None).cast("bigint")).withColumn("product_id", F.lit(None).cast("string")))
    # store context for in-store/kiosk touches
    off = off.withColumn("_st_idx", (F.abs(F.hash(F.col("touchpoint_id"), F.lit(seed + 5))) % F.lit(max(1, n_store))).cast("int"))
    off = off.join(F.broadcast(stores), off["_st_idx"] == stores["_st_idx"], "left").drop("_st_idx")
    in_store = F.col("channel_code").isin("in_store", "kiosk")
    off = (off
           .withColumn("store_sk", F.when(in_store, F.col("_st_sk")))
           .withColumn("store_id", F.when(in_store, F.col("_st_id")))
           .drop("_st_sk", "_st_id", "_st_idx"))
    # offline is identity-first: always resolved to a profile
    off = off.withColumn("_p_idx", (F.abs(F.hash(F.col("touchpoint_id"), F.lit(seed + 6))) % F.lit(max(1, n_prof))).cast("int"))
    off = off.join(F.broadcast(prof), off["_p_idx"] == prof["_p_idx"], "left").drop("_p_idx")
    off = (off
           .withColumn("profile_sk", F.col("_p_sk"))
           .withColumn("profile_id", F.col("_p_id"))
           # offline is identity-first: carry the identity_link assertion too (FK coverage).
           .withColumn("identity_link_sk", F.col("_il_sk"))
           .withColumn("identity_link_id", F.col("_il_id"))
           .drop("_p_sk", "_p_id", "_il_sk", "_il_id", "_p_idx"))

    # ---- 3. union + shared tails (timestamps, dwell, consent, currency, audit) ----
    common = ["touchpoint_id", "device_id_hash", "session_id", "identity_link_sk", "identity_link_id",
              "profile_sk", "profile_id", "interaction_type", "channel_code", "source_application", "touch_origin",
              "product_sk", "product_id", "store_sk", "store_id", "page_type", "page_url",
              "referrer_url", "search_term_text", "cart_id", "order_id", "event_value_amount"]
    both = dig_cols.select(*common).unionByName(off.select(*common))

    both = (both
            # event_date is a hashed offset within the fiscal-calendar span, so every touch
            # lands on a real date_key (touchpoint_calendar_coverage passes). event_timestamp
            # is that date plus a hashed intra-day offset.
            .withColumn("event_date",
                        F.date_add(F.lit(cal_lo).cast("date"),
                                   (F.abs(F.hash(F.col("touchpoint_id"), F.lit(seed + 7))) % F.lit(cal_span)).cast("int")))
            .withColumn("event_timestamp",
                        F.col("event_date").cast("timestamp")
                        + F.expr("INTERVAL '1' SECOND") * (F.abs(F.hash(F.col("touchpoint_id"), F.lit(seed + 12))) % F.lit(86400)).cast("int"))
            .withColumn("latency_seconds", (F.abs(F.hash(F.col("touchpoint_id"), F.lit(seed + 8))) % F.lit(30) + F.lit(1)).cast("int"))
            .withColumn("ingest_timestamp",
                        F.col("event_timestamp") + F.expr("INTERVAL '1' SECOND") * F.col("latency_seconds"))
            .withColumn("dwell_seconds", (F.abs(F.hash(F.col("touchpoint_id"), F.lit(seed + 9))) % F.lit(600)).cast("int"))
            .withColumn("currency_code",
                        F.when(F.col("event_value_amount").isNotNull(), F.lit("USD")).otherwise(F.lit(None).cast("string")))
            .withColumn("consent_status", _pick(CONSENT_STATUS, seed, "consent", F.col("touchpoint_id")))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", now))

    fqtn = f"{catalog}.{schema}.touchpoint"
    return _write(spark, both, fqtn, TOUCHPOINT_COLUMNS, mode)


# ---- entry point ----

def run(ctx):
    spark, catalog, mode = ctx.spark, ctx.catalog, ctx.mode
    cfg = load_config()
    generate_touchpoints(
        spark, catalog, ctx.schemas["interaction"],
        ctx.schemas["customer"], ctx.schemas["product"], ctx.schemas["store"],
        ctx.schemas["calendar"], cfg, mode)
    print("Interaction (touchpoint) generation complete.")


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
