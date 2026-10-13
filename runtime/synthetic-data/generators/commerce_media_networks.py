# ============================================================
# ORDM · Synthetic data · Commerce Media Networks generator
# Version: 0.5
# Generated: 2026-07-13
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-07-13
# ============================================================
# Populates the commerce-media-networks package end to end: FIRST the relocated
# retail-media DIMENSIONS (advertiser [derived from the silver supplier], campaign,
# ad_group, creative, placement, experiment, experiment_cell, delivery_channel), THEN the
# fact layer over them + core product/store/profile + customer_order_line (all must
# exist — declared as depends_on in _registry.py). Facts carry real dimension
# surrogate FKs (so the FK-orphan checks pass); optional intra-package links are
# left NULL. Hashed identifiers are SHA-256 of synthetic values (never raw). Single
# reporting currency = the deploy base currency.
# ============================================================

import os
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

try:
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _pick, _frac,
                         _count_1_to_max, attach_random_dim, _write)
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _pick, _frac,
                         _count_1_to_max, attach_random_dim, _write)

# ------------------------------------------------------------
# Column contracts — MUST match the DDL (minus IDENTITY *_sk).
# Checked against the DDL by tests/test_commerce_media_networks.py.
# ------------------------------------------------------------
MEDIA_EVENT_COLUMNS = [
    "media_event_id", "campaign_sk", "campaign_id", "ad_group_sk", "ad_group_id",
    "creative_sk", "creative_id", "placement_sk", "placement_id", "product_sk", "product_id",
    "store_sk", "store_id", "profile_sk", "profile_id", "delivery_channel_sk", "delivery_channel_id",
    "audience_sk", "audience_id", "keyword_sk", "keyword_id", "search_term_text",
    "experiment_sk", "experiment_id",
    "experiment_cell_sk", "experiment_cell_id", "parent_media_event_sk", "parent_media_event_id",
    "event_type", "event_ts", "event_date", "cost_amount", "currency_code", "duration_sec",
    "viewable_flag", "ivt_flag", "ivt_type", "click_resolved_flag", "customer_key_hash",
    "household_key_hash", "consent_status", "record_source", "load_timestamp",
]
CONVERSION_EVENT_COLUMNS = [
    "conversion_event_id", "profile_sk", "profile_id", "product_sk", "product_id",
    "store_sk", "store_id", "order_line_sk", "order_line_id", "order_id", "promo_sk", "promo_id", "experiment_sk",
    "experiment_id", "experiment_cell_sk", "experiment_cell_id", "conversion_type",
    "outcome_ts", "outcome_date", "gross_sales_amount", "net_sales_amount", "margin_amount",
    "currency_code", "units", "customer_key_hash", "consent_status", "record_source", "load_timestamp",
]
ATTRIBUTED_OUTCOME_COLUMNS = [
    "attributed_outcome_id", "campaign_sk", "campaign_id", "ad_group_sk", "ad_group_id",
    "creative_sk", "creative_id", "placement_sk", "placement_id", "advertiser_sk",
    "advertiser_id", "keyword_sk", "keyword_id", "product_sk", "product_id", "store_sk", "store_id", "profile_sk",
    "profile_id", "promo_sk", "promo_id", "touch_media_event_sk", "touch_media_event_id", "conversion_event_sk",
    "conversion_event_id", "experiment_sk", "experiment_id", "outcome_date", "attribution_model",
    "click_or_view_basis", "post_click_days", "post_view_days", "attributed_fraction",
    "gross_sales_amount", "net_sales_amount", "margin_amount", "currency_code", "units",
    "same_sku_flag", "halo_flag", "new_to_brand_flag", "new_to_category_flag", "extrapolated_flag",
    "customer_key_hash", "consent_status", "record_source", "load_timestamp",
]
EXPERIMENT_ASSIGNMENT_COLUMNS = [
    "experiment_assignment_id", "experiment_sk", "experiment_id", "experiment_cell_sk",
    "experiment_cell_id", "profile_sk", "profile_id", "assignment_unit_type",
    "assignment_unit_key_hash", "assignment_ts", "record_source", "load_timestamp",
]
AGG_CAMPAIGN_DAY_COLUMNS = [
    "campaign_day_id", "metric_date", "advertiser_sk", "advertiser_id",
    "campaign_sk", "campaign_id", "ad_group_sk", "ad_group_id", "creative_sk", "creative_id",
    "placement_sk", "placement_id", "product_sk", "product_id", "store_sk", "store_id",
    "delivery_channel_sk", "delivery_channel_id", "audience_sk", "audience_id",
    "impressions", "viewable_impressions", "gross_impressions", "ots_impressions",
    "invalid_traffic_impressions", "clicks", "scheduled_plays", "actual_plays", "conversions",
    "orders", "units", "platform_impressions", "ad_server_impressions", "reconciled_impressions",
    "discrepancy_pct", "media_spend_gross", "media_spend_net", "attributed_gross_sales",
    "attributed_net_sales", "same_sku_sales", "halo_sales", "new_to_brand_sales",
    "incremental_sales", "currency_code", "attribution_model", "post_click_days", "post_view_days",
    "extrapolated_metric_flag", "privacy_suppressed_flag", "suppression_reason", "record_source", "load_timestamp",
]
INCREMENTALITY_RESULT_COLUMNS = [
    "incrementality_result_id", "experiment_sk", "experiment_id", "treatment_cell_sk",
    "treatment_cell_id", "control_cell_sk", "control_cell_id", "campaign_sk", "campaign_id",
    "advertiser_sk", "advertiser_id", "product_sk", "product_id", "snapshot_date",
    "metric_name", "analysis_level", "observed_treatment_value", "observed_control_value",
    "counterfactual_value", "incremental_sales_amount", "incremental_margin_amount",
    "media_spend_amount", "currency_code", "lift_pct", "iroas_value", "confidence_level_pct",
    "ci_lower_value", "ci_upper_value", "p_value", "statistical_significance_flag",
    "sample_size_treatment", "sample_size_control", "methodology", "suppressed_flag",
    "record_source", "load_timestamp",
]
EXPERIMENT_DAILY_COLUMNS = [
    "experiment_daily_id", "experiment_sk", "experiment_id", "experiment_cell_sk",
    "experiment_cell_id", "metric_date", "analysis_level", "exposed_units", "converted_units",
    "sales_amount", "media_spend_amount", "currency_code", "record_source", "load_timestamp",
]
BUDGET_ALLOCATION_COLUMNS = [
    "budget_allocation_id", "campaign_sk", "campaign_id", "ad_group_sk", "ad_group_id",
    "placement_sk", "placement_id", "advertiser_sk", "advertiser_id", "allocation_level",
    "budget_window_start", "budget_window_end", "allocated_budget_amount", "booked_budget_amount",
    "currency_code", "funding_source", "planned_impressions", "planned_clicks",
    "planned_sales_amount", "pacing_method", "record_source", "load_timestamp",
]
PACING_SNAPSHOT_COLUMNS = [
    "pacing_snapshot_id", "campaign_sk", "campaign_id", "ad_group_sk", "ad_group_id",
    "placement_sk", "placement_id", "snapshot_ts", "snapshot_date", "daily_budget",
    "planned_spend_to_date", "actual_spend_to_date", "expected_spend_to_date",
    "projected_end_spend", "currency_code", "pacing_ratio", "pacing_status", "record_source", "load_timestamp",
]
# STORE_ZONE_INTERVAL_COLUMNS was removed with the fact itself (ADR 0033). The contract
# now lives in generators/connected_store_signals.py as SENSOR_REPORT_INTERVAL_COLUMNS.
PRODUCT_STORE_DAY_COLUMNS = [
    "product_store_day_id", "product_sk", "product_id", "store_sk", "store_id", "business_date",
    "in_stock_flag", "on_hand_units", "pos_units", "pos_net_sales_amount", "currency_code",
    "record_source", "load_timestamp",
]

# ------------------------------------------------------------
# Relocated retail-media DIMENSION column contracts (gold; formerly the
# canonical-core/media domain). MUST match the moved DDL (minus IDENTITY *_sk).
# Checked against the DDL by tests/test_commerce_media_networks.py.
# ------------------------------------------------------------
ADVERTISER_COLUMNS = [
    "advertiser_id", "supplier_sk", "supplier_id", "brand_name", "agency_name",
    "finance_account_code", "billing_currency_code", "relationship_type",
    "advertiser_status", "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
CAMPAIGN_COLUMNS = [
    "campaign_id", "advertiser_sk", "advertiser_id", "campaign_name",
    "objective", "campaign_status", "start_date", "end_date", "budget_amount",
    "currency_code", "buy_model", "attribution_model", "default_post_click_days",
    "default_post_view_days", "sales_metric_type", "supplier_visible_flag",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
AD_GROUP_COLUMNS = [
    "ad_group_id", "campaign_sk", "campaign_id", "audience_sk", "audience_id",
    "ad_group_name", "ad_group_status",
    "targeting_mode", "bid_strategy", "default_bid_amount", "currency_code",
    "optimization_goal", "start_date", "end_date", "effective_from_date",
    "effective_to_date", "is_current", "created_timestamp", "source_updated_timestamp",
    "record_source", "load_timestamp",
]
CREATIVE_COLUMNS = [
    "creative_id", "campaign_sk", "campaign_id", "creative_name", "creative_type",
    "mime_type", "duration_seconds", "aspect_ratio", "language_code", "approval_status",
    "brand_safety_class", "asset_uri", "effective_from_date", "effective_to_date",
    "is_current", "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
PLACEMENT_COLUMNS = [
    "placement_id", "placement_name", "media_platform", "ad_product_line", "placement_type",
    "ad_format", "pricing_model", "device_type", "store_scope", "sellable_capacity_qty",
    "capacity_unit", "page_or_zone_code", "effective_from_date", "effective_to_date",
    "is_current", "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
EXPERIMENT_COLUMNS = [
    "experiment_id", "campaign_sk", "campaign_id", "experiment_name", "experiment_type",
    "methodology", "unit_of_assignment", "objective_metric", "experiment_status",
    "start_date", "end_date", "confidence_level", "effective_from_date", "effective_to_date",
    "is_current", "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
EXPERIMENT_CELL_COLUMNS = [
    "experiment_cell_id", "experiment_sk", "experiment_id", "cell_name", "cell_role",
    "traffic_allocation_pct", "is_control", "effective_from_date", "effective_to_date",
    "is_current", "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
DELIVERY_CHANNEL_COLUMNS = [
    "delivery_channel_id", "delivery_channel_name", "delivery_channel_category", "is_in_store_flag",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
KEYWORD_COLUMNS = [
    "keyword_id", "ad_group_sk", "ad_group_id", "keyword_text", "match_type",
    "keyword_status", "is_negative_flag", "bid_amount", "currency_code",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
# AUDIENCE_COLUMNS moved to the trade_promotion generator (ADR 0022).

# ------------------------------------------------------------
# Vocabularies (subsets of the DDL "Allowed values").
# ------------------------------------------------------------
EVENT_TYPES = ["impression", "viewable_impression", "click", "ad_play", "video_start", "video_complete"]
IVT_TYPES = ["none", "givt", "sivt"]
CONSENT_STATUS = ["granted", "denied", "unknown"]
CONVERSION_TYPES = ["purchase", "add_to_cart", "pdp_view", "store_visit", "signup"]
ATTRIBUTION_MODELS = ["last_touch", "first_touch", "linear", "position_based", "data_driven"]
BASIS = ["click", "view"]
ASSIGNMENT_UNIT_TYPES = ["user", "household", "geo", "store", "device"]
SUPPRESSION_REASONS = ["below_threshold", "consent", "policy", "none"]
METRIC_NAMES = ["incremental_sales", "incremental_units", "roas", "conversion_rate", "reach"]
ANALYSIS_LEVELS = ["overall", "store", "geo", "product", "category", "vendor"]
METHODOLOGIES = ["randomized_control", "matched_market", "synthetic_control", "difference_in_differences", "other"]
FUNDING_SOURCES = ["supplier", "retailer", "shared", "agency"]
PACING_METHODS = ["even", "asap", "front_loaded", "custom"]
PACING_STATUS = ["on_track", "under_pacing", "over_pacing", "exhausted"]
# ZONE_CODES moved to generators/connected_store_signals.py with the footfall fact
# (ADR 0033), where it now seeds a real store_zone dimension rather than a bare code.

# ------------------------------------------------------------
# Relocated retail-media DIMENSION vocabularies (formerly generators/media.py).
# Enum lists are subsets of the moved DDL domains.
# ------------------------------------------------------------
BRAND_WORDS = ["Sunrise", "Peak", "Harbor", "Meadow", "Nova", "Cedar", "Vela", "Orchard"]
AGENCIES = ["Omnimedia", "BrandReach", "MediaPro", "Catalyst"]
RELATIONSHIP_TYPES = ["direct", "agency", "reseller"]
ADVERTISER_STATUS = ["active", "inactive"]
OBJECTIVES = ["awareness", "consideration", "conversion", "loyalty", "other"]
CAMPAIGN_STATUS = ["draft", "active", "paused", "completed", "archived"]
BUY_MODELS = ["cpc", "cpm", "cpa", "flat", "other"]
SALES_METRIC_TYPES = ["gross", "net"]
AD_GROUP_STATUS = ["draft", "active", "paused", "completed", "archived"]
TARGETING_MODES = ["keyword", "audience", "automatic", "contextual", "manual"]
BID_STRATEGIES = ["manual_cpc", "auto", "target_cpa", "target_roas", "max_conversions"]
OPTIMIZATION_GOALS = ["clicks", "conversions", "roas", "impressions", "reach"]
CREATIVE_TYPES = ["image", "video", "audio", "html", "native", "text"]
APPROVAL_STATUS = ["draft", "submitted", "approved", "rejected", "archived"]
BRAND_SAFETY_CLASSES = ["safe", "moderate", "restricted"]
MIME_TYPES = ["image/jpeg", "image/png", "video/mp4", "audio/mpeg", "text/html"]
ASPECT_RATIOS = ["16:9", "1:1", "9:16", "4:3"]
LANG_CODES = ["en", "fr", "de", "es", "it"]
AD_PRODUCT_LINES = ["sponsored_products", "onsite_display", "offsite_display", "email", "loyalty"]
PLACEMENT_TYPES = ["search", "banner", "product_listing", "video", "audio", "endcap", "shelf", "other"]
AD_FORMATS = ["display", "video", "audio", "native", "sponsored_product", "text"]
PRICING_MODELS = ["cpc", "cpm", "cpa", "flat", "other"]
DEVICE_TYPES = ["desktop", "mobile", "tablet", "ctv", "other"]
MATCH_TYPES = ["exact", "phrase", "broad", "negative"]
KEYWORD_STATUS = ["active", "paused", "archived"]
# audience dimension (types/origins/count) moved to the trade_promotion generator with the
# audience table itself (ADR 0022 — promoted to shared silver marketing).
STORE_SCOPES = ["all_stores", "banner", "region", "single_store", "online"]
CAPACITY_UNITS = ["impressions", "slots", "seconds", "sov_pct"]
PLATFORMS = ["onsite_web", "onsite_app", "offsite_dsp", "in_store_network", "email_platform"]
EXPERIMENT_TYPES = ["geo_holdout", "audience_holdout", "ghost_ads", "switchback", "pre_post", "other"]
OBJECTIVE_METRICS = ["incremental_sales", "incremental_units", "roas", "conversion_rate", "reach", "other"]
EXPERIMENT_STATUS = ["draft", "running", "completed", "analyzed", "archived"]
CELL_ROLES = ["treatment", "control", "holdout"]


def load_config():
    cfg = {"seed": 1401, "events_per_campaign": 3, "conversions": 4000,
           "budget_per_campaign": 1, "pacing_per_campaign": 2, "zone_rows": 200, "psd_rows": 400,
           # relocated retail-media dimension fan-out (formerly the media generator)
           "brands_per_supplier": 2, "campaigns_per_brand": 3, "ad_groups_per_campaign": 2,
           "creatives_per_campaign": 2, "num_placements": 40}
    c = load_domain_config("commerce_media_networks")
    cfg["seed"] = c.get("seed", cfg["seed"])
    vols = c.get("volumes", {}) or {}
    for k in list(cfg):
        if k != "seed":
            cfg[k] = vols.get(k, cfg[k])
    return cfg


# ------------------------------------------------------------
# Relocated retail-media DIMENSION builders (ported from the former
# former generators/media.py; the advertiser/channel renames applied). The
# advertiser reuses the silver supplier (an advertiser role); the other dims
# derive from advertiser/campaign. Written into the cmn schema BEFORE the facts.
# ------------------------------------------------------------
def build_advertisers(spark, supplier_current, seed, brands_per, base_currency):
    base = (supplier_current
            .withColumn("_n", _count_1_to_max(brands_per, seed, "adv_n", "supplier_id"))
            .withColumn("k", F.explode(F.expr("sequence(1, _n)"))))
    rel = _pick(RELATIONSHIP_TYPES, seed, "rel", "supplier_id", "k")
    return (base
            .withColumn("advertiser_id",
                        F.concat(F.lit("ADV-"), F.col("supplier_id"), F.lit("-"), F.col("k")))
            .withColumn("brand_name",
                        F.concat(_pick(BRAND_WORDS, seed, "brand", "supplier_id", "k"),
                                 F.lit(" "), F.col("k").cast("string")))
            .withColumn("relationship_type", rel)
            .withColumn("agency_name",
                        F.when(F.col("relationship_type") == "agency",
                               _pick(AGENCIES, seed, "agency", "supplier_id", "k"))
                         .otherwise(F.lit(None).cast("string")))
            .withColumn("finance_account_code",
                        F.concat(F.lit("FIN-"), F.col("supplier_id"), F.lit("-"), F.col("k")))
            .withColumn("billing_currency_code", F.lit(base_currency))
            .withColumn("advertiser_status",
                        F.when(_frac(seed, "adv", "supplier_id", "k") < 0.9, F.lit("active"))
                         .otherwise(F.lit("inactive")))
            .withColumn("effective_from_date",
                        F.expr("date_add(date'2021-01-01', cast(abs(hash(supplier_id, k)) % 900 as int))"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_campaigns_dim(spark, adv_current, seed, campaigns_per, base_currency):
    base = (adv_current
            .withColumn("_n", _count_1_to_max(campaigns_per, seed, "cmp_n", "advertiser_id"))
            .withColumn("k", F.explode(F.expr("sequence(1, _n)"))))
    start = F.expr("date_add(date'2024-01-01', cast(abs(hash(advertiser_id, k)) % 500 as int))")
    return (base
            .withColumn("campaign_id",
                        F.concat(F.lit("CMP-"), F.col("advertiser_id"), F.lit("-"), F.col("k")))
            .withColumn("campaign_name",
                        F.concat(F.lit("Campaign "), F.col("advertiser_id"), F.lit("/"), F.col("k")))
            .withColumn("objective", _pick(OBJECTIVES, seed, "obj", "advertiser_id", "k"))
            .withColumn("campaign_status", _pick(CAMPAIGN_STATUS, seed, "cst", "advertiser_id", "k"))
            .withColumn("start_date", start)
            .withColumn("end_date",
                        F.expr("date_add(date'2024-01-01', cast(abs(hash(advertiser_id, k)) % 500 as int) "
                               "+ (abs(hash(advertiser_id, k, 7)) % 60 + 14))"))
            .withColumn("budget_amount",
                        ((F.abs(F.hash("advertiser_id", "k", F.lit(seed))) % F.lit(490) + F.lit(10))
                         * F.lit(1000)).cast("decimal(18,2)"))
            .withColumn("currency_code", F.lit(base_currency))
            .withColumn("buy_model", _pick(BUY_MODELS, seed, "buy", "advertiser_id", "k"))
            .withColumn("attribution_model", _pick(ATTRIBUTION_MODELS, seed, "attr", "advertiser_id", "k"))
            .withColumn("default_post_click_days",
                        (F.abs(F.hash("advertiser_id", "k", F.lit(seed))) % F.lit(14) + F.lit(1)).cast("int"))
            .withColumn("default_post_view_days",
                        (F.abs(F.hash("advertiser_id", "k", F.lit(seed))) % F.lit(7) + F.lit(1)).cast("int"))
            .withColumn("sales_metric_type", _pick(SALES_METRIC_TYPES, seed, "smt", "advertiser_id", "k"))
            .withColumn("supplier_visible_flag", _frac(seed, "vis", "advertiser_id", "k") < 0.8)
            .withColumn("effective_from_date", F.col("start_date"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_ad_groups_dim(spark, campaign_current, seed, per, base_currency):
    base = (campaign_current
            .withColumn("_n", _count_1_to_max(per, seed, "ag_n", "campaign_id"))
            .withColumn("k", F.explode(F.expr("sequence(1, _n)"))))
    start = F.expr("date_add(date'2024-01-01', cast(abs(hash(campaign_id, k)) % 500 as int))")
    return (base
            .withColumn("ad_group_id",
                        F.concat(F.lit("AG-"), F.col("campaign_id"), F.lit("-"), F.col("k")))
            .withColumn("ad_group_name",
                        F.concat(F.lit("Ad Group "), F.col("campaign_id"), F.lit("/"), F.col("k")))
            .withColumn("ad_group_status", _pick(AD_GROUP_STATUS, seed, "ags", "campaign_id", "k"))
            .withColumn("audience_sk", F.lit(None).cast("bigint"))
            .withColumn("audience_id", F.lit(None).cast("string"))
            .withColumn("targeting_mode", _pick(TARGETING_MODES, seed, "tm", "campaign_id", "k"))
            .withColumn("bid_strategy", _pick(BID_STRATEGIES, seed, "bs", "campaign_id", "k"))
            .withColumn("default_bid_amount",
                        ((F.abs(F.hash("campaign_id", "k", F.lit(seed))) % F.lit(500) + F.lit(50))
                         / F.lit(100.0)).cast("decimal(18,2)"))
            .withColumn("currency_code", F.lit(base_currency))
            .withColumn("optimization_goal", _pick(OPTIMIZATION_GOALS, seed, "og", "campaign_id", "k"))
            .withColumn("start_date", start)
            .withColumn("end_date",
                        F.expr("date_add(date'2024-01-01', cast(abs(hash(campaign_id, k)) % 500 as int) "
                               "+ (abs(hash(campaign_id, k, 3)) % 60 + 7))"))
            .withColumn("effective_from_date", F.col("start_date"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_keywords_dim(spark, ad_group_current, seed, per, base_currency):
    base = (ad_group_current
            .withColumn("_n", _count_1_to_max(per, seed, "kw_n", "ad_group_id"))
            .withColumn("k", F.explode(F.expr("sequence(1, _n)"))))
    return (base
            .withColumn("keyword_id",
                        F.concat(F.lit("KW-"), F.col("ad_group_id"), F.lit("-"), F.col("k")))
            .withColumn("keyword_text",
                        F.concat(F.lit("term "), F.col("ad_group_id"), F.lit("/"), F.col("k")))
            .withColumn("match_type", _pick(MATCH_TYPES, seed, "kmt", "ad_group_id", "k"))
            .withColumn("keyword_status", _pick(KEYWORD_STATUS, seed, "kst", "ad_group_id", "k"))
            .withColumn("is_negative_flag", F.col("match_type") == F.lit("negative"))
            .withColumn("bid_amount",
                        ((F.abs(F.hash("ad_group_id", "k", F.lit(seed))) % F.lit(400) + F.lit(20))
                         / F.lit(100.0)).cast("decimal(18,2)"))
            .withColumn("currency_code", F.lit(base_currency))
            .withColumn("effective_from_date", F.lit("2024-01-01").cast("date"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_creatives_dim(spark, campaign_current, seed, per, base_currency):
    base = (campaign_current
            .withColumn("_n", _count_1_to_max(per, seed, "cr_n", "campaign_id"))
            .withColumn("k", F.explode(F.expr("sequence(1, _n)"))))
    return (base
            .withColumn("creative_id",
                        F.concat(F.lit("CRV-"), F.col("campaign_id"), F.lit("-"), F.col("k")))
            .withColumn("creative_name",
                        F.concat(F.lit("Creative "), F.col("campaign_id"), F.lit("/"), F.col("k")))
            .withColumn("creative_type", _pick(CREATIVE_TYPES, seed, "ct", "campaign_id", "k"))
            .withColumn("mime_type", _pick(MIME_TYPES, seed, "mt", "campaign_id", "k"))
            .withColumn("duration_seconds",
                        F.when(F.col("creative_type").isin("video", "audio"),
                               (F.abs(F.hash("campaign_id", "k", F.lit(seed))) % F.lit(55) + F.lit(5)).cast("int"))
                         .otherwise(F.lit(None).cast("int")))
            .withColumn("aspect_ratio", _pick(ASPECT_RATIOS, seed, "ar", "campaign_id", "k"))
            .withColumn("language_code", _pick(LANG_CODES, seed, "lc", "campaign_id", "k"))
            .withColumn("approval_status", _pick(APPROVAL_STATUS, seed, "as", "campaign_id", "k"))
            .withColumn("brand_safety_class", _pick(BRAND_SAFETY_CLASSES, seed, "bsc", "campaign_id", "k"))
            .withColumn("asset_uri", F.concat(F.lit("asset://creatives/"), F.col("campaign_id"),
                                              F.lit("/"), F.col("k")))
            .withColumn("effective_from_date",
                        F.expr("date_add(date'2024-01-01', cast(abs(hash(campaign_id, k)) % 500 as int))"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_placements_dim(spark, seed, n):
    """Standalone inventory catalog — not derived from a parent."""
    base = spark.range(n).withColumnRenamed("id", "pid")
    return (base
            .withColumn("placement_id",
                        F.concat(F.lit("PLC-"), F.lpad(F.col("pid").cast("string"), 5, "0")))
            .withColumn("placement_name", F.concat(F.lit("Placement "), F.col("pid").cast("string")))
            .withColumn("media_platform", _pick(PLATFORMS, seed, "plat", "pid"))
            .withColumn("ad_product_line", _pick(AD_PRODUCT_LINES, seed, "chan", "pid"))
            .withColumn("placement_type", _pick(PLACEMENT_TYPES, seed, "ptype", "pid"))
            .withColumn("ad_format", _pick(AD_FORMATS, seed, "fmt", "pid"))
            .withColumn("pricing_model", _pick(PRICING_MODELS, seed, "pm", "pid"))
            .withColumn("device_type", _pick(DEVICE_TYPES, seed, "dev", "pid"))
            .withColumn("store_scope", _pick(STORE_SCOPES, seed, "ss", "pid"))
            .withColumn("sellable_capacity_qty",
                        (F.abs(F.hash("pid", F.lit(seed))) % F.lit(9000) + F.lit(1000)).cast("int"))
            .withColumn("capacity_unit", _pick(CAPACITY_UNITS, seed, "cu", "pid"))
            .withColumn("page_or_zone_code",
                        F.concat(F.lit("ZONE-"), (F.abs(F.hash("pid")) % F.lit(20)).cast("string")))
            .withColumn("effective_from_date",
                        F.expr("date_add(date'2023-01-01', cast(abs(hash(pid)) % 400 as int))"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_experiments_dim(spark, campaign_current, seed):
    """Incrementality experiments over a subset (~35%) of campaigns."""
    exp = campaign_current.where(_frac(seed, "hasexp", "campaign_id") < 0.35)
    start = F.expr("date_add(date'2024-02-01', cast(abs(hash(campaign_id)) % 400 as int))")
    return (exp
            .withColumn("experiment_id", F.concat(F.lit("EXP-"), F.col("campaign_id")))
            .withColumn("experiment_name", F.concat(F.lit("Experiment "), F.col("campaign_id")))
            .withColumn("experiment_type", _pick(EXPERIMENT_TYPES, seed, "et", "campaign_id"))
            .withColumn("methodology", _pick(METHODOLOGIES, seed, "meth", "campaign_id"))
            .withColumn("unit_of_assignment", _pick(ASSIGNMENT_UNIT_TYPES, seed, "uoa", "campaign_id"))
            .withColumn("objective_metric", _pick(OBJECTIVE_METRICS, seed, "om", "campaign_id"))
            .withColumn("experiment_status", _pick(EXPERIMENT_STATUS, seed, "est", "campaign_id"))
            .withColumn("start_date", start)
            .withColumn("end_date",
                        F.expr("date_add(date'2024-02-01', cast(abs(hash(campaign_id)) % 400 as int) "
                               "+ (abs(hash(campaign_id, 5)) % 60 + 30))"))
            .withColumn("confidence_level",
                        F.element_at(F.array(F.lit(0.90), F.lit(0.95), F.lit(0.99)),
                                     ((F.abs(F.hash("campaign_id", F.lit(seed))) % F.lit(3)) + F.lit(1)).cast("int"))
                         .cast("decimal(5,4)"))
            .withColumn("effective_from_date", F.col("start_date"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_experiment_cells_dim(spark, experiment_current, seed):
    """Two cells per experiment: treatment (k=1) + control (k=2), 50/50."""
    base = experiment_current.withColumn("k", F.explode(F.array(F.lit(1), F.lit(2))))
    return (base
            .withColumn("experiment_cell_id",
                        F.concat(F.lit("EC-"), F.col("experiment_id"), F.lit("-"), F.col("k")))
            .withColumn("cell_name", F.when(F.col("k") == 1, F.lit("Treatment")).otherwise(F.lit("Control")))
            .withColumn("cell_role", F.when(F.col("k") == 1, F.lit("treatment")).otherwise(F.lit("control")))
            .withColumn("traffic_allocation_pct", F.lit(50.00).cast("decimal(5,2)"))
            .withColumn("is_control", F.col("k") == 2)
            .withColumn("effective_from_date", F.expr("date'2024-02-01'"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_delivery_channels(spark):
    """Conformed delivery-channel reference dimension (Type 1)."""
    rows = [
        ("onsite_web", "Onsite Web", "onsite_web", False),
        ("onsite_app", "Onsite App", "onsite_app", False),
        ("offsite", "Offsite", "offsite", False),
        ("in_store_screen", "In-Store Screen", "in_store_screen", True),
        ("in_store_audio", "In-Store Audio", "in_store_audio", True),
        ("dooh", "Digital Out-of-Home", "dooh", False),
        ("other", "Other", "other", False),
    ]
    return (spark.createDataFrame(
                rows, "delivery_channel_id string, delivery_channel_name string, delivery_channel_category string, is_in_store_flag boolean")
            .withColumn("created_timestamp", F.current_timestamp())
            .withColumn("source_updated_timestamp", F.current_timestamp())
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def _audit(df):
    return (df.withColumn("record_source", F.lit(RECORD_SOURCE))
              .withColumn("load_timestamp", F.current_timestamp()))


def _hash(*keys):
    return F.sha2(F.concat_ws(
        "|",
        *[(F.col(k) if isinstance(k, str) else k).cast("string") for k in keys],
    ), 256)


def generate(spark, catalog, schemas, cfg, mode, base_currency="USD"):
    if not catalog:
        raise ValueError("`catalog` parameter is required (guardrail #1: no hardcoded catalog).")

    def fq(schema, table):
        return f"{catalog}.{schemas[schema]}.{table}"

    seed = cfg["seed"]
    cur = F.lit(base_currency)
    print(f"[ordm] generating commerce-media-networks into {catalog} (seed={seed}, mode={mode})")

    # === 0. relocated retail-media DIMENSIONS (gold), built into the cmn schema
    #        BEFORE the facts. advertiser reuses the silver supplier; the other
    #        dims derive from advertiser/campaign; delivery_channel is a static lookup. ===
    supplier_current = (spark.table(fq("supplier", "supplier"))
                        .where("is_current = true").select("supplier_id", "supplier_sk"))
    advertisers = build_advertisers(spark, supplier_current, seed,
                                    cfg["brands_per_supplier"], base_currency)
    _write(spark, advertisers, fq("cmn", "advertiser"), ADVERTISER_COLUMNS, mode)

    adv_current = (spark.table(fq("cmn", "advertiser"))
                   .where("is_current = true").select("advertiser_id", "advertiser_sk"))
    campaigns_dim = build_campaigns_dim(spark, adv_current, seed, cfg["campaigns_per_brand"], base_currency)
    _write(spark, campaigns_dim, fq("cmn", "campaign"), CAMPAIGN_COLUMNS, mode)

    campaign_current = (spark.table(fq("cmn", "campaign"))
                        .where("is_current = true").select("campaign_id", "campaign_sk"))
    _write(spark, build_ad_groups_dim(spark, campaign_current, seed, cfg["ad_groups_per_campaign"], base_currency),
           fq("cmn", "ad_group"), AD_GROUP_COLUMNS, mode)
    ad_group_current = (spark.table(fq("cmn", "ad_group"))
                        .where("is_current = true").select("ad_group_id", "ad_group_sk"))
    _write(spark, build_keywords_dim(spark, ad_group_current, seed, cfg.get("keywords_per_ad_group", 3), base_currency),
           fq("cmn", "keyword"), KEYWORD_COLUMNS, mode)
    _write(spark, build_creatives_dim(spark, campaign_current, seed, cfg["creatives_per_campaign"], base_currency),
           fq("cmn", "creative"), CREATIVE_COLUMNS, mode)
    _write(spark, build_placements_dim(spark, seed, cfg["num_placements"]),
           fq("cmn", "placement"), PLACEMENT_COLUMNS, mode)

    _write(spark, build_experiments_dim(spark, campaign_current, seed),
           fq("cmn", "experiment"), EXPERIMENT_COLUMNS, mode)
    experiment_current = (spark.table(fq("cmn", "experiment"))
                          .where("is_current = true").select("experiment_id", "experiment_sk"))
    _write(spark, build_experiment_cells_dim(spark, experiment_current, seed),
           fq("cmn", "experiment_cell"), EXPERIMENT_CELL_COLUMNS, mode)

    _write(spark, build_delivery_channels(spark), fq("cmn", "delivery_channel"), DELIVERY_CHANNEL_COLUMNS, mode)
    # audience moved to the shared silver marketing dim (ADR 0022); the trade_promotion
    # generator (the marketing writer) now populates marketing.audience. CMN facts leave
    # audience_sk NULL (ETL/follow-up populated), so nothing here reads it.

    # --- read conformed dimensions + core facts (current versions) ---
    campaigns = spark.table(fq("cmn", "campaign")).where("is_current = true") \
        .select("campaign_sk", "campaign_id", "advertiser_sk", "advertiser_id")
    ad_groups = spark.table(fq("cmn", "ad_group")).where("is_current = true").select("ad_group_sk", "ad_group_id")
    creatives = spark.table(fq("cmn", "creative")).where("is_current = true").select("creative_sk", "creative_id")
    placements = spark.table(fq("cmn", "placement")).where("is_current = true").select("placement_sk", "placement_id")
    experiments = spark.table(fq("cmn", "experiment")).where("is_current = true") \
        .select("experiment_sk", "experiment_id", "campaign_sk", "campaign_id")
    cells = spark.table(fq("cmn", "experiment_cell")).where("is_current = true") \
        .select("experiment_cell_sk", "experiment_cell_id", "experiment_sk", "cell_role")
    products = spark.table(fq("product", "product")).where("is_current = true").select("product_sk", "product_id")
    stores = spark.table(fq("store", "store")).where("is_current = true").select("store_sk", "store_id")
    profiles = spark.table(fq("customer", "profile")).where("is_current = true").select("profile_sk", "profile_id")
    order_lines = spark.table(fq("order", "customer_order_line")) \
        .select("order_line_sk", "order_line_id", "order_id", "profile_sk", "profile_id",
                "product_sk", "product_id", "store_sk", "store_id", "net_amount", "units")

    n_prod, n_store, n_prof = products.count(), stores.count(), profiles.count()
    n_ag, n_cr, n_pl = ad_groups.count(), creatives.count(), placements.count()

    # ---- 1. media_event (driven by campaigns; attach product/profile/ad_group/creative/placement) ----
    ev = (campaigns.withColumn("k", F.explode(F.expr(f"sequence(1, {int(cfg['events_per_campaign'])})")))
          .withColumn("media_event_id", F.concat(F.lit("ME-"), F.col("campaign_id"), F.lit("-"), F.col("k"))))
    ev = attach_random_dim(ev, ad_groups, n_ag, "ag", seed, "media_event_id")
    ev = attach_random_dim(ev, creatives, n_cr, "cr", seed, "media_event_id")
    ev = attach_random_dim(ev, placements, n_pl, "pl", seed, "media_event_id")
    ev = attach_random_dim(ev, products, n_prod, "pr", seed, "media_event_id")
    ev = attach_random_dim(ev, profiles, n_prof, "pf", seed, "media_event_id")
    ev = attach_random_dim(ev, stores, n_store, "st", seed, "media_event_id")
    et = _pick(EVENT_TYPES, seed, "et", "media_event_id")
    ev = (ev
          .withColumn("event_type", et)
          .withColumn("experiment_sk", F.lit(None).cast("bigint")).withColumn("experiment_id", F.lit(None).cast("string"))
          .withColumn("experiment_cell_sk", F.lit(None).cast("bigint")).withColumn("experiment_cell_id", F.lit(None).cast("string"))
          .withColumn("parent_media_event_sk", F.lit(None).cast("bigint")).withColumn("parent_media_event_id", F.lit(None).cast("string"))
          .withColumn("event_date", F.expr("date_add(date'2024-06-01', cast(abs(hash(media_event_id)) % 90 as int))"))
          .withColumn("event_ts", F.col("event_date").cast("timestamp"))
          .withColumn("cost_amount", F.round((F.abs(F.hash("media_event_id", F.lit(seed))) % F.lit(500) / F.lit(1000.0)).cast("decimal(18,2)"), 2))
          .withColumn("currency_code", cur)
          .withColumn("duration_sec", F.when(F.col("event_type").isin("ad_play", "video_start", "video_complete"),
                                             (F.abs(F.hash("media_event_id")) % F.lit(30) + F.lit(5)).cast("int")).otherwise(F.lit(None).cast("int")))
          .withColumn("viewable_flag", _frac(seed, "vw", "media_event_id") < 0.7)
          .withColumn("ivt_flag", _frac(seed, "iv", "media_event_id") < 0.05)
          .withColumn("ivt_type", F.when(F.col("ivt_flag"), _pick(["givt", "sivt"], seed, "ivt", "media_event_id")).otherwise(F.lit("none")))
          .withColumn("click_resolved_flag", F.when(F.col("event_type") == "click", _frac(seed, "cr2", "media_event_id") < 0.9).otherwise(F.lit(None).cast("boolean")))
          .withColumn("customer_key_hash", _hash("profile_id"))
          .withColumn("household_key_hash", _hash("profile_id", F.lit("hh")))
          .withColumn("consent_status", _pick(CONSENT_STATUS, seed, "cs", "media_event_id"))
          # delivery channel (cmn.delivery_channel) + shared marketing audience (marketing.audience) — nullable FKs, ETL/follow-up populated
          .withColumn("delivery_channel_sk", F.lit(None).cast("bigint")).withColumn("delivery_channel_id", F.lit(None).cast("string"))
          .withColumn("audience_sk", F.lit(None).cast("bigint")).withColumn("audience_id", F.lit(None).cast("string"))
          .withColumn("keyword_sk", F.lit(None).cast("bigint")).withColumn("keyword_id", F.lit(None).cast("string"))
          .withColumn("search_term_text", F.lit(None).cast("string")))
    _write(spark, _audit(ev), fq("cmn", "media_event"), MEDIA_EVENT_COLUMNS, mode)

    # ---- 2. conversion_event (driven by a sample of order lines) ----
    cv = (order_lines.where(_frac(seed, "conv", "order_line_id") < (float(cfg["conversions"]) / max(1, order_lines.count())))
          .withColumn("conversion_event_id", F.concat(F.lit("CV-"), F.col("order_line_id")))
          .withColumn("experiment_sk", F.lit(None).cast("bigint")).withColumn("experiment_id", F.lit(None).cast("string"))
          .withColumn("experiment_cell_sk", F.lit(None).cast("bigint")).withColumn("experiment_cell_id", F.lit(None).cast("string"))
          .withColumn("conversion_type", F.lit("purchase"))
          .withColumn("outcome_date", F.expr("date_add(date'2024-06-01', cast(abs(hash(order_line_id)) % 90 as int))"))
          .withColumn("outcome_ts", F.col("outcome_date").cast("timestamp"))
          .withColumn("net_sales_amount", F.col("net_amount").cast("decimal(18,2)"))
          .withColumn("gross_sales_amount", F.round((F.col("net_amount") * F.lit(1.1)).cast("decimal(18,2)"), 2))
          .withColumn("margin_amount", F.round((F.col("net_amount") * F.lit(0.3)).cast("decimal(18,2)"), 2))
          .withColumn("currency_code", cur)
          .withColumn("customer_key_hash", _hash("profile_id"))
          .withColumn("consent_status", _pick(CONSENT_STATUS, seed, "cs2", "order_line_id"))
          # concurrent trade-promotion conformance (marketing.promotion) — nullable FK
          .withColumn("promo_sk", F.lit(None).cast("bigint")).withColumn("promo_id", F.lit(None).cast("string")))
    _write(spark, _audit(cv), fq("cmn", "conversion_event"), CONVERSION_EVENT_COLUMNS, mode)

    # ---- 3. attributed_outcome (driven by campaigns; attach product/profile) ----
    ao = (campaigns.withColumn("k", F.explode(F.expr("sequence(1, 2)")))
          .withColumn("attributed_outcome_id", F.concat(F.lit("AO-"), F.col("campaign_id"), F.lit("-"), F.col("k"))))
    ao = attach_random_dim(ao, ad_groups, n_ag, "ag3", seed, "attributed_outcome_id")
    ao = attach_random_dim(ao, creatives, n_cr, "cr3", seed, "attributed_outcome_id")
    ao = attach_random_dim(ao, placements, n_pl, "pl3", seed, "attributed_outcome_id")
    ao = attach_random_dim(ao, products, n_prod, "pr3", seed, "attributed_outcome_id")
    ao = attach_random_dim(ao, profiles, n_prof, "pf3", seed, "attributed_outcome_id")
    ao = attach_random_dim(ao, stores, n_store, "st3", seed, "attributed_outcome_id")
    net = F.round((F.abs(F.hash("attributed_outcome_id", F.lit(seed))) % F.lit(20000) / F.lit(100.0)).cast("decimal(18,2)"), 2)
    ao = (ao
          .withColumn("touch_media_event_sk", F.lit(None).cast("bigint")).withColumn("touch_media_event_id", F.lit(None).cast("string"))
          .withColumn("conversion_event_sk", F.lit(None).cast("bigint")).withColumn("conversion_event_id", F.lit(None).cast("string"))
          .withColumn("experiment_sk", F.lit(None).cast("bigint")).withColumn("experiment_id", F.lit(None).cast("string"))
          .withColumn("outcome_date", F.expr("date_add(date'2024-06-01', cast(abs(hash(attributed_outcome_id)) % 90 as int))"))
          .withColumn("attribution_model", _pick(ATTRIBUTION_MODELS, seed, "am", "attributed_outcome_id"))
          .withColumn("click_or_view_basis", _pick(BASIS, seed, "b", "attributed_outcome_id"))
          .withColumn("post_click_days", F.lit(7)).withColumn("post_view_days", F.lit(1))
          .withColumn("attributed_fraction", F.lit(1.0).cast("decimal(9,6)"))
          .withColumn("net_sales_amount", net)
          .withColumn("gross_sales_amount", F.round((net * F.lit(1.1)).cast("decimal(18,2)"), 2))
          .withColumn("margin_amount", F.round((net * F.lit(0.3)).cast("decimal(18,2)"), 2))
          .withColumn("currency_code", cur)
          .withColumn("units", (F.abs(F.hash("attributed_outcome_id")) % F.lit(5) + F.lit(1)).cast("int"))
          .withColumn("same_sku_flag", _frac(seed, "ss", "attributed_outcome_id") < 0.6)
          .withColumn("halo_flag", _frac(seed, "hl", "attributed_outcome_id") < 0.3)
          .withColumn("new_to_brand_flag", _frac(seed, "ntb", "attributed_outcome_id") < 0.25)
          .withColumn("new_to_category_flag", _frac(seed, "ntc", "attributed_outcome_id") < 0.15)
          .withColumn("extrapolated_flag", _frac(seed, "ex", "attributed_outcome_id") < 0.1)
          .withColumn("customer_key_hash", _hash("profile_id"))
          .withColumn("consent_status", F.lit("granted"))
          .withColumn("keyword_sk", F.lit(None).cast("bigint"))
          .withColumn("keyword_id", F.lit(None).cast("string"))
          # concurrent trade-promotion conformance (marketing.promotion) — nullable FK
          .withColumn("promo_sk", F.lit(None).cast("bigint")).withColumn("promo_id", F.lit(None).cast("string")))
    _write(spark, _audit(ao), fq("cmn", "attributed_outcome"), ATTRIBUTED_OUTCOME_COLUMNS, mode)

    # ---- 4. experiment_assignment_bridge (cells × N units; attach profile) ----
    ba = (cells.withColumn("k", F.explode(F.expr("sequence(1, 20)")))
          .withColumn("experiment_assignment_id", F.concat(F.lit("EA-"), F.col("experiment_cell_id"), F.lit("-"), F.col("k")))
          .withColumnRenamed("experiment_sk", "experiment_sk"))
    ba = attach_random_dim(ba, profiles, n_prof, "pf4", seed, "experiment_assignment_id")
    ba = (ba
          .withColumn("experiment_id", F.lit(None).cast("string"))
          .withColumn("assignment_unit_type", _pick(ASSIGNMENT_UNIT_TYPES, seed, "au", "experiment_assignment_id"))
          .withColumn("assignment_unit_key_hash", _hash("profile_id"))
          .withColumn("assignment_ts", F.expr("cast(date'2024-05-01' as timestamp)")))
    _write(spark, _audit(ba), fq("cmn", "experiment_assignment_bridge"), EXPERIMENT_ASSIGNMENT_COLUMNS, mode)

    # ---- 5. campaign_day (campaigns × days; ALL sentinels for the finer dims) ----
    ac = (campaigns.withColumn("d", F.explode(F.expr("sequence(0, 6)")))
          .withColumn("metric_date", F.expr("date_add(date'2024-06-01', d * 7)"))
          .withColumn("campaign_day_id", F.concat(F.lit("ACD-"), F.col("campaign_id"), F.lit("-"), F.col("d"))))
    imp = (F.abs(F.hash("campaign_day_id", F.lit(seed))) % F.lit(50000) + F.lit(1000))
    clk = (imp / F.lit(50)).cast("bigint")
    spend = F.round((imp / F.lit(20)).cast("decimal(18,2)"), 2)
    sales = F.round((spend * (F.lit(2) + _frac(seed, "roas", "campaign_day_id") * F.lit(6))).cast("decimal(18,2)"), 2)
    ac = (ac
          .withColumn("ad_group_sk", F.lit(None).cast("bigint")).withColumn("ad_group_id", F.lit("ALL"))
          .withColumn("creative_sk", F.lit(None).cast("bigint")).withColumn("creative_id", F.lit("ALL"))
          .withColumn("placement_sk", F.lit(None).cast("bigint")).withColumn("placement_id", F.lit("ALL"))
          .withColumn("product_sk", F.lit(None).cast("bigint")).withColumn("product_id", F.lit("ALL"))
          .withColumn("store_sk", F.lit(None).cast("bigint")).withColumn("store_id", F.lit("ALL"))
          # shared marketing dims (conformed) — sentinel ALL at the rollup grain
          .withColumn("delivery_channel_sk", F.lit(None).cast("bigint")).withColumn("delivery_channel_id", F.lit("ALL"))
          .withColumn("audience_sk", F.lit(None).cast("bigint")).withColumn("audience_id", F.lit("ALL"))
          .withColumn("impressions", imp.cast("bigint"))
          .withColumn("viewable_impressions", (imp * F.lit(0.7)).cast("bigint"))
          .withColumn("gross_impressions", (imp * F.lit(1.05)).cast("bigint"))
          .withColumn("ots_impressions", F.lit(0).cast("bigint"))
          .withColumn("invalid_traffic_impressions", (imp * F.lit(0.03)).cast("bigint"))
          .withColumn("clicks", clk).withColumn("scheduled_plays", F.lit(0).cast("bigint")).withColumn("actual_plays", F.lit(0).cast("bigint"))
          .withColumn("conversions", (clk / F.lit(10)).cast("bigint"))
          .withColumn("orders", (clk / F.lit(12)).cast("bigint"))
          .withColumn("units", (clk / F.lit(8)).cast("bigint"))
          .withColumn("platform_impressions", imp.cast("bigint")).withColumn("ad_server_impressions", (imp * F.lit(0.98)).cast("bigint"))
          .withColumn("reconciled_impressions", (imp * F.lit(0.99)).cast("bigint"))
          .withColumn("discrepancy_pct", F.lit(2.0).cast("decimal(9,4)"))
          .withColumn("media_spend_gross", F.round((spend * F.lit(1.1)).cast("decimal(18,2)"), 2)).withColumn("media_spend_net", spend)
          .withColumn("attributed_gross_sales", F.round((sales * F.lit(1.1)).cast("decimal(18,2)"), 2)).withColumn("attributed_net_sales", sales)
          .withColumn("same_sku_sales", F.round((sales * F.lit(0.6)).cast("decimal(18,2)"), 2))
          .withColumn("halo_sales", F.round((sales * F.lit(0.3)).cast("decimal(18,2)"), 2))
          .withColumn("new_to_brand_sales", F.round((sales * F.lit(0.2)).cast("decimal(18,2)"), 2))
          .withColumn("incremental_sales", F.round((sales * F.lit(0.4)).cast("decimal(18,2)"), 2))
          .withColumn("currency_code", cur)
          .withColumn("attribution_model", F.lit("last_touch")).withColumn("post_click_days", F.lit(7)).withColumn("post_view_days", F.lit(1))
          .withColumn("extrapolated_metric_flag", F.lit(False)).withColumn("privacy_suppressed_flag", F.lit(False))
          .withColumn("suppression_reason", F.lit("none")))
    _write(spark, _audit(ac), fq("cmn", "campaign_day"), AGG_CAMPAIGN_DAY_COLUMNS, mode)

    # ---- 6. incrementality_result (experiments × metric; treatment+control from cells) ----
    treat = cells.where("cell_role = 'treatment'").select("experiment_sk", F.col("experiment_cell_sk").alias("treatment_cell_sk"), F.col("experiment_cell_id").alias("treatment_cell_id"))
    ctrl = cells.where("cell_role = 'control'").select("experiment_sk", F.col("experiment_cell_sk").alias("control_cell_sk"), F.col("experiment_cell_id").alias("control_cell_id"))
    ir = (experiments.join(treat, "experiment_sk", "left").join(ctrl, "experiment_sk", "left")
          .withColumn("incrementality_result_id", F.concat(F.lit("IR-"), F.col("experiment_id")))
          .withColumn("advertiser_sk", F.lit(None).cast("bigint")).withColumn("advertiser_id", F.lit(None).cast("string"))
          .withColumn("keyword_sk", F.lit(None).cast("bigint")).withColumn("keyword_id", F.lit(None).cast("string"))
          .withColumn("product_sk", F.lit(None).cast("bigint")).withColumn("product_id", F.lit("ALL"))
          .withColumn("snapshot_date", F.lit(F.expr("date'2024-08-01'")))
          .withColumn("metric_name", F.lit("incremental_sales")).withColumn("analysis_level", F.lit("overall"))
          .withColumn("observed_treatment_value", F.round((F.abs(F.hash("experiment_id", F.lit(seed))) % F.lit(100000) / F.lit(100.0)).cast("decimal(18,4)"), 4))
          .withColumn("observed_control_value", F.round((F.abs(F.hash("experiment_id", F.lit(seed + 1))) % F.lit(80000) / F.lit(100.0)).cast("decimal(18,4)"), 4))
          .withColumn("counterfactual_value", F.col("observed_control_value"))
          .withColumn("incremental_sales_amount", F.round((F.col("observed_treatment_value") - F.col("observed_control_value")).cast("decimal(18,2)"), 2))
          .withColumn("incremental_margin_amount", F.round((F.col("incremental_sales_amount") * F.lit(0.3)).cast("decimal(18,2)"), 2))
          .withColumn("media_spend_amount", F.round((F.abs(F.hash("experiment_id")) % F.lit(50000) / F.lit(100.0)).cast("decimal(18,2)"), 2))
          .withColumn("currency_code", cur)
          .withColumn("lift_pct", F.round(((F.col("observed_treatment_value") - F.col("observed_control_value")) / F.when(F.col("observed_control_value") == 0, F.lit(None)).otherwise(F.col("observed_control_value")) * F.lit(100)).cast("decimal(9,4)"), 4))
          .withColumn("iroas_value", F.round((F.col("incremental_sales_amount") / F.when(F.col("media_spend_amount") == 0, F.lit(None)).otherwise(F.col("media_spend_amount"))).cast("decimal(12,4)"), 4))
          .withColumn("confidence_level_pct", F.lit(95.00).cast("decimal(5,2)"))
          .withColumn("ci_lower_value", F.round((F.col("incremental_sales_amount") * F.lit(0.8)).cast("decimal(18,4)"), 4))
          .withColumn("ci_upper_value", F.round((F.col("incremental_sales_amount") * F.lit(1.2)).cast("decimal(18,4)"), 4))
          .withColumn("p_value", F.round((_frac(seed, "pv", "experiment_id") * F.lit(0.1)).cast("decimal(9,6)"), 6))
          .withColumn("statistical_significance_flag", _frac(seed, "pv", "experiment_id") * F.lit(0.1) < 0.05)
          .withColumn("sample_size_treatment", (F.abs(F.hash("experiment_id")) % F.lit(9000) + F.lit(1000)).cast("bigint"))
          .withColumn("sample_size_control", (F.abs(F.hash("experiment_id", F.lit(2))) % F.lit(9000) + F.lit(1000)).cast("bigint"))
          .withColumn("methodology", _pick(METHODOLOGIES, seed, "meth", "experiment_id"))
          .withColumn("suppressed_flag", F.lit(False)))
    _write(spark, _audit(ir), fq("cmn", "incrementality_result"), INCREMENTALITY_RESULT_COLUMNS, mode)

    # ---- 7. experiment_daily (cells × days) ----
    ed = (cells.withColumn("d", F.explode(F.expr("sequence(0, 6)")))
          .withColumn("metric_date", F.expr("date_add(date'2024-06-01', d * 7)"))
          .withColumn("experiment_daily_id", F.concat(F.lit("AED-"), F.col("experiment_cell_id"), F.lit("-"), F.col("d")))
          .withColumn("experiment_id", F.lit(None).cast("string"))
          .withColumn("analysis_level", F.lit("overall"))
          .withColumn("exposed_units", (F.abs(F.hash("experiment_daily_id")) % F.lit(5000) + F.lit(100)).cast("bigint"))
          .withColumn("converted_units", (F.abs(F.hash("experiment_daily_id")) % F.lit(500)).cast("bigint"))
          .withColumn("sales_amount", F.round((F.abs(F.hash("experiment_daily_id")) % F.lit(100000) / F.lit(100.0)).cast("decimal(18,2)"), 2))
          .withColumn("media_spend_amount", F.round((F.abs(F.hash("experiment_daily_id")) % F.lit(20000) / F.lit(100.0)).cast("decimal(18,2)"), 2))
          .withColumn("currency_code", cur))
    _write(spark, _audit(ed), fq("cmn", "experiment_daily"), EXPERIMENT_DAILY_COLUMNS, mode)

    # ---- 8. budget_allocation (one per campaign) ----
    bd = (campaigns
          .withColumn("budget_allocation_id", F.concat(F.lit("BA-"), F.col("campaign_id")))
          .withColumn("ad_group_sk", F.lit(None).cast("bigint")).withColumn("ad_group_id", F.lit(None).cast("string"))
          .withColumn("placement_sk", F.lit(None).cast("bigint")).withColumn("placement_id", F.lit(None).cast("string"))
          .withColumn("allocation_level", F.lit("campaign"))
          .withColumn("budget_window_start", F.lit(F.expr("date'2024-06-01'"))).withColumn("budget_window_end", F.lit(F.expr("date'2024-08-31'")))
          .withColumn("allocated_budget_amount", F.round((F.abs(F.hash("campaign_id", F.lit(seed))) % F.lit(90000) + F.lit(10000)).cast("decimal(18,2)"), 2))
          .withColumn("booked_budget_amount", F.col("allocated_budget_amount"))
          .withColumn("currency_code", cur)
          .withColumn("funding_source", _pick(FUNDING_SOURCES, seed, "fs", "campaign_id"))
          .withColumn("planned_impressions", (F.abs(F.hash("campaign_id")) % F.lit(900000) + F.lit(100000)).cast("bigint"))
          .withColumn("planned_clicks", (F.abs(F.hash("campaign_id")) % F.lit(9000) + F.lit(1000)).cast("bigint"))
          .withColumn("planned_sales_amount", F.round((F.abs(F.hash("campaign_id")) % F.lit(500000)).cast("decimal(18,2)"), 2))
          .withColumn("pacing_method", _pick(PACING_METHODS, seed, "pm", "campaign_id")))
    _write(spark, _audit(bd), fq("cmn", "budget_allocation"), BUDGET_ALLOCATION_COLUMNS, mode)

    # ---- 9. pacing_snapshot (N per campaign) ----
    ps = (campaigns.withColumn("k", F.explode(F.expr(f"sequence(1, {int(cfg['pacing_per_campaign'])})")))
          .withColumn("pacing_snapshot_id", F.concat(F.lit("PS-"), F.col("campaign_id"), F.lit("-"), F.col("k")))
          .withColumn("ad_group_sk", F.lit(None).cast("bigint")).withColumn("ad_group_id", F.lit(None).cast("string"))
          .withColumn("placement_sk", F.lit(None).cast("bigint")).withColumn("placement_id", F.lit(None).cast("string"))
          .withColumn("snapshot_date", F.expr("date_add(date'2024-06-15', cast(abs(hash(pacing_snapshot_id)) % 60 as int))"))
          .withColumn("snapshot_ts", F.col("snapshot_date").cast("timestamp"))
          .withColumn("daily_budget", F.lit(1000.00).cast("decimal(18,2)"))
          .withColumn("planned_spend_to_date", F.round((F.abs(F.hash("pacing_snapshot_id")) % F.lit(50000)).cast("decimal(18,2)"), 2))
          .withColumn("actual_spend_to_date", F.round((F.col("planned_spend_to_date") * (F.lit(0.8) + _frac(seed, "pace", "pacing_snapshot_id") * F.lit(0.5))).cast("decimal(18,2)"), 2))
          .withColumn("expected_spend_to_date", F.col("planned_spend_to_date"))
          .withColumn("projected_end_spend", F.round((F.col("actual_spend_to_date") * F.lit(1.5)).cast("decimal(18,2)"), 2))
          .withColumn("currency_code", cur)
          .withColumn("pacing_ratio", F.round((F.col("actual_spend_to_date") / F.when(F.col("planned_spend_to_date") == 0, F.lit(None)).otherwise(F.col("planned_spend_to_date"))).cast("decimal(9,4)"), 4))
          .withColumn("pacing_status", _pick(PACING_STATUS, seed, "pst", "pacing_snapshot_id")))
    _write(spark, _audit(ps), fq("cmn", "pacing_snapshot"), PACING_SNAPSHOT_COLUMNS, mode)

    # ---- 10. store_zone_interval: RELOCATED, no longer generated here ----
    # The footfall aggregate moved to connected_store_signals.sensor_report_interval
    # (ADR 0033) and is populated by generators/connected_store_signals.py. CMN reads it
    # through cmn_schema.gold_store_zone_interval, a view, which needs no rows of its own.

    # ---- 11. product_store_day (sample of order lines' product×store × days) ----
    psd = (order_lines.select("product_sk", "product_id", "store_sk", "store_id").distinct()
           .where(_frac(seed, "psd", "product_id") < 0.2)
           .withColumn("product_store_day_id", F.concat(F.lit("PSD-"), F.col("product_id"), F.lit("-"), F.col("store_id")))
           .withColumn("business_date", F.expr("date_add(date'2024-06-01', cast(abs(hash(product_store_day_id)) % 60 as int))"))
           .withColumn("in_stock_flag", _frac(seed, "is", "product_store_day_id") < 0.9)
           .withColumn("on_hand_units", (F.abs(F.hash("product_store_day_id")) % F.lit(200)).cast("int"))
           .withColumn("pos_units", (F.abs(F.hash("product_store_day_id")) % F.lit(50)).cast("int"))
           .withColumn("pos_net_sales_amount", F.round((F.abs(F.hash("product_store_day_id")) % F.lit(5000) / F.lit(10.0)).cast("decimal(18,2)"), 2))
           .withColumn("currency_code", cur))
    _write(spark, _audit(psd), fq("cmn", "product_store_day"), PRODUCT_STORE_DAY_COLUMNS, mode)

    print("[ordm] commerce-media-networks generation complete.")


def run(ctx):
    cfg = load_config()
    generate(ctx.spark, ctx.catalog, ctx.schemas, cfg, ctx.mode, ctx.base_currency)


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
