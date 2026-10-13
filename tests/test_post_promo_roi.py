"""Tests for the Post-Promotion ROI use case.

Static contract tests keep the gold views consistent and guardrail-clean.
Engine tests run the REAL gold SQL (gold_weekly_baseline -> gold_promo_roi_by_category
-> gold_promo_roi) on Spark (the Databricks engine) over temp-view fixtures with hand-computed
expectations, proving the ROI math, cannibalization and forward-buy detection,
and the divide-by-zero -> NULL path.
"""

import os
import re

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.ordm_config import resolve, view_select_body

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GOLD = os.path.join(REPO, "outcome-packages", "promote-with-purpose", "gold")
WB = os.path.join(GOLD, "gold_weekly_baseline.sql")
BYCAT = os.path.join(GOLD, "gold_promo_roi_by_category.sql")
ROI = os.path.join(GOLD, "gold_promo_roi.sql")
PERF = os.path.join(GOLD, "gold_promo_performance.sql")
PRODUCT_DDL = os.path.join(REPO, "canonical-core", "product", "tables", "product.sql")


# ---------- static ----------

@pytest.mark.parametrize("path", [WB, BYCAT, ROI, PERF])
def test_view_parses(path):
    # Parse the SELECT body (form-agnostic: views and materialized views alike).
    sel = sqlglot.parse_one(view_select_body(resolve(open(path).read(), "c")),
                            read="databricks", error_level="ignore")
    assert sel is not None and sel.named_selects, f"{os.path.basename(path)} did not parse"


def test_roi_view_exposes_required_columns():
    sel = sqlglot.parse_one(view_select_body(resolve(open(ROI).read(), "c")),
                            read="databricks", error_level="ignore")
    outputs = set(sel.named_selects)
    required = {"promo_id", "baseline_units", "baseline_revenue", "baseline_margin",
                "incremental_units", "incremental_revenue", "incremental_margin",
                "trade_spend", "roi", "planned_lift_pct", "realized_lift_pct",
                "cannibalization_units", "cannibalization_margin",
                "forward_buy_units", "forward_buy_margin", "net_incremental_margin"}
    assert required <= outputs, f"gold_promo_roi missing: {sorted(required - outputs)}"


def test_margin_source_present():
    cols = open(PRODUCT_DDL).read()
    assert re.search(r"\bunit_cost\b", cols), "product is missing unit_cost (margin source)"


def test_no_banned_or_hardcoded_in_gold():
    bad = []
    for f in os.listdir(GOLD):
        if not f.endswith(".sql"):
            continue
        txt = open(os.path.join(GOLD, f)).read()
        if re.search(r"GROUP\s+BY\s+ALL|\b1\s*=\s*1\b", txt, re.I) \
           or re.search(r"https?://[\w.-]*databricks|retail_prod|retail_dev|Copyright|SPDX|Licensed under", txt, re.I):
            bad.append(f)
    assert not bad, f"banned pattern / hardcoded id / license header in: {bad}"


# ---------- engine: Spark fixture running the real ROI SQL ----------

import datetime

_SUBS = [
    ("${catalog}.${transaction_schema}.sales", "sales"),
    ("${catalog}.${calendar_schema}.fiscal_calendar", "fiscal_calendar"),
    ("${catalog}.${product_schema}.product", "product"),
    ("${catalog}.${promo_schema}.promotion_scope", "promotion_scope"),
    ("${catalog}.${promo_schema}.gold_weekly_baseline", "gold_weekly_baseline"),
    ("${catalog}.${promo_schema}.gold_promo_roi_by_category", "gold_promo_roi_by_category"),
    ("${catalog}.${marketing_schema}.promotion", "promotion"),
]
_BASE = datetime.date(2024, 1, 7)


def _view_body(path):
    # The REAL gold SQL with UC names rewritten to fixture temp views; Spark runs it
    # verbatim. view_select_body handles both plain and materialized view headers.
    body = view_select_body(open(path).read())
    for a, b in _SUBS:
        body = body.replace(a, b)
    return body


def _wk_date(wk):
    return _BASE + datetime.timedelta(days=(wk - 1) * 7)


def _build(spark):
    spark.createDataFrame(
        [(1, "P1", "bev", 10.0, 6.0, True), (2, "P2", "bev", 10.0, 6.0, True), (3, "P3", "snack", 10.0, 6.0, True)],
        "product_sk int, product_id string, category string, list_price double, unit_cost double, is_current boolean",
    ).createOrReplaceTempView("product")
    spark.createDataFrame(
        [(_wk_date(wk), 202400 + wk, wk) for wk in range(1, 16)],
        "date_key date, fiscal_week_id int, fiscal_week_index int",
    ).createOrReplaceTempView("fiscal_calendar")
    spark.createDataFrame(
        [(99, "NO_PROMO", "No Promotion", None, None, None, None, None, None, None, None, None, True),
         (1, "PR1", "Promo 1", "TPR", "SCAN_DOWN", "SHARED",
          datetime.date(2024, 3, 10), datetime.date(2024, 3, 23), 100.0, 50.0, 202410, 202411, True),
         (2, "PR2", "Promo 2", "FEATURE", "BILL_BACK", "SUPPLIER",
          datetime.date(2024, 2, 4), datetime.date(2024, 2, 10), 0.0, 30.0, 202405, 202405, True)],
        "promo_sk int, promo_id string, promo_name string, promo_type string, funding_type string, "
        "funded_by string, start_date date, end_date date, planned_trade_spend double, planned_lift_pct double, "
        "fiscal_week_start int, fiscal_week_end int, is_current boolean",
    ).createOrReplaceTempView("promotion")
    spark.createDataFrame([(1, 1, 1), (2, 3, 1)], "promo_sk int, product_sk int, store_sk int") \
         .createOrReplaceTempView("promotion_scope")

    sales = []

    def ins(product_sk, wk, promo_id, units, net):
        sales.append((product_sk, 1, promo_id, _wk_date(wk), units, float(net)))

    for wk in range(1, 16):
        # P1: normal, then promoted weeks 10-11, then forward-buy dip 12-13, then normal
        if wk in (10, 11):
            ins(1, wk, "PR1", 15, 135)          # promoted (10% off): 15 units, net 135
        elif wk in (12, 13):
            ins(1, wk, "NO_PROMO", 4, 40)        # forward-buy dip below baseline (~10)
        else:
            ins(1, wk, "NO_PROMO", 10, 100)
        # P2: substitute (bev), cannibalized during PR1 window 10-11
        if wk in (10, 11):
            ins(2, wk, "NO_PROMO", 5, 50)        # cannibalization dip below baseline
        else:
            ins(2, wk, "NO_PROMO", 10, 100)
        # P3: promoted by PR2 (zero trade spend) week 5
        if wk == 5:
            ins(3, wk, "PR2", 12, 108)
        else:
            ins(3, wk, "NO_PROMO", 10, 100)
    spark.createDataFrame(
        sales, "product_sk int, store_sk int, promo_id string, date_key date, units int, net_revenue double"
    ).createOrReplaceTempView("sales")

    spark.sql("CREATE OR REPLACE TEMP VIEW gold_weekly_baseline AS " + _view_body(WB))
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_promo_roi_by_category AS " + _view_body(BYCAT))
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_promo_roi AS " + _view_body(ROI))


def test_roi_returns_rows(spark):
    _build(spark)
    n = spark.sql("SELECT COUNT(*) AS n FROM gold_promo_roi").first().n
    assert n == 2, f"expected PR1 and PR2, got {n}"


def test_roi_math_known_values(spark):
    _build(spark)
    row = spark.sql("SELECT incremental_margin, trade_spend, roi FROM gold_promo_roi WHERE promo_id='PR1'").first()
    inc_margin, spend, roi = (float(x) for x in row)
    # promoted_margin = 2*(135 - 15*6) = 90 ; baseline_margin = 20 units * (10-6) = 80
    assert inc_margin == pytest.approx(10.0), inc_margin
    assert spend == pytest.approx(100.0), spend
    assert roi == pytest.approx(0.10), roi          # 10 / 100


def test_cannibalization_detected(spark):
    _build(spark)
    cu, cm = spark.sql("SELECT cannibalization_units, cannibalization_margin "
                       "FROM gold_promo_roi WHERE promo_id='PR1'").first()
    # P2 dip: wk10 (10-5)=5, wk11 (9.375-5)=4.375 -> 9.375 units ; margin 9.375*4 = 37.5
    assert float(cu) == pytest.approx(9.375), cu
    assert float(cm) == pytest.approx(37.5), cm


def test_forward_buy_detected(spark):
    _build(spark)
    fu, fm = spark.sql("SELECT forward_buy_units, forward_buy_margin "
                       "FROM gold_promo_roi WHERE promo_id='PR1'").first()
    # P1 post weeks 12,13: (10-4)=6 + (9-4)=5 -> 11 units ; margin 11*4 = 44
    assert float(fu) == pytest.approx(11.0), fu
    assert float(fm) == pytest.approx(44.0), fm


def test_net_incremental_margin_goes_negative(spark):
    _build(spark)
    net = spark.sql("SELECT net_incremental_margin FROM gold_promo_roi WHERE promo_id='PR1'").first()[0]
    # 10 (incremental) - 37.5 (cannib) - 44 (forward buy) = -71.5
    assert float(net) == pytest.approx(-71.5), net
    any_neg = spark.sql("SELECT COUNT(*) AS n FROM gold_promo_roi WHERE net_incremental_margin < 0").first().n
    assert any_neg >= 1


def test_divide_by_zero_returns_null(spark):
    _build(spark)
    roi = spark.sql("SELECT roi FROM gold_promo_roi WHERE promo_id='PR2'").first()[0]
    assert roi is None, f"zero trade spend must yield NULL roi, got {roi}"
