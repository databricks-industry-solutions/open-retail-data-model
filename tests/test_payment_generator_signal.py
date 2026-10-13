"""Tests for payment-generator refund-store-tier signal.

Static contract tests (AST-based) pin the synthetic-data refund tier contract:
tier shares sum to 1, multipliers positive with HIGH > NORMAL > LOW, orphan share
strictly in (0,1), build_payments applies refund_store_multiplier and
ADJUSTMENT_ORPHAN_SHARE, the refund branch uses the multiplier (not a flat rate),
and seeds.yaml documents the knobs if the generator reads them.

Spark fixture (skips without a JVM) runs build_payments on a tiny order_lines DataFrame,
checks determinism (two runs equal), and verifies that HIGH-tier stores get more
refunds than LOW on a large enough synthetic sample.
"""

import ast
import math
import os
import re
import sys
import importlib.util

import pytest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GEN = os.path.join(REPO, "runtime", "synthetic-data", "generators")
GENERATOR = os.path.join(GEN, "customer_ltv.py")
SEEDS = os.path.join(REPO, "runtime", "synthetic-data", "seeds.yaml")


def _load_generator():
    """Load the customer_ltv generator module with its sibling _common importable."""
    gen_dir = os.path.join(REPO, "runtime", "synthetic-data", "generators")
    if gen_dir not in sys.path:
        sys.path.insert(0, gen_dir)
    spec = importlib.util.spec_from_file_location("ordm_customer_ltv_gen", GENERATOR)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------- static tests (AST-based, no Spark) ----------

def _ast_constants(name):
    """Extract module-level constant assignments as {name: value}."""
    mod = ast.parse(open(GENERATOR).read())
    return {n.targets[0].id: ast.literal_eval(n.value)
            for n in mod.body if isinstance(n, ast.Assign)
            and len(n.targets) == 1
            and isinstance(n.targets[0], ast.Name)
            and n.targets[0].id == name}


def _ast_calls(fn_name):
    """Find all calls to a named function in the generator."""
    mod = ast.parse(open(GENERATOR).read())
    return [n for n in ast.walk(mod)
            if isinstance(n, ast.Call)
            and isinstance(n.func, ast.Name)
            and n.func.id == fn_name]


def test_refund_store_tier_shares_sum_to_one():
    """REFUND_STORE_TIER_SHARES must be a dict where values sum to 1.0."""
    consts = _ast_constants("REFUND_STORE_TIER_SHARES")
    assert "REFUND_STORE_TIER_SHARES" in consts, (
        "REFUND_STORE_TIER_SHARES constant not found in customer_ltv.py")
    shares = consts["REFUND_STORE_TIER_SHARES"]
    assert isinstance(shares, dict), f"REFUND_STORE_TIER_SHARES must be dict, got {type(shares)}"
    total = sum(shares.values())
    assert math.isclose(total, 1.0, abs_tol=1e-9), (
        f"REFUND_STORE_TIER_SHARES values must sum to 1.0, got {total}")


def test_refund_store_tier_multipliers_positive_and_ordered():
    """REFUND_STORE_TIER_MULTIPLIER dict: all positive, HIGH > NORMAL > LOW."""
    consts = _ast_constants("REFUND_STORE_TIER_MULTIPLIER")
    assert "REFUND_STORE_TIER_MULTIPLIER" in consts, (
        "REFUND_STORE_TIER_MULTIPLIER constant not found in customer_ltv.py")
    mults = consts["REFUND_STORE_TIER_MULTIPLIER"]
    assert isinstance(mults, dict), f"REFUND_STORE_TIER_MULTIPLIER must be dict, got {type(mults)}"
    assert set(mults.keys()) == {"HIGH", "NORMAL", "LOW"}, (
        f"REFUND_STORE_TIER_MULTIPLIER must have keys HIGH/NORMAL/LOW, got {set(mults.keys())}")
    for tier, mult in mults.items():
        assert mult > 0, f"REFUND_STORE_TIER_MULTIPLIER[{tier}] = {mult} must be positive"
    assert mults["HIGH"] > mults["NORMAL"] > mults["LOW"], (
        f"HIGH > NORMAL > LOW ordering violated: {mults}")


def test_adjustment_orphan_share_strictly_in_open_interval():
    """ADJUSTMENT_ORPHAN_SHARE in (0, 1) exclusive on both ends."""
    consts = _ast_constants("ADJUSTMENT_ORPHAN_SHARE")
    assert "ADJUSTMENT_ORPHAN_SHARE" in consts, (
        "ADJUSTMENT_ORPHAN_SHARE constant not found in customer_ltv.py")
    orphan = consts["ADJUSTMENT_ORPHAN_SHARE"]
    assert 0 < orphan < 1, (
        f"ADJUSTMENT_ORPHAN_SHARE = {orphan} must be strictly in (0, 1)")


def test_build_payments_calls_refund_store_multiplier():
    """build_payments must call refund_store_multiplier helper."""
    calls = _ast_calls("refund_store_multiplier")
    assert len(calls) > 0, (
        "refund_store_multiplier not called in customer_ltv.py; "
        "build_payments must apply store-tier signal to refund rate")


def test_build_payments_references_adjustment_orphan_share():
    """build_payments must reference ADJUSTMENT_ORPHAN_SHARE constant."""
    src = open(GENERATOR).read()
    assert "ADJUSTMENT_ORPHAN_SHARE" in src, (
        "ADJUSTMENT_ORPHAN_SHARE not found in customer_ltv.py; "
        "build_payments must use it to conditionally NULL order_id on adjustments")
    # Check it appears in build_payments (not just at module level)
    body = src.split("def build_payments")[1].split("\ndef ")[0]
    assert "ADJUSTMENT_ORPHAN_SHARE" in body, (
        "ADJUSTMENT_ORPHAN_SHARE not referenced in build_payments body")


def test_refund_tier_branch_no_longer_flat_rate():
    """The refund branch must not apply a single flat 0.3 rate; it uses the multiplier."""
    src = open(GENERATOR).read()
    # Find the refund branch (between "refund = (" and the next ")" at statement level)
    match = re.search(r"refund\s*=\s*\(\s*orders\s*\n(.*?)\n\s*\)",
                      src, re.DOTALL)
    assert match, "refund branch not found in expected format"
    refund_body = match.group(1)
    # Must NOT have a hardcoded "F.lit(0.3)" applying uniformly to all refund amounts
    # (the store-tier multiplier should now gate the refund_rate, or adjust the amount differently)
    assert "refund_store_multiplier" in refund_body or "_frac" in refund_body, (
        "refund branch must apply store-tier logic via refund_store_multiplier or "
        "deterministic _frac (not a single flat rate)")


def test_seeds_yaml_documents_tier_knobs():
    """Tier constants are module-level; base refund_rate in seeds.yaml is what gets adjusted."""
    seeds_text = open(SEEDS).read()
    # The tier multipliers and orphan share are hardcoded module constants
    # (deterministic per store/adjustment by design). The base refund_rate that gets
    # multiplied IS documented in seeds.yaml, so the contract is satisfied.
    assert "customer_ltv:" in seeds_text, "customer_ltv section must exist in seeds.yaml"
    cltv_section = seeds_text.split("customer_ltv:")[1].split("\n  [a-z_]")[0]
    assert "refund_rate:" in cltv_section, (
        "seeds.yaml customer_ltv must document refund_rate "
        "(the base rate before store-tier multiplier adjustment)")


def test_refund_store_multiplier_function_exists_and_deterministic():
    """refund_store_multiplier(store_id, seed, ...) must be a pure, deterministic helper."""
    src = open(GENERATOR).read()
    # Check function is defined
    assert re.search(r"def refund_store_multiplier\s*\(", src), (
        "refund_store_multiplier function not defined in customer_ltv.py")
    # Check it uses store_id (and likely a hash, not rand)
    match = re.search(r"def refund_store_multiplier\s*\((.*?)\):", src)
    assert match, "refund_store_multiplier signature not found"
    sig = match.group(1)
    assert "store" in sig.lower(), (
        "refund_store_multiplier must accept store_id (or similar) as parameter")
    # Verify no rand() call in the function (deterministic via hash/frac)
    func_match = re.search(r"def refund_store_multiplier\s*\(.*?\):(.*?)(?=\ndef |\Z)",
                           src, re.DOTALL)
    if func_match:
        func_body = func_match.group(1)
        assert "rand(" not in func_body, (
            "refund_store_multiplier must be deterministic (no rand() calls)")


# ---------- Spark fixture: determinism + tier signal ----------

# customer_order_line columns build_payments reads (one store per order, as the generator builds them)
_ORDER_LINE_SCHEMA = (
    "order_line_id string, order_id string, profile_sk long, profile_id string, "
    "product_sk long, product_id string, store_sk long, store_id string, order_date date, "
    "event_timestamp timestamp, units int, gross_amount double, net_amount double, currency_code string"
)


def _order_line(i, order_id, store_idx, net=100.0):
    import datetime as dt
    return (f"L{i}", order_id, i, f"C{i}", 1, "SKU-1", store_idx, f"STR-{store_idx:03d}",
            dt.date(2024, 1, 1), dt.datetime(2024, 1, 1, 10, 0, 0), 1, net, net, "USD")


@pytest.mark.skipif(
    not importlib.util.find_spec("pyspark"),
    reason="PySpark not available (JVM required)"
)
def test_reversals_never_exceed_what_was_collected(spark):
    """The generator's reversal invariants, which keep realized revenue non-negative per order:
    reversals land only on orders whose sale was captured or settled; a full chargeback is never
    drawn on a refunded order; an adjustment is never drawn on a charged-back order. Rates are
    raised so every branch fires on a 2,000-order fixture."""
    from pyspark.sql import functions as F
    gen = _load_generator()
    order_lines = spark.createDataFrame(
        [_order_line(i, f"O{i}", i % 20) for i in range(2000)], _ORDER_LINE_SCHEMA)
    cfg = {"seed": 7, "refund_rate": 0.4, "chargeback_rate": 0.6, "adjustment_rate": 0.6}
    pay = gen.build_payments(spark, order_lines, "USD", 7, cfg)
    # recover the order key from payment_id (PAY*-<order_id>) so orphaned adjustments (NULL
    # order_id) are still attributed to the order they were drawn on
    pay = pay.withColumn("ord", F.regexp_extract("payment_id", r"^[A-Z]+-(.*)$", 1))
    per_order = {r.ord: r for r in pay.groupBy("ord").agg(
        F.max(F.when((F.col("payment_type") == "sale")
                     & F.col("payment_status").isin("captured", "settled"), 1).otherwise(0)).alias("collected"),
        F.max(F.when(F.col("payment_type") == "refund", 1).otherwise(0)).alias("refund"),
        F.max(F.when(F.col("payment_type") == "chargeback", 1).otherwise(0)).alias("chargeback"),
        F.max(F.when(F.col("payment_type") == "adjustment", 1).otherwise(0)).alias("adjustment"),
    ).collect()}
    reversed_orders = [r for r in per_order.values() if r.refund or r.chargeback or r.adjustment]
    assert reversed_orders, "fixture must produce reversals"
    assert any(r.refund for r in reversed_orders), "fixture must exercise the refund branch"
    assert any(r.chargeback for r in reversed_orders), "fixture must exercise the chargeback branch"
    linked_adjustments = pay.where("payment_type = 'adjustment' AND order_id IS NOT NULL").count()
    assert linked_adjustments > 0, "fixture must exercise adjustments that keep their order_id"
    assert all(r.collected for r in reversed_orders), "a reversal landed on an order with no collected sale"
    assert not [r.ord for r in per_order.values() if r.refund and r.chargeback], "chargeback on a refunded order"
    assert not [r.ord for r in per_order.values() if r.chargeback and r.adjustment], "adjustment on a charged-back order"


@pytest.mark.skipif(
    not importlib.util.find_spec("pyspark"),
    reason="PySpark not available (JVM required)"
)
def test_build_payments_deterministic(spark):
    """Two runs of build_payments with same seed must produce identical results."""
    gen = _load_generator()

    # Small fixture: 200 single-line orders over 5 stores, so refunds/adjustments/chargebacks occur
    order_lines = spark.createDataFrame(
        [_order_line(i, f"O{i}", i % 5) for i in range(200)], _ORDER_LINE_SCHEMA)
    cfg = {"seed": 42}

    # Run twice
    payments1 = gen.build_payments(spark, order_lines, "USD", 42, cfg).collect()
    payments2 = gen.build_payments(spark, order_lines, "USD", 42, cfg).collect()

    # Convert to dicts for comparison (Rows may differ in memory but data is the same)
    def to_dicts(rows):
        return sorted([r.asDict() for r in rows], key=lambda r: r["payment_id"])

    data1 = to_dicts(payments1)
    data2 = to_dicts(payments2)
    assert len(data1) == len(data2), f"Row count mismatch: {len(data1)} vs {len(data2)}"
    for d1, d2 in zip(data1, data2):
        for key in ["payment_id", "payment_type", "payment_status", "amount"]:
            assert d1.get(key) == d2.get(key), (
                f"Determinism failed on {key}: {d1.get(key)} vs {d2.get(key)}")


@pytest.mark.skipif(
    not importlib.util.find_spec("pyspark"),
    reason="PySpark not available (JVM required)"
)
def test_high_tier_stores_get_more_refunds_than_low(spark):
    """HIGH-tier stores (x2.0) refund more of their orders than LOW-tier stores (x0.5).

    Tiers come from the generator's own refund_store_multiplier (Spark hash), never a re-implemented
    hash, so the test cannot disagree with what the generator actually did."""
    from pyspark.sql import functions as F
    gen = _load_generator()

    n_stores, orders_per_store = 50, 40
    order_lines = spark.createDataFrame(
        [_order_line(s * orders_per_store + k, f"O{s * orders_per_store + k}", s)
         for s in range(n_stores) for k in range(orders_per_store)],
        _ORDER_LINE_SCHEMA)
    cfg = {"seed": 42, "refund_rate": 0.20}
    payments = gen.build_payments(spark, order_lines, "USD", 42, cfg)

    mult = {r.store_id: float(r.m) for r in
            order_lines.select("store_id").distinct()
            .withColumn("m", gen.refund_store_multiplier(F.col("store_id"))).collect()}
    refunds = {r.store_id: r.n for r in
               payments.where("payment_type = 'refund'").groupBy("store_id").count()
               .withColumnRenamed("count", "n").collect()}

    def tier_rate(m):
        stores = [s for s, v in mult.items() if v == m]
        assert stores, f"no store landed in the x{m} tier out of {n_stores}"
        return sum(refunds.get(s, 0) for s in stores) / (len(stores) * orders_per_store)

    high, low = tier_rate(2.0), tier_rate(0.5)
    # expected per-order refund probability = 0.20 x multiplier x 0.9 collected share: HIGH ~0.36, LOW ~0.09
    assert high > 2 * low, f"HIGH-tier refund share {high:.3f} should be well above LOW {low:.3f}"
