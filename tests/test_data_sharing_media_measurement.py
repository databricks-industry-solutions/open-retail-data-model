"""Static consistency tests for the Data Sharing with Suppliers package: the DDL/generator
column contracts, PK contracts, no-PII guarantees on the entitled gold views, and the
presence of each use case's data-quality checks. Covers the media-measurement pieces
(reporting_entitlement, supplier_media_report_snapshot, gold_supplier_media_report), the
Joint Demand Planning tables, and the Data Monetization tables."""

import ast
import os
import re

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.ordm_config import resolve

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PKG = os.path.join(REPO, "outcome-packages", "data-sharing-with-suppliers")
GENERATOR = os.path.join(REPO, "runtime", "synthetic-data", "generators", "data_sharing_with_suppliers.py")
CHECKS = os.path.join(PKG, "checks.sql")
GOLD = os.path.join(PKG, "gold", "gold_supplier_media_report.sql")

GOLD_JDP = os.path.join(PKG, "gold", "gold_joint_demand_plan.sql")
GOLD_DPR = os.path.join(PKG, "gold", "gold_data_product_revenue.sql")
GOLD_DME = os.path.join(PKG, "gold", "gold_data_monetization_exceptions.sql")

TABLES = [
    "reporting_entitlement", "supplier_media_report_snapshot",
    # Joint Demand Planning (CPFR)
    "demand_collaboration", "demand_plan_submission", "consensus_forecast_snapshot",
    # Data Monetization
    "data_product", "data_product_subscription", "data_share_consumption",
]
COLUMNS_CONST = {
    "reporting_entitlement": "REPORTING_ENTITLEMENT_COLUMNS",
    "supplier_media_report_snapshot": "SNAPSHOT_COLUMNS",
    "demand_collaboration": "DEMAND_COLLABORATION_COLUMNS",
    "demand_plan_submission": "DEMAND_PLAN_SUBMISSION_COLUMNS",
    "consensus_forecast_snapshot": "CONSENSUS_SNAPSHOT_COLUMNS",
    "data_product": "DATA_PRODUCT_COLUMNS",
    "data_product_subscription": "DATA_PRODUCT_SUBSCRIPTION_COLUMNS",
    "data_share_consumption": "DATA_SHARE_CONSUMPTION_COLUMNS",
}
_PK_RE = re.compile(r"CONSTRAINT\s+pk_[a-z_]+\s+PRIMARY\s+KEY\s*\(\s*([a-z_]+)\s*\)", re.I)
PII = {"customer_key_hash", "household_key_hash", "assignment_unit_key_hash"}


def _text(table):
    return resolve(open(os.path.join(PKG, "tables", f"{table}.sql")).read(), "c")


def _create(table):
    stmts = sqlglot.parse(_text(table), read="databricks", error_level="ignore")
    create = next((s for s in stmts if isinstance(s, E.Create)), None)
    # Fail with the CAUSE, not a bare StopIteration. The usual culprit is an escaped
    # apostrophe ('') inside a column COMMENT: sqlglot falls back to parsing the whole
    # CREATE as an opaque Command, so every column-level assertion silently loses its
    # input. Reword the comment to avoid the apostrophe instead.
    assert create is not None, (
        f"{table}: the CREATE did not parse as a Create statement (sqlglot fell back to a "
        f"Command). A common cause is an escaped apostrophe ('') in a COMMENT string.")
    return create


def _generator_constants():
    mod = ast.parse(open(GENERATOR).read())
    out = {}
    for n in mod.body:
        if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name) \
                and isinstance(n.value, ast.List) and all(isinstance(e, ast.Constant) for e in n.value.elts):
            out[n.targets[0].id] = [e.value for e in n.value.elts]
    return out


@pytest.mark.parametrize("table", TABLES)
def test_ddl_pk_contract(table):
    create = _create(table)
    assert create is not None
    m = _PK_RE.search(open(os.path.join(PKG, "tables", f"{table}.sql")).read())
    assert m and m.group(1).endswith("_sk")
    cols = {c.name for c in create.find_all(E.ColumnDef)}
    stem = m.group(1)[:-3]
    assert f"{stem}_id" in cols


@pytest.mark.parametrize("table", TABLES)
def test_generator_columns_match_ddl(table):
    create = _create(table)
    pk = _PK_RE.search(open(os.path.join(PKG, "tables", f"{table}.sql")).read()).group(1)
    ddl = {c.name for c in create.find_all(E.ColumnDef) if c.name != pk}
    gen = set(_generator_constants()[COLUMNS_CONST[table]])
    assert gen == ddl, f"{table} drift — missing={sorted(ddl - gen)} extra={sorted(gen - ddl)}"


def test_gold_no_raw_pii():
    stmt = sqlglot.parse_one(resolve(open(GOLD).read(), "c"), read="databricks", error_level="ignore")
    outs = set((stmt.expression if isinstance(stmt, E.Create) else stmt).named_selects)
    assert not (PII & outs), f"gold_supplier_media_report exposes PII: {sorted(PII & outs)}"
    assert "principal_id" in outs, "entitled report must carry principal_id for row filtering"


def test_media_measurement_checks_present():
    text = open(CHECKS).read()
    for name in ("re_advertiser_fk_orphan", "smrs_single_currency", "smr_gold_no_raw_pii"):
        assert name in text, f"missing check {name}"


def test_joint_demand_gold_no_raw_pii():
    stmt = sqlglot.parse_one(resolve(open(GOLD_JDP).read(), "c"), read="databricks", error_level="ignore")
    outs = set((stmt.expression if isinstance(stmt, E.Create) else stmt).named_selects)
    assert not (PII & outs), f"gold_joint_demand_plan exposes PII: {sorted(PII & outs)}"
    assert "principal_id" in outs, "entitled joint plan must carry principal_id for row filtering"


def test_joint_demand_checks_present():
    text = open(CHECKS).read()
    for name in ("dc_supplier_fk_orphan", "dc_scd2_current_open", "dc_scope_unique_current",
                 "dps_single_currency", "dps_submitted_ts_not_null", "cfs_single_currency",
                 "jdp_cross_table_single_currency", "jdp_gold_no_raw_pii"):
        assert name in text, f"missing check {name}"


@pytest.mark.parametrize("gold", [GOLD_DPR, GOLD_DME])
def test_data_monetization_gold_no_raw_pii(gold):
    stmt = sqlglot.parse_one(resolve(open(gold).read(), "c"), read="databricks", error_level="ignore")
    outs = set((stmt.expression if isinstance(stmt, E.Create) else stmt).named_selects)
    name = os.path.basename(gold)
    assert not (PII & outs), f"{name} exposes PII: {sorted(PII & outs)}"
    assert "principal_id" in outs, f"{name} must carry principal_id for row filtering"


def test_data_monetization_checks_present():
    text = open(CHECKS).read()
    for name in ("dp_scd2_current_open", "dp_single_currency", "dp_usage_priced_products_have_unit",
                 "dpsub_scd2_current_open", "dpsub_scope_unique_current",
                 "dpsub_subscribed_ts_not_null", "dpsub_billing_frequency_recognised",
                 "dpsub_term_start_not_null", "dpsub_term_dates_ordered",
                 "dpsub_data_product_fk_orphan", "dpsub_advertiser_fk_orphan",
                 "dsc_subscription_fk_orphan", "dsc_usage_date_in_calendar",
                 "dsc_fiscal_period_matches_usage_date",
                 "dsc_measures_non_negative", "dsc_single_currency",
                 "dm_cross_table_single_currency", "dpr_media_allocation_reconciles",
                 "dpr_suppressed_measures_are_withheld",
                 "dpr_gold_no_raw_pii", "dme_gold_no_raw_pii"):
        assert name in text, f"missing check {name}"


def test_data_monetization_enums_are_subset_of_declared_checks():
    """Every enum value the GENERATOR can emit must be allowed by the CHECK constraint
    declared in relationships.sql. A generator emitting an unlisted value would deploy
    fine locally and then fail the Delta constraint on a real write."""
    rel = open(os.path.join(PKG, "relationships.sql")).read()
    consts = _generator_constants()
    # generator constant -> the constraint whose IN (...) list must contain it
    pairs = [
        ("DATA_PRODUCT_CATEGORIES", "chk_dp_category"),
        ("DELIVERY_MODES", "chk_dp_delivery_mode"),
        ("PRICING_MODELS", "chk_dp_pricing_model"),
        ("CONSUMPTION_UNITS", "chk_dp_consumption_unit"),
        ("DATA_PRODUCT_STATUS", "chk_dp_status"),
        ("BILLING_FREQUENCIES", "chk_dpsub_billing_frequency"),
        ("SUBSCRIPTION_STATUS", "chk_dpsub_status"),
    ]
    for const, constraint in pairs:
        m = re.search(rf"CONSTRAINT\s+{constraint}\s+CHECK\s*\((.+?)\);", rel, re.I | re.S)
        assert m, f"no CHECK named {constraint} in relationships.sql"
        allowed = set(re.findall(r"'([^']+)'", m.group(1)))
        declared = set(consts[const])
        assert declared <= allowed, \
            f"{const} has values not allowed by {constraint}: {sorted(declared - allowed)}"


# ---- gold_supplier_media_report executed on Spark (entitlement precedence) ----
# The workspace's synthetic entitlements are all brand-wide, so these fixtures are the
# only place the "most-specific entitlement wins" rule is exercised.

_MEDIA_SUBS = [
    ("${catalog}.${cmn_schema}.campaign_day", "campaign_day"),
    ("${catalog}.${dss_schema}.reporting_entitlement", "reporting_entitlement"),
    ("${catalog}.${cmn_schema}.advertiser", "advertiser"),
    ("${catalog}.${cmn_schema}.campaign", "campaign"),
]


def _media_view_body():
    raw = open(GOLD).read()
    body = raw[raw.index(" AS", raw.index("CREATE OR REPLACE VIEW")) + 3:].strip().rstrip(";")
    for a, b in _MEDIA_SUBS:
        body = body.replace(a, b)
    assert "${" not in body, "unmapped placeholder in gold_supplier_media_report"
    return body


def _build_media(spark, entitlements):
    # ADV1 runs two campaigns: C1 with 40 conversions, C2 with 30.
    spark.createDataFrame(
        [("ADV1", "C1", 1000, 800, 50, 40, 45, 100.0, 400.0, 50.0, 80.0, False),
         ("ADV1", "C2", 500, 400, 20, 30, 32, 50.0, 200.0, 20.0, 30.0, False)],
        "advertiser_id string, campaign_id string, impressions bigint, viewable_impressions bigint, "
        "clicks bigint, conversions bigint, units bigint, media_spend_net double, "
        "attributed_net_sales double, new_to_brand_sales double, incremental_sales double, "
        "privacy_suppressed_flag boolean").createOrReplaceTempView("campaign_day")
    spark.createDataFrame(
        entitlements,
        "principal_id string, advertiser_id string, campaign_id string, "
        "min_disclosure_threshold int, is_current boolean, entitlement_status string"
    ).createOrReplaceTempView("reporting_entitlement")
    spark.createDataFrame([("ADV1", "Brand One", True)],
                          "advertiser_id string, brand_name string, is_current boolean") \
        .createOrReplaceTempView("advertiser")
    spark.createDataFrame([("C1", "Campaign One", True), ("C2", "Campaign Two", True)],
                          "campaign_id string, campaign_name string, is_current boolean") \
        .createOrReplaceTempView("campaign")
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_supplier_media_report AS " + _media_view_body())


def test_media_report_most_specific_entitlement_wins(spark):
    _build_media(spark, [
        ("P1", "ADV1", None, 0, True, "active"),   # brand-wide ...
        ("P1", "ADV1", "C1", 0, True, "active"),   # ... plus a campaign-scoped grant on C1
        ("P2", "ADV1", None, 0, True, "active"),   # brand-wide only
        ("P3", "ADV1", "C2", 0, True, "active"),   # campaign-scoped only
        ("P4", "ADV1", None, 0, True, "revoked"),  # not active: sees nothing
    ])
    rows = spark.sql("SELECT principal_id, campaign_id FROM gold_supplier_media_report").collect()
    keys = [(r.principal_id, r.campaign_id) for r in rows]
    assert sorted(keys) == [("P1", "C1"), ("P1", "C2"), ("P2", "C1"), ("P2", "C2"), ("P3", "C2")]
    assert len(keys) == len(set(keys)), "P1/C1 must be emitted once, not once per grant"


def test_media_report_disclosure_threshold_suppresses_below_floor(spark):
    # Floor of 35 conversions: C1 (40) is disclosed, C2 (30) is suppressed.
    _build_media(spark, [("P1", "ADV1", None, 35, True, "active")])
    got = {r.campaign_id for r in spark.sql("SELECT campaign_id FROM gold_supplier_media_report").collect()}
    assert got == {"C1"}


def test_media_report_campaign_grant_threshold_replaces_brand_wide(spark):
    # P1 holds a brand-wide grant (floor 0) and a campaign-scoped grant on C1 (floor 50). On C1 the
    # campaign-scoped grant wins, so its floor applies: C1's 40 conversions are suppressed for P1,
    # and the brand-wide grant does not leak it back. C2 still comes through the brand-wide grant.
    _build_media(spark, [
        ("P1", "ADV1", None, 0, True, "active"),
        ("P1", "ADV1", "C1", 50, True, "active"),
    ])
    got = sorted((r.principal_id, r.campaign_id)
                 for r in spark.sql("SELECT principal_id, campaign_id FROM gold_supplier_media_report").collect())
    assert got == [("P1", "C2")]


def test_media_report_inactive_campaign_grant_does_not_hide_brand_wide(spark):
    # A revoked or non-current campaign-scoped grant must not suppress the brand-wide match: the
    # anti-join reads the filtered ent CTE, not the raw entitlement table.
    _build_media(spark, [
        ("P1", "ADV1", None, 0, True, "active"),
        ("P1", "ADV1", "C1", 0, True, "revoked"),
        ("P2", "ADV1", None, 0, True, "active"),
        ("P2", "ADV1", "C2", 0, False, "active"),
    ])
    got = sorted((r.principal_id, r.campaign_id)
                 for r in spark.sql("SELECT principal_id, campaign_id FROM gold_supplier_media_report").collect())
    assert got == [("P1", "C1"), ("P1", "C2"), ("P2", "C1"), ("P2", "C2")]
