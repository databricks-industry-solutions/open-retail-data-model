# ============================================================
# ORDM · Synthetic data · Data Sharing with Suppliers generator
# Version: 0.5
# Generated: 2026-07-13
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-08-03
# ============================================================
# Populates the media-measurement extension tables (reporting_entitlement,
# supplier_media_report_snapshot) from the Commerce Media Networks advertiser dim
# and the Commerce Media Networks campaign_day fact (must exist — declared as
# depends_on in _registry.py). The category-growth gold view is a pure view over
# other packages and needs no generator.
#
# Also populates the joint-demand-planning (CPFR) extension tables
# (demand_collaboration, demand_plan_submission, consensus_forecast_snapshot) from
# the canonical core (supplier, product, calendar). The two joint-demand gold views
# are pure views and need no generator rows.
#
# And the data-monetization extension tables (data_product,
# data_product_subscription, data_share_consumption) from the canonical core
# (supplier) and the Commerce Media Networks advertiser dim. The two
# data-monetization gold views are pure views and need no generator rows.
#
# Every gold view in this package is a pure view, so the generator only ever writes
# the extension tables.
# ============================================================

import os
import sys

from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

try:
    from _common import RECORD_SOURCE, get_param, load_domain_config, _pick, _frac, _write
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import RECORD_SOURCE, get_param, load_domain_config, _pick, _frac, _write

# Column contracts — MUST match the DDL (minus IDENTITY *_sk).
REPORTING_ENTITLEMENT_COLUMNS = [
    "reporting_entitlement_id", "principal_id", "principal_type", "advertiser_sk",
    "advertiser_id", "campaign_sk", "campaign_id", "min_disclosure_threshold",
    "entitlement_status", "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
SNAPSHOT_COLUMNS = [
    "supplier_media_report_snapshot_id", "advertiser_sk", "advertiser_id",
    "campaign_sk", "campaign_id", "report_level", "report_period_start", "report_period_end",
    "snapshot_ts", "snapshot_date", "report_version", "impressions", "viewable_impressions",
    "clicks", "conversions", "units", "media_spend_net", "attributed_net_sales",
    "new_to_brand_sales", "incremental_sales", "roas_net", "iroas_value", "currency_code",
    "threshold_suppressed_flag", "record_source", "load_timestamp",
]

PRINCIPAL_TYPES = ["group", "account", "service_principal"]
ENTITLEMENT_STATUS = ["active", "suspended", "revoked"]
REPORT_LEVELS = ["brand", "campaign", "product"]

# Joint Demand Planning (CPFR) column contracts — MUST match the DDL (minus IDENTITY *_sk).
DEMAND_COLLABORATION_COLUMNS = [
    "demand_collaboration_id", "principal_id", "principal_type", "supplier_sk",
    "supplier_id", "product_sk", "product_id", "plan_horizon_weeks",
    "min_disclosure_threshold", "collaboration_status", "effective_from_date",
    "effective_to_date", "is_current", "created_timestamp", "source_updated_timestamp",
    "record_source", "load_timestamp",
]
DEMAND_PLAN_SUBMISSION_COLUMNS = [
    "demand_plan_submission_id", "plan_cycle_id", "party_role", "supplier_sk",
    "supplier_id", "product_sk", "product_id", "fiscal_week_id", "forecast_qty",
    "forecast_value_net", "currency_code", "submission_version", "submission_status",
    "submitted_ts", "record_source", "load_timestamp",
]
CONSENSUS_SNAPSHOT_COLUMNS = [
    "consensus_forecast_snapshot_id", "plan_cycle_id", "supplier_sk", "supplier_id",
    "product_sk", "product_id", "fiscal_week_id", "snapshot_ts", "snapshot_date",
    "plan_version", "consensus_qty", "consensus_value_net", "retailer_qty",
    "supplier_qty", "variance_pct", "currency_code", "threshold_suppressed_flag",
    "record_source", "load_timestamp",
]

COLLABORATION_STATUS = ["active", "suspended", "ended"]
PARTY_ROLES = ["retailer", "supplier"]
SUBMISSION_STATUS = ["draft", "submitted", "superseded", "withdrawn"]

# Data Monetization column contracts — MUST match the DDL (minus IDENTITY *_sk).
DATA_PRODUCT_COLUMNS = [
    "data_product_id", "data_product_name", "data_product_category", "delivery_mode",
    "pricing_model", "consumption_unit", "list_price_amount", "currency_code",
    "min_disclosure_threshold", "data_product_status", "effective_from_date",
    "effective_to_date", "is_current", "created_timestamp", "source_updated_timestamp",
    "record_source", "load_timestamp",
]
DATA_PRODUCT_SUBSCRIPTION_COLUMNS = [
    "data_product_subscription_id", "principal_id", "principal_type", "data_product_sk",
    "data_product_id", "supplier_sk", "supplier_id", "advertiser_sk", "advertiser_id",
    "contracted_price_amount", "contracted_units", "billing_frequency", "currency_code",
    "term_start_date", "term_end_date", "min_disclosure_threshold", "subscription_status",
    "subscribed_ts", "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp",
]
DATA_SHARE_CONSUMPTION_COLUMNS = [
    "data_share_consumption_id", "data_product_subscription_sk",
    "data_product_subscription_id", "principal_id", "data_product_sk", "data_product_id",
    "supplier_sk", "supplier_id", "usage_date", "fiscal_year", "fiscal_period",
    "access_channel", "consumption_units", "billed_query_count", "billable_amount",
    "currency_code", "threshold_suppressed_flag", "record_source", "load_timestamp",
]

DATA_PRODUCT_CATEGORIES = ["media_measurement", "demand_collaboration", "category_benchmark", "audience_insight"]
DELIVERY_MODES = ["share", "api", "file_export", "dashboard"]
PRICING_MODELS = ["subscription_flat", "per_consumption_unit", "tiered", "revenue_share"]
CONSUMPTION_UNITS = ["query", "row_scanned", "report_delivery", "api_call"]
DATA_PRODUCT_STATUS = ["draft", "published", "deprecated", "retired"]
BILLING_FREQUENCIES = ["monthly", "quarterly", "annual"]
SUBSCRIPTION_STATUS = ["pending", "active", "suspended", "cancelled", "expired"]


def load_config():
    cfg = {"seed": 1501}
    c = load_domain_config("data_sharing_with_suppliers")
    cfg["seed"] = c.get("seed", cfg["seed"])
    return cfg


def _audit(df):
    return (df.withColumn("record_source", F.lit(RECORD_SOURCE))
              .withColumn("load_timestamp", F.current_timestamp()))


def generate(spark, catalog, schemas, cfg, mode, base_currency="USD"):
    if not catalog:
        raise ValueError("`catalog` parameter is required (guardrail #1: no hardcoded catalog).")

    def fq(schema, table):
        return f"{catalog}.{schemas[schema]}.{table}"

    seed = cfg["seed"]
    cur = F.lit(base_currency)
    print(f"[ordm] generating data-sharing-with-suppliers (media measurement) into {catalog} (seed={seed})")

    brands = spark.table(fq("cmn", "advertiser")).where("is_current = true") \
        .select("advertiser_sk", "advertiser_id")

    # 1. reporting_entitlement — one brand-wide entitlement per advertiser, granted to a
    #    per-supplier governance group. SCD2, all current.
    ent = (brands
           .withColumn("reporting_entitlement_id", F.concat(F.lit("RE-"), F.col("advertiser_id")))
           .withColumn("principal_id", F.concat(F.lit("grp_supplier_"),
                                                F.lpad((F.abs(F.hash("advertiser_id")) % F.lit(100000)).cast("string"), 8, "0")))
           .withColumn("principal_type", F.lit("group"))
           .withColumn("campaign_sk", F.lit(None).cast("bigint")).withColumn("campaign_id", F.lit(None).cast("string"))
           .withColumn("min_disclosure_threshold", F.lit(50))
           .withColumn("entitlement_status",
                       F.when(_frac(seed, "es", "advertiser_id") < 0.92, F.lit("active")).otherwise(F.lit("suspended")))
           .withColumn("effective_from_date", F.lit(F.expr("date'2024-01-01'")))
           .withColumn("effective_to_date", F.lit(None).cast("date"))
           .withColumn("is_current", F.lit(True))
           .withColumn("created_timestamp", F.expr("cast(date'2024-01-01' as timestamp)"))
           .withColumn("source_updated_timestamp", F.expr("cast(date'2024-01-01' as timestamp)")))
    _write(spark, _audit(ent), fq("dss", "reporting_entitlement"), REPORTING_ENTITLEMENT_COLUMNS, mode)

    # 2. supplier_media_report_snapshot — freeze the CMN aggregate to brand x campaign.
    agg = (spark.table(fq("cmn", "campaign_day"))
           .where("COALESCE(privacy_suppressed_flag, false) = false")
           .groupBy("advertiser_sk", "advertiser_id", "campaign_sk", "campaign_id")
           .agg(F.sum("impressions").alias("impressions"),
                F.sum("viewable_impressions").alias("viewable_impressions"),
                F.sum("clicks").alias("clicks"),
                F.sum("conversions").alias("conversions"),
                F.sum("units").alias("units"),
                F.sum("media_spend_net").alias("media_spend_net"),
                F.sum("attributed_net_sales").alias("attributed_net_sales"),
                F.sum("new_to_brand_sales").alias("new_to_brand_sales"),
                F.sum("incremental_sales").alias("incremental_sales")))
    snap = (agg
            .withColumn("supplier_media_report_snapshot_id",
                        F.concat(F.lit("SMRS-"), F.coalesce(F.col("campaign_id"), F.col("advertiser_id")), F.lit("-v1")))
            .withColumn("report_level", F.when(F.col("campaign_id").isNotNull(), F.lit("campaign")).otherwise(F.lit("brand")))
            .withColumn("report_period_start", F.lit(F.expr("date'2024-06-01'")))
            .withColumn("report_period_end", F.lit(F.expr("date'2024-08-31'")))
            .withColumn("snapshot_date", F.lit(F.expr("date'2024-09-01'")))
            .withColumn("snapshot_ts", F.expr("cast(date'2024-09-01' as timestamp)"))
            .withColumn("report_version", F.lit(1))
            .withColumn("media_spend_net", F.col("media_spend_net").cast("decimal(18,2)"))
            .withColumn("attributed_net_sales", F.col("attributed_net_sales").cast("decimal(18,2)"))
            .withColumn("new_to_brand_sales", F.col("new_to_brand_sales").cast("decimal(18,2)"))
            .withColumn("incremental_sales", F.col("incremental_sales").cast("decimal(18,2)"))
            .withColumn("roas_net", F.round((F.col("attributed_net_sales") / F.when(F.col("media_spend_net") == 0, F.lit(None)).otherwise(F.col("media_spend_net"))).cast("decimal(12,4)"), 4))
            .withColumn("iroas_value", F.round((F.col("incremental_sales") / F.when(F.col("media_spend_net") == 0, F.lit(None)).otherwise(F.col("media_spend_net"))).cast("decimal(12,4)"), 4))
            .withColumn("currency_code", cur)
            .withColumn("threshold_suppressed_flag", F.col("conversions") < F.lit(50)))
    _write(spark, _audit(snap), fq("dss", "supplier_media_report_snapshot"), SNAPSHOT_COLUMNS, mode)

    _generate_jdp(spark, fq, seed, base_currency, mode)
    _generate_data_monetization(spark, fq, seed, base_currency, mode)

    print("[ordm] data-sharing-with-suppliers generation complete.")


def _generate_jdp(spark, fq, seed, base_currency, mode):
    """Joint Demand Planning (CPFR) tables from the canonical core (supplier, product,
    calendar). Assigns each product to a supplier deterministically (product carries no
    supplier FK), over a bounded window of fiscal weeks."""
    cur = F.lit(base_currency)
    plan_cycle = "PC-2026-01"
    print("[ordm] generating data-sharing-with-suppliers (joint demand planning) ...")

    suppliers = spark.table(fq("supplier", "supplier")).where("is_current = true") \
        .select("supplier_sk", "supplier_id")
    products = spark.table(fq("product", "product")).where("is_current = true") \
        .select("product_sk", "product_id")

    if suppliers.limit(1).count() == 0:
        print("[ordm] no suppliers found; skipping joint demand planning.")
        return

    # weeks: a fixed 8-week window (fiscal_year*100 + week); avoids depending on which
    # calendar rows exist while staying join-compatible with fiscal_calendar.fiscal_week_id.
    weeks = [202601 + i for i in range(8)]

    # Deterministically assign products to suppliers WITHOUT collecting to the driver:
    # number the suppliers (dense, stable by supplier_id), hash each product to a primary
    # supplier index, then BROADCAST-join back the supplier keys. Spark auto-broadcasts the
    # small numbered-supplier side; no create_map / .collect() on the driver.
    #
    # ~1 in 3 products also gets a SECOND (dual-source) supplier, so a product is shared
    # across suppliers — this exercises gold_joint_demand_plan's per-supplier baseline
    # ALLOCATION (a single-supplier-per-product world would never hit that path).
    # Number the (small) supplier dimension. partitionBy a constant keeps it a single
    # window without an unpartitioned-window warning; suppliers is a dimension, not a
    # fact, so the single partition is intentional and bounded.
    from pyspark.sql import Window
    sup_indexed = suppliers.withColumn(
        "sup_idx", F.row_number().over(Window.partitionBy(F.lit(1)).orderBy("supplier_id")) - F.lit(1))
    n_suppliers = sup_indexed.agg(F.max("sup_idx")).first()[0] + 1

    # Cap the JDP demo footprint to a bounded product set (kept light on purpose — this is
    # illustrative synthetic data, not a full catalog load).
    JDP_MAX_PRODUCTS = 300
    prod_base = products.limit(JDP_MAX_PRODUCTS)
    primary = prod_base.withColumn(
        "sup_idx", (F.abs(F.hash("product_id", F.lit("jdp_sup"), F.lit(seed))) % F.lit(n_suppliers)).cast("int"))
    # Second supplier only when there are >=2 suppliers and the product is in the dual-source
    # third; offset the index by 1 (mod n) so it differs from the primary.
    secondary = (prod_base
                 .where((F.lit(n_suppliers) >= 2) & (_frac(seed, "jdp_dual", "product_id") < 0.33))
                 .withColumn("sup_idx",
                             ((F.abs(F.hash("product_id", F.lit("jdp_sup"), F.lit(seed))) + F.lit(1)) % F.lit(n_suppliers)).cast("int")))
    scope = (primary.unionByName(secondary)
             .join(F.broadcast(sup_indexed), "sup_idx", "left")
             .drop("sup_idx")
             .dropDuplicates(["product_id", "supplier_id"]))
    # NOTE: no .cache() here. The daily/serving deploy runs generate_all on SERVERLESS compute,
    # which rejects PERSIST/CACHE ([NOT_SUPPORTED_WITH_SERVERLESS] PERSIST TABLE ... SQLSTATE 0A000).
    # `scope` is reused 3x below, but it is built purely from DETERMINISTIC transforms (seeded
    # hashes, a broadcast join, dropDuplicates on a stable key), so recomputing it is correct and
    # cheap on this bounded demo footprint (<=JDP_MAX_PRODUCTS rows). Never add .cache()/.persist()
    # in a generator -- see tests/test_generator_runtime_regressions.py
    # ::test_no_generator_caches_or_persists_on_serverless.

    # 1. demand_collaboration — one supplier-wide grant per supplier, to a per-supplier group.
    collab = (scope.select("supplier_sk", "supplier_id").distinct()
              .withColumn("demand_collaboration_id", F.concat(F.lit("DC-"), F.col("supplier_id")))
              .withColumn("principal_id", F.concat(F.lit("grp_supplier_"),
                          F.lpad((F.abs(F.hash("supplier_id")) % F.lit(100000)).cast("string"), 8, "0")))
              .withColumn("principal_type", F.lit("group"))
              .withColumn("product_sk", F.lit(None).cast("bigint"))
              .withColumn("product_id", F.lit(None).cast("string"))
              .withColumn("plan_horizon_weeks", F.lit(len(weeks)))
              .withColumn("min_disclosure_threshold", F.lit(10))
              .withColumn("collaboration_status",
                          F.when(_frac(seed, "dc_status", "supplier_id") < 0.9, F.lit("active")).otherwise(F.lit("suspended")))
              .withColumn("effective_from_date", F.expr("date'2025-01-01'"))
              .withColumn("effective_to_date", F.lit(None).cast("date"))
              .withColumn("is_current", F.lit(True))
              .withColumn("created_timestamp", F.expr("cast(date'2025-01-01' as timestamp)"))
              .withColumn("source_updated_timestamp", F.expr("cast(date'2025-01-01' as timestamp)")))
    _write(spark, _audit(collab), fq("dss", "demand_collaboration"), DEMAND_COLLABORATION_COLUMNS, mode)

    # scope x weeks grid, with a base demand shaped by product/week hash.
    weeks_df = spark.createDataFrame([(w,) for w in weeks], "fiscal_week_id int")
    grid = (scope.crossJoin(weeks_df)
            .withColumn("base_qty", (F.abs(F.hash("product_id", "fiscal_week_id")) % F.lit(400) + F.lit(50)).cast("bigint")))

    # 2. demand_plan_submission — retailer and supplier each submit v1 (latest, submitted).
    #    Retailer and supplier plans deviate from the base by small deterministic factors.
    retailer = (grid
                .withColumn("party_role", F.lit("retailer"))
                .withColumn("forecast_qty",
                            (F.col("base_qty") * (F.lit(1.0) + (_frac(seed, "ret", "product_id", "fiscal_week_id") - F.lit(0.5)) * F.lit(0.2))).cast("bigint")))
    supplier_sub = (grid
                    .withColumn("party_role", F.lit("supplier"))
                    .withColumn("forecast_qty",
                                (F.col("base_qty") * (F.lit(1.0) + (_frac(seed, "sup", "product_id", "fiscal_week_id") - F.lit(0.5)) * F.lit(0.3))).cast("bigint")))
    submissions = (retailer.unionByName(supplier_sub)
                   .withColumn("plan_cycle_id", F.lit(plan_cycle))
                   .withColumn("demand_plan_submission_id",
                               F.concat_ws("-", F.lit("DPS"), F.col("plan_cycle_id"), F.col("party_role"),
                                           F.col("supplier_id"), F.col("product_id"), F.col("fiscal_week_id").cast("string"), F.lit("v1")))
                   .withColumn("forecast_value_net", (F.col("forecast_qty") * F.lit(9.99)).cast("decimal(18,2)"))
                   .withColumn("currency_code", cur)
                   .withColumn("submission_version", F.lit(1))
                   .withColumn("submission_status", F.lit("submitted"))
                   .withColumn("submitted_ts", F.expr("cast(date'2026-01-05' as timestamp)")))
    _write(spark, _audit(submissions), fq("dss", "demand_plan_submission"), DEMAND_PLAN_SUBMISSION_COLUMNS, mode)

    # 3. consensus_forecast_snapshot — the frozen agreed plan (midpoint of the two parties).
    consensus = (grid
                 .withColumn("retailer_qty",
                             (F.col("base_qty") * (F.lit(1.0) + (_frac(seed, "ret", "product_id", "fiscal_week_id") - F.lit(0.5)) * F.lit(0.2))).cast("bigint"))
                 .withColumn("supplier_qty",
                             (F.col("base_qty") * (F.lit(1.0) + (_frac(seed, "sup", "product_id", "fiscal_week_id") - F.lit(0.5)) * F.lit(0.3))).cast("bigint"))
                 .withColumn("consensus_qty", ((F.col("retailer_qty") + F.col("supplier_qty")) / F.lit(2)).cast("bigint"))
                 .withColumn("variance_pct",
                             F.round(((F.col("retailer_qty") - F.col("supplier_qty")) /
                                      F.when(F.col("supplier_qty") == 0, F.lit(None)).otherwise(F.col("supplier_qty"))).cast("decimal(9,4)"), 4))
                 .withColumn("plan_cycle_id", F.lit(plan_cycle))
                 .withColumn("consensus_forecast_snapshot_id",
                             F.concat_ws("-", F.lit("CFS"), F.col("supplier_id"), F.col("product_id"),
                                         F.col("fiscal_week_id").cast("string"), F.lit("v1")))
                 .withColumn("consensus_value_net", (F.col("consensus_qty") * F.lit(9.99)).cast("decimal(18,2)"))
                 .withColumn("currency_code", cur)
                 .withColumn("plan_version", F.lit(1))
                 .withColumn("snapshot_date", F.expr("date'2026-01-08'"))
                 .withColumn("snapshot_ts", F.expr("cast(date'2026-01-08' as timestamp)"))
                 .withColumn("threshold_suppressed_flag", F.col("consensus_qty") < F.lit(10)))
    _write(spark, _audit(consensus), fq("dss", "consensus_forecast_snapshot"), CONSENSUS_SNAPSHOT_COLUMNS, mode)


def _generate_data_monetization(spark, fq, seed, base_currency, mode):
    """Data Monetization tables: the data-product catalog, per-principal subscription
    licences, and the metered consumption that bills against them.

    Reads the canonical core (supplier) and the Commerce Media Networks advertiser dim
    (for the advertiser-scoped licences whose revenue the gold view compares against
    retail-media spend). Deliberately covers the interesting shapes the gold views and
    their regression tests exercise: an all-supplier licence AND a supplier-scoped one on
    the same product (so the most-specific-grant dedup and the media allocation both have
    something to do), paid-but-unused licences, over-runs, and a cancelled latest version.
    """
    cur = F.lit(base_currency)
    print("[ordm] generating data-sharing-with-suppliers (data monetization) ...")

    suppliers = spark.table(fq("supplier", "supplier")).where("is_current = true") \
        .select("supplier_sk", "supplier_id")
    if suppliers.limit(1).count() == 0:
        print("[ordm] no suppliers found; skipping data monetization.")
        return

    # ---- 1. data_product — a small fixed catalog (a rate card is reference data, not
    # something to randomize). One product per category so every enum value is exercised;
    # the per_consumption_unit ones are what make rate-card divergence meaningful.
    # Row shape follows DATA_PRODUCT_COLUMNS order.
    products = [
        ("DP-MEDIA-PERF",  "Supplier Media Performance", "media_measurement",     "api",         "per_consumption_unit", "query",           10.00,  25),
        ("DP-DEMAND-FEED", "Joint Demand Plan Feed",     "demand_collaboration",  "share",       "subscription_flat",    "report_delivery", 2500.00, 10),
        ("DP-CAT-BENCH",   "Category Benchmark Report",  "category_benchmark",    "dashboard",   "tiered",               "report_delivery", 1200.00, 50),
        ("DP-AUD-INSIGHT", "Audience Insight Extract",   "audience_insight",      "file_export", "per_consumption_unit", "row_scanned",     0.02,   100),
    ]
    dp = (spark.createDataFrame(
              products,
              "data_product_id string, data_product_name string, data_product_category string, "
              "delivery_mode string, pricing_model string, consumption_unit string, "
              "list_price_amount_d double, min_disclosure_threshold int")
          .withColumn("list_price_amount", F.col("list_price_amount_d").cast("decimal(18,2)"))
          .drop("list_price_amount_d")
          .withColumn("currency_code", cur)
          .withColumn("data_product_status", F.lit("published"))
          .withColumn("effective_from_date", F.expr("date'2025-06-01'"))
          .withColumn("effective_to_date", F.lit(None).cast("date"))
          .withColumn("is_current", F.lit(True))
          .withColumn("created_timestamp", F.expr("cast(date'2025-06-01' as timestamp)"))
          .withColumn("source_updated_timestamp", F.expr("cast(date'2025-06-01' as timestamp)")))
    _write(spark, _audit(dp), fq("dss", "data_product"), DATA_PRODUCT_COLUMNS, mode)

    # Re-read the written catalog to pick up the Delta-assigned IDENTITY data_product_sk,
    # so the subscription/consumption FKs point at real surrogates rather than invented ones.
    dp_keys = spark.table(fq("dss", "data_product")).where("is_current = true") \
        .select("data_product_sk", "data_product_id", "pricing_model", "consumption_unit", "list_price_amount")

    # ---- 2. data_product_subscription — licences held by per-supplier governance groups.
    # Bounded demo footprint, and small enough that every licence shape stays legible.
    DM_MAX_SUPPLIERS = 40
    sup_base = suppliers.limit(DM_MAX_SUPPLIERS)

    # The advertiser dim gives the brand role of a supplier; join on supplier_sk so an
    # advertiser-scoped licence lines up with the supplier it belongs to. Only the FIRST
    # advertiser per supplier is used (a supplier may advertise several brands) — picked
    # deterministically by advertiser_id so re-runs are stable.
    adv = (spark.table(fq("cmn", "advertiser")).where("is_current = true")
           .select("advertiser_sk", "advertiser_id", "supplier_sk"))
    adv_ranked = adv.withColumn(
        "adv_rn", F.row_number().over(Window.partitionBy("supplier_sk").orderBy("advertiser_id")))
    adv_one = adv_ranked.where("adv_rn = 1").drop("adv_rn")

    # Every supplier group licenses the media-performance product, SUPPLIER-SCOPED and
    # advertiser-scoped: this is the row whose revenue is compared to retail-media spend.
    base = (sup_base.join(F.broadcast(adv_one), "supplier_sk", "left")
            .withColumn("principal_id",
                        F.concat(F.lit("grp_supplier_"),
                                 F.lpad((F.abs(F.hash("supplier_id")) % F.lit(100000)).cast("string"), 8, "0"))))

    # Terms start 2026-01-04, the first day of FY2026 period 1 under this calendar seeding,
    # NOT 2026-01-01: the NRF 4-5-4 fiscal year 2025 runs through 2026-01-03, so a
    # 1 January start would put every licence's first covered period in FY2025 P12 — a real
    # (correctly reported) but confusing extra period with no usage in it.
    media_dp = F.broadcast(dp_keys.where("data_product_id = 'DP-MEDIA-PERF'"))
    scoped = (base.crossJoin(media_dp)
              .withColumn("contracted_price_amount", F.lit(1800.00).cast("decimal(18,2)"))
              # allowance varies deterministically so utilisation is not uniform
              .withColumn("contracted_units",
                          (F.lit(200) + (F.abs(F.hash("supplier_id", F.lit("dm_units"), F.lit(seed))) % F.lit(300))).cast("bigint"))
              .withColumn("billing_frequency", F.lit("monthly"))
              .withColumn("term_start_date", F.expr("date'2026-01-04'"))
              # ~1 in 6 licences has a fixed end inside the calendar window, close enough to
              # the periods present that the exception queue raises it as a lapsing term
              # (the 90-day window is measured from the reported period's END, so a term
              # ending beyond the calendar would never surface).
              .withColumn("term_end_date",
                          F.when(_frac(seed, "dm_term", "supplier_id") < 0.17, F.expr("date'2026-02-28'"))
                           .otherwise(F.lit(None).cast("date")))
              .withColumn("subscription_status",
                          F.when(_frac(seed, "dm_status", "supplier_id") < 0.88, F.lit("active"))
                           .when(_frac(seed, "dm_status", "supplier_id") < 0.95, F.lit("suspended"))
                           .otherwise(F.lit("cancelled")))
              .withColumn("scope_tag", F.lit("sup")))

    # A subset of groups ALSO holds an ALL-SUPPLIER licence on the same product (supplier_sk
    # NULL). This is the overlap the gold view's most-specific-grant ranking resolves, and
    # the multi-licence advertiser group the media allocation splits spend across.
    all_sup = (base.where(_frac(seed, "dm_allsup", "supplier_id") < 0.25)
               .crossJoin(media_dp)
               .withColumn("contracted_price_amount", F.lit(3200.00).cast("decimal(18,2)"))
               .withColumn("contracted_units", F.lit(600).cast("bigint"))
               .withColumn("billing_frequency", F.lit("quarterly"))
               .withColumn("term_start_date", F.expr("date'2026-01-04'"))
               .withColumn("term_end_date", F.lit(None).cast("date"))
               .withColumn("subscription_status", F.lit("active"))
               .withColumn("scope_tag", F.lit("all"))
               # an all-supplier licence has no single supplier or advertiser scope
               .withColumn("supplier_sk", F.lit(None).cast("bigint"))
               .withColumn("supplier_id_null", F.lit(None).cast("string"))
               .withColumn("advertiser_sk", F.lit(None).cast("bigint"))
               .withColumn("advertiser_id", F.lit(None).cast("string")))

    # A third slice licenses the FLAT-priced demand feed and never consumes it — the
    # paid-but-unused signal, the most commercially material exception in this use case.
    feed_dp = F.broadcast(dp_keys.where("data_product_id = 'DP-DEMAND-FEED'"))
    unused = (base.where(_frac(seed, "dm_unused", "supplier_id") < 0.30)
              .crossJoin(feed_dp)
              .withColumn("contracted_price_amount", F.lit(2200.00).cast("decimal(18,2)"))
              .withColumn("contracted_units", F.lit(12).cast("bigint"))
              .withColumn("billing_frequency", F.lit("annual"))
              .withColumn("term_start_date", F.expr("date'2026-01-04'"))
              .withColumn("term_end_date", F.lit(None).cast("date"))
              .withColumn("subscription_status", F.lit("active"))
              .withColumn("scope_tag", F.lit("unused")))

    # A fourth slice licenses the remaining two catalog products, so every product in the
    # rate card is actually licensed (and the `tiered` and `row_scanned` shapes get
    # exercised downstream rather than sitting inert in the catalog). These carry the
    # 'expired' status, which the revenue view deliberately KEEPS — it reports history by
    # fiscal period, so an expired contract still earned in the periods it covered.
    other_dp = F.broadcast(dp_keys.where("data_product_id IN ('DP-CAT-BENCH', 'DP-AUD-INSIGHT')"))
    other = (base.where(_frac(seed, "dm_other", "supplier_id") < 0.35)
             .crossJoin(other_dp)
             .withColumn("contracted_price_amount", F.lit(1000.00).cast("decimal(18,2)"))
             .withColumn("contracted_units",
                         F.when(F.col("data_product_id") == "DP-AUD-INSIGHT", F.lit(80000))
                          .otherwise(F.lit(40)).cast("bigint"))
             .withColumn("billing_frequency", F.lit("monthly"))
             .withColumn("term_start_date", F.expr("date'2026-01-04'"))
             # Ends inside the calendar window (see usage_days) so these licences still cover
             # a period the spine contains and their revenue is reportable.
             .withColumn("term_end_date", F.expr("date'2026-02-14'"))
             .withColumn("subscription_status", F.lit("expired"))
             .withColumn("scope_tag", F.lit("other")))

    def _shape(df, all_supplier_scope=False):
        out = df
        if all_supplier_scope:
            out = out.drop("supplier_id").withColumnRenamed("supplier_id_null", "supplier_id")
        return (out
                .withColumn("principal_type", F.lit("group"))
                .withColumn("data_product_subscription_id",
                            F.concat_ws("-", F.lit("DPS"), F.col("data_product_id"),
                                        F.col("principal_id"), F.col("scope_tag"), F.lit("v1")))
                .withColumn("currency_code", cur)
                .withColumn("min_disclosure_threshold", F.lit(0))
                .withColumn("subscribed_ts", F.expr("cast(date'2025-12-15' as timestamp)"))
                .withColumn("effective_from_date", F.expr("date'2025-12-15'"))
                .withColumn("effective_to_date", F.lit(None).cast("date"))
                .withColumn("is_current", F.lit(True))
                .withColumn("created_timestamp", F.expr("cast(date'2025-12-15' as timestamp)"))
                .withColumn("source_updated_timestamp", F.expr("cast(date'2025-12-15' as timestamp)")))

    subs = (_shape(scoped)
            .unionByName(_shape(all_sup, all_supplier_scope=True), allowMissingColumns=True)
            .unionByName(_shape(unused), allowMissingColumns=True)
            .unionByName(_shape(other), allowMissingColumns=True))
    _write(spark, _audit(subs), fq("dss", "data_product_subscription"),
           DATA_PRODUCT_SUBSCRIPTION_COLUMNS, mode)

    # ---- 3. data_share_consumption — metered daily usage against the written licences.
    # Re-read to pick up the IDENTITY subscription surrogate, and skip the flat-priced
    # 'unused' licences entirely so they stay genuinely unused.
    lic = (spark.table(fq("dss", "data_product_subscription")).where("is_current = true")
           .select("data_product_subscription_sk", "data_product_subscription_id", "principal_id",
                   "data_product_sk", "data_product_id", "supplier_sk", "supplier_id",
                   "contracted_units", "billing_frequency", "subscription_status")
           .where("data_product_id <> 'DP-DEMAND-FEED'"))

    # Usage days: sample days in FY2026 fiscal periods 1 and 2. Each date MUST satisfy two
    # constraints, both verified against the generated fiscal_calendar rather than assumed:
    #   1. it exists in the calendar. The synthetic calendar is seeded from
    #      calendar_start_date 2024-01-07 for calendar_weeks 110 (runtime/synthetic-data/seeds.yaml),
    #      so it ends 2026-02-14 — FY2026 period 2 is the LAST complete period available.
    #      A later date would have no calendar row, so the revenue view's fiscal-period
    #      spine would not contain it and the usage would silently vanish.
    #   2. its labelled (fiscal_year, fiscal_period) matches what the NRF 4-5-4 calendar
    #      derives for that date, or dsc_fiscal_period_matches_usage_date fails. Under this
    #      seeding FY2026 P1 = 2026-01-04..2026-01-31 and P2 = 2026-02-01..2026-02-14.
    # Kept to a fixed literal list so the fact stays deterministic and bounded without
    # reading the calendar at generation time.
    usage_days = [
        ("2026-01-07", 2026, 1), ("2026-01-14", 2026, 1),
        ("2026-01-21", 2026, 1), ("2026-01-28", 2026, 1),
        ("2026-02-04", 2026, 2), ("2026-02-11", 2026, 2),
    ]
    days_df = spark.createDataFrame(usage_days, "usage_date_s string, fiscal_year int, fiscal_period int") \
        .withColumn("usage_date", F.col("usage_date_s").cast("date")).drop("usage_date_s")

    # A suspended or cancelled licence stops generating usage partway through, so the
    # revenue view has periods where a licence exists but billed nothing.
    cons = (lic.crossJoin(F.broadcast(days_df))
            .where((F.col("subscription_status") == "active")
                   | ((F.col("subscription_status") != "active") & (F.col("fiscal_period") == 1)))
            # ~15% of (licence, day) pairs simply have no activity — real usage is bursty.
            .where(_frac(seed, "dm_active_day", "data_product_subscription_id", "usage_date") >= 0.15)
            .withColumn("units_per_day",
                        (F.lit(5) + (F.abs(F.hash("data_product_subscription_id", "usage_date",
                                                  F.lit("dm_units_day"), F.lit(seed))) % F.lit(60))).cast("bigint")))

    # Attach the product's rate so billable_amount is resolved against real terms rather
    # than a magic number. per_consumption_unit bills units x rate; the flat/tiered models
    # bill their list amount once per usage row (illustrative — the point is that the
    # stored amount is NOT units x rate for those models).
    # Attach the rate card on the DURABLE business key, not the IDENTITY surrogate: the
    # business key is assigned by this generator and is therefore always present, whereas
    # *_sk is assigned by the engine on write.
    cons = (cons.join(F.broadcast(dp_keys.select("data_product_id", "pricing_model", "consumption_unit", "list_price_amount")),
                      "data_product_id", "left")
            .withColumn("consumption_units",
                        F.when(F.col("consumption_unit") == "row_scanned",
                               F.col("units_per_day") * F.lit(1000))
                         .otherwise(F.col("units_per_day")).cast("bigint"))
            .withColumn("billable_amount",
                        F.when(F.col("pricing_model") == "per_consumption_unit",
                               (F.col("consumption_units") * F.col("list_price_amount")))
                         .otherwise(F.col("list_price_amount")).cast("decimal(18,2)"))
            .withColumn("billed_query_count", F.col("units_per_day"))
            .withColumn("access_channel", _pick(["share", "api", "file_export", "dashboard"],
                                                seed, "dm_channel", "data_product_subscription_id"))
            .withColumn("data_share_consumption_id",
                        F.concat_ws("-", F.lit("DSC"), F.col("data_product_subscription_id"),
                                    F.date_format("usage_date", "yyyyMMdd")))
            .withColumn("currency_code", cur)
            # Low-volume days are marked suppressed; the revenue view drops them before
            # aggregating so a suppressed measure never reaches a disclosed total.
            .withColumn("threshold_suppressed_flag", F.col("consumption_units") < F.lit(8)))
    _write(spark, _audit(cons), fq("dss", "data_share_consumption"),
           DATA_SHARE_CONSUMPTION_COLUMNS, mode)


def run(ctx):
    generate(ctx.spark, ctx.catalog, ctx.schemas, load_config(), ctx.mode, ctx.base_currency)


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
