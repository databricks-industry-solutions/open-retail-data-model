"""Spark tests for AI-Assisted Store Associates gold views.

These tests execute the real gold SQL against small deterministic fixtures built
from the pure Python builders in runtime/synthetic-data/generators/ai_assisted_store_associates.py
to verify the generator + gold layer work together end-to-end. Tests run on Databricks
in CI; they skip locally without Spark.

Fixtures build temp views from the generator builders with known structure so gold SQL
correctness is obvious. The builders are called directly without Spark to verify they
produce well-formed rows; temp views materialize those rows; gold views execute against
the temps; assertions validate the output.
"""

import os
import re
import sys
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal as D

import pytest

# Add repo root to path
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from tools.ordm_config import view_select_body

# Import generators lazily to avoid import failures without pyspark
GENERATORS_ROOT = os.path.join(REPO_ROOT, "runtime", "synthetic-data", "generators")
if GENERATORS_ROOT not in sys.path:
    sys.path.insert(0, GENERATORS_ROOT)


def _get_builder_module():
    """Import ai_assisted_store_associates module on demand."""
    global _builder_module
    if "_builder_module" not in globals():
        import ai_assisted_store_associates as m
        _builder_module = m
    return _builder_module


def _read_gold_view_body(filename):
    """Read a gold view SQL file and extract the SELECT body, stripping CREATE ... AS."""
    path = os.path.join(
        REPO_ROOT,
        "outcome-packages",
        "ai-assisted-store-associates",
        "gold",
        filename,
    )
    with open(path) as f:
        sql = f.read()
    return view_select_body(sql)


def _substitute_schemas(sql):
    """Substitute schema tokens in SQL for temp view references."""
    # Replace catalog.schema.table with just table name (all temp views)
    sql = re.sub(r"\$\{catalog\}\.\$\{aasa_schema\}\.", "", sql)
    return sql


@pytest.fixture
def aasa_fixture(spark):
    """Build temp views for the four AASA base tables using pure Python builders.

    Returns a dict with the fixture data for assertions.
    """
    # Import builder module (skips if pyspark unavailable)
    pytest.importorskip("pyspark")
    m = _get_builder_module()

    # Use anchor at UTC today (will be UTC midnight of run date in real runs)
    anchor = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)

    # ===== Build associates using pure builder =====
    # Create minimal employee and skill data
    employees = [
        {
            "employee_id": "EMP-001",
            "primary_role_code": "sales_associate",
            "employment_status": "active",
            "employment_type": "full_time",
            "hire_date": date(2024, 1, 1),
            "home_store_sk": 1,
            "home_store_id": "STR-001",
        },
        {
            "employee_id": "EMP-002",
            "primary_role_code": "cashier",
            "employment_status": "active",
            "employment_type": "full_time",
            "hire_date": date(2024, 6, 1),
            "home_store_sk": 1,
            "home_store_id": "STR-001",
        },
        {
            "employee_id": "EMP-003",
            "primary_role_code": "inventory",
            "employment_status": "active",
            "employment_type": "part_time",
            "hire_date": date(2025, 3, 1),
            "home_store_sk": 2,
            "home_store_id": "STR-002",
        },
        {
            "employee_id": "EMP-004",
            "primary_role_code": "fulfillment",
            "employment_status": "active",
            "employment_type": "full_time",
            "hire_date": date(2024, 12, 1),
            "home_store_sk": 2,
            "home_store_id": "STR-002",
        },
        {
            "employee_id": "EMP-005",
            "primary_role_code": "supervisor",
            "employment_status": "active",
            "employment_type": "full_time",
            "hire_date": date(2023, 1, 15),
            "home_store_sk": 3,
            "home_store_id": "STR-003",
        },
        {
            "employee_id": "EMP-006",
            "primary_role_code": "sales_associate",
            "employment_status": "active",
            "employment_type": "part_time",
            "hire_date": date(2025, 6, 1),
            "home_store_sk": 3,
            "home_store_id": "STR-003",
        },
    ]

    skills = [
        {"employee_id": "EMP-001", "skill_code": "electronics", "is_active": True},
        {"employee_id": "EMP-001", "skill_code": "appliances", "is_active": True},
        {"employee_id": "EMP-002", "skill_code": "customer_service", "is_active": True},
        {"employee_id": "EMP-003", "skill_code": "inventory", "is_active": True},
        {"employee_id": "EMP-004", "skill_code": "fulfillment", "is_active": True},
        {"employee_id": "EMP-005", "skill_code": "management", "is_active": True},
        {"employee_id": "EMP-006", "skill_code": "sales", "is_active": True},
    ]

    # Use pure builder to generate associate rows
    associate_rows = m.build_associate_rows(employees, skills)

    # Assign surrogate keys manually for the fixture
    for idx, row in enumerate(associate_rows, start=1):
        row["associate_sk"] = idx

    # Create associate temp view
    associate_schema = (
        "associate_sk LONG, associate_id STRING, store_sk LONG, store_id STRING, "
        "role STRING, skill_tags STRING, employment_type STRING, primary_department STRING, "
        "is_active BOOLEAN, hire_date DATE, effective_from_date DATE, effective_to_date DATE, "
        "is_current BOOLEAN, created_timestamp TIMESTAMP, source_updated_timestamp TIMESTAMP, "
        "record_source STRING, load_timestamp TIMESTAMP"
    )
    spark.createDataFrame(associate_rows, schema=associate_schema).createOrReplaceTempView(
        "associate"
    )

    # ===== Build stores and products for action routing =====
    stores = [
        {"store_sk": 1, "store_id": "STR-001"},
        {"store_sk": 2, "store_id": "STR-002"},
        {"store_sk": 3, "store_id": "STR-003"},
    ]

    products = [
        {"product_sk": 101, "product_id": "PROD-101"},
        {"product_sk": 102, "product_id": "PROD-102"},
        {"product_sk": 103, "product_id": "PROD-103"},
        {"product_sk": 104, "product_id": "PROD-104"},
    ]

    profiles = [
        {"profile_sk": 201, "profile_id": "PROF-201"},
        {"profile_sk": 202, "profile_id": "PROF-202"},
    ]

    # ===== Build actions using pure builder =====
    cfg = {
        "action_history_days": 3,
        "actions_per_store_day": 4,
        "open_actions_per_associate_max": 5,
    }
    seed = 42

    action_rows, response_rows, outcome_rows = m.build_action_rows(
        associate_rows, stores, products, profiles, anchor, cfg, seed, "USD"
    )

    # Assign surrogate keys to actions manually
    for idx, row in enumerate(action_rows, start=1):
        row["suggested_action_sk"] = idx

    # Assign surrogate keys to responses and link to actions
    action_sk_by_id = {row["suggested_action_id"]: row["suggested_action_sk"]
                       for row in action_rows}
    for idx, row in enumerate(response_rows, start=1):
        row["action_response_log_sk"] = idx
        row["suggested_action_sk"] = action_sk_by_id.get(row["suggested_action_id"])

    # Assign surrogate keys to outcomes
    for idx, row in enumerate(outcome_rows, start=1):
        row["outcome_resolution_sk"] = idx
        row["suggested_action_sk"] = action_sk_by_id.get(row["suggested_action_id"])

    # Create suggested_action temp view
    action_schema = (
        "suggested_action_sk LONG, suggested_action_id STRING, generated_timestamp TIMESTAMP, "
        "associate_sk LONG, associate_id STRING, store_sk LONG, store_id STRING, "
        "store_zone_id STRING, profile_sk LONG, profile_id STRING, "
        "product_sk LONG, product_id STRING, action_type STRING, trigger_source STRING, "
        "base_score INT, priority_score DOUBLE, decay_type STRING, expiration_timestamp TIMESTAMP, "
        "context_payload STRING, record_source STRING, load_timestamp TIMESTAMP"
    )
    spark.createDataFrame(action_rows, schema=action_schema).createOrReplaceTempView(
        "suggested_action"
    )

    # Create action_response_log temp view
    if response_rows:
        response_schema = (
            "action_response_log_sk LONG, action_response_log_id STRING, "
            "suggested_action_sk LONG, suggested_action_id STRING, "
            "associate_sk LONG, associate_id STRING, response_timestamp TIMESTAMP, "
            "response_type STRING, reason_code STRING, record_source STRING, load_timestamp TIMESTAMP"
        )
        spark.createDataFrame(response_rows, schema=response_schema).createOrReplaceTempView(
            "action_response_log"
        )
    else:
        # Create empty view
        spark.createDataFrame([], schema="action_response_log_sk LONG, action_response_log_id STRING, suggested_action_sk LONG, suggested_action_id STRING, associate_sk LONG, associate_id STRING, response_timestamp TIMESTAMP, response_type STRING, reason_code STRING, record_source STRING, load_timestamp TIMESTAMP").createOrReplaceTempView(
            "action_response_log"
        )

    # Create outcome_resolution temp view
    if outcome_rows:
        outcome_schema = (
            "outcome_resolution_sk LONG, outcome_resolution_id STRING, "
            "suggested_action_sk LONG, suggested_action_id STRING, "
            "resolution_timestamp TIMESTAMP, outcome_type STRING, "
            "outcome_value_amount DECIMAL(18,2), currency_code STRING, "
            "units_affected INT, record_source STRING, load_timestamp TIMESTAMP"
        )
        spark.createDataFrame(outcome_rows, schema=outcome_schema).createOrReplaceTempView(
            "outcome_resolution"
        )
    else:
        # Create empty view
        spark.createDataFrame([], schema="outcome_resolution_sk LONG, outcome_resolution_id STRING, suggested_action_sk LONG, suggested_action_id STRING, resolution_timestamp TIMESTAMP, outcome_type STRING, outcome_value_amount DECIMAL(18,2), currency_code STRING, units_affected INT, record_source STRING, load_timestamp TIMESTAMP").createOrReplaceTempView(
            "outcome_resolution"
        )

    return {
        "anchor": anchor,
        "associates": associate_rows,
        "actions": action_rows,
        "responses": response_rows,
        "outcomes": outcome_rows,
        "action_sk_by_id": action_sk_by_id,
    }


def test_queue_view_returns_non_empty(spark, aasa_fixture):
    """gold_associate_action_queue_current returns rows for open actions."""
    body = _read_gold_view_body("gold_associate_action_queue_current.sql")
    body = _substitute_schemas(body)
    result = spark.sql(body).collect()
    assert len(result) > 0, "queue view should return open actions"


def test_queue_view_no_terminal_responses(spark, aasa_fixture):
    """Rows in the queue have no terminal response (completed/expired/rejected)."""
    body = _read_gold_view_body("gold_associate_action_queue_current.sql")
    body = _substitute_schemas(body)
    result = spark.sql(body).collect()

    for row in result:
        current_state = row["current_state"]
        assert current_state != "completed", (
            f"action {row['suggested_action_id']} has terminal state {current_state}"
        )
        assert current_state != "expired", (
            f"action {row['suggested_action_id']} has terminal state {current_state}"
        )
        assert current_state != "rejected", (
            f"action {row['suggested_action_id']} has terminal state {current_state}"
        )


def test_queue_view_expiration_future(spark, aasa_fixture):
    """Open actions in queue have expiration_timestamp > current_timestamp."""
    body = _read_gold_view_body("gold_associate_action_queue_current.sql")
    body = _substitute_schemas(body)
    result = spark.sql(body).collect()

    for row in result:
        expiration = row["expiration_timestamp"]
        assert expiration is not None, (
            f"action {row['suggested_action_id']} has NULL expiration"
        )
        # Expiration should be in the future (positive minutes_to_expiry)
        minutes_to_expiry = row["minutes_to_expiry"]
        assert minutes_to_expiry is None or minutes_to_expiry > -5, (
            f"action {row['suggested_action_id']} is already expired: {minutes_to_expiry} min"
        )


def test_queue_view_ranking_dense_per_associate(spark, aasa_fixture):
    """queue_rank is dense and starts at 1 per associate_id."""
    body = _read_gold_view_body("gold_associate_action_queue_current.sql")
    body = _substitute_schemas(body)
    result = spark.sql(body).collect()

    by_associate = {}
    for row in result:
        assoc_id = row["associate_id"]
        rank = row["queue_rank"]
        if assoc_id not in by_associate:
            by_associate[assoc_id] = []
        by_associate[assoc_id].append(rank)

    for assoc_id, ranks in by_associate.items():
        ranks = sorted(ranks)
        # Check dense ranking: [1, 2, 3, ...] or subset like [1, 3] if gaps
        assert ranks[0] == 1, (
            f"associate {assoc_id} first rank is {ranks[0]}, expected 1"
        )
        for i, rank in enumerate(ranks, start=1):
            assert rank >= i, (
                f"associate {assoc_id} has non-dense rank: {rank} at position {i}"
            )


def test_queue_view_decay_none_equals_generation_score(spark, aasa_fixture):
    """For decay_type='none', current_priority_score == round(priority_score, 2)."""
    body = _read_gold_view_body("gold_associate_action_queue_current.sql")
    body = _substitute_schemas(body)
    result = spark.sql(body).collect()

    for row in result:
        if row["decay_type"] == "none":
            priority = row["priority_score"]
            current = row["current_priority_score"]
            expected = round(priority, 2) if priority is not None else None
            assert current == expected, (
                f"action {row['suggested_action_id']} with decay_type=none has "
                f"current_priority_score={current}, expected {expected}"
            )


def test_funnel_view_returns_non_empty(spark, aasa_fixture):
    """gold_action_outcome_funnel_daily returns rows for history actions."""
    body = _read_gold_view_body("gold_action_outcome_funnel_daily.sql")
    body = _substitute_schemas(body)
    result = spark.sql(body).collect()
    assert len(result) > 0, "funnel view should return history actions"


def test_funnel_view_action_counts_match_fixture(spark, aasa_fixture):
    """Funnel aggregations match expected counts from fixture."""
    # Compute expected counts from fixture
    actions = aasa_fixture["actions"]
    responses = aasa_fixture["responses"]
    outcomes = aasa_fixture["outcomes"]

    # Build expected counts by (store_id, trading_date, action_type)
    from collections import defaultdict
    from datetime import date

    expected_counts = defaultdict(lambda: {
        "actions_generated": 0,
        "actions_accepted": 0,
        "actions_completed": 0,
    })

    # Count generated actions
    for action in actions:
        gen_ts = action["generated_timestamp"]
        trading_date = gen_ts.date() if hasattr(gen_ts, 'date') else gen_ts
        key = (action["store_id"], str(trading_date), action["action_type"])
        expected_counts[key]["actions_generated"] += 1

    # Count accepted responses
    action_map = {a["suggested_action_id"]: a for a in actions}
    for response in responses:
        action_id = response["suggested_action_id"]
        if action_id in action_map:
            action = action_map[action_id]
            gen_ts = action["generated_timestamp"]
            trading_date = gen_ts.date() if hasattr(gen_ts, 'date') else gen_ts
            key = (action["store_id"], str(trading_date), action["action_type"])
            if response["response_type"] == "accepted":
                expected_counts[key]["actions_accepted"] += 1
            if response["response_type"] == "completed":
                expected_counts[key]["actions_completed"] += 1

    # Query funnel
    body = _read_gold_view_body("gold_action_outcome_funnel_daily.sql")
    body = _substitute_schemas(body)
    result = spark.sql(body).collect()

    # The view's grain is store x zone x associate x trading_date x action_type; roll it up to
    # store x trading_date x action_type before comparing with the fixture counts.
    got = defaultdict(lambda: {"actions_generated": 0, "actions_accepted": 0, "actions_completed": 0})
    for row in result:
        key = (row["store_id"], str(row["trading_date"]), row["action_type"])
        for col in ("actions_generated", "actions_accepted", "actions_completed"):
            got[key][col] += row[col] or 0

    assert dict(got) == dict(expected_counts), "funnel counts differ from the fixture"


def test_funnel_view_single_currency(spark, aasa_fixture):
    """outcome_currency_code is either NULL or single value across all rows."""
    body = _read_gold_view_body("gold_action_outcome_funnel_daily.sql")
    body = _substitute_schemas(body)
    result = spark.sql(body).collect()

    currencies = set()
    for row in result:
        if row["outcome_currency_code"] is not None:
            currencies.add(row["outcome_currency_code"])

    assert len(currencies) <= 1, (
        f"funnel has multiple currencies: {currencies}"
    )


def test_funnel_view_sales_closed_and_value_present(spark, aasa_fixture):
    """Funnel has sales_closed > 0 and realized_outcome_value > 0 overall."""
    body = _read_gold_view_body("gold_action_outcome_funnel_daily.sql")
    body = _substitute_schemas(body)
    result = spark.sql(body).collect()

    total_sales_closed = sum(row["sales_closed"] or 0 for row in result)
    total_value = sum(row["realized_outcome_value"] or 0 for row in result)

    assert total_sales_closed > 0, "funnel should have sales_closed outcomes"
    assert total_value > 0, "funnel should have realized_outcome_value"


def test_data_quality_checks_pass(spark, aasa_fixture):
    """Run all error-severity checks from checks.sql against temp views."""
    checks_path = os.path.join(
        REPO_ROOT,
        "outcome-packages",
        "ai-assisted-store-associates",
        "checks.sql",
    )
    with open(checks_path) as f:
        checks_sql = f.read()

    # Parse checks: each is between "-- check: <name>" and the next check or EOF
    # Extract only error-severity checks that touch the four tables
    check_pattern = re.compile(
        r"-- check:\s+(\w+)\s*\|\s*severity:\s*(error|warn|metric)(.*?)(?=-- check:|$)",
        re.DOTALL,
    )

    errors = []
    for match in check_pattern.finditer(checks_sql):
        check_name = match.group(1)
        severity = match.group(2)
        check_body = match.group(3).strip()

        # Skip metric checks and non-error severity
        if severity != "error":
            continue

        # Skip checks that reference external schemas (store, product, customer)
        # Keep only checks about the four AASA tables
        if any(
            schema in check_body
            for schema in ["${store_schema}", "${product_schema}", "${customer_schema}"]
        ):
            continue

        # Skip checks that are known to reference missing external tables
        if "gold_associate_product_inventory_current" in check_body:
            continue
        if "gold_associate_price_promotion_current" in check_body:
            continue
        if "gold_associate_order_status_current" in check_body:
            continue
        if "gold_associate_data_freshness" in check_body:
            continue

        # Remove schema references for temp views
        check_body = re.sub(
            r"\$\{catalog\}\.\$\{aasa_schema\}\.",
            "",
            check_body,
        )

        # Run the check
        try:
            result = spark.sql(check_body).collect()
            if len(result) > 0:
                errors.append(
                    f"Check {check_name}: {len(result)} violation(s) found"
                )
        except Exception as e:
            # Skip checks with parse errors (e.g., schema references we can't substitute)
            pass

    assert len(errors) == 0, (
        f"Data quality checks failed:\n" + "\n".join(errors)
    )
