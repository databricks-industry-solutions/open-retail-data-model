# ============================================================
# ORDM · Synthetic data · Inventory domain generator
# Version: 0.5
# Generated: 2026-06-29
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-06-29 by @ojasvi-goyal-03
# ============================================================
import os
import sys

import dbldatagen as dg
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window

try:
    from _common import RECORD_SOURCE, get_param, _write, load_domain_config, attach_random_dim
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import RECORD_SOURCE, get_param, _write, load_domain_config, attach_random_dim

INVENTORY_POSITION_COLUMNS = [
    "inventory_position_id", "date_key", "product_sk", "product_id", "store_sk", "store_id",
    "units_on_hand_sod", "units_on_hand_eod", "units_in_transit",
    "units_on_order", "units_received_today", "is_stockout",
    "stockout_pct_day", "size_availability_pct", "replenishment_flag",
    "record_source", "load_timestamp"
]

def _indexed(df):
    """Dense 0-based index over a small dimension (deterministic order)."""
    return df.withColumn("_ord_idx", F.row_number().over(Window.orderBy(*df.columns)) - F.lit(1))


def build_inventory_position(spark, prod_df, store_df, calendar_df, n, trailing_days, seed):
    """Inventory positions over the SAME calendar the sales fact uses (fiscal_calendar), so gold
    views that join inventory to a sales day find a position. Two row sets from one spec:
      * history: the first n rows, each a randomly chosen product x store x calendar day;
      * trailing: one row for EVERY product x store on each of the calendar's last
        `trailing_days` days, so the latest sales snapshot per product x store (what
        gold_assortment_optimization reads for days-on-hand) has a same-day position."""
    n_p, n_s = prod_df.count(), store_df.count()
    days = calendar_df.select("date_key").distinct()
    n_d = days.count()
    trailing = days.orderBy(F.col("date_key").desc()).limit(int(trailing_days))
    n_t = trailing.count()
    n_dense = n_p * n_s * n_t
    spec = (
        dg.DataGenerator(spark, name="inventory_position", rows=n + n_dense, partitions=8,
                         randomSeedMethod="fixed", randomSeed=seed)
        # dbldatagen omits its internal `id` column from the output unless asked;
        # emit it so the withColumnRenamed("id", "_rid") below is not a silent
        # no-op. `_rid` is the per-row key attach_random_dim hashes on.
        .withIdOutput()
        
        .withColumn("units_on_hand_sod", "decimal(12,3)",
                    expr="cast(abs(hash(id)) % 500 as decimal(12,3))")
        .withColumn("units_received_today", "decimal(12,3)",
                    expr="cast(case when abs(hash(id)) % 10 = 0 then abs(hash(id)) % 100 else 0 end as decimal(12,3))")
        .withColumn("units_on_hand_eod", "decimal(12,3)",
                    expr="cast(units_on_hand_sod + units_received_today - (abs(hash(id)) % 50) as decimal(12,3))")
        
        .withColumn("units_in_transit", "decimal(12,3)",
                    expr="cast(case when abs(hash(id)) % 5 = 0 then abs(hash(id)) % 200 else 0 end as decimal(12,3))")
        .withColumn("units_on_order", "decimal(12,3)",
                    expr="cast(case when abs(hash(id)) % 4 = 0 then abs(hash(id)) % 300 else 0 end as decimal(12,3))")
        
        .withColumn("is_stockout", "boolean", expr="units_on_hand_eod <= 0")
        .withColumn("stockout_pct_day", "decimal(5,4)",
                    expr="cast(case when is_stockout then 1.0 else 0.0 end as decimal(5,4))")
        .withColumn("size_availability_pct", "decimal(5,4)",
                    expr="cast((abs(hash(id)) % 10000) / 10000.0 as decimal(5,4))")
        .withColumn("replenishment_flag", "boolean",
                    expr="units_on_hand_eod < 50")
    )
    base = spec.build().withColumnRenamed("id", "_rid")
    hist = base.where(F.col("_rid") < F.lit(n))
    hist = attach_random_dim(hist, prod_df, n_p, "prod", seed, "_rid")
    hist = attach_random_dim(hist, store_df, n_s, "store", seed, "_rid")
    hist = attach_random_dim(hist, days, n_d, "day", seed, "_rid")
    # trailing: decode the row index into (product, store, day) so every combination appears once
    t = F.col("_rid") - F.lit(n)
    dense = (base.where(F.col("_rid") >= F.lit(n))
             .withColumn("_pi", t % F.lit(n_p))
             .withColumn("_si", F.floor(t / F.lit(n_p)) % F.lit(n_s))
             .withColumn("_di", F.floor(t / F.lit(n_p * n_s))))
    for dim, col in ((prod_df, "_pi"), (store_df, "_si"), (trailing, "_di")):
        dense = (dense.join(F.broadcast(_indexed(dim)), F.col(col) == F.col("_ord_idx"), "inner")
                 .drop(col, "_ord_idx"))
    base = hist.unionByName(dense)
    
    # Deduplicate to ensure the grain (product, store, date) is unique
    base = base.dropDuplicates(["product_sk", "store_sk", "date_key"])
    
    # Build unique ID from the grain
    df = base.withColumn("inventory_position_id",
                         F.concat_ws("-", F.lit("INV"), F.col("product_id"), F.col("store_id"), F.col("date_key")))
    
    # Fix negative EOD
    df = df.withColumn("units_on_hand_eod", F.when(F.col("units_on_hand_eod") < 0, F.lit(0)).otherwise(F.col("units_on_hand_eod")))
    
    return (df
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))

def generate(spark, catalog, schemas, num_records, seed, mode, trailing_days=30):
    if not catalog:
        raise ValueError("`catalog` parameter is required.")

    def fq(schema, table):
        return f"{catalog}.{schemas[schema]}.{table}"

    print(f"[ordm] generating inventory domain into {catalog}.{schemas['inventory']} "
          f"(records={num_records}, seed={seed}, mode={mode})")

    prod_df = spark.table(fq("product", "product")).select("product_sk", "product_id").where("is_current = true")
    store_df = spark.table(fq("store", "store")).select("store_sk", "store_id").where("is_current = true")

    calendar_df = spark.table(fq("calendar", "fiscal_calendar"))

    inv_pos = build_inventory_position(spark, prod_df, store_df, calendar_df, num_records, trailing_days, seed)
    _write(spark, inv_pos, fq("inventory", "inventory_position"), INVENTORY_POSITION_COLUMNS, mode)

    print("[ordm] inventory domain generation complete.")

def run(ctx):
    cfg = load_domain_config("inventory")
    vols = cfg.get("volumes", {})
    # calculate n from products/stores/days (seeds.yaml), overridable via --num_records
    default_n = vols.get("products", 100) * vols.get("stores", 20) * vols.get("days", 30)
    num_records = int(get_param("num_records", default_n))
    seed = int(get_param("seed", cfg.get("seed", 1001)))
    trailing_days = int(get_param("trailing_days", vols.get("trailing_days", 30)))
    generate(ctx.spark, ctx.catalog, ctx.schemas, num_records, seed, ctx.mode, trailing_days)


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))

if __name__ == "__main__":
    main()
