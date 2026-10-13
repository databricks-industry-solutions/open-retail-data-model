"""Static consistency tests for the Commerce Media Networks outcome package.

Validate — without a Spark cluster — that the fact DDL, the data-quality checks,
and the gold views stay mutually consistent and within the ORDM guardrails.
(Synthetic data for the fact layer is a documented NICE follow-up; the package
reaches the MUST tier via sample-queries.)
"""

import ast
import glob
import os
import re

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.ordm_config import resolve

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PKG = os.path.join(REPO, "outcome-packages", "commerce-media-networks")
TABLES_DIR = os.path.join(PKG, "tables")
GOLD_DIR = os.path.join(PKG, "gold")
CHECKS = os.path.join(PKG, "checks.sql")
GENERATOR = os.path.join(REPO, "runtime", "synthetic-data", "generators", "commerce_media_networks.py")

TABLE_FILES = sorted(glob.glob(os.path.join(TABLES_DIR, "*.sql")))
GOLD_FILES = sorted(glob.glob(os.path.join(GOLD_DIR, "*.sql")))
STORE_ZONE_COMPAT = os.path.join(GOLD_DIR, "store_zone_interval.sql")

_PK_RE = re.compile(r"CONSTRAINT\s+pk_[a-z_]+\s+PRIMARY\s+KEY\s*\(\s*([a-z_]+)\s*\)", re.I)
PII_COLUMNS = {"customer_key_hash", "household_key_hash", "assignment_unit_key_hash"}

# table -> generator column-contract constant
COLUMNS_CONST = {
    "media_event": "MEDIA_EVENT_COLUMNS",
    "conversion_event": "CONVERSION_EVENT_COLUMNS",
    "attributed_outcome": "ATTRIBUTED_OUTCOME_COLUMNS",
    "experiment_assignment_bridge": "EXPERIMENT_ASSIGNMENT_COLUMNS",
    "campaign_day": "AGG_CAMPAIGN_DAY_COLUMNS",
    "incrementality_result": "INCREMENTALITY_RESULT_COLUMNS",
    "experiment_daily": "EXPERIMENT_DAILY_COLUMNS",
    "budget_allocation": "BUDGET_ALLOCATION_COLUMNS",
    "pacing_snapshot": "PACING_SNAPSHOT_COLUMNS",
    # store_zone_interval relocated to connected-store-signals (ADR 0033).
    "product_store_day": "PRODUCT_STORE_DAY_COLUMNS",
    # Relocated retail-media dimensions now co-located in this gold package.
    "advertiser": "ADVERTISER_COLUMNS",
    "campaign": "CAMPAIGN_COLUMNS",
    "ad_group": "AD_GROUP_COLUMNS",
    "creative": "CREATIVE_COLUMNS",
    "placement": "PLACEMENT_COLUMNS",
    "experiment": "EXPERIMENT_COLUMNS",
    "experiment_cell": "EXPERIMENT_CELL_COLUMNS",
    "delivery_channel": "DELIVERY_CHANNEL_COLUMNS",
    "keyword": "KEYWORD_COLUMNS",
    # audience promoted to shared silver marketing (ADR 0022); no longer a CMN table.
}


def _generator_constants():
    mod = ast.parse(open(GENERATOR).read())
    out = {}
    for node in mod.body:
        if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name) \
                and isinstance(node.value, ast.List) and all(isinstance(e, ast.Constant) for e in node.value.elts):
            out[node.targets[0].id] = [e.value for e in node.value.elts]
    return out


def _ddl_columns_minus_pk(path):
    create = _create(path)
    m = _PK_RE.search(open(path).read())
    pk = m.group(1) if m else None
    return {c.name for c in create.find_all(E.ColumnDef) if c.name != pk}


def _text(path):
    return resolve(open(path).read(), "c")  # ${catalog}/${*_schema} -> identifiers


def _create(path):
    return next((s for s in sqlglot.parse(_text(path), read="databricks", error_level="ignore")
                 if isinstance(s, E.Create)), None)


# ---------- fact DDL ----------

@pytest.mark.parametrize("path", TABLE_FILES, ids=[os.path.basename(f) for f in TABLE_FILES])
def test_fact_parses_and_has_pk_contract(path):
    create = _create(path)
    assert create is not None, f"{os.path.basename(path)} did not parse as a CREATE TABLE"
    m = _PK_RE.search(open(path).read())
    assert m, f"{os.path.basename(path)} has no CONSTRAINT pk_<t> PRIMARY KEY (<col>)"
    pk_col = m.group(1)
    assert pk_col.endswith("_sk"), f"{os.path.basename(path)} PK is not a surrogate _sk"
    cols = {c.name for c in create.find_all(E.ColumnDef)}
    stem = pk_col[:-len("_sk")]
    assert f"{stem}_id" in cols, f"{os.path.basename(path)} missing durable {stem}_id"


def test_expected_fact_set_present():
    names = {os.path.basename(f)[:-4] for f in TABLE_FILES}
    expected = {
        # facts / aggregates / bridges
        "media_event", "conversion_event", "attributed_outcome",
        "experiment_assignment_bridge", "campaign_day", "incrementality_result",
        "experiment_daily", "budget_allocation", "pacing_snapshot",
        # store_zone_interval RELOCATED to connected-store-signals as
        # sensor_report_interval (ADR 0033). CMN reads it back through the deprecated
        # exact-name store_zone_interval compatibility view, which is a view and so has no
        # entry here.
        "product_store_day",
        # relocated retail-media dimensions (gold; formerly canonical-core/media)
        "advertiser", "campaign", "ad_group", "creative", "placement",
        "experiment", "experiment_cell", "delivery_channel", "keyword",
        # audience promoted to shared silver marketing (ADR 0022) — no longer co-located here.
    }
    assert names == expected, f"fact set drift: missing={sorted(expected - names)} extra={sorted(names - expected)}"


# ---------- generator <-> DDL ----------

@pytest.mark.parametrize("path", TABLE_FILES, ids=[os.path.basename(f) for f in TABLE_FILES])
def test_generator_columns_match_ddl(path):
    table = os.path.basename(path)[:-4]
    consts = _generator_constants()
    gen = set(consts[COLUMNS_CONST[table]])
    ddl = _ddl_columns_minus_pk(path)
    assert gen == ddl, f"{table} column drift — missing={sorted(ddl - gen)} extra={sorted(gen - ddl)}"


# ---------- gold views ----------

@pytest.mark.parametrize("path", GOLD_FILES, ids=[os.path.basename(f) for f in GOLD_FILES])
def test_gold_view_no_raw_pii(path):
    stmt = sqlglot.parse_one(_text(path), read="databricks", error_level="ignore")
    sel = stmt.expression if isinstance(stmt, E.Create) else stmt
    outs = set(sel.named_selects)
    leaked = PII_COLUMNS & outs
    assert not leaked, f"{os.path.basename(path)} exposes raw PII: {sorted(leaked)}"


def test_store_zone_interval_compatibility_keeps_exact_name_and_shape():
    """Existing consumers address the retired table by this exact object and depend on
    its ordered projection. A differently named gold view is not compatibility."""
    assert os.path.exists(STORE_ZONE_COMPAT)
    stmt = sqlglot.parse_one(_text(STORE_ZONE_COMPAT), read="databricks")
    assert isinstance(stmt, E.Create)
    assert stmt.this.name == "store_zone_interval"
    expected = [
        "store_zone_interval_sk", "store_zone_interval_id", "store_sk", "store_id",
        "store_zone_code", "interval_start_ts", "interval_date", "interval_minutes",
        "footfall_count", "avg_dwell_seconds", "opportunity_to_see", "aggregated_flag",
        "record_source", "load_timestamp",
    ]
    assert stmt.expression.named_selects == expected


def test_store_zone_interval_compatibility_keeps_exact_retired_types():
    """A view can preserve column names while silently changing inferred types.

    Require explicit casts at the compatibility boundary so its contract does not
    depend on future type changes in the CSS source views.
    """
    stmt = sqlglot.parse_one(_text(STORE_ZONE_COMPAT), read="databricks")
    expected = {
        "store_zone_interval_sk": "BIGINT",
        "store_zone_interval_id": "STRING",
        "store_sk": "BIGINT",
        "store_id": "STRING",
        "store_zone_code": "STRING",
        "interval_start_ts": "TIMESTAMP",
        "interval_date": "DATE",
        "interval_minutes": "INT",
        "footfall_count": "BIGINT",
        "avg_dwell_seconds": "INT",
        "opportunity_to_see": "BIGINT",
        "aggregated_flag": "BOOLEAN",
        "record_source": "STRING",
        "load_timestamp": "TIMESTAMP",
    }
    actual = {}
    for projection in stmt.expression.expressions:
        expression = projection.this
        assert isinstance(expression, E.Cast), (
            f"{projection.alias_or_name} must be explicitly cast at the deprecated "
            "compatibility boundary"
        )
        actual[projection.alias_or_name] = expression.to.sql(dialect="databricks")

    assert actual == expected


def test_store_zone_interval_compatibility_does_not_invent_ots():
    txt = open(STORE_ZONE_COMPAT).read()
    assert "30.0" not in txt and "0.85" not in txt


def test_store_zone_interval_compatibility_uses_the_interval_shared_boundary():
    """The shim cannot rebuild interval metadata from operational facts.

    Its source must already contain only disclosure-approved interval rows, or a
    suppressed cell still publishes its timestamp and duration.
    """
    txt = open(STORE_ZONE_COMPAT).read()
    assert "gold_zone_traffic_interval_shared" in txt
    assert "${catalog}.${css_schema}.sensor_report_interval" not in txt
    assert (
        "FROM ${catalog}.${css_schema}.gold_zone_traffic_shared" not in txt
    )


# ---------- data-quality checks ----------

def _parse_checks(text):
    header = re.compile(r"^--\s*check:\s*(\w+)\s*\|\s*severity:\s*(error|warn|metric)\s*$", re.I)
    checks, current, buf = [], None, []
    for line in text.splitlines():
        m = header.match(line.strip())
        if m:
            current, buf = (m.group(1), m.group(2).lower()), []
            continue
        if current is None or line.strip().startswith("--"):
            continue
        buf.append(line)
        if ";" in line:
            checks.append((current[0], current[1], "\n".join(buf).rstrip().rstrip(";")))
            current, buf = None, []
    return checks


def test_dq_checks_well_formed():
    checks = _parse_checks(open(CHECKS).read())
    assert len(checks) >= 25, f"expected a meaningful suite, found {len(checks)}"
    names = [c[0] for c in checks]
    assert len(names) == len(set(names)), "duplicate check names"
    for name, severity, query in checks:
        assert severity in ("error", "warn", "metric")
        # table-form ${catalog}.${cmn_schema}.<t>, or the information_schema form '${cmn_schema}'.
        assert "${catalog}.${cmn_schema}." in query or "'${cmn_schema}'" in query, \
            f"{name} does not reference the package schema"


def test_every_fact_has_a_check():
    text = open(CHECKS).read()
    for path in TABLE_FILES:
        t = os.path.basename(path)[:-4]
        assert f"${{catalog}}.${{cmn_schema}}.{t}" in text, f"no DQ check covers {t}"


def test_checks_have_pii_and_currency_guards():
    text = open(CHECKS).read()
    assert "cmn_gold_no_raw_pii" in text, "missing the gold no-raw-PII guard"
    assert text.count("single_currency") >= 6, "single-reporting-currency checks missing on monetary facts"


# ---------- guardrails ----------

def _authored():
    return glob.glob(os.path.join(PKG, "**", "*.sql"), recursive=True) + [
        os.path.join(PKG, "glossary.md"), os.path.join(PKG, "README.md")]


def test_no_hardcoded_or_license():
    for f in _authored():
        txt = open(f).read()
        assert not re.search(r"https?://[\w.-]*databricks|retail_prod|retail_dev", txt), f"hardcoded ref in {f}"
        assert not re.search(r"Copyright|SPDX-License|Licensed under|All rights reserved", txt, re.I), f"licence in {f}"


def test_no_banned_sql():
    for f in glob.glob(os.path.join(PKG, "**", "*.sql"), recursive=True):
        assert not re.search(r"GROUP\s+BY\s+ALL|\b1\s*=\s*1\b", open(f).read(), re.I), f"banned SQL in {f}"
