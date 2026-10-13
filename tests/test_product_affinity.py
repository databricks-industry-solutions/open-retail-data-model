"""Tests for Product Affinity (gold_product_affinity_pairwise + gold_customer_product_affinity).

Static contract tests (output columns, PII absence, no banned/hardcoded SQL) plus Spark
fixtures running the REAL gold view SQL on small known-answer baskets: market-basket
support/confidence/lift on a deliberately correlated fixture (ORDM's synthetic baskets are
uniform-random, so real correlation is faint there), and the recency-weighted
purchase-history affinity score reproduced from the documented heuristic.
"""

import datetime
import os
import re

import pytest
import sqlglot

from tools.ordm_config import resolve, view_select_body

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ACU = os.path.join(REPO, "outcome-packages", "actionable-customer-understanding")
PAIRWISE = os.path.join(ACU, "gold", "gold_product_affinity_pairwise.sql")
CUST_PROD = os.path.join(ACU, "gold", "gold_customer_product_affinity.sql")

PII_COLUMNS = {"loyalty_id", "household_id", "first_name", "middle_name", "last_name",
               "date_of_birth", "name_prefix", "name_suffix", "contact_value"}


def _outputs(path):
    sel = sqlglot.parse_one(view_select_body(resolve(open(path).read(), "c")),
                            read="databricks", error_level="ignore")
    return set(sel.named_selects)


# ---------- static ----------

def test_pairwise_exposes_required_columns():
    required = {"product_affinity_id", "product_id_a", "product_id_b", "time_window",
                "cooccurrence_baskets", "total_baskets", "support", "confidence", "lift"}
    assert required <= _outputs(PAIRWISE), f"missing: {sorted(required - _outputs(PAIRWISE))}"


def test_customer_product_exposes_required_columns():
    required = {"customer_product_affinity_id", "profile_id", "product_id", "purchase_count",
                "recency_weight", "affinity_score", "affinity_band", "primary_driver"}
    assert required <= _outputs(CUST_PROD), f"missing: {sorted(required - _outputs(CUST_PROD))}"


def test_no_raw_pii_in_affinity_views():
    # Neither serving surface exposes raw PII; the customer view keys on the pseudonymous
    # profile_id, and the pairwise view carries no customer key at all.
    for path in (PAIRWISE, CUST_PROD):
        leaked = PII_COLUMNS & _outputs(path)
        assert not leaked, f"{os.path.basename(path)} exposes raw PII: {sorted(leaked)}"
    assert "profile_id" in _outputs(CUST_PROD)
    assert not (PII_COLUMNS & _outputs(PAIRWISE)) and "profile_id" not in _outputs(PAIRWISE)


def test_no_banned_or_hardcoded():
    for path in (PAIRWISE, CUST_PROD):
        txt = open(path).read()
        assert not re.search(r"GROUP\s+BY\s+ALL|\b1\s*=\s*1\b", txt, re.I), path
        assert not re.search(r"https?://[\w.-]*databricks|retail_prod|retail_dev|Copyright|SPDX|Licensed under",
                             txt, re.I), path


# ---------- engine: Spark fixtures running the real views ----------

_SUBS = [
    ("${catalog}.${order_schema}.customer_order_line", "customer_order_line"),
    ("${catalog}.${product_schema}.product", "product"),
]
_ORDER_SCHEMA = ("profile_id string, order_id string, product_id string, "
                 "order_date date, event_timestamp timestamp, units int, net_amount double, "
                 "currency_code string")
_PRODUCT_SCHEMA = ("product_id string, product_name string, category string, "
                   "subcategory string, brand string, is_current boolean")
_PRODUCTS = [
    ("P1", "Widget", "Hardware", "Fasteners", "Acme", True),
    ("P2", "Gadget", "Hardware", "Tools", "Acme", True),
    ("P3", "Gizmo", "Grocery", "Snacks", "Yum", True),
    ("P4", "Doohickey", "Grocery", "Pantry", "Yum", True),
    ("P5", "Thingamajig", "Grocery", "Pantry", "Yum", True),
]


def _body(path):
    body = view_select_body(open(path).read())
    for a, b in _SUBS:
        body = body.replace(a, b)
    return body


def _make(spark, order_rows):
    spark.createDataFrame(order_rows, _ORDER_SCHEMA).createOrReplaceTempView("customer_order_line")
    spark.createDataFrame(_PRODUCTS, _PRODUCT_SCHEMA).createOrReplaceTempView("product")


def _o(order_id, product_id, profile_id="C1", d=(2024, 1, 1)):
    # event_timestamp = noon of the order date (a real intraday instant, not midnight),
    # so gold_customer_product_affinity.last_purchased_at (MAX event_timestamp) is exercised.
    return (profile_id, order_id, product_id, datetime.date(*d), datetime.datetime(*d, 12),
            1, 10.0, "USD")


def _pairwise_build(spark):
    # RECENT baskets (2024-06-30, inside every window): 8 contain BOTH P1 and P2, P1 alone in 2
    #   more, P2 alone in 2 more, P3 alone in 6 -> recent total=18, item(P1)=10, item(P2)=10,
    #   item(P3)=6, pair(P1,P2)=8.
    # OLD baskets (2024-01-01, ~181 days back -> only inside ALL_TIME): 5 contain BOTH P4 and P5.
    # as_of = MAX(order_date) = 2024-06-30. 30D cutoff 2024-05-31, 90D cutoff 2024-04-01.
    #   30D / 90D: recent only (total 18). P1,P2: support 8/18, conf 0.8, lift 1.44. P4,P5 absent.
    #   ALL_TIME: total 23. P1,P2: lift (8/23)/((10/23)^2)=1.84. P4,P5: (5/23)/((5/23)^2)=4.6, conf 1.0.
    recent, old = (2024, 6, 30), (2024, 1, 1)
    rows = []
    for i in range(1, 9):
        rows += [_o(f"O{i}", "P1", d=recent), _o(f"O{i}", "P2", d=recent)]
    rows += [_o("O9", "P1", d=recent), _o("O10", "P1", d=recent)]
    rows += [_o("O11", "P2", d=recent), _o("O12", "P2", d=recent)]
    rows += [_o(f"O{i}", "P3", d=recent) for i in range(13, 19)]
    for i in range(19, 24):
        rows += [_o(f"O{i}", "P4", d=old), _o(f"O{i}", "P5", d=old)]
    _make(spark, rows)
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_product_affinity_pairwise AS " + _body(PAIRWISE))


def test_pairwise_market_basket_math(spark):
    _pairwise_build(spark)
    # Core algebra on the 30D window (recent only, total=18). Both directions of the one
    # correlated pair; P3 (always bought alone) pairs with nothing.
    r = spark.sql("""SELECT support, confidence, lift, cooccurrence_baskets, total_baskets,
                            is_mirrored_pair
                     FROM gold_product_affinity_pairwise
                     WHERE product_id_a='P1' AND product_id_b='P2' AND time_window='30D'""").first()
    assert float(r.support) == pytest.approx(8 / 18, abs=1e-4)
    assert float(r.confidence) == pytest.approx(0.8, abs=1e-4)
    assert float(r.lift) == pytest.approx(1.44, abs=1e-4)
    assert r.cooccurrence_baskets == 8 and r.total_baskets == 18
    # is_mirrored_pair = (product_id_a > product_id_b): 'P1' > 'P2' is False here, True on mirror.
    assert r.is_mirrored_pair is False
    mirror = spark.sql("""SELECT is_mirrored_pair FROM gold_product_affinity_pairwise
                          WHERE product_id_a='P2' AND product_id_b='P1' AND time_window='30D'""").first()
    assert mirror.is_mirrored_pair is True
    assert spark.sql("""SELECT COUNT(*) AS n FROM gold_product_affinity_pairwise
                        WHERE product_id_a='P3' OR product_id_b='P3'""").first().n == 0


def test_pairwise_trailing_windows(spark):
    _pairwise_build(spark)
    # All three windows are emitted; each recent pair appears in every window it qualifies for.
    assert {r.time_window for r in spark.sql(
        "SELECT DISTINCT time_window FROM gold_product_affinity_pairwise").collect()} \
        == {"30D", "90D", "ALL_TIME"}
    # 8 rows total: P1<->P2 in 30D/90D/ALL_TIME (2 dirs x 3) + P4<->P5 in ALL_TIME only (2 dirs).
    assert spark.sql("SELECT COUNT(*) AS n FROM gold_product_affinity_pairwise").first().n == 8

    # The window changes the denominator, so the same pair's lift differs by window.
    def lift(a, b, win):
        row = spark.sql(f"""SELECT lift FROM gold_product_affinity_pairwise
                            WHERE product_id_a='{a}' AND product_id_b='{b}'
                              AND time_window='{win}'""").first()
        return None if row is None else float(row.lift)
    assert lift("P1", "P2", "30D") == pytest.approx(1.44, abs=1e-4)
    assert lift("P1", "P2", "90D") == pytest.approx(1.44, abs=1e-4)   # old data is >90d out
    assert lift("P1", "P2", "ALL_TIME") == pytest.approx(1.84, abs=1e-4)  # denominator 23, not 18

    # A pair present ONLY in old baskets surfaces in ALL_TIME but not the trailing windows.
    assert lift("P4", "P5", "ALL_TIME") == pytest.approx(4.6, abs=1e-4)
    assert lift("P4", "P5", "30D") is None and lift("P4", "P5", "90D") is None
    assert spark.sql("""SELECT COUNT(*) AS n FROM gold_product_affinity_pairwise
                        WHERE (product_id_a IN ('P4','P5') OR product_id_b IN ('P4','P5'))
                          AND time_window IN ('30D','90D')""").first().n == 0


def test_pairwise_lift_labels_resolved(spark):
    _pairwise_build(spark)
    r = spark.sql("""SELECT category_a, brand_a, product_name_b
                     FROM gold_product_affinity_pairwise
                     WHERE product_id_a='P1' AND product_id_b='P2' AND time_window='ALL_TIME'""").first()
    assert r.category_a == "Hardware" and r.brand_a == "Acme" and r.product_name_b == "Gadget"


def _cust_prod_build(spark):
    # as_of_date = MAX(order_date) = 2024-06-30 (C1's last P1 order).
    #   C1×P1: 5 orders, last 2024-06-30 -> days 0, intensity min(1,5/5)=1, recency 1.0, score 1.0 (high)
    #   C2×P2: 1 order 2024-04-01 (90d back) -> intensity 0.2, recency 0.5, score 0.10 (low)
    #   C3×P3: 3 orders, last 2024-05-16 (45d back) -> intensity 0.6, recency 0.5^0.5=0.7071, score 0.4243 (medium)
    rows = [_o(f"C1-O{i}", "P1", "C1", (2024, 2, i)) for i in range(1, 5)]
    rows.append(_o("C1-O5", "P1", "C1", (2024, 6, 30)))
    rows.append(_o("C2-O1", "P2", "C2", (2024, 4, 1)))
    rows += [_o(f"C3-O{i}", "P3", "C3", (2024, 3, i)) for i in range(1, 3)]
    rows.append(_o("C3-O3", "P3", "C3", (2024, 5, 16)))
    _make(spark, rows)
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_customer_product_affinity AS " + _body(CUST_PROD))


def test_customer_product_affinity_score(spark):
    _cust_prod_build(spark)
    assert spark.sql("SELECT COUNT(*) AS n FROM gold_customer_product_affinity").first().n == 3
    rows = {(r.profile_id, r.product_id): r for r in spark.sql(
        """SELECT profile_id, product_id, purchase_count, days_since_last_purchase,
                  recency_weight, affinity_score, affinity_band, primary_driver,
                  last_purchased_at, last_purchase_date
           FROM gold_customer_product_affinity""").collect()}

    c1 = rows[("C1", "P1")]
    assert c1.purchase_count == 5 and c1.days_since_last_purchase == 0
    assert float(c1.recency_weight) == pytest.approx(1.0, abs=1e-4)
    assert float(c1.affinity_score) == pytest.approx(1.0, abs=1e-4)
    assert c1.affinity_band == "high" and c1.primary_driver == "PURCHASE_HISTORY"
    # last_purchased_at is the real event instant (MAX event_timestamp = noon of the last
    # purchase), NOT midnight of last_purchase_date — it carries time-of-day.
    assert c1.last_purchased_at == datetime.datetime(2024, 6, 30, 12)
    assert c1.last_purchased_at.hour == 12

    c2 = rows[("C2", "P2")]
    assert c2.days_since_last_purchase == 90
    assert float(c2.recency_weight) == pytest.approx(0.5, abs=1e-4)
    assert float(c2.affinity_score) == pytest.approx(0.1, abs=1e-4)  # min(1, 0.2 * 0.5)
    assert c2.affinity_band == "low"

    c3 = rows[("C3", "P3")]
    assert c3.days_since_last_purchase == 45
    assert float(c3.affinity_score) == pytest.approx(0.6 * (0.5 ** 0.5), abs=1e-4)  # ~0.4243
    assert c3.affinity_band == "medium"


# ---------- end-to-end: the order generator's seeded co-purchase populates the surface ----------

def _load_generator():
    """Load the customer_ltv generator module with its sibling _common importable."""
    import importlib.util
    gen_dir = os.path.join(REPO, "runtime", "synthetic-data", "generators")
    if gen_dir not in os.sys.path:
        os.sys.path.insert(0, gen_dir)
    spec = importlib.util.spec_from_file_location(
        "ordm_customer_ltv_gen_affinity", os.path.join(gen_dir, "customer_ltv.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_generator_seeding_populates_pairwise_affinity(spark):
    # build_order_lines seeds a light co-purchase pattern so gold_product_affinity_pairwise is
    # NON-empty on generated data (uniform-random baskets alone would leave it empty). Run the
    # REAL generator + the REAL pairwise view and assert a seeded affinity pair surfaces.
    gen = _load_generator()
    n_products = 40
    products = spark.createDataFrame(
        [(i, f"P{i:02d}", 10.0 + i) for i in range(n_products)],
        "product_sk int, product_id string, list_price double")
    profiles = spark.createDataFrame(
        [(i, f"C{i:03d}") for i in range(80)], "profile_sk int, profile_id string")
    stores = spark.createDataFrame(
        [(i, f"S{i}") for i in range(3)], "store_sk int, store_id string")

    # affinity_denom=4 enables the opt-in co-purchase seeding (default is 0/neutral).
    lines = gen.build_order_lines(
        spark, profiles, products, stores, datetime.date(2024, 1, 1), 90,
        seed=4004, max_orders=6, value_skew=1.0, lines_per_order_max=4, base_currency="USD",
        affinity_denom=4, affinity_pair_count=gen.AFFINITY_PAIR_COUNT)
    lines.createOrReplaceTempView("customer_order_line")
    # the product label dim the pairwise view LEFT-joins (current version).
    spark.createDataFrame(
        [(f"P{i:02d}", f"Prod {i}", "Cat", "Sub", "Brand", True) for i in range(n_products)],
        _PRODUCT_SCHEMA).createOrReplaceTempView("product")
    spark.sql("CREATE OR REPLACE TEMP VIEW gpa AS " + _body(PAIRWISE))

    # The seeding forces stable (anchor, partner) pairs to co-occur far above chance, so the
    # surface is non-empty AND carries strong-lift pairs (uniform-random baskets would clear
    # almost nothing at lift >= 1.05). Assert both, implementation-agnostically (the pair
    # products are hash-derived, not a fixed product index).
    r = spark.sql(
        "SELECT COUNT(*) AS n, MAX(lift) AS maxlift FROM gpa WHERE time_window = 'ALL_TIME'").first()
    assert r.n > 0, "the seeded generator must populate gold_product_affinity_pairwise"
    assert float(r.maxlift) > 1.5, "seeding must create strong co-occurrence (lift >> 1), not noise"


def test_generator_seeding_is_off_by_default_and_scoped(spark):
    # M1 guard: the co-purchase seeding must be OPT-IN (default neutral) and, when on, touch ONLY
    # the first two lines of themed baskets — so it never silently reshapes the core order fact
    # that CLV / Behavioral / Market Analysis read. Run the generator with seeding OFF (default)
    # vs ON on the same fixture+seed and compare the per-line product assignment.
    gen = _load_generator()
    n_products = 40
    products = spark.createDataFrame(
        [(i, f"P{i:02d}", 10.0 + i) for i in range(n_products)],
        "product_sk int, product_id string, list_price double")
    profiles = spark.createDataFrame(
        [(i, f"C{i:03d}") for i in range(50)], "profile_sk int, profile_id string")
    stores = spark.createDataFrame([(i, f"S{i}") for i in range(3)], "store_sk int, store_id string")
    args = (spark, profiles, products, stores, datetime.date(2024, 1, 1), 90)
    kw = dict(seed=4004, max_orders=5, value_skew=1.0, lines_per_order_max=4, base_currency="USD")

    def pmap(df):
        return {(r.order_id, r.line_idx): r.product_id
                for r in df.select("order_id", "line_idx", "product_id").collect()}

    neutral = pmap(gen.build_order_lines(*args, **kw))                         # default: affinity_denom=0
    seeded = pmap(gen.build_order_lines(*args, affinity_denom=4, **kw))

    assert neutral.keys() == seeded.keys(), "seeding must not add/remove order lines"
    # lines beyond the first two are NEVER touched by seeding.
    assert all(neutral[k] == seeded[k] for k in neutral if k[1] >= 3), \
        "seeding must leave line_idx >= 3 byte-identical"
    # ...and it does change some first/second lines (proves the flag is live, not a no-op).
    assert any(neutral[k] != seeded[k] for k in neutral if k[1] in (1, 2)), \
        "affinity_denom=4 must actually seed co-purchase pairs on the first two lines"
