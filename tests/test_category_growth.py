"""Tests for Category Growth (gold_category_growth).

Static contract tests + a Spark fixture running the REAL view (Spark is the
Databricks engine; the SQL is executed verbatim, no dialect translation): the
four growth effects reconcile to delta_revenue, category_share sums to ~1 per
period, YoY uses the correct fiscal-period comparison, and the view degrades
gracefully (rows returned, upstream-derived columns NULL) when an upstream view
is empty.
"""

import datetime
import os
import re

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.ordm_config import resolve

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
VIEW = os.path.join(REPO, "outcome-packages", "data-sharing-with-suppliers", "gold", "gold_category_growth.sql")


# ---------- static ----------

def test_view_parses_and_exposes_columns():
    create = next(s for s in sqlglot.parse(resolve(open(VIEW).read(), "c"), read="databricks", error_level="ignore")
                  if isinstance(s, E.Create))
    outputs = set(create.expression.named_selects)
    required = {"category", "fiscal_year", "fiscal_period", "category_revenue", "category_margin",
                "delta_revenue", "pop_growth_pct", "yoy_growth_pct", "distribution_effect",
                "volume_effect", "price_effect", "mix_effect", "category_share",
                "promo_contribution", "value_share_platinum", "supplier_top_share"}
    assert required <= outputs, f"missing: {sorted(required - outputs)}"


def test_no_banned_or_hardcoded():
    txt = open(VIEW).read()
    assert not re.search(r"GROUP\s+BY\s+ALL|\b1\s*=\s*1\b", txt, re.I)
    assert not re.search(r"https?://[\w.-]*databricks|retail_prod|retail_dev|Copyright|SPDX|Licensed under", txt, re.I)


# ---------- engine: Spark fixture running the real view ----------

_SUBS = [
    ("${catalog}.${transaction_schema}.sales", "sales"),
    ("${catalog}.${product_schema}.product", "product"),
    ("${catalog}.${calendar_schema}.fiscal_calendar", "fiscal_calendar"),
    ("${catalog}.${promo_schema}.gold_promo_roi_by_category", "gold_promo_roi_by_category"),
    ("${catalog}.${order_schema}.customer_order_line", "customer_order_line"),
    ("${catalog}.${acu_schema}.gold_customer_ltv", "gold_customer_ltv"),
    ("${catalog}.${procurement_schema}.purchase_order_line", "purchase_order_line"),
    ("${catalog}.${risk_schema}.gold_supplier_scorecard", "gold_supplier_scorecard"),
]


def _view_body():
    # The REAL gold SQL, with the UC three-level names rewritten to the fixture
    # temp views. No dialect translation -- Spark IS the target engine.
    raw = open(VIEW).read()
    body = raw[raw.index(" AS", raw.index("CREATE OR REPLACE VIEW")) + 3:].strip().rstrip(";")
    for a, b in _SUBS:
        body = body.replace(a, b)
    return body


DA = datetime.date(2024, 1, 7)
DB = datetime.date(2024, 2, 7)
DY = datetime.date(2023, 2, 7)


def _build(spark, populate_upstream=False):
    spark.createDataFrame(
        [(1, "bev", "regular", 4.0), (2, "bev", "premium", 8.0), (3, "snack", "regular", 3.0)],
        "product_sk int, category string, subcategory string, unit_cost double",
    ).createOrReplaceTempView("product")
    spark.createDataFrame(
        [(DA, 2024, 1), (DB, 2024, 2), (DY, 2023, 2)],
        "date_key date, fiscal_year int, fiscal_period int",
    ).createOrReplaceTempView("fiscal_calendar")
    sales = [
        # period A: bev rev 300, units 25, dist 3 ; snack rev 40
        (1, 1, DA, 10, 100.0), (1, 2, DA, 10, 100.0), (2, 1, DA, 5, 100.0), (3, 1, DA, 8, 40.0),
        # period B: bev rev 484, units 34, dist 4 ; snack rev 40
        (1, 1, DB, 12, 132.0), (1, 2, DB, 12, 132.0), (2, 1, DB, 4, 88.0), (2, 2, DB, 6, 132.0), (3, 1, DB, 8, 40.0),
        # prior year for bev (fy2023 fp2)
        (1, 1, DY, 10, 90.0),
    ]
    spark.createDataFrame(sales, "product_sk int, store_sk int, date_key date, units int, net_revenue double") \
         .createOrReplaceTempView("sales")

    # upstream views as temp views -- empty unless populated (graceful-degradation)
    promo = [("bev", DB, 25.0)] if populate_upstream else []
    spark.createDataFrame(promo, "category string, end_date date, incremental_margin double") \
         .createOrReplaceTempView("gold_promo_roi_by_category")
    col = [(1, 1, DB, 200.0), (2, 2, DB, 100.0)] if populate_upstream else []
    spark.createDataFrame(col, "profile_sk int, product_sk int, order_date date, net_amount double") \
         .createOrReplaceTempView("customer_order_line")
    ltv = [(1, "PLATINUM"), (2, "BRONZE")] if populate_upstream else []
    spark.createDataFrame(ltv, "profile_sk int, value_tier string").createOrReplaceTempView("gold_customer_ltv")
    pol = [("SUP1", 1, 100, 5.0), ("SUP2", 2, 40, 5.0)] if populate_upstream else []
    spark.createDataFrame(pol, "supplier_id string, product_sk int, received_qty int, unit_price double") \
         .createOrReplaceTempView("purchase_order_line")
    sc = [("SUP1", 80.0), ("SUP2", 60.0)] if populate_upstream else []
    spark.createDataFrame(sc, "supplier_id string, composite_score double") \
         .createOrReplaceTempView("gold_supplier_scorecard")

    spark.sql("CREATE OR REPLACE TEMP VIEW gold_category_growth AS " + _view_body())


def _bevB(spark):
    return spark.sql("SELECT delta_revenue, distribution_effect, volume_effect, price_effect, mix_effect "
                     "FROM gold_category_growth WHERE category='bev' AND fiscal_year=2024 AND fiscal_period=2").first()


def test_decomposition_reconciles_to_delta_revenue(spark):
    _build(spark)
    r = _bevB(spark)
    delta, dist, vol, price, mix = (float(x) for x in r)
    assert delta == pytest.approx(184.0)
    assert (dist + vol + price + mix) == pytest.approx(delta, abs=1e-6)   # four effects reconcile
    assert dist == pytest.approx(100.0, abs=1e-6)
    assert vol == pytest.approx(8.0, abs=1e-6)
    assert price == pytest.approx(44.0, abs=1e-6)
    assert mix == pytest.approx(32.0, abs=1e-6)


def test_category_share_sums_to_one_per_period(spark):
    _build(spark)
    for fp in (1, 2):
        total = spark.sql(f"SELECT SUM(category_share) AS s FROM gold_category_growth "
                          f"WHERE fiscal_year=2024 AND fiscal_period={fp}").first().s
        assert float(total) == pytest.approx(1.0, abs=1e-9)


def test_yoy_uses_fiscal_period_comparison(spark):
    _build(spark)
    yoy = spark.sql("SELECT yoy_growth_pct FROM gold_category_growth "
                    "WHERE category='bev' AND fiscal_year=2024 AND fiscal_period=2").first()[0]
    assert float(yoy) == pytest.approx(100.0 * (484 - 90) / 90, abs=1e-6)
    pop1 = spark.sql("SELECT pop_growth_pct FROM gold_category_growth "
                     "WHERE category='bev' AND fiscal_year=2024 AND fiscal_period=1").first()[0]
    assert pop1 is None   # no prior period


def test_first_period_has_no_decomposition(spark):
    # With no prior period, delta_revenue and ALL four effects are NULL. price_effect
    # used to equal the period's whole revenue there (p0 falls back to 0), which
    # inflated every roll-up of the effects (e.g. mv_category_growth totals).
    _build(spark)
    r = spark.sql("SELECT delta_revenue, distribution_effect, volume_effect, price_effect, mix_effect "
                  "FROM gold_category_growth WHERE category='bev' AND fiscal_year=2024 AND fiscal_period=1").first()
    assert r is not None
    assert all(v is None for v in r), r


def test_graceful_degradation_when_upstream_absent(spark):
    _build(spark, populate_upstream=False)
    row = spark.sql("SELECT promo_contribution, value_share_platinum, top_supplier_id, supplier_top_share "
                    "FROM gold_category_growth WHERE category='bev' AND fiscal_period=2").first()
    assert all(v is None for v in row), f"expected NULL upstream columns when absent, got {row}"
    assert spark.sql("SELECT COUNT(*) AS n FROM gold_category_growth").first().n > 0


def test_upstream_signals_populate_when_present(spark):
    _build(spark, populate_upstream=True)
    r = spark.sql("SELECT promo_contribution, value_share_platinum, top_supplier_id, supplier_top_score "
                  "FROM gold_category_growth WHERE category='bev' AND fiscal_year=2024 AND fiscal_period=2").first()
    assert float(r.promo_contribution) == pytest.approx(25.0)
    assert float(r.value_share_platinum) == pytest.approx(200.0 / 300.0)
    assert r.top_supplier_id == 'SUP1'
    assert float(r.supplier_top_score) == pytest.approx(80.0)
