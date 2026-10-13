"""Executable fixtures for the Connected Store Signals gold views (Foot Traffic).

Spark — the same engine Databricks runs — executes the REAL gold SQL verbatim against
temp-view fixtures. The static tests in test_connected_store_signals.py prove the SQL is
shaped correctly; these prove it COMPUTES correctly, which is where this domain actually
bites: every wrong answer here is a plausible number, not an error.

The fixture is built from the DDL rather than a hand-written column list. The shared
sensor_report_interval envelope and its one-to-one foot_traffic_interval_detail extension
are derived separately, while each test row remains a readable sparse dict.

The four behaviours under test, each the subject of a documented trap:

  1. LEVEL PURITY — the store view must read only aggregation_level = 'site' and the zone
     view only 'area'. A shopper crossing five zones is counted five times, so summing zone
     rows into a store total inflates it silently.
  2. OCCUPANCY — peak occupancy is a MAX and average occupancy is DURATION-WEIGHTED. An
     unweighted AVG() of per-interval averages is wrong whenever intervals differ in length.
  3. DWELL — the average is SUM(seconds) / SUM(count), not AVG(of per-interval averages).
     Those differ whenever the observation counts differ, which is always.
  4. PRODUCTIVITY — sales and units per entry are valid; conversion is not exposed until
     ORDM has a canonical transaction or receipt count.
  5. DISCLOSURE — operational views retain valid zero and below-k observations; only the
     explicitly shared views suppress them, with every dependent measure suppressed too.
"""
import datetime as dt
import decimal
import os
import re

import pytest

from tools.ordm_config import view_select_body
from tools.ordm_ddl.parser import parse_table_sql

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PKG = os.path.join(REPO, "outcome-packages", "connected-store-signals")
CMN = os.path.join(REPO, "outcome-packages", "commerce-media-networks")

FACT_DDL = os.path.join(PKG, "tables", "sensor_report_interval.sql")
DETAIL_DDL = os.path.join(PKG, "tables", "foot_traffic_interval_detail.sql")
ZONE_DDL = os.path.join(PKG, "tables", "store_zone.sql")
DEVICE_DDL = os.path.join(PKG, "tables", "sensor_device.sql")
DEPLOY_DDL = os.path.join(PKG, "tables", "sensing_deployment.sql")
POLICY_DDL = os.path.join(PKG, "tables", "sensing_disclosure_policy.sql")
ACTUATOR_DDL = os.path.join(PKG, "tables", "actuator_capability.sql")
RULE_DDL = os.path.join(PKG, "tables", "evaluation_rule.sql")
ACTION_DDL = os.path.join(PKG, "tables", "automation_action.sql")
EXECLOG_DDL = os.path.join(PKG, "tables", "execution_log.sql")
TAGGED_ITEM_DDL = os.path.join(PKG, "tables", "tagged_item.sql")
RFID_EVENT_DDL = os.path.join(PKG, "tables", "rfid_read_event.sql")
RFID_SESSION_DDL = os.path.join(PKG, "tables", "rfid_count_session.sql")
ESL_LABEL_DDL = os.path.join(PKG, "tables", "esl_label.sql")
ESL_PRICE_OBSERVATION_DDL = os.path.join(PKG, "tables", "esl_price_observation.sql")
SHELF_POSITION_ASSIGNMENT_DDL = os.path.join(PKG, "tables", "shelf_position_assignment.sql")
SHELF_STATE_OBSERVATION_DDL = os.path.join(PKG, "tables", "shelf_state_observation.sql")
ESL_LABEL_ASSIGNMENT_DDL = os.path.join(PKG, "tables", "esl_label_assignment.sql")
RELATIONSHIPS_SQL = os.path.join(PKG, "relationships.sql")

_FQN_RE = re.compile(r"\$\{catalog\}\.\$\{\w+_schema\}\.(\w+)")


def _to_temp_views(sql):
    """Rewrite every `${catalog}.${x_schema}.t` to the bare temp-view name `t`.

    Done by pattern rather than an explicit table list on purpose: a new table reference
    in a view or a check then fails with "table not found" (which names the missing
    fixture) instead of a parse error on a half-substituted three-part name."""
    return _FQN_RE.sub(r"\1", sql)

# fiscal_calendar and sales are canonical-core tables, so their fixture columns are the
# few the CSS views actually read — deliberately narrow, to keep the coupling visible.
_CALENDAR = ("date_sk long, date_key date, fiscal_year int, fiscal_period int, "
             # fiscal_week_id is INT (fiscal_year * 100 + fiscal_week), matching
             # canonical-core/calendar/tables/fiscal_calendar.sql. It was STRING here, so the
             # executable tests never exercised the real type of a column the gold views
             # project and sample-queries.sql filters on with an integer literal.
             "fiscal_week int, fiscal_week_id int, fiscal_week_index int, "
             "day_of_week int, is_holiday boolean")
_SALES = ("sales_id string, date_key date, store_id string, product_id string, "
          "units int, gross_revenue double, net_revenue double, discount_amount double, "
          "currency_code string, promo_id string")

D = dt.date


def TS(*parts):
    """A UTC INSTANT, not a naive local datetime.

    PySpark converts a naive Python datetime using the SYSTEM timezone, so a bare
    datetime(2026, 3, 2, 9, 0) means 09:00 in whatever zone the developer's machine is set
    to — the fixture would then encode a different instant on a colleague's laptop and on
    CI, and every epoch-derived grain key would disagree. Making the value tz-aware pins
    the instant, which is the same discipline the model itself imposes on this column."""
    return dt.datetime(*parts, tzinfo=dt.timezone.utc)


_DDL_CACHE = {}


def _ddl(path):
    if path not in _DDL_CACHE:
        parsed = parse_table_sql(open(path).read())
        _DDL_CACHE[path] = {c["name"]: c["sql_type"] for c in parsed["columns"]}
    return _DDL_CACHE[path]


def _type_of(path, col):
    return _ddl(path)[col]


def _coerce(sql_type, value):
    """Spark's DECIMAL verifier rejects a bare float, so a DECIMAL fixture value has to
    arrive as a Decimal. Done here rather than at every call site, so a fixture can stay
    readable and a type change in the DDL cannot leave a stale literal behind."""
    if value is None:
        return None
    if sql_type.upper().startswith(("DECIMAL", "NUMERIC")):
        return decimal.Decimal(str(value))
    return value


def _view_table(spark, path, dicts, name, skip=()):
    """Register a temp view from sparse dicts, in DDL column order, NULL-filling the rest.
    The schema is DERIVED from the DDL, so a renamed or retyped column fails here loudly
    instead of leaving the fixture testing a shape the model no longer has."""
    types = _ddl(path)
    cols = [c for c in types if c not in skip]
    for d in dicts:
        unknown = set(d) - set(cols)
        assert not unknown, (
            f"fixture sets columns absent from {os.path.basename(path)}: {sorted(unknown)}")
    rows = [tuple(_coerce(types[c], d.get(c)) for c in cols) for d in dicts]
    schema = ", ".join(f"{c} {types[c]}" for c in cols)
    spark.createDataFrame(rows, schema).createOrReplaceTempView(name)


def _create_view(spark, name, path):
    body = _to_temp_views(view_select_body(open(path).read()))
    spark.sql(f"CREATE OR REPLACE TEMP VIEW {name} AS " + body)


def _metric_expr(filename, measure):
    """Return one authored metric-view measure expression for Spark execution."""
    text = open(os.path.join(PKG, "metric-views", filename)).read()
    match = re.search(
        rf"^  - name:\s*{re.escape(measure)}\s*$\n"
        rf"^\s+expr:\s*(.+)$",
        text,
        re.M,
    )
    assert match, f"{filename} has no measure named {measure}"
    return match.group(1)


def _build_interval_tables(spark, rows):
    """Split readable combined fixtures across the envelope and traffic extension.

    The helper rejects fields owned by neither table. This preserves the old fixture's
    useful column-drift detection while enforcing the revised 1:1 schema boundary.
    """
    core_columns = set(_ddl(FACT_DDL))
    detail_columns = set(_ddl(DETAIL_DDL)) - {"sensor_report_interval_sk"}
    allowed = core_columns | detail_columns
    for row in rows:
        unknown = set(row) - allowed
        assert not unknown, f"interval fixture fields belong to neither table: {sorted(unknown)}"

    core_rows = [{k: v for k, v in row.items() if k in core_columns} for row in rows]
    _view_table(
        spark, FACT_DDL, core_rows, "_sri_unkeyed",
        skip=("sensor_report_interval_sk",),
    )
    core_projection = [c for c in _ddl(FACT_DDL) if c != "sensor_report_interval_sk"]
    spark.sql(
        "CREATE OR REPLACE TEMP VIEW sensor_report_interval AS SELECT "
        "xxhash64(sensor_report_interval_id) AS sensor_report_interval_sk, "
        + ", ".join(core_projection) + " FROM _sri_unkeyed"
    )

    # Only a space-scoped count carries the Foot Traffic extension. The shared
    # envelope also supports item/object counts for RFID and Smart Shelf, which
    # deliberately have no traffic semantics.
    count_rows = [
        row for row in rows
        if row["report_type"] == "gs1:Count" and row["subject_type"] == "space"
    ]
    detail_types = _ddl(DETAIL_DDL)
    detail_projection = [
        c for c in detail_types if c != "sensor_report_interval_sk"
    ]
    detail_values = [
        tuple(
            [row["sensor_report_interval_id"]]
            + [_coerce(detail_types[c], row.get(c)) for c in detail_projection]
        )
        for row in count_rows
    ]
    detail_schema = (
        "sensor_report_interval_id string, "
        + ", ".join(f"{c} {detail_types[c]}" for c in detail_projection)
    )
    spark.createDataFrame(detail_values, detail_schema).createOrReplaceTempView(
        "_ftid_unkeyed"
    )
    spark.sql(
        "CREATE OR REPLACE TEMP VIEW foot_traffic_interval_detail AS SELECT "
        "xxhash64(sensor_report_interval_id) AS sensor_report_interval_sk, "
        + ", ".join(detail_projection) + " FROM _ftid_unkeyed"
    )


# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

# Two intervals on 2026-03-02 for STR-1, at BOTH levels, plus a decoy temperature row.
#
# The site rows are 60 and 30 minutes long and carry DIFFERENT average occupancies, which
# is what makes the duration-weighted average distinguishable from a plain AVG():
#   weighted   = (10*60 + 40*30) / 90 = 20.0
#   unweighted = (10 + 40) / 2        = 25.0
# Dwell likewise: 600s/10 obs and 900s/5 obs give SUM/SUM = 100s, but AVG-of-avgs = 120s.
#
# The durable ids are written out in full rather than derived, so sri_grain_key_wellformed
# is actually testing something: it reconstructs the key from the columns, and a fixture
# that built its id the same way would make the check tautological. Note the timestamp
# component is Spark's CAST(ts AS STRING) form ("2026-03-02 09:00:00"), which is what the
# check compares against.
_SITE_A = dict(
    sensor_report_interval_id="space|STR-1|gs1:Count|site|60|1772442000|_ALL",
    subject_type="space", subject_id="STR-1", store_sk=1, store_id="STR-1",
    report_type="gs1:Count", aggregation_level="site",
    interval_start_ts=TS(2026, 3, 2, 9, 0), interval_end_ts=TS(2026, 3, 2, 10, 0),
    interval_minutes=60, store_timezone="America/New_York", utc_offset_minutes=-300,
    trading_date=D(2026, 3, 2), hour_of_day=4, day_part="morning",
    footfall_count=100, entry_count=100, exit_count=95,
    visitor_count_raw=110, staff_count=10, visitor_count_adjusted=100, child_count=8,
    staff_adjustment_applied=True, staff_exclusion_enabled=True,
    staff_exclusion_method="patterned_tag", staff_exclusion_stage="at_aggregation",
    staff_exclusion_grade="high",
    counting_unit="person", group_counting_enabled=False, unique_visitor_enabled=False,
    child_counting_enabled=True, child_height_threshold_cm=130,
    directionality="bidirectional", passby_convention="excludes_entrants",
    occupancy_snapshot_end=15, occupancy_min=5, occupancy_max=30, occupancy_avg=10.0,
    dwell_seconds_total=600, dwell_count=10,
    time_mode="within_operating_hours", measurement_validity="valid",
    arrival_completeness="complete", is_imputed=False, is_zero_observed=False,
    uptime_ratio=1.0, coverage_ratio=1.0,
    source_observation_count=60, expected_observation_count=60,
    source_session_id="SESSION-SITE", source_message_count=60,
    sequence_gap_count=0, duplicate_delivery_count=0,
    historical_message_count=0, bad_quality_message_count=0,
    sensor_device_id="_ALL",
    sensing_deployment_sk=1, sensing_deployment_id="DEP-1",
    ingest_timestamp=TS(2026, 3, 2, 10, 5), latency_seconds=300,
    record_source="test", load_timestamp=TS(2026, 3, 2, 10, 5),
)
_SITE_B = dict(
    _SITE_A,
    sensor_report_interval_id="space|STR-1|gs1:Count|site|30|1772445600|_ALL",
    interval_start_ts=TS(2026, 3, 2, 10, 0), interval_end_ts=TS(2026, 3, 2, 10, 30),
    interval_minutes=30,
    footfall_count=50, entry_count=50, exit_count=48,
    visitor_count_raw=55, staff_count=5, visitor_count_adjusted=50, child_count=4,
    occupancy_snapshot_end=12, occupancy_min=8, occupancy_max=22, occupancy_avg=40.0,
    dwell_seconds_total=900, dwell_count=5,
    source_observation_count=30, expected_observation_count=30,
    source_message_count=30,
)
# Invalid measurements stay in quality denominators but never enter traffic totals.
_SITE_INVALID = dict(
    _SITE_B,
    sensor_report_interval_id="space|STR-1|gs1:Count|site|30|1772447400|_ALL",
    interval_start_ts=TS(2026, 3, 2, 10, 30),
    interval_end_ts=TS(2026, 3, 2, 11, 0),
    footfall_count=777,
    entry_count=777,
    exit_count=770,
    visitor_count_raw=777,
    visitor_count_adjusted=777,
    staff_count=0,
    child_count=0,
    measurement_validity="invalid",
)
# An AREA row for the same store-day. Its footfall (999) is deliberately absurd relative
# to the site total: if it ever leaks into the store view, the assertion fails loudly
# instead of being absorbed into a plausible-looking sum.
_AREA = dict(
    _SITE_A,
    sensor_report_interval_id="space|ZN-GROCERY|gs1:Count|area|60|1772442000|DEV-1",
    subject_id="ZN-GROCERY",
    aggregation_level="area", store_zone_sk=10, store_zone_id="ZN-GROCERY",
    footfall_count=999, entry_count=999, exit_count=990, passersby_count=1500,
    visitor_count_raw=None, visitor_count_adjusted=None, staff_count=None, child_count=None,
    staff_adjustment_applied=None,
    occupancy_max=44, occupancy_avg=12.0,
    dwell_seconds_total=1200, dwell_count=8,
    engaged_count=6, passing_count=2, engagement_threshold_seconds=30,
    sensor_device_sk=1, sensor_device_id="DEV-1",
)
# A temperature row: the sparsity control. It must be invisible to every traffic view.
_TEMP = dict(
    sensor_report_interval_id="point|EQ-1|gs1:Temperature|subject|60|1772442000|DEV-2",
    subject_type="point", subject_id="EQ-1", store_sk=1, store_id="STR-1",
    report_type="gs1:Temperature", aggregation_level="subject",
    interval_start_ts=TS(2026, 3, 2, 9, 0), interval_end_ts=TS(2026, 3, 2, 10, 0),
    interval_minutes=60, store_timezone="America/New_York", utc_offset_minutes=-300,
    trading_date=D(2026, 3, 2),
    value=4.5, min_value=3.9, max_value=5.2, mean_value=4.5,
    uom="CEL", unit_iri="http://qudt.org/vocab/unit/DEG_C",
    measurement_validity="valid", arrival_completeness="complete",
    uptime_ratio=1.0, coverage_ratio=1.0,
    source_observation_count=60, expected_observation_count=60,
    source_session_id="SESSION-TEMP", source_message_count=60,
    sequence_gap_count=0, duplicate_delivery_count=0,
    historical_message_count=0, bad_quality_message_count=0,
    sensor_device_sk=2, sensor_device_id="DEV-2",
    sensing_deployment_sk=1, sensing_deployment_id="DEP-1",
    ingest_timestamp=TS(2026, 3, 2, 10, 5), latency_seconds=300,
    record_source="test", load_timestamp=TS(2026, 3, 2, 10, 5),
    equipment_sk=1, equipment_id="EQ-1",
)
# A HUMIDITY row from the SAME probe, same asset, same interval. Combination probes are
# ordinary hardware, and this row exists to pin the device-health grain: with report_type
# outside the grouping, DEV-2's two measurements collapsed into one device-day whose
# intervals_reported was 2 and whose uptime averaged a temperature reading against a
# humidity one. The numbers stayed plausible, which is why only a duplicate-key assertion
# finds it. Its uptime is deliberately different from the temperature row's so a collapse
# shows up as a changed value rather than only as a changed row count.
_HUMID = dict(
    _TEMP,
    sensor_report_interval_id="point|EQ-1|gs1:RelativeHumidity|subject|60|1772442000|DEV-2",
    report_type="gs1:RelativeHumidity",
    value=62.0, min_value=58.0, max_value=66.0, mean_value=62.0,
    uom="P1", unit_iri="http://qudt.org/vocab/unit/PERCENT",
    uptime_ratio=0.5,
    source_observation_count=30, expected_observation_count=60,
    source_message_count=30,
)
# A measured zero in a quiet zone. Operational truth stays complete; the explicitly
# shared projection applies zero and dependent-measure suppression after daily aggregation.
_AREA_QUIET = dict(
    _AREA,
    sensor_report_interval_id="space|ZN-FLOWERS|gs1:Count|area|60|1772449200|DEV-1",
    subject_id="ZN-FLOWERS",
    interval_start_ts=TS(2026, 3, 2, 11, 0), interval_end_ts=TS(2026, 3, 2, 12, 0),
    store_zone_sk=11, store_zone_id="ZN-FLOWERS",
    footfall_count=0, entry_count=0, exit_count=0, passersby_count=4,
    unique_visitor_count=0, is_zero_observed=True,
    occupancy_snapshot_end=0, occupancy_min=0, occupancy_max=0, occupancy_avg=0.0,
    dwell_seconds_total=0, dwell_count=0, engaged_count=0, passing_count=0,
    cumulative_entries=0, cumulative_exits=0,
    visitor_count_raw=None, visitor_count_adjusted=None, staff_count=None, child_count=None,
)


def _build(spark):
    # The fact _sk and the extension FK are both derived from the durable id in Spark,
    # exactly as ADR 0028 requires.
    _build_interval_tables(
        spark,
        [_SITE_A, _SITE_B, _SITE_INVALID, _AREA, _AREA_QUIET, _TEMP, _HUMID],
    )

    # The site zone exists so the two area zones' parent_zone_id resolves. Without it
    # sz_parent_resolves_current fires — which is the check doing its job, since a zone
    # whose parent is missing cannot be rolled up.
    _view_table(spark, ZONE_DDL, [
        dict(store_zone_sk=1, store_zone_id="ZN-SITE", store_sk=1, store_id="STR-1",
             zone_code="SITE", zone_name="Store", zone_type="site",
             hierarchy_depth=0, hierarchy_path="/site",
             area_sqm=1000.0, capacity_persons=400, is_sales_floor=True, is_countable=True,
             effective_from_date=D(2025, 1, 1), is_current=True,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
        dict(store_zone_sk=10, store_zone_id="ZN-GROCERY", store_sk=1, store_id="STR-1",
             zone_code="GROCERY", zone_name="Grocery", zone_type="area",
             parent_zone_sk=1, parent_zone_id="ZN-SITE",
             hierarchy_depth=1, hierarchy_path="/site/area-grocery",
             area_sqm=200.0, capacity_persons=80, is_sales_floor=True, is_countable=True,
             effective_from_date=D(2025, 1, 1), is_current=True,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
        dict(store_zone_sk=11, store_zone_id="ZN-FLOWERS", store_sk=1, store_id="STR-1",
             zone_code="FLOWERS", zone_name="Flowers", zone_type="area",
             parent_zone_sk=1, parent_zone_id="ZN-SITE",
             hierarchy_depth=1, hierarchy_path="/site/area-flowers",
             area_sqm=40.0, capacity_persons=15, is_sales_floor=True, is_countable=True,
             effective_from_date=D(2025, 1, 1), is_current=True,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
    ], "store_zone")

    _view_table(spark, POLICY_DDL, [
        dict(
            sensing_disclosure_policy_sk=1,
            sensing_disclosure_policy_id="external_default",
            audience_code="external",
            k_threshold=10,
            suppress_zero_flag=True,
            minimum_interval_minutes=15,
            effective_from_date=D(2024, 1, 1),
            is_current=True,
            policy_basis="aggregate disclosure policy",
            record_source="test",
            load_timestamp=TS(2026, 3, 2, 0, 0),
        ),
    ], "sensing_disclosure_policy")

    _view_table(spark, DEPLOY_DDL, [
        dict(sensing_deployment_sk=1, sensing_deployment_id="DEP-1",
             store_sk=1, store_id="STR-1",
             deployment_name="Front-of-store thermal counters",
             sensing_method_code="thermal", sensing_purpose_code="people_counting",
             lawful_basis_code="legitimate_interest", jurisdiction_code="US-IL",
             dpia_completed_flag=True, dpia_reference="DPIA-2025-01",
             dpia_covers_employees_flag=True, dpia_review_due_date=D(2027, 1, 1),
             signage_posted_flag=True, ai_act_notice_status="not_applicable",
             works_council_consulted_flag=True, consultation_reference="WC-2025-01",
             consent_required_flag="not_required", optout_mechanism_code="signage_contact",
             retention_days_max=30, retention_basis="policy: aggregate-only, ADR 0029",
             staff_exclusion_method="patterned_tag", staff_exclusion_stage="at_aggregation",
             external_disclosure_policy_sk=1,
             external_disclosure_policy_id="external_default",
             deployment_status="active", deployed_date=D(2025, 1, 1),
             effective_from_date=D(2025, 1, 1), is_current=True,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
    ], "sensing_deployment")

    # DEV-2 is a buffered vaccine-storage probe whose calibration has LAPSED. It is parked
    # in `maintenance` rather than `active` because that is the honest state for an
    # out-of-calibration device — and sd_calibration_current warns on exactly the
    # active-and-lapsed combination, so leaving it active would (correctly) flag.
    _view_table(spark, DEVICE_DDL, [
        dict(sensor_device_sk=1, sensor_device_id="DEV-1", store_sk=1, store_id="STR-1",
             store_zone_sk=10, store_zone_id="ZN-GROCERY",
             device_type="people_counter", sensing_technology="thermal", device_role="sense",
             manufacturer="Acme", model="TC-100", firmware_version="2.1.0",
             is_directional=True, supports_dwell=True, supports_occupancy=True,
             sensing_deployment_sk=1, sensing_deployment_id="DEP-1", device_status="active",
             installed_date=D(2025, 1, 1),
             calibration_valid_from=D(2025, 1, 1), calibration_valid_to=D(2027, 1, 1),
             accuracy_tolerance=0.5, probe_type="none", is_backup_device=False,
             bacnet_out_of_service=False, battery_powered=False,
             effective_from_date=D(2025, 1, 1), is_current=True,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
        dict(sensor_device_sk=2, sensor_device_id="DEV-2", store_sk=1, store_id="STR-1",
             device_type="temperature", sensing_technology="thermistor", device_role="sense",
             manufacturer="Acme", model="TP-10", firmware_version="1.0.0",
             is_directional=False, supports_dwell=False, supports_occupancy=False,
             sensing_deployment_sk=1, sensing_deployment_id="DEP-1",
             device_status="maintenance", installed_date=D(2025, 1, 1),
             equipment_sk=1, equipment_id="EQ-1",
             calibration_valid_from=D(2025, 1, 1), calibration_valid_to=D(2026, 3, 10),
             accuracy_tolerance=0.5, probe_type="buffered", is_backup_device=False,
             bacnet_out_of_service=False, battery_powered=True,
             effective_from_date=D(2025, 1, 1), is_current=True,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
    ], "sensor_device")

    # Calendar: the current day plus the prior-year same-fiscal-week/day row, so the PY
    # comparison in the store view actually resolves rather than silently returning NULL.
    spark.createDataFrame([
        (1, D(2026, 3, 2), 2026, 3, 5, 202605, 5, 2, False),
        (2, D(2025, 3, 3), 2025, 3, 5, 202505, 5, 2, False),
    ], _CALENDAR).createOrReplaceTempView("fiscal_calendar")

    spark.createDataFrame([
        ("S1", D(2026, 3, 2), "STR-1", "SKU-1", 60, 900.0, 750.0, 150.0, "USD", "PROMO-1"),
        ("S2", D(2026, 3, 2), "STR-1", "SKU-2", 30, 400.0, 350.0, 50.0, "USD", "NO_PROMO"),
    ], _SALES).createOrReplaceTempView("sales")

    # Device health unions RFID-reader and ESL-gateway telemetry. Foot Traffic fixtures
    # need no rows from either branch, but analysis still requires their real schemas.
    _view_table(spark, TAGGED_ITEM_DDL, [], "tagged_item")
    _view_table(spark, RFID_SESSION_DDL, [], "rfid_count_session")
    _view_table(spark, RFID_EVENT_DDL, [], "rfid_read_event")
    _view_table(spark, ESL_LABEL_DDL, [], "esl_label")
    _view_table(spark, ESL_PRICE_OBSERVATION_DDL, [], "esl_price_observation")

    _create_view(spark, "gold_store_traffic_daily_current",
                 os.path.join(PKG, "gold", "gold_store_traffic_daily_current.sql"))
    _create_view(spark, "gold_zone_traffic_current",
                 os.path.join(PKG, "gold", "gold_zone_traffic_current.sql"))
    _create_view(spark, "gold_store_traffic_daily_shared",
                 os.path.join(PKG, "gold", "gold_store_traffic_daily_shared.sql"))
    _create_view(spark, "gold_zone_traffic_shared",
                 os.path.join(PKG, "gold", "gold_zone_traffic_shared.sql"))
    _create_view(spark, "gold_zone_traffic_interval_shared",
                 os.path.join(PKG, "gold", "gold_zone_traffic_interval_shared.sql"))
    _create_view(spark, "gold_traffic_sales_productivity_current",
                 os.path.join(PKG, "gold", "gold_traffic_sales_productivity_current.sql"))
    _create_view(spark, "gold_css_device_health",
                 os.path.join(PKG, "gold", "gold_css_device_health.sql"))
    _create_view(spark, "store_zone_interval",
                 os.path.join(CMN, "gold", "store_zone_interval.sql"))


# ---------------------------------------------------------------------------
# 1. Level purity
# ---------------------------------------------------------------------------

def test_store_view_reads_site_rows_only(spark):
    """The area row carries footfall 999. If the view mixed levels the total would be
    1149 rather than 150, and nothing about that number looks wrong from the outside."""
    _build(spark)
    r = spark.sql("SELECT * FROM gold_store_traffic_daily_current WHERE store_id = 'STR-1'").collect()
    assert len(r) == 1, f"expected one store-day row, got {len(r)}"
    assert r[0].footfall_count == 150, (
        f"expected 100 + 50 from the two SITE intervals, got {r[0].footfall_count} — "
        "an area row or the temperature row leaked into the store total")
    assert r[0].aggregation_level == "site"


def test_zone_view_reads_area_rows_only(spark):
    _build(spark)
    rows = {r.store_zone_id: r for r in spark.sql("SELECT * FROM gold_zone_traffic_current").collect()}
    assert set(rows) == {"ZN-GROCERY", "ZN-FLOWERS"}
    assert rows["ZN-GROCERY"].footfall_count == 999
    assert all(r.aggregation_level == "area" for r in rows.values())


def test_temperature_rows_are_invisible_to_traffic_views(spark):
    """ADR 0032's first containment control, checked end-to-end: one wide fact is only
    safe if the traffic views are pinned to report_type = 'gs1:Count'."""
    _build(spark)
    total = spark.sql("SELECT SUM(footfall_count) AS n FROM gold_store_traffic_daily_current").first().n
    assert total == 150
    zone_total = spark.sql("SELECT SUM(footfall_count) AS n FROM gold_zone_traffic_current").first().n
    assert zone_total == 999, "the temperature row contributed to a footfall total"


def test_invalid_interval_is_excluded_from_measures_but_kept_in_quality_denominator(spark):
    _build(spark)
    row = spark.sql(
        "SELECT footfall_count, interval_count, valid_interval_share "
        "FROM gold_store_traffic_daily_current"
    ).first()
    assert row.footfall_count == 150, "the invalid count leaked into the operational total"
    assert row.interval_count == 3
    assert float(row.valid_interval_share) == pytest.approx(2 / 3)


# ---------------------------------------------------------------------------
# 2. Occupancy
# ---------------------------------------------------------------------------

def test_peak_occupancy_is_a_max_not_a_sum(spark):
    _build(spark)
    r = spark.sql("SELECT peak_occupancy FROM gold_store_traffic_daily_current").first()
    assert r.peak_occupancy == 30, (
        f"peak occupancy must be MAX(30, 22) = 30, got {r.peak_occupancy} "
        "(52 would mean the view summed a semi-additive measure)")


def test_average_occupancy_is_duration_weighted(spark):
    """(10*60 + 40*30) / 90 = 20.0. An unweighted AVG() would give 25.0 — a 25% error
    from nothing more than two intervals of different length."""
    _build(spark)
    r = spark.sql("SELECT avg_occupancy FROM gold_store_traffic_daily_current").first()
    assert r.avg_occupancy == pytest.approx(20.0), (
        f"expected the duration-weighted 20.0, got {r.avg_occupancy} "
        "(25.0 means the view used AVG() of per-interval averages)")


# ---------------------------------------------------------------------------
# 3. Dwell
# ---------------------------------------------------------------------------

def test_average_dwell_is_sum_over_count(spark):
    """(600 + 900) / (10 + 5) = 100s. AVG of the per-interval averages (60s and 180s)
    would give 120s, because it weights a 5-observation interval like a 10-observation one."""
    _build(spark)
    r = spark.sql("SELECT avg_dwell_seconds, dwell_seconds_total, dwell_count "
                  "FROM gold_store_traffic_daily_current").first()
    assert r.dwell_seconds_total == 1500 and r.dwell_count == 15
    assert r.avg_dwell_seconds == pytest.approx(100.0), (
        f"expected SUM/SUM = 100.0s, got {r.avg_dwell_seconds} (120.0 means AVG-of-averages)")


def test_zone_engagement_rate_uses_dwell_count_denominator(spark):
    _build(spark)
    r = spark.sql("SELECT engagement_rate FROM gold_zone_traffic_current "
                  "WHERE store_zone_id = 'ZN-GROCERY'").first()
    assert r.engagement_rate == pytest.approx(6 / 8)


def test_zone_density_uses_the_zone_dimension(spark):
    """The density denominators come from store_zone, which is exactly what the bare
    store_zone_code string on the retired CMN fact could not provide."""
    _build(spark)
    r = spark.sql("SELECT footfall_per_sqm, peak_capacity_utilisation FROM gold_zone_traffic_current "
                  "WHERE store_zone_id = 'ZN-GROCERY'").first()
    # area_sqm is DECIMAL, so the ratio comes back as a Decimal — cast rather than compare
    # across numeric types.
    assert float(r.footfall_per_sqm) == pytest.approx(999 / 200.0)
    assert float(r.peak_capacity_utilisation) == pytest.approx(44 / 80.0)


def test_zone_day_consolidates_scd2_versions_and_weights_area_by_duration(spark):
    """A mid-day refit changes area from 200 to 100 sqm.

    The two 60-minute facts point to their exact dimension versions. The serving
    result must remain one durable zone-day with effective area 150 sqm, rather
    than duplicating the day or applying today's layout to both intervals.
    """
    after_refit = dict(
        _AREA,
        sensor_report_interval_id=(
            "space|ZN-GROCERY|gs1:Count|area|60|1772445600|DEV-1"
        ),
        interval_start_ts=TS(2026, 3, 2, 10, 0),
        interval_end_ts=TS(2026, 3, 2, 11, 0),
        store_zone_sk=12,
        footfall_count=101,
        entry_count=101,
        exit_count=100,
    )
    _build_interval_tables(spark, [_AREA, after_refit])
    _view_table(spark, ZONE_DDL, [
        dict(
            store_zone_sk=10, store_zone_id="ZN-GROCERY",
            store_sk=1, store_id="STR-1", zone_code="GROCERY",
            zone_name="Grocery before refit", zone_type="area",
            hierarchy_depth=1, hierarchy_path="/site/area-grocery",
            area_sqm=200.0, capacity_persons=80,
            is_sales_floor=True, is_countable=True,
            effective_from_date=D(2025, 1, 1),
            effective_to_date=D(2026, 3, 2), is_current=False,
            record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0),
        ),
        dict(
            store_zone_sk=12, store_zone_id="ZN-GROCERY",
            store_sk=1, store_id="STR-1", zone_code="GROCERY",
            zone_name="Grocery after refit", zone_type="area",
            hierarchy_depth=1, hierarchy_path="/site/area-grocery",
            area_sqm=100.0, capacity_persons=50,
            is_sales_floor=True, is_countable=True,
            effective_from_date=D(2026, 3, 2), is_current=True,
            record_source="test", load_timestamp=TS(2026, 3, 2, 10, 0),
        ),
    ], "store_zone")
    spark.createDataFrame([
        (1, D(2026, 3, 2), 2026, 3, 10, 202610, 62, 1, False),
    ], _CALENDAR).createOrReplaceTempView("fiscal_calendar")
    _create_view(
        spark,
        "gold_zone_traffic_current",
        os.path.join(PKG, "gold", "gold_zone_traffic_current.sql"),
    )

    rows = spark.sql(
        "SELECT footfall_count, area_sqm, capacity_persons, footfall_per_sqm, "
        "interval_count FROM gold_zone_traffic_current"
    ).collect()
    assert len(rows) == 1
    row = rows[0]
    assert row.footfall_count == 1100
    assert float(row.area_sqm) == pytest.approx(150.0)
    assert float(row.capacity_persons) == pytest.approx(65.0)
    assert float(row.footfall_per_sqm) == pytest.approx(1100 / 150.0)
    assert row.interval_count == 2


def test_null_quality_and_space_values_do_not_dilute_weighted_averages(spark):
    """Unknown ratios and space attributes contribute neither value nor denominator."""
    reported_site = dict(_SITE_A, coverage_ratio=0.8)
    unknown_site = dict(
        _SITE_A,
        sensor_report_interval_id=(
            "space|STR-1|gs1:Count|site|60|1772445600|_ALL"
        ),
        interval_start_ts=TS(2026, 3, 2, 10, 0),
        interval_end_ts=TS(2026, 3, 2, 11, 0),
        uptime_ratio=None,
        coverage_ratio=None,
    )
    reported_area = dict(_AREA, coverage_ratio=0.8)
    unknown_area = dict(
        _AREA,
        sensor_report_interval_id=(
            "space|ZN-GROCERY|gs1:Count|area|60|1772445600|DEV-1"
        ),
        interval_start_ts=TS(2026, 3, 2, 10, 0),
        interval_end_ts=TS(2026, 3, 2, 11, 0),
        store_zone_sk=12,
        uptime_ratio=None,
        coverage_ratio=None,
    )
    _build_interval_tables(
        spark,
        [reported_site, unknown_site, reported_area, unknown_area],
    )
    _view_table(spark, ZONE_DDL, [
        dict(
            store_zone_sk=10, store_zone_id="ZN-GROCERY",
            store_sk=1, store_id="STR-1", zone_code="GROCERY",
            zone_name="Grocery measured", zone_type="area",
            hierarchy_depth=1, hierarchy_path="/site/area-grocery",
            area_sqm=200.0, capacity_persons=80,
            is_sales_floor=True, is_countable=True,
            effective_from_date=D(2025, 1, 1), is_current=False,
            record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0),
        ),
        dict(
            store_zone_sk=12, store_zone_id="ZN-GROCERY",
            store_sk=1, store_id="STR-1", zone_code="GROCERY",
            zone_name="Grocery unknown", zone_type="area",
            hierarchy_depth=1, hierarchy_path="/site/area-grocery",
            area_sqm=None, capacity_persons=None,
            is_sales_floor=True, is_countable=True,
            effective_from_date=D(2026, 3, 2), is_current=True,
            record_source="test", load_timestamp=TS(2026, 3, 2, 10, 0),
        ),
    ], "store_zone")
    spark.createDataFrame([
        (1, D(2026, 3, 2), 2026, 3, 10, 202610, 62, 1, False),
    ], _CALENDAR).createOrReplaceTempView("fiscal_calendar")
    _create_view(
        spark,
        "gold_store_traffic_daily_current",
        os.path.join(PKG, "gold", "gold_store_traffic_daily_current.sql"),
    )
    _create_view(
        spark,
        "gold_zone_traffic_current",
        os.path.join(PKG, "gold", "gold_zone_traffic_current.sql"),
    )

    store = spark.sql(
        "SELECT avg_uptime_ratio, avg_coverage_ratio "
        "FROM gold_store_traffic_daily_current"
    ).first()
    assert float(store.avg_uptime_ratio) == pytest.approx(1.0)
    assert float(store.avg_coverage_ratio) == pytest.approx(0.8)

    zone = spark.sql(
        "SELECT avg_uptime_ratio, avg_coverage_ratio, area_sqm, capacity_persons "
        "FROM gold_zone_traffic_current"
    ).first()
    assert float(zone.avg_uptime_ratio) == pytest.approx(1.0)
    assert float(zone.avg_coverage_ratio) == pytest.approx(0.8)
    assert float(zone.area_sqm) == pytest.approx(200.0)
    assert float(zone.capacity_persons) == pytest.approx(80.0)


def test_prior_year_traffic_matches_fiscal_week_and_weekday(spark):
    """The prior-year peer is the equivalent retail trading day, not a date shift."""
    current = dict(
        _SITE_A,
        footfall_count=150,
        entry_count=150,
        exit_count=145,
        visitor_count_adjusted=150,
    )
    prior = dict(
        _SITE_A,
        sensor_report_interval_id=(
            "space|STR-1|gs1:Count|site|60|1740992400|_ALL"
        ),
        interval_start_ts=TS(2025, 3, 3, 9, 0),
        interval_end_ts=TS(2025, 3, 3, 10, 0),
        trading_date=D(2025, 3, 3),
        footfall_count=80,
        entry_count=80,
        exit_count=78,
        visitor_count_adjusted=80,
        staff_count=5,
        child_count=4,
    )
    _build_interval_tables(spark, [current, prior])
    spark.createDataFrame([
        (1, D(2026, 3, 2), 2026, 3, 5, 202605, 5, 2, False),
        (2, D(2025, 3, 3), 2025, 3, 5, 202505, 5, 2, False),
    ], _CALENDAR).createOrReplaceTempView("fiscal_calendar")
    _create_view(
        spark,
        "gold_store_traffic_daily_current",
        os.path.join(PKG, "gold", "gold_store_traffic_daily_current.sql"),
    )

    row = spark.sql(
        "SELECT footfall_count_py, footfall_delta_py, footfall_growth_py "
        "FROM gold_store_traffic_daily_current "
        "WHERE trading_date = DATE '2026-03-02'"
    ).first()
    assert row.footfall_count_py == 80
    assert row.footfall_delta_py == 70
    assert float(row.footfall_growth_py) == pytest.approx(0.875)


# ---------------------------------------------------------------------------
# 4. Traffic-sales productivity
# ---------------------------------------------------------------------------

def test_productivity_surface_does_not_publish_conversion(spark):
    _build(spark)
    columns = set(spark.table("gold_traffic_sales_productivity_current").columns)
    assert not {
        "conversion_rate",
        "conversion_numerator_basis",
        "conversion_denominator_basis",
    } & columns


def test_productivity_measures_use_entries_as_denominator(spark):
    _build(spark)
    r = spark.sql("SELECT sales_per_entry, units_per_entry, net_revenue, units "
                  "FROM gold_traffic_sales_productivity_current").first()
    assert r.net_revenue == pytest.approx(1100.0) and r.units == 90
    assert r.sales_per_entry == pytest.approx(1100.0 / 150)
    assert r.units_per_entry == pytest.approx(90 / 150)


def test_productivity_survives_non_directional_footfall_hardware(spark):
    """Non-directional counters report footfall but cannot populate entry_count."""
    from pyspark.sql import functions as F

    _build(spark)
    # Register the nulled-entry shape under the SAME name, not through an intermediate view:
    # a SQL CREATE VIEW stores its plan by name, so replacing the target with a SELECT over a
    # helper that reads the target re-resolves into a cycle Spark rejects (RECURSIVE_VIEW).
    (
        spark.table("gold_store_traffic_daily_current")
        .withColumn("entry_count", F.lit(None).cast("long"))
        .createOrReplaceTempView("gold_store_traffic_daily_current")
    )
    _create_view(
        spark,
        "gold_traffic_sales_productivity_current",
        os.path.join(PKG, "gold", "gold_traffic_sales_productivity_current.sql"),
    )

    row = spark.sql(
        "SELECT sales_per_entry, units_per_entry, sales_per_footfall, "
        "units_per_footfall, net_revenue, units, footfall_count "
        "FROM gold_traffic_sales_productivity_current"
    ).first()

    assert row.sales_per_entry is None and row.units_per_entry is None
    assert row.sales_per_footfall == pytest.approx(row.net_revenue / row.footfall_count)
    assert row.units_per_footfall == pytest.approx(row.units / row.footfall_count)


def test_promo_context_is_carried(spark):
    _build(spark)
    r = spark.sql("SELECT promo_active_flag, active_promo_count "
                  "FROM gold_traffic_sales_productivity_current").first()
    assert r.promo_active_flag is True
    assert r.active_promo_count == 1, "NO_PROMO must not count as an active promotion"


# ---------------------------------------------------------------------------
# 5. Device health
# ---------------------------------------------------------------------------

def test_device_health_excludes_the_cross_device_aggregate(spark):
    """sensor_device_id = '_ALL' is a sentinel for a cross-device aggregate, not a device.
    Counting it would inflate the fleet and attribute real uptime to a device that does
    not exist."""
    _build(spark)
    ids = {r.sensor_device_id for r in spark.sql("SELECT sensor_device_id FROM gold_css_device_health").collect()}
    assert "_ALL" not in ids
    assert ids == {"DEV-1", "DEV-2"}


def test_device_health_surfaces_calibration_expiry(spark):
    """DEV-2 is a buffered vaccine-storage probe whose calibration lapses on 2026-03-10;
    the fixture's 'today' is later, so it must read expired rather than current."""
    _build(spark)
    rows = {r.sensor_device_id: r for r in spark.sql(
        "SELECT sensor_device_id, calibration_status, probe_type FROM gold_css_device_health").collect()}
    assert rows["DEV-2"].calibration_status == "expired"
    assert rows["DEV-2"].probe_type == "buffered"
    assert rows["DEV-1"].calibration_status == "current"


def test_device_health_is_one_row_per_device_report_and_level(spark):
    """report_type and aggregation_level are part of the grain, not decoration.

    DEV-2 is a combination probe reporting temperature AND humidity over the same interval.
    The first version of this view grouped by device and trading_date alone, so those two
    measurements collapsed into a single device-day: intervals_reported read 2, the two
    uptimes were averaged into one meaningless 0.75, and observations_expected doubled. The
    same arithmetic hit every entrance counter in the estate, which emits both its own area
    rows and the store's site rows, so the headline missing_observation_rate was wrong on
    exactly the devices anyone would look at first. Nothing in the output looked wrong.
    """
    _build(spark)
    rows = spark.sql(
        "SELECT sensor_device_id, report_type, aggregation_level, intervals_reported, "
        "avg_uptime_ratio, observations_expected FROM gold_css_device_health "
        "WHERE sensor_device_id = 'DEV-2' ORDER BY report_type").collect()

    assert [(r.report_type, r.intervals_reported) for r in rows] == [
        ("gs1:RelativeHumidity", 1), ("gs1:Temperature", 1)]
    by_type = {r.report_type: r for r in rows}
    assert float(by_type["gs1:Temperature"].avg_uptime_ratio) == pytest.approx(1.0)
    assert float(by_type["gs1:RelativeHumidity"].avg_uptime_ratio) == pytest.approx(0.5)
    assert by_type["gs1:Temperature"].observations_expected == 60

    dupes = spark.sql(
        "SELECT COUNT(*) AS n FROM (SELECT sensor_device_id, trading_date, report_type, "
        "aggregation_level, COUNT(*) AS c FROM gold_css_device_health "
        "GROUP BY sensor_device_id, trading_date, report_type, aggregation_level "
        "HAVING COUNT(*) > 1)").first()
    assert dupes.n == 0


def test_source_observation_completeness_is_independent_of_footfall(spark):
    """The area device sees 999 shoppers in one interval and zero in another, but source
    completeness follows the configured cadence: 60 observations for each hour."""
    _build(spark)
    row = spark.sql(
        "SELECT observations_received, observations_expected "
        "FROM gold_css_device_health "
        "WHERE sensor_device_id = 'DEV-1' AND report_type = 'gs1:Count'"
    ).first()
    assert row.observations_received == 120
    assert row.observations_expected == 120


def test_device_attributes_resolve_as_of_the_measurement(spark):
    """The view joins sensor_device on the fact's version-specific _sk with no is_current
    predicate, per the enforced SCD2-JOIN-CONTRACT (§A.16).

    Joining on the durable id plus is_current instead would decorate a historical device-day
    with TODAY's firmware and calibration — which defeats the reason the registry is SCD2 at
    all, since mv_device_health tells a user to group by firmware_version to investigate a
    counting discontinuity. Here DEV-1 has been re-versioned: the fact points at the OLD
    version, so the old firmware is the correct answer even though a newer row exists.
    """
    _build(spark)
    from pyspark.sql import functions as F

    current = spark.table("sensor_device")
    # unionByName, not SELECT * EXCEPT: EXCEPT moves the replaced columns to the end, and a
    # positional UNION then silently pairs firmware_version with a boolean.
    newer = (current.filter("sensor_device_id = 'DEV-1'")
             .withColumn("sensor_device_sk", F.lit(99).cast("bigint"))
             .withColumn("firmware_version", F.lit("9.9.9"))
             .withColumn("effective_from_date", F.lit(dt.date(2026, 6, 1)))
             .withColumn("is_current", F.lit(True)))
    (current.withColumn("is_current", F.lit(False)).unionByName(newer)
     .createOrReplaceTempView("sensor_device"))
    _create_view(spark, "gold_css_device_health",
                 os.path.join(PKG, "gold", "gold_css_device_health.sql"))
    r = spark.sql("SELECT firmware_version FROM gold_css_device_health "
                  "WHERE sensor_device_id = 'DEV-1'").collect()
    assert {row.firmware_version for row in r} == {"2.1.0"}, (
        "device attributes resolved to the CURRENT version rather than the one in effect "
        "when the interval was measured")


def test_device_health_carries_governance_context(spark):
    _build(spark)
    r = spark.sql("SELECT dpia_completed_flag, sensing_method_code, deployment_status "
                  "FROM gold_css_device_health WHERE sensor_device_id = 'DEV-1'").first()
    assert r.dpia_completed_flag is True
    assert r.sensing_method_code == "thermal"
    assert r.deployment_status == "active"


# ---------------------------------------------------------------------------
# 6. Disclosure boundary and exact CMN compatibility contract (ADR 0033)
# ---------------------------------------------------------------------------

def test_operational_zero_is_retained_and_shared_zero_suppresses_dependent_measures(spark):
    _build(spark)
    operational = spark.sql(
        "SELECT footfall_count, passersby_count, is_zero_observed "
        "FROM gold_zone_traffic_current WHERE store_zone_id = 'ZN-FLOWERS'"
    ).first()
    assert operational.footfall_count == 0
    assert operational.passersby_count == 4
    assert operational.is_zero_observed is True

    shared = spark.sql(
        "SELECT footfall_count, passersby_count, dwell_count, "
        "disclosure_suppressed_flag FROM gold_zone_traffic_shared "
        "WHERE store_zone_id = 'ZN-FLOWERS'"
    ).first()
    assert shared.disclosure_suppressed_flag is True
    assert shared.footfall_count is None
    assert shared.passersby_count is None
    assert shared.dwell_count is None


def test_unsuppressed_shared_cell_retains_measures(spark):
    _build(spark)
    row = spark.sql(
        "SELECT footfall_count, disclosure_suppressed_flag "
        "FROM gold_zone_traffic_shared WHERE store_zone_id = 'ZN-GROCERY'"
    ).first()
    assert row.disclosure_suppressed_flag is False
    assert row.footfall_count == 999


def test_shared_views_resolve_policy_rollover_by_durable_id(spark):
    """A deployment's policy-version surrogate must not freeze disclosure controls.

    The deployment still carries v1's ``_sk`` while its durable policy id has rolled to
    v2. Every shared surface must resolve v2 for the fact date instead of silently
    dropping the row because v1's window ended.
    """
    _build(spark)
    _view_table(spark, POLICY_DDL, [
        dict(
            sensing_disclosure_policy_sk=1,
            sensing_disclosure_policy_id="external_default",
            audience_code="external",
            k_threshold=2000,
            suppress_zero_flag=True,
            minimum_interval_minutes=15,
            effective_from_date=D(2024, 1, 1),
            effective_to_date=D(2026, 3, 1),
            is_current=False,
        ),
        dict(
            sensing_disclosure_policy_sk=2,
            sensing_disclosure_policy_id="external_default",
            audience_code="external",
            k_threshold=10,
            suppress_zero_flag=True,
            minimum_interval_minutes=15,
            effective_from_date=D(2026, 3, 1),
            effective_to_date=None,
            is_current=True,
        ),
    ], "sensing_disclosure_policy")

    for view_name in (
        "gold_store_traffic_daily_shared",
        "gold_zone_traffic_shared",
        "gold_zone_traffic_interval_shared",
    ):
        _create_view(
            spark,
            view_name,
            os.path.join(PKG, "gold", f"{view_name}.sql"),
        )

    store = spark.sql(
        "SELECT footfall_count, sensing_disclosure_policy_id "
        "FROM gold_store_traffic_daily_shared WHERE store_id = 'STR-1'"
    ).first()
    zone = spark.sql(
        "SELECT footfall_count, sensing_disclosure_policy_id "
        "FROM gold_zone_traffic_shared WHERE store_zone_id = 'ZN-GROCERY'"
    ).first()
    interval = spark.sql(
        "SELECT footfall_count, sensing_disclosure_policy_id "
        "FROM gold_zone_traffic_interval_shared WHERE store_zone_id = 'ZN-GROCERY'"
    ).first()

    assert store is not None and store.footfall_count == 150
    assert zone is not None and zone.footfall_count == 999
    assert interval is not None and interval.footfall_count == 999
    assert {
        store.sensing_disclosure_policy_id,
        zone.sensing_disclosure_policy_id,
        interval.sensing_disclosure_policy_id,
    } == {"external_default"}


def test_cmn_shim_reproduces_the_retired_column_shape(spark):
    _build(spark)
    assert spark.table("store_zone_interval").columns == [
        "store_zone_interval_sk",
        "store_zone_interval_id",
        "store_sk",
        "store_id",
        "store_zone_code",
        "interval_start_ts",
        "interval_date",
        "interval_minutes",
        "footfall_count",
        "avg_dwell_seconds",
        "opportunity_to_see",
        "aggregated_flag",
        "record_source",
        "load_timestamp",
    ]


def test_shared_interval_and_cmn_shim_use_device_free_keys(spark):
    _build(spark)
    expected_id = "STR-1|ZN-GROCERY|1772442000|60"
    shared = spark.sql(
        "SELECT shared_zone_traffic_interval_sk, shared_zone_traffic_interval_id "
        "FROM gold_zone_traffic_interval_shared "
        "WHERE store_zone_id = 'ZN-GROCERY'"
    ).first()
    cmn = spark.sql(
        "SELECT store_zone_interval_sk, store_zone_interval_id "
        "FROM store_zone_interval WHERE store_zone_code = 'GROCERY'"
    ).first()
    expected_sk = spark.sql(
        f"SELECT xxhash64('{expected_id}') AS shared_sk"
    ).first().shared_sk

    assert shared.shared_zone_traffic_interval_id == expected_id
    assert "DEV-1" not in shared.shared_zone_traffic_interval_id
    assert shared.shared_zone_traffic_interval_sk == expected_sk
    assert cmn.store_zone_interval_id == expected_id
    assert cmn.store_zone_interval_sk == expected_sk


def test_cmn_shim_resolves_zone_code_from_the_dimension(spark):
    """The retired fact carried a bare store_zone_code string. The shim has to resolve it
    through the real dimension, which is the whole point of the relocation."""
    _build(spark)
    r = spark.sql("SELECT store_zone_code FROM store_zone_interval "
                  "WHERE store_zone_code = 'GROCERY'").first()
    assert r.store_zone_code == "GROCERY"


def test_cmn_shim_omits_suppressed_intervals_and_does_not_invent_ots(spark):
    _build(spark)
    rows = {r.store_zone_code: r for r in spark.sql(
        "SELECT store_zone_code, footfall_count, avg_dwell_seconds, opportunity_to_see "
        "FROM store_zone_interval"
    ).collect()}
    assert "FLOWERS" not in rows, (
        "a suppressed interval retained a compatibility row whose timestamp and "
        "duration could disclose the protected cell"
    )
    assert rows["GROCERY"].footfall_count == 999
    assert rows["GROCERY"].opportunity_to_see is None


def test_cmn_shim_exposes_only_zone_level_rows(spark):
    _build(spark)
    n = spark.sql("SELECT COUNT(*) AS n FROM store_zone_interval").first().n
    assert n == 1, (
        f"expected one unsuppressed area interval, got {n} "
        "(a suppressed, site, or temperature row leaked in)"
    )


def test_cmn_shim_preserves_interval_grain_and_duration_semantics(spark):
    """Two canonical source intervals remain two compatibility rows.

    A daily compatibility projection would collapse them and change
    ``interval_minutes`` from interval length to daily observed coverage.
    """
    later = dict(
        _AREA,
        sensor_report_interval_id=(
            "space|ZN-GROCERY|gs1:Count|area|60|1772445600|DEV-1"
        ),
        interval_start_ts=TS(2026, 3, 2, 10, 0),
        interval_end_ts=TS(2026, 3, 2, 11, 0),
        footfall_count=101,
        entry_count=101,
        exit_count=100,
        dwell_seconds_total=505,
        dwell_count=5,
    )
    _build(spark)
    _build_interval_tables(
        spark,
        [_SITE_A, _SITE_B, _SITE_INVALID, _AREA, later, _AREA_QUIET, _TEMP, _HUMID],
    )
    _create_view(
        spark,
        "gold_zone_traffic_interval_shared",
        os.path.join(PKG, "gold", "gold_zone_traffic_interval_shared.sql"),
    )
    _create_view(
        spark,
        "store_zone_interval",
        os.path.join(CMN, "gold", "store_zone_interval.sql"),
    )

    rows = spark.sql(
        "SELECT interval_start_ts, interval_minutes, footfall_count "
        "FROM store_zone_interval WHERE store_zone_code = 'GROCERY' "
        "ORDER BY interval_start_ts"
    ).collect()
    assert len(rows) == 2
    assert [r.interval_minutes for r in rows] == [60, 60]
    assert [r.footfall_count for r in rows] == [999, 101]


def test_canonical_overlap_check_rejects_vendor_native_and_rollup_mix(spark):
    """A 15-minute vendor-native row cannot coexist with its 60-minute rollup.

    Both rows are otherwise valid and belong to the same series, so the overlap
    check—not a cadence allow-list—must identify the ambiguity.
    """
    rolled_up = dict(_TEMP)
    vendor_native = dict(
        _TEMP,
        sensor_report_interval_id=(
            "point|EQ-1|gs1:Temperature|subject|15|1772442900|DEV-2"
        ),
        interval_start_ts=TS(2026, 3, 2, 9, 15),
        interval_end_ts=TS(2026, 3, 2, 9, 30),
        interval_minutes=15,
        source_observation_count=15,
        expected_observation_count=15,
        source_message_count=15,
    )
    _build_interval_tables(spark, [rolled_up, vendor_native])

    query = next(
        q for name, _, q in _parse_checks()
        if name == "sri_canonical_interval_overlap"
    )
    violations = spark.sql(_to_temp_views(query)).collect()
    assert len(violations) == 1


def test_canonical_overlap_check_rejects_cross_device_site_series(spark):
    """Device lineage cannot split one additive site publication series.

    A cross-device ``_ALL`` rollup and a device-native constituent describe the
    same store, report, level, and window. If device identity participates in the
    overlap join, both rows pass DQ and the store-day view sums them.
    """
    device_native = dict(
        _SITE_A,
        sensor_report_interval_id=(
            "space|STR-1|gs1:Count|site|60|1772442000|DEV-1"
        ),
        sensor_device_sk=1,
        sensor_device_id="DEV-1",
    )
    _build_interval_tables(spark, [_SITE_A, device_native])

    query = next(
        q for name, _, q in _parse_checks()
        if name == "sri_canonical_interval_overlap"
    )
    violations = spark.sql(_to_temp_views(query)).collect()
    assert len(violations) == 1, (
        "the additive series was split by sensor_device_id, allowing _ALL and "
        "device-native site totals to coexist"
    )


def test_nonspace_gs1_count_does_not_require_traffic_detail(spark):
    """RFID and Smart Shelf counts reuse the envelope without Foot Traffic fields."""
    item_count = dict(
        _TEMP,
        sensor_report_interval_id=(
            "epc|urn:epc:id:sgtin:0614141.107346.2017|gs1:Count|subject|"
            "60|1772442000|DEV-2"
        ),
        subject_type="epc",
        subject_id="urn:epc:id:sgtin:0614141.107346.2017",
        report_type="gs1:Count",
        value=12.0,
        min_value=None,
        max_value=None,
        mean_value=None,
        uom="H87",
        unit_iri="http://qudt.org/vocab/unit/NUM",
    )
    _build_interval_tables(spark, [item_count])

    requires_detail = next(
        q for name, _, q in _parse_checks()
        if name == "ftid_space_count_requires_detail"
    )
    forbids_detail = next(
        q for name, _, q in _parse_checks()
        if name == "ftid_noncount_report_forbids_detail"
    )
    assert not spark.sql(_to_temp_views(requires_detail)).collect()
    assert not spark.sql(_to_temp_views(forbids_detail)).collect()


# ---------------------------------------------------------------------------
# 7. Metric expressions execute on Spark
# ---------------------------------------------------------------------------

def test_metric_rollups_use_the_minutes_that_contributed_to_each_average(spark):
    """Each daily average travels with its measure-specific denominator."""
    spark.createDataFrame(
        [
            (10.0, 1.0, 0.8, 120.0, 60.0, 60.0, 60.0),
            (0.0, 0.0, 0.0, 120.0, 120.0, 120.0, 120.0),
        ],
        "avg_occupancy double, avg_uptime_ratio double, avg_coverage_ratio double, "
        "interval_minutes_total double, occupancy_interval_minutes_total double, "
        "uptime_interval_minutes_total double, coverage_interval_minutes_total double",
    ).createOrReplaceTempView("metric_daily")

    expected = {
        "avg_occupancy": 3.3333333333333335,
        "uptime": 0.3333333333333333,
        "avg_coverage": 0.26666666666666666,
    }
    for filename in ("store_foot_traffic.sql", "zone_foot_traffic.sql"):
        for measure, value in expected.items():
            actual = spark.sql(
                f"SELECT {_metric_expr(filename, measure)} AS value FROM metric_daily"
            ).first().value
            assert float(actual) == pytest.approx(value), f"{filename}: {measure}"

    productivity_coverage = spark.sql(
        "SELECT "
        + _metric_expr("traffic_sales_productivity.sql", "avg_coverage")
        + " AS value FROM metric_daily"
    ).first().value
    assert float(productivity_coverage) == pytest.approx(expected["avg_coverage"])


def test_device_valid_interval_share_excludes_rfid_event_quality(spark):
    """Interval validity must not pool sensor measurement validity with RFID stray reads."""
    spark.createDataFrame(
        [
            (90.0, 10.0, 100.0, "gs1:Count"),
            (198.0, 2.0, 200.0, "rfid:ReadEvent"),
        ],
        "valid_intervals double, invalid_intervals double, intervals_reported double, "
        "report_type string",
    ).createOrReplaceTempView("device_day")

    actual = spark.sql(
        "SELECT "
        + _metric_expr("device_health.sql", "valid_interval_share")
        + " AS value FROM device_day"
    ).first().value
    assert float(actual) == pytest.approx(0.9)


def test_device_health_rates_ignore_rfid_rows_without_observation_kpis(spark):
    """RFID read volume must not dilute interval-based Foot Traffic fleet KPIs."""
    spark.createDataFrame(
        [
            (10.0, 0.8, 0.6, 90.0, 100.0),
            (200.0, None, None, None, None),
        ],
        "intervals_reported double, avg_uptime_ratio double, avg_coverage_ratio double, "
        "observations_received double, observations_expected double",
    ).createOrReplaceTempView("mixed_device_day")

    expected = {
        "online_rate": 0.8,
        "coverage_rate": 0.6,
        "missing_observation_rate": 0.1,
    }
    for measure, value in expected.items():
        actual = spark.sql(
            "SELECT " + _metric_expr("device_health.sql", measure)
            + " AS value FROM mixed_device_day"
        ).first().value
        assert float(actual) == pytest.approx(value), measure


def test_zone_capture_rate_reaggregates_counts(spark):
    """A multi-day capture rate divides total footfall by total passers-by."""
    spark.createDataFrame(
        [(10.0, 100.0), (90.0, 300.0)],
        "footfall_count double, passersby_count double",
    ).createOrReplaceTempView("zone_daily")

    actual = spark.sql(
        "SELECT "
        + _metric_expr("zone_foot_traffic.sql", "capture_rate")
        + " AS value FROM zone_daily"
    ).first().value
    assert float(actual) == pytest.approx(0.25)


# ---------------------------------------------------------------------------
# 8. The data-quality suite, executed
# ---------------------------------------------------------------------------
# checks.sql is the sole enforcement of five ADRs, so "it is written down" is not enough —
# it has to PARSE and RUN. This executes all 69 checks against the fixture above and
# asserts the error/warn ones return no rows. That makes the fixture a conforming instance
# of the model by construction, and catches a check that is silently unrunnable (a typo'd
# column returns an ANALYSIS_ERROR, not a violation, and run_checks.py would report it as
# an error only at deploy time).

# The three checks that read Unity Catalog metadata rather than data. They cannot run against
# temp views, and are listed by NAME rather than pattern-skipped so that adding a third
# metadata check is a deliberate act.
_METADATA_ONLY_CHECKS = {
    "sri_no_person_level_columns": "reads ${catalog}.information_schema.columns",
    "css_no_sensing_to_pricing_lineage": "reads ${catalog}.information_schema.views",
    "shared_no_suppression_side_channels": "reads ${catalog}.information_schema.columns",
    "rfid_append_only_schema": "reads ${catalog}.information_schema.columns",
}

CHECKS_SQL = os.path.join(PKG, "checks.sql")


def _parse_checks():
    header = re.compile(r"^--\s*check:\s*(\w+)\s*\|\s*severity:\s*(error|warn|metric)\s*$", re.I)
    out, current, buf = [], None, []
    for line in open(CHECKS_SQL).read().splitlines():
        m = header.match(line.strip())
        if m:
            current, buf = (m.group(1), m.group(2).lower()), []
            continue
        if current is None or line.strip().startswith("--"):
            continue
        buf.append(line)
        if ";" in line:
            out.append((current[0], current[1], "\n".join(buf).rstrip().rstrip(";")))
            current, buf = None, []
    return out


def _check_query(name):
    matches = [query for check_name, _, query in _parse_checks() if check_name == name]
    assert len(matches) == 1, f"expected exactly one authored check named {name}"
    return _to_temp_views(matches[0])


def _check_rows(spark, name, fixtures):
    """Execute an authored DQ query against small, deliberately invalid Spark views."""
    for view_name, schema, rows in fixtures:
        spark.createDataFrame(rows, schema).createOrReplaceTempView(view_name)
    return [tuple(row) for row in spark.sql(_check_query(name)).collect()]


_NEGATIVE_DQ_CASES = [
    pytest.param(
        "ftid_space_count_requires_detail",
        [
            (
                "sensor_report_interval",
                "sensor_report_interval_sk long, sensor_report_interval_id string, "
                "report_type string, subject_type string",
                [(1, "space|STR-1|gs1:Count|site|60|1|DEV-1", "gs1:Count", "space")],
            ),
            (
                "foot_traffic_interval_detail",
                "sensor_report_interval_sk long",
                [(1,), (1,)],
            ),
        ],
        [("space|STR-1|gs1:Count|site|60|1|DEV-1",)],
        id="duplicate-traffic-detail",
    ),
    pytest.param(
        "ftid_space_count_requires_detail",
        [
            (
                "sensor_report_interval",
                "sensor_report_interval_sk long, sensor_report_interval_id string, "
                "report_type string, subject_type string",
                [(1, "space|STR-1|gs1:Count|site|60|1|DEV-1", "gs1:Count", "space")],
            ),
            ("foot_traffic_interval_detail", "sensor_report_interval_sk long", []),
        ],
        [("space|STR-1|gs1:Count|site|60|1|DEV-1",)],
        id="missing-traffic-detail",
    ),
    pytest.param(
        "ftid_noncount_report_forbids_detail",
        [
            (
                "sensor_report_interval",
                "sensor_report_interval_sk long, sensor_report_interval_id string, "
                "report_type string, subject_type string",
                [(1, "epc|ITEM-1|gs1:Count|subject|60|1|DEV-1", "gs1:Count", "epc")],
            ),
            ("foot_traffic_interval_detail", "sensor_report_interval_sk long", [(1,)]),
        ],
        [("epc|ITEM-1|gs1:Count|subject|60|1|DEV-1",)],
        id="nonspace-count-has-traffic-detail",
    ),
    pytest.param(
        # A detail row whose sensor_report_interval_sk has no parent envelope row. The two
        # 1:1 checks above inner-join FROM the fact, so they never see it; only this reverse
        # anti-join does. Parent has sk=1, the orphan detail carries sk=999.
        "ftid_interval_fk_orphan",
        [
            (
                "sensor_report_interval",
                "sensor_report_interval_sk long",
                [(1,)],
            ),
            (
                "foot_traffic_interval_detail",
                "sensor_report_interval_sk long, footfall_count int",
                [(999, 42)],
            ),
        ],
        [(999, 42)],
        id="orphaned-traffic-detail",
    ),
    pytest.param(
        "sri_source_observation_bounds",
        [(
            "sensor_report_interval",
            "source_observation_count int, expected_observation_count int",
            [(61, 60)],
        )],
        [(61, 60)],
        id="observations-exceed-cadence",
    ),
    pytest.param(
        "sri_source_message_summary_bounds",
        [(
            "sensor_report_interval",
            "source_message_count int, sequence_gap_count int, "
            "duplicate_delivery_count int, historical_message_count int, "
            "bad_quality_message_count int",
            [(10, -1, 0, 0, 0)],
        )],
        [(10, -1, 0, 0, 0)],
        id="negative-message-summary",
    ),
    pytest.param(
        "sri_sk_collision",
        [(
            "sensor_report_interval",
            "sensor_report_interval_sk long, sensor_report_interval_id string",
            [(42, "interval-A"), (42, "interval-B")],
        )],
        [(42, 2)],
        id="hash-surrogate-collision",
    ),
    pytest.param(
        "ftid_counting_convention_uniform",
        [
            (
                "sensor_report_interval",
                "sensor_report_interval_sk long, store_id string, trading_date date, "
                "aggregation_level string, store_zone_sk long, report_type string, "
                "time_mode string",
                [
                    (1, "STR-1", D(2026, 3, 2), "area", 10, "gs1:Count", "within_operating_hours"),
                    (2, "STR-1", D(2026, 3, 2), "area", 10, "gs1:Count", "within_operating_hours"),
                ],
            ),
            (
                "foot_traffic_interval_detail",
                "sensor_report_interval_sk long, counting_unit string, "
                "group_counting_enabled boolean, staff_exclusion_enabled boolean, "
                "staff_exclusion_stage string",
                [
                    (1, "person", False, True, "at_aggregation"),
                    (2, "group", True, True, "at_aggregation"),
                ],
            ),
        ],
        [("STR-1", D(2026, 3, 2), "area", 10, 2, 2, 1, 1, 1)],
        id="mixed-counting-conventions",
    ),
    pytest.param(
        "ftid_nondirectional_exits_null",
        [
            (
                "sensor_report_interval",
                "sensor_report_interval_sk long, report_type string",
                [(1, "gs1:Count")],
            ),
            (
                "foot_traffic_interval_detail",
                "sensor_report_interval_sk long, directionality string, exit_count int",
                [(1, "none", 0)],
            ),
        ],
        [(1, "none", 0)],
        id="nondirectional-exit-count",
    ),
    pytest.param(
        "ftid_staff_adjustment_balances",
        [(
            "foot_traffic_interval_detail",
            "staff_adjustment_applied boolean, visitor_count_raw int, "
            "staff_count int, visitor_count_adjusted int",
            [(True, 100, 10, 95)],
        )],
        [(True, 100, 10, 95)],
        id="unbalanced-staff-adjustment",
    ),
    pytest.param(
        "ftid_dwell_denominator_present",
        [(
            "foot_traffic_interval_detail",
            "dwell_seconds_total long, dwell_count long",
            [(600, 0)],
        )],
        [(600, 0)],
        id="missing-dwell-denominator",
    ),
    pytest.param(
        "sdep_external_policy_present",
        [(
            "sensing_deployment",
            "sensing_deployment_id string, is_current boolean, deployment_status string, "
            "sensing_purpose_code string, external_disclosure_policy_sk long, "
            "external_disclosure_policy_id string",
            [("DEP-1", True, "active", "people_counting", None, None)],
        )],
        [("DEP-1", True, "active", "people_counting", None, None)],
        id="active-deployment-without-policy",
    ),
    pytest.param(
        "sdep_disclosure_policy_key_pair",
        [
            (
                "sensing_deployment",
                "sensing_deployment_id string, external_disclosure_policy_sk long, "
                "external_disclosure_policy_id string",
                [("DEP-1", 10, "partner_default")],
            ),
            (
                "sensing_disclosure_policy",
                "sensing_disclosure_policy_sk long, sensing_disclosure_policy_id string",
                [(10, "external_default")],
            ),
        ],
        [("DEP-1",)],
        id="disclosure-policy-key-pair-mismatch",
    ),
    pytest.param(
        "sdep_disclosure_policy_effective",
        [
            (
                "sensor_report_interval",
                "sensor_report_interval_id string, sensing_deployment_sk long, "
                "report_type string, trading_date date",
                [("space|STR-1|gs1:Count|site|60|1|DEV-1", 1, "gs1:Count", D(2026, 3, 2))],
            ),
            (
                "sensing_deployment",
                "sensing_deployment_sk long, external_disclosure_policy_id string",
                [(1, "external_default")],
            ),
            (
                "sensing_disclosure_policy",
                "sensing_disclosure_policy_sk long, sensing_disclosure_policy_id string, "
                "effective_from_date date, effective_to_date date",
                [(10, "external_default", D(2026, 4, 1), None)],
            ),
        ],
        [("space|STR-1|gs1:Count|site|60|1|DEV-1", "external_default")],
        id="policy-not-effective-on-measurement-date",
    ),
    pytest.param(
        "shared_minimum_interval_granularity",
        [(
            "sensing_disclosure_policy",
            "sensing_disclosure_policy_id string, is_current boolean, "
            "minimum_interval_minutes int",
            [("external_default", True, 2880)],
        )],
        [("external_default", True, 2880)],
        id="policy-window-over-one-day",
    ),
    pytest.param(
        "shared_dependent_measure_suppression",
        [
            (
                "gold_zone_traffic_shared",
                "store_id string, trading_date date, disclosure_suppressed_flag boolean, "
                "footfall_count long, entry_count long, exit_count long, passersby_count long, "
                "peak_occupancy long, avg_occupancy double, dwell_seconds_total long, "
                "dwell_count long, avg_dwell_seconds double, engaged_count long, "
                "passing_count long, engagement_rate double, footfall_per_sqm double, "
                "occupancy_per_sqm double, peak_capacity_utilisation double",
                [(
                    "STR-1", D(2026, 3, 2), True,
                    None, None, None, None, None, None, None, None, 42.0,
                    None, None, None, None, None, None,
                )],
            ),
            (
                "gold_store_traffic_daily_shared",
                "store_id string, trading_date date, disclosure_suppressed_flag boolean, "
                "footfall_count long, entry_count long, exit_count long, peak_occupancy long, "
                "avg_occupancy double, dwell_seconds_total long, dwell_count long, "
                "avg_dwell_seconds double",
                [],
            ),
        ],
        [("zone", "STR-1", D(2026, 3, 2))],
        id="suppressed-cell-retains-dependent-measure",
    ),
    pytest.param(
        "productivity_single_currency",
        [
            (
                "gold_traffic_sales_productivity_current",
                "store_id string, trading_date date",
                [("STR-1", D(2026, 3, 2))],
            ),
            (
                "sales",
                "store_id string, date_key date, currency_code string",
                [
                    ("STR-1", D(2026, 3, 2), "USD"),
                    ("STR-1", D(2026, 3, 2), "EUR"),
                ],
            ),
        ],
        [("STR-1", D(2026, 3, 2), 2)],
        id="mixed-store-day-currency",
    ),
    pytest.param(
        "css_device_health_grain",
        [(
            "gold_css_device_health",
            "sensor_device_sk long, trading_date date, report_type string, aggregation_level string",
            [
                (1, D(2026, 3, 2), "gs1:Count", "area"),
                (1, D(2026, 3, 2), "gs1:Count", "area"),
            ],
        )],
        [(1, D(2026, 3, 2), "gs1:Count", "area", 2)],
        id="duplicate-device-health-grain",
    ),
    pytest.param(
        "css_store_traffic_grain",
        [(
            "gold_store_traffic_daily_current",
            "store_id string, trading_date date",
            [("STR-1", D(2026, 3, 2)), ("STR-1", D(2026, 3, 2))],
        )],
        [("STR-1", D(2026, 3, 2), 2)],
        id="duplicate-store-traffic-grain",
    ),
    pytest.param(
        "css_zone_traffic_grain",
        [(
            "gold_zone_traffic_current",
            "store_zone_id string, trading_date date",
            [("ZN-1", D(2026, 3, 2)), ("ZN-1", D(2026, 3, 2))],
        )],
        [("ZN-1", D(2026, 3, 2), 2)],
        id="duplicate-zone-traffic-grain",
    ),
    pytest.param(
        # The shape the round-4 NULL-validity bug produced: an interval with NULL
        # measurement_validity was evaluated (and breached) but never counted as valid.
        "ecd_count_hierarchy",
        [(
            "gold_css_environmental_compliance_daily",
            "breach_interval_count long, evaluated_interval_count long, "
            "valid_reading_count long, reading_count long",
            [(2, 3, 3, 3), (1, 1, 0, 1)],
        )],
        [(1, 1, 0, 1)],
        id="evaluated-exceeds-valid",
    ),
    pytest.param(
        # The same bug seen across the two views: the daily view counts the NULL-validity
        # breach, the episodes view (valid intervals only) does not. ER-3 reconciles, and
        # the unruled daily row is ignored.
        "iot_breach_episode_reconciliation",
        [
            (
                "gold_css_environmental_compliance_daily",
                "evaluation_rule_id string, breach_interval_count long",
                [("ER-2", 3), ("ER-3", 1), (None, 5)],
            ),
            (
                "gold_css_excursion_episodes",
                "evaluation_rule_id string, interval_count long",
                [("ER-2", 2), ("ER-3", 1)],
            ),
        ],
        [("ER-2", 3, 2)],
        id="daily-breach-missing-from-episodes",
    ),
    pytest.param(
        # The reverse direction of the FULL OUTER JOIN: an episode for a rule whose daily
        # rows never counted a breach.
        "iot_breach_episode_reconciliation",
        [
            (
                "gold_css_environmental_compliance_daily",
                "evaluation_rule_id string, breach_interval_count long",
                [("ER-3", 1)],
            ),
            (
                "gold_css_excursion_episodes",
                "evaluation_rule_id string, interval_count long",
                [("ER-3", 1), ("ER-4", 1)],
            ),
        ],
        [("ER-4", None, 1)],
        id="episode-without-daily-breach",
    ),
    pytest.param(
        "exe_firings_bounded",
        [(
            "gold_css_excursion_episodes",
            "firings long, successful_firings long, failed_firings long",
            [(1, 1, 0), (1, 1, 1)],
        )],
        [(1, 1, 1)],
        id="outcomes-exceed-firings",
    ),
    pytest.param(
        # Inclusive operators may sit exactly on the limit; strict ones may not, and
        # equality rules carry no exceedance at all.
        "exe_peak_exceedance_non_negative",
        [(
            "gold_css_excursion_episodes",
            "peak_exceedance double, condition_operator string",
            [(0.0, "greater_than_or_equal"), (None, "equal"), (0.0, "greater_than")],
        )],
        [(0.0, "greater_than")],
        id="strict-operator-on-the-limit",
    ),
    pytest.param(
        "exe_resolution_consistency",
        [(
            "gold_css_excursion_episodes",
            "has_successful_action boolean, successful_firings long, "
            "minutes_to_first_successful_action int",
            [(True, 1, 5), (False, 0, None), (True, 0, None)],
        )],
        [(True, 0, None)],
        id="resolved-without-a-successful-firing",
    ),
]


def _build_automation(spark):
    """Fixtures for the sense -> evaluate -> act -> log automation loop.

    Registered so test_check_runs_and_fixture_conforms has a conforming row for every
    ac_/er_/aa_/el_ assertion in checks.sql — without these the parametrized runner hits
    those checks against an empty catalog and every one fails TABLE_OR_VIEW_NOT_FOUND.

    The rows reuse the existing registry the checks join to: the actuator hangs off DEV-1
    (sensor_device_sk=1) and EQ-1 (equipment_sk=1), the rule observes the same device. One
    rule fans out to TWO actions — an actuator-targeted system_command and a role-targeted
    notification — the multi-action case the model is built for, which also drives BOTH
    branches of aa_actuator_target_consistent (typed actuator FK present vs. NULL). Each
    action fires once, giving two distinct execution_log ids off one rule (the firing-scoped
    grain el_grain_unique guards). sensor_report_interval_sk is left NULL — its _sk is an
    xxhash64 of the durable id derived inside the interval fixture, not a literal we can
    restate here, and the DDL admits NULL for a trigger that is not a single canonical
    interval; el_interval_fk_orphan still runs and passes on the NULL branch."""
    _view_table(spark, ACTUATOR_DDL, [
        dict(actuator_capability_sk=1, actuator_capability_id="AC-1",
             sensor_device_sk=1, sensor_device_id="DEV-1",
             equipment_sk=1, equipment_id="EQ-1",
             command_type="toggle_power", acceptable_value_range="0,1",
             actuator_status="active", installed_date=D(2025, 1, 1),
             effective_from_date=D(2025, 1, 1), is_current=True,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
    ], "actuator_capability")

    _view_table(spark, RULE_DDL, [
        dict(evaluation_rule_sk=1, evaluation_rule_id="ER-1",
             sensor_device_sk=1, sensor_device_id="DEV-1",
             rule_name="Vaccine fridge over 8C for 10 minutes",
             report_type="gs1:Temperature", condition_operator="greater_than",
             threshold_value_numeric=8.0, time_window_seconds=600,
             severity="critical", is_enabled=True,
             effective_from_date=D(2025, 1, 1), is_current=True,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
    ], "evaluation_rule")

    _view_table(spark, ACTION_DDL, [
        # Actuator target: carries the typed actuator_capability_sk (physical command path).
        dict(automation_action_sk=1, automation_action_id="AA-1",
             evaluation_rule_sk=1, evaluation_rule_id="ER-1",
             action_type="system_command", target_entity_type="actuator",
             target_entity_id="AC-1",
             actuator_capability_sk=1, actuator_capability_id="AC-1",
             payload_template='{"command": "start_cooling"}', is_enabled=True,
             effective_from_date=D(2025, 1, 1), is_current=True,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
        # Role target: no actuator, so the typed FK is NULL (the other consistency branch).
        dict(automation_action_sk=2, automation_action_id="AA-2",
             evaluation_rule_sk=1, evaluation_rule_id="ER-1",
             action_type="notification", target_entity_type="role",
             target_entity_id="store_manager",
             payload_template='{"message": "Fridge breach"}', is_enabled=True,
             effective_from_date=D(2025, 1, 1), is_current=True,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
    ], "automation_action")

    _view_table(spark, EXECLOG_DDL, [
        dict(execution_log_sk=1, execution_log_id="EL-1",
             automation_action_sk=1, automation_action_id="AA-1",
             actuator_capability_sk=1, actuator_capability_id="AC-1",
             evaluation_rule_sk=1, evaluation_rule_id="ER-1",
             triggered_at_timestamp=TS(2026, 3, 2, 9, 5), execution_status="success",
             response_payload='{"status_code": 200}', latency_ms=250,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
        dict(execution_log_sk=2, execution_log_id="EL-2",
             automation_action_sk=2, automation_action_id="AA-2",
             evaluation_rule_sk=1, evaluation_rule_id="ER-1",
             triggered_at_timestamp=TS(2026, 3, 2, 9, 5), execution_status="success",
             response_payload='{"delivered": true}', latency_ms=120,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
    ], "execution_log")


def _build_with_core(spark):
    """The fixture plus the canonical-core FK targets the orphan checks join to."""
    _build(spark)
    # The shared checks file now includes Smart Shelf assertions. Empty, DDL-derived
    # tables let this Foot Traffic fixture prove every check is executable without
    # inventing Smart Shelf rows that are irrelevant to its behavior tests.
    _view_table(
        spark, SHELF_POSITION_ASSIGNMENT_DDL, [], "shelf_position_assignment"
    )
    _view_table(spark, SHELF_STATE_OBSERVATION_DDL, [], "shelf_state_observation")
    _view_table(spark, ESL_LABEL_ASSIGNMENT_DDL, [], "esl_label_assignment")
    spark.createDataFrame(
        [(1, "STR-1", True)], "store_sk long, store_id string, is_current boolean"
    ).createOrReplaceTempView("store")
    spark.createDataFrame(
        [(1, "SKU-1", "00000000000001", True),
         (2, "SKU-2", "00000000000002", True)],
        "product_sk long, product_id string, gtin string, is_current boolean"
    ).createOrReplaceTempView("product")
    spark.createDataFrame(
        [(1, "EQ-1", True)], "equipment_sk long, equipment_id string, is_current boolean"
    ).createOrReplaceTempView("equipment")
    _build_automation(spark)
    spark.createDataFrame(
        [], "shipment_line_sk long, shipment_line_id string, product_id string"
    ).createOrReplaceTempView("shipment_line")
    # IoT environmental serving layer: needs evaluation_rule / execution_log from
    # _build_automation, so it is created after them.
    for view in ("gold_css_environmental_compliance_daily", "gold_css_excursion_episodes",
                 "gold_css_rule_effectiveness_daily"):
        _create_view(spark, view, os.path.join(PKG, "gold", f"{view}.sql"))


# A fridge excursion on DEV-2: two contiguous 60-minute readings above 8 °C straight after
# _TEMP's in-range 09:00 reading, then a hotter reading whose validity is NULL. Kept out of
# _build so the traffic, device-health and conformance tests keep their fixture.
_TEMP_BREACH_1 = dict(
    _TEMP,
    sensor_report_interval_id="point|EQ-1|gs1:Temperature|subject|60|1772445600|DEV-2",
    interval_start_ts=TS(2026, 3, 2, 10, 0), interval_end_ts=TS(2026, 3, 2, 11, 0),
    value=9.5, min_value=9.1, max_value=9.9, mean_value=9.5,
    ingest_timestamp=TS(2026, 3, 2, 11, 5), load_timestamp=TS(2026, 3, 2, 11, 5),
)
_TEMP_BREACH_2 = dict(
    _TEMP_BREACH_1,
    sensor_report_interval_id="point|EQ-1|gs1:Temperature|subject|60|1772449200|DEV-2",
    interval_start_ts=TS(2026, 3, 2, 11, 0), interval_end_ts=TS(2026, 3, 2, 12, 0),
    value=10.0, min_value=9.6, max_value=10.4, mean_value=10.0,
    ingest_timestamp=TS(2026, 3, 2, 12, 5), load_timestamp=TS(2026, 3, 2, 12, 5),
)
# Contiguous with the breach and over the limit, but NULL validity is not valid (the round-4
# fix), so it must neither extend the episode nor count as a breach in the daily view.
_TEMP_NULL_VALIDITY = dict(
    _TEMP_BREACH_1,
    sensor_report_interval_id="point|EQ-1|gs1:Temperature|subject|60|1772452800|DEV-2",
    interval_start_ts=TS(2026, 3, 2, 12, 0), interval_end_ts=TS(2026, 3, 2, 13, 0),
    value=11.0, min_value=10.6, max_value=11.4, mean_value=11.0,
    measurement_validity=None,
    ingest_timestamp=TS(2026, 3, 2, 13, 5), load_timestamp=TS(2026, 3, 2, 13, 5),
)


def _append_rows(spark, path, name, dicts):
    """Add rows to a fixture table registered by _view_table, keeping the rows it has."""
    _view_table(spark, path, dicts, f"_{name}_extra")
    spark.table(name).unionByName(spark.table(f"_{name}_extra")).createOrReplaceTempView(name)


# ER-2: DEV-2's temperature over 8 °C. It carries no subject scope, so it applies to every
# subject DEV-2 reports for.
_ER_2 = dict(
    evaluation_rule_sk=2, evaluation_rule_id="ER-2",
    sensor_device_sk=2, sensor_device_id="DEV-2",
    rule_name="Vaccine fridge over 8C",
    report_type="gs1:Temperature", condition_operator="greater_than",
    threshold_value_numeric=8.0, uom_code="CEL", time_window_seconds=600,
    severity="critical", is_enabled=True,
    effective_from_date=D(2025, 1, 1), is_current=True,
    record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0),
)


def _build_excursion(spark):
    """The core fixture plus one answered excursion, so the IoT views have rows to check.

    _build_with_core leaves gold_css_excursion_episodes empty: _TEMP (4.5 °C) never breaches,
    and ER-1 watches DEV-1, which reports no temperature. Here ER-2 watches DEV-2 at
    greater_than 8.0, and EL-3 fires off the FIRST breach interval through the causal key
    sensor_report_interval_sk, looked up from the interval view because it is an xxhash64
    of the durable id."""
    _build_with_core(spark)
    _build_interval_tables(
        spark,
        [_SITE_A, _SITE_B, _SITE_INVALID, _AREA, _AREA_QUIET, _TEMP, _HUMID,
         _TEMP_BREACH_1, _TEMP_BREACH_2, _TEMP_NULL_VALIDITY],
    )
    trigger_sk = spark.sql(
        "SELECT sensor_report_interval_sk FROM sensor_report_interval "
        f"WHERE sensor_report_interval_id = '{_TEMP_BREACH_1['sensor_report_interval_id']}'"
    ).first()[0]
    _append_rows(spark, RULE_DDL, "evaluation_rule", [_ER_2])
    _append_rows(spark, ACTION_DDL, "automation_action", [
        dict(automation_action_sk=3, automation_action_id="AA-3",
             evaluation_rule_sk=2, evaluation_rule_id="ER-2",
             action_type="notification", target_entity_type="role",
             target_entity_id="store_manager",
             payload_template='{"message": "Vaccine fridge breach"}', is_enabled=True,
             effective_from_date=D(2025, 1, 1), is_current=True,
             record_source="test", load_timestamp=TS(2026, 3, 2, 0, 0)),
    ])
    _append_rows(spark, EXECLOG_DDL, "execution_log", [
        dict(execution_log_sk=3, execution_log_id="EL-3",
             automation_action_sk=3, automation_action_id="AA-3",
             evaluation_rule_sk=2, evaluation_rule_id="ER-2",
             sensor_report_interval_sk=trigger_sk,
             triggered_at_timestamp=TS(2026, 3, 2, 10, 5), execution_status="success",
             response_payload='{"delivered": true}', latency_ms=180,
             record_source="test", load_timestamp=TS(2026, 3, 2, 10, 5)),
    ])
    for view in ("gold_css_environmental_compliance_daily", "gold_css_excursion_episodes",
                 "gold_css_rule_effectiveness_daily"):
        _create_view(spark, view, os.path.join(PKG, "gold", f"{view}.sql"))


def test_excursion_episode_joins_contiguous_breaches_and_credits_the_firing(spark):
    """Two contiguous breaching intervals are ONE episode; the NULL-validity reading after
    them does not extend it; the firing off the first interval is credited to it."""
    _build_excursion(spark)
    rows = spark.sql(
        "SELECT evaluation_rule_id, interval_count, duration_minutes, "
        "unix_timestamp(episode_start_ts) AS start_s, unix_timestamp(episode_end_ts) AS end_s, "
        "peak_value, peak_exceedance, firings, successful_firings, failed_firings, "
        "has_successful_action, minutes_to_first_successful_action, is_open_at_dataset_end "
        "FROM gold_css_excursion_episodes"
    ).collect()
    assert len(rows) == 1
    e = rows[0]
    assert e.evaluation_rule_id == "ER-2"
    assert (e.interval_count, e.duration_minutes) == (2, 120)
    # Epoch seconds, so the assertion does not depend on the session timezone.
    assert (e.start_s, e.end_s) == (
        int(TS(2026, 3, 2, 10, 0).timestamp()), int(TS(2026, 3, 2, 12, 0).timestamp()))
    assert (e.peak_value, e.peak_exceedance) == (pytest.approx(10.0), pytest.approx(2.0))
    assert (e.firings, e.successful_firings, e.failed_firings) == (1, 1, 0)
    assert e.has_successful_action is True
    assert e.minutes_to_first_successful_action == 5
    # The series' latest interval is the NULL-validity one ending 13:00, so the episode closed.
    assert e.is_open_at_dataset_end is False


def test_compliance_day_counts_the_same_breaches_as_the_episode(spark):
    """The daily view sees all four readings but evaluates only the three valid ones, and
    counts the same two breaches the episode holds."""
    _build_excursion(spark)
    r = spark.sql(
        "SELECT * FROM gold_css_environmental_compliance_daily "
        "WHERE sensor_device_id = 'DEV-2' AND report_type = 'gs1:Temperature'"
    ).collect()
    assert len(r) == 1
    r = r[0]
    assert r.evaluation_rule_id == "ER-2"
    assert (r.reading_count, r.valid_reading_count, r.evaluated_interval_count) == (4, 3, 3)
    assert (r.breach_interval_count, r.minutes_outside_range) == (2, 120)
    assert r.is_compliant is False
    assert r.share_intervals_in_range == pytest.approx(1 / 3)
    # Value statistics use valid readings only: 11.0 (NULL validity) stays out of the max.
    assert (r.min_value, r.max_value, r.avg_value) == (
        pytest.approx(4.5), pytest.approx(10.0), pytest.approx(8.0))


def _build_temperature_series(spark, temp_rows):
    """The core fixture with ER-2 over the given DEV-2 temperature rows, and only the two
    IoT views these tests read (no firings: the episode shape is under test, not the
    response)."""
    _build_with_core(spark)
    _build_interval_tables(
        spark, [_SITE_A, _SITE_B, _SITE_INVALID, _AREA, _AREA_QUIET, _HUMID] + temp_rows,
    )
    _append_rows(spark, RULE_DDL, "evaluation_rule", [_ER_2])
    for view in ("gold_css_environmental_compliance_daily", "gold_css_excursion_episodes"):
        _create_view(spark, view, os.path.join(PKG, "gold", f"{view}.sql"))


def _episodes_by_subject(spark):
    return {
        r.subject_id: r for r in spark.sql(
            "SELECT subject_id, interval_count, duration_minutes, "
            "unix_timestamp(episode_start_ts) AS start_s, unix_timestamp(episode_end_ts) AS end_s, "
            "is_open_at_dataset_end FROM gold_css_excursion_episodes"
        ).collect()
    }


def test_episode_uses_start_plus_interval_minutes_when_the_end_is_missing(spark):
    """interval_end_ts is nullable. With both breach readings missing their end, the derived
    end (start + interval_minutes) still makes them contiguous, and it supplies the episode
    end, so the episode is not split per interval and never has a NULL end."""
    _build_temperature_series(spark, [
        _TEMP,
        dict(_TEMP_BREACH_1, interval_end_ts=None),
        dict(_TEMP_BREACH_2, interval_end_ts=None),
    ])
    episodes = _episodes_by_subject(spark)
    assert list(episodes) == ["EQ-1"]
    e = episodes["EQ-1"]
    assert (e.interval_count, e.duration_minutes) == (2, 120)
    assert (e.start_s, e.end_s) == (
        int(TS(2026, 3, 2, 10, 0).timestamp()), int(TS(2026, 3, 2, 12, 0).timestamp()))
    # The series' last derived end is the episode's own end (12:00), so it is still open.
    assert e.is_open_at_dataset_end is True


# A second case on DEV-2's logger (subject EQ-2): one breaching reading at 10:00, then the
# channel stops reporting. EQ-1 breaches 10:00-12:00 and then reports in range until 13:00.
_TEMP_EQ2_BREACH = dict(
    _TEMP_BREACH_1,
    sensor_report_interval_id="point|EQ-2|gs1:Temperature|subject|60|1772445600|DEV-2",
    subject_id="EQ-2", equipment_sk=2, equipment_id="EQ-2",
    value=9.0, min_value=8.6, max_value=9.4, mean_value=9.0,
)
_TEMP_EQ1_RECOVERED = dict(
    _TEMP_BREACH_1,
    sensor_report_interval_id="point|EQ-1|gs1:Temperature|subject|60|1772452800|DEV-2",
    interval_start_ts=TS(2026, 3, 2, 12, 0), interval_end_ts=TS(2026, 3, 2, 13, 0),
    value=5.0, min_value=4.6, max_value=5.4, mean_value=5.0,
    ingest_timestamp=TS(2026, 3, 2, 13, 5), load_timestamp=TS(2026, 3, 2, 13, 5),
)
_TWO_SUBJECT_ROWS = [_TEMP, _TEMP_BREACH_1, _TEMP_BREACH_2, _TEMP_EQ1_RECOVERED, _TEMP_EQ2_BREACH]


def test_two_subjects_on_one_device_get_their_own_episodes_and_open_flags(spark):
    """Both subjects breach at 10:00 under the same device rule. Episodes are per subject,
    so the tied 10:00 starts do not interleave into one run, and the open flag follows each
    subject's own last reading: EQ-1 recovered at 12:00 (closed), EQ-2 went silent after its
    breach (still open, although the device kept reporting until 13:00)."""
    _build_temperature_series(spark, _TWO_SUBJECT_ROWS)
    episodes = _episodes_by_subject(spark)
    assert sorted(episodes) == ["EQ-1", "EQ-2"]
    eq1, eq2 = episodes["EQ-1"], episodes["EQ-2"]
    assert (eq1.interval_count, eq1.duration_minutes) == (2, 120)
    assert (eq1.start_s, eq1.end_s) == (
        int(TS(2026, 3, 2, 10, 0).timestamp()), int(TS(2026, 3, 2, 12, 0).timestamp()))
    assert eq1.is_open_at_dataset_end is False
    assert (eq2.interval_count, eq2.duration_minutes) == (1, 60)
    assert (eq2.start_s, eq2.end_s) == (
        int(TS(2026, 3, 2, 10, 0).timestamp()), int(TS(2026, 3, 2, 11, 0).timestamp()))
    assert eq2.is_open_at_dataset_end is True


def test_multi_subject_ruled_series_flags_the_two_subject_logger(spark):
    """iot_multi_subject_ruled_series is informational: it counts DEV-2's temperature series
    once because two subjects sit under ER-2, whether or not they share limits."""
    _build_temperature_series(spark, _TWO_SUBJECT_ROWS)
    query = next(q for n, _, q in _parse_checks() if n == "iot_multi_subject_ruled_series")
    assert spark.sql(_to_temp_views(query)).first()[0] == 1


def test_series_exclusion_telemetry_separates_history_loss_from_a_coarser_subject(spark):
    """EQ-1 moves from 60- to 15-minute readings (as after a firmware change), and EQ-2 on
    the same logger stays at 60 minutes. The canonical series becomes subject x 15 minutes,
    so EQ-1's earlier 09:00 reading (history loss) and EQ-2's reading (the documented
    coarser-subject drop) are both excluded; only the first is the subject's own history."""
    _build_temperature_series(spark, [
        _TEMP,
        dict(
            _TEMP_BREACH_1,
            sensor_report_interval_id="point|EQ-1|gs1:Temperature|subject|15|1772445600|DEV-2",
            interval_end_ts=TS(2026, 3, 2, 10, 15), interval_minutes=15,
            value=5.0, min_value=4.8, max_value=5.2, mean_value=5.0,
        ),
        _TEMP_EQ2_BREACH,
    ])
    counts = {}
    for name in ("iot_series_excluded_valid_intervals", "iot_series_history_loss_intervals"):
        query = next(q for n, _, q in _parse_checks() if n == name)
        counts[name] = spark.sql(_to_temp_views(query)).first()[0]
    assert counts == {"iot_series_excluded_valid_intervals": 2,
                      "iot_series_history_loss_intervals": 1}


_IOT_CHECKS = [c for c in _parse_checks()
               if c[0].startswith(("ecd_", "exe_", "iot_", "red_")) and c[1] != "metric"]


def test_iot_checks_pass_on_a_real_excursion(spark):
    """The ecd_/exe_/iot_/red_ checks also pass when their views have rows. Against
    _build_with_core they only prove they run: the episode and firing views are empty
    there. One build for all of them rather than a parametrized rebuild per check."""
    assert _IOT_CHECKS, "no IoT checks parsed — the prefixes or the parser drifted"
    _build_excursion(spark)
    for view in ("gold_css_excursion_episodes", "gold_css_rule_effectiveness_daily"):
        assert spark.table(view).count() > 0, f"{view} is empty: the excursion fixture is vacuous"
    failures = {}
    for name, severity, query in _IOT_CHECKS:
        violations = spark.sql(_to_temp_views(query)).limit(5).collect()
        if violations:
            failures[name] = [_identify(r) for r in violations]
    assert not failures, f"IoT checks flagged the excursion fixture: {failures}"


def test_check_suite_is_fully_parsed():
    names = [c[0] for c in _parse_checks()]
    assert len(names) == len(set(names))
    assert len(names) >= 60, f"only {len(names)} checks parsed — the suite or the parser drifted"
    assert set(_METADATA_ONLY_CHECKS) <= set(names), "a named metadata-only check no longer exists"


@pytest.mark.parametrize("name,severity,query", _parse_checks(),
                         ids=[c[0] for c in _parse_checks()])
def test_check_runs_and_fixture_conforms(spark, name, severity, query):
    if name in _METADATA_ONLY_CHECKS:
        pytest.skip(f"{name}: {_METADATA_ONLY_CHECKS[name]} — not available on temp views")
    _build_with_core(spark)
    df = spark.sql(_to_temp_views(query))   # raises on an unrunnable check
    if severity == "metric":
        df.collect()                    # a metric reports a value and never fails
        return
    violations = df.limit(5).collect()
    # Report the identifying columns rather than the whole ~100-column row: a full-row dump
    # of five sensor_report_interval rows buries the failure it is meant to explain.
    assert not violations, (
        f"{name} ({severity}) flagged the fixture: "
        f"{[_identify(r) for r in violations]}")


@pytest.mark.parametrize("name,fixtures,expected", _NEGATIVE_DQ_CASES)
def test_authored_check_rejects_invalid_fixture(spark, name, fixtures, expected):
    """Each negative fixture executes the exact authored check on the target engine."""
    assert _check_rows(spark, name, fixtures) == expected


_COLUMNS_FIXTURE_SCHEMA = "table_schema string, table_name string, column_name string"
_VIEWS_FIXTURE_SCHEMA = "table_schema string, table_name string, view_definition string"


def _columns_metadata_rows(spark, name, rows, schema="pr_130"):
    """Execute one information_schema.columns-based check against a fixture catalog.

    These checks are skipped by the suite above because they read Unity Catalog metadata
    rather than data. That is exactly why they need their own execution path: an
    unexercised metadata check is where the single-schema scoping bug below hid."""
    query = next(q for n, _, q in _parse_checks() if n == name)
    query = query.replace("${catalog}.information_schema.columns", "info_schema_columns")
    query = query.replace("${css_schema}", schema)
    spark.createDataFrame(rows, _COLUMNS_FIXTURE_SCHEMA) \
         .createOrReplaceTempView("info_schema_columns")
    return [tuple(r) for r in spark.sql(query).collect()]


def _views_metadata_rows(spark, name, rows, schema="pr_132"):
    """Execute one information_schema.views check under lean CI's --single_schema."""
    query = next(q for n, _, q in _parse_checks() if n == name)
    query = query.replace("${catalog}.information_schema.views", "info_schema_views")
    for token in ("css", "cmn", "bmv", "sdi", "product"):
        query = query.replace(f"${{{token}_schema}}", schema)
    spark.createDataFrame(rows, _VIEWS_FIXTURE_SCHEMA) \
         .createOrReplaceTempView("info_schema_views")
    return [tuple(r) for r in spark.sql(query).collect()]


def test_person_level_guard_ignores_other_domains_in_a_collapsed_schema(spark):
    """ADR 0029's guard must not fire on canonical-core's own person-level columns.

    The lean per-PR deploy gate passes --single_schema pr_<N>, which collapses EVERY
    domain's schema token onto one database, and FK closure deploys canonical-core there
    too. customer.profile legitimately carries `gender` (consented first-party profile
    data, not sensing output), so a check scoped by table_schema alone reported it as an
    ADR 0029 violation and failed the deploy gate."""
    rows = [
        # canonical-core, co-located by --single_schema: legitimate, must NOT be flagged.
        ("pr_130", "profile", "gender"),
        ("pr_130", "profile", "customer_sk"),
        # this package's own objects, clean.
        ("pr_130", "sensor_report_interval", "footfall_count"),
        ("pr_130", "rfid_read_event", "tagged_item_sk"),
        ("pr_130", "gold_zone_traffic_shared", "visitor_count"),
    ]
    assert _columns_metadata_rows(spark, "sri_no_person_level_columns", rows) == []


@pytest.mark.parametrize("table_name,column_name", [
    ("sensor_report_interval", "device_mac_address"),
    ("rfid_read_event", "shopper_person_id"),
    ("gold_zone_traffic_shared", "journey_path"),
    ("mv_zone_foot_traffic", "sentiment_score"),
])
def test_person_level_guard_still_flags_this_packages_objects(spark, table_name, column_name):
    """The scoping must not have hollowed the guardrail out: a never-publish column on
    any of the package's own tables, gold views or metric views is still a violation."""
    rows = [("pr_130", "profile", "gender"), ("pr_130", table_name, column_name)]
    assert _columns_metadata_rows(spark, "sri_no_person_level_columns", rows) == \
        [(column_name, table_name)]


def test_pricing_lineage_guard_ignores_css_price_analytics_in_collapsed_schema(spark):
    """CSS price-observation analytics are readers, not price-producing dependencies.

    Lean CI deploys every domain into pr_<N>. The guard must use object ownership rather
    than treating every price-named CSS view as if it lived in a pricing-owned schema.
    """
    rows = [
        ("pr_132", "gold_price_accuracy_current",
         "SELECT * FROM `ordm_cicd`.`pr_132`.`esl_price_observation`"),
        ("pr_132", "mv_price_accuracy",
         "SELECT * FROM ordm_cicd.pr_132.gold_price_accuracy_current"),
        # A pricing-owned view reading a non-CSS object is also legitimate.
        ("pr_132", "mv_price_actuals", "SELECT * FROM ordm_cicd.pr_132.product_price"),
        # A longer table name must not collide with the CSS object-name prefix.
        ("pr_132", "gold_price_forecast",
         "SELECT * FROM ordm_cicd.pr_132.shelf_state_observation_history"),
    ]
    assert _views_metadata_rows(
        spark, "css_no_sensing_to_pricing_lineage", rows
    ) == []


def test_pricing_lineage_guard_flags_css_input_in_collapsed_schema(spark):
    """Object scoping must preserve ADR 0030 when schema names all resolve to pr_<N>."""
    rows = [
        ("pr_132", "mv_price_actuals",
         "SELECT * FROM ordm_cicd.pr_132.product_price p "
         "JOIN `ordm_cicd`.`pr_132`.`shelf_state_observation` s ON TRUE"),
    ]
    assert _views_metadata_rows(
        spark, "css_no_sensing_to_pricing_lineage", rows
    ) == [("pr_132", "mv_price_actuals")]


def test_declared_interval_minutes_must_match_physical_boundaries(spark):
    violations = _check_rows(
        spark,
        "sri_interval_duration_agreement",
        [(
            "sensor_report_interval",
            "interval_start_ts timestamp, interval_end_ts timestamp, interval_minutes int",
            [(TS(2026, 3, 2, 9, 0), TS(2026, 3, 2, 9, 16, 40), 15)],
        )],
    )
    assert len(violations) == 1
    assert violations[0][2] == 15


def test_shared_threshold_uses_policy_effective_for_shared_date(spark):
    policy_schema = (
        "sensing_disclosure_policy_id string, k_threshold int, "
        "suppress_zero_flag boolean, effective_from_date date, "
        "effective_to_date date, is_current boolean"
    )
    shared_schema = (
        "store_id string, trading_date date, footfall_count long, "
        "sensing_disclosure_policy_id string"
    )
    fixtures = [
        (
            "sensing_disclosure_policy",
            policy_schema,
            [
                ("external_default", 10, True, D(2024, 1, 1), D(2026, 4, 1), False),
                ("external_default", 20, True, D(2026, 4, 1), None, True),
            ],
        ),
        (
            "gold_zone_traffic_shared",
            shared_schema,
            [("STR-1", D(2026, 3, 2), 12, "external_default")],
        ),
        ("gold_store_traffic_daily_shared", shared_schema, []),
    ]
    assert _check_rows(spark, "shared_suppression_threshold", fixtures) == []

    fixtures[1] = (
        "gold_zone_traffic_shared",
        shared_schema,
        [("STR-1", D(2026, 3, 2), 8, "external_default")],
    )
    violations = _check_rows(spark, "shared_suppression_threshold", fixtures)
    assert violations == [("zone", "STR-1", D(2026, 3, 2), 8)]


def test_zero_suppression_has_reachable_policy_configuration(spark):
    relationship_text = open(RELATIONSHIPS_SQL).read()
    match = re.search(
        r"chk_sdp_threshold\s+CHECK\s*\(([^)]+)\)",
        relationship_text,
        re.I,
    )
    assert match, "relationships.sql has no chk_sdp_threshold expression"

    predicate_rows = spark.sql(
        "SELECT k_threshold, " + match.group(1) + " AS is_valid "
        "FROM VALUES (0), (-1) AS policy(k_threshold)"
    ).collect()
    predicate = {row.k_threshold: row.is_valid for row in predicate_rows}
    assert predicate == {0: True, -1: False}

    policy_schema = (
        "sensing_disclosure_policy_id string, k_threshold int, "
        "suppress_zero_flag boolean, minimum_interval_minutes int, "
        "effective_from_date date, effective_to_date date, is_current boolean"
    )
    shared_schema = (
        "store_id string, trading_date date, footfall_count long, "
        "sensing_disclosure_policy_id string"
    )
    fixtures = [
        (
            "sensing_disclosure_policy",
            policy_schema,
            [("zero_only", 0, True, 15, D(2024, 1, 1), None, True)],
        ),
        (
            "gold_zone_traffic_shared",
            shared_schema,
            [("STR-1", D(2026, 3, 2), 0, "zero_only")],
        ),
        ("gold_store_traffic_daily_shared", shared_schema, []),
    ]
    assert _check_rows(spark, "sdp_valid_controls", fixtures) == []
    assert _check_rows(spark, "shared_zero_suppression", fixtures) == [
        ("zone", "STR-1", D(2026, 3, 2), 0)
    ]


def _identify(row):
    d = row.asDict()
    keys = ("sensor_report_interval_id", "store_zone_id", "sensor_device_id",
            "sensing_deployment_id", "store_id", "n")
    ident = {k: d[k] for k in keys if k in d}
    return ident or d


# ---------------------------------------------------------------------------
# 8. The grain key must not depend on the session timezone
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("session_tz", ["UTC", "America/Los_Angeles", "Asia/Kolkata"])
def test_grain_key_is_session_timezone_independent(spark, session_tz):
    """Regression test for a defect found by running the check suite (2026-07-28).

    The key originally embedded CAST(interval_start_ts AS STRING). Databricks TIMESTAMP is
    TIMESTAMP_LTZ, so that renders in the reader's spark.sql.session.timeZone — meaning the
    durable id was a property of the SESSION, not the row. Two consequences, both silent:
    sri_grain_key_wellformed flagged every row whenever the DQ run's timezone differed from
    the generator's, and a restatement under a different timezone would compute a different
    id and surrogate and therefore INSERT a duplicate instead of updating.

    Asia/Kolkata is in the list deliberately: its +05:30 offset catches an implementation
    that assumes whole-hour offsets."""
    original = spark.conf.get("spark.sql.session.timeZone")
    try:
        spark.conf.set("spark.sql.session.timeZone", session_tz)
        _build_with_core(spark)
        query = next(q for n, _, q in _parse_checks() if n == "sri_grain_key_wellformed")
        violations = spark.sql(_to_temp_views(query)).collect()
        assert not violations, (
            f"sri_grain_key_wellformed flags {len(violations)} row(s) under session "
            f"timeZone={session_tz}; the grain key is not an instant-based key")
    finally:
        spark.conf.set("spark.sql.session.timeZone", original)


@pytest.mark.parametrize("session_tz", ["UTC", "America/Los_Angeles", "Asia/Kolkata"])
def test_time_agreement_is_session_timezone_independent(spark, session_tz):
    """The same LTZ trap as above, in the check that polices time.

    sri_time_agreement compared trading_date against
    `CAST(interval_start_ts + make_interval(...) AS DATE)`. That cast resolves in
    spark.sql.session.timeZone, so an ERROR-severity check's verdict became a property of
    whoever ran the build: this fixture passed under UTC and flagged 6 rows under
    America/Los_Angeles. It is now computed in epoch space, and Kolkata's +05:30 is here to
    catch an implementation that assumes whole-hour offsets.

    Worth stating why this needed its own test rather than being caught by the suite above:
    the two checks are the same mistake in two places, and the earlier test pinned only the
    first, so passing it gave no information about the second.
    """
    original = spark.conf.get("spark.sql.session.timeZone")
    try:
        spark.conf.set("spark.sql.session.timeZone", session_tz)
        _build_with_core(spark)
        query = next(q for n, _, q in _parse_checks() if n == "sri_time_agreement")
        violations = spark.sql(_to_temp_views(query)).collect()
        assert not violations, (
            f"sri_time_agreement flags {len(violations)} row(s) under session "
            f"timeZone={session_tz}; the local-date derivation is not instant-based")
    finally:
        spark.conf.set("spark.sql.session.timeZone", original)


def test_sequence_gap_counts_lost_messages_not_duplicates(spark):
    """Raw message fields remain in Bronze; the interval fact carries only summaries.

    Two missing messages and one duplicate delivery are aggregated independently across
    two source sessions, without pretending that one interval row is one source message.
    """
    _build(spark)
    rows = [
        dict(
            _TEMP,
            source_session_id="SESSION-1",
            source_message_count=3,
            sequence_gap_count=2,
            duplicate_delivery_count=0,
        ),
        dict(
            _TEMP,
            sensor_report_interval_id=(
                "point|EQ-1|gs1:Temperature|subject|60|1772445600|DEV-2"
            ),
            interval_start_ts=TS(2026, 3, 2, 10, 0),
            interval_end_ts=TS(2026, 3, 2, 11, 0),
            source_session_id="SESSION-2",
            source_message_count=3,
            sequence_gap_count=0,
            duplicate_delivery_count=1,
        ),
    ]
    _build_interval_tables(spark, rows)
    _create_view(spark, "gold_css_device_health",
                 os.path.join(PKG, "gold", "gold_css_device_health.sql"))

    r = spark.sql("SELECT sequence_gap_count, duplicate_delivery_count, session_count "
                  "FROM gold_css_device_health WHERE sensor_device_id = 'DEV-2'").first()
    assert r.sequence_gap_count == 2
    assert r.duplicate_delivery_count == 1
    assert r.session_count == 2
