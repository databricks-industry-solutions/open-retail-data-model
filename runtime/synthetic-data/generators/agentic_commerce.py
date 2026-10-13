# ============================================================
# ORDM · Synthetic data · Agentic Commerce generator
# Version: 0.5
# Generated: 2026-07-28
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-08-02
# ============================================================
# Populates both grains of the Agentic Commerce package from conformed
# canonical-core masters (customer, product, store, inventory, order; run those
# first). Deterministic for a given seed; volumes/seed come from
# runtime/synthetic-data/seeds.yaml. Two independent slices:
#   1. Conversational shopping / intent product discovery — conversation_session,
#      assistant_turn_event, discovery_intent/result/engagement_event. Writes only
#      privacy-safe session identifiers, intent hashes, and synthetic engagement
#      signals; no raw transcript or prompt text is generated.
#   2. Agent-to-agent (A2A) transactions — a2a_agent, a2a_mandate, a2a_session,
#      a2a_negotiation_event.
# ============================================================

import os
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window

try:
    from _common import RECORD_SOURCE, _frac, _pick, attach_random_dim, get_param, load_domain_config, _write
    from _context import DeployContext
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import RECORD_SOURCE, _frac, _pick, attach_random_dim, get_param, load_domain_config, _write
    from _context import DeployContext


CONVERSATION_SESSION_COLUMNS = [
    "conversation_session_id", "profile_sk", "profile_id", "store_sk", "store_id",
    "session_id", "conversation_id", "entry_channel", "locale_code", "jurisdiction_code",
    "started_ts", "ended_ts", "started_date", "session_status", "resolution_type",
    "personalization_eligible_flag", "consent_status", "record_source", "load_timestamp",
]
ASSISTANT_TURN_EVENT_COLUMNS = [
    "assistant_turn_event_id", "conversation_session_sk", "conversation_session_id",
    "discovery_intent_event_sk", "discovery_intent_event_id", "turn_sequence_number",
    "actor_type", "turn_type", "assistant_action_type", "intent_category",
    "intent_confidence_score", "is_fallback_flag", "is_handoff_flag", "event_ts",
    "event_date", "record_source", "load_timestamp",
]
DISCOVERY_INTENT_EVENT_COLUMNS = [
    "discovery_intent_event_id", "conversation_session_sk", "conversation_session_id",
    "profile_sk", "profile_id", "store_sk", "store_id", "session_id", "conversation_id",
    "discovery_channel", "locale_code", "jurisdiction_code", "intent_text_hash",
    "intent_category", "intent_confidence_score",
    "personalization_eligible_flag", "consent_status", "event_ts", "event_date",
    "record_source", "load_timestamp",
]
DISCOVERY_RESULT_EVENT_COLUMNS = [
    "discovery_result_event_id", "discovery_intent_event_sk", "discovery_intent_event_id",
    "product_sk", "product_id", "store_sk", "store_id", "result_rank", "retrieval_score",
    "ranking_score", "personalization_score", "availability_score", "reason_code",
    "is_available_flag", "units_available", "list_price_amount", "currency_code",
    "event_ts", "event_date", "record_source", "load_timestamp",
]
DISCOVERY_ENGAGEMENT_EVENT_COLUMNS = [
    "discovery_engagement_event_id", "discovery_result_event_sk", "discovery_result_event_id",
    "discovery_intent_event_sk", "discovery_intent_event_id", "profile_sk", "profile_id",
    "product_sk", "product_id", "store_sk", "store_id", "order_line_sk", "order_line_id",
    "order_id", "engagement_type", "engagement_ts", "engagement_date", "quantity",
    "net_amount", "currency_code", "attribution_window_minutes", "record_source", "load_timestamp",
]

CHANNELS = ["web", "mobile_app", "kiosk", "store_associate", "voice", "api"]
SESSION_STATUSES = ["active", "completed", "abandoned", "escalated"]
RESOLUTION_TYPES = ["product_selected", "add_to_cart", "purchase", "handoff", "no_resolution", "abandoned"]
ACTOR_TYPES = ["shopper", "assistant", "associate", "system"]
TURN_TYPES = [
    "intent_capture", "recommendation", "product_comparison", "availability_check",
    "cart_action", "handoff", "fallback", "clarification", "other",
]
ACTION_TYPES = [
    "none", "search_products", "recommend_products", "compare_products", "check_availability",
    "add_to_cart", "handoff_to_associate", "answer_question", "clarify_intent",
]
INTENT_CATEGORIES = [
    "product_search", "need_based", "occasion", "problem_solution", "compatibility",
    "style_fit", "replenishment", "comparison", "unknown",
]
CONSENT_STATUS = ["granted", "denied", "unknown"]
REASON_CODES = [
    "lexical_match", "semantic_match", "purchase_affinity", "substitute",
    "complement", "trending", "available_nearby", "business_rule",
]


def _hash(*cols):
    return F.sha2(F.concat_ws("||", *[F.col(c) if isinstance(c, str) else c for c in cols]), 256)


def _audit(df):
    return (df.withColumn("record_source", F.lit(RECORD_SOURCE))
              .withColumn("load_timestamp", F.current_timestamp()))


def _defaults():
    cfg = load_domain_config("agentic_commerce") or {}
    volumes = cfg.get("volumes", {}) or {}
    return {
        "seed": int(cfg.get("seed", 11011)),
        "profiles": int(volumes.get("profiles", 150)),
        "sessions_per_profile": int(volumes.get("sessions_per_profile", volumes.get("intents_per_profile", 2))),
        "results_per_intent": int(volumes.get("results_per_intent", 5)),
        "turns_per_session": int(volumes.get("turns_per_session", 4)),
    }


def generate(spark, catalog, schemas, cfg, mode, base_currency="USD"):
    if not catalog:
        raise ValueError("`catalog` parameter is required (guardrail #1: no hardcoded catalog).")

    def fq(schema, table):
        return f"{catalog}.{schemas[schema]}.{table}"

    seed = cfg["seed"]
    cur = F.lit(base_currency)
    print(f"[ordm] generating agentic-commerce into {catalog} (seed={seed}, mode={mode})")

    profiles = (spark.table(fq("customer", "profile"))
                .where("is_current = true")
                .select("profile_sk", "profile_id")
                .orderBy("profile_id")
                .limit(int(cfg["profiles"])))
    stores = (spark.table(fq("store", "store"))
              .where("is_current = true")
              .select("store_sk", "store_id"))
    products = (spark.table(fq("product", "product"))
                .where("is_current = true AND product_status = 'active'")
                .select("product_sk", "product_id", "list_price", "currency_code"))
    latest_inventory = (spark.table(fq("inventory", "inventory_position"))
                        .select("product_id", "store_id", "units_on_hand_eod", "is_stockout", "date_key")
                        .withColumn("_rn", F.row_number().over(
                            Window.partitionBy("product_id", "store_id").orderBy(F.col("date_key").desc())))
                        .where("_rn = 1")
                        .drop("_rn"))
    order_lines = (spark.table(fq("order", "customer_order_line"))
                   .select("order_line_sk", "order_line_id", "order_id", "profile_id",
                           "product_id", "store_id", "net_amount", "units")
                   .withColumn("_rn", F.row_number().over(
                       Window.partitionBy("profile_id", "product_id", "store_id").orderBy("order_line_id")))
                   .where("_rn = 1")
                   .drop("_rn"))

    n_stores, n_products = stores.count(), products.count()

    sessions = (profiles
                .withColumn("k", F.explode(F.expr(f"sequence(1, {int(cfg['sessions_per_profile'])})")))
                .withColumn("conversation_session_id",
                            F.concat(F.lit("CS-"), F.col("profile_id"), F.lit("-"), F.col("k"))))
    sessions = attach_random_dim(sessions, stores, n_stores, "session-store", seed, "conversation_session_id")
    session_score = _frac(seed, "session-resolution", "conversation_session_id")
    sessions = (sessions
                .withColumn("session_id", F.concat(F.lit("S-"), F.sha2(F.col("conversation_session_id"), 256)))
                .withColumn("conversation_id", F.concat(F.lit("C-"), F.sha2(F.concat(F.col("conversation_session_id"), F.lit("-agent")), 256)))
                .withColumn("entry_channel", _pick(CHANNELS, seed, "channel", "conversation_session_id"))
                .withColumn("locale_code", _pick(["en-US", "en-GB", "fr-CA", "es-US"], seed, "locale", "conversation_session_id"))
                .withColumn("jurisdiction_code", _pick(["US", "CA", "GB"], seed, "jurisdiction", "conversation_session_id"))
                .withColumn("consent_status", _pick(CONSENT_STATUS, seed, "consent", "conversation_session_id"))
                .withColumn("personalization_eligible_flag", F.col("consent_status") == "granted")
                .withColumn("started_date", F.expr("date_add(date'2024-06-01', cast(abs(hash(conversation_session_id)) % 45 as int))"))
                .withColumn("started_ts", F.col("started_date").cast("timestamp"))
                .withColumn("duration_minutes", (F.abs(F.hash("conversation_session_id", F.lit(seed))) % F.lit(25) + F.lit(2)).cast("int"))
                .withColumn("ended_ts",
                            F.when(session_score >= 0.08,
                                   F.from_unixtime(F.unix_timestamp("started_ts") + F.col("duration_minutes") * 60).cast("timestamp"))
                             .otherwise(F.lit(None).cast("timestamp")))
                .withColumn("resolution_type",
                            F.when(session_score < 0.08, F.lit("abandoned"))
                             .when(session_score < 0.18, F.lit("handoff"))
                             .when(session_score < 0.38, F.lit("purchase"))
                             .when(session_score < 0.58, F.lit("add_to_cart"))
                             .when(session_score < 0.82, F.lit("product_selected"))
                             .otherwise(F.lit("no_resolution")))
                .withColumn("session_status",
                            F.when(F.col("resolution_type") == "abandoned", F.lit("abandoned"))
                             .when(F.col("resolution_type") == "handoff", F.lit("escalated"))
                             .when(F.col("ended_ts").isNull(), F.lit("active"))
                             .otherwise(F.lit("completed")))
                .drop("k", "duration_minutes"))
    _write(spark, _audit(sessions), fq("ac", "conversation_session"), CONVERSATION_SESSION_COLUMNS, mode)

    persisted_sessions = (spark.table(fq("ac", "conversation_session"))
                          .select("conversation_session_sk", "conversation_session_id", "profile_sk", "profile_id",
                                  "store_sk", "store_id", "session_id", "conversation_id", "entry_channel",
                                  "locale_code", "jurisdiction_code", "started_ts", "started_date",
                                  "resolution_type", "personalization_eligible_flag", "consent_status"))

    intents = (persisted_sessions
               .withColumn("discovery_intent_event_id", F.concat(F.lit("DI-"), F.col("conversation_session_id")))
               .withColumn("discovery_channel", F.col("entry_channel"))
               .withColumn("intent_category", _pick(INTENT_CATEGORIES, seed, "intent", "discovery_intent_event_id"))
               .withColumn("intent_text_hash", _hash("intent_category", "profile_id", "discovery_intent_event_id", F.lit(seed)))
               .withColumn("intent_confidence_score", F.round((F.lit(0.55) + _frac(seed, "confidence", "discovery_intent_event_id") * F.lit(0.45)).cast("double"), 4))
               .withColumn("event_date", F.col("started_date"))
               .withColumn("event_ts", F.from_unixtime(F.unix_timestamp("started_ts") + F.lit(60)).cast("timestamp"))
               .drop("entry_channel", "started_ts", "started_date", "resolution_type"))
    _write(spark, _audit(intents), fq("ac", "discovery_intent_event"), DISCOVERY_INTENT_EVENT_COLUMNS, mode)

    persisted_intents = (spark.table(fq("ac", "discovery_intent_event"))
                         .select("discovery_intent_event_sk", "discovery_intent_event_id",
                                 "conversation_session_sk", "conversation_session_id",
                                 "profile_sk", "profile_id", "store_sk", "store_id", "conversation_id",
                                 "event_ts", "event_date", "intent_category", "intent_confidence_score",
                                 "personalization_eligible_flag"))

    turns = (persisted_sessions
             .withColumn("turn_sequence_number", F.explode(F.expr(f"sequence(1, {int(cfg['turns_per_session'])})")))
             .withColumn("assistant_turn_event_id",
                         F.concat(F.lit("AT-"), F.col("conversation_session_id"), F.lit("-"), F.col("turn_sequence_number")))
             .join(persisted_intents.select("conversation_id", "discovery_intent_event_sk",
                                            "discovery_intent_event_id", "intent_category",
                                            "intent_confidence_score"),
                   "conversation_id", "left"))
    turns = (turns
             .withColumn("actor_type",
                         F.when(F.col("turn_sequence_number") == 1, F.lit("shopper"))
                          .when(F.col("turn_sequence_number") == 2, F.lit("assistant"))
                          .when(F.col("resolution_type") == "handoff", F.lit("associate"))
                          .otherwise(_pick(ACTOR_TYPES, seed, "actor", "assistant_turn_event_id")))
             .withColumn("turn_type",
                         F.when(F.col("turn_sequence_number") == 1, F.lit("intent_capture"))
                          .when(F.col("turn_sequence_number") == 2, F.lit("recommendation"))
                          .when(F.col("resolution_type") == "handoff", F.lit("handoff"))
                          .when(F.col("resolution_type").isin("add_to_cart", "purchase"), F.lit("cart_action"))
                          .otherwise(_pick(TURN_TYPES, seed, "turn", "assistant_turn_event_id")))
             .withColumn("assistant_action_type",
                         F.when(F.col("turn_type") == "intent_capture", F.lit("clarify_intent"))
                          .when(F.col("turn_type") == "recommendation", F.lit("recommend_products"))
                          .when(F.col("turn_type") == "product_comparison", F.lit("compare_products"))
                          .when(F.col("turn_type") == "availability_check", F.lit("check_availability"))
                          .when(F.col("turn_type") == "cart_action", F.lit("add_to_cart"))
                          .when(F.col("turn_type") == "handoff", F.lit("handoff_to_associate"))
                          .when(F.col("turn_type") == "fallback", F.lit("answer_question"))
                          .otherwise(F.lit("none")))
             .withColumn("is_fallback_flag", F.col("turn_type") == "fallback")
             .withColumn("is_handoff_flag", F.col("turn_type") == "handoff")
             .withColumn("event_ts", F.from_unixtime(F.unix_timestamp("started_ts") + F.col("turn_sequence_number") * 60).cast("timestamp"))
             .withColumn("event_date", F.col("event_ts").cast("date"))
             .withColumn("discovery_intent_event_sk",
                         F.when(F.col("turn_sequence_number").isin(1, 2), F.col("discovery_intent_event_sk"))
                          .otherwise(F.lit(None).cast("bigint")))
             .withColumn("discovery_intent_event_id",
                         F.when(F.col("turn_sequence_number").isin(1, 2), F.col("discovery_intent_event_id"))
                          .otherwise(F.lit(None).cast("string")))
             .withColumn("intent_category",
                         F.when(F.col("turn_sequence_number").isin(1, 2), F.col("intent_category"))
                          .otherwise(F.lit(None).cast("string")))
             .withColumn("intent_confidence_score",
                         F.when(F.col("turn_sequence_number").isin(1, 2), F.col("intent_confidence_score"))
                          .otherwise(F.lit(None).cast("double")))
             .drop("profile_sk", "profile_id", "store_sk", "store_id", "session_id",
                   "conversation_id", "entry_channel", "locale_code", "jurisdiction_code",
                   "started_ts", "started_date", "resolution_type", "personalization_eligible_flag",
                   "consent_status"))
    _write(spark, _audit(turns), fq("ac", "assistant_turn_event"), ASSISTANT_TURN_EVENT_COLUMNS, mode)

    results = (persisted_intents
               .withColumn("result_rank", F.explode(F.expr(f"sequence(1, {int(cfg['results_per_intent'])})")))
               .withColumn("discovery_result_event_id",
                           F.concat(F.lit("DR-"), F.col("discovery_intent_event_id"), F.lit("-"), F.col("result_rank"))))
    results = attach_random_dim(results, products, n_products, "result-product", seed,
                                "discovery_result_event_id", "result_rank")
    results = (results
               .join(latest_inventory, ["product_id", "store_id"], "left")
               .withColumn("retrieval_score", F.round((F.lit(0.35) + _frac(seed, "retrieval", "discovery_result_event_id") * F.lit(0.65)).cast("double"), 4))
               .withColumn("personalization_score",
                           F.when(F.col("personalization_eligible_flag"),
                                  F.round(_frac(seed, "personalization", "discovery_result_event_id").cast("double"), 4))
                            .otherwise(F.lit(0.0)))
               .withColumn("availability_score",
                           F.when((F.col("is_stockout") == False) & (F.col("units_on_hand_eod") > 0), F.lit(1.0))
                            .otherwise(F.lit(0.25)))
               .withColumn("ranking_score",
                           F.round((F.col("retrieval_score") * F.lit(0.6)
                                    + F.col("personalization_score") * F.lit(0.2)
                                    + F.col("availability_score") * F.lit(0.2)).cast("double"), 4))
               .withColumn("reason_code", _pick(REASON_CODES, seed, "reason", "discovery_result_event_id"))
               .withColumn("is_available_flag", F.coalesce((F.col("is_stockout") == False) & (F.col("units_on_hand_eod") > 0), F.lit(True)))
               .withColumn("units_available", F.coalesce(F.col("units_on_hand_eod"), F.lit(0)).cast("decimal(12,3)"))
               .withColumn("list_price_amount", F.col("list_price").cast("decimal(18,4)"))
               .withColumn("currency_code", F.coalesce(F.col("currency_code"), cur))
               .withColumn("event_ts", F.col("event_ts"))
               .withColumn("event_date", F.col("event_date"))
               .drop("list_price", "is_stockout", "units_on_hand_eod", "date_key", "personalization_eligible_flag"))
    _write(spark, _audit(results), fq("ac", "discovery_result_event"), DISCOVERY_RESULT_EVENT_COLUMNS, mode)

    persisted_results = (spark.table(fq("ac", "discovery_result_event"))
                         .select("discovery_result_event_sk", "discovery_result_event_id",
                                 "discovery_intent_event_sk", "discovery_intent_event_id",
                                 "product_sk", "product_id", "store_sk", "store_id",
                                 "event_ts", "event_date", "result_rank", "list_price_amount", "currency_code"))
    persisted_intents_for_engagement = persisted_intents.select(
        "discovery_intent_event_id", "profile_sk", "profile_id")

    engagement_base = (persisted_results
                       .where(_frac(seed, "engage", "discovery_result_event_id") < 0.85)
                       .join(persisted_intents_for_engagement, "discovery_intent_event_id", "left")
                       .withColumn("discovery_engagement_event_id",
                                   F.concat(F.lit("DE-"), F.col("discovery_result_event_id"))))
    engagement_score = _frac(seed, "engagement-type", "discovery_engagement_event_id")
    engagements = (engagement_base
                   .withColumn("engagement_type",
                               # Splits the old "view" tail into view + a ~10% dismiss band so
                               # every engagement_type enum value (incl. dismiss) is exercised by
                               # synthetic data; purchase/add_to_cart/select proportions unchanged.
                               F.when(engagement_score < 0.12, F.lit("purchase"))
                                .when(engagement_score < 0.32, F.lit("add_to_cart"))
                                .when(engagement_score < 0.72, F.lit("select"))
                                .when(engagement_score < 0.90, F.lit("view"))
                                .otherwise(F.lit("dismiss")))
                   .join(order_lines, ["profile_id", "product_id", "store_id"], "left")
                   .withColumn("quantity",
                               F.when(F.col("engagement_type").isin("add_to_cart", "purchase"),
                                      (F.abs(F.hash("discovery_engagement_event_id", F.lit(seed))) % F.lit(3) + F.lit(1)).cast("int"))
                                .otherwise(F.lit(None).cast("int")))
                   .withColumn("net_amount",
                               F.when(F.col("engagement_type") == "purchase",
                                      F.round((F.coalesce(F.col("net_amount"), F.col("list_price_amount")) * F.col("quantity")).cast("decimal(18,2)"), 2))
                                .otherwise(F.lit(None).cast("decimal(18,2)")))
                   .withColumn("currency_code",
                               F.when(F.col("engagement_type") == "purchase", F.coalesce(F.col("currency_code"), cur))
                                .otherwise(F.lit(None).cast("string")))
                   .withColumn("attribution_window_minutes",
                               (F.abs(F.hash("discovery_engagement_event_id", F.lit(seed))) % F.lit(90)).cast("int"))
                   .withColumn("engagement_ts",
                               F.from_unixtime(F.unix_timestamp("event_ts") + F.col("attribution_window_minutes") * 60).cast("timestamp"))
                   .withColumn("engagement_date", F.col("engagement_ts").cast("date"))
                   .drop("event_ts", "event_date", "result_rank", "list_price_amount"))
    _write(spark, _audit(engagements), fq("ac", "discovery_engagement_event"),
           DISCOVERY_ENGAGEMENT_EVENT_COLUMNS, mode)


# ============================================================
# Agent-to-Agent (A2A) transactions slice
# ------------------------------------------------------------
# Column contracts -- MUST match the DDL (minus IDENTITY *_sk).
# ============================================================
A2A_AGENT_COLUMNS = [
    "a2a_agent_id", "agent_name", "agent_role", "operator_name",
    "represented_profile_id", "represented_store_id",
    "protocol_version", "trust_status", "is_autonomous",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
A2A_MANDATE_COLUMNS = [
    "a2a_mandate_id", "buyer_profile_sk", "buyer_profile_id",
    "a2a_agent_sk", "a2a_agent_id", "consent_id",
    "spend_ceiling_amount", "per_transaction_limit_amount", "currency_code",
    "approval_threshold_amount", "allowed_categories", "mandate_status",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
A2A_SESSION_COLUMNS = [
    "a2a_session_id", "buyer_profile_sk", "buyer_profile_id",
    "store_sk", "store_id", "product_sk", "product_id",
    "initiating_agent_sk", "initiating_agent_id", "responding_agent_sk", "responding_agent_id",
    "session_status", "communication_channel", "initiator_type", "session_summary",
    "initiated_timestamp", "last_activity_timestamp", "completed_timestamp",
    "record_source", "source_updated_timestamp", "load_timestamp",
]
A2A_NEGOTIATION_EVENT_COLUMNS = [
    "a2a_negotiation_event_id", "a2a_session_sk", "a2a_session_id",
    "a2a_agent_sk", "a2a_agent_id", "product_sk", "product_id",
    "event_type", "event_sequence",
    "proposed_price", "currency_code", "proposed_quantity",
    "event_timestamp", "ingest_timestamp", "latency_seconds",
    "record_source", "load_timestamp",
]

OPERATORS = ["acme-agents", "shopbot-labs", "retail-ai-coop", "vendor-agent-net"]
A2A_CHANNELS = ["api", "marketplace", "direct", "voice"]
TRUST = ["verified", "verified", "verified", "unverified", "suspended"]  # weighted toward verified
CATEGORIES = ["electronics", "home", "grocery", "apparel", "toys"]
# Terminal + active session statuses, weighted (most sessions complete or abandon).
A2A_SESSION_STATUSES = ["completed", "completed", "agreed", "negotiating", "abandoned", "failed", "expired"]


def load_config():
    c = load_domain_config("agentic_commerce")
    vols = c.get("volumes", {}) or {}
    return {
        "seed": c.get("seed", 13013),
        "agents": vols.get("agents", 40),
        "mandates": vols.get("mandates", 30),
        "sessions": vols.get("sessions", 200),
        "events_max": vols.get("events_per_session_max", 6),
    }


def generate_agents(spark, catalog, schema, cfg, mode, profile_df, store_df):
    """Buyer agents represent a profile; seller agents represent a store. SCD2 current rows."""
    seed, n = cfg["seed"], cfg["agents"]
    today = F.current_date()
    now = F.current_timestamp()

    # Small conformed dimensions -> broadcast-joined one-per-row via attach_random_dim
    # (scales with the fact table; no driver-side collect or per-row array literal).
    prof_dim = profile_df.select(F.col("profile_id").alias("_rep_profile_id"))
    store_dim = store_df.select(F.col("store_id").alias("_rep_store_id"))
    prof_count, store_count = prof_dim.count(), store_dim.count()

    ids = spark.range(n).withColumn(
        "a2a_agent_id", F.concat(F.lit("AGT-"), F.format_string("%05d", F.col("id") + F.lit(1))))

    df = attach_random_dim(ids, prof_dim, prof_count, "prof", seed, F.col("a2a_agent_id"))
    df = attach_random_dim(df, store_dim, store_count, "store", seed, F.col("a2a_agent_id"))

    df = (df
          .withColumn("agent_role",
                      F.when(_frac(seed, "role", F.col("a2a_agent_id")) < F.lit(0.5), F.lit("buyer_agent"))
                       .otherwise(F.lit("seller_agent")))
          .withColumn("agent_name",
                      F.concat(F.initcap(F.regexp_replace(_pick(OPERATORS, seed, "op", F.col("a2a_agent_id")), "-", " ")),
                               F.lit(" Agent "), F.format_string("%05d", F.col("id") + F.lit(1))))
          .withColumn("operator_name", _pick(OPERATORS, seed, "op", F.col("a2a_agent_id")))
          .withColumn("represented_profile_id",
                      F.when(F.col("agent_role") == "buyer_agent", F.col("_rep_profile_id"))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("represented_store_id",
                      F.when(F.col("agent_role") == "seller_agent", F.col("_rep_store_id"))
                       .otherwise(F.lit(None).cast("string")))
          .withColumn("protocol_version",
                      _pick(["1.0", "1.1", "2.0"], seed, "proto", F.col("a2a_agent_id")))
          .withColumn("trust_status", _pick(TRUST, seed, "trust", F.col("a2a_agent_id")))
          .withColumn("is_autonomous", _frac(seed, "auto", F.col("a2a_agent_id")) < F.lit(0.7))
          .withColumn("effective_from_date", F.date_sub(today, 180))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("id", "_rep_profile_id", "_rep_store_id"))

    fqtn = f"{catalog}.{schema}.a2a_agent"
    return _write(spark, df, fqtn, A2A_AGENT_COLUMNS, mode)


def generate_mandates(spark, catalog, schema, cfg, mode, profile_df, agent_df):
    """One mandate per (buyer agent, its represented profile). SCD2 current rows."""
    seed, n = cfg["seed"], cfg["mandates"]
    today = F.current_date()
    now = F.current_timestamp()

    prof = profile_df.select("profile_sk", "profile_id").withColumn("is_current_flag", F.lit(True))
    # Buyer agents only carry a represented_profile_id; join to the profile surrogate.
    # The row_number below is a DELIBERATE global window (no partitionBy): it takes a
    # deterministic global top-N of buyer agents to seed exactly `n` mandates. This is
    # the one bounded-collect exception to the partitioned-window rule — buyer agents
    # are capped at cfg["agents"] (tens of rows), so the single-partition sort never
    # scales with fact volume. Do NOT copy this pattern onto a fact-grain table.
    buyers = (agent_df.filter("agent_role = 'buyer_agent'")
              .select("a2a_agent_sk", "a2a_agent_id", "represented_profile_id")
              .withColumn("_rank", F.row_number().over(Window.orderBy("a2a_agent_sk")))
              .filter(F.col("_rank") <= n))

    df = (buyers
          .join(prof, buyers["represented_profile_id"] == prof["profile_id"], "left")
          .withColumn("a2a_mandate_id", F.concat(F.lit("MND-"), F.format_string("%05d", F.col("_rank"))))
          .withColumn("buyer_profile_id", F.col("represented_profile_id"))
          .withColumn("consent_id",
                      F.concat(F.lit("CNS-"), F.col("represented_profile_id")))
          .withColumn("spend_ceiling_amount",
                      (F.lit(1000) + (F.abs(F.hash(F.col("a2a_mandate_id"), F.lit(seed))) % F.lit(9000))).cast("decimal(18,2)"))
          .withColumn("per_transaction_limit_amount",
                      (F.lit(100) + (F.abs(F.hash(F.col("a2a_mandate_id"), F.lit(seed + 1))) % F.lit(900))).cast("decimal(18,2)"))
          .withColumn("currency_code", F.lit("USD"))
          .withColumn("approval_threshold_amount",
                      (F.lit(500) + (F.abs(F.hash(F.col("a2a_mandate_id"), F.lit(seed + 2))) % F.lit(1500))).cast("decimal(18,2)"))
          .withColumn("allowed_categories",
                      _pick([",".join(CATEGORIES[:2]), ",".join(CATEGORIES[:3]), ",".join(CATEGORIES)],
                            seed, "cats", F.col("a2a_mandate_id")))
          .withColumn("mandate_status",
                      F.when(_frac(seed, "mstatus", F.col("a2a_mandate_id")) < F.lit(0.85), F.lit("active"))
                       .otherwise(F.lit("suspended")))
          .withColumn("effective_from_date", F.date_sub(today, 90))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", now)
          .withColumn("source_updated_timestamp", now)
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .withColumnRenamed("profile_sk", "buyer_profile_sk")
          .drop("_rank", "represented_profile_id", "profile_id", "is_current_flag"))

    fqtn = f"{catalog}.{schema}.a2a_mandate"
    return _write(spark, df, fqtn, A2A_MANDATE_COLUMNS, mode)


def generate_sessions(spark, catalog, schema, cfg, mode, profile_df, store_df, product_df, agent_df):
    """One row per A2A session, pairing a buyer agent with a seller agent."""
    seed, n = cfg["seed"], cfg["sessions"]
    now = F.current_timestamp()

    # Conformed dimensions attached one-per-row via broadcast join (scales with the
    # fact; no driver collect / per-row array literal). Each dim aliases its columns
    # so they don't collide, then a distinct salt per role gives independent picks.
    prof_dim = profile_df.select(F.col("profile_sk").alias("buyer_profile_sk"),
                                 F.col("profile_id").alias("buyer_profile_id"))
    store_dim = store_df.select(F.col("store_sk").alias("store_sk"),
                                F.col("store_id").alias("store_id"))
    prod_dim = product_df.select(F.col("product_sk").alias("product_sk"),
                                 F.col("product_id").alias("product_id"))
    # Attach the two agents by their real side (buyer / seller). Who INITIATED is
    # a separate axis (initiator_type), assigned below — most negotiations are
    # buyer-opened, but sellers proactively open some, so both enum values are
    # exercised without changing which agent is the buyer vs the seller.
    buyer_dim = (agent_df.filter("agent_role = 'buyer_agent'")
                 .select(F.col("a2a_agent_sk").alias("buyer_agent_sk"),
                         F.col("a2a_agent_id").alias("buyer_agent_id")))
    seller_dim = (agent_df.filter("agent_role = 'seller_agent'")
                  .select(F.col("a2a_agent_sk").alias("seller_agent_sk"),
                          F.col("a2a_agent_id").alias("seller_agent_id")))
    pc, sc, qc = prof_dim.count(), store_dim.count(), prod_dim.count()
    bc, cc = buyer_dim.count(), seller_dim.count()

    ids = spark.range(n).withColumn(
        "a2a_session_id", F.concat(F.lit("A2A-"), F.format_string("%06d", F.col("id") + F.lit(1))))
    k = F.col("a2a_session_id")

    df = attach_random_dim(ids, prof_dim, pc, "sess_prof", seed, k)
    df = attach_random_dim(df, store_dim, sc, "sess_store", seed, k)
    df = attach_random_dim(df, prod_dim, qc, "sess_prod", seed, k)
    df = attach_random_dim(df, buyer_dim, bc, "sess_buyer", seed, k)
    df = attach_random_dim(df, seller_dim, cc, "sess_seller", seed, k)

    df = (df
          .withColumn("session_status", _pick(A2A_SESSION_STATUSES, seed, "status", k))
          .withColumn("communication_channel", _pick(A2A_CHANNELS, seed, "chan", k))
          # Which side opened the session. ~75% buyer-initiated, the rest
          # seller-initiated (a seller agent proactively reaching a buyer).
          .withColumn("initiator_type",
                      F.when(_frac(seed, "init", k) < F.lit(0.75), F.lit("buyer_agent"))
                       .otherwise(F.lit("seller_agent")))
          # Map the buyer/seller agents onto the initiating/responding roles per
          # initiator_type, so initiating_agent = whoever opened it either way.
          .withColumn("initiating_agent_sk",
                      F.when(F.col("initiator_type") == "buyer_agent", F.col("buyer_agent_sk"))
                       .otherwise(F.col("seller_agent_sk")))
          .withColumn("initiating_agent_id",
                      F.when(F.col("initiator_type") == "buyer_agent", F.col("buyer_agent_id"))
                       .otherwise(F.col("seller_agent_id")))
          .withColumn("responding_agent_sk",
                      F.when(F.col("initiator_type") == "buyer_agent", F.col("seller_agent_sk"))
                       .otherwise(F.col("buyer_agent_sk")))
          .withColumn("responding_agent_id",
                      F.when(F.col("initiator_type") == "buyer_agent", F.col("seller_agent_id"))
                       .otherwise(F.col("buyer_agent_id")))
          .withColumn("session_summary",
                      F.concat(F.lit("A2A negotiation for "), F.col("product_id"),
                               F.lit(" ("), F.col("session_status"), F.lit(")")))
          .withColumn("initiated_timestamp",
                      F.least(now - F.expr("INTERVAL '1' HOUR") * (F.abs(F.hash(k, F.lit(seed + 5))) % F.lit(720) + F.lit(1)).cast("int"), now))
          # Terminal statuses get a completed_timestamp; active ones stay NULL.
          .withColumn("_is_terminal", F.col("session_status").isin("completed", "abandoned", "failed", "expired"))
          .withColumn("completed_timestamp",
                      F.when(F.col("_is_terminal"),
                             F.least(F.col("initiated_timestamp") + F.expr("INTERVAL '1' MINUTE") * (F.abs(F.hash(k, F.lit(seed + 6))) % F.lit(120) + F.lit(1)).cast("int"), now))
                       .otherwise(F.lit(None).cast("timestamp")))
          .withColumn("last_activity_timestamp",
                      F.coalesce(F.col("completed_timestamp"),
                                 F.least(F.col("initiated_timestamp") + F.expr("INTERVAL '1' MINUTE") * (F.abs(F.hash(k, F.lit(seed + 7))) % F.lit(30) + F.lit(1)).cast("int"), now)))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("source_updated_timestamp", F.col("last_activity_timestamp"))
          .withColumn("load_timestamp", now)
          .drop("id", "_is_terminal"))

    fqtn = f"{catalog}.{schema}.a2a_session"
    return _write(spark, df, fqtn, A2A_SESSION_COLUMNS, mode)


def generate_events(spark, catalog, schema, cfg, mode, session_df):
    """Per session, emit a negotiation event sequence. Deterministic.
    Most sessions run a short offer/counter/acceptance (or offer/rejection) path;
    a deterministic ~20% run the full protocol adding price_request,
    availability_check, and escalation_to_human, so all seven event_type values
    appear and the human-escalation KPI is exercised. A completed/agreed session
    ends in exactly one acceptance (asserted in checks).
    """
    seed = cfg["seed"]
    now = F.current_timestamp()

    # Build a fixed step ladder per session: offer(1), counter_offer(2), acceptance(3)
    # for sessions that reached agreement; a shorter offer/rejection for others.
    # Resolve the true buyer/seller agent from initiator_type: buyer-initiated
    # sessions have initiating=buyer, seller-initiated have initiating=seller.
    # Events are keyed on the negotiating ROLE, independent of who opened the
    # session: the SELLER emits the opening offer (its quote/ask), the BUYER
    # counters lower, and the deal settles between. This makes first_offer_price
    # the seller's opening quote, so gold's price_concession_pct — (first_offer -
    # agreed) / first_offer — reads unambiguously as how much ground the seller
    # gave from that quote (positive = discount below the opening ask).
    sess = session_df.select(
        "a2a_session_sk", "a2a_session_id", "product_sk", "product_id",
        "session_status", "initiated_timestamp",
        F.when(F.col("initiator_type") == "buyer_agent", F.col("initiating_agent_sk"))
         .otherwise(F.col("responding_agent_sk")).alias("buyer_agent_sk"),
        F.when(F.col("initiator_type") == "buyer_agent", F.col("initiating_agent_id"))
         .otherwise(F.col("responding_agent_id")).alias("buyer_agent_id"),
        F.when(F.col("initiator_type") == "buyer_agent", F.col("responding_agent_sk"))
         .otherwise(F.col("initiating_agent_sk")).alias("seller_agent_sk"),
        F.when(F.col("initiator_type") == "buyer_agent", F.col("responding_agent_id"))
         .otherwise(F.col("initiating_agent_id")).alias("seller_agent_id"))

    # A deterministic minority (~20%) of sessions run the FULL protocol — a leading
    # price_request, a mid availability_check, and a human escalation (a proposal
    # exceeded the buyer's mandate) — while the rest run the short happy path. This
    # exercises all seven event_type values (not just four) and keeps the headline
    # KPIs non-zero: escalated_to_human (gold_a2a_session_summary) and, from it,
    # human_escalation_rate (mv_negotiation_outcomes) would be identically 0 if no
    # escalation_to_human row were ever emitted.
    sess = sess.withColumn("_rich", _frac(seed, "rich", F.col("a2a_session_id")) < F.lit(0.20))

    reached = sess.filter("session_status IN ('completed','agreed')")
    other = sess.filter("session_status NOT IN ('completed','agreed')")

    # Step templates: (event_type, sequence, agent_side). Seller opens with a quote,
    # buyer counters lower, seller accepts — so first_offer_price is the seller's ask
    # and price_concession_pct reads as a downward concession. Each cohort has a plain
    # (happy-path) and a rich variant; the rich variants add the non-price protocol
    # steps but still carry exactly one 'offer' and at most one 'acceptance', so the
    # first-offer anchor and single-acceptance invariant are preserved.
    reached_plain = spark.createDataFrame(
        [("offer", 1, "seller"), ("counter_offer", 2, "buyer"), ("acceptance", 3, "seller")],
        "event_type STRING, event_sequence INT, agent_side STRING")
    reached_rich = spark.createDataFrame(
        [("price_request", 1, "buyer"), ("offer", 2, "seller"), ("availability_check", 3, "seller"),
         ("counter_offer", 4, "buyer"), ("escalation_to_human", 5, "buyer"), ("acceptance", 6, "seller")],
        "event_type STRING, event_sequence INT, agent_side STRING")
    other_plain = spark.createDataFrame(
        [("offer", 1, "seller"), ("rejection", 2, "buyer")],
        "event_type STRING, event_sequence INT, agent_side STRING")
    other_rich = spark.createDataFrame(
        [("price_request", 1, "buyer"), ("offer", 2, "seller"), ("availability_check", 3, "seller"),
         ("escalation_to_human", 4, "buyer"), ("rejection", 5, "buyer")],
        "event_type STRING, event_sequence INT, agent_side STRING")

    def _expand(sess_df, steps_df):
        return sess_df.crossJoin(F.broadcast(steps_df))

    ev = (_expand(reached.filter(~F.col("_rich")), reached_plain)
          .unionByName(_expand(reached.filter(F.col("_rich")), reached_rich))
          .unionByName(_expand(other.filter(~F.col("_rich")), other_plain))
          .unionByName(_expand(other.filter(F.col("_rich")), other_rich)))
    k = F.concat(F.col("a2a_session_id"), F.lit("-"), F.col("event_sequence").cast("string"))

    df = (ev
          .withColumn("a2a_negotiation_event_id", F.concat(F.lit("NEV-"), F.abs(F.hash(k, F.lit(seed))).cast("string")))
          # Emitting agent: buyer steps -> buyer agent, seller steps -> seller agent
          # (the negotiating role, regardless of which side opened the session).
          .withColumn("a2a_agent_sk",
                      F.when(F.col("agent_side") == "buyer", F.col("buyer_agent_sk")).otherwise(F.col("seller_agent_sk")))
          .withColumn("a2a_agent_id",
                      F.when(F.col("agent_side") == "buyer", F.col("buyer_agent_id")).otherwise(F.col("seller_agent_id")))
          # Price ladder: seller's opening offer high, buyer's counter lower,
          # acceptance settles between — a downward concession from the ask.
          .withColumn("_base", (F.lit(50) + (F.abs(F.hash(F.col("a2a_session_id"), F.lit(seed + 8))) % F.lit(450))).cast("double"))
          .withColumn("proposed_price",
                      F.when(F.col("event_type").isin("offer", "counter_offer", "acceptance"),
                             F.when(F.col("event_type") == "offer", F.col("_base") * F.lit(1.10))
                              .when(F.col("event_type") == "counter_offer", F.col("_base") * F.lit(0.95))
                              .otherwise(F.col("_base") * F.lit(1.00)).cast("decimal(18,4)"))
                       .otherwise(F.lit(None).cast("decimal(18,4)")))
          .withColumn("currency_code",
                      F.when(F.col("proposed_price").isNotNull(), F.lit("USD")).otherwise(F.lit(None).cast("string")))
          .withColumn("proposed_quantity",
                      F.when(F.col("proposed_price").isNotNull(),
                             (F.abs(F.hash(F.col("a2a_session_id"), F.lit(seed + 9))) % F.lit(10) + F.lit(1)).cast("int"))
                       .otherwise(F.lit(None).cast("int")))
          .withColumn("event_timestamp",
                      F.least(F.col("initiated_timestamp") + F.expr("INTERVAL '1' MINUTE") * (F.col("event_sequence") * F.lit(5)), now))
          .withColumn("latency_seconds", (F.abs(F.hash(k, F.lit(seed + 10))) % F.lit(30) + F.lit(1)).cast("int"))
          .withColumn("ingest_timestamp",
                      F.least(F.col("event_timestamp") + F.expr("INTERVAL '1' SECOND") * F.col("latency_seconds"), now))
          .withColumn("record_source", F.lit(RECORD_SOURCE))
          .withColumn("load_timestamp", now)
          .drop("agent_side", "session_status", "initiated_timestamp", "_base", "_rich",
                "buyer_agent_sk", "buyer_agent_id", "seller_agent_sk", "seller_agent_id"))

    fqtn = f"{catalog}.{schema}.a2a_negotiation_event"
    return _write(spark, df, fqtn, A2A_NEGOTIATION_EVENT_COLUMNS, mode)


# ---- entry point ----

def run(ctx):
    # Slice 1: conversational shopping + intent product discovery.
    generate(ctx.spark, ctx.catalog, ctx.schemas, _defaults(), ctx.mode, ctx.base_currency)

    # Slice 2: agent-to-agent (A2A) transactions.
    spark, catalog, mode = ctx.spark, ctx.catalog, ctx.mode
    ac = ctx.schemas["ac"]
    cfg = load_config()

    profile_df = spark.table(f"{catalog}.{ctx.schemas['customer']}.profile").filter("is_current = TRUE")
    store_df = spark.table(f"{catalog}.{ctx.schemas['store']}.store").filter("is_current = TRUE")
    product_df = spark.table(f"{catalog}.{ctx.schemas['product']}.product").filter("is_current = TRUE")

    agent_df = generate_agents(spark, catalog, ac, cfg, mode, profile_df, store_df)
    generate_mandates(spark, catalog, ac, cfg, mode, profile_df, agent_df)
    session_df = generate_sessions(spark, catalog, ac, cfg, mode, profile_df, store_df, product_df, agent_df)
    generate_events(spark, catalog, ac, cfg, mode, session_df)
    print("Agentic Commerce generation complete.")


def main():
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
