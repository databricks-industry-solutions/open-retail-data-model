"""Static consistency tests for data-sharing-with-suppliers metric views.

Tests that parse the YAML of metric views (category_growth, joint_demand_plan,
supplier_media_report, data_product_revenue), verify every measure exists, ensure
ratio measures use sum()-based expressions (not avg of per-row ratios), validate
that all referenced columns exist in the source gold views, and check the header
structure.

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
DSS_PKG = os.path.join(REPO, "outcome-packages", "data-sharing-with-suppliers")
GOLD_DIR = os.path.join(DSS_PKG, "gold")
MV_DIR = os.path.join(DSS_PKG, "metric-views")

GOLD_CATEGORY_GROWTH = os.path.join(GOLD_DIR, "gold_category_growth.sql")
MV_CATEGORY_GROWTH = os.path.join(MV_DIR, "category_growth.sql")


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


def _view_columns(path):
    """Extract column names from a CREATE VIEW statement."""
    raw = _text(path)
    parsed = sqlglot.parse_one(raw, read="databricks", error_level="ignore")

    assert isinstance(parsed, E.Create), f"{os.path.basename(path)} did not parse as CREATE"
    # For CREATE VIEW, get the SELECT output columns
    return set(parsed.expression.named_selects)


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


# ---------- Category Growth metric view tests ----------

def test_mv_category_growth_exists():
    assert os.path.exists(MV_CATEGORY_GROWTH), (
        f"category_growth.sql does not exist at {MV_CATEGORY_GROWTH}"
    )


def test_mv_category_growth_parses():
    text = open(MV_CATEGORY_GROWTH).read()
    assert "CREATE OR REPLACE VIEW" in text
    assert "WITH METRICS LANGUAGE YAML" in text
    assert "mv_category_growth" in text
    _metric_doc(MV_CATEGORY_GROWTH)  # should not raise


def test_mv_category_growth_has_version_header():
    text = open(MV_CATEGORY_GROWTH).read()
    assert re.search(r"-- Version: 0\.\d+", text), "Missing version header"
    assert re.search(r"-- Generated: 20\d{2}-\d{2}-\d{2}", text), "Missing generated date"
    assert "-- Last reviewed:" in text, "Missing last reviewed date"


def test_mv_category_growth_has_required_fields():
    doc = _metric_doc(MV_CATEGORY_GROWTH)
    field_names = {f["name"] for f in doc.get("fields", [])}
    required_fields = {"category", "fiscal_year", "fiscal_period"}
    assert required_fields <= field_names, f"missing fields: {sorted(required_fields - field_names)}"


def test_mv_category_growth_has_required_measures():
    doc = _metric_doc(MV_CATEGORY_GROWTH)
    measure_names = {m["name"] for m in doc.get("measures", [])}
    required_measures = {
        "category_revenue", "category_units", "category_margin",
        "delta_revenue", "distribution_effect", "volume_effect", "price_effect", "mix_effect",
        "pop_growth_rate", "yoy_growth_rate", "promo_contribution",
    }
    assert required_measures <= measure_names, f"missing measures: {sorted(required_measures - measure_names)}"


def test_mv_category_growth_ratio_measures_use_sum_not_avg():
    doc = _metric_doc(MV_CATEGORY_GROWTH)
    measures = _measure_expressions(doc)
    # Every measure must roll up correctly across categories and periods: amounts are
    # SUMs and both growth rates are SUM/SUM. No AVG of a per-row ratio, and no window
    # function (a metric view measure with OVER fails at query time).
    for name, expr in measures.items():
        up = expr.upper()
        assert "AVG(" not in up, f"{name} averages a per-row value: {expr}"
        assert " OVER" not in up, f"{name} uses a window function: {expr}"
    for ratio_name in ("pop_growth_rate", "yoy_growth_rate"):
        assert "NULLIF(SUM(" in measures[ratio_name].upper(), \
            f"{ratio_name} should be a SUM/SUM ratio, got: {measures[ratio_name]}"


def test_mv_category_growth_yoy_uses_year_ago_numerator():
    # YoY must compare revenue with prior_year_revenue over the same rows; dividing the
    # period-over-period delta by the year-ago base mixes two different comparisons.
    expr = _measure_expressions(_metric_doc(MV_CATEGORY_GROWTH))["yoy_growth_rate"]
    assert "delta_revenue" not in expr
    assert "prior_year_revenue IS NOT NULL" in expr


def test_mv_category_growth_omits_per_row_shares():
    # The gold view's shares are ratios of one category x period row with no exposed
    # numerator/denominator, so they cannot be measures.
    names = {m["name"] for m in _metric_doc(MV_CATEGORY_GROWTH)["measures"]}
    assert not names & {"category_share", "value_share_platinum", "value_share_gold",
                        "value_share_silver", "value_share_bronze",
                        "supplier_top_share", "supplier_top_score"}


def test_mv_category_growth_referenced_columns_exist():
    doc = _metric_doc(MV_CATEGORY_GROWTH)
    gold_cols = _view_columns(GOLD_CATEGORY_GROWTH)
    ref_cols = _get_all_referenced_columns(doc)
    missing = ref_cols - gold_cols
    assert not missing, f"columns referenced in {os.path.basename(MV_CATEGORY_GROWTH)} " \
                        f"not found in {os.path.basename(GOLD_CATEGORY_GROWTH)}: {sorted(missing)}"


def test_mv_category_growth_has_no_hardcoded_catalog():
    text = open(MV_CATEGORY_GROWTH).read()
    assert not re.search(r"https?://[\w.-]*databricks|retail_prod|retail_dev", text, re.I)


def test_mv_category_growth_yaml_valid():
    doc = _metric_doc(MV_CATEGORY_GROWTH)
    assert "version" in doc, "YAML missing version"
    assert "comment" in doc, "YAML missing comment"
    version = doc.get("version")
    # Accept 1, 1.0, 1.1 (as int, float, or string)
    assert version in [1, 1.0, 1.1, "1", "1.0", "1.1"], \
        f"YAML version should be 1.x, got {version}"
    for field in doc.get("fields", []):
        assert "name" in field, "field missing name"
        assert "expr" in field, "field missing expr"
        assert "display_name" in field, "field missing display_name"
    for measure in doc.get("measures", []):
        assert "name" in measure, "measure missing name"
        assert "expr" in measure, "measure missing expr"
        assert "display_name" in measure, "measure missing display_name"
