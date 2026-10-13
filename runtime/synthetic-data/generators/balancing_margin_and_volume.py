# ============================================================
# ORDM · Synthetic data · Balancing Margin and Volume generator
# Version: 0.5
# ============================================================

import math
import os
import random
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql import types as T

try:
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _write, shelf_facings)
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _write, shelf_facings)

COMPETITOR_COLUMNS = [
    "competitor_id", "competitor_name", "competitor_type", "website_url",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp", "record_source", "load_timestamp"
]

PRODUCT_RELATIONSHIP_COLUMNS = [
    "product_relationship_id", "product_sk", "product_id", "related_product_sk", "related_product_id",
    "relationship_type", "affinity_coefficient", "record_source", "load_timestamp"
]

COMPETITOR_PRICE_COLUMNS = [
    "competitor_price_id", "competitor_sk", "competitor_id", "product_sk", "product_id",
    "date_key", "competitor_price", "competitor_mrp", "currency_code", "is_on_comp_promo",
    "is_out_of_stock", "data_source", "record_source", "load_timestamp"
]

PLANOGRAM_COLUMNS = [
    "planogram_id", "store_sk", "store_id", "product_sk", "product_id", 
    "space_planning_category", "allocated_facings", "allocated_sqft",
    "effective_from_date", "effective_to_date", "is_current",
    "created_timestamp", "source_updated_timestamp",
    "record_source", "load_timestamp"
]

COMPETITOR_TYPES = ["online", "brick_and_mortar", "discount", "premium"]
RELATIONSHIP_TYPES = ["substitute", "complement"]

def load_config():
    c = load_domain_config("balancing_margin_and_volume")
    vols = c.get("volumes", {}) or {}
    fan = c.get("fanout", {}) or {}
    return {
        "seed": c.get("seed", 8008),
        "competitors": vols.get("competitors", 5),
        "relationships_per_product": vols.get("relationships_per_product", 3),
        "price_observations_density": vols.get("price_observations_density", 0.05),
        "planogram_density": vols.get("planogram_density", 0.1),
        "affinity_min": fan.get("affinity_min", 0.1),
        "affinity_max": fan.get("affinity_max", 1.0),
    }

def build_competitors(spark, n, seed):
    rnd = random.Random(seed)
    rows = []
    for i in range(1, n + 1):
        rows.append((
            f"COMP-{i:03d}",
            f"Competitor {i}",
            rnd.choice(COMPETITOR_TYPES),
            f"https://competitor{i}.example.com",
            "2018-01-01"
        ))
    df = spark.createDataFrame(rows, ["competitor_id", "competitor_name", "competitor_type", "website_url", "eff"])
    return (df
            .withColumn("effective_from_date", F.col("eff").cast("date"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp())
            .drop("eff"))

def build_product_relationships(spark, products_df, relationships_per_product, seed):
    rnd = random.Random(seed)
    prods = [r for r in products_df.select("product_sk", "product_id").collect()]
    rows = []
    for p in prods:
        k = rnd.randint(0, relationships_per_product)
        related = rnd.sample(prods, min(k, len(prods)))
        for r in related:
            if p.product_sk == r.product_sk: continue
            rtype = rnd.choice(RELATIONSHIP_TYPES)
            rows.append((
                f"REL-{p.product_id}-{r.product_id}-{rtype}",
                p.product_sk, p.product_id,
                r.product_sk, r.product_id,
                rtype,
                round(rnd.uniform(0.1, 1.0), 4)
            ))
    df = spark.createDataFrame(rows, ["product_relationship_id", "product_sk", "product_id", "related_product_sk", "related_product_id", "relationship_type", "affinity"])
    return (df
            .withColumn("affinity_coefficient", F.col("affinity").cast("decimal(5,4)"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp())
            .drop("affinity"))

def build_competitor_prices(spark, products_df, competitors_df, calendar_df, density, seed):
    p = products_df.select("product_sk", "product_id", "list_price")
    c = competitors_df.select("competitor_sk", "competitor_id")
    d = calendar_df.select("date_key")
    
    obs = p.crossJoin(c).crossJoin(d).sample(fraction=density, seed=seed)
    
    return (obs
            .withColumn("competitor_price_id", F.concat_ws("|", F.col("competitor_id"), F.col("product_id"), F.col("date_key")))
            .withColumn("competitor_price", F.round(F.col("list_price") * (F.lit(1.0) + (F.rand(seed) * 0.2 - 0.1)), 2).cast("decimal(18,4)"))
            .withColumn("competitor_mrp", F.round(F.col("competitor_price") * 1.2, 2).cast("decimal(18,4)"))
            .withColumn("currency_code", F.lit("USD"))
            .withColumn("is_on_comp_promo", F.rand(seed+1) > 0.8)
            .withColumn("is_out_of_stock", F.rand(seed+2) > 0.95)
            .withColumn("data_source", F.lit("Web Scraper"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp())
            .drop("list_price"))

def build_planogram(spark, products_df, stores_df, density, seed):
    p = products_df.select("product_sk", "product_id", "category")
    s = stores_df.select("store_sk", "store_id")
    
    # Pre-sample to avoid expanding the full cartesian product
    root_density = math.sqrt(density)
    p_sample = p.sample(fraction=root_density, seed=seed)
    s_sample = s.sample(fraction=root_density, seed=seed)
    obs = p_sample.crossJoin(s_sample)
    
    return (obs
            .withColumnRenamed("category", "space_planning_category")
            # same deterministic facings the sales generator scaled units by (_common.shelf_facings)
            .withColumn("allocated_facings", shelf_facings().cast("int"))
            .withColumn("allocated_sqft", F.round(F.col("allocated_facings") * 1.5, 2).cast("decimal(10,2)"))
            .withColumn("effective_from_date", F.lit("2018-01-01").cast("date"))
            .withColumn("effective_to_date", F.lit(None).cast("date"))
            .withColumn("is_current", F.lit(True))
            .withColumn("created_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col("effective_from_date").cast("timestamp"))
            .withColumn("planogram_id", F.concat_ws("|", F.col("store_id"), F.col("product_id")))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))

def generate(spark, catalog, schemas, cfg, mode):
    if not catalog:
        raise ValueError("`catalog` parameter is required.")

    def fq(schema, table):
        return f"{catalog}.{schemas[schema]}.{table}"

    seed = cfg["seed"]
    print(f"[ordm] generating BMV into {catalog}")

    comp = build_competitors(spark, cfg["competitors"], seed)
    _write(spark, comp, fq("bmv", "competitor"), COMPETITOR_COLUMNS, mode)
    comp_current = spark.table(fq("bmv", "competitor"))

    products_current = spark.table(fq("product", "product")).where("is_current = true")
    
    rels = build_product_relationships(spark, products_current, cfg["relationships_per_product"], seed)
    _write(spark, rels, fq("bmv", "product_relationship"), PRODUCT_RELATIONSHIP_COLUMNS, mode)

    calendar = spark.table(fq("calendar", "fiscal_calendar"))
    
    prices = build_competitor_prices(spark, products_current, comp_current, calendar, cfg["price_observations_density"], seed)
    _write(spark, prices, fq("bmv", "competitor_price"), COMPETITOR_PRICE_COLUMNS, mode)

    stores_current = spark.table(fq("store", "store")).where("is_current = true")
    plano = build_planogram(spark, products_current, stores_current, cfg["planogram_density"], seed)
    _write(spark, plano, fq("bmv", "planogram"), PLANOGRAM_COLUMNS, mode)

    print("[ordm] BMV generation complete.")

def run(ctx):
    cfg = load_config()
    generate(ctx.spark, ctx.catalog, ctx.schemas, cfg, ctx.mode)

def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))

if __name__ == "__main__":
    main()
