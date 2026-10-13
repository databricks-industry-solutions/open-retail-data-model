"""Tests for Agentic Commerce / Intent Product Discovery.

Static tests keep the DDL, generator, DQ checks, and gold schemas aligned.
Spark fixture tests run the real gold SQL over temp views to validate the
candidate availability logic and result engagement rollups.
"""

import ast
import os
import re

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.ordm_config import resolve, view_select_body

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PKG = os.path.join(REPO, "outcome-packages", "agentic-commerce")
GENERATOR = os.path.join(REPO, "runtime", "synthetic-data", "generators", "agentic_commerce.py")
REGISTRY = os.path.join(REPO, "runtime", "synthetic-data", "generators", "_registry.py")
CHECKS = os.path.join(PKG, "checks.sql")

TABLES = {
    "conversation_session": ("conversation_session_sk", "CONVERSATION_SESSION_COLUMNS"),
    "assistant_turn_event": ("assistant_turn_event_sk", "ASSISTANT_TURN_EVENT_COLUMNS"),
    "discovery_intent_event": ("discovery_intent_event_sk", "DISCOVERY_INTENT_EVENT_COLUMNS"),
    "discovery_result_event": ("discovery_result_event_sk", "DISCOVERY_RESULT_EVENT_COLUMNS"),
    "discovery_engagement_event": ("discovery_engagement_event_sk", "DISCOVERY_ENGAGEMENT_EVENT_COLUMNS"),
}
GOLD_CANDIDATE = os.path.join(PKG, "gold", "gold_product_discovery_candidate_current.sql")
GOLD_PERFORMANCE = os.path.join(PKG, "gold", "gold_intent_product_discovery_performance.sql")
GOLD_SESSION = os.path.join(PKG, "gold", "gold_conversational_shopping_session.sql")
GOLD_CONVERSATION_PERFORMANCE = os.path.join(PKG, "gold", "gold_conversational_shopping_performance.sql")
PII_COLUMNS = {
    "profile_id", "session_id", "conversation_id", "intent_text_hash", "loyalty_id",
    "household_id", "first_name", "middle_name", "last_name", "date_of_birth", "contact_value",
}


def _path(table):
    return os.path.join(PKG, "tables", f"{table}.sql")


def _text(path):
    return resolve(open(path).read(), "ordm")


def _create(path):
    return next((s for s in sqlglot.parse(_text(path), read="databricks", error_level="ignore")
                 if isinstance(s, E.Create)), None)


def _ddl_columns_minus_pk(table):
    create = _create(_path(table))
    pk = TABLES[table][0]
    return {c.name for c in create.find_all(E.ColumnDef) if c.name != pk}


def _generator_constants():
    mod = ast.parse(open(GENERATOR).read())
    out = {}
    for node in mod.body:
        if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name) \
                and isinstance(node.value, ast.List) and all(isinstance(e, ast.Constant) for e in node.value.elts):
            out[node.targets[0].id] = [e.value for e in node.value.elts]
    return out


@pytest.mark.parametrize("table", list(TABLES))
def test_table_parses_and_has_pk_contract(table):
    create = _create(_path(table))
    assert create is not None, f"{table} did not parse as a CREATE TABLE"
    text = open(_path(table)).read()
    pk = TABLES[table][0]
    assert re.search(rf"CONSTRAINT\s+pk_{table}\s+PRIMARY\s+KEY\s*\(\s*{pk}\s*\)", text, re.I)
    cols = {c.name for c in create.find_all(E.ColumnDef)}
    assert pk in cols
    assert pk.removesuffix("_sk") + "_id" in cols
    assert "dbx_data_type" in text


@pytest.mark.parametrize("table", list(TABLES))
def test_generator_columns_match_ddl(table):
    gen = set(_generator_constants()[TABLES[table][1]])
    ddl = _ddl_columns_minus_pk(table)
    assert gen == ddl, f"{table} drift: missing={sorted(ddl - gen)} extra={sorted(gen - ddl)}"


def test_registry_includes_agentic_generator():
    text = open(REGISTRY).read()
    # provides key is "ac" (matches ${ac_schema}); the parallel "agentic" token was
    # dropped when the conversational and A2A slices were reconciled onto one schema.
    assert 'GenSpec("agentic_commerce", frozenset({"ac"})' in text
    assert '"inventory"' in text and '"order"' in text


@pytest.mark.parametrize("path", [GOLD_CANDIDATE, GOLD_PERFORMANCE, GOLD_SESSION, GOLD_CONVERSATION_PERFORMANCE])
def test_gold_views_expose_required_columns_and_no_raw_pii(path):
    stmt = sqlglot.parse_one(view_select_body(_text(path)), read="databricks", error_level="ignore")
    outputs = set(stmt.named_selects)
    leaked = PII_COLUMNS & outputs
    assert not leaked, f"{os.path.basename(path)} exposes raw PII: {sorted(leaked)}"
    leaked_surrogates = {name for name in outputs if name.endswith("_sk")}
    assert not leaked_surrogates, f"{os.path.basename(path)} exposes deployment-local surrogate keys: {sorted(leaked_surrogates)}"
    if path == GOLD_CANDIDATE:
        required = {"product_id", "product_name", "category", "current_list_price_amount",
                    "store_id", "units_available", "is_available_flag"}
    elif path == GOLD_PERFORMANCE:
        required = {"discovery_result_event_id", "intent_category", "known_customer_flag",
                    "result_rank", "selected_flag", "added_to_cart_flag", "purchased_flag",
                    "purchase_net_amount"}
    elif path == GOLD_SESSION:
        required = {"conversation_session_id", "entry_channel", "primary_intent_category",
                    "total_turns", "handoff_flag", "fallback_turns", "selected_flag",
                    "added_to_cart_flag", "purchased_flag", "purchase_net_amount"}
    else:
        required = {"started_date", "entry_channel", "primary_intent_category",
                    "conversation_sessions", "sessions_reaching_discovery",
                    "assisted_conversion_rate", "handoff_rate", "fallback_rate"}
    assert required <= outputs, f"{os.path.basename(path)} missing: {sorted(required - outputs)}"


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


def test_dq_checks_well_formed_and_cover_tables():
    text = open(CHECKS).read()
    checks = _parse_checks(text)
    assert len(checks) >= 30
    names = [c[0] for c in checks]
    assert len(names) == len(set(names)), "duplicate check names"
    for name, severity, query in checks:
        assert severity in ("error", "warn", "metric")
        assert "${catalog}.${ac_schema}." in query or "'${ac_schema}'" in query, \
            f"{name} does not reference the package schema"
    for table in TABLES:
        assert f"${{catalog}}.${{ac_schema}}.{table}" in text
    assert "agentic_gold_no_raw_pii" in text
    assert text.count("single_currency") >= 2


def test_no_banned_or_hardcoded_patterns():
    authored = [os.path.join(PKG, "README.md"), os.path.join(PKG, "glossary.md")]
    for root, _, files in os.walk(PKG):
        authored += [os.path.join(root, f) for f in files if f.endswith(".sql") or f.endswith((".yaml", ".yml"))]
    pat = re.compile(r"GROUP\s+BY\s+ALL|\b1\s*=\s*1\b|https?://[\w.-]*databricks|retail_mvm|retail_ecm|Copyright|SPDX|Licensed under", re.I)
    bad = [os.path.relpath(f, REPO) for f in authored if pat.search(open(f).read())]
    assert not bad, f"banned SQL/hardcoded identifier/license pattern: {bad}"


def _body(path, replacements):
    body = view_select_body(open(path).read())
    for src, dst in replacements:
        body = body.replace(src, dst)
    return body


def test_candidate_view_uses_latest_inventory_and_current_price(spark):
    spark.createDataFrame(
        [(1, "P1", "0001", "SKU1", "STYLE1", "Blue Shoe", "Acme", "footwear", "shoes",
          "apparel", "blue", "9", "each", 25.0, "USD", "active", True),
         (2, "P2", "0002", "SKU2", None, "Old Hat", "Acme", "accessories", "hats",
          "apparel", None, None, "each", 10.0, "USD", "inactive", True),
         (3, "P3", "0003", "SKU3", None, "No Inventory Tee", "Acme", "apparel", "tops",
          "apparel", None, None, "each", 15.0, "USD", "active", True)],
        "product_sk int, product_id string, gtin string, sku string, style_id string, product_name string, "
        "brand string, category string, subcategory string, department string, color string, size string, "
        "unit_of_measure string, list_price double, currency_code string, product_status string, is_current boolean",
    ).createOrReplaceTempView("product")
    spark.createDataFrame(
        [(10, 1, "P1", "list", 20.0, "USD", "2024-01-01", True),
         (11, 1, "P1", "list", 22.0, "USD", "2024-06-01", True)],
        "product_price_sk int, product_sk int, product_id string, price_type string, amount double, "
        "currency_code string, effective_from_date string, is_current boolean",
    ).createOrReplaceTempView("product_price")
    spark.createDataFrame(
        [(100, "IP1", 1, "P1", 9, "S1", "2024-06-01", 0.0, True, 0.0),
         (101, "IP2", 1, "P1", 9, "S1", "2024-06-02", 5.0, False, 0.8)],
        "inventory_position_sk int, inventory_position_id string, product_sk int, product_id string, "
        "store_sk int, store_id string, date_key string, units_on_hand_eod double, is_stockout boolean, "
        "size_availability_pct double",
    ).createOrReplaceTempView("inventory_position")
    body = _body(GOLD_CANDIDATE, [
        ("${catalog}.${product_schema}.product_price", "product_price"),
        ("${catalog}.${product_schema}.product", "product"),
        ("${catalog}.${inventory_schema}.inventory_position", "inventory_position"),
    ])
    spark.sql("CREATE OR REPLACE TEMP VIEW candidate AS " + body)
    row = spark.sql("SELECT product_id, current_list_price_amount, units_available, is_available_flag "
                    "FROM candidate WHERE product_id = 'P1'").first()
    assert row.product_id == "P1"
    assert float(row.current_list_price_amount) == pytest.approx(22.0)
    assert float(row.units_available) == pytest.approx(5.0)
    assert row.is_available_flag is True
    missing_inventory = spark.sql("SELECT units_available, is_available_flag FROM candidate WHERE product_id = 'P3'").first()
    assert missing_inventory.units_available is None
    assert missing_inventory.is_available_flag is False


def test_performance_view_rolls_up_engagements_without_pii(spark):
    spark.createDataFrame(
        [(1, "DI1", 1, "CS1", 123, "C123", 9, "S1", "SESSION", "CONV", "web", "en-US", "US",
          "HASH", "need_based", 0.9, True, "granted", "2024-06-01 10:00:00", "2024-06-01")],
        "discovery_intent_event_sk int, discovery_intent_event_id string, conversation_session_sk int, "
        "conversation_session_id string, profile_sk int, profile_id string, store_sk int, store_id string, "
        "session_id string, conversation_id string, discovery_channel string, "
        "locale_code string, jurisdiction_code string, intent_text_hash string, intent_category string, "
        "intent_confidence_score double, personalization_eligible_flag boolean, consent_status string, "
        "event_ts string, event_date string",
    ).createOrReplaceTempView("discovery_intent_event")
    spark.createDataFrame(
        [(10, "DR1", 1, "DI1", 7, "P1", 9, "S1", 1, 0.8, 0.9, 0.5, 1.0,
          "semantic_match", True, 5.0, 12.0, "USD", "2024-06-01 10:00:01", "2024-06-01"),
         (11, "DR2", 1, "DI1", 8, "P2", 9, "S1", 2, 0.7, 0.8, 0.4, 1.0,
          "semantic_match", True, 3.0, 8.0, "USD", "2024-06-01 10:00:02", "2024-06-01")],
        "discovery_result_event_sk int, discovery_result_event_id string, discovery_intent_event_sk int, "
        "discovery_intent_event_id string, product_sk int, product_id string, store_sk int, store_id string, "
        "result_rank int, retrieval_score double, ranking_score double, personalization_score double, "
        "availability_score double, reason_code string, is_available_flag boolean, units_available double, "
        "list_price_amount double, currency_code string, event_ts string, event_date string",
    ).createOrReplaceTempView("discovery_result_event")
    spark.createDataFrame(
        [(100, "DE1", 10, "DR1", 1, "DI1", 123, "C123", 7, "P1", 9, "S1", None, None,
          None, "select", "2024-06-01 10:01:00", "2024-06-01", None, None, None, 1),
         (101, "DE2", 10, "DR1", 1, "DI1", 123, "C123", 7, "P1", 9, "S1", 501, "OL1",
          "O1", "purchase", "2024-06-01 10:05:00", "2024-06-01", 2, 24.0, "USD", 5),
         (102, "DE3", 11, "DR2", 1, "DI1", 123, "C123", 8, "P2", 9, "S1", 501, "OL1",
          "O1", "purchase", "2024-06-01 10:06:00", "2024-06-01", 2, 24.0, "USD", 6)],
        "discovery_engagement_event_sk int, discovery_engagement_event_id string, discovery_result_event_sk int, "
        "discovery_result_event_id string, discovery_intent_event_sk int, discovery_intent_event_id string, "
        "profile_sk int, profile_id string, product_sk int, product_id string, store_sk int, store_id string, "
        "order_line_sk int, order_line_id string, order_id string, engagement_type string, engagement_ts string, "
        "engagement_date string, quantity int, net_amount double, currency_code string, attribution_window_minutes int",
    ).createOrReplaceTempView("discovery_engagement_event")
    spark.createDataFrame(
        [(7, "P1", "Blue Shoe", "Acme", "footwear", "shoes", "apparel"),
         (8, "P2", "Blue Socks", "Acme", "footwear", "socks", "apparel")],
        "product_sk int, product_id string, product_name string, brand string, category string, subcategory string, department string",
    ).createOrReplaceTempView("product")
    body = _body(GOLD_PERFORMANCE, [
        ("${catalog}.${ac_schema}.discovery_engagement_event", "discovery_engagement_event"),
        ("${catalog}.${ac_schema}.discovery_result_event", "discovery_result_event"),
        ("${catalog}.${ac_schema}.discovery_intent_event", "discovery_intent_event"),
        ("${catalog}.${product_schema}.product", "product"),
    ])
    spark.sql("CREATE OR REPLACE TEMP VIEW performance AS " + body)
    outputs = set(spark.table("performance").columns)
    assert not (PII_COLUMNS & outputs)
    row = spark.sql("SELECT selected_flag, purchased_flag, engagement_count, purchased_units, purchase_net_amount "
                    "FROM performance WHERE discovery_result_event_id = 'DR1'").first()
    assert row.selected_flag is True
    assert row.purchased_flag is True
    assert row.engagement_count == 2
    assert row.purchased_units == 2
    assert float(row.purchase_net_amount) == pytest.approx(24.0)
    totals = spark.sql("SELECT SUM(purchased_units) AS units, SUM(purchase_net_amount) AS amount FROM performance").first()
    assert totals.units == 2
    assert float(totals.amount) == pytest.approx(24.0)


def test_conversational_session_view_rolls_up_turns_and_outcomes(spark):
    spark.createDataFrame(
        [(1, "CS1", 123, "C123", 9, "S1", "SESSION", "CONV", "web", "en-US", "US",
          "2024-06-01 10:00:00", "2024-06-01 10:08:00", "2024-06-01", "completed",
          "purchase", True, "granted")],
        "conversation_session_sk int, conversation_session_id string, profile_sk int, profile_id string, "
        "store_sk int, store_id string, session_id string, conversation_id string, entry_channel string, "
        "locale_code string, jurisdiction_code string, started_ts string, ended_ts string, started_date string, "
        "session_status string, resolution_type string, personalization_eligible_flag boolean, consent_status string",
    ).createOrReplaceTempView("conversation_session")
    spark.createDataFrame(
        [(10, "AT1", 1, "CS1", 1, "DI1", 1, "shopper", "intent_capture", "clarify_intent",
          "need_based", 0.9, False, False, "2024-06-01 10:01:00", "2024-06-01"),
         (11, "AT2", 1, "CS1", 1, "DI1", 2, "assistant", "recommendation", "recommend_products",
          "need_based", 0.9, False, False, "2024-06-01 10:02:00", "2024-06-01"),
         (12, "AT3", 1, "CS1", None, None, 3, "assistant", "fallback", "answer_question",
          None, None, True, False, "2024-06-01 10:03:00", "2024-06-01")],
        "assistant_turn_event_sk int, assistant_turn_event_id string, conversation_session_sk int, "
        "conversation_session_id string, discovery_intent_event_sk int, discovery_intent_event_id string, "
        "turn_sequence_number int, actor_type string, turn_type string, assistant_action_type string, "
        "intent_category string, intent_confidence_score double, is_fallback_flag boolean, is_handoff_flag boolean, "
        "event_ts string, event_date string",
    ).createOrReplaceTempView("assistant_turn_event")
    spark.createDataFrame(
        [(1, "DI1", 1, "CS1", 123, "C123", 9, "S1", "SESSION", None, "web", "en-US", "US",
          "HASH", "need_based", 0.9, True, "granted", "2024-06-01 10:01:00", "2024-06-01")],
        "discovery_intent_event_sk int, discovery_intent_event_id string, conversation_session_sk int, "
        "conversation_session_id string, profile_sk int, profile_id string, store_sk int, store_id string, "
        "session_id string, conversation_id string, discovery_channel string, "
        "locale_code string, jurisdiction_code string, intent_text_hash string, intent_category string, "
        "intent_confidence_score double, personalization_eligible_flag boolean, consent_status string, "
        "event_ts string, event_date string",
    ).createOrReplaceTempView("discovery_intent_event")
    spark.createDataFrame(
        [(100, "DE1", 10, "DR1", 1, "DI1", 123, "C123", 7, "P1", 9, "S1", None, None,
          None, "select", "2024-06-01 10:04:00", "2024-06-01", None, None, None, 3),
         (101, "DE2", 10, "DR1", 1, "DI1", 123, "C123", 7, "P1", 9, "S1", 501, "OL1",
          "O1", "purchase", "2024-06-01 10:06:00", "2024-06-01", 2, 24.0, "USD", 5),
         (102, "DE3", 10, "DR1", 1, "DI1", 123, "C123", 7, "P1", 9, "S1", 501, "OL1",
          "O1", "purchase", "2024-06-01 10:07:00", "2024-06-01", 2, 24.0, "USD", 6)],
        "discovery_engagement_event_sk int, discovery_engagement_event_id string, discovery_result_event_sk int, "
        "discovery_result_event_id string, discovery_intent_event_sk int, discovery_intent_event_id string, "
        "profile_sk int, profile_id string, product_sk int, product_id string, store_sk int, store_id string, "
        "order_line_sk int, order_line_id string, order_id string, engagement_type string, engagement_ts string, "
        "engagement_date string, quantity int, net_amount double, currency_code string, attribution_window_minutes int",
    ).createOrReplaceTempView("discovery_engagement_event")
    body = _body(GOLD_SESSION, [
        ("${catalog}.${ac_schema}.conversation_session", "conversation_session"),
        ("${catalog}.${ac_schema}.assistant_turn_event", "assistant_turn_event"),
        ("${catalog}.${ac_schema}.discovery_intent_event", "discovery_intent_event"),
        ("${catalog}.${ac_schema}.discovery_engagement_event", "discovery_engagement_event"),
    ])
    spark.sql("CREATE OR REPLACE TEMP VIEW conversation_session_gold AS " + body)
    outputs = set(spark.table("conversation_session_gold").columns)
    assert not (PII_COLUMNS & outputs)
    row = spark.sql("SELECT total_turns, fallback_turns, first_discovery_turn_number, "
                    "selected_flag, purchased_flag, purchased_units, purchase_net_amount "
                    "FROM conversation_session_gold").first()
    assert row.total_turns == 3
    assert row.fallback_turns == 1
    assert row.first_discovery_turn_number == 1
    assert row.selected_flag is True
    assert row.purchased_flag is True
    assert row.purchased_units == 2
    assert float(row.purchase_net_amount) == pytest.approx(24.0)


def test_conversational_performance_view_aggregates_session_metrics(spark):
    spark.createDataFrame(
        [("2024-06-01", "web", "need_based", "purchase", True, True, True, True, 3, 1, 2, 24.0, "USD"),
         ("2024-06-01", "web", "need_based", "no_resolution", False, False, False, False, 4, 0, 0, 0.0, None)],
        "started_date string, entry_channel string, primary_intent_category string, resolution_type string, "
        "known_customer_flag boolean, personalization_eligible_flag boolean, selected_flag boolean, "
        "purchased_flag boolean, total_turns int, fallback_turns int, purchased_units int, purchase_net_amount double, "
        "currency_code string",
    ).createOrReplaceTempView("gold_conversational_shopping_session")
    # Add columns the aggregate expects but this test does not assert directly.
    spark.sql("""
        CREATE OR REPLACE TEMP VIEW session_full AS
        SELECT *, false AS added_to_cart_flag, false AS handoff_flag,
               CAST(1 AS INT) AS first_discovery_turn_number
        FROM gold_conversational_shopping_session
    """)
    body = _body(GOLD_CONVERSATION_PERFORMANCE, [
        ("${catalog}.${ac_schema}.gold_conversational_shopping_session", "session_full"),
    ])
    spark.sql("CREATE OR REPLACE TEMP VIEW conversation_performance AS " + body)
    row = spark.sql("SELECT conversation_sessions, sessions_reaching_discovery, purchase_sessions, "
                    "assisted_conversion_rate, fallback_rate "
                    "FROM conversation_performance WHERE resolution_type='purchase'").first()
    assert row.conversation_sessions == 1
    assert row.sessions_reaching_discovery == 1
    assert row.purchase_sessions == 1
    assert float(row.assisted_conversion_rate) == pytest.approx(1.0)
    assert float(row.fallback_rate) == pytest.approx(1.0)
