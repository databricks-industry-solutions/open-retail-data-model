"""Tests for Data Monetization (gold_data_product_revenue, gold_data_monetization_exceptions).

Static contract tests + a Spark fixture running the REAL views (Spark is the Databricks
engine; the SQL is executed verbatim, no dialect translation). The key properties:
  - the advertiser's retail-media spend is ALLOCATED across the licence rows that share
    that advertiser, so a principal holding both an all-supplier and a supplier-scoped
    licence does not fan the whole advertiser spend onto every row (SUM stays equal to the
    advertiser's actual spend);
  - overlapping grants do not double-bill: usage matching both an all-supplier and a
    supplier-scoped licence is attributed once, to the more specific one;
  - latest-version ranking happens before the status filter, so a cancelled latest
    vacates the scope rather than resurfacing the stale active terms it replaced;
  - contracted_units is pro-rated from the BILLING period to one fiscal period, so a
    quarterly/annual commitment is not compared against a month of usage;
  - a paid-but-unused licence still produces a row (that is the churn signal), which is why
    zero-consumption rows are exempt from the disclosure floor;
  - the views degrade gracefully BY DATA (rows returned, media columns NULL) when the
    Commerce Media Networks view exists but is empty (the view must still exist to compile;
    a genuinely absent object fails at analysis time, like any view dependency);
  - a NULL min_disclosure_threshold means no low-volume floor.
"""

import os

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.ordm_config import resolve

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PKG = os.path.join(REPO, "outcome-packages", "data-sharing-with-suppliers")
REVENUE = os.path.join(PKG, "gold", "gold_data_product_revenue.sql")
EXCEPTIONS = os.path.join(PKG, "gold", "gold_data_monetization_exceptions.sql")


# ---------- static ----------

def _outputs(path):
    create = next(s for s in sqlglot.parse(resolve(open(path).read(), "c"), read="databricks",
                                           error_level="ignore")
                  if isinstance(s, E.Create))
    return set(create.expression.named_selects)


def test_revenue_view_parses_and_exposes_columns():
    required = {"principal_id", "data_product_id", "supplier_scope_id", "advertiser_id",
                "fiscal_year", "fiscal_period", "subscription_status",
                "contracted_price_amount", "list_price_amount", "contracted_units",
                "consumption_units", "data_revenue_amount", "currency_code",
                "contract_discount_pct", "contract_utilisation_pct",
                "revenue_per_consumption_unit", "media_spend_net",
                "total_monetised_value", "data_revenue_share_pct", "usage_suppressed_flag"}
    outputs = _outputs(REVENUE)
    assert required <= outputs, f"missing: {sorted(required - outputs)}"


def test_exceptions_view_parses_and_exposes_columns():
    required = {"principal_id", "data_product_id", "supplier_scope_id", "fiscal_year",
                "fiscal_period", "exception_reason", "revenue_at_risk", "priority_rank",
                "contract_utilisation_pct", "currency_code"}
    outputs = _outputs(EXCEPTIONS)
    assert required <= outputs, f"missing: {sorted(required - outputs)}"


# ---------- engine: Spark fixture running the real views ----------

_SUBS = [
    ("${catalog}.${dss_schema}.data_product_subscription", "data_product_subscription"),
    ("${catalog}.${dss_schema}.data_share_consumption", "data_share_consumption"),
    ("${catalog}.${dss_schema}.data_product", "data_product"),
    ("${catalog}.${dss_schema}.gold_data_product_revenue", "gold_data_product_revenue"),
    ("${catalog}.${cmn_schema}.gold_campaign_performance", "gold_campaign_performance"),
    ("${catalog}.${calendar_schema}.fiscal_calendar", "fiscal_calendar"),
    ("${catalog}.${supplier_schema}.supplier", "supplier"),
]

_SUB_SCHEMA = (
    "data_product_subscription_id string, principal_id string, principal_type string, "
    "data_product_id string, supplier_id string, advertiser_id string, "
    "contracted_price_amount double, contracted_units bigint, billing_frequency string, "
    "currency_code string, term_start_date string, term_end_date string, "
    "min_disclosure_threshold int, subscription_status string, subscribed_ts string, "
    "effective_from_date string, effective_to_date string, is_current boolean"
)
_SUB_CAST = [
    "data_product_subscription_id", "principal_id", "principal_type", "data_product_id",
    "supplier_id", "advertiser_id", "contracted_price_amount", "contracted_units",
    "billing_frequency", "currency_code",
    "CAST(term_start_date AS DATE) AS term_start_date",
    "CAST(term_end_date AS DATE) AS term_end_date",
    "min_disclosure_threshold", "subscription_status", "subscribed_ts",
    "CAST(effective_from_date AS DATE) AS effective_from_date",
    "CAST(effective_to_date AS DATE) AS effective_to_date", "is_current",
]

_CONS_SCHEMA = (
    "data_share_consumption_id string, data_product_subscription_id string, "
    "principal_id string, data_product_id string, supplier_id string, usage_date string, "
    "fiscal_year int, fiscal_period int, access_channel string, consumption_units bigint, "
    "billed_query_count bigint, billable_amount double, currency_code string, "
    "threshold_suppressed_flag boolean"
)
_CONS_CAST = [
    "data_share_consumption_id", "data_product_subscription_id", "principal_id",
    "data_product_id", "supplier_id", "CAST(usage_date AS DATE) AS usage_date",
    "fiscal_year", "fiscal_period", "access_channel", "consumption_units",
    "billed_query_count", "billable_amount", "currency_code", "threshold_suppressed_flag",
]


def _view_body(path, marker="CREATE OR REPLACE VIEW"):
    raw = open(path).read()
    body = raw[raw.index(" AS", raw.index(marker)) + 3:].strip().rstrip(";")
    for a, b in _SUBS:
        body = body.replace(a, b)
    return body


# A licence version: keep the field order aligned with _SUB_SCHEMA.
def _sub(sub_id, principal, product, supplier, advertiser, price, units, freq, status,
         subscribed_ts, term_start="2026-01-01", term_end=None, threshold=0,
         eff_from="2026-01-01", eff_to=None, is_current=True):
    return (sub_id, principal, "group", product, supplier, advertiser, price, units, freq,
            "USD", term_start, term_end, threshold, status, subscribed_ts, eff_from,
            eff_to, is_current)


def _cons(cons_id, sub_id, principal, product, supplier, usage_date, period, units, amount,
          suppressed=False):
    return (cons_id, sub_id, principal, product, supplier, usage_date, 2026, period, "api",
            units, units, amount, "USD", suppressed)


def _build(spark, subs=None, cons=None, populate_media=True, products=None,
           product_has_threshold=False):
    """Fixture: FY2026 periods 1-2, one advertiser (ADV1), suppliers S1/S2.

    Default shape: principal P1 holds BOTH an all-supplier licence and an S1-scoped
    licence on DP1 (the overlap), and consumption exists for S1 (150u) and S2 (60u).
    """
    cal = [(f"2026-01-{d:02d}", 2026, 1) for d in range(1, 29)] + \
          [(f"2026-02-{d:02d}", 2026, 2) for d in range(1, 29)]
    spark.createDataFrame(cal, "date_key string, fiscal_year int, fiscal_period int") \
        .selectExpr("CAST(date_key AS DATE) AS date_key", "fiscal_year", "fiscal_period") \
        .createOrReplaceTempView("fiscal_calendar")

    dp_schema = ("data_product_id string, data_product_name string, data_product_category string, "
                 "pricing_model string, consumption_unit string, list_price_amount double, "
                 "currency_code string, is_current boolean")
    dp_rows = products if products is not None else [
        ("DP1", "Media Report", "media_measurement", "per_consumption_unit", "query", 10.00, "USD", True)]
    if product_has_threshold:
        dp_schema += ", min_disclosure_threshold int"
    else:
        # The view reads the catalog's default floor, so the column must exist even when a
        # test does not exercise it.
        dp_rows = [row + (None,) for row in dp_rows]
        dp_schema += ", min_disclosure_threshold int"
    spark.createDataFrame(dp_rows, dp_schema).createOrReplaceTempView("data_product")

    if subs is None:
        subs = [
            _sub("all1", "P1", "DP1", None, "ADV1", 3000.0, 600, "monthly", "active", "2026-01-01 00:00:00"),
            _sub("sup1", "P1", "DP1", "S1", "ADV1", 1800.0, 200, "monthly", "active", "2026-01-01 00:00:00"),
        ]
    spark.createDataFrame(subs, _SUB_SCHEMA).selectExpr(*_SUB_CAST) \
        .createOrReplaceTempView("data_product_subscription")

    if cons is None:
        cons = [
            _cons("c1", "sup1", "P1", "DP1", "S1", "2026-01-10", 1, 150, 1500.0),
            _cons("c2", "all1", "P1", "DP1", "S2", "2026-01-11", 1, 60, 600.0),
        ]
    spark.createDataFrame(cons, _CONS_SCHEMA).selectExpr(*_CONS_CAST) \
        .createOrReplaceTempView("data_share_consumption")

    media = [("ADV1", "2026-01-05", 4000.0), ("ADV1", "2026-01-20", 1000.0)] if populate_media else []
    spark.createDataFrame(media, "advertiser_id string, metric_date string, media_spend_net double") \
        .selectExpr("advertiser_id", "CAST(metric_date AS DATE) AS metric_date", "media_spend_net") \
        .createOrReplaceTempView("gold_campaign_performance")

    spark.createDataFrame([("S1", "Supplier One", True), ("S2", "Supplier Two", True)],
                          "supplier_id string, supplier_name string, is_current boolean") \
        .createOrReplaceTempView("supplier")

    spark.sql("CREATE OR REPLACE TEMP VIEW gold_data_product_revenue AS " + _view_body(REVENUE))
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_data_monetization_exceptions AS " + _view_body(EXCEPTIONS))


def test_media_spend_allocated_across_licences_stays_additive(spark):
    # P1 holds an all-supplier AND an S1-scoped licence on the same advertiser, so a naive
    # join would fan ADV1's whole 5000 spend onto BOTH rows (SUM = 10000). The allocation
    # must split it by revenue share so the per-row values sum back to the actual spend.
    _build(spark)
    rows = spark.sql("""SELECT supplier_scope_id, media_spend_net
                        FROM gold_data_product_revenue
                        WHERE fiscal_period = 1 AND media_spend_net IS NOT NULL""").collect()
    total = sum(float(r.media_spend_net) for r in rows)
    assert total == pytest.approx(5000.0, abs=1e-6), \
        "per-row media allocations must sum to the advertiser's actual period spend"
    # Shares: S1-scoped earned 1500 of 2100, all-supplier earned 600 of 2100.
    by_scope = {r.supplier_scope_id: float(r.media_spend_net) for r in rows}
    assert by_scope["S1"] == pytest.approx(5000.0 * 1500.0 / 2100.0, abs=1e-6)
    assert by_scope[None] == pytest.approx(5000.0 * 600.0 / 2100.0, abs=1e-6)


def test_single_licence_advertiser_gets_full_spend(spark):
    _build(spark, subs=[_sub("sup1", "P1", "DP1", "S1", "ADV1", 1800.0, 200, "monthly",
                             "active", "2026-01-01 00:00:00")],
           cons=[_cons("c1", "sup1", "P1", "DP1", "S1", "2026-01-10", 1, 150, 1500.0)])
    r = spark.sql("""SELECT media_spend_net FROM gold_data_product_revenue
                     WHERE fiscal_period = 1 AND supplier_scope_id = 'S1'""").first()
    assert float(r.media_spend_net) == pytest.approx(5000.0, abs=1e-6)


def test_overlapping_grants_do_not_double_bill(spark):
    # S1's 150 units match BOTH the all-supplier and the S1-scoped licence. They must be
    # attributed ONCE (to the more specific licence), so total revenue is 1500 + 600.
    _build(spark)
    r = spark.sql("""SELECT SUM(data_revenue_amount) AS rev, SUM(consumption_units) AS units
                     FROM gold_data_product_revenue""").first()
    assert float(r.rev) == pytest.approx(2100.0, abs=1e-6)
    assert int(r.units) == 210


def test_cancelled_latest_vacates_scope(spark):
    # Rank-before-filter: the latest licence version is 'cancelled', so the scope must
    # vacate rather than resurfacing the prior 'active' version's terms.
    subs = [
        _sub("s1", "P2", "DP1", "S1", None, 900.0, 100, "monthly", "active",
             "2026-01-01 00:00:00", eff_from="2026-01-01", eff_to="2026-01-15", is_current=False),
        _sub("s1b", "P2", "DP1", "S1", None, 0.0, 0, "monthly", "cancelled",
             "2026-01-15 00:00:00", eff_from="2026-01-15"),
    ]
    _build(spark, subs=subs, cons=[])
    n = spark.sql("SELECT COUNT(*) AS n FROM gold_data_product_revenue WHERE principal_id='P2'").first().n
    assert n == 0, "a cancelled latest must vacate the scope, not resurface the prior active terms"


def test_latest_licence_version_wins_by_event_time(spark):
    # A re-price opens a new version at the same effective date; the later subscribed_ts
    # must win, so the CURRENT contracted price is served (not the superseded one).
    subs = [
        _sub("v1", "P1", "DP1", "S1", "ADV1", 1800.0, 200, "monthly", "active",
             "2026-01-01 00:00:00", eff_from="2026-01-01", eff_to="2026-01-01", is_current=False),
        _sub("v2", "P1", "DP1", "S1", "ADV1", 2400.0, 200, "monthly", "active",
             "2026-01-02 00:00:00", eff_from="2026-01-01"),
    ]
    _build(spark, subs=subs, cons=[_cons("c1", "v2", "P1", "DP1", "S1", "2026-01-10", 1, 150, 1500.0)])
    r = spark.sql("""SELECT contracted_price_amount FROM gold_data_product_revenue
                     WHERE fiscal_period = 1 AND supplier_scope_id = 'S1'""").first()
    assert float(r.contracted_price_amount) == pytest.approx(2400.0, abs=1e-6), \
        "the most recently agreed licence version must win"


@pytest.mark.parametrize("freq,divisor", [("monthly", 1.0), ("quarterly", 3.0), ("annual", 12.0)])
def test_contracted_units_prorated_to_fiscal_period(spark, freq, divisor):
    # contracted_units is stated per BILLING period; a fiscal period is a retail month, so
    # a quarterly/annual commitment must be divided before comparison. Without this an
    # annual allowance measured against one month understates utilisation 12-fold.
    subs = [_sub("s1", "P1", "DP1", "S1", None, 1200.0, 1200, freq, "active", "2026-01-01 00:00:00")]
    _build(spark, subs=subs,
           cons=[_cons("c1", "s1", "P1", "DP1", "S1", "2026-01-10", 1, 100, 1000.0)])
    r = spark.sql("""SELECT contract_utilisation_pct FROM gold_data_product_revenue
                     WHERE fiscal_period = 1 AND supplier_scope_id = 'S1'""").first()
    assert float(r.contract_utilisation_pct) == pytest.approx(100.0 / (1200.0 / divisor), abs=1e-4)


def test_unrecognised_billing_frequency_nulls_utilisation(spark):
    # An unrecognised frequency must yield NULL rather than a wrong denominator.
    subs = [_sub("s1", "P1", "DP1", "S1", None, 1200.0, 1200, "fortnightly", "active",
                 "2026-01-01 00:00:00")]
    _build(spark, subs=subs,
           cons=[_cons("c1", "s1", "P1", "DP1", "S1", "2026-01-10", 1, 100, 1000.0)])
    r = spark.sql("""SELECT contract_utilisation_pct FROM gold_data_product_revenue
                     WHERE fiscal_period = 1 AND supplier_scope_id = 'S1'""").first()
    assert r.contract_utilisation_pct is None


def test_paid_unused_licence_still_produces_a_row(spark):
    # The churn signal: a licence covering the period with NO usage must still appear (and
    # must not be filtered out by the disclosure floor), or the paid-but-unused exception
    # could never be raised.
    subs = [_sub("s1", "P1", "DP1", "S1", None, 2200.0, 100, "monthly", "active",
                 "2026-01-01 00:00:00", threshold=50)]
    _build(spark, subs=subs, cons=[])
    rows = spark.sql("""SELECT fiscal_period, consumption_units, data_revenue_amount
                        FROM gold_data_product_revenue WHERE supplier_scope_id = 'S1'""").collect()
    assert len(rows) == 2, "an in-term licence must yield a row per covered fiscal period"
    assert all(r.consumption_units is None for r in rows)
    exc = spark.sql("""SELECT exception_reason, revenue_at_risk
                       FROM gold_data_monetization_exceptions WHERE fiscal_period = 1""").first()
    assert exc.exception_reason == "paid_unused_subscription"
    assert float(exc.revenue_at_risk) == pytest.approx(2200.0, abs=1e-6), \
        "an unused licence risks the CONTRACTED price, not zero"


def test_disclosure_floor_suppresses_measures_not_the_row(spark):
    # Usage below the floor is WITHHELD (measures NULL, flag set) but the licence row must
    # survive: a silently missing period is indistinguishable from a licence that was never
    # sold, and dropping it would under-report the P&L.
    subs = [_sub("s1", "P1", "DP1", "S1", None, 900.0, 100, "monthly", "active",
                 "2026-01-01 00:00:00", threshold=100)]
    _build(spark, subs=subs,
           cons=[_cons("c1", "s1", "P1", "DP1", "S1", "2026-01-10", 1, 20, 200.0)])
    r = spark.sql("""SELECT consumption_units, data_revenue_amount, contract_utilisation_pct,
                            revenue_per_consumption_unit, usage_suppressed_flag
                     FROM gold_data_product_revenue
                     WHERE fiscal_period = 1 AND supplier_scope_id = 'S1'""").first()
    assert r is not None, "the licence row must survive suppression, not be dropped"
    assert r.usage_suppressed_flag is True
    assert r.consumption_units is None, "below-floor volume must be withheld"
    assert r.data_revenue_amount is None
    # Derived metrics must not leak the withheld volume back out.
    assert r.contract_utilisation_pct is None
    assert r.revenue_per_consumption_unit is None


def test_product_default_threshold_applies_when_the_grant_states_none(spark):
    """data_product.min_disclosure_threshold is documented as the default the GRANT
    overrides, so both levels must reach the suppression decision. Reading only the grant
    would make the catalog default dead metadata."""
    products = [("DP1", "Media Report", "media_measurement", "per_consumption_unit",
                 "query", 10.00, "USD", True, 100)]
    subs = [_sub("s1", "P1", "DP1", "S1", None, 900.0, 500, "monthly", "active",
                 "2026-01-01 00:00:00", threshold=None)]  # grant sets NO floor
    _build(spark, subs=subs,
           cons=[_cons("c1", "s1", "P1", "DP1", "S1", "2026-01-10", 1, 20, 200.0)],
           products=products, populate_media=False, product_has_threshold=True)
    r = spark.sql("""SELECT consumption_units, usage_suppressed_flag
                     FROM gold_data_product_revenue
                     WHERE fiscal_period = 1 AND supplier_scope_id = 'S1'""").first()
    assert r.usage_suppressed_flag is True, \
        "the product's catalog default floor (100) must apply when the grant states none"
    assert r.consumption_units is None


def test_grant_threshold_overrides_the_product_default(spark):
    # The grant is the more specific level, so its floor wins — here a LOWER grant floor
    # discloses usage the product default would have withheld.
    products = [("DP1", "Media Report", "media_measurement", "per_consumption_unit",
                 "query", 10.00, "USD", True, 100)]
    subs = [_sub("s1", "P1", "DP1", "S1", None, 900.0, 500, "monthly", "active",
                 "2026-01-01 00:00:00", threshold=5)]
    _build(spark, subs=subs,
           cons=[_cons("c1", "s1", "P1", "DP1", "S1", "2026-01-10", 1, 20, 200.0)],
           products=products, populate_media=False, product_has_threshold=True)
    r = spark.sql("""SELECT consumption_units, usage_suppressed_flag
                     FROM gold_data_product_revenue
                     WHERE fiscal_period = 1 AND supplier_scope_id = 'S1'""").first()
    assert r.usage_suppressed_flag is False, "the grant's floor (5) must override the default (100)"
    assert int(r.consumption_units) == 20


def test_suppressed_row_is_not_reported_as_paid_unused(spark):
    # A suppressed row's measures are NULL because they were withheld, not because nothing
    # happened — it must NOT raise a false churn alarm on a licence that was being used.
    subs = [_sub("s1", "P1", "DP1", "S1", None, 900.0, 100, "monthly", "active",
                 "2026-01-01 00:00:00", threshold=100)]
    _build(spark, subs=subs,
           cons=[_cons("c1", "s1", "P1", "DP1", "S1", "2026-01-10", 1, 20, 200.0)],
           populate_media=False)
    reasons = [r.exception_reason for r in spark.sql(
        """SELECT exception_reason FROM gold_data_monetization_exceptions
           WHERE fiscal_period = 1 AND supplier_scope_id = 'S1'""").collect()]
    assert reasons == [], f"a suppressed row must raise no exception, got {reasons}"


def test_null_threshold_means_no_floor(spark):
    # ...and a NULL threshold discloses every entitled row regardless of volume.
    subs = [_sub("s1", "P1", "DP1", "S1", None, 900.0, 100, "monthly", "active",
                 "2026-01-01 00:00:00", threshold=None)]
    _build(spark, subs=subs,
           cons=[_cons("c1", "s1", "P1", "DP1", "S1", "2026-01-10", 1, 3, 30.0)])
    r = spark.sql("""SELECT consumption_units FROM gold_data_product_revenue
                     WHERE fiscal_period = 1 AND supplier_scope_id = 'S1'""").first()
    assert int(r.consumption_units) == 3, "a NULL floor must disclose every entitled row"


def test_suppressed_usage_excluded_from_totals(spark):
    # A threshold_suppressed_flag row must never contribute to a disclosed total.
    subs = [_sub("s1", "P1", "DP1", "S1", None, 900.0, 100, "monthly", "active",
                 "2026-01-01 00:00:00")]
    _build(spark, subs=subs, cons=[
        _cons("c1", "s1", "P1", "DP1", "S1", "2026-01-10", 1, 100, 1000.0),
        _cons("c2", "s1", "P1", "DP1", "S1", "2026-01-11", 1, 5, 50.0, suppressed=True),
    ])
    r = spark.sql("""SELECT consumption_units, data_revenue_amount FROM gold_data_product_revenue
                     WHERE fiscal_period = 1 AND supplier_scope_id = 'S1'""").first()
    assert int(r.consumption_units) == 100
    assert float(r.data_revenue_amount) == pytest.approx(1000.0, abs=1e-6)


def test_graceful_degradation_when_media_empty(spark):
    # Degrade BY DATA: the CMN view exists but is empty; every revenue row is still
    # returned with the media signal (and its derived columns) NULL.
    _build(spark, populate_media=False)
    rows = spark.sql("""SELECT data_revenue_amount, media_spend_net, total_monetised_value,
                               data_revenue_share_pct FROM gold_data_product_revenue""").collect()
    assert len(rows) > 0, "rows must still be returned when the media view is empty"
    assert all(r.media_spend_net is None for r in rows)
    assert all(r.total_monetised_value is None for r in rows)
    assert all(r.data_revenue_share_pct is None for r in rows)
    assert any(r.data_revenue_amount is not None for r in rows), \
        "the data revenue itself must survive the missing media signal"


def test_exception_taxonomy_and_priority_rank(spark):
    # Each reason fires on its own shape, and the queue ranks by revenue at risk within a
    # principal. All four licences sit under ONE principal so priority_rank is comparable.
    products = [
        ("DP1", "Media Report", "media_measurement", "per_consumption_unit", "query", 10.00, "USD", True),
    ]
    subs = [
        # over-run: 100/mo allowance, 150 used -> 1.5 > 1.20
        _sub("over", "P1", "DP1", "S1", None, 900.0, 100, "monthly", "active", "2026-01-01 00:00:00"),
        # under-consumed: 10000/mo allowance, 150 used -> 0.015 < 0.10
        _sub("under", "P1", "DP1", "S2", None, 900.0, 10000, "monthly", "active", "2026-01-01 00:00:00"),
        # rate-card divergence: per-unit list 10.00 but billed 20.00/unit -> +100%
        _sub("rate", "P1", "DP1", "S3", None, 900.0, 200, "monthly", "active", "2026-01-01 00:00:00"),
        # lapsing term: ends 2026-02-20, i.e. within 90 days of P1's end (2026-01-28)
        _sub("lapse", "P1", "DP1", "S4", None, 900.0, 200, "monthly", "active",
             "2026-01-01 00:00:00", term_end="2026-02-20"),
    ]
    cons = [
        _cons("k1", "over", "P1", "DP1", "S1", "2026-01-10", 1, 150, 1500.0),
        _cons("k2", "under", "P1", "DP1", "S2", "2026-01-10", 1, 150, 1500.0),
        _cons("k3", "rate", "P1", "DP1", "S3", "2026-01-10", 1, 150, 3000.0),
        _cons("k4", "lapse", "P1", "DP1", "S4", "2026-01-10", 1, 180, 1800.0),
    ]
    _build(spark, subs=subs, cons=cons, products=products, populate_media=False)
    got = {r.supplier_scope_id: r.exception_reason for r in spark.sql(
        """SELECT supplier_scope_id, exception_reason FROM gold_data_monetization_exceptions
           WHERE fiscal_period = 1""").collect()}
    assert got["S1"] == "over_contracted_consumption"
    assert got["S2"] == "under_consumed_subscription"
    assert got["S3"] == "rate_card_divergence"
    assert got["S4"] == "lapsing_term"

    ranked = spark.sql("""SELECT supplier_scope_id, revenue_at_risk, priority_rank
                          FROM gold_data_monetization_exceptions
                          WHERE fiscal_period = 1 ORDER BY priority_rank""").collect()
    assert [r.priority_rank for r in ranked] == list(range(1, len(ranked) + 1)), \
        "priority_rank must be dense and 1-based within a principal"
    risks = [float(r.revenue_at_risk) for r in ranked]
    assert risks == sorted(risks, reverse=True), "the queue must rank by revenue at risk, descending"
    assert ranked[0].supplier_scope_id == "S3", "the highest-revenue exception must rank first"


_MV_TOTAL_EXPR = "COALESCE(SUM(data_revenue_amount), 0) + COALESCE(SUM(media_spend_net), 0)"


def test_metric_view_total_survives_either_component_being_absent(spark):
    """total_monetised_value must COALESCE BOTH terms, symmetrically.

    Either component can legitimately be NULL over a whole group, and a bare addition NULLs
    the headline KPI in both directions (verified: Spark gives NULL for 300.0 + NULL):
      - media absent — only advertiser-scoped licences carry media, so every other data
        product, and any deployment where Commerce Media Networks is unpopulated, has none;
      - revenue absent — a paid-but-unused advertiser-scoped licence has media, no revenue.
    Coalescing only one side leaves the measure asymmetric. This deliberately DIFFERS from
    the row-level view, which NULL-propagates; both files carry a note saying so.
    """
    raw = open(os.path.join(PKG, "metric-views", "data_product_revenue.sql")).read()
    assert _MV_TOTAL_EXPR in raw, \
        "total_monetised_value must COALESCE both terms so one absent component != absent total"

    # (a) media absent, revenue present
    _build(spark, populate_media=False)
    r = spark.sql(f"""SELECT SUM(data_revenue_amount) AS rev, SUM(media_spend_net) AS media,
                             SUM(data_revenue_amount) + SUM(media_spend_net) AS bare,
                             {_MV_TOTAL_EXPR} AS measure
                      FROM gold_data_product_revenue""").first()
    assert r.media is None and float(r.rev) > 0
    assert r.bare is None, "the bare addition NULLs a real total — the defect being guarded"
    assert float(r.measure) == pytest.approx(float(r.rev), abs=1e-6)

    # (b) revenue absent, media present — an unused advertiser-scoped licence
    _build(spark, subs=[_sub("s1", "P1", "DP1", "S1", "ADV1", 1800.0, 200, "monthly",
                             "active", "2026-01-01 00:00:00")], cons=[])
    r = spark.sql(f"""SELECT SUM(data_revenue_amount) AS rev, SUM(media_spend_net) AS media,
                             SUM(data_revenue_amount) + SUM(media_spend_net) AS bare,
                             {_MV_TOTAL_EXPR} AS measure
                      FROM gold_data_product_revenue""").first()
    assert r.rev is None and float(r.media) > 0, "fixture: media with no billed revenue"
    assert r.bare is None
    assert float(r.measure) == pytest.approx(float(r.media), abs=1e-6)


def test_row_level_total_still_null_propagates():
    """The gold view keeps 'known total or nothing' per row — the divergence from the metric
    view is intentional, and both files must say so, or it reads as drift."""
    gold = open(REVENUE).read()
    assert "COALESCE(SUM(" not in gold, "the row-level total must NOT adopt the aggregate semantics"
    assert "mv_data_product_revenue" in gold, \
        "the gold view must cross-reference the metric view's differing definition"
    mv = open(os.path.join(PKG, "metric-views", "data_product_revenue.sql")).read()
    assert "gold_data_product_revenue.total_monetised_value" in mv, \
        "the metric view must cross-reference the row-level definition"


def test_metric_view_source_withholds_media_of_suppressed_rows():
    """The metric view's total_monetised_value is SUM(revenue) + SUM(media), so its source
    must expose ONE consistent row population. The gold view deliberately keeps a suppressed
    row's media allocation (it has to stay additive to the advertiser's actual spend) while
    NULLing that row's revenue — so the metric view must withhold that media itself, or the
    aggregate adds media with no matching revenue and understates data's share.
    """
    raw = open(os.path.join(PKG, "metric-views", "data_product_revenue.sql")).read()
    src = raw[raw.index("source:"):raw.index("fields:")]
    assert "usage_suppressed_flag" in src, \
        "the metric-view source must select usage_suppressed_flag to gate the media measure"
    assert "CASE WHEN usage_suppressed_flag THEN NULL ELSE media_spend_net END" in src, \
        ("the metric-view source must withhold media_spend_net for suppressed rows so it "
         "stays consistent with the withheld revenue measures")


def test_generator_usage_dates_reconcile_with_the_seeded_calendar():
    """The generator's literal usage dates carry DEGENERATE fiscal_year/fiscal_period keys,
    so nothing structural stops them drifting from the calendar. Two ways they can be wrong,
    both silent:
      - a date past the seeded calendar's last day has no calendar row, so the revenue
        view's fiscal-period spine never contains it and the usage vanishes;
      - a date whose labelled period disagrees with the NRF 4-5-4 derivation fails the
        dsc_fiscal_period_matches_usage_date check only once real data is generated.
    Recompute the calendar from seeds.yaml and assert both here, cheaply and without Spark.
    """
    import ast
    import datetime
    import re as _re

    import yaml

    seeds = yaml.safe_load(open(os.path.join(REPO, "runtime", "synthetic-data", "seeds.yaml")))

    def _find(node, key):
        if isinstance(node, dict):
            if key in node:
                return node[key]
            for v in node.values():
                got = _find(v, key)
                if got is not None:
                    return got
        return None

    start = datetime.date.fromisoformat(str(_find(seeds, "calendar_start_date")))
    weeks = int(_find(seeds, "calendar_weeks"))
    base_year = start.year

    # Replicates the 4-5-4 derivation in runtime/synthetic-data/generators/trade_promotion.py.
    calendar = {}
    for off in range(weeks * 7):
        d = start + datetime.timedelta(days=off)
        w = off // 7
        fw = w % 52 + 1
        quarter = (fw - 1) // 13 + 1
        wq = (fw - 1) % 13
        period_in_q = 1 if wq < 4 else (2 if wq < 9 else 3)
        calendar[d] = (base_year + w // 52, (quarter - 1) * 3 + period_in_q)

    gen = open(os.path.join(REPO, "runtime", "synthetic-data", "generators",
                            "data_sharing_with_suppliers.py")).read()
    m = _re.search(r"usage_days = (\[.*?\])", gen, _re.S)
    assert m, "could not locate usage_days in the generator"
    usage_days = ast.literal_eval(m.group(1))
    assert usage_days, "usage_days must not be empty"

    for date_str, fy, fp in usage_days:
        d = datetime.date.fromisoformat(date_str)
        assert d in calendar, (
            f"{date_str} is outside the seeded fiscal_calendar "
            f"({start} .. {max(calendar)}); its usage would silently vanish from the "
            f"revenue view's fiscal-period spine")
        assert calendar[d] == (fy, fp), (
            f"{date_str} is labelled FY{fy} P{fp} but the seeded 4-5-4 calendar derives "
            f"FY{calendar[d][0]} P{calendar[d][1]} — dsc_fiscal_period_matches_usage_date "
            f"would fail on generated data")


def test_clean_licence_raises_no_exception(spark):
    # A licence used well within its allowance, at the rate card, with an open term must
    # NOT appear in the queue — otherwise the queue is noise rather than signal.
    subs = [_sub("ok", "P1", "DP1", "S1", None, 900.0, 200, "monthly", "active", "2026-01-01 00:00:00")]
    cons = [_cons("k1", "ok", "P1", "DP1", "S1", "2026-01-10", 1, 100, 1000.0)]
    _build(spark, subs=subs, cons=cons, populate_media=False)
    n = spark.sql("""SELECT COUNT(*) AS n FROM gold_data_monetization_exceptions
                     WHERE fiscal_period = 1""").first().n
    assert n == 0, "a healthy licence must not be flagged"
