"""Static consistency tests for payment leakage and realized margin metric views.

Tests that parse the YAML of mv_realized_margin and mv_payment_actuals, verify
every measure required by the spec exists, ensure ratio measures use sum()-based
expressions (not avg of per-row ratios), and validate that all referenced columns
exist in the source tables.

No Spark engine required: pure DDL validation.
"""

import os
import re

import pytest
import sqlglot
import sqlglot.expressions as E
import yaml

from tools.ordm_config import resolve

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BMV_PKG = os.path.join(REPO, "outcome-packages", "balancing-margin-and-volume")
GOLD_DIR = os.path.join(BMV_PKG, "gold")
MV_DIR = os.path.join(BMV_PKG, "metric-views")
GOLD_REALIZED_MARGIN = os.path.join(GOLD_DIR, "gold_realized_margin.sql")
MV_REALIZED_MARGIN = os.path.join(MV_DIR, "realized_margin.sql")
MV_PAYMENT_ACTUALS = os.path.join(MV_DIR, "payment_actuals.sql")


def _text(path):
    """Resolve ${catalog}/${*_schema} tokens and return file contents."""
    return resolve(open(path).read(), "ordm")


def _metric_doc(path):
    """Parse UC metric-view YAML document from its dollar-quoted SQL body."""
    text = open(path).read()
    match = re.search(
        r"WITH\s+METRICS\s+LANGUAGE\s+YAML\s+AS\s*\$\$(.*?)\$\$",
        text,
        re.I | re.S,
    )
    assert match, f"{os.path.basename(path)} has no metric-view YAML body"
    return yaml.safe_load(match.group(1))


def _table_columns(path):
    """Extract column names from a CREATE TABLE or CREATE VIEW statement."""
    raw = _text(path)
    parsed = sqlglot.parse_one(raw, read="databricks", error_level="ignore")

    # Handle case where parse returns a Block containing multiple statements
    if isinstance(parsed, E.Block):
        create = next((stmt for stmt in parsed.expressions if isinstance(stmt, E.Create)), None)
        assert create, f"{os.path.basename(path)}: no CREATE statement found in block"
    else:
        create = parsed

    assert isinstance(create, E.Create), f"{os.path.basename(path)} did not parse as CREATE"

    # For CREATE TABLE, get column names from ColumnDef nodes
    if create.kind == "TABLE":
        return {col.name for col in create.find_all(E.ColumnDef)}

    # For CREATE VIEW, get the SELECT output columns
    return set(create.expression.named_selects)


def _measure_expressions(doc):
    """Return a dict of {measure_name: expr_string} from the metric view YAML."""
    out = {}
    for measure in doc.get("measures", []):
        out[measure["name"]] = measure.get("expr", "").strip()
    return out


def _get_all_referenced_columns(doc):
    """Extract all columns referenced in fields and measures."""
    cols = set()
    for item in [*doc.get("fields", []), *doc.get("measures", [])]:
        expr_str = item.get("expr", "").strip()
        if not expr_str:
            continue
        try:
            expression = sqlglot.parse_one(expr_str, read="databricks")
            cols.update({col.name for col in expression.find_all(E.Column)})
        except Exception:
            pass
    return cols


# ---------- prerequisites: files exist ----------

def test_gold_realized_margin_exists():
    assert os.path.exists(GOLD_REALIZED_MARGIN), (
        f"gold_realized_margin.sql does not exist at {GOLD_REALIZED_MARGIN}"
    )


def test_mv_realized_margin_exists():
    assert os.path.exists(MV_REALIZED_MARGIN), (
        f"realized_margin.sql does not exist at {MV_REALIZED_MARGIN}"
    )


def test_mv_payment_actuals_exists():
    assert os.path.exists(MV_PAYMENT_ACTUALS), (
        f"payment_actuals.sql does not exist at {MV_PAYMENT_ACTUALS}"
    )


# ---------- gold_realized_margin guardrails ----------

def test_gold_realized_margin_has_no_cast_null_placeholders():
    """The gold view must not contain unimplemented CAST(NULL AS ...) placeholders."""
    raw = _text(GOLD_REALIZED_MARGIN)
    casts = re.findall(r"CAST\s*\(\s*NULL\s+AS\s+\w+", raw, re.I)
    assert not casts, (
        f"gold_realized_margin contains {len(casts)} CAST(NULL AS ...) placeholder(s)"
    )


def test_gold_realized_margin_parses_as_create():
    """Basic sanity: the gold view SQL parses as a CREATE statement."""
    raw = _text(GOLD_REALIZED_MARGIN)
    create = sqlglot.parse_one(raw, read="databricks", error_level="ignore")
    assert isinstance(create, E.Create), "gold_realized_margin did not parse as CREATE VIEW"


def test_gold_realized_margin_has_expected_output_columns():
    """Spec §1 mandates these output columns on gold_realized_margin."""
    cols = _table_columns(GOLD_REALIZED_MARGIN)
    required = {
        "product_sk", "store_sk", "product_id", "store_id", "date_key", "currency_code",
        "pos_units", "pos_net_sales_lc", "pos_cogs_lc",
        "order_units", "order_booked_sales_lc", "order_settled_sales_lc", "order_unsettled_sales_lc",
        "order_refund_lc", "order_chargeback_lc", "order_adjustment_lc", "order_cogs_lc",
        "booked_revenue_lc", "realized_revenue_lc", "leakage_lc", "cogs_lc",
        "booked_margin_lc", "realized_margin_lc",
    }
    missing = sorted(required - cols)
    assert not missing, (
        f"gold_realized_margin missing required columns: {missing}"
    )


# ---------- mv_realized_margin §2 ----------

def test_mv_realized_margin_parses():
    """The metric view YAML must parse and be well-formed."""
    doc = _metric_doc(MV_REALIZED_MARGIN)
    assert doc.get("version") == 1.1, "mv_realized_margin must declare version: 1.1"
    assert "measures" in doc, "mv_realized_margin has no measures block"


def test_mv_realized_margin_spec_measures_all_present():
    """Spec §2 requires these measures; all must be present."""
    doc = _metric_doc(MV_REALIZED_MARGIN)
    measures = {m["name"] for m in doc.get("measures", [])}
    required = {
        "booked_revenue_lc", "realized_revenue_lc", "leakage_lc",
        "refund_lc", "chargeback_lc", "adjustment_lc", "unsettled_sales_lc",
        "cogs_lc", "booked_margin_lc", "realized_margin_lc",
        "booked_margin_pct", "realized_margin_pct", "leakage_rate", "order_channel_leakage_rate", "order_channel_share",
    }
    missing = sorted(required - measures)
    assert not missing, f"mv_realized_margin missing spec measures: {missing}"


def test_mv_realized_margin_rate_measures_are_sums_not_avgs():
    """Spec §2 & §6: ratio measures must divide sums, never AVG of per-row ratios."""
    doc = _metric_doc(MV_REALIZED_MARGIN)
    exprs = _measure_expressions(doc)

    rate_measures = {
        "booked_margin_pct", "realized_margin_pct", "leakage_rate", "order_channel_leakage_rate", "order_channel_share",
    }
    bad = []
    for name in rate_measures:
        if name in exprs:
            expr = exprs[name]
            # Ratio expressions should use SUM()/NULLIF(SUM()), not AVG
            if re.search(r"\bAVG\s*\(", expr, re.I):
                bad.append(f"{name}: {expr}")

    assert not bad, (
        f"mv_realized_margin rate measures use AVG (should use SUM ratios):\n" +
        "\n".join(bad)
    )


# Canonical dimension tables a metric-view source may join, keyed by the token-qualified name the
# source uses. Their columns are available to fields/measures.
_DIMENSION_TABLES = {
    "${product_schema}.product": ("canonical-core", "product", "tables", "product.sql"),
    "${store_schema}.store": ("canonical-core", "store", "tables", "store.sql"),
    "fiscal_calendar": ("canonical-core", "calendar", "tables", "fiscal_calendar.sql"),
}


def _joined_dimension_columns(doc):
    """Columns of every canonical dimension table the metric view's source query joins."""
    source_sql = doc.get("source", "")
    cols = set()
    for token, parts in _DIMENSION_TABLES.items():
        path = os.path.join(REPO, *parts)
        if token in source_sql and os.path.exists(path):
            cols.update(_table_columns(path))
    return cols


def test_mv_realized_margin_references_exist():
    """Every field/measure column reference must exist in source or joined tables."""
    doc = _metric_doc(MV_REALIZED_MARGIN)

    # Collect all available columns from the source and any joined tables
    available_cols = set()

    # Add columns from gold_realized_margin
    gold_cols = _table_columns(GOLD_REALIZED_MARGIN)
    available_cols.update(gold_cols)

    available_cols.update(_joined_dimension_columns(doc))

    # Check all referenced columns
    referenced_cols = _get_all_referenced_columns(doc)
    missing = sorted(referenced_cols - available_cols)

    assert not missing, (
        f"mv_realized_margin references undefined columns: {missing}"
    )


# ---------- mv_payment_actuals §3 ----------

def test_mv_payment_actuals_parses():
    """The metric view YAML must parse and be well-formed."""
    doc = _metric_doc(MV_PAYMENT_ACTUALS)
    assert doc.get("version") == 1.1, "mv_payment_actuals must declare version: 1.1"
    assert "measures" in doc, "mv_payment_actuals has no measures block"


def test_mv_payment_actuals_spec_measures_all_present():
    """Spec §3 requires these measures; all must be present."""
    doc = _metric_doc(MV_PAYMENT_ACTUALS)
    measures = {m["name"] for m in doc.get("measures", [])}
    required = {
        "settled_sale_amount_lc", "refund_amount_lc", "chargeback_amount_lc", "adjustment_amount_lc",
        "refund_rate", "chargeback_rate", "adjustment_rate", "payment_leakage_rate",
    }
    missing = sorted(required - measures)
    assert not missing, f"mv_payment_actuals missing spec measures: {missing}"


def test_mv_payment_actuals_rate_measures_are_sums_not_avgs():
    """Spec §3 & §6: rate measures must divide sums, never AVG of per-row ratios."""
    doc = _metric_doc(MV_PAYMENT_ACTUALS)
    exprs = _measure_expressions(doc)

    rate_measures = {
        "refund_rate", "chargeback_rate", "adjustment_rate", "payment_leakage_rate",
    }
    bad = []
    for name in rate_measures:
        if name in exprs:
            expr = exprs[name]
            # Ratio expressions should use SUM()/NULLIF(SUM()), not AVG
            if re.search(r"\bAVG\s*\(", expr, re.I):
                bad.append(f"{name}: {expr}")

    assert not bad, (
        f"mv_payment_actuals rate measures use AVG (should use SUM ratios):\n" +
        "\n".join(bad)
    )


def test_mv_payment_actuals_references_exist():
    """Every field/measure column reference must exist in source or joined tables."""
    doc = _metric_doc(MV_PAYMENT_ACTUALS)

    # Collect all available columns from the source (gold_payment_actuals)
    available_cols = set()

    gold_payment_path = os.path.join(GOLD_DIR, "gold_payment_actuals.sql")
    if os.path.exists(gold_payment_path):
        available_cols.update(_table_columns(gold_payment_path))

    available_cols.update(_joined_dimension_columns(doc))

    # Check all referenced columns
    referenced_cols = _get_all_referenced_columns(doc)
    missing = sorted(referenced_cols - available_cols)

    assert not missing, (
        f"mv_payment_actuals references undefined columns: {missing}"
    )
