"""Focused Spark tests for Smart Shelf ESL price-observation semantics.

Spark executes the committed gold and DQ SQL against the real DDL-derived schema so
price matching, correction history, latency, direction, and source-event identity stay
executable contracts rather than documentation-only promises.
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

PRICE_DDL = os.path.join(TABLES, "esl_price_observation.sql")

_FQN_RE = re.compile(r"\$\{catalog\}\.\$\{\w+_schema\}\.(\w+)")
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


def _table(spark, rows):
    types = _ddl(PRICE_DDL)
    for row in rows:
        unknown = set(row) - set(types)
        assert not unknown, f"unknown price fixture columns: {sorted(unknown)}"
    values = [
        tuple(_coerce(types[column], row.get(column)) for column in types)
        for row in rows
    ]
    schema = ", ".join(f"{column} {sql_type}" for column, sql_type in types.items())
    spark.createDataFrame(values, schema).createOrReplaceTempView("esl_price_observation")


def _gold(spark, as_of=TS(12)):
    expressions = shelf_policy_expressions()
    expressions["shelf_as_of_ts"] = f"TIMESTAMP'{as_of:%Y-%m-%d %H:%M:%S}'"
    sql = resolve(
        open(os.path.join(GOLD, "gold_price_accuracy_current.sql")).read(),
        "c",
        expressions=expressions,
    )
    body = _RESOLVED_FQN_RE.sub(r"\1", view_select_body(sql))
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_price_accuracy_current AS " + body)


def _dq_check(spark, name):
    sql = open(CHECKS).read()
    match = re.search(
        rf"-- check: {re.escape(name)} \| severity: [^\n]+\n(.*?);",
        sql,
        re.DOTALL,
    )
    assert match, f"missing DQ check: {name}"
    return spark.sql(_FQN_RE.sub(r"\1", match.group(1)))


def _price(label, source_id, observed_at, displayed, record, **values):
    source = values.pop("observation_source", "manual_audit")
    observation_id = values.pop(
        "esl_price_observation_id", f"{label}|{source}|{source_id}"
    )
    latency = values.get("display_sync_latency_seconds")
    row = {
        "esl_price_observation_sk": hash(observation_id),
        "esl_price_observation_id": observation_id,
        "source_observation_id": source_id,
        "esl_label_sk": 100 + int(label.removeprefix("L")),
        "esl_label_id": label,
        "esl_label_assignment_sk": 201,
        "esl_label_assignment_id": f"{label}|P1|Z1",
        "product_sk": 101,
        "product_id": "P1",
        "store_sk": 1,
        "store_id": "S1",
        "store_zone_sk": 11,
        "store_zone_id": "Z1",
        "observed_at_ts": observed_at,
        "store_timezone": "UTC",
        "utc_offset_minutes": 0,
        "trading_date": observed_at.date(),
        "hour_of_day": observed_at.hour,
        "observation_source": source,
        "displayed_price": displayed,
        "displayed_currency_code": "USD",
        "displayed_promo_indicator": False,
        "displayed_disclosure_indicator": False,
        "price_of_record": record,
        "price_of_record_currency_code": "USD" if record is not None else None,
        "price_of_record_source": "pricing_platform" if record is not None else None,
        "price_of_record_effective_ts": (
            observed_at - dt.timedelta(seconds=latency) if latency is not None else None
        ),
        "is_price_match": (
            displayed == record if displayed is not None and record is not None else None
        ),
        "sensing_derived_input_flag": False,
        "ingest_timestamp": observed_at + dt.timedelta(seconds=30),
        "record_source": "test",
        "load_timestamp": observed_at + dt.timedelta(seconds=30),
    }
    row.update(values)
    return row


def test_price_match_uses_last_observation_and_keeps_append_only_history(spark):
    rows = [
        _price("L1", "AUDIT-1", TS(8), 12, 10),
        _price("L1", "AUDIT-2", TS(9), 10, 10),
        _price("L2", "AUDIT-3", TS(9), None, 10),
    ]
    _table(spark, rows)
    _gold(spark)
    result = spark.table("gold_price_accuracy_current").collect()[0]

    assert spark.table("esl_price_observation").count() == 3
    assert result.labels_observed == 2
    assert result.price_observations == 3
    assert result.labels_evaluable == 1
    assert result.labels_matched_eod == 1
    assert result.labels_mismatched_eod == 0
    assert result.price_match_rate_eod == pytest.approx(1.0)
    assert result.labels_corrected == 1
    assert result.avg_correction_hours == pytest.approx(1.0)


def test_reopened_mismatch_ages_from_current_open_episode(spark):
    _table(
        spark,
        [
            _price("L1", "MISMATCH-1", TS(8), 12, 10),
            _price("L1", "MATCH", TS(9), 10, 10),
            _price("L1", "MISMATCH-2", TS(10), 12, 10),
            _price("L1", "MISMATCH-3", TS(10, 30), 12, 10),
        ],
    )
    _gold(spark)
    result = spark.table("gold_price_accuracy_current").collect()[0]

    assert result.labels_corrected == 1
    assert result.labels_mismatched_eod == 1
    assert float(result.max_open_mismatch_hours) == pytest.approx(0.5)


def test_price_of_record_currency_must_match_displayed_currency(spark):
    # A price-of-record captured from a non-store-reporting authority in a second
    # currency would make is_price_match / over-undercharge magnitudes compare across
    # currencies. The record side must carry its currency and it must agree.
    _table(
        spark,
        [
            _price("L1", "OK", TS(8), 10, 10),
            _price("L2", "FOREIGN", TS(8), 10, 9, price_of_record_currency_code="EUR"),
            _price("L3", "MISSING", TS(8), 10, 9, price_of_record_currency_code=None),
        ],
    )
    offenders = {r.esl_price_observation_id
                 for r in _dq_check(spark, "eslp_price_of_record_currency").collect()}
    assert offenders == {"L2|manual_audit|FOREIGN", "L3|manual_audit|MISSING"}

    # Serving fails closed even before the DQ runner blocks the deployment: currency-
    # unsafe rows remain observable as evidence but cannot enter regulatory comparison
    # counts, directions, or monetary mismatch magnitudes.
    _gold(spark)
    result = spark.table("gold_price_accuracy_current").collect()[0]
    assert result.labels_observed == 3
    assert result.labels_evaluable == 1
    assert result.labels_mismatched_eod == 0
    assert result.labels_overcharging_eod == 0
    assert result.labels_undercharging_eod == 0
    assert result.avg_mismatch_abs_amount is None
    assert result.max_mismatch_abs_amount is None

    # A second currency reaches the single-reporting-currency contract even when the
    # displayed side is unreadable (occluded), so the tie's NULL-displayed gap is closed.
    _table(
        spark,
        [
            _price("L1", "SEEN", TS(8), 10, 10),
            _price("L2", "OCCLUDED", TS(9), None, 9,
                   price_of_record_currency_code="EUR", displayed_currency_code=None),
        ],
    )
    assert _dq_check(spark, "eslp_single_currency").count() == 1


def test_overcharge_and_undercharge_are_counted_separately(spark):
    _table(
        spark,
        [
            _price("L1", "OVER", TS(9), 12, 10),
            _price("L2", "UNDER", TS(9), 8, 10),
        ],
    )
    _gold(spark)
    result = spark.table("gold_price_accuracy_current").collect()[0]

    assert result.labels_mismatched_eod == 2
    assert result.labels_overcharging_eod == 1
    assert result.labels_undercharging_eod == 1
    assert float(result.avg_mismatch_abs_amount) == pytest.approx(2.0)
    assert float(result.max_mismatch_abs_amount) == pytest.approx(2.0)


def test_sync_latency_uses_platform_ack_observations_only(spark):
    _table(
        spark,
        [
            _price(
                "L1",
                "ACK-30",
                TS(9),
                10,
                10,
                observation_source="platform_ack",
                display_sync_latency_seconds=30,
            ),
            _price(
                "L2",
                "ACK-60",
                TS(9),
                10,
                10,
                observation_source="platform_ack",
                display_sync_latency_seconds=60,
            ),
            _price(
                "L3",
                "ACK-120",
                TS(9),
                10,
                10,
                observation_source="platform_ack",
                display_sync_latency_seconds=120,
            ),
            _price(
                "L4",
                "CV-1",
                TS(9),
                10,
                10,
                observation_source="shelf_cv",
            ),
        ],
    )
    _gold(spark)
    result = spark.table("gold_price_accuracy_current").collect()[0]

    assert result.ack_observations == 3
    assert result.cv_observations == 1
    assert result.sync_latency_p50_seconds == pytest.approx(60)
    assert result.sync_latency_p95_seconds == pytest.approx(120)
    assert result.sync_latency_max_seconds == 120
    assert _dq_check(spark, "eslp_sync_latency_ack_only").count() == 0
    assert _dq_check(spark, "eslp_sync_latency_agreement").count() == 0


def test_source_observation_identity_deduplicates_redelivery_without_cross_source_collision(spark):
    first = _price(
        "L1",
        "SOURCE-1",
        TS(9),
        10,
        10,
        observation_source="platform_ack",
    )
    redelivery = dict(first)
    redelivery["esl_price_observation_id"] += "|MALFORMED-REDELIVERY"
    redelivery["esl_price_observation_sk"] = hash(
        redelivery["esl_price_observation_id"]
    )
    redelivery["ingest_timestamp"] = TS(9, 1)
    redelivery["load_timestamp"] = TS(9, 1)
    _table(spark, [first, redelivery])

    ledger = spark.table("esl_price_observation")
    assert ledger.count() == 2
    assert ledger.dropDuplicates(
        ["esl_label_id", "observation_source", "source_observation_id"]
    ).count() == 1
    assert _dq_check(spark, "eslp_grain_unique").count() == 0
    violation = _dq_check(spark, "eslp_source_identity_unique").collect()
    assert len(violation) == 1
    assert violation[0].source_observation_id == "SOURCE-1"
    assert violation[0].n == 2

    independent_source = _price(
        "L1",
        "SOURCE-1",
        TS(9),
        10,
        10,
        observation_source="shelf_cv",
    )
    _table(spark, [first, independent_source])
    assert first["esl_price_observation_id"] != independent_source["esl_price_observation_id"]
    assert _dq_check(spark, "eslp_source_identity_unique").count() == 0
