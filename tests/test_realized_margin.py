"""Golden fixtures for gold_realized_margin (Realized Margin & Revenue Leakage).

This test runs the REAL gold_realized_margin SQL on controlled temp-view fixtures
and asserts:
1. Grain is unique per product_sk x store_sk x date_key (sale cohort).
2. Hand-computed expected values for POS-only, order with refund weights,
   authorized-only (unsettled), lifecycle dedup, chargeback, NULL-order adjustment,
   and conservation vs gold_payment_actuals.
3. Every row satisfies identity checks (booked_revenue = pos_net_sales + order_booked_sales, etc).
4. Lifetime conservation: SUM(refund_lc), SUM(chargeback_lc), SUM(adjustment_lc) match
   gold_payment_actuals lifetime sums within 0.1% tolerance.
"""
import datetime as dt
import os

import pytest

from tools.ordm_config import view_select_body

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GOLD_REALIZED_MARGIN = os.path.join(
    REPO, "outcome-packages", "balancing-margin-and-volume", "gold", "gold_realized_margin.sql"
)
GOLD_PAYMENT_ACTUALS = os.path.join(
    REPO, "outcome-packages", "balancing-margin-and-volume", "gold", "gold_payment_actuals.sql"
)

# Token substitutions: bare temp-view names (do NOT resolve() to expand ${catalog} first).
_REALIZED_MARGIN_SUBS = [
    ("${catalog}.${transaction_schema}.sales", "sales"),
    ("${catalog}.${product_schema}.product", "product"),
    ("${catalog}.${order_schema}.customer_order_line", "customer_order_line"),
    ("${catalog}.${payment_schema}.payment", "payment"),
]

_PAYMENT_ACTUALS_SUBS = [
    ("${catalog}.${order_schema}.customer_order_line", "customer_order_line"),
    ("${catalog}.${payment_schema}.payment", "payment"),
]


def _build_fixture(spark):
    """
    Fixture with multiple test scenarios:

    **Scenario 1: POS-only (same day, no orders)**
    - date_key=2024-01-01, product_sk=1, store_sk=1
    - 100 units, 1000.00 net sales, 600.00 COGS (unit_cost=6.0)
    Expected (hand-computed):
      pos_units=100, pos_net_sales_lc=1000.00, pos_cogs_lc=600.00
      order_* all 0 (no orders)
      booked_revenue=1000.00, realized_revenue=1000.00 (no reversals)
      leakage=0, cogs=600.00, booked_margin=400.00, realized_margin=400.00

    **Scenario 2: Two-line order with refund, allocated 0.75/0.25 by net_amount weight**
    - date_key=2024-01-02, product_sk=2, store_sk=1
    - order_id=ORD-1, created 2024-01-02
    - Line 1: net_amount=150.00, units=10, product_sk=2 (75% weight)
    - Line 2: net_amount=50.00, units=5, product_sk=3 (25% weight)
    - Order net total: 200.00
    - Payment 1 (sale, settled): 200.00 on 2024-01-02 -> allocated 150.00 to line 1, 50.00 to line 2
    - Payment 2 (refund, settled): 60.00 on 2024-01-04 -> allocated 45.00 to line 1, 15.00 to line 2
    Expected for product_sk=2 (Line 1):
      order_units=10, order_booked_sales_lc=150.00, order_settled_sales_lc=150.00 (payment_status='settled')
      order_refund_lc=45.00 (payment_status='settled', 75% of 60.00 refund)
      order_unsettled_sales_lc=0 (booked == settled)
      order_cogs_lc=70.00 (10 units * 7.0 unit_cost)
      realized_revenue=150.00 + 0 - 45.00 = 105.00
      leakage=45.00 (refund only)
      realized_margin=105.00 - 70.00 = 35.00

    **Scenario 3: Authorized-only order (unsettled)**
    - date_key=2024-01-05, product_sk=4, store_sk=1
    - order_id=ORD-2, created 2024-01-05
    - One line: net_amount=80.00, units=2, product_sk=4
    - Payment (sale, authorized): 80.00 -> settled_sale=0 (status not captured/settled)
    - Expected:
      order_booked_sales_lc=80.00 (net_amount)
      order_settled_sales_lc=0 (payment_status='authorized' excluded)
      order_unsettled_sales_lc=80.00 (booked - settled)
      realized_revenue=0 + 0 = 0 (no settled sales, no reversals)
      leakage=80.00 (all unsettled)

    **Scenario 4: Lifecycle dedup (duplicate rows same payment_id)**
    - date_key=2024-01-06, product_sk=5, store_sk=1
    - order_id=ORD-3, one line net_amount=100.00
    - Payment (sale, order_id=ORD-3) with two rows:
        - Row 1: event_timestamp=2024-01-06 10:00, status='authorized', payment_sk=100
        - Row 2: event_timestamp=2024-01-06 11:00, status='captured', payment_sk=101 (later)
      gold_payment_actuals dedup keeps Row 2 (latest timestamp) -> status='captured'
    - Expected: settled_sale=100.00 (captured), no double-count

    **Scenario 5: Declined attempt (ignored)**
    - Payment (sale, order_id=ORD-1) status='declined': 100.00 -> settled_sale=0 (declined not in allow-list)

    **Scenario 6: Chargeback**
    - date_key=2024-01-07, product_sk=6, store_sk=1
    - order_id=ORD-4, one line net_amount=120.00, units=1
    - Payment 1 (sale, settled): 120.00
    - Payment 2 (chargeback, settled): 120.00 (100% reversal)
    - Expected:
      order_booked_sales_lc=120.00, order_settled_sales_lc=120.00
      order_chargeback_lc=120.00
      realized_revenue=120.00 - 120.00 = 0
      leakage=120.00 (all chargeback)

    **Scenario 7: NULL-order adjustment (excluded)**
    - Payment (adjustment, order_id=NULL): 50.00 -> product_sk=NULL (no order line match)
      gold_realized_margin filters WHERE product_sk IS NOT NULL, so excluded.
    """
    d = dt.date
    ts = dt.datetime

    # === Scenario 1: POS-only ===
    spark.createDataFrame(
        [("S1", d(2024, 1, 1), 1, "SKU-1", 1, "STR-1", 100, 1000.00, "USD")],
        "sales_id string, date_key date, product_sk long, product_id string, "
        "store_sk long, store_id string, units int, net_revenue double, currency_code string"
    ).createOrReplaceTempView("sales")

    # === Product dimension (unit_cost) ===
    spark.createDataFrame(
        [
            (1, "SKU-1", 6.00),
            (2, "SKU-2", 7.00),
            (3, "SKU-3", 5.00),
            (4, "SKU-4", 8.00),
            (5, "SKU-5", 4.00),
            (6, "SKU-6", 10.00),
        ],
        "product_sk long, product_id string, unit_cost double"
    ).createOrReplaceTempView("product")

    # === Scenarios 2-7: Orders ===
    spark.createDataFrame(
        [
            # Scenario 2: Two-line order, 75%/25% weight
            ("OL-1", "ORD-1", 2, "SKU-2", 1, "STR-1", d(2024, 1, 2), 150.00, 10, "USD"),
            ("OL-2", "ORD-1", 3, "SKU-3", 1, "STR-1", d(2024, 1, 2), 50.00, 5, "USD"),
            # Scenario 3: Authorized-only
            ("OL-3", "ORD-2", 4, "SKU-4", 1, "STR-1", d(2024, 1, 5), 80.00, 2, "USD"),
            # Scenario 4: Lifecycle dedup
            ("OL-4", "ORD-3", 5, "SKU-5", 1, "STR-1", d(2024, 1, 6), 100.00, 3, "USD"),
            # Scenario 6: Chargeback
            ("OL-5", "ORD-4", 6, "SKU-6", 1, "STR-1", d(2024, 1, 7), 120.00, 1, "USD"),
        ],
        "order_line_id string, order_id string, product_sk long, product_id string, "
        "store_sk long, store_id string, order_date date, net_amount double, units int, currency_code string"
    ).createOrReplaceTempView("customer_order_line")

    # === Payments ===
    spark.createDataFrame(
        [
            # Scenario 2: Settled sale + refund
            (1, "PAY-1", "ORD-1", "sale", "settled", 200.00, "USD",
             d(2024, 1, 2), ts(2024, 1, 2, 10, 0)),
            (2, "PAY-2", "ORD-1", "refund", "settled", 60.00, "USD",
             d(2024, 1, 4), ts(2024, 1, 4, 14, 0)),
            # Scenario 3: Authorized-only (no settlement)
            (3, "PAY-3", "ORD-2", "sale", "authorized", 80.00, "USD",
             d(2024, 1, 5), ts(2024, 1, 5, 9, 0)),
            # Scenario 4: Lifecycle dedup (keep latest by timestamp)
            (4, "PAY-4", "ORD-3", "sale", "authorized", 100.00, "USD",
             d(2024, 1, 6), ts(2024, 1, 6, 10, 0)),
            (5, "PAY-4", "ORD-3", "sale", "captured", 100.00, "USD",
             d(2024, 1, 6), ts(2024, 1, 6, 11, 0)),  # Same payment_id, later timestamp
            # Scenario 5: Declined (ignored)
            (6, "PAY-5", "ORD-1", "sale", "declined", 100.00, "USD",
             d(2024, 1, 3), ts(2024, 1, 3, 8, 0)),
            # Scenario 6: Chargeback (settled)
            (7, "PAY-6", "ORD-4", "sale", "settled", 120.00, "USD",
             d(2024, 1, 7), ts(2024, 1, 7, 10, 0)),
            (8, "PAY-7", "ORD-4", "chargeback", "settled", 120.00, "USD",
             d(2024, 1, 8), ts(2024, 1, 8, 15, 0)),
            # Scenario 7: NULL-order adjustment (excluded by gold_realized_margin)
            (9, "PAY-8", None, "adjustment", "settled", 50.00, "USD",
             d(2024, 1, 9), ts(2024, 1, 9, 12, 0)),
            # Scenario 8: reversals in non-realized states never count. A voided refund on ORD-1
            # and a declined chargeback on ORD-4 must leave refund/chargeback totals unchanged.
            (10, "PAY-9", "ORD-1", "refund", "voided", 40.00, "USD",
             d(2024, 1, 5), ts(2024, 1, 5, 9, 0)),
            (11, "PAY-10", "ORD-4", "chargeback", "declined", 120.00, "USD",
             d(2024, 1, 9), ts(2024, 1, 9, 9, 0)),
        ],
        "payment_sk long, payment_id string, order_id string, payment_type string, payment_status string, "
        "amount double, currency_code string, event_date date, event_timestamp timestamp"
    ).createOrReplaceTempView("payment")


def _view_body(path, subs):
    """Load SQL and apply token substitutions."""
    body = view_select_body(open(path).read())
    for a, b in subs:
        body = body.replace(a, b)
    return body


@pytest.fixture(scope="function")
def realized_margin_view(spark):
    """Build fixture and create temp view for gold_realized_margin."""
    _build_fixture(spark)
    body = _view_body(GOLD_REALIZED_MARGIN, _REALIZED_MARGIN_SUBS)
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_realized_margin AS " + body)
    return spark.sql("SELECT * FROM gold_realized_margin")


@pytest.fixture(scope="function")
def payment_actuals_view(spark):
    """Build fixture and create temp view for gold_payment_actuals."""
    _build_fixture(spark)
    body = _view_body(GOLD_PAYMENT_ACTUALS, _PAYMENT_ACTUALS_SUBS)
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_payment_actuals AS " + body)
    return spark.sql("SELECT * FROM gold_payment_actuals")


def test_view_runs_and_returns_rows(realized_margin_view):
    """Green today: the real gold SQL parses and executes on the fixture."""
    assert len(realized_margin_view.collect()) > 0, "gold_realized_margin returned no rows"


def test_grain_is_unique_per_product_store_date(realized_margin_view):
    """Grain is product_sk x store_sk x date_key (sale cohort); no duplicates."""
    df = realized_margin_view
    dups = df.groupBy("product_sk", "store_sk", "date_key").count().filter("count > 1").collect()
    assert len(dups) == 0, f"Duplicate grain: {dups}"


def test_pos_only_scenario(realized_margin_view):
    """
    Scenario 1: POS-only row (no orders).
    Expected (hand-computed):
      product_sk=1, store_sk=1, date_key=2024-01-01
      pos_units=100, pos_net_sales_lc=1000.00, pos_cogs_lc=600.00 (100*6.0)
      order_* all 0
      booked_revenue=1000.00, realized_revenue=1000.00, leakage=0
      cogs=600.00, booked_margin=400.00, realized_margin=400.00
    """
    df = realized_margin_view
    row = df.filter("product_sk=1 AND store_sk=1 AND date_key='2024-01-01'").collect()
    assert len(row) == 1, f"Expected 1 row for POS-only scenario, got {len(row)}"
    r = row[0]

    assert float(r.pos_units) == pytest.approx(100.0), "pos_units"
    assert float(r.pos_net_sales_lc) == pytest.approx(1000.00), "pos_net_sales_lc"
    assert float(r.pos_cogs_lc) == pytest.approx(600.00), "pos_cogs_lc"

    assert float(r.order_units) == pytest.approx(0.0), "order_units should be 0"
    assert float(r.order_booked_sales_lc) == pytest.approx(0.0), "order_booked_sales_lc"
    assert float(r.order_settled_sales_lc) == pytest.approx(0.0), "order_settled_sales_lc"
    assert float(r.order_unsettled_sales_lc) == pytest.approx(0.0), "order_unsettled_sales_lc"
    assert float(r.order_refund_lc) == pytest.approx(0.0), "order_refund_lc"
    assert float(r.order_chargeback_lc) == pytest.approx(0.0), "order_chargeback_lc"
    assert float(r.order_adjustment_lc) == pytest.approx(0.0), "order_adjustment_lc"

    assert float(r.booked_revenue_lc) == pytest.approx(1000.00), "booked_revenue"
    assert float(r.realized_revenue_lc) == pytest.approx(1000.00), "realized_revenue"
    assert float(r.leakage_lc) == pytest.approx(0.0), "leakage"
    assert float(r.cogs_lc) == pytest.approx(600.00), "cogs"
    assert float(r.booked_margin_lc) == pytest.approx(400.00), "booked_margin"
    assert float(r.realized_margin_lc) == pytest.approx(400.00), "realized_margin"


def test_two_line_order_with_refund_allocation(realized_margin_view):
    """
    Scenario 2: Two-line order, refund allocated 75%/25% by weight.
    Expected for product_sk=2 (Line 1, 75% weight):
      order_units=10, order_booked_sales_lc=150.00
      order_settled_sales_lc=150.00 (payment_status='settled')
      order_refund_lc=45.00 (75% of 60.00 refund)
      order_unsettled_sales_lc=0
      order_cogs_lc=70.00 (10 units * 7.0)
      realized_revenue=150.00 - 45.00 = 105.00
      leakage=45.00
      realized_margin=105.00 - 70.00 = 35.00
    """
    df = realized_margin_view
    row = df.filter("product_sk=2 AND store_sk=1 AND date_key='2024-01-02'").collect()
    assert len(row) == 1, f"Expected 1 row for product_sk=2, got {len(row)}"
    r = row[0]

    assert float(r.order_units) == pytest.approx(10.0), "order_units"
    assert float(r.order_booked_sales_lc) == pytest.approx(150.00), "order_booked_sales_lc"
    assert float(r.order_settled_sales_lc) == pytest.approx(150.00), "order_settled_sales_lc"
    assert float(r.order_refund_lc) == pytest.approx(45.00, abs=0.01), "order_refund_lc (75% of 60)"
    assert float(r.order_unsettled_sales_lc) == pytest.approx(0.0), "order_unsettled_sales_lc"
    assert float(r.order_cogs_lc) == pytest.approx(70.00), "order_cogs_lc (10 * 7.0)"

    assert float(r.booked_revenue_lc) == pytest.approx(150.00), "booked_revenue"
    assert float(r.realized_revenue_lc) == pytest.approx(105.00, abs=0.01), "realized_revenue"
    assert float(r.leakage_lc) == pytest.approx(45.00, abs=0.01), "leakage"
    assert float(r.realized_margin_lc) == pytest.approx(35.00, abs=0.01), "realized_margin"


def test_authorized_only_unsettled_order(realized_margin_view):
    """
    Scenario 3: Authorized-only order (unsettled).
    Expected for product_sk=4:
      order_booked_sales_lc=80.00 (net_amount)
      order_settled_sales_lc=0 (payment_status='authorized' excluded)
      order_unsettled_sales_lc=80.00 (booked - settled)
      realized_revenue=0 (no settled sales)
      leakage=80.00 (all unsettled)
    """
    df = realized_margin_view
    row = df.filter("product_sk=4 AND store_sk=1 AND date_key='2024-01-05'").collect()
    assert len(row) == 1, f"Expected 1 row for product_sk=4, got {len(row)}"
    r = row[0]

    assert float(r.order_booked_sales_lc) == pytest.approx(80.00), "order_booked_sales_lc"
    assert float(r.order_settled_sales_lc) == pytest.approx(0.0), "order_settled_sales_lc (authorized excluded)"
    assert float(r.order_unsettled_sales_lc) == pytest.approx(80.00), "order_unsettled_sales_lc"
    assert float(r.realized_revenue_lc) == pytest.approx(0.0), "realized_revenue"
    assert float(r.leakage_lc) == pytest.approx(80.00), "leakage (all unsettled)"


def test_lifecycle_dedup_keeps_latest(realized_margin_view):
    """
    Scenario 4: Lifecycle dedup (PAY-4 appears twice, keep latest status='captured').
    Expected for product_sk=5:
      order_settled_sales_lc=100.00 (payment_status='captured', not double-counted)
      no duplicate rows
    """
    df = realized_margin_view
    row = df.filter("product_sk=5 AND store_sk=1 AND date_key='2024-01-06'").collect()
    assert len(row) == 1, f"Expected 1 row for product_sk=5, got {len(row)}"
    r = row[0]

    assert float(r.order_settled_sales_lc) == pytest.approx(100.00), "settled_sales (latest status='captured')"
    assert float(r.order_booked_sales_lc) == pytest.approx(100.00), "booked_sales"


def test_chargeback_realized(realized_margin_view):
    """
    Scenario 6: Chargeback (settled).
    Expected for product_sk=6:
      order_settled_sales_lc=120.00
      order_chargeback_lc=120.00
      realized_revenue=120.00 - 120.00 = 0
      leakage=120.00 (full chargeback reversal)
    """
    df = realized_margin_view
    row = df.filter("product_sk=6 AND store_sk=1 AND date_key='2024-01-07'").collect()
    assert len(row) == 1, f"Expected 1 row for product_sk=6, got {len(row)}"
    r = row[0]

    assert float(r.order_settled_sales_lc) == pytest.approx(120.00), "order_settled_sales_lc"
    assert float(r.order_chargeback_lc) == pytest.approx(120.00, abs=0.01), "order_chargeback_lc"
    assert float(r.realized_revenue_lc) == pytest.approx(0.0, abs=0.01), "realized_revenue (full reversal)"
    assert float(r.leakage_lc) == pytest.approx(120.00, abs=0.01), "leakage"


def test_null_order_adjustment_excluded(realized_margin_view):
    """
    Scenario 7: NULL-order adjustment should NOT appear in gold_realized_margin
    (grain is product_sk x store_sk x date_key, and NULL-order events have product_sk=NULL).
    """
    df = realized_margin_view
    null_rows = df.filter("product_sk IS NULL").collect()
    assert len(null_rows) == 0, f"gold_realized_margin should not have NULL product_sk rows, got {len(null_rows)}"


def test_every_row_satisfies_identities(realized_margin_view):
    """
    Every row must satisfy these identities within 0.02 tolerance:
    - booked_revenue = pos_net_sales + order_booked_sales
    - realized_revenue = pos_net_sales + order_settled_sales - order_refund - order_chargeback - order_adjustment
    - leakage = booked_revenue - realized_revenue
    - cogs = pos_cogs + order_cogs
    - booked_margin = booked_revenue - cogs
    - realized_margin = realized_revenue - cogs
    """
    df = realized_margin_view
    for r in df.collect():
        br = float(r.booked_revenue_lc)
        rr = float(r.realized_revenue_lc)
        lk = float(r.leakage_lc)
        cgs = float(r.cogs_lc)
        bm = float(r.booked_margin_lc)
        rm = float(r.realized_margin_lc)

        pos_ns = float(r.pos_net_sales_lc or 0)
        ord_bs = float(r.order_booked_sales_lc or 0)
        ord_ss = float(r.order_settled_sales_lc or 0)
        ord_rf = float(r.order_refund_lc or 0)
        ord_cb = float(r.order_chargeback_lc or 0)
        ord_aj = float(r.order_adjustment_lc or 0)
        pos_cg = float(r.pos_cogs_lc or 0)
        ord_cg = float(r.order_cogs_lc or 0)

        # booked_revenue = pos_net_sales + order_booked_sales
        assert abs(br - (pos_ns + ord_bs)) < 0.02, \
            f"booked_revenue identity failed: {br} != {pos_ns} + {ord_bs}"

        # realized_revenue = pos_net_sales + order_settled_sales - refund - chargeback - adjustment
        expected_rr = pos_ns + ord_ss - ord_rf - ord_cb - ord_aj
        assert abs(rr - expected_rr) < 0.02, \
            f"realized_revenue identity failed: {rr} != {expected_rr}"

        # leakage = booked_revenue - realized_revenue
        assert abs(lk - (br - rr)) < 0.02, \
            f"leakage identity failed: {lk} != {br} - {rr}"

        # cogs = pos_cogs + order_cogs
        assert abs(cgs - (pos_cg + ord_cg)) < 0.02, \
            f"cogs identity failed: {cgs} != {pos_cg} + {ord_cg}"

        # booked_margin = booked_revenue - cogs
        assert abs(bm - (br - cgs)) < 0.02, \
            f"booked_margin identity failed: {bm} != {br} - {cgs}"

        # realized_margin = realized_revenue - cogs
        assert abs(rm - (rr - cgs)) < 0.02, \
            f"realized_margin identity failed: {rm} != {rr} - {cgs}"


def test_non_negative_magnitudes(realized_margin_view):
    """
    Per spec section 4: order_refund/chargeback/adjustment/cogs and order_booked are non-negative.
    (Units can be signed per spec, but magnitudes are absolute values.)
    Note: pos_cogs_lc and pos_net_sales_lc can be negative on days with returns (negative units),
    so they are not checked here (see bmv_realized_margin_nonneg_booked_and_cogs WARN check).
    """
    df = realized_margin_view
    for r in df.collect():
        assert float(r.order_refund_lc or 0) >= -0.01, "order_refund_lc should be non-negative"
        assert float(r.order_chargeback_lc or 0) >= -0.01, "order_chargeback_lc should be non-negative"
        assert float(r.order_adjustment_lc or 0) >= -0.01, "order_adjustment_lc should be non-negative"
        assert float(r.order_cogs_lc or 0) >= -0.01, "order_cogs_lc should be non-negative"
        assert float(r.order_booked_sales_lc or 0) >= -0.01, "order_booked_sales_lc should be non-negative"


def test_refund_attributed_to_order_date_not_event_date(realized_margin_view):
    """
    Per spec: "every payment reversal on an order is attributed back to that order's lines and
    order_date (not to the refund/chargeback event date)".

    Scenario: ORD-1 created on 2024-01-02, refund event on 2024-01-04.
    Expected: refund amount appears on 2024-01-02 (order_date), not 2024-01-04 (event_date).
    """
    df = realized_margin_view

    # Verify refund for ORD-1 appears on order_date=2024-01-02
    order_date_row = df.filter("product_sk=2 AND store_sk=1 AND date_key='2024-01-02'").collect()
    assert len(order_date_row) == 1, "Expected 1 row for product_sk=2 on order_date"
    assert float(order_date_row[0].order_refund_lc or 0) > 0, "Refund should appear on order_date"

    # Verify there's no separate row on the refund event date (2024-01-04)
    # (If refund were on event date, we'd see a new row for 2024-01-04)
    event_date_rows = df.filter("date_key='2024-01-04'").collect()
    # 2024-01-04 has no POS or order transactions in the fixture, so no rows expected
    assert len(event_date_rows) == 0, f"No rows expected on 2024-01-04 (refund event date), got {len(event_date_rows)}"


def test_conservation_vs_gold_payment_actuals(spark):
    """
    Per spec section 4: lifetime SUM(order_refund_lc), SUM(order_chargeback_lc),
    SUM(order_adjustment_lc) in gold_realized_margin equal gold_payment_actuals lifetime sums
    within max(1.00, 0.1%) tolerance. Both use identical allocation predicates and exclude the
    same unallocatable events (NULL order_id, orders with no lines, zero-net orders).

    This test runs BOTH views and compares lifetimes.
    """
    _build_fixture(spark)

    # Build gold_payment_actuals
    body_pa = _view_body(GOLD_PAYMENT_ACTUALS, _PAYMENT_ACTUALS_SUBS)
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_payment_actuals AS " + body_pa)

    # Build gold_realized_margin
    body_rm = _view_body(GOLD_REALIZED_MARGIN, _REALIZED_MARGIN_SUBS)
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_realized_margin AS " + body_rm)

    # Lifetime sums from gold_payment_actuals (event-date grain)
    pa = spark.sql("""
        SELECT
          SUM(refund_amount_lc) AS total_refund,
          SUM(chargeback_amount_lc) AS total_chargeback,
          SUM(adjustment_amount_lc) AS total_adjustment
        FROM gold_payment_actuals
    """).collect()[0]

    # Lifetime sums from gold_realized_margin (sale-cohort grain, but same economic events)
    rm = spark.sql("""
        SELECT
          SUM(order_refund_lc) AS total_refund,
          SUM(order_chargeback_lc) AS total_chargeback,
          SUM(order_adjustment_lc) AS total_adjustment
        FROM gold_realized_margin
    """).collect()[0]

    pa_refund = float(pa.total_refund or 0)
    pa_chargeback = float(pa.total_chargeback or 0)
    pa_adjustment = float(pa.total_adjustment or 0)

    rm_refund = float(rm.total_refund or 0)
    rm_chargeback = float(rm.total_chargeback or 0)
    rm_adjustment = float(rm.total_adjustment or 0)

    # Tolerance: max(1.00, 0.1% of gold_payment_actuals total)
    def tolerance(pa_amt):
        return max(1.00, abs(pa_amt) * 0.001)

    assert abs(rm_refund - pa_refund) <= tolerance(pa_refund), \
        f"refund conservation failed: gold_realized_margin={rm_refund}, gold_payment_actuals={pa_refund}"
    assert abs(rm_chargeback - pa_chargeback) <= tolerance(pa_chargeback), \
        f"chargeback conservation failed: gold_realized_margin={rm_chargeback}, gold_payment_actuals={pa_chargeback}"
    assert abs(rm_adjustment - pa_adjustment) <= tolerance(pa_adjustment), \
        f"adjustment conservation failed: gold_realized_margin={rm_adjustment}, gold_payment_actuals={pa_adjustment}"
