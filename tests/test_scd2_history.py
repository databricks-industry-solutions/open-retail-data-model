"""Tests for the multi-version SCD2 generator helpers (runtime/synthetic-data/_common.py).

These prove the helper that makes the SCD2 defect class testable actually emits
a correct history frame — so a later PR can wire it into the live generators with
confidence. Spark fixtures (the Databricks engine) run the real helper; they skip
cleanly when pyspark/JVM is absent. `stamp_scd2_history(..., multiversion_pct=0)`
must reproduce the legacy single-version output byte-for-byte in shape, and a
nonzero fraction must produce a gap-free half-open chain with exactly one current
row per entity, with cut-points inside the fact window. `resolve_scd2_asof` must
pick the version in effect at the event date.
"""
import importlib.util
import os

import pytest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
COMMON = os.path.join(REPO, "runtime", "synthetic-data", "generators", "_common.py")


def _load_common():
    # synthetic-data has a hyphen (not an importable package) -> load by path.
    spec = importlib.util.spec_from_file_location("ordm_gen_common", COMMON)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _products(spark):
    # Two products, single current version each (what the base generator emits).
    return spark.createDataFrame(
        [("SKU-1", "electronics", 10.0), ("SKU-2", "grocery", 4.0)],
        "product_id string, subcategory string, list_price double",
    )


# ---------- stamp_scd2_history ----------

def test_zero_pct_is_single_current_version(spark):
    c = _load_common()
    out = c.stamp_scd2_history(_products(spark), ["product_id"], "2018-01-01", 42,
                               multiversion_pct=0.0)
    rows = {r["product_id"]: r for r in out.collect()}
    assert out.count() == 2, "0% multiversion must leave one row per entity"
    for r in rows.values():
        assert r["is_current"] is True
        assert r["effective_to_date"] is None
        assert str(r["effective_from_date"]) == "2018-01-01"


def test_nonzero_pct_builds_contiguous_halfopen_chain(spark):
    c = _load_common()
    from pyspark.sql import functions as F
    # Force every entity multi-version (pct=1.0) so the chain invariants are
    # exercised deterministically regardless of the hash bucket. `mutate` changes
    # subcategory per version so the versions differ on a real attribute.
    out = c.stamp_scd2_history(
        _products(spark), ["product_id"], "2018-01-01", 42,
        multiversion_pct=1.0, max_versions=3,
        window_start="2024-01-07", window_end="2026-02-15",
        mutate={"subcategory": lambda ver: F.concat_ws("-v", F.col("subcategory"), ver.cast("string"))},
    )
    by_key = {}
    for r in out.collect():
        by_key.setdefault(r["product_id"], []).append(r)

    for key, versions in by_key.items():
        versions.sort(key=lambda r: str(r["effective_from_date"]))
        assert len(versions) >= 2, f"{key}: expected >=2 versions at pct=1.0"
        # exactly one current, and it is the last (open) version
        currents = [v for v in versions if v["is_current"]]
        assert len(currents) == 1, f"{key}: exactly one is_current row required"
        assert versions[-1]["is_current"] is True
        assert versions[-1]["effective_to_date"] is None
        # gap-free half-open chain: each version's end == next version's start
        for a, b in zip(versions, versions[1:]):
            assert a["effective_to_date"] is not None
            assert a["effective_to_date"] == b["effective_from_date"], \
                f"{key}: chain not contiguous at {a['effective_from_date']}"
        # first version starts at origin; later cut-points land inside the window
        assert str(versions[0]["effective_from_date"]) == "2018-01-01"
        for v in versions[1:]:
            assert "2024-01-07" <= str(v["effective_from_date"]) < "2026-02-15"


def test_asof_resolves_version_in_effect(spark):
    c = _load_common()
    from pyspark.sql import functions as F
    # One product, two price versions: $10 for [2024-01,2024-06), $12 open.
    hist = spark.createDataFrame(
        [("SKU-1", 101, "2024-01-01", "2024-06-01", 10.0),
         ("SKU-1", 102, "2024-06-01", None, 12.0)],
        "product_id string, product_sk long, effective_from_date string, "
        "effective_to_date string, amount double",
    ).withColumn("effective_from_date", F.col("effective_from_date").cast("date")) \
     .withColumn("effective_to_date", F.col("effective_to_date").cast("date"))
    facts = spark.createDataFrame(
        [("SKU-1", "2024-03-15"), ("SKU-1", "2024-07-15")],
        "product_id string, sale_date string",
    ).withColumn("sale_date", F.col("sale_date").cast("date"))

    resolved = {str(r["sale_date"]): r for r in
                c.resolve_scd2_asof(facts, hist, "sale_date", "product_id", "product_sk",
                                    extra_cols=["amount"]).collect()}
    assert resolved["2024-03-15"]["product_sk"] == 101
    assert resolved["2024-03-15"]["amount"] == 10.0
    assert resolved["2024-07-15"]["product_sk"] == 102
    assert resolved["2024-07-15"]["amount"] == 12.0
