"""Static consistency tests for conversational shopping metric views.

Tests that parse the YAML of mv_conversational_shopping_session, verify its
dimensions and measures exist,
ensure ratio measures use sum()-based expressions, and validate that all
referenced columns exist in the source tables.

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
GOLD_SESSION = os.path.join(GOLD_DIR, "gold_conversational_shopping_session.sql")
GOLD_DISCOVERY = os.path.join(GOLD_DIR, "gold_intent_product_discovery_performance.sql")
MV_SESSION = os.path.join(MV_DIR, "conversational_shopping_session.sql")


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
    """Extract output columns from a CREATE VIEW statement."""
    raw = _text(path)
    parsed = sqlglot.parse_one(raw, read="databricks", error_level="ignore")

    if isinstance(parsed, E.Block):
        create = next((stmt for stmt in parsed.expressions if isinstance(stmt, E.Create)), None)
        assert create, f"{os.path.basename(path)}: no CREATE statement found in block"
    else:
        create = parsed

    assert isinstance(create, E.Create), f"{os.path.basename(path)} did not parse as CREATE"
    return set(create.expression.named_selects)


def _get_all_referenced_columns(doc):
    """Extract all columns referenced in fields and measures."""
    cols = set()
    for item in [*doc.get("fields", []), *doc.get("measures", [])]:
        expr = item.get("expr", "").strip()
        if expr:
            parsed = sqlglot.parse_one(expr, read="databricks", error_level="ignore")
            for col in parsed.find_all(E.Column):
                if col.table is None:
                    cols.add(col.name)
    return cols


class TestConversationalShoppingSessionMetrics:
    def test_yaml_structure(self):
        doc = _metric_doc(MV_SESSION)
        assert doc["version"] in [1.1, "1.1"], f"version should be 1.1, got {doc['version']}"
        assert doc.get("comment"), "metric view must have a comment"
        assert "source" in doc, "metric view must have a source query"
        assert len(doc.get("fields", [])) > 0, "metric view must have fields"
        assert len(doc.get("measures", [])) > 0, "metric view must have measures"

    def test_required_measures_exist(self):
        doc = _metric_doc(MV_SESSION)
        measure_names = {m["name"] for m in doc.get("measures", [])}
        
        # KPIs specified in the brief and glossary
        required = {
            "assisted_conversion_rate",
            "handoff_rate",
            "fallback_rate",
            "session_add_to_cart_rate",
        }
        missing = required - measure_names
        assert not missing, f"Missing required measures: {missing}"

    def test_rate_measures_use_sum_expressions(self):
        doc = _metric_doc(MV_SESSION)
        for measure in doc.get("measures", []):
            if "rate" in measure["name"] or "count" in measure["name"]:
                expr = measure.get("expr", "").strip()
                # Rates should use SUM of boolean expressions, not AVG
                if "rate" in measure["name"]:
                    assert "SUM(CASE" in expr or "SUM(" in expr, \
                        f"Rate measure '{measure['name']}' should use SUM, got: {expr}"

    def test_all_referenced_columns_exist_in_source(self):
        doc = _metric_doc(MV_SESSION)
        source_cols = _view_columns(GOLD_SESSION)
        referenced = _get_all_referenced_columns(doc)
        
        # Filter to columns that are likely to be in source (exclude CASE keywords, etc.)
        unknown = referenced - source_cols - {"COALESCE", "CAST", "CASE", "WHEN", "THEN", "ELSE"}
        
        # Allow COALESCE calls and aggregates
        unknown = {col for col in unknown if not any(
            agg in col.upper() for agg in ["COUNT", "SUM", "AVG", "MAX", "MIN"]
        )}
        
        assert not unknown, f"Columns not found in source view: {unknown}"

    def test_fields_have_display_names_and_comments(self):
        doc = _metric_doc(MV_SESSION)
        for field in doc.get("fields", []):
            assert field.get("display_name"), f"Field '{field['name']}' missing display_name"
            assert field.get("comment"), f"Field '{field['name']}' missing comment"

    def test_measures_have_display_names_and_comments(self):
        doc = _metric_doc(MV_SESSION)
        for measure in doc.get("measures", []):
            assert measure.get("display_name"), f"Measure '{measure['name']}' missing display_name"
            assert measure.get("comment"), f"Measure '{measure['name']}' missing comment"
