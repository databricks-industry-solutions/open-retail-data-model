# ============================================================
# ORDM · Synthetic data · Actionable Customer Understanding · Market Analysis helper
# Version: 0.5
# Generated: 2026-08-24
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-08-24 by @saurabhshukla-db
# ============================================================
# Plain helper invoked by customer_ltv.py. It has no run(ctx): customer_ltv remains
# the sole provider of the acu schema key while declaring BMV as an upstream input.
# The generated story is sparse observation coverage, match-quality variation,
# unmatched competitor items, listing/availability changes, promotions, an
# unmeasured market-share remainder, and an append-only benchmark restatement.
# ============================================================

import os
import sys

from pyspark.sql import functions as F
from pyspark.sql.window import Window

try:
    from _common import RECORD_SOURCE, _write
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from _common import RECORD_SOURCE, _write


COMPETITOR_PRODUCT_MATCH_COLUMNS = [
    "competitor_product_match_id", "competitor_sk", "competitor_id",
    "competitor_item_ref", "product_sk", "product_id", "match_type",
    "match_method", "match_confidence", "first_matched_date",
    "last_verified_date", "is_active", "created_timestamp",
    "source_updated_timestamp", "record_source", "load_timestamp",
]

COMPETITOR_ASSORTMENT_COLUMNS = [
    "competitor_assortment_id", "source_observation_id", "competitor_sk",
    "competitor_id", "competitor_item_ref", "product_sk", "product_id",
    "category_ref", "match_type", "match_method", "match_confidence",
    "competitor_location_ref", "channel_code", "date_key", "observed_at_ts",
    "is_listed", "is_available", "search_rank", "marketplace_seller",
    "data_source", "raw_data_uri", "record_source", "load_timestamp",
]

COMPETITOR_PROMOTION_COLUMNS = [
    "competitor_promotion_id", "source_observation_id", "competitor_sk",
    "competitor_id", "competitor_item_ref", "product_sk", "product_id",
    "category_ref", "match_type", "match_method", "match_confidence",
    "competitor_location_ref", "channel_code", "promo_vehicle", "promo_type",
    "promo_price", "regular_price", "discount_depth_pct", "promo_start_date",
    "promo_end_date", "date_key", "observed_at_ts", "placement_rank",
    "is_front_page", "currency_code", "transaction_currency_code", "data_source",
    "raw_data_uri", "record_source", "load_timestamp",
]

MARKET_BENCHMARK_COLUMNS = [
    "market_benchmark_id", "source_observation_id", "benchmark_cell_id",
    "competitor_sk", "competitor_id", "market_definition", "geography_level",
    "geography_code", "category_ref", "subject_type", "subject_id", "period_type",
    "period_end_date", "sales_amount", "unit_volume", "market_share_pct",
    "market_growth_rate_pct", "eq_volume", "acv_weighted_distribution_pct",
    "numeric_distribution_pct", "tdp", "promo_sales_amount", "base_sales_amount",
    "currency_code", "is_restatement", "restates_market_benchmark_id",
    "observed_at_ts", "provider_updated_at_ts", "raw_data_uri", "record_source",
    "load_timestamp",
]

MATCH_TYPES = ["exact", "equivalent", "similar"]
MATCH_METHODS = ["gtin", "mpn_brand", "ai_text", "ai_image", "manual"]
CHANNELS = ["online", "in_store", "marketplace", "other"]
PROMO_VEHICLES = [
    "circular_print", "circular_digital", "onsite", "in_store", "email_app", "other"
]
PROMO_TYPES = ["TPR", "FEATURE", "DISPLAY", "FEATURE_AND_DISPLAY", "BOGO", "COUPON", "BUNDLE"]


def _element(values, zero_based_index):
    return F.element_at(F.array(*[F.lit(value) for value in values]), zero_based_index + F.lit(1))


def _dated_calendar(calendar_df):
    return (
        calendar_df.select("date_key").distinct()
        .withColumn("_date_index", F.datediff("date_key", F.lit("2000-01-01")))
    )


def build_competitor_product_matches(competitors_current, products_current, calendar_df):
    bounds = calendar_df.agg(
        F.min("date_key").alias("first_matched_date"),
        F.max("date_key").alias("last_verified_date"),
    )
    matches = (
        competitors_current.select("competitor_sk", "competitor_id")
        .crossJoin(products_current.select("product_sk", "product_id", "category", "list_price"))
        # Deterministically sample half the product axis per competitor before
        # any observation-day expansion, so competitor ranges are not universal.
        .where(F.pmod(F.abs(F.hash("competitor_id", "product_id")), F.lit(2)) == 0)
        .withColumn(
            "_match_index",
            F.row_number().over(Window.partitionBy("competitor_id").orderBy("product_id")),
        )
        .crossJoin(bounds)
        .withColumn(
            "competitor_item_ref",
            F.concat_ws("-", F.lit("ITEM"), F.col("competitor_id"), F.col("product_id")),
        )
        .withColumn(
            "competitor_product_match_id",
            F.concat_ws("|", F.col("competitor_id"), F.col("competitor_item_ref")),
        )
        .withColumn("match_type", _element(MATCH_TYPES, F.pmod(F.col("_match_index") - 1, F.lit(len(MATCH_TYPES)))))
        .withColumn("match_method", _element(MATCH_METHODS, F.pmod(F.col("_match_index") - 1, F.lit(len(MATCH_METHODS)))))
        .withColumn(
            "match_confidence",
            F.when(F.pmod(F.col("_match_index"), F.lit(3)) == 0, F.lit(0.72))
            .otherwise(F.lit(0.92) + F.pmod(F.col("_match_index"), F.lit(2)) * F.lit(0.03))
            .cast("decimal(5,4)"),
        )
        .withColumn("is_active", F.lit(True))
        .withColumn("created_timestamp", F.col("first_matched_date").cast("timestamp"))
        .withColumn("source_updated_timestamp", F.col("last_verified_date").cast("timestamp"))
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn("load_timestamp", F.col("last_verified_date").cast("timestamp"))
    )
    return matches


def build_competitor_assortment(matches, competitors_current, products_current, dated_calendar, seed):
    sparse_dates = dated_calendar.where(F.pmod(F.col("_date_index"), F.lit(2)) == 1)
    matched = (
        matches.crossJoin(sparse_dates)
        .withColumn("category_ref", F.coalesce(F.col("category"), F.lit("unclassified")))
        .withColumn("channel_code", _element(CHANNELS, F.pmod(F.col("_match_index") + F.col("_date_index"), F.lit(len(CHANNELS)))))
        .withColumn("is_listed", F.pmod(F.col("_date_index"), F.lit(5)) != 0)
        .withColumn(
            "is_available",
            F.when(~F.col("is_listed"), F.lit(None).cast("boolean"))
            .when(F.pmod(F.col("_date_index") + F.col("_match_index"), F.lit(4)) == 0, F.lit(None).cast("boolean"))
            .otherwise(F.pmod(F.col("_date_index") + F.col("_match_index"), F.lit(3)) != 0),
        )
    )

    unmatched = (
        competitors_current.select("competitor_sk", "competitor_id")
        .crossJoin(products_current.select(F.coalesce("category", F.lit("unclassified")).alias("category_ref")).distinct())
        .crossJoin(sparse_dates)
        .withColumn(
            "competitor_item_ref",
            F.concat_ws("-", F.lit("UNMATCHED"), F.col("competitor_id"), F.col("category_ref")),
        )
        .withColumn("product_sk", F.lit(None).cast("long"))
        .withColumn("product_id", F.lit(None).cast("string"))
        .withColumn("match_type", F.lit(None).cast("string"))
        .withColumn("match_method", F.lit(None).cast("string"))
        .withColumn("match_confidence", F.lit(None).cast("decimal(5,4)"))
        .withColumn("_match_index", F.lit(seed % 7 + 1))
        .withColumn("channel_code", F.lit("online"))
        .withColumn("is_listed", F.pmod(F.col("_date_index"), F.lit(5)) != 0)
        .withColumn(
            "is_available",
            F.when(F.col("is_listed"), F.lit(True)).otherwise(F.lit(None).cast("boolean")),
        )
    )

    observations = matched.select(unmatched.columns).unionByName(unmatched)
    return (
        observations
        .withColumn("competitor_location_ref", F.lit("ALL"))
        .withColumn("observed_at_ts", F.col("date_key").cast("timestamp") + F.expr("INTERVAL 12 HOURS"))
        .withColumn("search_rank", (F.pmod(F.abs(F.hash("competitor_item_ref", F.lit(seed))), F.lit(50)) + 1).cast("int"))
        .withColumn(
            "marketplace_seller",
            F.when(F.col("channel_code") == "marketplace", F.concat_ws("-", F.lit("SELLER"), F.col("competitor_id")))
            .otherwise(F.lit(None).cast("string")),
        )
        .withColumn("data_source", F.lit("synthetic_observation"))
        .withColumn("raw_data_uri", F.lit(None).cast("string"))
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn(
            "source_observation_id",
            F.concat_ws("|", F.lit("ASSORT"), F.col("competitor_id"), F.col("competitor_item_ref"),
                        F.col("competitor_location_ref"), F.col("channel_code"),
                        F.date_format("date_key", "yyyyMMdd")),
        )
        .withColumn("competitor_assortment_id", F.concat_ws("|", F.col("record_source"), F.col("source_observation_id")))
        .withColumn("load_timestamp", F.col("observed_at_ts") + F.expr("INTERVAL 1 HOUR"))
    )


def build_competitor_promotions(matches, dated_calendar, seed, base_currency):
    promo_dates = dated_calendar.where(F.pmod(F.col("_date_index"), F.lit(4)) == 1)
    return (
        matches.where(F.col("match_confidence") >= F.lit(0.80)).crossJoin(promo_dates)
        .withColumn("category_ref", F.coalesce(F.col("category"), F.lit("unclassified")))
        .withColumn("competitor_location_ref", F.lit("ALL"))
        .withColumn("channel_code", _element(CHANNELS, F.pmod(F.col("_match_index"), F.lit(len(CHANNELS)))))
        .withColumn("promo_vehicle", _element(PROMO_VEHICLES, F.pmod(F.col("_match_index") + F.col("_date_index"), F.lit(len(PROMO_VEHICLES)))))
        .withColumn("promo_type", _element(PROMO_TYPES, F.pmod(F.col("_match_index") + F.col("_date_index"), F.lit(len(PROMO_TYPES)))))
        .withColumn("regular_price", F.round(F.col("list_price") * F.lit(1.05), 4).cast("decimal(18,4)"))
        .withColumn("discount_depth_pct", (F.lit(10) + F.pmod(F.col("_match_index") * 5, F.lit(30))).cast("decimal(5,2)"))
        .withColumn(
            "promo_price",
            F.round(F.col("regular_price") * (F.lit(1.0) - F.col("discount_depth_pct") / F.lit(100.0)), 4).cast("decimal(18,4)"),
        )
        .withColumn("promo_start_date", F.col("date_key"))
        .withColumn("promo_end_date", F.date_add("date_key", 6))
        .withColumn("observed_at_ts", F.col("date_key").cast("timestamp") + F.expr("INTERVAL 8 HOURS"))
        .withColumn("placement_rank", (F.pmod(F.abs(F.hash("competitor_item_ref", F.lit(seed))), F.lit(12)) + 1).cast("int"))
        .withColumn("is_front_page", F.col("placement_rank") <= 2)
        .withColumn("currency_code", F.lit(base_currency))
        .withColumn(
            "transaction_currency_code",
            F.when(F.pmod(F.col("_match_index"), F.lit(7)) == 0, F.lit("CAD")).otherwise(F.lit(base_currency)),
        )
        .withColumn("data_source", F.lit("synthetic_observation"))
        .withColumn("raw_data_uri", F.lit(None).cast("string"))
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn(
            "source_observation_id",
            F.concat_ws("|", F.lit("PROMO"), F.col("competitor_id"), F.col("competitor_item_ref"),
                        F.col("competitor_location_ref"), F.col("promo_vehicle"),
                        F.date_format("date_key", "yyyyMMdd")),
        )
        .withColumn("competitor_promotion_id", F.concat_ws("|", F.col("record_source"), F.col("source_observation_id")))
        .withColumn("load_timestamp", F.col("observed_at_ts") + F.expr("INTERVAL 1 HOUR"))
    )


def _benchmark_base(frame, base_currency):
    return (
        frame
        .withColumn("market_definition", F.lit("measured_market"))
        .withColumn("geography_level", F.lit("total"))
        .withColumn("geography_code", F.lit("NATIONAL"))
        .withColumn("period_type", F.lit("quad_week"))
        .withColumn("unit_volume", F.round(F.col("sales_amount") / F.lit(4.0), 2).cast("decimal(18,2)"))
        .withColumn("market_growth_rate_pct", F.lit(2.5).cast("decimal(7,4)"))
        .withColumn("eq_volume", F.round(F.col("unit_volume") * F.lit(1.08), 2).cast("decimal(18,2)"))
        .withColumn("acv_weighted_distribution_pct", F.lit(None).cast("decimal(7,4)"))
        .withColumn("numeric_distribution_pct", F.lit(None).cast("decimal(7,4)"))
        .withColumn("tdp", F.lit(None).cast("decimal(18,4)"))
        .withColumn("promo_sales_amount", F.round(F.col("sales_amount") * F.lit(0.22), 2).cast("decimal(18,2)"))
        .withColumn("base_sales_amount", F.round(F.col("sales_amount") * F.lit(0.78), 2).cast("decimal(18,2)"))
        .withColumn("currency_code", F.lit(base_currency))
        .withColumn("is_restatement", F.lit(False))
        .withColumn("restates_market_benchmark_id", F.lit(None).cast("string"))
        .withColumn("record_source", F.lit(RECORD_SOURCE))
        .withColumn(
            "benchmark_cell_id",
            F.concat_ws("|", "record_source", "market_definition", "geography_level",
                        "geography_code", "category_ref",
                        "subject_type", F.coalesce("subject_id", F.lit("TOTAL")), "period_type",
                        F.date_format("period_end_date", "yyyyMMdd")),
        )
        .withColumn("source_observation_id", F.concat_ws("|", F.col("benchmark_cell_id"), F.lit("V1")))
        .withColumn("market_benchmark_id", F.concat_ws("|", F.col("record_source"), F.col("source_observation_id")))
        .withColumn("observed_at_ts", F.col("period_end_date").cast("timestamp") + F.expr("INTERVAL 10 DAYS"))
        .withColumn("provider_updated_at_ts", F.col("observed_at_ts"))
        .withColumn("raw_data_uri", F.lit(None).cast("string"))
        .withColumn("load_timestamp", F.col("observed_at_ts") + F.expr("INTERVAL 1 HOUR"))
    )


def build_market_benchmarks(competitors_current, products_current, dated_calendar, base_currency):
    periods = dated_calendar.where(F.pmod(F.col("_date_index"), F.lit(4)) == 1).select(
        F.col("date_key").alias("period_end_date")
    )
    categories = products_current.select(F.coalesce("category", F.lit("unclassified")).alias("category_ref")).distinct()
    cells = categories.crossJoin(periods).withColumn(
        "market_size", (F.lit(100000) + F.pmod(F.abs(F.hash("category_ref", "period_end_date")), F.lit(50000))).cast("decimal(18,2)")
    )

    totals = _benchmark_base(
        cells
        .withColumn("competitor_sk", F.lit(None).cast("long"))
        .withColumn("competitor_id", F.lit(None).cast("string"))
        .withColumn("subject_type", F.lit("total_category"))
        .withColumn("subject_id", F.lit(None).cast("string"))
        .withColumn("market_share_pct", F.lit(100.0).cast("decimal(7,4)"))
        .withColumn("sales_amount", F.col("market_size")),
        base_currency,
    )

    own = _benchmark_base(
        cells
        .withColumn("competitor_sk", F.lit(None).cast("long"))
        .withColumn("competitor_id", F.lit(None).cast("string"))
        .withColumn("subject_type", F.lit("own_banner"))
        .withColumn("subject_id", F.lit("OWN"))
        .withColumn("market_share_pct", F.lit(25.0).cast("decimal(7,4)"))
        .withColumn("sales_amount", F.round(F.col("market_size") * F.lit(0.25), 2).cast("decimal(18,2)")),
        base_currency,
    )

    competitor_count = competitors_current.agg(F.count(F.lit(1)).alias("competitor_count"))
    rivals = _benchmark_base(
        cells.crossJoin(competitors_current.select("competitor_sk", "competitor_id")).crossJoin(competitor_count)
        .withColumn("subject_type", F.lit("competitor_banner"))
        .withColumn("subject_id", F.col("competitor_id"))
        .withColumn("market_share_pct", (F.lit(40.0) / F.col("competitor_count")).cast("decimal(7,4)"))
        .withColumn("sales_amount", F.round(F.col("market_size") * F.col("market_share_pct") / F.lit(100.0), 2).cast("decimal(18,2)")),
        base_currency,
    )

    base = totals.select(MARKET_BENCHMARK_COLUMNS).unionByName(
        own.select(MARKET_BENCHMARK_COLUMNS)
    ).unionByName(rivals.select(MARKET_BENCHMARK_COLUMNS))

    first_own_cell = own.agg(
        F.min(F.struct("category_ref", "period_end_date")).alias("_first_cell")
    )
    restatement = (
        own.crossJoin(first_own_cell)
        .where(
            (F.col("category_ref") == F.col("_first_cell.category_ref"))
            & (F.col("period_end_date") == F.col("_first_cell.period_end_date"))
        )
        .withColumn("restates_market_benchmark_id", F.col("market_benchmark_id"))
        .withColumn("source_observation_id", F.concat_ws("|", F.col("benchmark_cell_id"), F.lit("V2")))
        .withColumn("market_benchmark_id", F.concat_ws("|", F.col("record_source"), F.col("source_observation_id")))
        .withColumn("is_restatement", F.lit(True))
        .withColumn("market_share_pct", (F.col("market_share_pct") + F.lit(1.0)).cast("decimal(7,4)"))
        .withColumn("sales_amount", F.round(F.col("market_size") * F.col("market_share_pct") / F.lit(100.0), 2).cast("decimal(18,2)"))
        .withColumn("unit_volume", F.round(F.col("sales_amount") / F.lit(4.0), 2).cast("decimal(18,2)"))
        .withColumn("promo_sales_amount", F.round(F.col("sales_amount") * F.lit(0.22), 2).cast("decimal(18,2)"))
        .withColumn("base_sales_amount", F.round(F.col("sales_amount") * F.lit(0.78), 2).cast("decimal(18,2)"))
        .withColumn("market_growth_rate_pct", (F.col("market_growth_rate_pct") + F.lit(0.2)).cast("decimal(7,4)"))
        .withColumn("provider_updated_at_ts", F.col("provider_updated_at_ts") + F.expr("INTERVAL 1 DAY"))
        .withColumn("observed_at_ts", F.col("observed_at_ts") + F.expr("INTERVAL 1 DAY"))
        .withColumn("load_timestamp", F.col("load_timestamp") + F.expr("INTERVAL 1 DAY"))
        .select(MARKET_BENCHMARK_COLUMNS)
    )
    return base.unionByName(restatement)


def build_market_analysis_frames(spark, competitors_current, products_current, calendar_df, seed, base_currency):
    del spark  # transformations use the supplied DataFrames' session
    dated_calendar = _dated_calendar(calendar_df)
    matches = build_competitor_product_matches(
        competitors_current, products_current, dated_calendar
    )
    return {
        "competitor_product_match": matches.select(COMPETITOR_PRODUCT_MATCH_COLUMNS),
        "competitor_assortment": build_competitor_assortment(
            matches, competitors_current, products_current, dated_calendar, seed
        ).select(COMPETITOR_ASSORTMENT_COLUMNS),
        "competitor_promotion": build_competitor_promotions(
            matches, dated_calendar, seed, base_currency
        ).select(COMPETITOR_PROMOTION_COLUMNS),
        "market_benchmark": build_market_benchmarks(
            competitors_current, products_current, dated_calendar, base_currency
        ).select(MARKET_BENCHMARK_COLUMNS),
    }


def generate_market_analysis(spark, catalog, schemas, seed, base_currency, mode):
    def fq(schema, table):
        return f"{catalog}.{schemas[schema]}.{table}"

    competitors_current = spark.table(fq("bmv", "competitor")).where("is_current = true")
    products_current = spark.table(fq("product", "product")).where("is_current = true")
    calendar_df = spark.table(fq("calendar", "fiscal_calendar"))
    frames = build_market_analysis_frames(
        spark, competitors_current, products_current, calendar_df, seed, base_currency
    )
    _write(
        spark, frames["competitor_product_match"], fq("acu", "competitor_product_match"),
        COMPETITOR_PRODUCT_MATCH_COLUMNS, mode,
    )
    _write(
        spark, frames["competitor_assortment"], fq("acu", "competitor_assortment"),
        COMPETITOR_ASSORTMENT_COLUMNS, mode,
    )
    _write(
        spark, frames["competitor_promotion"], fq("acu", "competitor_promotion"),
        COMPETITOR_PROMOTION_COLUMNS, mode,
    )
    _write(
        spark, frames["market_benchmark"], fq("acu", "market_benchmark"),
        MARKET_BENCHMARK_COLUMNS, mode,
    )
