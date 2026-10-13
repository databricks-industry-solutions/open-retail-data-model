"""Static consistency tests for Intent Product Discovery metric view.

Tests that parse the YAML of mv_intent_discovery_result_performance, verify
all required measures exist (result CTR, add-to-cart rate, discovery conversion rate),
ensure ratio measures use sum()-based expressions (not avg of per-row ratios),
and validate that all referenced columns exist in the source gold view.

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
AC_PKG = os.path.join(REPO, "outcome-packages", "agentic-commerce")
GOLD_DIR = os.path.join(AC_PKG, "gold")
MV_DIR = os.path.join(AC_PKG, "metric-views")
GOLD_DISCOVERY = os.path.join(GOLD_DIR, "gold_intent_product_discovery_performance.sql")
MV_DISCOVERY = os.path.join(MV_DIR, "intent_discovery_result_performance.sql")


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
        expr_str = item.get("expr", "").strip() if isinstance(item, dict) else ""
        if expr_str:
            # Simple regex to find identifiers; not perfect but good enough for validation
            cols.update(re.findall(r"\b([a-z_][a-z0-9_]*)\b", expr_str, re.I))
    return cols


class TestIntentDiscoveryMetricView:
    """Validate mv_intent_discovery_result_performance YAML and column references."""

    def test_metric_view_yaml_parses(self):
        """Metric view YAML should parse without error."""
        doc = _metric_doc(MV_DISCOVERY)
        assert doc is not None
        version = doc.get("version")
        assert version in [1.0, 1.1, "1.0", "1.1"], f"version {version} not supported"
        assert doc.get("comment")
        assert doc.get("source")

    def test_required_measures_exist(self):
        """All required KPI measures should be defined."""
        doc = _metric_doc(MV_DISCOVERY)
        measures = {m["name"] for m in doc.get("measures", [])}
        required = {
            "result_count",
            "result_ctr",
            "add_to_cart_rate",
            "discovery_conversion_rate",
        }
        assert required.issubset(
            measures
        ), f"Missing measures: {required - measures}"

    def test_ratio_measures_use_sum_expressions(self):
        """Ratio measures (CTR, rates) should aggregate with SUM, not AVG."""
        doc = _metric_doc(MV_DISCOVERY)
        measures = _measure_expressions(doc)

        ratio_measures = {
            "result_ctr",
            "add_to_cart_rate",
            "discovery_conversion_rate",
        }

        for name in ratio_measures:
            if name in measures:
                expr = measures[name].upper()
                # Ratio measures should use SUM(...) / COUNT(...) pattern
                assert "SUM(" in expr, f"{name} should use SUM() in numerator"
                assert "NULLIF(" in expr or "COALESCE(" in expr or expr.count("SUM(") >= 2, \
                    f"{name} should handle null division safely"

    def test_all_source_columns_exist_in_gold_view(self):
        """All columns referenced in source SELECT should exist in gold view."""
        doc = _metric_doc(MV_DISCOVERY)
        gold_cols = _table_columns(GOLD_DISCOVERY)

        # Extract SELECT clause from source
        source = doc.get("source", "").strip()
        # Simple extraction of columns between SELECT and FROM
        match = re.search(r"SELECT\s+(.*?)\s+FROM", source, re.I | re.S)
        if match:
            cols_clause = match.group(1)
            # Extract column names
            selected_cols = {col.strip() for col in cols_clause.split(",")}
            # Filter out special patterns like functions
            actual_cols = {
                col for col in selected_cols if col and not col.upper().startswith("(")
            }
            missing = actual_cols - gold_cols
            assert not missing, f"Source columns not in gold view: {missing}"

    def test_all_field_and_measure_columns_exist(self):
        """All columns referenced in fields and measures must exist in source."""
        doc = _metric_doc(MV_DISCOVERY)
        # Get columns from source SELECT
        source = doc.get("source", "").strip()
        match = re.search(r"SELECT\s+(.*?)\s+FROM", source, re.I | re.S)
        if match:
            cols_clause = match.group(1)
            source_cols = {col.strip() for col in cols_clause.split(",") if col.strip()}
        else:
            source_cols = set()

        referenced_cols = _get_all_referenced_columns(doc)
        # Filter out SQL functions and keywords
        sql_funcs = {
            "COUNT", "SUM", "AVG", "MIN", "MAX", "CAST", "NULLIF",
            "COALESCE", "CASE", "WHEN", "THEN", "ELSE", "END",
            "DISTINCT", "AS", "INT", "DOUBLE"
        }
        referenced_cols = {c for c in referenced_cols if c.upper() not in sql_funcs}

        missing = referenced_cols - source_cols
        assert not missing, f"Referenced columns not in source: {missing}"

    def test_version_format(self):
        """Metric view version should be semantic."""
        doc = _metric_doc(MV_DISCOVERY)
        version = doc.get("version")
        assert version, "version field should exist"
        assert isinstance(version, (int, float, str))

    def test_display_names_and_comments(self):
        """All fields and measures should have display names and comments."""
        doc = _metric_doc(MV_DISCOVERY)

        for field in doc.get("fields", []):
            assert field.get("display_name"), f"Field {field['name']} missing display_name"
            assert field.get("comment"), f"Field {field['name']} missing comment"

        for measure in doc.get("measures", []):
            assert measure.get("display_name"), f"Measure {measure['name']} missing display_name"
            assert measure.get("comment"), f"Measure {measure['name']} missing comment"


MV_INTENTS = os.path.join(MV_DIR, "intent_discovery_intents.sql")


def test_zero_result_rate_is_intent_grain_with_left_join():
    # Glossary: intent events that return no result events / total intent events. An
    # INNER JOIN to results would silently drop exactly the zero-result intents.
    doc = _metric_doc(MV_INTENTS)
    source = doc["source"].upper()
    assert "LEFT JOIN" in source and "DISCOVERY_INTENT_EVENT" in source
    measures = {m["name"]: m["expr"] for m in doc["measures"]}
    assert "zero_result_rate" in measures
    assert "NULLIF(COUNT(*), 0)" in measures["zero_result_rate"]
    assert not {f["name"] for f in doc["fields"]} & {"discovery_intent_event_id", "intent_text_hash", "session_id", "profile_id"}
