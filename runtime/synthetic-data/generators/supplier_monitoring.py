# ============================================================
# ORDM · Synthetic data · Supplier Score & Monitoring generator
# Version: 0.5
# Generated: 2026-06-09
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-06-09
# ============================================================
# Populates the canonical-core supplier dimension and the procurement
# purchase_order_line fact with realistic SPREAD: each supplier is assigned a
# behaviour profile (reliable / volatile / deteriorating / poor), so OTIF,
# fill rate, lead-time variance, defects and price compliance differ across
# suppliers and the scorecard (and later risk detection) have signal.
#
# Reuses product, store and fiscal_calendar (run the trade_promotion
# generator first). Shared helpers come from _common (extended, not forked).
# Volumes and the good/bad mix come from runtime/synthetic-data/seeds.yaml.
# ============================================================

import os
import random
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql import types as T

try:
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _pick, _frac,
                         _write, attach_random_dim)
except ImportError:  # ensure sibling modules are importable when run as a notebook
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _pick, _frac,
                         _write, attach_random_dim)

# ------------------------------------------------------------
# Column contracts — MUST match the DDL (minus IDENTITY *_sk).
# Verified against the DDL by tests/test_supplier_monitoring.py.
# ------------------------------------------------------------
SUPPLIER_COLUMNS = [
    "supplier_id", "gln", "supplier_name", "supplier_type", "country_code",
    "region", "onboarding_date", "supplier_status", "effective_from_date",
    "effective_to_date", "is_current", "created_timestamp", "source_updated_timestamp",
    "record_source", "load_timestamp",
]
PO_LINE_COLUMNS = [
    "po_line_id", "po_id", "supplier_sk", "supplier_id", "product_sk",
    "product_id", "store_sk", "store_id", "order_date", "promised_date",
    "actual_delivery_date", "ordered_qty", "received_qty", "defective_qty",
    "returned_qty", "unit_price", "contract_price", "currency_code",
    "transaction_currency_code", "order_status", "record_source", "load_timestamp",
]

SUPPLIER_TYPES = ["manufacturer", "distributor", "wholesaler", "importer", "broker"]
COUNTRY_CODES = ["US", "CA", "GB", "FR", "DE", "CN", "MX"]
REGIONS = ["north_america", "europe", "asia", "latin_america"]
SUPPLIER_STATUS = ["active", "inactive", "suspended"]
BEHAVIOR_PROFILES = ["reliable", "volatile", "deteriorating", "poor"]

# Behaviour parameters per profile. Spread is intentional so composite scores
# differ. lt = lead time (days); fill <= 1.0 (no over-delivery, keeps fill in
# [0,1]); defect/price are rates/probabilities.
PROFILE_PARAMS = {
    "reliable":      dict(lt_mean=5,  lt_sigma=1, fill=1.00, defect=0.005, price_over_prob=0.05, deterioration=0),
    "volatile":      dict(lt_mean=7,  lt_sigma=6, fill=0.97, defect=0.020, price_over_prob=0.20, deterioration=0),
    "deteriorating": dict(lt_mean=6,  lt_sigma=2, fill=0.95, defect=0.020, price_over_prob=0.20, deterioration=8),
    "poor":          dict(lt_mean=11, lt_sigma=4, fill=0.85, defect=0.060, price_over_prob=0.55, deterioration=0),
}


def load_config():
    c = load_domain_config("supplier_monitoring")
    vols = c.get("volumes", {}) or {}
    weights = c.get("profile_weights", {}) or {}
    return {
        "seed": c.get("seed", 3003),
        "suppliers": vols.get("suppliers", 40),
        "lines_per_supplier": vols.get("lines_per_supplier", 200),
        "exclusive_skus": vols.get("exclusive_skus", 6),
        "exclusive_lines_per_pair": vols.get("exclusive_lines_per_pair", 30),
        "profile_weights": {p: weights.get(p, 1) for p in BEHAVIOR_PROFILES},
    }


_PARAM_SCHEMA = T.StructType([
    T.StructField("supplier_id", T.StringType()),
    T.StructField("lt_mean", T.IntegerType()),
    T.StructField("lt_sigma", T.IntegerType()),
    T.StructField("fill", T.DoubleType()),
    T.StructField("defect", T.DoubleType()),
    T.StructField("price_over_prob", T.DoubleType()),
    T.StructField("deterioration", T.IntegerType()),
])


def build_suppliers(spark, n, seed, profile_weights):
    """Return (supplier_table_df, supplier_params_df). Profiles assigned by a
    seeded weighted draw so the good/bad mix is deterministic + configurable."""
    rnd = random.Random(seed)
    profiles = [p for p, w in profile_weights.items() for _ in range(max(0, int(w)))] or BEHAVIOR_PROFILES
    table_rows, param_rows = [], []
    for i in range(1, n + 1):
        sid = f"SUP-{i:05d}"
        profile = rnd.choice(profiles)
        pp = PROFILE_PARAMS[profile]
        table_rows.append((
            sid,
            str(300000000000 + i * 7).zfill(13),                 # GS1 GLN (13 digits)
            f"Supplier {i:05d}",
            rnd.choice(SUPPLIER_TYPES),
            rnd.choice(COUNTRY_CODES),
            rnd.choice(REGIONS),
            "active" if rnd.random() > 0.08 else rnd.choice(["inactive", "suspended"]),
        ))
        param_rows.append((sid, pp["lt_mean"], pp["lt_sigma"], float(pp["fill"]),
                           float(pp["defect"]), float(pp["price_over_prob"]), pp["deterioration"]))

    tbl_schema = T.StructType([
        T.StructField("supplier_id", T.StringType()),
        T.StructField("gln", T.StringType()),
        T.StructField("supplier_name", T.StringType()),
        T.StructField("supplier_type", T.StringType()),
        T.StructField("country_code", T.StringType()),
        T.StructField("region", T.StringType()),
        T.StructField("supplier_status", T.StringType()),
    ])
    supplier_df = (spark.createDataFrame(table_rows, schema=tbl_schema)
                   .withColumn("onboarding_date",
                               F.expr("date_add(date'2015-01-01', cast(abs(hash(supplier_id)) % 3000 as int))"))
                   .withColumn("effective_from_date", F.col("onboarding_date"))
                   .withColumn("effective_to_date", F.lit(None).cast("date"))
                   .withColumn("is_current", F.lit(True))
                   # Standard audit block (UTC).
                   .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
                   .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
                   .withColumn("record_source", F.lit(RECORD_SOURCE))
                   .withColumn("load_timestamp", F.current_timestamp()))
    params_df = spark.createDataFrame(param_rows, schema=_PARAM_SCHEMA)
    return supplier_df, params_df


def build_po_lines(spark, params_with_sk, products_current, stores_current,
                   start_date, n_days, seed, lines_per_supplier,
                   shared_product_ids, exclusive_pairs, exclusive_lines_per_pair,
                   base_currency):
    store_dim = stores_current.select("store_sk", "store_id")
    n_stores = store_dim.count()
    start = F.lit(start_date)

    # Normal lines: a random product from the SHARED pool (excludes sole-sourced SKUs).
    normal = (params_with_sk
              .crossJoin(spark.range(0, lines_per_supplier).withColumnRenamed("id", "line_idx"))
              .withColumn("product_id", _pick(shared_product_ids, seed, "prod", "supplier_id", "line_idx")))

    # Exclusive lines: SKUs sourced by ONE supplier only -> single-source signal.
    spine = normal
    if exclusive_pairs:
        ex_df = spark.createDataFrame(
            exclusive_pairs,
            schema=T.StructType([T.StructField("supplier_id", T.StringType()),
                                 T.StructField("product_id", T.StringType())]))
        exclusive = (ex_df
                     .join(params_with_sk, on="supplier_id", how="inner")
                     .crossJoin(spark.range(0, exclusive_lines_per_pair).withColumnRenamed("id", "_xl"))
                     .withColumn("line_idx", F.col("_xl") + F.lit(1000000))
                     .select(*normal.columns))
        spine = normal.unionByName(exclusive)

    # deterministic per (supplier, line) draws
    h = F.abs(F.hash("supplier_id", "line_idx", F.lit(seed)))
    f_fill = _frac(seed, "fill", "supplier_id", "line_idx")
    f_lt = _frac(seed, "lt", "supplier_id", "line_idx")
    f_price = _frac(seed, "price", "supplier_id", "line_idx")

    lines = (spine
             .withColumn("_h", h)
             .withColumn("order_offset", F.col("_h") % F.lit(max(1, n_days)))
             .withColumn("order_date", F.date_add(start, F.col("order_offset").cast("int")))
             .withColumn("period_progress", F.col("order_offset") / F.lit(float(max(1, n_days))))
             .withColumn("promised_date", F.date_add(F.col("order_date"), F.col("lt_mean").cast("int")))
             # actual lead time = planned + noise in [-sigma, +2*sigma] + deterioration over time
             .withColumn("_lt_noise",
                         F.round((f_lt * F.lit(3.0) - F.lit(1.0)) * F.col("lt_sigma")
                                 + F.col("deterioration") * F.col("period_progress")))
             .withColumn("_actual_lt", F.greatest((F.col("lt_mean") + F.col("_lt_noise")).cast("int"), F.lit(1)))
             .withColumn("actual_delivery_date", F.date_add(F.col("order_date"), F.col("_actual_lt")))
             .withColumn("ordered_qty", (F.col("_h") % F.lit(491) + F.lit(10)).cast("int"))
             # fill <= 1.0 so received <= ordered (fill_rate stays in [0,1])
             .withColumn("_fill_eff", F.least(F.col("fill") + (f_fill - F.lit(0.5)) * F.lit(0.04), F.lit(1.0)))
             .withColumn("received_qty",
                         F.least(F.round(F.col("ordered_qty") * F.col("_fill_eff")).cast("int"), F.col("ordered_qty")))
             # defect rate worsens over time for deteriorating suppliers
             .withColumn("_defect_eff",
                         F.col("defect") + F.when(F.col("deterioration") > 0,
                                                  F.col("period_progress") * F.lit(0.03)).otherwise(F.lit(0.0)))
             .withColumn("defective_qty", F.round(F.col("received_qty") * F.col("_defect_eff")).cast("int"))
             .withColumn("returned_qty", F.round(F.col("defective_qty") * F.lit(0.4)).cast("int")))

    # store via broadcast join (no driver collect / array literal); product key +
    # price basis via a single join on the already-chosen product_id.
    lines = attach_random_dim(lines, store_dim, n_stores, "store", seed, "supplier_id", "line_idx")
    lines = (lines
             .join(products_current.select("product_id", "product_sk", "list_price"), on="product_id", how="inner")
             # Unit-grain prices keep 4 decimals (principle #9d).
             .withColumn("contract_price", F.round(F.col("list_price") * F.lit(0.6), 4))
             # compliant unless this line draws an overage (profile probability)
             .withColumn("unit_price",
                         F.when(f_price < F.col("price_over_prob"),
                                F.round(F.col("contract_price") * (F.lit(1.0) + (f_price * F.lit(0.08) + F.lit(0.02))), 4))
                          .otherwise(F.col("contract_price")))
             # Prices are in the reporting/base currency; procurement is settled
             # in base (transaction_currency_code preserved for lineage).
             .withColumn("currency_code", F.lit(base_currency))
             .withColumn("transaction_currency_code", F.lit(base_currency))
             .withColumn("order_status", F.lit("received"))
             .withColumn("po_id", F.concat_ws("-", F.lit("PO"), F.col("supplier_id"),
                                              (F.col("line_idx") / F.lit(5)).cast("int")))
             .withColumn("po_line_id", F.concat_ws("-", F.lit("POL"), F.col("supplier_id"), F.col("line_idx")))
             .withColumn("record_source", F.lit(RECORD_SOURCE))
             .withColumn("load_timestamp", F.current_timestamp()))
    return lines


def generate(spark, catalog, schemas, cfg, mode, base_currency="USD"):
    if not catalog:
        raise ValueError("`catalog` parameter is required (guardrail #1: no hardcoded catalog).")

    def fq(schema, table):
        return f"{catalog}.{schemas[schema]}.{table}"

    seed = cfg["seed"]
    print(f"[ordm] generating Supplier Monitoring into {catalog} "
          f"(suppliers={cfg['suppliers']}, lines/supplier={cfg['lines_per_supplier']}, "
          f"seed={seed}, mode={mode})")

    # 1. suppliers
    supplier_df, params_df = build_suppliers(spark, cfg["suppliers"], seed, cfg["profile_weights"])
    _write(spark, supplier_df, fq("supplier", "supplier"), SUPPLIER_COLUMNS, mode)
    supplier_current = spark.table(fq("supplier", "supplier")).where("is_current = true")

    # 2. conformed dims (must already exist from the trade_promotion generator)
    products_current = spark.table(fq("product", "product")).where("is_current = true")
    stores_current = spark.table(fq("store", "store")).where("is_current = true")
    calendar_tbl = spark.table(fq("calendar", "fiscal_calendar"))
    cal = calendar_tbl.agg(F.min("date_key").alias("mn"), F.count(F.lit(1)).alias("cnt")).first()
    start_date, n_days = cal["mn"], int(cal["cnt"])

    # 3. split the product pool: reserve a few SKUs as sole-sourced (each owned
    #    by one supplier) so single_source_flag has a genuine signal.
    product_ids = [r[0] for r in products_current.select("product_id").collect()]
    supplier_ids = [r[0] for r in supplier_current.select("supplier_id").collect()]
    m = min(cfg["exclusive_skus"], len(product_ids), len(supplier_ids))
    exclusive_pairs = [(supplier_ids[i], product_ids[i]) for i in range(m)]
    shared_product_ids = product_ids[m:] or product_ids   # never leave the pool empty

    # 4. purchase-order lines, keyed to the real supplier surrogate
    params_with_sk = params_df.join(
        supplier_current.select("supplier_id", "supplier_sk"), on="supplier_id", how="inner")
    po_lines = build_po_lines(spark, params_with_sk, products_current, stores_current,
                              start_date, n_days, seed, cfg["lines_per_supplier"],
                              shared_product_ids, exclusive_pairs, cfg["exclusive_lines_per_pair"],
                              base_currency)
    _write(spark, po_lines, fq("procurement", "purchase_order_line"), PO_LINE_COLUMNS, mode)

    print("[ordm] Supplier Monitoring generation complete.")


def run(ctx):
    cfg = load_config()
    for key in ("suppliers", "lines_per_supplier"):
        val = get_param(key, "")
        if val:
            cfg[key] = int(val)
    generate(ctx.spark, ctx.catalog, ctx.schemas, cfg, ctx.mode, ctx.base_currency)


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
