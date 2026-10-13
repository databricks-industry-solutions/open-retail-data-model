# ============================================================
# ORDM · Synthetic data · Trade Promotion use case generator
# Version: 0.5
# Generated: 2026-06-09
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-06-09
# ============================================================
# Populates the Trade Promotion use case end to end:
#   canonical-core: product, store, fiscal_calendar, sales, promotion (+ NO_PROMO member)
#   promote-with-purpose: promotion_scope, gold_trade_promotion (metric view)
# and the Location-Based Offers use case:
#   promote-with-purpose: offer_zone, location_offer, offer_event
#
# The offer tables are built HERE rather than in a location_based_offers module
# because _registry.py allows exactly one provider per schema key and this
# generator already declares `promo` in its `provides` set. A second generator
# claiming `promo` makes topo_sort()/waves() raise ValueError.
# and stamps a subset of sales-fact rows with promo_sk inside each promo's
# date + scope window, so promoted and non-promoted sales both exist.
#
# Engine: dbldatagen for high-volume entities (product, store), PySpark for
# the calendar and the relational/attribution work, and a small seeded
# driver-side build for the promotion calendar (seasonal, windowed). All
# volumes come from runtime/synthetic-data/seeds.yaml (no hardcoded magic numbers).
# Shared helpers come from _common (the generator framework is extended,
# not forked).
# ============================================================

import datetime
import os
import random
import sys

import dbldatagen as dg
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql import types as T
from pyspark.sql.window import Window

try:
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _write,
                         attach_random_dim, shelf_space_multiplier, BEHAVIORAL_SEGMENT_IDS)
except ImportError:  # ensure sibling modules are importable when run as a notebook
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _write,
                         attach_random_dim, shelf_space_multiplier, BEHAVIORAL_SEGMENT_IDS)

# ------------------------------------------------------------
# Column contracts — MUST match the table DDL (minus IDENTITY *_sk).
# Verified against the DDL by tests/test_trade_promotion.py.
# ------------------------------------------------------------
PRODUCT_COLUMNS = [
    "product_id", "gtin", "sku", "style_id", "color", "size", "product_name",
    "brand", "category", "subcategory", "department", "unit_of_measure",
    "list_price", "unit_cost", "currency_code", "transaction_currency_code",
    "product_status", "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
PRODUCT_PRICE_COLUMNS = [
    "product_price_id", "product_sk", "product_id", "price_type", "amount",
    "currency_code", "transaction_currency_code", "effective_from_date",
    "effective_to_date", "is_current", "created_timestamp",
    "source_updated_timestamp", "record_source", "load_timestamp",
]
FX_RATE_COLUMNS = [
    "fx_rate_id", "date_key", "from_currency_code", "to_currency_code",
    "rate", "created_timestamp", "source_updated_timestamp",
    "record_source", "load_timestamp",
]
STORE_COLUMNS = [
    "store_id", "gln", "store_name", "store_format", "region", "district",
    "city", "state_province", "country_code", "open_date", "store_status",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp",
    "record_source", "load_timestamp",
]
FISCAL_CALENDAR_COLUMNS = [
    "date_key", "date_id", "calendar_year", "calendar_month", "calendar_day",
    "day_of_week", "day_name", "is_weekend", "is_holiday", "fiscal_year",
    "fiscal_quarter", "fiscal_period", "fiscal_season", "fiscal_week", "fiscal_week_id",
    "fiscal_week_index", "fiscal_week_start_date", "fiscal_week_end_date",
    "created_timestamp", "source_updated_timestamp",
    "record_source", "load_timestamp",
]
SALES_COLUMNS = [
    "sales_id", "date_key", "product_sk", "product_id", "store_sk",
    "store_id", "promo_sk", "promo_id", "units", "gross_revenue",
    "discount_amount", "net_revenue", "currency_code", "transaction_currency_code",
    "record_source", "load_timestamp",
]
PROMOTION_COLUMNS = [
    "promo_id", "promo_name", "promo_type", "funding_type", "funded_by",
    "supplier_share_pct", "start_date", "end_date", "fiscal_week_start",
    "fiscal_week_end", "planned_discount_pct", "planned_lift_pct",
    "planned_trade_spend", "effective_from_date", "effective_to_date",
    "is_current", "created_timestamp", "source_updated_timestamp",
    "record_source", "load_timestamp",
]
PROMOTION_SCOPE_COLUMNS = [
    "scope_id", "promo_sk", "promo_id", "product_sk", "product_id",
    "store_sk", "store_id", "record_source", "load_timestamp",
]
# Location-Based Offers (promote-with-purpose). These live here, not in a module of
# their own, because the registry allows exactly ONE provider per schema key and this
# generator already provides `promo` — see the module docstring.
OFFER_ZONE_COLUMNS = [
    "zone_id", "store_id", "zone_type", "radius_m", "centroid_geohash7",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
LOCATION_OFFER_COLUMNS = [
    "location_offer_id", "promotion_id", "zone_sk", "trigger_type",
    "min_dwell_seconds", "daily_trigger_cap", "suppression_window_hours",
    "channel", "offer_start_ts", "offer_end_ts", "status",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
OFFER_EVENT_COLUMNS = [
    "offer_event_id", "location_offer_sk", "customer_id", "store_id",
    "event_ts", "event_type", "suppression_reason", "transaction_id",
    "consent_verified", "record_source", "load_timestamp",
]

# Enum domains — every literal below must be a subset of the CHECK constraints in
# outcome-packages/promote-with-purpose/relationships.sql (asserted by
# tests/test_location_based_offers.py).
ZONE_TYPES = ["store_radius", "polygon", "beacon", "mall_common_area"]
TRIGGER_TYPES = ["geofence_enter", "geofence_exit", "dwell", "beacon_proximity"]
OFFER_CHANNELS = ["push", "sms", "email", "in_app"]
OFFER_STATUSES = ["draft", "active", "paused", "ended"]
OFFER_EVENT_TYPES = ["triggered", "suppressed", "delivered", "opened", "redeemed"]
SUPPRESSION_REASONS = ["no_consent", "daily_cap", "quiet_hours", "frequency_window"]
# Crockford base32 minus i/l/o/u — the geohash alphabet. centroid_geohash7 is derived
# deterministically from the seed and the anchor store key, never from a coordinate.
GEOHASH_ALPHABET = "0123456789bcdefghjkmnpqrstuvwxyz"
# audience / segment-definition dimension (promoted to shared silver marketing, ADR 0022).
AUDIENCE_COLUMNS = [
    "audience_id", "audience_name", "audience_type", "audience_origin",
    "definition_description", "size_estimate", "is_addressable_flag",
    "segmentation_basis", "definition_origin", "definition_method",
    "criteria_expression", "evaluation_mode", "iab_taxonomy_code",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
AUDIENCE_TYPES = ["first_party", "modeled", "lookalike", "demographic", "behavioral", "contextual", "retargeting", "custom"]
AUDIENCE_ORIGINS = ["crm", "loyalty", "modeled", "third_party", "platform", "survey"]
N_RETAIL_MEDIA_AUDIENCES = 12  # generic retail-media targeting audiences (legacy CMN shape)
# ------------------------------------------------------------
# Vocabularies (enum domains match the DDL "Allowed values").
# ------------------------------------------------------------
PROMO_TYPES = ["TPR", "FEATURE", "DISPLAY", "FEATURE_AND_DISPLAY", "BOGO", "COUPON", "BUNDLE"]
FUNDING_TYPES = ["OFF_INVOICE", "BILL_BACK", "SCAN_DOWN", "LUMP_SUM"]
FUNDED_BY = ["SUPPLIER", "RETAILER", "SHARED"]
PRODUCT_STATUS = ["active", "inactive", "discontinued"]
STORE_STATUS = ["active", "inactive", "closed"]
STORE_FORMATS = ["hypermarket", "supermarket", "convenience", "drugstore", "online"]
UNITS_OF_MEASURE = ["each", "kg", "g", "l", "ml", "pack"]
CATEGORIES = ["beverages", "snacks", "dairy", "bakery", "household", "personal_care"]
SUBCATEGORIES = ["regular", "premium", "value", "organic"]
DEPARTMENTS = ["grocery", "fresh", "non_food", "health_beauty"]
BRANDS = ["brand_a", "brand_b", "brand_c", "brand_d", "private_label"]
REGIONS = ["north", "south", "east", "west", "central"]
COUNTRY_CODES = ["US", "CA", "GB", "FR", "DE"]
CURRENCIES = ["USD", "EUR", "GBP", "CAD"]
COLORS = ["red", "blue", "green", "black", "white", "natural"]
SIZES = ["xs", "s", "m", "l", "xl", "500ml", "1l"]
PRICE_TYPES = ["list", "cost", "promotional", "contract"]
# Representative source -> USD rates. The fx_rate dimension is the conversion
# reference an ingest pipeline would use; synthetic monetary columns are already
# emitted in base, so these populate fx_rate for completeness/auditing.
FX_TO_USD = {"USD": 1.0, "EUR": 1.08, "GBP": 1.27, "CAD": 0.74}


NO_PROMO_ID = "NO_PROMO"


# ------------------------------------------------------------
# Config
# ------------------------------------------------------------
def load_config():
    c = load_domain_config("trade_promotion")
    vols = c.get("volumes", {}) or {}
    fan = c.get("fanout", {}) or {}
    seas = c.get("seasonality", {}) or {}
    post = c.get("post_promo", {}) or {}
    return {
        "seed": c.get("seed", 2002),
        "products": vols.get("products", 120),
        "stores": vols.get("stores", 30),
        "promotions": vols.get("promotions", 60),
        "calendar_start_date": vols.get("calendar_start_date", "2024-01-07"),
        "calendar_weeks": vols.get("calendar_weeks", 110),
        "daily_sales_density": vols.get("daily_sales_density", 0.06),
        "zones": vols.get("zones", 40),
        "location_offers": vols.get("location_offers", 25),
        "offer_events_per_offer_max": vols.get("offer_events_per_offer_max", 400),
        "scope_products_max": fan.get("scope_products_per_promo_max", 15),
        "scope_stores_max": fan.get("scope_stores_per_promo_max", 12),
        "promo_duration_weeks_max": fan.get("promo_duration_weeks_max", 4),
        "quarter_weights": seas.get("quarter_weights", [2, 1, 1, 4]),
        "forward_buy_weeks": post.get("forward_buy_weeks", 2),
        "forward_buy_dip_factor": post.get("forward_buy_dip_factor", 0.55),
        "cannibalization_dip_factor": post.get("cannibalization_dip_factor", 0.70),
    }


# ------------------------------------------------------------
# Fiscal calendar (NRF 4-5-4), day grain, built in PySpark from a day index.
#
# SIMPLIFICATION: this models a fixed 52-week (4-5-4) fiscal year and does NOT
# insert the NRF 53rd "leap" week that occurs roughly every 5-6 years. For the
# synthetic demo calendar this is acceptable, but it means multi-year spans can
# drift from the official NRF calendar at year boundaries. A real deployment
# should source an authoritative 4-5-4 calendar (incl. 53-week years). The
# calendar DQ check `calendar_weeks_per_year_4_5_4` reports any fiscal year that
# is not 52 or 53 weeks so this assumption is visible, not silent.
# ------------------------------------------------------------
def build_fiscal_calendar(spark, start_date_str, weeks, seed):
    base_year = int(start_date_str[:4])
    n_days = weeks * 7
    df = spark.range(0, n_days).withColumnRenamed("id", "day_offset")
    start = F.to_date(F.lit(start_date_str))
    w = (F.col("day_offset") / F.lit(7)).cast("int")          # 0-based week index
    ww = (w % F.lit(52)) + F.lit(1)                            # week within fiscal year (1..52; see note: no 53rd week)
    quarter = ((ww - F.lit(1)) / F.lit(13)).cast("int") + F.lit(1)
    wiq = ((ww - F.lit(1)) % F.lit(13)) + F.lit(1)            # week within quarter (1..13)
    period_in_q = (F.when(wiq <= F.lit(4), F.lit(1))
                    .when(wiq <= F.lit(9), F.lit(2))
                    .otherwise(F.lit(3)))
    fiscal_year = F.lit(base_year) + (w / F.lit(52)).cast("int")
    return (df
            .withColumn("date_key", F.date_add(start, F.col("day_offset").cast("int")))
            # Durable STRING business key: date rendered ISO 8601 (yyyy-MM-dd).
            .withColumn("date_id", F.date_format("date_key", "yyyy-MM-dd"))
            .withColumn("_w", w)
            .withColumn("calendar_year", F.year("date_key"))
            .withColumn("calendar_month", F.month("date_key"))
            .withColumn("calendar_day", F.dayofmonth("date_key"))
            # ISO day of week (1=Mon..7=Sun) from Spark dayofweek (1=Sun..7=Sat)
            .withColumn("_dow", F.dayofweek("date_key"))
            .withColumn("day_of_week", F.when(F.col("_dow") == 1, F.lit(7)).otherwise(F.col("_dow") - 1))
            .withColumn("day_name", F.lower(F.date_format("date_key", "EEEE")))
            .withColumn("is_weekend", F.col("_dow").isin(1, 7))
            .withColumn("is_holiday",
                        ((F.col("calendar_month") == 12) & (F.col("calendar_day") == 25)) |
                        ((F.col("calendar_month") == 1) & (F.col("calendar_day") == 1)))
            .withColumn("fiscal_year", fiscal_year)
            .withColumn("fiscal_quarter", quarter)
            .withColumn("fiscal_period", (quarter - F.lit(1)) * F.lit(3) + period_in_q)
            # fiscal_season: retail half-year merchandising season derived from fiscal_period
            # (spring = periods 1-6 / fiscal H1, fall = periods 7-12 / fiscal H2). Conformed here
            # so consumers group by season without re-deriving it (issue #102).
            .withColumn("fiscal_season",
                        F.when(((quarter - F.lit(1)) * F.lit(3) + period_in_q) <= F.lit(6), F.lit("spring"))
                         .otherwise(F.lit("fall")))
            .withColumn("fiscal_week", ww)
            .withColumn("fiscal_week_id", F.col("fiscal_year") * F.lit(100) + ww)
            .withColumn("fiscal_week_index", F.col("_w") + F.lit(1))
            .withColumn("fiscal_week_start_date", F.date_add(start, F.col("_w") * F.lit(7)))
            .withColumn("fiscal_week_end_date", F.date_add(start, F.col("_w") * F.lit(7) + F.lit(6)))
            # Static generated reference: created/source-updated at generation time.
            .withColumn("created_timestamp", F.current_timestamp())
            .withColumn("source_updated_timestamp", F.current_timestamp())
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


# ------------------------------------------------------------
# Product / store masters (dbldatagen)
# ------------------------------------------------------------
def build_products(spark, n, seed, base_currency):
    spec = (
        dg.DataGenerator(spark, name="product", rows=n, partitions=4,
                         randomSeedMethod="fixed", randomSeed=seed)
        .withColumn("product_id", "string", expr="concat('SKU-', lpad(cast(id as string), 8, '0'))")
        .withColumn("gtin", "string", expr="lpad(cast((id * 13 + 100000000000) as string), 13, '0')")
        .withColumn("sku", "string", expr="concat('S', lpad(cast(id as string), 7, '0'))")
        # Variant hierarchy: every ~3 consecutive SKUs share a style; colour/size
        # are the variant-defining attributes (product -> style -> SKU).
        .withColumn("style_id", "string", expr="concat('STY-', lpad(cast(cast(id / 3 as int) as string), 6, '0'))")
        .withColumn("color", "string", values=COLORS)
        .withColumn("size", "string", values=SIZES)
        .withColumn("product_name", "string", expr="concat('Product ', lpad(cast(id as string), 6, '0'))")
        .withColumn("brand", "string", values=BRANDS)
        .withColumn("category", "string", values=CATEGORIES)
        .withColumn("subcategory", "string", values=SUBCATEGORIES)
        .withColumn("department", "string", values=DEPARTMENTS)
        .withColumn("unit_of_measure", "string", values=UNITS_OF_MEASURE)
        .withColumn("_price", "int", minValue=99, maxValue=4999, omit=True)
        # Unit-grain prices/costs are DECIMAL(18,4) (principle #9d).
        .withColumn("list_price", "decimal(18,4)", expr="cast(_price as decimal(18,4)) / 100")
        # Unit cost = 50-92% of list price (deterministic per product), so per-unit
        # margin is positive but compresses under deep promotional discounts. The top
        # of the range (cost > 85% of list) gives a tail of thin-margin SKUs (<15%
        # gross margin, the 'Low' margin bucket) that assortment DROP rules act on.
        .withColumn("_cost_ratio", "int", minValue=50, maxValue=92, omit=True)
        .withColumn("unit_cost", "decimal(18,4)", expr="cast(_price * _cost_ratio as decimal(18,4)) / 10000")
        # list_price/unit_cost are already in the reporting/base currency (normalized
        # at ingest); transaction_currency_code records the original sourcing currency
        # (products are sourced internationally) for lineage only.
        .withColumn("transaction_currency_code", "string", values=CURRENCIES)
        .withColumn("currency_code", "string", expr=f"'{base_currency}'")
        .withColumn("product_status", "string", values=PRODUCT_STATUS, weights=[90, 7, 3])
    )
    return _stamp_scd2(spec.build(), "2018-01-01")


def build_product_price(spark, products_current, base_currency):
    """Price history rows mirroring the product dim's current list / cost
    snapshot (one current version per product x price_type). The table supports
    full SCD2 history; the synthetic seed emits the current snapshot."""
    # product_sk is the foreign surrogate FK to product.product_sk, resolved AS OF
    # the price's effective_from_date. The synthetic seed emits the current price
    # snapshot mirrored from the current product version, so product_sk is that
    # version's surrogate (as-of == current here). Carried through from products_current.
    priced = products_current.select(
        "product_sk", "product_id", "transaction_currency_code", "effective_from_date",
        F.expr("stack(2, 'list', list_price, 'cost', unit_cost) as (price_type, amount)"))
    return (priced
            .withColumn("amount", F.col("amount").cast("decimal(18,4)"))
            .withColumn("currency_code", F.lit(base_currency))
            .withColumn("product_price_id",
                        F.concat_ws("|", F.col("product_id"), F.col("price_type"),
                                    F.col("effective_from_date")))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_fx_rate(spark, calendar_df, base_currency, seed):
    """Daily from->base FX rates for every source currency (incl. the base
    self-rate = 1). The conversion reference for currency normalization."""
    rates = spark.createDataFrame(
        [(ccy, float(r)) for ccy, r in FX_TO_USD.items()],
        "from_currency_code string, rate double")
    days = calendar_df.select("date_key").distinct()
    return (days.crossJoin(rates)
            .withColumn("to_currency_code", F.lit(base_currency))
            .withColumn("rate", F.col("rate").cast("decimal(18,8)"))
            .withColumn("fx_rate_id", F.concat_ws("|", F.col("date_key"),
                                                  F.col("from_currency_code"),
                                                  F.col("to_currency_code")))
            # Static generated reference: created/source-updated at generation time.
            .withColumn("created_timestamp", F.current_timestamp())
            .withColumn("source_updated_timestamp", F.current_timestamp())
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_stores(spark, n, seed):
    spec = (
        dg.DataGenerator(spark, name="store", rows=n, partitions=2,
                         randomSeedMethod="fixed", randomSeed=seed)
        .withColumn("store_id", "string", expr="concat('STR-', lpad(cast(id as string), 5, '0'))")
        .withColumn("gln", "string", expr="lpad(cast((id * 7 + 200000000000) as string), 13, '0')")
        .withColumn("store_name", "string", expr="concat('Store ', lpad(cast(id as string), 4, '0'))")
        .withColumn("store_format", "string", values=STORE_FORMATS)
        .withColumn("region", "string", values=REGIONS)
        .withColumn("district", "string", expr="concat('D', lpad(cast(id % 20 as string), 3, '0'))")
        .withColumn("city", "string", expr="concat('City ', cast(id % 50 as string))")
        .withColumn("state_province", "string", expr="concat('S', lpad(cast(id % 30 as string), 2, '0'))")
        .withColumn("country_code", "string", values=COUNTRY_CODES)
        .withColumn("_open_off", "int", minValue=0, maxValue=3650, omit=True)
        .withColumn("open_date", "date", expr="date_add(date'2010-01-01', _open_off)")
        .withColumn("store_status", "string", values=STORE_STATUS, weights=[92, 5, 3])
    )
    return _stamp_scd2(spec.build(), "2010-01-01")


def _stamp_scd2(df, eff_from):
    return (df
            .withColumn("effective_from_date", F.lit(eff_from).cast("date"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            # Standard audit block (UTC). Source-system instants approximated by
            # the version's effective date; load is the pipeline instant.
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


# ------------------------------------------------------------
# Promotion calendar (seeded, seasonal, windowed) — built driver-side.
# ------------------------------------------------------------
# Decimal columns are declared DoubleType here and cast to their target
# DECIMAL precision/scale after createDataFrame: under Spark Connect the local
# Arrow conversion asserts DecimalType values are python decimal.Decimal (it will
# NOT coerce a python float), so we feed doubles and cast in-DataFrame — the same
# double-then-cast pattern used by build_fx_rate.
_PROMO_SCHEMA = T.StructType([
    T.StructField("promo_id", T.StringType()),
    T.StructField("promo_name", T.StringType()),
    T.StructField("promo_type", T.StringType()),
    T.StructField("funding_type", T.StringType()),
    T.StructField("funded_by", T.StringType()),
    T.StructField("supplier_share_pct", T.DoubleType()),
    T.StructField("start_date", T.DateType()),
    T.StructField("end_date", T.DateType()),
    T.StructField("fiscal_week_start", T.IntegerType()),
    T.StructField("fiscal_week_end", T.IntegerType()),
    T.StructField("planned_discount_pct", T.DoubleType()),
    T.StructField("planned_lift_pct", T.DoubleType()),
    T.StructField("planned_trade_spend", T.DoubleType()),
])


def build_promotions(spark, weeks_rows, n, seed, duration_max, quarter_weights, calendar_start):
    """weeks_rows: list of dicts with fiscal_week_id, fiscal_week_index,
    fiscal_quarter, fiscal_week_start_date, fiscal_week_end_date."""
    rnd = random.Random(seed)
    weeks = sorted(weeks_rows, key=lambda r: r["fiscal_week_index"])
    by_index = {r["fiscal_week_index"]: r for r in weeks}
    max_index = max(by_index)
    # Seasonality: weight each week by its quarter's weight.
    weighted = []
    for r in weeks:
        wgt = quarter_weights[(r["fiscal_quarter"] - 1) % len(quarter_weights)]
        weighted.extend([r["fiscal_week_index"]] * int(wgt))

    rows = []
    # Reserved no-promotion member.
    rows.append((NO_PROMO_ID, "No Promotion", None, None, None, None,
                 None, None, None, None, None, None, None))
    for i in range(1, n + 1):
        start_idx = rnd.choice(weighted)
        dur = rnd.randint(1, duration_max)
        end_idx = min(start_idx + dur - 1, max_index)
        sw, ew = by_index[start_idx], by_index[end_idx]
        fby = rnd.choice(FUNDED_BY)
        if fby == "RETAILER":
            share = None
        elif fby == "SUPPLIER":
            share = round(rnd.uniform(80, 100), 2)
        else:  # SHARED
            share = round(rnd.uniform(30, 70), 2)
        rows.append((
            f"PROMO-{i:05d}",
            f"Promotion {i:05d}",
            rnd.choice(PROMO_TYPES),
            rnd.choice(FUNDING_TYPES),
            fby,
            share,
            sw["fiscal_week_start_date"],
            ew["fiscal_week_end_date"],
            sw["fiscal_week_id"],
            ew["fiscal_week_id"],
            round(rnd.uniform(5, 40), 2),
            round(rnd.uniform(10, 120), 2),
            round(rnd.uniform(1000, 50000), 2),
        ))
    df = spark.createDataFrame(rows, schema=_PROMO_SCHEMA)
    # Cast the double staging columns back to their DDL DECIMAL precision/scale.
    df = (df
          .withColumn("supplier_share_pct", F.col("supplier_share_pct").cast("decimal(5,2)"))
          .withColumn("planned_discount_pct", F.col("planned_discount_pct").cast("decimal(5,2)"))
          .withColumn("planned_lift_pct", F.col("planned_lift_pct").cast("decimal(6,2)"))
          .withColumn("planned_trade_spend", F.col("planned_trade_spend").cast("decimal(18,2)")))
    # SCD2: effective from the promo start (or calendar start for NO_PROMO).
    return (df
            .withColumn("effective_from_date",
                        F.coalesce(F.col("start_date"), F.lit(calendar_start).cast("date")))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            # Standard audit block (UTC), consistent with _stamp_scd2: source-system
            # instants are approximated by the version's effective date.
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_promotion_scope(spark, promo_ids, product_ids, store_ids, seed,
                          products_max, stores_max):
    rnd = random.Random(seed + 1)
    rows = []
    for pid in promo_ids:
        prods = rnd.sample(product_ids, min(products_max, len(product_ids)))
        stores = rnd.sample(store_ids, min(stores_max, len(store_ids)))
        for prod in prods:
            for st in stores:
                rows.append((f"SCOPE-{pid}-{prod}-{st}", pid, prod, st))
    schema = T.StructType([
        T.StructField("scope_id", T.StringType()),
        T.StructField("promo_id", T.StringType()),
        T.StructField("product_id", T.StringType()),
        T.StructField("store_id", T.StringType()),
    ])
    return spark.createDataFrame(rows, schema=schema)


# ------------------------------------------------------------
# audience / segment-definition dimension (shared silver marketing, ADR 0022)
# ------------------------------------------------------------
# Canned behavioral segment-definition seeds. These are DOCUMENTED, externally-grounded
# EXAMPLES (IAB Audience Taxonomy Tier-1: Purchase-Intent / Interest / Demographic; classic
# RFM lifecycle grid), not an asserted ORDM-canonical taxonomy — the model ships the mechanism
# (definition catalog + attributes), and these show the shape. Definitions only: no member
# lists, no PII. criteria_expression is portable, vendor-neutral predicate text.
CANNED_SEGMENTS = [
    # (audience_id, name, type, origin, basis, method, criteria_expression, eval_mode, iab_code, description)
    ("SEG-HIGH-VALUE-REPEAT", "High-Value Repeat Buyers", "first_party", "crm", "value_rfm", "rule",
     "value_tier IN ('PLATINUM','GOLD') AND frequency >= 4", "batch", "PI",
     "Top value-tier customers with repeat purchase cadence."),
    ("SEG-LAPSING", "Lapsing Customers", "behavioral", "crm", "lifecycle", "rule",
     "lifecycle_stage = 'lapsing'", "batch", "PI",
     "Previously-active customers whose recency now exceeds their normal cadence."),
    ("SEG-CHURNED-WINBACK", "Churned - Winback Target", "behavioral", "crm", "lifecycle", "rule",
     "lifecycle_stage = 'churned'", "batch", "PI",
     "Churned customers eligible for a winback treatment."),
    ("SEG-NEW-TO-BRAND", "New-to-Brand", "behavioral", "crm", "lifecycle", "rule",
     "lifecycle_stage = 'new'", "batch", "PI",
     "Customers in their first purchase window."),
    ("SEG-DISCOUNT-DRIVEN", "Discount-Driven Shoppers", "behavioral", "crm", "behavioral", "rule",
     "promo_purchase_share_ratio >= 0.5", "batch", "I",
     "Customers whose purchases skew to promoted product."),
    ("SEG-FULL-PRICE-LOYAL", "Full-Price Loyalists", "behavioral", "crm", "behavioral", "rule",
     "promo_purchase_share_ratio < 0.1 AND frequency >= 3", "batch", "I",
     "Repeat buyers who rarely need a discount."),
    ("SEG-VIP", "VIP / Advocates", "first_party", "loyalty", "value_rfm", "rule",
     "value_tier = 'PLATINUM'", "batch", "PI",
     "Highest value-tier customers."),
    ("SEG-AT-RISK-HIGH-VALUE", "At-Risk High Value", "behavioral", "crm", "predictive", "rule",
     "churn_risk_proxy = TRUE AND value_tier IN ('PLATINUM','GOLD')", "batch", "PI",
     "High-value customers flagged at churn risk by the recency heuristic."),
]
# Guard (m2): the CANNED_SEGMENTS ids must match the shared BEHAVIORAL_SEGMENT_IDS that
# customer_ltv assigns membership to — one source of truth, so a future edit here can't
# silently orphan membership rows written by the other generator.
assert [s[0] for s in CANNED_SEGMENTS] == BEHAVIORAL_SEGMENT_IDS, \
    "CANNED_SEGMENTS ids drifted from _common.BEHAVIORAL_SEGMENT_IDS"


def build_audiences(spark, n_retail_media, seed):
    """The audience / segment-definition dimension (SCD2 current-only), promoted to
    shared silver marketing (ADR 0022). Two populations, one dimension:
      * generic retail-media targeting audiences (the legacy CMN shape) — new segment-
        definition columns left NULL, so behaviour is unchanged for CMN facts.
      * behavioral canned segment-definition seeds (CANNED_SEGMENTS) — the segment side
        the behavioral-segmentation use case (ACU) references by audience_id.
    """
    at = F.array(*[F.lit(v) for v in AUDIENCE_TYPES])
    ao = F.array(*[F.lit(v) for v in AUDIENCE_ORIGINS])
    retail_media = (spark.range(1, int(n_retail_media) + 1).withColumnRenamed("id", "k")
            .withColumn("audience_id", F.concat(F.lit("AUD-"), F.col("k").cast("string")))
            .withColumn("audience_name", F.concat(F.lit("Audience "), F.col("k").cast("string")))
            .withColumn("audience_type", F.element_at(at, (F.col("k") % F.lit(len(AUDIENCE_TYPES)) + F.lit(1)).cast("int")))
            .withColumn("audience_origin", F.element_at(ao, (F.col("k") % F.lit(len(AUDIENCE_ORIGINS)) + F.lit(1)).cast("int")))
            .withColumn("definition_description", F.lit("Synthetic retail-media audience for demonstration (no PII)."))
            .withColumn("size_estimate", (F.abs(F.hash(F.col("audience_id"), F.lit(seed))) % F.lit(900000) + F.lit(1000)).cast("bigint"))
            .withColumn("is_addressable_flag", F.lit(True))
            .withColumn("segmentation_basis", F.lit(None).cast("string"))
            .withColumn("definition_origin", F.lit(None).cast("string"))
            .withColumn("definition_method", F.lit(None).cast("string"))
            .withColumn("criteria_expression", F.lit(None).cast("string"))
            .withColumn("evaluation_mode", F.lit(None).cast("string"))
            .withColumn("iab_taxonomy_code", F.lit(None).cast("string"))
            .drop("k"))
    canned_schema = T.StructType([
        T.StructField("audience_id", T.StringType()),
        T.StructField("audience_name", T.StringType()),
        T.StructField("audience_type", T.StringType()),
        T.StructField("audience_origin", T.StringType()),
        T.StructField("segmentation_basis", T.StringType()),
        T.StructField("definition_method", T.StringType()),
        T.StructField("criteria_expression", T.StringType()),
        T.StructField("evaluation_mode", T.StringType()),
        T.StructField("iab_taxonomy_code", T.StringType()),
        T.StructField("definition_description", T.StringType()),
    ])
    canned = (spark.createDataFrame(CANNED_SEGMENTS, schema=canned_schema)
            .withColumn("audience_origin", F.lit("crm"))
            .withColumn("definition_origin", F.lit("canned"))
            .withColumn("size_estimate", F.lit(None).cast("bigint"))
            # SEG-AT-RISK-HIGH-VALUE is an analytics/watchlist segment (not for delivery),
            # so it is NOT addressable — this exercises the is_addressable_flag exclusion path
            # in gold_activatable_audience_current on seed data (every other segment is TRUE).
            .withColumn("is_addressable_flag", F.col("audience_id") != F.lit("SEG-AT-RISK-HIGH-VALUE")))
    audiences = retail_media.unionByName(canned, allowMissingColumns=True)
    return (audiences
            .withColumn("effective_from_date", F.expr("date'2024-01-01'"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", F.current_timestamp())
            .withColumn("source_updated_timestamp", F.current_timestamp())
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


# ------------------------------------------------------------
# Sales fact with promotion attribution
# ------------------------------------------------------------
# Share of products (percent) that are long-tail slow movers in every store. Their 7-day
# demand stays at or under the 20-unit 'Slow Mover' bucket, so the assortment DROP rule has
# candidates on synthetic data.
SLOW_MOVER_SHARE_PCT = 20

def build_sales(spark, calendar_df, products_current, stores_current,
                promo_windows, fb_windows, cannib_windows, no_promo_sk, seed,
                density, fb_factor, cannib_factor, base_currency):
    prod = products_current.select("product_sk", "product_id", "list_price", "category")
    stores = stores_current.select("store_sk", "store_id")
    days = calendar_df.select("date_key")
    n_p, n_s, n_d = prod.count(), stores.count(), days.count()

    # Generate exactly the density-thinned number of rows and attach a random
    # product / store / day to each via broadcast joins -- NO product x store x
    # day cartesian. Collisions (same product,store,day) are deduped downstream
    # by the attribution window, so the output is the unique selling combinations.
    n_target = max(1, int(n_p * n_s * n_d * density))
    base = spark.range(0, n_target).withColumnRenamed("id", "_rid")
    base = attach_random_dim(base, prod, n_p, "prod", seed, "_rid")
    base = attach_random_dim(base, stores, n_s, "store", seed, "_rid")
    base = attach_random_dim(base, days, n_d, "day", seed, "_rid")
    # base demand 3..20 units/day, or 1..3 for long-tail SKUs (a deterministic SLOW_MOVER_SHARE of
    # products, slow in every store), scaled by the shelf-space response: the product x store's
    # facings (the same deterministic facings the BMV planogram records) with a known per-category
    # elasticity, so the assortment space-elasticity estimator has a true value to recover.
    day_hash = F.abs(F.hash("product_id", "store_id", "date_key", F.lit(seed)))
    is_slow = F.abs(F.hash("product_id", F.lit("slow_mover"), F.lit(seed))) % F.lit(100) < F.lit(SLOW_MOVER_SHARE_PCT)
    base = base.withColumn("base_units",
                           F.when(is_slow, day_hash % F.lit(3) + F.lit(1))
                            .otherwise(day_hash % F.lit(18) + F.lit(3))
                           * shelf_space_multiplier())

    # Attribute to a promotion when the day falls inside a scoped promo window.
    matched = (base.join(
                    promo_windows,
                    on=[base.product_sk == promo_windows.w_product_sk,
                        base.store_sk == promo_windows.w_store_sk,
                        base.date_key >= promo_windows.start_date,
                        base.date_key <= promo_windows.end_date],
                    how="left")
               .drop("w_product_sk", "w_store_sk"))
    # When several promos overlap, keep the lowest promo_sk deterministically.
    pick = Window.partitionBy("product_sk", "store_sk", "date_key").orderBy(F.col("w_promo_sk").asc_nulls_last())
    matched = matched.withColumn("_rn", F.row_number().over(pick)).where("_rn = 1")

    # The two value-killers, resolved to a per (product, store, day) flag via the
    # distinct hit sets (range-joined once, so the main path stays an equi-join).
    keys = base.select("product_sk", "store_sk", "date_key")
    fb_hit = (keys.join(fb_windows,
                        on=[keys.product_sk == fb_windows.fb_product_sk,
                            keys.store_sk == fb_windows.fb_store_sk,
                            keys.date_key >= fb_windows.fb_start,
                            keys.date_key <= fb_windows.fb_end], how="inner")
              .select("product_sk", "store_sk", "date_key").distinct()
              .withColumn("_is_fb", F.lit(True)))
    cannib_hit = (keys.join(cannib_windows,
                            on=[keys.product_sk == cannib_windows.c_product_sk,
                                keys.store_sk == cannib_windows.c_store_sk,
                                keys.date_key >= cannib_windows.cstart,
                                keys.date_key <= cannib_windows.cend], how="inner")
                  .select("product_sk", "store_sk", "date_key").distinct()
                  .withColumn("_is_cannib", F.lit(True)))
    matched = (matched
               .join(fb_hit, on=["product_sk", "store_sk", "date_key"], how="left")
               .join(cannib_hit, on=["product_sk", "store_sk", "date_key"], how="left"))

    promoted = F.col("w_promo_sk").isNotNull()
    # Precedence: promoted (lift) > forward-buy dip > cannibalization dip > normal.
    mult = (F.when(promoted, F.lit(1.0) + F.col("w_lift_pct") / F.lit(100.0))
             .when(F.col("_is_fb").isNotNull(), F.lit(float(fb_factor)))
             .when(F.col("_is_cannib").isNotNull(), F.lit(float(cannib_factor)))
             .otherwise(F.lit(1.0)))
    disc_pct = F.when(promoted, F.col("w_discount_pct")).otherwise(F.lit(0.0))
    # a sales row records at least one unit (long-tail SKUs under a dip factor would otherwise round to 0)
    units = F.greatest(F.round(F.col("base_units") * mult).cast("int"), F.lit(1))
    gross = F.round(units * F.col("list_price"), 2)
    discount = F.round(gross * disc_pct / F.lit(100.0), 2)
    return (matched
            .withColumn("units", units)
            .withColumn("gross_revenue", gross)
            .withColumn("discount_amount", discount)
            .withColumn("net_revenue", F.col("gross_revenue") - F.col("discount_amount"))
            # Monetary columns are in the reporting/base currency; sales are
            # transacted in the home market (= base) so lineage equals base too.
            .withColumn("currency_code", F.lit(base_currency))
            .withColumn("transaction_currency_code", F.lit(base_currency))
            .withColumn("promo_sk", F.coalesce(F.col("w_promo_sk"), F.lit(no_promo_sk)))
            .withColumn("promo_id", F.coalesce(F.col("w_promo_id"), F.lit(NO_PROMO_ID)))
            .withColumn("sales_id", F.concat_ws("-", F.lit("SAL"), F.col("product_id"),
                                                F.col("store_id"), F.col("date_key")))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


# ------------------------------------------------------------
# Location-Based Offers (offer_zone / location_offer / offer_event)
#
# Built driver-side from a seeded RNG (volumes are in the low thousands, well
# under the ~10k threshold where dbldatagen earns its keep) so every invariant
# the DQ checks assert can be enforced at the point a row is constructed rather
# than repaired afterwards. Each rule below names the check it satisfies.
#
# PRIVACY: no coordinate, no device identifier, no location trail is generated.
# A zone is a named area with a coarse 7-char geohash centroid derived from the
# SEED and the anchor store key — not from any real position. Customers appear
# only as pseudonymous keys.
# ------------------------------------------------------------
# Pseudonymous customer keys are minted here rather than read from the customer
# domain: this generator declares no `depends_on`, so the customer tables are not
# guaranteed to exist when it runs (a dependency would mean editing _registry.py).
# offer_event.customer_id is a LOGICAL reference documented in relationships.sql,
# never a declared UC FK, and no DQ check asserts it resolves. The key shape
# matches customer.py's profile_id ('CUST-' + 8 digits) so the two line up when
# both generators have run.
N_OFFER_CUSTOMERS = 500
# Crockford base32 (I/L/O/U excluded) — the ULID alphabet.
ULID_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


def _geohash7(seed, store_id, i):
    """A deterministic 7-char geohash-alphabet string. Derived from the seed and
    the anchor store key — never from a coordinate (the package privacy floor)."""
    rng = random.Random(f"{seed}:{store_id}:{i}")
    return "".join(rng.choice(GEOHASH_ALPHABET) for _ in range(7))


def _ulid(rng):
    """A ULID-shaped opaque key. offer_event_id is the durable business key the
    EMITTING system assigns (the idempotency key for replay/de-duplication), so
    the generator stands in for that emitter."""
    return "".join(rng.choice(ULID_ALPHABET) for _ in range(26))


def build_offer_zones(spark, store_ids, n, seed):
    """One SCD2-current row per zone, each anchored to a store."""
    rng = random.Random(seed + 9101)
    effective_from = datetime.date(2024, 1, 7)
    rows = []
    for i in range(n):
        store_id = store_ids[i % len(store_ids)]
        # Cycle the four enforced zone_type values so every branch is exercised.
        zone_type = ZONE_TYPES[i % len(ZONE_TYPES)]
        # chk_offer_zone_radius: radius_m > 0 only for a radial zone, NULL otherwise.
        radius_m = rng.randint(50, 500) if zone_type == "store_radius" else None
        rows.append((f"ZONE-{i:04d}", store_id, zone_type, radius_m,
                     _geohash7(seed, store_id, i), effective_from, None, True))
    schema = T.StructType([
        T.StructField("zone_id", T.StringType(), False),
        T.StructField("store_id", T.StringType(), True),
        T.StructField("zone_type", T.StringType(), True),
        T.StructField("radius_m", T.IntegerType(), True),
        T.StructField("centroid_geohash7", T.StringType(), True),
        T.StructField("effective_from_date", T.DateType(), False),
        T.StructField("effective_to_date", T.DateType(), True),
        T.StructField("is_current", T.BooleanType(), False),
    ])
    return (spark.createDataFrame(rows, schema)
            .withColumn("created_timestamp", F.current_timestamp())
            .withColumn("source_updated_timestamp", F.current_timestamp())
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_location_offers(spark, zone_rows, promo_ids, n, seed, calendar_bounds):
    """One row per configured offer. zone_rows is [(zone_sk, store_id), ...] read
    back from offer_zone so the Delta-assigned surrogate is used for the FK."""
    rng = random.Random(seed + 9102)
    cal_start, cal_end = calendar_bounds
    # Keep every offer window strictly inside the fiscal calendar's span, so each
    # event date resolves to a fiscal week when gold joins fiscal_calendar.
    span_days = (cal_end - cal_start).days
    rows = []
    for i in range(n):
        zone_sk, _store_id = zone_rows[i % len(zone_rows)]
        trigger_type = TRIGGER_TYPES[i % len(TRIGGER_TYPES)]
        # location_offer_dwell_requires_min_dwell: set IFF trigger_type='dwell'.
        min_dwell = rng.choice([60, 120, 300]) if trigger_type == "dwell" else None
        start_offset = rng.randint(0, max(span_days - 90, 1))
        duration = rng.randint(14, 75)
        start_ts = datetime.datetime.combine(cal_start + datetime.timedelta(days=start_offset),
                                             datetime.time(0, 0))
        # chk_location_offer_window: offer_end_ts strictly after offer_start_ts.
        end_ts = start_ts + datetime.timedelta(days=duration)
        rows.append((
            f"LOFF-{i:04d}",
            promo_ids[i % len(promo_ids)],
            zone_sk,
            trigger_type,
            min_dwell,
            rng.randint(1, 5),          # chk_location_offer_daily_cap: > 0
            rng.choice([0, 6, 12, 24]),  # chk_location_offer_suppression_window: >= 0
            OFFER_CHANNELS[i % len(OFFER_CHANNELS)],
            start_ts,
            end_ts,
            # Weighted toward 'active' so gold_zone_engagement_weekly.active_offers
            # is non-trivial, while still exercising all four enforced values.
            OFFER_STATUSES[i % len(OFFER_STATUSES)] if i % 3 == 0 else "active",
        ))
    schema = T.StructType([
        T.StructField("location_offer_id", T.StringType(), False),
        T.StructField("promotion_id", T.StringType(), True),
        T.StructField("zone_sk", T.LongType(), True),
        T.StructField("trigger_type", T.StringType(), True),
        T.StructField("min_dwell_seconds", T.IntegerType(), True),
        T.StructField("daily_trigger_cap", T.IntegerType(), False),
        T.StructField("suppression_window_hours", T.IntegerType(), False),
        T.StructField("channel", T.StringType(), True),
        T.StructField("offer_start_ts", T.TimestampType(), False),
        T.StructField("offer_end_ts", T.TimestampType(), False),
        T.StructField("status", T.StringType(), True),
    ])
    return (spark.createDataFrame(rows, schema)
            .withColumn("created_timestamp", F.current_timestamp())
            .withColumn("source_updated_timestamp", F.current_timestamp())
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_offer_events(spark, offers, customer_ids, sales_keys, seed, max_per_offer):
    """The delivery/engagement funnel. `offers` is a list of dicts carrying the
    Delta-assigned location_offer_sk, the offer window and the zone's anchor store.

    Mix: every trigger emits a 'triggered' row, then either 'suppressed' (~15%) or
    'delivered' (~85%); a delivered event yields 'opened' ~40% and 'redeemed' ~8%
    of the time. That keeps all four gold rates strictly inside 0..1
    (gold_location_offer_performance_rate_bounds).
    """
    rng = random.Random(seed + 9103)
    rows = []
    for offer in offers:
        sk = offer["location_offer_sk"]
        start_ts, end_ts = offer["offer_start_ts"], offer["offer_end_ts"]
        store_id = offer["zone_store_id"]
        window_seconds = max(int((end_ts - start_ts).total_seconds()), 1)

        def _trigger_ts():
            # offer_event_within_offer_window: every event_ts inside [start, end].
            return start_ts + datetime.timedelta(
                seconds=rng.randint(0, window_seconds))

        def _stage_ts(trigger_ts, delay_seconds):
            # Gold computes the funnel at fiscal-week grain. Keep every child of
            # a delivery in its trigger's cohort; independently sampling each
            # stage across the full offer window can put an open in a week with
            # no matching delivery and produce open_rate > 1. Capping at the end
            # of the trigger's date also prevents a late-Saturday journey from
            # crossing the Sunday-start fiscal-week boundary.
            next_date = datetime.datetime.combine(
                trigger_ts.date() + datetime.timedelta(days=1),
                datetime.time.min,
            )
            same_date_end = next_date - datetime.timedelta(microseconds=1)
            return min(
                trigger_ts + datetime.timedelta(seconds=delay_seconds),
                same_date_end,
                end_ts,
            )

        for _ in range(rng.randint(max_per_offer // 4, max_per_offer)):
            customer_id = customer_ids[rng.randrange(len(customer_ids))]
            trigger_ts = _trigger_ts()
            # offer_event_suppression_reason_iff_suppressed: NULL unless suppressed.
            rows.append((_ulid(rng), sk, customer_id, store_id, trigger_ts,
                         "triggered", None, None, True))
            if rng.random() < 0.15:
                reason = SUPPRESSION_REASONS[rng.randrange(len(SUPPRESSION_REASONS))]
                # consent_verified is FALSE only where that is the suppression cause.
                rows.append((_ulid(rng), sk, customer_id, store_id, _stage_ts(trigger_ts, 60),
                             "suppressed", reason, None, reason != "no_consent"))
                continue
            # offer_event_delivery_requires_consent: TRUE on every delivery-class row.
            rows.append((_ulid(rng), sk, customer_id, store_id, _stage_ts(trigger_ts, 60),
                         "delivered", None, None, True))
            if rng.random() < 0.40:
                rows.append((_ulid(rng), sk, customer_id, store_id, _stage_ts(trigger_ts, 120),
                             "opened", None, None, True))
            if rng.random() < 0.08:
                # offer_event_redeemed_requires_transaction: a resolvable sales_id,
                # set IFF the event is a redemption.
                rows.append((_ulid(rng), sk, customer_id, store_id, _stage_ts(trigger_ts, 180),
                             "redeemed", None, sales_keys[rng.randrange(len(sales_keys))], True))
    schema = T.StructType([
        T.StructField("offer_event_id", T.StringType(), False),
        T.StructField("location_offer_sk", T.LongType(), False),
        T.StructField("customer_id", T.StringType(), False),
        T.StructField("store_id", T.StringType(), False),
        T.StructField("event_ts", T.TimestampType(), False),
        T.StructField("event_type", T.StringType(), True),
        T.StructField("suppression_reason", T.StringType(), True),
        T.StructField("transaction_id", T.StringType(), True),
        T.StructField("consent_verified", T.BooleanType(), False),
    ])
    return (spark.createDataFrame(rows, schema)
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


# ------------------------------------------------------------
# Orchestration
# ------------------------------------------------------------
def generate(spark, catalog, schemas, cfg, mode, base_currency="USD"):
    if not catalog:
        raise ValueError("`catalog` parameter is required (guardrail #1: no hardcoded catalog).")

    def fq(schema, table):
        return f"{catalog}.{schemas[schema]}.{table}"

    seed = cfg["seed"]
    print(f"[ordm] generating Trade Promotion into {catalog} "
          f"(products={cfg['products']}, stores={cfg['stores']}, "
          f"promotions={cfg['promotions']}, seed={seed}, mode={mode})")

    # 1. fiscal calendar + FX rates (the currency-normalization reference)
    calendar_df = build_fiscal_calendar(spark, cfg["calendar_start_date"], cfg["calendar_weeks"], seed)
    _write(spark, calendar_df, fq("calendar", "fiscal_calendar"), FISCAL_CALENDAR_COLUMNS, mode)
    calendar_tbl = spark.table(fq("calendar", "fiscal_calendar"))
    _write(spark, build_fx_rate(spark, calendar_tbl, base_currency, seed),
           fq("calendar", "fx_rate"), FX_RATE_COLUMNS, mode)

    # 2. product / store masters
    _write(spark, build_products(spark, cfg["products"], seed, base_currency), fq("product", "product"), PRODUCT_COLUMNS, mode)
    _write(spark, build_stores(spark, cfg["stores"], seed), fq("store", "store"), STORE_COLUMNS, mode)
    products_current = spark.table(fq("product", "product")).where("is_current = true")
    stores_current = spark.table(fq("store", "store")).where("is_current = true")
    # Price history (mirrors the current list/cost snapshot on the product dim).
    _write(spark, build_product_price(spark, products_current, base_currency),
           fq("product", "product_price"), PRODUCT_PRICE_COLUMNS, mode)

    # 3. promotion calendar (seasonal, windowed)
    weeks_rows = [r.asDict() for r in calendar_tbl
                  .select("fiscal_week_id", "fiscal_week_index", "fiscal_quarter",
                          "fiscal_week_start_date", "fiscal_week_end_date")
                  .distinct().orderBy("fiscal_week_index").collect()]
    promotions = build_promotions(spark, weeks_rows, cfg["promotions"], seed,
                                  cfg["promo_duration_weeks_max"], cfg["quarter_weights"],
                                  cfg["calendar_start_date"])
    # The promotion dimension is CONFORMED canonical-core (marketing schema); only
    # the promotion_scope bridge below lives in the promote-with-purpose package.
    _write(spark, promotions, fq("marketing", "promotion"), PROMOTION_COLUMNS, mode)
    promo_current = spark.table(fq("marketing", "promotion")).where("is_current = true")
    no_promo_sk = promo_current.where(F.col("promo_id") == NO_PROMO_ID).select("promo_sk").first()[0]

    # The audience / segment-definition dimension is conformed canonical-core (marketing
    # schema, ADR 0022) — retail-media targeting audiences + behavioral canned-segment seeds.
    _write(spark, build_audiences(spark, N_RETAIL_MEDIA_AUDIENCES, seed),
           fq("marketing", "audience"), AUDIENCE_COLUMNS, mode)

    # 4. promotion scope (product x store coverage), excluding the NO_PROMO member
    product_ids = [r[0] for r in products_current.select("product_id").orderBy("product_id").collect()]
    store_ids = [r[0] for r in stores_current.select("store_id").orderBy("store_id").collect()]
    real_promo_ids = [r[0] for r in promo_current.where(F.col("promo_id") != NO_PROMO_ID)
                      .select("promo_id").orderBy("promo_id").collect()]
    scope_keys = build_promotion_scope(spark, real_promo_ids, product_ids, store_ids,
                                       seed, cfg["scope_products_max"], cfg["scope_stores_max"])
    scope = (scope_keys
             .join(promo_current.select("promo_id", "promo_sk"), on="promo_id", how="inner")
             .join(products_current.select("product_id", "product_sk"), on="product_id", how="inner")
             .join(stores_current.select("store_id", "store_sk"), on="store_id", how="inner")
             .withColumn("record_source", F.lit(RECORD_SOURCE))
             .withColumn("load_timestamp", F.current_timestamp()))
    _write(spark, scope, fq("promo", "promotion_scope"), PROMOTION_SCOPE_COLUMNS, mode)

    # 5. sales fact, attributed via scope + promo date window
    promo_windows = (spark.table(fq("promo", "promotion_scope"))
                     .join(promo_current.select(
                         F.col("promo_sk").alias("w_promo_sk"),
                         F.col("promo_id").alias("w_promo_id"),
                         F.col("start_date"), F.col("end_date"),
                         F.col("planned_discount_pct").alias("w_discount_pct"),
                         F.col("planned_lift_pct").alias("w_lift_pct"),
                         F.col("promo_id")), on="promo_id", how="inner")
                     .select(F.col("product_sk").alias("w_product_sk"),
                             F.col("store_sk").alias("w_store_sk"),
                             "w_promo_sk", "w_promo_id", "start_date", "end_date",
                             "w_discount_pct", "w_lift_pct"))
    # 5a. forward-buy windows: the N weeks AFTER each promo, per promoted product x store.
    scope_tbl = spark.table(fq("promo", "promotion_scope")).select("promo_sk", "product_sk", "store_sk")
    fb_windows = (scope_tbl
                  .join(promo_current.select("promo_sk", "end_date"), on="promo_sk", how="inner")
                  .select(F.col("product_sk").alias("fb_product_sk"),
                          F.col("store_sk").alias("fb_store_sk"),
                          F.date_add("end_date", 1).alias("fb_start"),
                          F.date_add("end_date", cfg["forward_buy_weeks"] * 7).alias("fb_end"))
                  .where("fb_end IS NOT NULL").distinct())

    # 5b. cannibalization windows: substitute SKUs (same category, NOT in scope)
    #     in the promo's stores during the promo window.
    prod_cat = products_current.select("product_sk", "category")
    scope_cat = (scope_tbl
                 .join(promo_current.select("promo_sk", "start_date", "end_date"), on="promo_sk", how="inner")
                 .join(prod_cat, on="product_sk", how="inner")
                 .select("promo_sk", "store_sk", "category", "start_date", "end_date").distinct())
    scope_products = scope_tbl.select("promo_sk", "product_sk").distinct()
    cannib_windows = (scope_cat
                      .join(prod_cat.select(F.col("product_sk").alias("cand_sk"), "category"),
                            on="category", how="inner")
                      .join(scope_products.select("promo_sk", F.col("product_sk").alias("cand_sk")),
                            on=["promo_sk", "cand_sk"], how="left_anti")
                      .select(F.col("cand_sk").alias("c_product_sk"),
                              F.col("store_sk").alias("c_store_sk"),
                              F.col("start_date").alias("cstart"),
                              F.col("end_date").alias("cend")).distinct())

    sales = build_sales(spark, calendar_tbl, products_current, stores_current,
                        promo_windows, fb_windows, cannib_windows, no_promo_sk, seed,
                        cfg["daily_sales_density"], cfg["forward_buy_dip_factor"],
                        cfg["cannibalization_dip_factor"], base_currency)
    _write(spark, sales, fq("transaction", "sales"), SALES_COLUMNS, mode)

    # 6. Location-Based Offers. AFTER the sales fact, because redemption events
    #    carry a transaction_id that must resolve to a real sales.sales_id.
    zones = build_offer_zones(spark, store_ids, cfg["zones"], seed)
    _write(spark, zones, fq("promo", "offer_zone"), OFFER_ZONE_COLUMNS, mode)
    zones_current = spark.table(fq("promo", "offer_zone")).where("is_current = true")
    # Re-read to pick up the Delta-assigned zone_sk before building the children.
    zone_rows = [(r["zone_sk"], r["store_id"])
                 for r in zones_current.select("zone_sk", "store_id", "zone_id")
                 .orderBy("zone_id").collect()]

    cal_bounds = calendar_tbl.agg(F.min("date_key").alias("lo"),
                                  F.max("date_key").alias("hi")).first()
    offers = build_location_offers(spark, zone_rows, real_promo_ids, cfg["location_offers"],
                                   seed, (cal_bounds["lo"], cal_bounds["hi"]))
    _write(spark, offers, fq("promo", "location_offer"), LOCATION_OFFER_COLUMNS, mode)
    # Re-read for location_offer_sk, and carry the zone's anchor store onto the event.
    offer_rows = [r.asDict() for r in
                  spark.table(fq("promo", "location_offer"))
                  .join(zones_current.select("zone_sk", F.col("store_id").alias("zone_store_id")),
                        on="zone_sk", how="inner")
                  .select("location_offer_sk", "location_offer_id", "offer_start_ts",
                          "offer_end_ts", "zone_store_id")
                  .orderBy("location_offer_id")
                  .collect()]

    sales_keys = [r[0] for r in spark.table(fq("transaction", "sales"))
                  .select("sales_id").distinct().orderBy("sales_id").limit(5000).collect()]
    customer_ids = [f"CUST-{i:08d}" for i in range(1, N_OFFER_CUSTOMERS + 1)]
    events = build_offer_events(spark, offer_rows, customer_ids, sales_keys, seed,
                                cfg["offer_events_per_offer_max"])
    _write(spark, events, fq("promo", "offer_event"), OFFER_EVENT_COLUMNS, mode)
    print(f"[ordm] Location-Based Offers: zones={cfg['zones']}, "
          f"offers={cfg['location_offers']}, events<={cfg['location_offers'] * cfg['offer_events_per_offer_max']}")

    print("[ordm] Trade Promotion generation complete.")


def run(ctx):
    cfg = load_config()
    # Allow volume overrides via params (else seeds.yaml defaults).
    for key in ("products", "stores", "promotions", "calendar_weeks"):
        val = get_param(key, "")
        if val:
            cfg[key] = int(val)
    generate(ctx.spark, ctx.catalog, ctx.schemas, cfg, ctx.mode, ctx.base_currency)


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
