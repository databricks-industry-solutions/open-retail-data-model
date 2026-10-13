"""Contracts and Spark semantics for Market Analysis competitive position.

The tests execute the real gold SELECT against fixtures and independently execute
the metric-view measure expressions. They also pin the two compliance walls:
no person-level inputs and no Market Analysis dependency in pricing surfaces.
"""

import datetime as dt
import glob
import os
import re

import pytest
import sqlglot

from tools.ddl_domain_closure import referenced_labels
from tools.ordm_ddl.parser import parse_relationships
from tools.ordm_config import (
    lineage_policy,
    policy_name_pattern,
    policy_object_values,
    policy_schema_literals,
    resolve,
    schema_defaults,
    single_schema_overrides,
    view_select_body,
)


REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PKG = os.path.join(REPO, "outcome-packages", "actionable-customer-understanding")
GOLD = os.path.join(PKG, "gold", "gold_competitive_position.sql")
METRIC = os.path.join(PKG, "metric-views", "competitive_position.sql")
CHECKS = os.path.join(PKG, "checks.sql")
RELATIONSHIPS = os.path.join(PKG, "relationships.sql")
README = os.path.join(PKG, "README.md")
SAMPLE_QUERIES = os.path.join(PKG, "sample-queries.sql")
ADR = os.path.join(
    REPO, "governance", "decisions",
    "0042-market-analysis-reads-bmv-competitor-foundation.md",
)

LINEAGE_POLICY = "market_analysis_no_pricing_lineage"
LICENSE_POLICY = "market_benchmark_no_redistribution"
MARKET_OBJECTS = set(lineage_policy(LINEAGE_POLICY)["protected_objects"])
ALLOWED_SOURCE_TOKENS = {
    "acu_schema", "bmv_schema", "product_schema", "transaction_schema", "calendar_schema",
    "marketing_schema", "promo_schema",
}
FORBIDDEN_PERSON_SOURCE_TOKENS = {
    "customer_schema", "interaction_schema", "ucv_schema", "cmn_schema"
}


def _dq_query(name):
    text = open(CHECKS, encoding="utf-8").read()
    header = re.search(
        rf"^-- check: {re.escape(name)} \| severity: (?:error|warn|metric)$",
        text,
        re.MULTILINE,
    )
    assert header, f"DQ check {name!r} is missing"
    body = []
    for line in text[header.end():].splitlines():
        if line.strip().startswith("--"):
            continue
        body.append(line)
        if ";" in line:
            break
    return "\n".join(body).strip().rstrip(";").strip()


def _gold_outputs():
    parsed = sqlglot.parse_one(
        resolve(view_select_body(open(GOLD, encoding="utf-8").read()), "c"),
        read="databricks",
        error_level="ignore",
    )
    return set(parsed.named_selects)


def _metric_expr(name):
    text = open(METRIC, encoding="utf-8").read()
    match = re.search(
        rf"^\s*- name: {re.escape(name)}\s*$\n\s+expr:\s*(.+)$",
        text,
        re.MULTILINE,
    )
    assert match, f"metric measure {name!r} is missing"
    return match.group(1).strip()


def _gold_body():
    body = view_select_body(open(GOLD, encoding="utf-8").read())
    substitutions = {
        "${catalog}.${transaction_schema}.sales": "sales",
        "${catalog}.${calendar_schema}.fiscal_calendar": "fiscal_calendar",
        "${catalog}.${bmv_schema}.competitor_price": "competitor_price",
        "${catalog}.${product_schema}.product": "product",
        "${catalog}.${bmv_schema}.competitor": "competitor",
        "${catalog}.${acu_schema}.competitor_promotion": "competitor_promotion",
        "${catalog}.${acu_schema}.competitor_assortment": "competitor_assortment",
        "${catalog}.${marketing_schema}.promotion": "promotion",
        "${catalog}.${promo_schema}.promotion_scope": "promotion_scope",
    }
    for source, target in substitutions.items():
        body = body.replace(source, target)
    return body


def _build_gold(spark):
    dates = [dt.date(2026, 1, d) for d in (1, 10, 20, 31)]
    spark.createDataFrame(
        [(d, 2026, 1) for d in dates],
        "date_key date, fiscal_year int, fiscal_period int",
    ).createOrReplaceTempView("fiscal_calendar")

    spark.createDataFrame(
        [
            (101, "P1", "snacks", 10.0, "USD", dates[0], None, "active"),
            (102, "P2", "snacks", 8.0, "USD", dates[0], None, "active"),
            (103, "P3", "snacks", 6.0, "USD", dates[0], None, "discontinued"),
        ],
        "product_sk long, product_id string, category string, list_price double, currency_code string, "
        "effective_from_date date, effective_to_date date, product_status string",
    ).createOrReplaceTempView("product")

    # Two stores for P1 on Jan 10 prove own sales are collapsed to one item-day
    # before the competitor join (5 units, one promoted store => promoted presence).
    spark.createDataFrame(
        [
            ("P1", dates[1], 2, "NO_PROMO"),
            ("P1", dates[1], 3, "PROMO-1"),
            ("P2", dates[1], 10, "NO_PROMO"),
            ("P1", dates[2], 4, "NO_PROMO"),
        ],
        "product_id string, date_key date, units int, promo_id string",
    ).createOrReplaceTempView("sales")

    # Own promotion presence comes from marketing.promotion plus the PWP scope,
    # not from competitor-promotion rows. P1 remains promoted on Jan 20 when no
    # competitor promotion exists, which proves SOV can exceed 50%.
    spark.createDataFrame(
        [
            (1, "PROMO-1", dates[1], dates[2]),
            (2, "PROMO-2", dates[1], dates[1]),
        ],
        "promo_sk long, promo_id string, start_date date, end_date date",
    ).createOrReplaceTempView("promotion")
    spark.createDataFrame(
        [(1, "P1"), (2, "P2")],
        "promo_sk long, product_id string",
    ).createOrReplaceTempView("promotion_scope")

    # competitor_sk changes inside the period; durable competitor_id must produce
    # one row. P2 has a positive observed price but zero MRP, so it remains in the
    # full observation population without entering the regular-price index.
    spark.createDataFrame(
        [
            (1, "C1", 101, "P1", dates[1], 5.0, 6.0, "USD", True, False),
            (1, "C1", 102, "P2", dates[1], 7.0, 0.0, "USD", False, True),
            (2, "C1", 101, "P1", dates[2], 4.0, 8.0, "USD", None, None),
        ],
        "competitor_sk long, competitor_id string, product_sk long, product_id string, "
        "date_key date, competitor_price double, competitor_mrp double, currency_code string, "
        "is_on_comp_promo boolean, is_out_of_stock boolean",
    ).createOrReplaceTempView("competitor_price")

    spark.createDataFrame(
        [
            ("PR-1", "snacks", "C1", "P1", "online", "circular_digital", 20.0,
             dt.date(2026, 1, 9), dates[1], dt.datetime(2026, 1, 10, 12), "USD"),
            ("PR-2", "snacks", "C1", "P2", "online", "onsite", 10.0,
             dates[1], dates[1], dt.datetime(2026, 1, 10, 12), "USD"),
            ("PR-3", "snacks", "C1", None, "online", "circular_print", None,
             None, dates[2], dt.datetime(2026, 1, 20, 12), "USD"),
        ],
        "competitor_promotion_id string, category_ref string, competitor_id string, "
        "product_id string, channel_code string, promo_vehicle string, "
        "discount_depth_pct double, promo_start_date date, date_key date, "
        "observed_at_ts timestamp, currency_code string",
    ).createOrReplaceTempView("competitor_promotion")

    spark.createDataFrame(
        [
            ("AS-1", "snacks", "C1", "I1", "P1", "exact", 0.95, "ALL", "online",
             dates[1], dt.datetime(2026, 1, 10, 12), True, True, 1),
            ("AS-2", "snacks", "C1", "I1", "P1", "exact", 0.95, "ALL", "online",
             dates[2], dt.datetime(2026, 1, 20, 12), True, False, 3),
            ("AS-3", "snacks", "C1", "I2", "P2", "similar", 0.95, "ALL", "online",
             dates[1], dt.datetime(2026, 1, 10, 12), True, True, 4),
            ("AS-4", "snacks", "C1", "U1", None, None, None, "ALL", "online",
             dates[1], dt.datetime(2026, 1, 10, 12), True, True, 5),
            ("AS-5", "snacks", "C1", "U1", None, None, None, "ALL", "online",
             dates[2], dt.datetime(2026, 1, 20, 12), False, False, None),
            ("AS-6", "snacks", "C1", "I3", "P3", "exact", 0.99, "ALL", "online",
             dates[1], dt.datetime(2026, 1, 10, 12), True, True, 6),
        ],
        "competitor_assortment_id string, category_ref string, competitor_id string, "
        "competitor_item_ref string, product_id string, match_type string, "
        "match_confidence double, competitor_location_ref string, channel_code string, "
        "date_key date, observed_at_ts timestamp, is_listed boolean, is_available boolean, "
        "search_rank int",
    ).createOrReplaceTempView("competitor_assortment")

    spark.createDataFrame(
        [
            (1, "C1", "Old Banner", dates[0], dt.date(2026, 1, 15)),
            (2, "C1", "New Banner", dt.date(2026, 1, 15), None),
        ],
        "competitor_sk long, competitor_id string, competitor_name string, "
        "effective_from_date date, effective_to_date date",
    ).createOrReplaceTempView("competitor")

    spark.sql("CREATE OR REPLACE TEMP VIEW gold_competitive_position AS " + _gold_body())


# ---------- static contract ----------


def test_gold_contract_has_observation_native_rollup_components():
    required = {
        "category", "competitor_id", "competitor_name", "channel_code",
        "fiscal_year", "fiscal_period", "currency_code", "measure_scope",
        "price_ratio_sum", "valid_price_observation_count", "valid_price_product_count",
        "observed_price_product_count", "matched_units",
        "own_promo_presence_count", "competitor_promo_presence_count",
        "comparable_promo_observation_count", "comparable_promo_day_count",
        "available_observation_count", "out_of_stock_observation_count",
        "stock_flagged_observation_count", "competitor_observation_count",
        "competitor_promotion_observation_count", "discount_depth_pct_sum",
        "valid_discount_depth_count", "assortment_observation_count",
        "listed_observation_count", "points_of_availability_count", "listed_channel_count",
        "competitor_listed_item_count", "matched_listed_product_count",
        "matched_listed_inactive_product_count", "observed_own_product_count",
        "matched_listed_competitor_item_count", "unmatched_listed_item_count",
        "unmatched_listed_item_present_flag",
        "own_catalog_product_count", "own_catalog_observation_coverage_pct",
        "search_rank_sum", "search_rank_observation_count",
        "detection_lag_days_sum", "detection_lag_observation_count",
        "observation_interval_days_sum", "observation_interval_count",
        "price_index_basis", "price_coverage_basis", "promo_sov_basis",
        "distribution_basis", "availability_basis", "assortment_basis",
        "detection_basis", "channel_basis",
    }
    outputs = _gold_outputs()
    assert required <= outputs, f"missing gold outputs: {sorted(required - outputs)}"
    text = open(GOLD, encoding="utf-8").read()
    assert "LEAST(" not in text.upper(), "coverage must not be hidden by a 100% cap"
    assert "market_share" not in text.lower(), "market share belongs in its separate grain"
    assert not re.search(r"CAST\s*\(\s*NULL\s+AS", text, re.IGNORECASE)


def test_cross_package_competitor_relationships_are_durable_key_logical_links():
    relationships = open(RELATIONSHIPS, encoding="utf-8").read()
    parsed = parse_relationships(relationships)
    assert "${bmv_schema}.competitor" not in relationships
    assert relationships.count("FOREIGN KEY (product_sk)") == 3
    for table in (
        "competitor_promotion", "competitor_assortment",
        "competitor_product_match", "market_benchmark",
    ):
        assert not any(
            fk["parent"] == "competitor"
            for fk in parsed["fks"].get(table, [])
        )

    checks = open(CHECKS, encoding="utf-8").read()
    assert checks.count("competitor_logical_fk_orphan") == 4
    for check_name in (
        "competitor_promotion_competitor_logical_fk_orphan",
        "competitor_assortment_competitor_logical_fk_orphan",
        "competitor_product_match_competitor_logical_fk_orphan",
        "market_benchmark_competitor_logical_fk_orphan",
    ):
        query = _dq_query(check_name)
        assert "NOT EXISTS" in query
        assert "is_current" not in query


def test_measure_scope_lists_only_reachable_channel_grain_combinations():
    gold = open(GOLD, encoding="utf-8").read()
    metadata = "\n".join(
        open(path, encoding="utf-8").read()
        for path in (METRIC, os.path.join(PKG, "comments.sql"), README,
                     os.path.join(PKG, "glossary.md"))
    )
    for dead_scope in ("price_promotion", "price_assortment", "price_promotion_assortment"):
        assert dead_scope not in gold
        assert dead_scope not in metadata
    for reachable_scope in ("price", "promotion", "assortment", "promotion_assortment"):
        assert reachable_scope in metadata


def test_market_benchmark_subject_has_one_odcs_validity_domain():
    checks = parse_relationships(open(RELATIONSHIPS, encoding="utf-8").read())["checks"]
    subject_checks = [check for check in checks["market_benchmark"] if check["col"] == "subject_type"]
    assert len(subject_checks) == 1
    assert set(subject_checks[0]["values"]) == {
        "own_banner", "competitor_banner", "brand", "private_label", "total_category",
    }


def test_cross_package_and_benchmark_identity_decisions_are_documented():
    adr = open(ADR, encoding="utf-8").read()
    readme = open(README, encoding="utf-8").read()
    assert "promotion_scope" in adr and "deploys after the bridge" in adr
    assert "promotion_scope` (Promote with Purpose)" in readme
    assert "category remap therefore creates a new logical cell" in adr
    assert "category remap intentionally creates a new logical cell" in readme


def test_match_registry_is_provenance_only_and_drift_checked():
    relationships = open(RELATIONSHIPS, encoding="utf-8").read()
    checks = open(CHECKS, encoding="utf-8").read()
    readme = open(README, encoding="utf-8").read()
    assert "logical provenance link" in relationships
    assert "competitor_product_match_snapshot_drift" in checks
    assert "v1 serving uses point-in-time observation snapshots" in readme


def test_scd2_aggregation_uses_durable_identities():
    text = open(GOLD, encoding="utf-8").read()
    for clause in re.findall(
        r"(?:GROUP\s+BY|PARTITION\s+BY)(.*?)(?=\bORDER\s+BY\b|\bHAVING\b|\)|$)",
        text,
        re.IGNORECASE | re.DOTALL,
    ):
        assert "competitor_sk" not in clause.lower()
        assert "product_sk" not in clause.lower()
    assert "cp.product_sk = p.product_sk" in text
    assert "a.competitor_id = c.competitor_id" in text


def test_market_analysis_has_no_person_level_sources():
    text = "\n".join(
        open(path, encoding="utf-8").read() for path in (GOLD, METRIC)
    )
    tokens = set(re.findall(r"\$\{(\w+_schema)\}", text))
    assert tokens <= ALLOWED_SOURCE_TOKENS
    assert not (tokens & FORBIDDEN_PERSON_SOURCE_TOKENS)
    assert "gold_competitor_analysis" not in text, "MA must preserve every competitor from BMV silver"


def test_dependency_closure_includes_market_analysis_inputs():
    direct = referenced_labels("actionable-customer-understanding")
    assert {
        "balancing-margin-and-volume", "product", "transaction", "calendar",
        "marketing", "promote-with-purpose",
    } <= direct


def test_pricing_surfaces_do_not_read_market_analysis():
    paths = glob.glob(os.path.join(REPO, "outcome-packages", "*", "gold", "*.sql"))
    paths += glob.glob(os.path.join(REPO, "outcome-packages", "*", "metric-views", "*.sql"))
    paths += glob.glob(os.path.join(REPO, "canonical-core", "**", "*.sql"), recursive=True)
    for path in paths:
        # ACU defines and consumes its own Market Analysis objects. Every other
        # committed serving surface is the auto-extending static backstop.
        if os.path.commonpath((PKG, path)) == PKG:
            continue
        text = open(path, encoding="utf-8").read().lower()
        references = {
            name for name in MARKET_OBJECTS
            if re.search(rf"\b{re.escape(name)}\b", text)
        }
        assert not references, path


def test_lineage_registry_drives_the_deployed_schema_scan():
    policy = lineage_policy(LINEAGE_POLICY)
    defaults = schema_defaults()
    scopes = policy["price_producing_scopes"]
    assert scopes, "price-producing registry must not be empty"
    for scope in scopes:
        assert scope["schema_token"] in defaults
        assert os.path.isdir(os.path.join(REPO, scope["path"]))

    registered_paths = {scope["path"] for scope in scopes}
    assert {
        "outcome-packages/promote-with-purpose",
        "outcome-packages/connected-store-signals",
    } <= registered_paths

    non_pricing_name_matches = {
        "outcome-packages/predictive-operations/metric-views/maintenance_cost.sql",
    }
    serving_paths = glob.glob(os.path.join(REPO, "outcome-packages", "*", "gold", "*.sql"))
    serving_paths += glob.glob(
        os.path.join(REPO, "outcome-packages", "*", "metric-views", "*.sql")
    )
    name_pattern = re.compile(policy_name_pattern(LINEAGE_POLICY))
    for path in serving_paths:
        rel = os.path.relpath(path, REPO)
        if os.path.commonpath((PKG, path)) == PKG or rel in non_pricing_name_matches:
            continue
        if name_pattern.search(os.path.basename(path).lower()):
            owner_path = "/".join(rel.split(os.sep)[:2])
            assert owner_path in registered_paths, rel

    expected_literals = policy_schema_literals(LINEAGE_POLICY, defaults)
    resolved = resolve(open(CHECKS, encoding="utf-8").read(), "c")
    assert expected_literals in resolved
    assert policy_object_values(LINEAGE_POLICY) in resolved
    assert policy_name_pattern(LINEAGE_POLICY) in resolved
    assert "${market_analysis_price_producing_schema_literals}" not in resolved
    assert "${market_analysis_protected_object_values}" not in resolved
    assert "${market_analysis_price_producing_name_pattern}" not in resolved

    collapsed = single_schema_overrides("pr_135")
    assert policy_schema_literals(LINEAGE_POLICY, collapsed) == "'pr_135'"
    assert "IN ('pr_135')" in resolve(
        open(CHECKS, encoding="utf-8").read(), "c", collapsed
    )


def test_licensed_benchmark_registry_blocks_sharing_surfaces():
    policy = lineage_policy(LICENSE_POLICY)
    scopes = policy[policy["schema_scopes_key"]]
    assert {scope["path"] for scope in scopes} == {
        "outcome-packages/data-sharing-with-suppliers"
    }
    protected = set(policy["protected_objects"])
    for root, _, files in os.walk(os.path.join(REPO, scopes[0]["path"])):
        for filename in files:
            if not filename.endswith(".sql"):
                continue
            text = open(os.path.join(root, filename), encoding="utf-8").read().lower()
            assert not any(re.search(rf"\b{re.escape(name)}\b", text) for name in protected)

    resolved = resolve(open(CHECKS, encoding="utf-8").read(), "c")
    assert policy_schema_literals(LICENSE_POLICY) in resolved
    assert policy_object_values(LICENSE_POLICY) in resolved
    assert "${market_benchmark_sharing_schema_literals}" not in resolved
    assert "${market_benchmark_licensed_object_values}" not in resolved


def test_compliance_checks_are_present_and_scoped():
    text = open(CHECKS, encoding="utf-8").read()
    assert "market_analysis_no_person_level_columns" in text
    assert "market_analysis_no_pricing_lineage" in text
    assert "market_benchmark_no_redistribution_lineage" in text
    assert "VALUES ${market_analysis_protected_object_values}" in text
    assert "regexp_like(lower(v.table_name), '${market_analysis_price_producing_name_pattern}')" in text
    for object_name in MARKET_OBJECTS:
        assert object_name in policy_object_values(LINEAGE_POLICY)


def test_market_analysis_sample_query_has_no_constant_basis_filter():
    text = open(SAMPLE_QUERIES, encoding="utf-8").read()
    assert "price_index_basis = 'own_list_price_vs_competitor_mrp'" not in text


def test_metric_ratios_are_ratio_of_sums():
    for name in (
        "price_index_vs_competitor",
        "sales_weighted_price_index_vs_competitor",
        "price_observation_coverage_pct",
        "promo_sov_pct",
        "avg_discount_depth_pct",
        "listed_share_pct",
        "availability_rate_pct",
        "assortment_overlap_pct",
        "assortment_uniqueness_pct",
        "assortment_jaccard_index_pct",
        "match_coverage_pct",
        "share_of_search_avg_rank",
        "avg_detection_lag_upper_bound_days",
        "avg_promotion_detection_lag_days",
        "avg_assortment_detection_lag_days",
        "avg_observation_cadence_days",
    ):
        expr = _metric_expr(name).upper()
        assert "SUM(" in expr and "NULLIF(" in expr
        assert "AVG(" not in expr


def test_own_catalog_count_is_non_additive_and_coverage_stays_at_gold_grain():
    expr = _metric_expr("own_catalog_product_count").upper()
    assert "MAX(" in expr
    assert "SUM(" not in expr

    metric_text = open(METRIC, encoding="utf-8").read()
    assert not re.search(
        r"^\s*- name: own_catalog_observation_coverage_pct\s*$",
        metric_text,
        re.MULTILINE,
    )
    assert "own_catalog_observation_coverage_pct" in _gold_outputs()


# ---------- Spark semantics: execute the real gold SQL ----------


def test_banner_share_sum_combines_only_mutually_exclusive_banner_lens(spark):
    schema = (
        "record_source string, market_definition string, geography_level string, "
        "geography_code string, category_ref string, subject_type string, "
        "period_type string, period_end_date date, "
        "provider_reported_market_share_pct double"
    )
    period_end = dt.date(2026, 1, 31)
    spark.createDataFrame(
        [
            ("provider", "market", "total", "US", "snacks", "own_banner", "month", period_end, 55.0),
            ("provider", "market", "total", "US", "snacks", "competitor_banner", "month", period_end, 30.0),
            ("provider", "market", "total", "US", "snacks", "competitor_banner", "month", period_end, 20.0),
            ("provider", "market", "total", "US", "snacks", "brand", "month", period_end, 80.0),
            ("provider", "market", "total", "US", "snacks", "private_label", "month", period_end, 40.0),
            ("provider", "market", "total", "US", "drinks", "own_banner", "month", period_end, 45.0),
            ("provider", "market", "total", "US", "drinks", "competitor_banner", "month", period_end, 50.0),
            ("provider", "market", "total", "US", "drinks", "brand", "month", period_end, 75.0),
            ("provider", "market", "total", "US", "drinks", "private_label", "month", period_end, 35.0),
        ],
        schema,
    ).createOrReplaceTempView("gold_market_share")

    def resolved_check(name):
        return _dq_query(name).replace(
            "${catalog}.${acu_schema}.gold_market_share",
            "gold_market_share",
        )

    assert spark.sql(resolved_check("market_benchmark_share_sum")).count() == 0
    violations = spark.sql(
        resolved_check("market_share_banner_set_share_sum")
    ).collect()
    assert len(violations) == 1
    assert violations[0].category_ref == "snacks"
    assert violations[0].measured_banner_share_pct == pytest.approx(105.0)


def test_count_consistency_accepts_sparse_multi_channel_period_count(spark):
    base = {
        "valid_price_product_count": 0,
        "observed_price_product_count": 0,
        "valid_price_observation_count": 0,
        "competitor_observation_count": 0,
        "own_promo_presence_count": 0,
        "competitor_promo_presence_count": 0,
        "comparable_promo_observation_count": 0,
        "comparable_promo_day_count": 0,
        "valid_discount_depth_count": 0,
        "competitor_promotion_observation_count": 0,
        "circular_print_promo_count": 0,
        "circular_digital_promo_count": 0,
        "onsite_promo_count": 0,
        "in_store_promo_count": 0,
        "email_app_promo_count": 0,
        "other_promo_count": 0,
        "assortment_observation_count": 1,
        "listed_observation_count": 1,
        "stock_flagged_observation_count": 1,
        "available_observation_count": 1,
        "out_of_stock_observation_count": 0,
        "points_of_availability_count": 1,
        "listed_channel_count": 3,
        "competitor_listed_item_count": 1,
        "matched_listed_competitor_item_count": 0,
        "unmatched_listed_item_count": 0,
        "observed_own_product_count": 0,
        "own_catalog_product_count": 0,
        "matched_listed_product_count": 0,
        "matched_listed_inactive_product_count": 0,
        "search_rank_observation_count": 0,
        "detection_lag_observation_count": 0,
        "promotion_detection_observation_count": 0,
        "assortment_detection_observation_count": 0,
        "assortment_state_change_count": 0,
        "observation_interval_count": 0,
    }
    rows = [
        dict(base, channel_code=channel)
        for channel in ("online", "store", "marketplace")
    ]
    spark.createDataFrame(rows).createOrReplaceTempView("gold_competitive_position")

    assert spark.sql(
        "SELECT * FROM gold_competitive_position "
        "WHERE listed_channel_count > listed_observation_count"
    ).count() == 3
    query = _dq_query("market_analysis_count_consistency").replace(
        "${catalog}.${acu_schema}.gold_competitive_position",
        "gold_competitive_position",
    )
    assert spark.sql(query).count() == 0


def test_person_level_check_exempts_only_email_app_promo_counter(spark):
    schema = "table_schema string, table_name string, column_name string"
    spark.createDataFrame(
        [
            (
                "actionable_customer_understanding",
                "gold_competitive_position",
                "email_app_promo_count",
            ),
            (
                "actionable_customer_understanding",
                "mv_competitive_position",
                "email_app_promo_count",
            ),
            (
                "actionable_customer_understanding",
                "gold_market_share",
                "customer_email",
            ),
            (
                "actionable_customer_understanding",
                "gold_market_share",
                "email_address",
            ),
            (
                "actionable_customer_understanding",
                "mv_market_share",
                "billing_email",
            ),
        ],
        schema,
    ).createOrReplaceTempView("market_analysis_columns")
    query = _dq_query("market_analysis_no_person_level_columns")
    query = query.replace(
        "${catalog}.information_schema.columns",
        "market_analysis_columns",
    )
    query = query.replace("'${acu_schema}'", "'actionable_customer_understanding'")
    flagged = {
        (row.column_name, row.table_name)
        for row in spark.sql(query).collect()
    }
    assert flagged == {
        ("customer_email", "gold_market_share"),
        ("email_address", "gold_market_share"),
        ("billing_email", "mv_market_share"),
    }


def test_gold_uses_durable_competitor_and_period_appropriate_name(spark):
    _build_gold(spark)
    rows = spark.sql("SELECT * FROM gold_competitive_position").collect()
    assert len(rows) == 2
    assert {row.channel_code for row in rows} == {"all", "online"}
    assert {row.competitor_id for row in rows} == {"C1"}
    assert {row.competitor_name for row in rows} == {"New Banner"}
    assert {row.category for row in rows} == {"snacks"}
    assert {row.measure_scope for row in rows} == {"price", "promotion_assortment"}


def test_price_pairs_coverage_and_weighting(spark):
    _build_gold(spark)
    row = spark.sql("SELECT * FROM gold_competitive_position WHERE channel_code = 'all'").first()
    assert row.competitor_observation_count == 3
    assert row.valid_price_observation_count == 2
    assert row.valid_price_product_count == 1
    assert row.observed_price_product_count == 2
    assert row.price_observation_coverage_pct == pytest.approx(50.0)
    assert row.price_index_vs_competitor == pytest.approx(1750.0 / 12.0)
    assert row.matched_units == pytest.approx(9.0)
    assert row.sales_weighted_price_index_vs_competitor == pytest.approx(4000.0 / 27.0)
    assert row.currency_code == "USD"
    assert row.price_index_basis == "own_list_price_vs_competitor_mrp"
    assert row.assortment_overlap_pct is None
    assert row.assortment_uniqueness_pct is None


def test_observation_native_promotion_assortment_and_detection_bounds(spark):
    _build_gold(spark)
    row = spark.sql("SELECT * FROM gold_competitive_position WHERE channel_code = 'online'").first()
    assert row.own_promo_presence_count == 3
    assert row.competitor_promo_presence_count == 2
    assert row.comparable_promo_observation_count == 4
    assert row.comparable_promo_day_count == 2
    assert row.competitor_promotion_observation_count == 3
    assert row.promo_sov_pct == pytest.approx(60.0)
    assert row.promo_sov_pct > 50.0  # regression: competitor-row conditioning capped SOV at 50%
    assert row.avg_discount_depth_pct == pytest.approx(15.0)
    assert row.assortment_observation_count == 6
    assert row.listed_observation_count == 5
    assert row.available_observation_count == 4
    assert row.out_of_stock_observation_count == 1
    assert row.stock_flagged_observation_count == 5
    assert row.listed_share_pct == pytest.approx(500.0 / 6.0)
    assert row.availability_rate_pct == pytest.approx(80.0)
    assert row.points_of_availability_count == 1
    assert row.listed_channel_count == 1
    assert row.competitor_listed_item_count == 4
    assert row.matched_listed_product_count == 1
    assert row.matched_listed_inactive_product_count == 1
    assert row.observed_own_product_count == 2
    assert row.unmatched_listed_item_count == 2
    assert row.own_catalog_product_count == 2
    assert row.own_catalog_observation_coverage_pct == pytest.approx(100.0)
    assert row.assortment_overlap_pct == pytest.approx(50.0)
    assert row.assortment_uniqueness_pct == pytest.approx(50.0)
    assert row.assortment_jaccard_index_pct == pytest.approx(25.0)
    assert row.match_coverage_pct == pytest.approx(50.0)
    assert row.unmatched_listed_item_present_flag is True
    assert row.assortment_state_change_count == 2
    assert row.assortment_detection_observation_count == 2
    assert row.observation_interval_count == 2
    assert row.avg_observation_cadence_days == pytest.approx(10.0)
    assert row.avg_promotion_detection_lag_days == pytest.approx(
        row.promotion_detection_lag_days_sum / row.promotion_detection_observation_count
    )
    assert row.avg_assortment_detection_lag_days == pytest.approx(10.0)
    assert "upper_bound" in row.detection_basis


def test_metric_rollups_execute_as_ratio_of_sums(spark):
    rows = [
        (2.0, 1, 4.0, 2.0, 1, 2, 1, 1, 30.0, 2, 1, 2, 1, 2,
         1, 3, 2, 1, 2, 2, 3.0, 1, 2.0, 1, 1.0, 1, 1.0, 1, 4.0, 2),
        (9.0, 3, 18.0, 6.0, 9, 18, 9, 0, 70.0, 8, 9, 18, 9, 18,
         9, 27, 18, 9, 18, 18, 27.0, 9, 18.0, 9, 9.0, 9, 9.0, 9, 36.0, 8),
    ]
    schema = (
        "price_ratio_sum double, valid_price_observation_count long, "
        "sales_weighted_price_ratio_sum double, matched_units double, "
        "valid_price_product_count long, observed_price_product_count long, "
        "own_promo_presence_count long, competitor_promo_presence_count long, "
        "discount_depth_pct_sum double, valid_discount_depth_count long, "
        "listed_observation_count long, assortment_observation_count long, "
        "available_observation_count long, stock_flagged_observation_count long, "
        "matched_listed_product_count long, competitor_listed_item_count long, "
        "unmatched_listed_item_count long, matched_listed_competitor_item_count long, "
        "observed_own_product_count long, own_catalog_product_count long, "
        "search_rank_sum double, search_rank_observation_count long, "
        "detection_lag_days_sum double, detection_lag_observation_count long, "
        "promotion_detection_lag_days_sum double, promotion_detection_observation_count long, "
        "assortment_detection_lag_days_sum double, assortment_detection_observation_count long, "
        "observation_interval_days_sum double, observation_interval_count long"
    )
    spark.createDataFrame(rows, schema).createOrReplaceTempView("metric_rollup_fixture")

    expected = {
        "price_index_vs_competitor": 275.0,
        "sales_weighted_price_index_vs_competitor": 275.0,
        "price_observation_coverage_pct": 50.0,
        "promo_sov_pct": 1000.0 / 11.0,
        "avg_discount_depth_pct": 10.0,
        "listed_share_pct": 50.0,
        "availability_rate_pct": 50.0,
        "assortment_overlap_pct": 50.0,
        "assortment_uniqueness_pct": 50.0,
        "assortment_jaccard_index_pct": 25.0,
        "match_coverage_pct": 100.0 / 3.0,
        "share_of_search_avg_rank": 3.0,
        "avg_detection_lag_upper_bound_days": 2.0,
        "avg_promotion_detection_lag_days": 1.0,
        "avg_assortment_detection_lag_days": 1.0,
        "avg_observation_cadence_days": 4.0,
    }
    for name, value in expected.items():
        actual = spark.sql(
            f"SELECT {_metric_expr(name)} AS value FROM metric_rollup_fixture"
        ).first().value
        assert float(actual) == pytest.approx(value)
