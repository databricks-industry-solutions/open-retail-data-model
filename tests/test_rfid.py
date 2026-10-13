"""Focused executable tests for the Connected Store Signals RFID gold layer.

These focused tests cover the business decisions that can otherwise produce plausible but
wrong results: attributed current state, reconciliation basis, count coverage,
linked-versus-unlinked receiving evidence, and RFID key/location DQ contracts. Spark
executes the committed SQL itself.
"""

import datetime as dt
import decimal
import os
import re

import pytest

from tools.ordm_config import (
    resolve,
    rfid_clock_expressions,
    rfid_policy_expressions,
    view_select_body,
)
from tools.ordm_ddl.parser import parse_table_sql


REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PKG = os.path.join(REPO, "outcome-packages", "connected-store-signals")
TABLES = os.path.join(PKG, "tables")
GOLD = os.path.join(PKG, "gold")
METRIC_VIEWS = os.path.join(PKG, "metric-views")
CHECKS = os.path.join(PKG, "checks.sql")

EVENT_DDL = os.path.join(TABLES, "rfid_read_event.sql")
ITEM_DDL = os.path.join(TABLES, "tagged_item.sql")
SESSION_DDL = os.path.join(TABLES, "rfid_count_session.sql")
DEVICE_DDL = os.path.join(TABLES, "sensor_device.sql")
ZONE_DDL = os.path.join(TABLES, "store_zone.sql")
REPORT_DDL = os.path.join(TABLES, "sensor_report_interval.sql")
TRAFFIC_DETAIL_DDL = os.path.join(TABLES, "foot_traffic_interval_detail.sql")
DEPLOYMENT_DDL = os.path.join(TABLES, "sensing_deployment.sql")
ESL_LABEL_DDL = os.path.join(TABLES, "esl_label.sql")
ESL_PRICE_OBSERVATION_DDL = os.path.join(TABLES, "esl_price_observation.sql")

_FQN_RE = re.compile(r"\$\{catalog\}\.\$\{\w+_schema\}\.(\w+)")
_RESOLVED_FQN_RE = re.compile(r"\bc\.[a-z_][a-z0-9_]*\.(\w+)", re.I)
_DDL_CACHE = {}
D = dt.date


def TS(*parts):
    return dt.datetime(*parts, tzinfo=dt.timezone.utc)


def _ddl(path):
    if path not in _DDL_CACHE:
        parsed = parse_table_sql(open(path).read())
        _DDL_CACHE[path] = {column["name"]: column["sql_type"] for column in parsed["columns"]}
    return _DDL_CACHE[path]


def _coerce(sql_type, value):
    if value is not None and sql_type.upper().startswith(("DECIMAL", "NUMERIC")):
        return decimal.Decimal(str(value))
    return value


def _table(spark, path, rows, name):
    types = _ddl(path)
    for row in rows:
        assert not set(row) - set(types), f"unknown {name} fixture columns: {sorted(set(row) - set(types))}"
    values = [tuple(_coerce(types[column], row.get(column)) for column in types) for row in rows]
    schema = ", ".join(f"{column} {sql_type}" for column, sql_type in types.items())
    spark.createDataFrame(values, schema).createOrReplaceTempView(name)


def _gold(spark, name, rfid_as_of_mode="wall_clock", rfid_policy=None):
    path = os.path.join(GOLD, f"{name}.sql")
    expressions = rfid_clock_expressions(
        rfid_as_of_mode,
        "c",
        {"css_schema": "connected_store_signals"},
    )
    if rfid_policy:
        expressions.update(rfid_policy_expressions(**rfid_policy))
    resolved = resolve(open(path).read(), "c", expressions=expressions)
    body = _RESOLVED_FQN_RE.sub(r"\1", view_select_body(resolved))
    spark.sql(f"CREATE OR REPLACE TEMP VIEW {name} AS " + body)


def _metric_expr(filename, measure):
    """Return one authored metric-view measure expression for Spark execution."""
    text = open(os.path.join(METRIC_VIEWS, filename)).read()
    match = re.search(
        rf"^  - name:\s*{re.escape(measure)}\s*$\n"
        rf"^\s+expr:\s*(.+)$",
        text,
        re.M,
    )
    assert match, f"{filename} has no measure named {measure}"
    return match.group(1)


def _dq_check(spark, name):
    sql = open(CHECKS).read()
    match = re.search(
        rf"-- check: {re.escape(name)} \| severity: [^\n]+\n(.*?);",
        sql,
        re.DOTALL,
    )
    assert match, f"missing DQ check: {name}"
    return spark.sql(_FQN_RE.sub(r"\1", match.group(1)))


def _event(event_id, item_id, event_ts, **values):
    row = {
        "rfid_read_event_sk": hash(event_id),
        "rfid_read_event_id": event_id,
        "tagged_item_sk": hash(item_id),
        "tagged_item_id": item_id,
        "is_unregistered_epc": False,
        "product_sk": 101,
        "product_id": "P1",
        "store_sk": 1,
        "store_id": "S1",
        "store_zone_sk": 11,
        "store_zone_id": "Z1",
        "sensor_device_sk": 21,
        "sensor_device_id": "D-FIXED",
        "sensing_deployment_sk": 31,
        "sensing_deployment_id": "DEP-RFID",
        "event_ts": event_ts,
        "first_seen_ts": event_ts - dt.timedelta(seconds=1),
        "last_seen_ts": event_ts,
        "store_timezone": "America/Chicago",
        "utc_offset_minutes": -300,
        "trading_date": event_ts.date(),
        "hour_of_day": event_ts.hour,
        "zone_source": "device_placement",
        "direction_code": "not_applicable",
        "attribution_confidence": 0.99,
        "is_stray_suspect": False,
        "read_count": 3,
        "duplicate_delivery_count": 0,
        "ingest_timestamp": event_ts + dt.timedelta(seconds=10),
        "record_source": "test",
        "load_timestamp": event_ts + dt.timedelta(seconds=10),
    }
    row.update(values)
    return row


def _item(item_id, product_id="P1", product_sk=101):
    return {
        "tagged_item_sk": hash(item_id),
        "tagged_item_id": item_id,
        "epc_scheme": "sgtin",
        "gtin": "00000000000001",
        "serial_number": item_id.rsplit(".", 1)[-1],
        "product_sk": product_sk,
        "product_id": product_id,
        "tag_privacy_state": "active",
        "commissioned_at_ts": TS(2026, 1, 1),
        "record_source": "test",
        "load_timestamp": TS(2026, 1, 1),
    }


def _session(session_sk, session_id, start_ts, end_ts, scope_type="full_store"):
    return {
        "rfid_count_session_sk": session_sk,
        "rfid_count_session_id": session_id,
        "source_session_id": session_id,
        "store_sk": 1,
        "store_id": "S1",
        "count_method": "fixed_window",
        "scope_type": scope_type,
        "started_at_ts": start_ts,
        "ended_at_ts": end_ts,
        "store_timezone": "America/Chicago",
        "utc_offset_minutes": -300,
        "trading_date": D(2026, 8, 17),
        "hour_of_day": (start_ts.hour - 5) % 24,
        "ingest_timestamp": end_ts + dt.timedelta(seconds=30),
        "record_source": "test",
        "load_timestamp": end_ts + dt.timedelta(seconds=30),
    }


def test_item_current_state_excludes_strays_and_persists_recall(spark):
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    item_a = "urn:epc:id:sgtin:0614141.100001.1"
    item_b = "urn:epc:id:sgtin:0614141.100001.2"
    events = [
        _event("A-valid", item_a, now - dt.timedelta(minutes=30), store_zone_id="Z-GOOD"),
        _event("A-stray", item_a, now - dt.timedelta(minutes=5),
               store_zone_id="Z-BLEED", is_stray_suspect=True, attribution_confidence=0.2),
        _event("B-recall", item_b, now - dt.timedelta(hours=2),
               sensor_device_sk=22, sensor_device_id="D-MOBILE",
               zone_source="operator_declared",
               disposition_uri="https://ref.gs1.org/cbv/Disp-recalled"),
        _event("B-later", item_b, now - dt.timedelta(hours=1),
               sensor_device_sk=22, sensor_device_id="D-MOBILE",
               zone_source="operator_declared",
               disposition_uri="https://ref.gs1.org/cbv/Disp-sellable_accessible"),
    ]
    devices = [
        {"sensor_device_sk": 21, "sensor_device_id": "D-FIXED", "is_mobile_platform": False},
        {"sensor_device_sk": 22, "sensor_device_id": "D-MOBILE", "is_mobile_platform": True},
    ]
    _table(spark, EVENT_DDL, events, "rfid_read_event")
    _table(spark, DEVICE_DDL, devices, "sensor_device")
    _gold(spark, "gold_item_current_state")

    rows = {row.tagged_item_id: row for row in spark.sql(
        "SELECT tagged_item_id, store_zone_id, derived_disposition_uri, "
        "derived_presence_state, freshness_window_minutes FROM gold_item_current_state"
    ).collect()}
    assert rows[item_a].store_zone_id == "Z-GOOD"
    assert rows[item_a].derived_presence_state == "present"
    assert rows[item_b].derived_disposition_uri.endswith("Disp-recalled")
    assert rows[item_b].derived_presence_state == "unavailable"
    assert rows[item_b].freshness_window_minutes == 1440


def test_terminal_item_state_outlives_freshness_while_nonterminal_evidence_stales(spark):
    """Freshness qualifies presence evidence; it must not erase known terminal facts."""
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    recalled = "urn:epc:id:sgtin:0614141.100001.stale-recalled"
    sold = "urn:epc:id:sgtin:0614141.100001.stale-sold"
    shipped = "urn:epc:id:sgtin:0614141.100001.stale-shipped"
    damaged = "urn:epc:id:sgtin:0614141.100001.stale-damaged"
    ordinary = "urn:epc:id:sgtin:0614141.100001.stale-ordinary"
    events = [
        _event(
            "STALE-RECALL",
            recalled,
            now - dt.timedelta(hours=4),
            disposition_uri="https://ref.gs1.org/cbv/Disp-recalled",
        ),
        _event(
            "STALE-RECALL-LATER",
            recalled,
            now - dt.timedelta(hours=3),
            disposition_uri="https://ref.gs1.org/cbv/Disp-sellable_accessible",
        ),
        _event(
            "STALE-SOLD",
            sold,
            now - dt.timedelta(hours=3),
            disposition_uri="https://ref.gs1.org/cbv/Disp-retail_sold",
        ),
        _event(
            "STALE-SHIPPED",
            shipped,
            now - dt.timedelta(hours=3),
            biz_step_uri="https://ref.gs1.org/cbv/BizStep-shipping",
        ),
        _event(
            "STALE-DAMAGED",
            damaged,
            now - dt.timedelta(hours=3),
            disposition_uri="https://ref.gs1.org/cbv/Disp-damaged",
        ),
        _event("STALE-ORDINARY", ordinary, now - dt.timedelta(hours=3)),
    ]
    _table(spark, EVENT_DDL, events, "rfid_read_event")
    _table(
        spark,
        DEVICE_DDL,
        [{"sensor_device_sk": 21, "sensor_device_id": "D-FIXED", "is_mobile_platform": False}],
        "sensor_device",
    )
    _gold(spark, "gold_item_current_state")

    rows = {row.tagged_item_id: row for row in spark.sql(
        "SELECT tagged_item_id, derived_disposition_uri, derived_presence_state, "
        "freshness_age_minutes, freshness_window_minutes FROM gold_item_current_state"
    ).collect()}
    assert all(
        row.freshness_age_minutes > row.freshness_window_minutes
        for row in rows.values()
    )
    assert rows[recalled].derived_disposition_uri.endswith("Disp-recalled")
    assert rows[recalled].derived_presence_state == "unavailable"
    assert rows[sold].derived_presence_state == "absent"
    assert rows[shipped].derived_presence_state == "absent"
    assert rows[damaged].derived_presence_state == "unavailable"
    assert rows[ordinary].derived_presence_state == "stale"


def test_historical_item_presence_can_evaluate_at_the_rfid_data_max(spark):
    """A frozen demo remains historical; only its evaluation clock moves to data end."""
    event_ts = TS(2024, 12, 31, 20)
    item_id = "urn:epc:id:sgtin:0614141.100001.historical"
    _table(spark, EVENT_DDL, [_event("HISTORICAL", item_id, event_ts)], "rfid_read_event")
    _table(
        spark,
        DEVICE_DDL,
        [{"sensor_device_sk": 21, "sensor_device_id": "D-FIXED", "is_mobile_platform": False}],
        "sensor_device",
    )

    _gold(spark, "gold_item_current_state")
    wall_clock = spark.sql(
        "SELECT derived_presence_state FROM gold_item_current_state"
    ).first()
    assert wall_clock.derived_presence_state == "stale"

    _gold(spark, "gold_item_current_state", rfid_as_of_mode="data_max")
    data_clock = spark.sql(
        "SELECT derived_presence_state, freshness_age_minutes FROM gold_item_current_state"
    ).first()
    assert data_clock.derived_presence_state == "present"
    assert data_clock.freshness_age_minutes == 0

    _gold(spark, "gold_zone_item_presence_current")
    presence = spark.sql(
        "SELECT units_present, max_freshness_age_minutes FROM gold_zone_item_presence_current"
    ).first()
    assert presence.units_present == 1
    assert presence.max_freshness_age_minutes == 0


def test_item_visibility_uses_the_same_historical_rfid_clock(spark):
    event_ts = TS(2024, 12, 31, 20)
    _table(
        spark,
        EVENT_DDL,
        [_event("VISIBILITY-HISTORICAL", "item-historical", event_ts)],
        "rfid_read_event",
    )

    _gold(spark, "gold_item_visibility_daily", rfid_as_of_mode="data_max")
    row = spark.sql(
        "SELECT latest_event_ts, freshness_age_minutes, fresh_as_of_ts "
        "FROM gold_item_visibility_daily"
    ).first()

    assert row.latest_event_ts == row.fresh_as_of_ts
    assert row.freshness_age_minutes == 0


def test_count_coverage_uses_configured_wall_clock_policy_windows(spark):
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    events = [
        _event(
            "COUNT-RECENT",
            "item-recent",
            now - dt.timedelta(days=10),
            rfid_count_session_sk=1,
            rfid_count_session_id="SESSION-RECENT",
        ),
        _event(
            "COUNT-OLD",
            "item-old",
            now - dt.timedelta(days=40),
            rfid_count_session_sk=2,
            rfid_count_session_id="SESSION-OLD",
        ),
    ]
    zones = [{
        "store_zone_sk": 11,
        "store_zone_id": "Z1",
        "store_sk": 1,
        "store_id": "S1",
        "zone_code": "sales-floor",
        "zone_name": "Sales floor",
        "zone_type": "aisle",
        "is_sales_floor": True,
        "effective_from_date": D(2026, 1, 1),
        "is_current": True,
    }]
    _table(spark, EVENT_DDL, events, "rfid_read_event")
    _table(spark, ZONE_DDL, zones, "store_zone")

    _gold(
        spark,
        "gold_zone_count_coverage",
        rfid_policy={
            "count_target_cadence_days": "5",
            "count_lookback_days": "14",
        },
    )
    row = spark.sql(
        "SELECT target_cadence_days, is_overdue, count_lookback_days, "
        "count_sessions_in_lookback FROM gold_zone_count_coverage"
    ).first()

    assert row.target_cadence_days == 5
    assert row.is_overdue is True
    assert row.count_lookback_days == 14
    assert row.count_sessions_in_lookback == 1


def test_inventory_accuracy_uses_closing_hour_and_rfid_eligibility(spark):
    aligned = _session(1, "S-ALIGNED", TS(2026, 8, 18, 1), TS(2026, 8, 18, 2))
    misaligned = _session(2, "S-MISALIGNED", TS(2026, 8, 17, 17), TS(2026, 8, 17, 18))
    post_midnight = _session(
        3,
        "S-POST-MIDNIGHT",
        TS(2026, 8, 18, 5, 30),
        TS(2026, 8, 18, 6, 30),
    )
    item_1 = "urn:epc:id:sgtin:0614141.100001.1"
    item_2 = "urn:epc:id:sgtin:0614141.100001.2"
    item_3 = "urn:epc:id:sgtin:0614141.100002.1"
    items = [_item(item_1, product_sk=101), _item(item_2, product_sk=102),
             _item(item_3, product_id="P2", product_sk=201)]
    events = [
        _event("P1-A", item_1, TS(2026, 8, 18, 1, 15), product_sk=101,
               rfid_count_session_sk=1, rfid_count_session_id="S-ALIGNED"),
        _event("P1-B", item_2, TS(2026, 8, 18, 1, 20), product_sk=102,
               rfid_count_session_sk=1, rfid_count_session_id="S-ALIGNED"),
        _event("P1-M", item_1, TS(2026, 8, 17, 17, 15),
               rfid_count_session_sk=2, rfid_count_session_id="S-MISALIGNED"),
        _event("P1-POST", item_1, TS(2026, 8, 18, 6),
               rfid_count_session_sk=3, rfid_count_session_id="S-POST-MIDNIGHT"),
        _event("P2-HISTORY", item_3, TS(2026, 8, 10, 12), product_sk=201, product_id="P2"),
    ]
    _table(spark, SESSION_DDL, [aligned, misaligned, post_midnight], "rfid_count_session")
    _table(spark, EVENT_DDL, events, "rfid_read_event")
    _table(spark, ITEM_DDL, items, "tagged_item")
    spark.createDataFrame([
        (102, "P1", "S1", D(2026, 8, 17), decimal.Decimal("3.000")),
        (102, "P1", "S1", D(2026, 8, 18), decimal.Decimal("30.000")),
        (201, "P2", "S1", D(2026, 8, 17), decimal.Decimal("2.000")),
        (301, "P3", "S1", D(2026, 8, 17), decimal.Decimal("4.000")),
    ], "product_sk long, product_id string, store_id string, date_key date, units_on_hand_eod decimal(12,3)").createOrReplaceTempView("inventory_position")
    spark.createDataFrame([
        (102, "Dept", "Cat", "Sub"), (201, "Dept", "Cat", "Sub"),
        (301, "Dept", "Cat", "Sub"),
    ], "product_sk long, department string, category string, subcategory string").createOrReplaceTempView("product")
    _gold(spark, "gold_inventory_accuracy_daily")

    rows = {(row.rfid_count_session_id, row.product_id): row for row in spark.sql(
        "SELECT * FROM gold_inventory_accuracy_daily"
    ).collect()}
    assert len([key for key in rows if key == ("S-ALIGNED", "P1")]) == 1
    assert rows[("S-ALIGNED", "P1")].reconciliation_basis == "aligned_eod"
    assert float(rows[("S-ALIGNED", "P1")].inventory_accuracy_pct) == pytest.approx(2 / 3)
    post = rows[("S-POST-MIDNIGHT", "P1")]
    assert post.session_end_local_date == D(2026, 8, 18)
    assert post.reconciliation_date == D(2026, 8, 17)
    assert float(post.book_units_eod) == pytest.approx(3.0)
    assert rows[("S-MISALIGNED", "P1")].inventory_accuracy_pct is None
    assert rows[("S-MISALIGNED", "P1")].observed_to_book_agreement_pct is not None
    assert rows[("S-ALIGNED", "P2")].is_phantom_stock is True
    assert not any(product_id == "P3" for _, product_id in rows)

    _gold(spark, "gold_inventory_accuracy_daily_latest")
    latest = spark.sql(
        "SELECT * FROM gold_inventory_accuracy_daily_latest "
        "WHERE reconciliation_basis = 'aligned_eod'"
    ).collect()
    latest_p1 = [row for row in latest if row.product_id == "P1"]
    assert len(latest_p1) == 1
    assert latest_p1[0].rfid_count_session_id == "S-POST-MIDNIGHT"
    assert sum(float(row.book_units_eod) for row in latest) == pytest.approx(5.0)

    # The support view deliberately retains one row per basis. Execute the authored
    # metric expressions without grouping by basis to prove the aligned and misaligned
    # copies of the same EOD book snapshot are not summed together.
    metric_values = spark.sql(
        "SELECT "
        + _metric_expr("inventory_accuracy.sql", "observed_units")
        + " AS observed_units, "
        + _metric_expr("inventory_accuracy.sql", "book_units")
        + " AS book_units, "
        + _metric_expr("inventory_accuracy.sql", "absolute_unit_variance")
        + " AS absolute_unit_variance "
        + "FROM gold_inventory_accuracy_daily_latest WHERE product_id = 'P1'"
    ).first()
    assert float(metric_values.observed_units) == pytest.approx(1.0)
    assert float(metric_values.book_units) == pytest.approx(3.0)
    assert float(metric_values.absolute_unit_variance) == pytest.approx(2.0)

    _gold(spark, "gold_rfid_oos_candidates")
    candidate = spark.sql(
        "SELECT * FROM gold_rfid_oos_candidates WHERE product_id = 'P2'"
    ).first()
    assert candidate is not None
    assert candidate.candidate_reason == "phantom_stock"
    assert candidate.reconciliation_date == D(2026, 8, 17)
    assert "oos_duration_days" not in spark.table("gold_rfid_oos_candidates").columns
    assert "oos_end_date_key" not in spark.table("gold_rfid_oos_candidates").columns


def test_count_session_summary_keeps_partial_coverage_honest(spark):
    sessions = [
        # UTC start is the following day while trading_date remains the store-local 17th.
        _session(1, "S-FULL", TS(2026, 8, 18, 1), TS(2026, 8, 18, 2)),
        _session(2, "S-PART", TS(2026, 8, 17, 16), TS(2026, 8, 17, 17), "partial"),
    ]
    zones = [
        {"store_zone_sk": 10, "store_zone_id": "Z-SITE", "store_sk": 1, "store_id": "S1",
         "zone_code": "site", "zone_type": "site", "effective_from_date": D(2026, 1, 1), "is_current": True},
        {"store_zone_sk": 11, "store_zone_id": "Z1", "store_sk": 1, "store_id": "S1",
         "zone_code": "one", "zone_type": "aisle", "effective_from_date": D(2026, 1, 1),
         "effective_to_date": D(2026, 8, 18), "is_current": False},
        {"store_zone_sk": 12, "store_zone_id": "Z2", "store_sk": 1, "store_id": "S1",
         "zone_code": "two", "zone_type": "aisle", "effective_from_date": D(2026, 1, 1),
         "effective_to_date": D(2026, 8, 18), "is_current": False},
    ]
    events = [
        _event("FULL-1", "item-1", TS(2026, 8, 18, 1, 10),
               rfid_count_session_sk=1, rfid_count_session_id="S-FULL"),
        _event("FULL-SITE", "item-site", TS(2026, 8, 18, 1, 20),
               store_zone_sk=10, store_zone_id="Z-SITE",
               rfid_count_session_sk=1, rfid_count_session_id="S-FULL"),
        _event("PART-1", "item-2", TS(2026, 8, 17, 16, 10),
               rfid_count_session_sk=2, rfid_count_session_id="S-PART"),
    ]
    _table(spark, SESSION_DDL, sessions, "rfid_count_session")
    _table(spark, ZONE_DDL, zones, "store_zone")
    _table(spark, EVENT_DDL, events, "rfid_read_event")
    _gold(spark, "gold_count_session_summary")

    rows = {row.rfid_count_session_id: row for row in spark.sql(
        "SELECT * FROM gold_count_session_summary"
    ).collect()}
    assert rows["S-FULL"].planned_zones == 2
    assert rows["S-FULL"].zones_covered == 1
    assert rows["S-FULL"].zones_missed == 1
    assert float(rows["S-FULL"].zone_coverage_rate) == pytest.approx(0.5)
    assert rows["S-PART"].planned_zones is None
    assert rows["S-PART"].zones_missed is None
    assert rows["S-PART"].zone_coverage_rate is None


def test_receiving_verification_separates_linked_and_unlinked_evidence(spark):
    receiving = "https://ref.gs1.org/cbv/BizStep-receiving"
    events = [
        _event("LINKED", "item-1", TS(2026, 8, 17, 10), biz_step_uri=receiving,
               shipment_line_sk=501, shipment_line_id="SL1"),
        _event("UNLINKED-1", "item-2", TS(2026, 8, 17, 11), biz_step_uri=receiving,
               product_sk=201, product_id="P2"),
        _event("UNLINKED-2", "item-3", TS(2026, 8, 17, 11, 5), biz_step_uri=receiving,
               product_sk=201, product_id="P2"),
    ]
    _table(spark, EVENT_DDL, events, "rfid_read_event")
    spark.createDataFrame([(501, "SL1", "SHIP1", 3)],
                          "shipment_line_sk long, shipment_line_id string, shipment_id string, shipped_quantity int").createOrReplaceTempView("shipment_line")
    _gold(spark, "gold_receiving_verification")

    rows = {row.verification_tier: row for row in spark.sql(
        "SELECT * FROM gold_receiving_verification"
    ).collect()}
    assert rows["linked_shipment"].shipment_id == "SHIP1"
    assert rows["linked_shipment"].expected_units == 3
    assert rows["linked_shipment"].observed_units == 1
    assert rows["linked_shipment"].verification_status == "short"
    assert rows["unlinked_window_evidence"].shipment_id is None
    assert rows["unlinked_window_evidence"].expected_units is None
    assert rows["unlinked_window_evidence"].observed_units == 2
    assert rows["unlinked_window_evidence"].verification_status == "evidence_only"


def test_rfid_dq_registration_and_zone_source_contracts(spark):
    event_ts = TS(2026, 8, 17, 10)
    registered_grai = "urn:epc:id:grai:0614141.12345.1"
    registered_sgtin = "urn:epc:id:sgtin:0614141.100001.99"
    registered_sgtin_ok = "urn:epc:id:sgtin:0614141.100001.100"
    registered_sgtin_wrong = "urn:epc:id:sgtin:0614141.100001.101"
    unregistered = "urn:epc:id:sgtin:9999999.99999.1"
    registration_rows = [
        _event("GRAI-OK", registered_grai, event_ts, product_sk=None, product_id=None),
        _event(
            "SGTIN-MISSING-PRODUCT",
            registered_sgtin,
            event_ts,
            product_sk=None,
            product_id=None,
        ),
        _event("SGTIN-OK", registered_sgtin_ok, event_ts),
        _event(
            "SGTIN-WRONG-PRODUCT",
            registered_sgtin_wrong,
            event_ts,
            product_sk=201,
            product_id="P2",
        ),
        _event(
            "UNREGISTERED-OK",
            unregistered,
            event_ts,
            is_unregistered_epc=True,
            tagged_item_sk=None,
            product_sk=None,
            product_id=None,
        ),
        _event("MISSING-ITEM", "item-missing", event_ts, tagged_item_sk=None),
        _event("HALF-PRODUCT", "item-half", event_ts, product_id=None),
    ]
    _table(spark, EVENT_DDL, registration_rows, "rfid_read_event")
    grai_item = _item(registered_grai)
    grai_item.update(epc_scheme="grai", gtin=None, product_sk=None, product_id=None)
    _table(
        spark,
        ITEM_DDL,
        [
            grai_item,
            _item(registered_sgtin),
            _item(registered_sgtin_ok),
            _item(registered_sgtin_wrong),
            _item("item-half"),
        ],
        "tagged_item",
    )
    violations = {
        row.rfid_read_event_id
        for row in _dq_check(spark, "rre_registration_pairing").collect()
    }
    assert violations == {
        "MISSING-ITEM",
        "HALF-PRODUCT",
        "SGTIN-MISSING-PRODUCT",
        "SGTIN-WRONG-PRODUCT",
    }

    zone_rows = [
        _event("FIXED-OK", "item-fixed-ok", event_ts),
        _event(
            "FIXED-BAD",
            "item-fixed-bad",
            event_ts,
            zone_source="platform_localization",
        ),
        _event(
            "MOBILE-OPERATOR-OK",
            "item-mobile-operator",
            event_ts,
            sensor_device_sk=22,
            sensor_device_id="D-MOBILE",
            zone_source="operator_declared",
        ),
        _event(
            "MOBILE-PLATFORM-OK",
            "item-mobile-platform",
            event_ts,
            sensor_device_sk=22,
            sensor_device_id="D-MOBILE",
            zone_source="platform_localization",
        ),
        _event(
            "MOBILE-BAD",
            "item-mobile-bad",
            event_ts,
            sensor_device_sk=22,
            sensor_device_id="D-MOBILE",
        ),
    ]
    devices = [
        {"sensor_device_sk": 21, "sensor_device_id": "D-FIXED", "is_mobile_platform": False},
        {"sensor_device_sk": 22, "sensor_device_id": "D-MOBILE", "is_mobile_platform": True},
    ]
    _table(spark, EVENT_DDL, zone_rows, "rfid_read_event")
    _table(spark, DEVICE_DDL, devices, "sensor_device")
    violations = {
        row.rfid_read_event_id
        for row in _dq_check(spark, "rre_zone_source_honesty").collect()
    }
    assert violations == {"FIXED-BAD", "MOBILE-BAD"}


def test_rfid_session_calendar_and_retail_sold_context_checks(spark):
    session = _session(1, "S-CALENDAR", TS(2026, 8, 17, 20), TS(2026, 8, 17, 21))
    _table(spark, SESSION_DDL, [session], "rfid_count_session")
    spark.createDataFrame([(D(2026, 8, 18),)], "date_key date").createOrReplaceTempView(
        "fiscal_calendar"
    )
    assert [row.rfid_count_session_id for row in _dq_check(
        spark, "rcs_calendar_orphan"
    ).collect()] == ["S-CALENDAR"]

    sold = "https://ref.gs1.org/cbv/Disp-retail_sold"
    events = [
        _event("SOLD-CHECKOUT", "item-checkout", TS(2026, 8, 17, 10),
               store_zone_sk=11, store_zone_id="Z-CHECKOUT", disposition_uri=sold),
        _event("SOLD-PORTAL", "item-portal", TS(2026, 8, 17, 10, 1),
               store_zone_sk=12, store_zone_id="Z-ENTRANCE", disposition_uri=sold),
        _event("SOLD-AISLE", "item-aisle", TS(2026, 8, 17, 10, 2),
               store_zone_sk=13, store_zone_id="Z-AISLE", disposition_uri=sold),
    ]
    zones = [
        {"store_zone_sk": 11, "store_zone_id": "Z-CHECKOUT", "store_id": "S1",
         "zone_code": "checkout", "zone_type": "queue"},
        {"store_zone_sk": 12, "store_zone_id": "Z-ENTRANCE", "store_id": "S1",
         "zone_code": "entrance", "zone_type": "entrance"},
        {"store_zone_sk": 13, "store_zone_id": "Z-AISLE", "store_id": "S1",
         "zone_code": "aisle", "zone_type": "aisle"},
    ]
    _table(spark, EVENT_DDL, events, "rfid_read_event")
    _table(spark, ZONE_DDL, zones, "store_zone")
    violations = {
        row.rfid_read_event_id
        for row in _dq_check(spark, "rre_retail_sold_context").collect()
    }
    assert violations == {"SOLD-AISLE"}


def test_device_health_keeps_silent_rfid_readers_and_null_observation_kpis(spark):
    event = _event("RFID-EVENT", "item-1", TS(2026, 8, 17, 10))
    devices = [
        {"sensor_device_sk": 21, "sensor_device_id": "D-FIXED", "store_id": "S1",
         "device_type": "rfid_reader", "device_status": "active",
         "sensing_deployment_sk": 31, "sensing_deployment_id": "DEP-RFID",
         "effective_from_date": D(2026, 1, 1), "is_current": True},
        {"sensor_device_sk": 22, "sensor_device_id": "D-ZERO", "store_id": "S1",
         "device_type": "rfid_reader", "device_status": "active",
         "sensing_deployment_sk": 31, "sensing_deployment_id": "DEP-RFID",
         "effective_from_date": D(2026, 1, 1), "is_current": True},
    ]
    deployment = {
        "sensing_deployment_sk": 31,
        "sensing_deployment_id": "DEP-RFID",
        "effective_from_date": D(2026, 1, 1),
        "is_current": True,
    }
    _table(spark, REPORT_DDL, [], "sensor_report_interval")
    _table(spark, TRAFFIC_DETAIL_DDL, [], "foot_traffic_interval_detail")
    _table(spark, EVENT_DDL, [event], "rfid_read_event")
    _table(spark, DEVICE_DDL, devices, "sensor_device")
    _table(spark, DEPLOYMENT_DDL, [deployment], "sensing_deployment")
    # Device health is a whole-estate union. RFID fixtures need the Smart Shelf
    # branches' real empty schemas even when the test has no ESL acknowledgements.
    _table(spark, ESL_LABEL_DDL, [], "esl_label")
    _table(spark, ESL_PRICE_OBSERVATION_DDL, [], "esl_price_observation")
    _gold(spark, "gold_css_device_health")

    event_row = spark.sql(
        "SELECT observations_expected, observations_received, source_message_count "
        "FROM gold_css_device_health "
        "WHERE sensor_device_id = 'D-FIXED' AND trading_date = DATE'2026-08-17'"
    ).first()
    assert event_row.observations_expected is None
    assert event_row.observations_received is None
    assert event_row.source_message_count == 3

    silent = spark.sql(
        "SELECT intervals_reported, observations_expected, observations_received, "
        "source_message_count, session_count FROM gold_css_device_health "
        "WHERE sensor_device_id = 'D-ZERO'"
    ).first()
    assert silent is not None
    assert silent.intervals_reported == 0
    assert silent.observations_expected is None
    assert silent.observations_received is None
    assert silent.source_message_count == 0
    assert silent.session_count == 0
