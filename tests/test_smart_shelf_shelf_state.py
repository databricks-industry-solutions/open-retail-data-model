"""Focused Spark tests for Smart Shelf shelf-state semantics.

The tests execute the committed gold and DQ SQL against DDL-derived fixture schemas.
They protect the latest-capture, denominator, state-honesty, episode, and two-row
misplacement decisions that are easy to make plausible-but-wrong in downstream SQL.
"""

import datetime as dt
import decimal
import os
import re

import pytest

from tools.ordm_config import resolve, shelf_policy_expressions, view_select_body
from tools.ordm_ddl.parser import parse_table_sql


REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PKG = os.path.join(REPO, "outcome-packages", "connected-store-signals")
TABLES = os.path.join(PKG, "tables")
GOLD = os.path.join(PKG, "gold")
CHECKS = os.path.join(PKG, "checks.sql")

OBSERVATION_DDL = os.path.join(TABLES, "shelf_state_observation.sql")
ASSIGNMENT_DDL = os.path.join(TABLES, "shelf_position_assignment.sql")

_RESOLVED_FQN_RE = re.compile(r"\bc\.[a-z_][a-z0-9_]*\.(\w+)", re.I)
_DDL_CACHE = {}


def TS(hour, minute=0):
    return dt.datetime(2026, 8, 17, hour, minute, tzinfo=dt.timezone.utc)


def _ddl(path):
    if path not in _DDL_CACHE:
        parsed = parse_table_sql(open(path).read())
        _DDL_CACHE[path] = {
            column["name"]: column["sql_type"] for column in parsed["columns"]
        }
    return _DDL_CACHE[path]


def _coerce(sql_type, value):
    if value is not None and sql_type.upper().startswith(("DECIMAL", "NUMERIC")):
        return decimal.Decimal(str(value))
    return value


def _table(spark, path, rows, name):
    types = _ddl(path)
    for row in rows:
        unknown = set(row) - set(types)
        assert not unknown, f"unknown {name} fixture columns: {sorted(unknown)}"
    values = [
        tuple(_coerce(types[column], row.get(column)) for column in types)
        for row in rows
    ]
    schema = ", ".join(f"{column} {sql_type}" for column, sql_type in types.items())
    spark.createDataFrame(values, schema).createOrReplaceTempView(name)


def _gold(spark, name, as_of=TS(12)):
    expressions = shelf_policy_expressions()
    expressions["shelf_as_of_ts"] = f"TIMESTAMP'{as_of:%Y-%m-%d %H:%M:%S}'"
    sql = resolve(
        open(os.path.join(GOLD, f"{name}.sql")).read(),
        "c",
        expressions=expressions,
    )
    body = _RESOLVED_FQN_RE.sub(r"\1", view_select_body(sql))
    spark.sql(f"CREATE OR REPLACE TEMP VIEW {name} AS " + body)


def _dq_check(spark, name, expressions=None):
    sql = resolve(open(CHECKS).read(), "c", expressions=expressions)
    match = re.search(
        rf"-- check: {re.escape(name)} \| severity: [^\n]+\n(.*?);",
        sql,
        re.DOTALL,
    )
    assert match, f"missing DQ check: {name}"
    return spark.sql(_RESOLVED_FQN_RE.sub(r"\1", match.group(1)))


def _observation(observation_id, position, product, observed_at, state, **values):
    product_number = int(product.removeprefix("P"))
    position_number = int(position.removeprefix("Z"))
    facing_by_state = {
        "in_stock": 3,
        "low_stock": 1,
        "out_of_stock": 0,
        "misplaced": 1,
        "unknown": None,
    }
    row = {
        "shelf_state_observation_sk": hash(observation_id),
        "shelf_state_observation_id": observation_id,
        "source_capture_id": f"CAP-{observation_id}",
        "shelf_position_assignment_sk": 1000 + position_number,
        "shelf_position_assignment_id": f"{position}|{product}",
        "store_sk": 1,
        "store_id": "S1",
        "store_zone_sk": 10 + position_number,
        "store_zone_id": position,
        "product_sk": 100 + product_number,
        "product_id": product,
        "sensor_device_sk": 21,
        "sensor_device_id": "D-SHELF",
        "sensing_deployment_sk": 31,
        "sensing_deployment_id": "DEP-SHELF",
        "observation_ts": observed_at,
        "store_timezone": "UTC",
        "utc_offset_minutes": 0,
        "trading_date": observed_at.date(),
        "hour_of_day": observed_at.hour,
        "shelf_state": state,
        "observed_facing_count": facing_by_state[state],
        "min_facing_threshold": 2,
        "is_gap_detected": state == "out_of_stock",
        "is_misplaced_detected": False,
        "is_price_tag_mismatch_detected": False,
        "zone_source": "device_placement",
        "attribution_confidence": 1.0,
        "measurement_validity": "valid",
        "arrival_completeness": "complete",
        "confidence_score": 0.95,
        "is_occluded": False,
        "coverage_ratio": 1.0,
        "restatement_version": 1,
        "ingest_timestamp": observed_at + dt.timedelta(minutes=1),
        "record_source": "test",
        "load_timestamp": observed_at + dt.timedelta(minutes=1),
    }
    row.update(values)
    return row


def _assignment(position, product):
    position_number = int(position.removeprefix("Z"))
    product_number = int(product.removeprefix("P"))
    return {
        "shelf_position_assignment_sk": 1000 + position_number,
        "shelf_position_assignment_id": f"{position}|{product}",
        "store_sk": 1,
        "store_id": "S1",
        "store_zone_sk": 10 + position_number,
        "store_zone_id": position,
        "product_sk": 100 + product_number,
        "product_id": product,
        "expected_facing_count": 3,
        "min_facing_count": 2,
        "facing_sequence": position_number,
        "assignment_source": "manual",
        "assignment_status": "active",
        "valid_from_ts": TS(0),
        "effective_from_date": dt.date(2026, 8, 17),
        "is_current": True,
        "created_timestamp": TS(0),
        "source_updated_timestamp": TS(0),
        "record_source": "test",
        "load_timestamp": TS(0),
    }


def test_osa_denominator_separates_known_unknown_and_unobserved(spark):
    assignments = [_assignment(f"Z{i}", f"P{i}") for i in range(1, 5)]
    observations = [
        _observation("O1", "Z1", "P1", TS(8), "in_stock"),
        _observation("O2", "Z2", "P2", TS(8), "out_of_stock"),
        _observation("O3-OLD", "Z3", "P3", TS(8), "in_stock"),
        _observation(
            "O3-NEW",
            "Z3",
            "P3",
            TS(9),
            "unknown",
            measurement_validity="invalid",
        ),
    ]
    _table(spark, ASSIGNMENT_DDL, assignments, "shelf_position_assignment")
    _table(spark, OBSERVATION_DDL, observations, "shelf_state_observation")
    spark.createDataFrame(
        [(101, "grocery"), (102, "grocery"), (103, "grocery"), (104, "grocery")],
        "product_sk long, category string",
    ).createOrReplaceTempView("product")

    _gold(spark, "gold_osa_daily_current")
    row = spark.table("gold_osa_daily_current").collect()[0]

    assert row.expected_positions == 4
    assert row.observed_positions == 3
    assert row.positions_known == 2
    assert row.positions_unknown == 1
    assert row.positions_unobserved == 1
    assert row.positions_available_eod == 1
    assert row.positions_oos_eod == 1
    assert row.osa_pct_eod == pytest.approx(0.5)
    assert row.observation_coverage_pct == pytest.approx(0.75)
    assert row.known_state_pct == pytest.approx(2 / 3)


def test_zero_observation_day_is_reported_as_unobserved(spark):
    _table(
        spark,
        ASSIGNMENT_DDL,
        [_assignment("Z1", "P1")],
        "shelf_position_assignment",
    )
    _table(spark, OBSERVATION_DDL, [], "shelf_state_observation")
    spark.createDataFrame(
        [(101, "grocery")],
        "product_sk long, category string",
    ).createOrReplaceTempView("product")
    spark.createDataFrame(
        [],
        "store_id string, product_id string, allocated_facings int, is_current boolean",
    ).createOrReplaceTempView("planogram")

    _gold(spark, "gold_osa_daily_current")
    osa = spark.table("gold_osa_daily_current").collect()
    assert len(osa) == 1
    assert osa[0].expected_positions == 1
    assert osa[0].observed_positions == 0
    assert osa[0].positions_unobserved == 1
    assert osa[0].observation_coverage_pct == pytest.approx(0.0)

    _gold(spark, "gold_planogram_compliance_current")
    compliance = spark.table("gold_planogram_compliance_current").collect()
    assert len(compliance) == 1
    assert compliance[0].positions_expected == 1
    assert compliance[0].positions_observed == 0
    assert compliance[0].positions_unobserved == 1
    assert compliance[0].observation_coverage_pct == pytest.approx(0.0)


def test_latest_unknown_invalid_capture_does_not_resurrect_valid_state(spark):
    observations = [
        _observation("OLD", "Z1", "P1", TS(8), "in_stock"),
        _observation(
            "NEW",
            "Z1",
            "P1",
            TS(9),
            "unknown",
            measurement_validity="invalid",
        ),
    ]
    _table(spark, OBSERVATION_DDL, observations, "shelf_state_observation")
    _table(spark, ASSIGNMENT_DDL, [_assignment("Z1", "P1")], "shelf_position_assignment")
    spark.createDataFrame([(21, False)], "sensor_device_sk long, is_mobile_platform boolean").createOrReplaceTempView(
        "sensor_device"
    )

    _gold(spark, "gold_shelf_state_current")
    row = spark.table("gold_shelf_state_current").collect()[0]

    assert row.source_capture_id == "CAP-NEW"
    assert row.shelf_state == "unknown"
    assert row.measurement_validity == "invalid"
    assert row.is_usable is False
    assert row.is_presence_compliant is None
    assert row.is_facing_compliant is None


def test_future_capture_does_not_override_state_at_evaluation_clock(spark):
    observations = [
        _observation("CURRENT", "Z1", "P1", TS(8), "in_stock"),
        _observation("FUTURE", "Z1", "P1", TS(13), "out_of_stock"),
    ]
    _table(spark, OBSERVATION_DDL, observations, "shelf_state_observation")
    _table(
        spark,
        ASSIGNMENT_DDL,
        [_assignment("Z1", "P1")],
        "shelf_position_assignment",
    )
    spark.createDataFrame(
        [(21, False)],
        "sensor_device_sk long, is_mobile_platform boolean",
    ).createOrReplaceTempView("sensor_device")

    _gold(spark, "gold_shelf_state_current", as_of=TS(12))
    row = spark.table("gold_shelf_state_current").collect()[0]
    assert row.source_capture_id == "CAP-CURRENT"
    assert row.freshness_age_minutes == 240

    future_ts = dt.datetime(2099, 1, 1, tzinfo=dt.timezone.utc)
    _table(
        spark,
        OBSERVATION_DDL,
        [_observation("CLOCK-SKEW", "Z1", "P1", future_ts, "in_stock")],
        "shelf_state_observation",
    )
    assert _dq_check(spark, "sso_observation_not_future").count() == 1


def test_surrogate_and_durable_reference_keys_must_identify_same_entities(spark):
    spark.createDataFrame([(1, "S-PARENT")], "store_sk long, store_id string").createOrReplaceTempView("store")
    spark.createDataFrame([(11, "Z-PARENT")], "store_zone_sk long, store_zone_id string").createOrReplaceTempView("store_zone")
    spark.createDataFrame([(101, "P-PARENT")], "product_sk long, product_id string").createOrReplaceTempView("product")
    spark.createDataFrame([(21, "D-PARENT")], "sensor_device_sk long, sensor_device_id string").createOrReplaceTempView("sensor_device")
    spark.createDataFrame([(31, "DEP-PARENT")], "sensing_deployment_sk long, sensing_deployment_id string").createOrReplaceTempView("sensing_deployment")

    spark.createDataFrame(
        [(51, "A-PARENT", 1, "S-CHILD", 11, "Z-CHILD", 101, "P-CHILD")],
        "shelf_position_assignment_sk long, shelf_position_assignment_id string, store_sk long, store_id string, store_zone_sk long, store_zone_id string, product_sk long, product_id string",
    ).createOrReplaceTempView("shelf_position_assignment")
    spark.createDataFrame(
        [("O1", 51, "A-CHILD", 1, "S-CHILD", 11, "Z-CHILD", 101, "P-CHILD", 21, "D-CHILD", 31, "DEP-CHILD")],
        "shelf_state_observation_id string, shelf_position_assignment_sk long, shelf_position_assignment_id string, store_sk long, store_id string, store_zone_sk long, store_zone_id string, product_sk long, product_id string, sensor_device_sk long, sensor_device_id string, sensing_deployment_sk long, sensing_deployment_id string",
    ).createOrReplaceTempView("shelf_state_observation")
    spark.createDataFrame(
        [(41, "L-PARENT", 1, "S-CHILD", 21, "D-CHILD")],
        "esl_label_sk long, esl_label_id string, store_sk long, store_id string, sensor_device_sk long, sensor_device_id string",
    ).createOrReplaceTempView("esl_label")
    spark.createDataFrame(
        [(61, "B-PARENT", 41, "L-CHILD", 101, "P-CHILD", 1, "S-CHILD", 11, "Z-CHILD")],
        "esl_label_assignment_sk long, esl_label_assignment_id string, esl_label_sk long, esl_label_id string, product_sk long, product_id string, store_sk long, store_id string, store_zone_sk long, store_zone_id string",
    ).createOrReplaceTempView("esl_label_assignment")
    spark.createDataFrame(
        [("PO1", 41, "L-CHILD", 61, "B-CHILD", 101, "P-CHILD", 1, "S-CHILD", 11, "Z-CHILD")],
        "esl_price_observation_id string, esl_label_sk long, esl_label_id string, esl_label_assignment_sk long, esl_label_assignment_id string, product_sk long, product_id string, store_sk long, store_id string, store_zone_sk long, store_zone_id string",
    ).createOrReplaceTempView("esl_price_observation")

    for check in (
        "ssa_reference_key_agreement",
        "sso_reference_key_agreement",
        "esll_reference_key_agreement",
        "esla_reference_key_agreement",
        "eslp_reference_key_agreement",
    ):
        assert _dq_check(spark, check).count() == 1


def test_state_enum_honesty_checks_each_failure_class(spark):
    dishonest = [
        _observation("BAD-OOS", "Z1", "P1", TS(8), "out_of_stock", observed_facing_count=1),
        _observation("BAD-LOW", "Z2", "P2", TS(8), "low_stock", observed_facing_count=2),
        _observation("BAD-IN", "Z3", "P3", TS(8), "in_stock", observed_facing_count=1),
        _observation("BAD-UNKNOWN", "Z4", "P4", TS(8), "unknown", observed_facing_count=0),
    ]
    _table(spark, OBSERVATION_DDL, dishonest, "shelf_state_observation")

    expected = {
        "sso_state_oos_zero_facings": "BAD-OOS",
        "sso_state_low_stock_band": "BAD-LOW",
        "sso_state_in_stock_meets_threshold": "BAD-IN",
        "sso_state_unknown_measures_null": "BAD-UNKNOWN",
    }
    for check, observation_id in expected.items():
        rows = _dq_check(spark, check).select("shelf_state_observation_id").collect()
        assert [row.shelf_state_observation_id for row in rows] == [observation_id]


def test_oos_episode_shaping_ignores_unknown_and_closes_on_usable_recovery(spark):
    observations = [
        _observation("IN-1", "Z1", "P1", TS(8), "in_stock"),
        _observation("OOS-1", "Z1", "P1", TS(9), "out_of_stock"),
        _observation(
            "UNKNOWN",
            "Z1",
            "P1",
            TS(9, 10),
            "unknown",
            measurement_validity="invalid",
        ),
        _observation(
            "OOS-2",
            "Z1",
            "P1",
            TS(9, 20),
            "out_of_stock",
            measurement_validity="degraded",
        ),
        _observation("RECOVERY", "Z1", "P1", TS(10), "in_stock"),
        _observation("OOS-3", "Z1", "P1", TS(11), "out_of_stock"),
    ]
    _table(spark, OBSERVATION_DDL, observations, "shelf_state_observation")
    spark.createDataFrame(
        [("S1", "P1", dt.date(2026, 8, 17), 7.0)],
        "store_id string, product_id string, date_key date, units_on_hand_eod double",
    ).createOrReplaceTempView("inventory_position")

    _gold(spark, "gold_observed_oos_episodes", as_of=TS(12))
    rows = spark.table("gold_observed_oos_episodes").orderBy("episode_start_ts").collect()

    assert len(rows) == 2
    closed, ongoing = rows
    assert closed.oos_episode_id.endswith("2026-08-17 09:00:00")
    assert closed.episode_recovery_ts - closed.episode_start_ts == dt.timedelta(hours=1)
    assert closed.episode_duration_minutes == 60
    assert closed.supporting_observation_count == 2
    assert closed.data_quality_flag is True
    assert closed.candidate_reason == "phantom_stock"
    assert ongoing.episode_start_ts - closed.episode_recovery_ts == dt.timedelta(hours=1)
    assert ongoing.episode_recovery_ts is None
    assert ongoing.is_ongoing is True
    assert ongoing.episode_duration_minutes == 60


def test_misplacement_requires_expected_product_sibling_in_same_capture(spark):
    assignment = _assignment("Z1", "P1")
    misplaced = _observation(
        "MISPLACED-P2",
        "Z1",
        "P2",
        TS(9),
        "misplaced",
        source_capture_id="CAP-MISPLACED-1",
        shelf_position_assignment_id="Z1|P1",
    )
    _table(spark, ASSIGNMENT_DDL, [assignment], "shelf_position_assignment")
    _table(spark, OBSERVATION_DDL, [misplaced], "shelf_state_observation")
    assert _dq_check(spark, "sso_misplaced_sibling_present").count() == 1

    expected_product = _observation(
        "MISSING-P1",
        "Z1",
        "P1",
        TS(9),
        "out_of_stock",
        source_capture_id="CAP-MISPLACED-1",
        is_misplaced_detected=True,
    )
    _table(
        spark,
        OBSERVATION_DDL,
        [misplaced, expected_product],
        "shelf_state_observation",
    )

    assert misplaced["source_capture_id"] == expected_product["source_capture_id"]
    assert _dq_check(spark, "sso_state_misplaced_semantics").count() == 0
    assert _dq_check(spark, "sso_misplaced_sibling_present").count() == 0
