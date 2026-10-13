"""Golden fixture for gold_price_actuals (Balancing Margin and Volume).

This is the fix-agnostic regression test for the flagship SCD2 fan-out defect
(standard §A.16): gold_price_actuals joins the product_price history
table on `product_sk + price_type` with no as-of predicate, so once product_price
carries more than one price version per product, each daily sales row fans out to
every historical version — multiplying units, net sales, and every margin metric.

The fixture builds exactly that condition: one product with TWO `list` price
versions sharing one `product_sk`. Spark (the Databricks engine) runs the REAL
gold SQL verbatim on temp-view fixtures.

Two of the assertions are marked xfail(strict=True): they encode the CORRECT
behaviour (one row per product x store x date; the list price resolved as-of the
sale date). They fail against today's fan-out view, so they are xfail now — and
when the fix-the-views PR lands, they XPASS, which a strict xfail turns into a
failure, forcing the marker to be removed. That is the built-in forcing function
that ties this test to the fix. The remaining assertion (the harness runs the real
SQL and returns rows) is green today, proving the fixture + CLUSTER BY strip work.
"""
import os

import pytest

from tools.ordm_config import view_select_body

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
VIEW = os.path.join(REPO, "outcome-packages", "balancing-margin-and-volume",
                    "gold", "gold_price_actuals.sql")

_SUBS = [
    ("${catalog}.${transaction_schema}.sales", "sales"),
    ("${catalog}.${product_schema}.product_price", "product_price"),
    ("${catalog}.${product_schema}.product", "product"),
]

# sales fact: minimal columns the view reads (units>0, net_revenue, keys).
_SALES = "sales_id string, date_key date, product_sk long, product_id string, " \
         "store_sk long, store_id string, units int, net_revenue double"
# product dim (current snapshot): the view reads list_price + product_sk PK.
_PRODUCT = "product_sk long, product_id string, list_price double, is_current boolean"
# product_price history: PK product_price_sk + non-PK product_sk + SCD2 window.
_PRICE = "product_price_sk long, product_id string, product_sk long, price_type string, " \
         "amount double, effective_from_date date, effective_to_date date, is_current boolean"


def _view_body():
    # Substitute the ${...} token FQNs directly to bare temp-view names (do NOT
    # resolve() first — that would expand ${catalog} to a catalog part and leave a
    # 3-part name Spark's default catalog rejects). Mirrors test_customer_ltv.
    body = view_select_body(open(VIEW).read())
    for a, b in _SUBS:
        body = body.replace(a, b)
    return body


def _build(spark):
    import datetime as dt
    d = dt.date
    # One product (product_sk=1). Two LIST price versions sharing product_sk=1:
    #   $10 effective [2024-01-01, 2024-06-01), $12 effective [2024-06-01, open).
    # Plus one cost version. This is the fan-out trigger.
    spark.createDataFrame(
        [(1, "SKU-1", 12.0, True)], _PRODUCT).createOrReplaceTempView("product")
    spark.createDataFrame([
        (101, "SKU-1", 1, "list", 10.0, d(2024, 1, 1), d(2024, 6, 1), False),
        (102, "SKU-1", 1, "list", 12.0, d(2024, 6, 1), None, True),
        (201, "SKU-1", 1, "cost", 6.0, d(2024, 1, 1), None, True),
    ], _PRICE).createOrReplaceTempView("product_price")
    # Two sales days: one under each list-price regime.
    spark.createDataFrame([
        ("S1", d(2024, 3, 15), 1, "SKU-1", 1, "STR-1", 5, 50.0),
        ("S2", d(2024, 7, 15), 1, "SKU-1", 1, "STR-1", 5, 60.0),
    ], _SALES).createOrReplaceTempView("sales")
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_price_actuals AS " + _view_body())


def test_view_runs_and_returns_rows(spark):
    """Green today: the real gold SQL parses (CLUSTER BY stripped) and executes on
    the multi-version fixture. Guards the harness itself."""
    _build(spark)
    assert spark.sql("SELECT COUNT(*) AS n FROM gold_price_actuals").first().n > 0


@pytest.mark.xfail(strict=True, reason="gold_price_actuals fans out on product_price "
                   "history (no as-of); fixed by the SCD2 fix-the-views PR — remove "
                   "this marker then (standard §A.16).")
def test_grain_is_one_row_per_product_store_date(spark):
    _build(spark)
    # Correct grain: 2 sales days -> 2 rows. Today's fan-out yields 2x (one row per
    # list-price version) so this is xfail until the as-of fix lands.
    n = spark.sql("SELECT COUNT(*) AS n FROM gold_price_actuals").first().n
    assert n == 2, f"expected 1 row per product x store x date (2), got {n} (fan-out)"


@pytest.mark.xfail(strict=True, reason="base_price_lc must be the list price as-of the "
                   "sale date; the fan-out currently duplicates/among versions. Fixed by "
                   "the SCD2 fix-the-views PR — remove this marker then (standard §A.16).")
def test_base_price_resolved_as_of_sale_date(spark):
    _build(spark)
    prices = {str(r["date_key"]): float(r["base_price_lc"]) for r in
              spark.sql("SELECT date_key, base_price_lc FROM gold_price_actuals").collect()}
    # March sale -> $10 regime; July sale -> $12 regime.
    assert prices["2024-03-15"] == pytest.approx(10.0)
    assert prices["2024-07-15"] == pytest.approx(12.0)
