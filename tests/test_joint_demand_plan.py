"""Tests for Joint Demand Planning (gold_joint_demand_plan).

Static contract tests + a Spark fixture running the REAL view (Spark is the
Databricks engine; the SQL is executed verbatim, no dialect translation). The
key properties:
  - the SDI statistical baseline is ALLOCATED across suppliers by demand share, so
    a product shared by two suppliers does not fan the whole-product baseline onto
    every row (SUM stays equal to the product baseline);
  - latest-version ranking happens before the status filter, so a withdrawn latest
    vacates the scope rather than resurfacing a stale prior;
  - the view degrades gracefully BY DATA (rows returned, statistical_forecast_qty NULL)
    when the Smarter Demand view exists but is empty (the view must still exist to
    compile; a genuinely absent object fails at analysis time, like any view dependency);
  - a NULL min_disclosure_threshold means no low-volume floor.
"""

import os

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.ordm_config import resolve

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
VIEW = os.path.join(REPO, "outcome-packages", "data-sharing-with-suppliers", "gold", "gold_joint_demand_plan.sql")


# ---------- static ----------

def test_view_parses_and_exposes_columns():
    create = next(s for s in sqlglot.parse(resolve(open(VIEW).read(), "c"), read="databricks", error_level="ignore")
                  if isinstance(s, E.Create))
    outputs = set(create.expression.named_selects)
    required = {"principal_id", "supplier_id", "product_id", "fiscal_week_id",
                "retailer_qty", "supplier_qty", "consensus_qty",
                "retailer_value_net", "supplier_value_net", "consensus_value_net",
                "statistical_forecast_qty", "plan_variance_pct", "consensus_vs_baseline_pct"}
    assert required <= outputs, f"missing: {sorted(required - outputs)}"


# ---------- engine: Spark fixture running the real view ----------

_SUBS = [
    ("${catalog}.${dss_schema}.demand_plan_submission", "demand_plan_submission"),
    ("${catalog}.${dss_schema}.consensus_forecast_snapshot", "consensus_forecast_snapshot"),
    ("${catalog}.${dss_schema}.demand_collaboration", "demand_collaboration"),
    ("${catalog}.${sdi_schema}.gold_demand_forecast_weekly", "gold_demand_forecast_weekly"),
    ("${catalog}.${supplier_schema}.supplier", "supplier"),
    ("${catalog}.${product_schema}.product", "product"),
]


def _view_body():
    raw = open(VIEW).read()
    body = raw[raw.index(" AS", raw.index("CREATE OR REPLACE VIEW")) + 3:].strip().rstrip(";")
    for a, b in _SUBS:
        body = body.replace(a, b)
    return body


def _build(spark, populate_sdi=True, submission_rows=None, threshold=0):
    # Two suppliers share product P1 (week 202601); S1 also has a solo product P2.
    subs = submission_rows if submission_rows is not None else [
        # (id, cycle, party, supplier, product, week, qty, value, version, status, ts)
        ("s1", "PC1", "retailer", "S1", "P1", 202601, 100, 999.0, 1, "submitted", "2026-01-05 00:00:00"),
        ("s2", "PC1", "supplier", "S1", "P1", 202601, 120, 1200.0, 1, "submitted", "2026-01-05 00:00:00"),
        ("s3", "PC1", "retailer", "S2", "P1", 202601, 60,  600.0,  1, "submitted", "2026-01-05 00:00:00"),
        ("s4", "PC1", "supplier", "S2", "P1", 202601, 40,  400.0,  1, "submitted", "2026-01-05 00:00:00"),
        ("s5", "PC1", "retailer", "S1", "P2", 202601, 30,  300.0,  1, "submitted", "2026-01-05 00:00:00"),
        ("s6", "PC1", "supplier", "S1", "P2", 202601, 30,  300.0,  1, "submitted", "2026-01-05 00:00:00"),
    ]
    # attach a currency to every submission (schema requires it; the view reads it).
    subs = [row + ("USD",) for row in subs]
    spark.createDataFrame(
        subs,
        "demand_plan_submission_id string, plan_cycle_id string, party_role string, supplier_id string, "
        "product_id string, fiscal_week_id int, forecast_qty bigint, forecast_value_net double, "
        "submission_version int, submission_status string, submitted_ts string, currency_code string",
    ).createOrReplaceTempView("demand_plan_submission")

    # Consensus for the two S?/P1 rows (S1=110, S2=50) and S1/P2 (=30).
    cons = [
        ("c1", "PC1", "S1", "P1", 202601, "2026-01-08 00:00:00", 1, 110, 1100.0, 100, 120, 0.0, "USD", False),
        ("c2", "PC1", "S2", "P1", 202601, "2026-01-08 00:00:00", 1, 50,  500.0,  60,  40,  0.0, "USD", False),
        ("c3", "PC1", "S1", "P2", 202601, "2026-01-08 00:00:00", 1, 30,  300.0,  30,  30,  0.0, "USD", False),
    ]
    spark.createDataFrame(
        cons,
        "consensus_forecast_snapshot_id string, plan_cycle_id string, supplier_id string, product_id string, "
        "fiscal_week_id int, snapshot_ts string, plan_version int, consensus_qty bigint, consensus_value_net double, "
        "retailer_qty bigint, supplier_qty bigint, variance_pct double, currency_code string, threshold_suppressed_flag boolean",
    ).createOrReplaceTempView("consensus_forecast_snapshot")

    # Collaboration entitlements: one supplier-wide grant per supplier.
    collab = [
        ("dc1", "grpS1", "S1", None, threshold, True, "active"),
        ("dc2", "grpS2", "S2", None, threshold, True, "active"),
    ]
    spark.createDataFrame(
        collab,
        "demand_collaboration_id string, principal_id string, supplier_id string, product_id string, "
        "min_disclosure_threshold int, is_current boolean, collaboration_status string",
    ).createOrReplaceTempView("demand_collaboration")

    # SDI weekly baseline: whole-product P1 baseline = 300 (store_sku grain), P2 = 90.
    sdi = [
        ("P1", "ST1", 202601, 200.0, "store_sku", "short_term", "2026-01-01"),
        ("P1", "ST2", 202601, 100.0, "store_sku", "short_term", "2026-01-01"),
        ("P2", "ST1", 202601, 90.0,  "store_sku", "short_term", "2026-01-01"),
    ] if populate_sdi else []
    spark.createDataFrame(
        sdi,
        "product_id string, store_id string, fiscal_week_id int, forecast_quantity double, "
        "grain_type string, forecast_horizon_type string, forecast_origin_date_key string",
    ).createOrReplaceTempView("gold_demand_forecast_weekly")

    spark.createDataFrame(
        [("S1", "Supplier One", True), ("S2", "Supplier Two", True)],
        "supplier_id string, supplier_name string, is_current boolean",
    ).createOrReplaceTempView("supplier")
    spark.createDataFrame(
        [("P1", "Product One", True), ("P2", "Product Two", True)],
        "product_id string, product_name string, is_current boolean",
    ).createOrReplaceTempView("product")

    spark.sql("CREATE OR REPLACE TEMP VIEW gold_joint_demand_plan AS " + _view_body())


def test_baseline_allocated_across_suppliers_stays_additive(spark):
    # H1 fix: P1 is shared by S1 (consensus 110) and S2 (consensus 50). The product
    # baseline (300) must be split by demand share, NOT fanned whole onto both rows.
    _build(spark)
    rows = {r.supplier_id: r for r in spark.sql(
        "SELECT supplier_id, statistical_forecast_qty FROM gold_joint_demand_plan "
        "WHERE product_id='P1' AND fiscal_week_id=202601").collect()}
    s1 = float(rows["S1"].statistical_forecast_qty)
    s2 = float(rows["S2"].statistical_forecast_qty)
    # Shares: S1 = 110/160, S2 = 50/160 of the 300 product baseline.
    assert s1 == pytest.approx(300.0 * 110.0 / 160.0, abs=1e-6)
    assert s2 == pytest.approx(300.0 * 50.0 / 160.0, abs=1e-6)
    # Additivity: the per-supplier allocations sum back to the product baseline.
    assert (s1 + s2) == pytest.approx(300.0, abs=1e-6)


def test_solo_product_gets_full_baseline(spark):
    _build(spark)
    r = spark.sql("SELECT statistical_forecast_qty FROM gold_joint_demand_plan "
                  "WHERE supplier_id='S1' AND product_id='P2' AND fiscal_week_id=202601").first()
    assert float(r.statistical_forecast_qty) == pytest.approx(90.0, abs=1e-6)


def test_withdrawn_latest_vacates_scope(spark):
    # M1 fix: rank-before-filter. S1/P1 supplier submits v2 as 'withdrawn'; the latest
    # supplier submission is therefore withdrawn, so supplier_qty must be NULL (not the
    # stale v1=120).
    rows = [
        ("s1", "PC1", "retailer", "S1", "P1", 202601, 100, 999.0, 1, "submitted", "2026-01-05 00:00:00"),
        ("s2", "PC1", "supplier", "S1", "P1", 202601, 120, 1200.0, 1, "submitted", "2026-01-05 00:00:00"),
        ("s2b", "PC1", "supplier", "S1", "P1", 202601, 0, 0.0, 2, "withdrawn", "2026-01-06 00:00:00"),
    ]
    _build(spark, submission_rows=rows)
    r = spark.sql("SELECT retailer_qty, supplier_qty FROM gold_joint_demand_plan "
                  "WHERE supplier_id='S1' AND product_id='P1' AND fiscal_week_id=202601").first()
    assert int(r.retailer_qty) == 100
    assert r.supplier_qty is None, "a withdrawn latest must vacate the scope, not resurface v1"


def test_latest_cycle_wins_across_cycles(spark):
    # H1 (round 3): submission_version restarts per plan cycle, so ranking must key on
    # event time, not version. An older cycle's high version must NOT shadow a newer
    # cycle's fresh low-version plan for the same target week.
    rows = [
        # older cycle PC1: retailer S1×P1×W202605 at version 3, submitted earlier
        ("a", "PC1", "retailer", "S1", "P1", 202605, 300, 3000.0, 3, "submitted", "2026-01-05 00:00:00"),
        # newer cycle PC2: same week re-planned fresh at version 1, submitted later
        ("b", "PC2", "retailer", "S1", "P1", 202605, 111, 1110.0, 1, "submitted", "2026-02-05 00:00:00"),
        # a supplier plan so the row is well-formed
        ("c", "PC2", "supplier", "S1", "P1", 202605, 100, 1000.0, 1, "submitted", "2026-02-05 00:00:00"),
    ]
    _build(spark, submission_rows=rows)
    r = spark.sql("SELECT retailer_qty FROM gold_joint_demand_plan "
                  "WHERE supplier_id='S1' AND product_id='P1' AND fiscal_week_id=202605").first()
    assert int(r.retailer_qty) == 111, "the most recently submitted plan must win regardless of cycle version"


def test_latest_consensus_wins_across_cycles(spark):
    # H1 (round 4): consensus must rank by snapshot_ts (event time), not plan_version,
    # so a later cycle's re-published consensus wins even at a different version number.
    subs = [
        ("r", "PC2", "retailer", "S1", "P1", 202601, 100, 1000.0, 1, "submitted", "2026-02-05 00:00:00"),
        ("s", "PC2", "supplier", "S1", "P1", 202601, 100, 1000.0, 1, "submitted", "2026-02-05 00:00:00"),
    ]
    _build(spark, submission_rows=subs)
    # Override consensus: older cycle high version (later target but earlier snapshot) vs
    # newer cycle low version (later snapshot). The later snapshot must win.
    cons = [
        ("c_old", "PC1", "S1", "P1", 202601, "2026-01-08 00:00:00", 9, 500, 5000.0, 100, 100, 0.0, "USD", False),
        ("c_new", "PC2", "S1", "P1", 202601, "2026-02-08 00:00:00", 1, 130, 1300.0, 100, 100, 0.0, "USD", False),
    ]
    spark.createDataFrame(
        cons,
        "consensus_forecast_snapshot_id string, plan_cycle_id string, supplier_id string, product_id string, "
        "fiscal_week_id int, snapshot_ts string, plan_version int, consensus_qty bigint, consensus_value_net double, "
        "retailer_qty bigint, supplier_qty bigint, variance_pct double, currency_code string, threshold_suppressed_flag boolean",
    ).createOrReplaceTempView("consensus_forecast_snapshot")
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_joint_demand_plan AS " + _view_body())
    r = spark.sql("SELECT consensus_qty FROM gold_joint_demand_plan "
                  "WHERE supplier_id='S1' AND product_id='P1' AND fiscal_week_id=202601").first()
    assert int(r.consensus_qty) == 130, "the most recently snapshotted consensus must win regardless of plan_version"


def test_currency_labelled_without_consensus(spark):
    # m1 (round 3): a party-only row (no consensus) must still carry a currency_code.
    rows = [
        ("r1", "PC1", "retailer", "S1", "P9", 202601, 40, 400.0, 1, "submitted", "2026-01-05 00:00:00"),
        ("r2", "PC1", "supplier", "S1", "P9", 202601, 40, 400.0, 1, "submitted", "2026-01-05 00:00:00"),
    ]
    _build(spark, submission_rows=rows)
    r = spark.sql("SELECT currency_code, consensus_qty FROM gold_joint_demand_plan "
                  "WHERE supplier_id='S1' AND product_id='P9' AND fiscal_week_id=202601").first()
    assert r.consensus_qty is None, "fixture has no consensus for this scope"
    assert r.currency_code == "USD", "party-only rows must still carry a currency label"


def test_graceful_degradation_when_sdi_empty(spark):
    # Degrade BY DATA: the SDI view exists but is empty; every plan row is still
    # returned with the baseline (and its derived lift) NULL.
    _build(spark, populate_sdi=False)
    rows = spark.sql("SELECT statistical_forecast_qty, consensus_vs_baseline_pct FROM gold_joint_demand_plan").collect()
    assert len(rows) > 0, "rows must still be returned when the SDI baseline view is empty"
    assert all(r.statistical_forecast_qty is None for r in rows)
    assert all(r.consensus_vs_baseline_pct is None for r in rows)


def test_null_threshold_means_no_floor(spark):
    # A NULL min_disclosure_threshold discloses every entitled row regardless of volume.
    _build(spark, threshold=None)
    n = spark.sql("SELECT COUNT(*) AS n FROM gold_joint_demand_plan").first().n
    assert n == 3, f"expected all 3 entitled rows with a NULL floor, got {n}"
