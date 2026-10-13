"""Static consistency tests for the Connected Store Signals outcome package.

Validate — without a Spark cluster — that the DDL, the generator column contracts, the
data-quality checks, the gold views, and the metric views stay mutually consistent.

Beyond the usual per-package guardrails, this file locks in the FIVE invariants the
package's correctness actually rests on, each of which is easy to break with a
well-intentioned edit and impossible to notice afterwards:

  1. sensor_report_interval's surrogate is a HASH, not IDENTITY (ADR 0028 — Hash
     surrogate keys for high-volume gold event facts), while the
     SCD2 masters and disclosure-policy dimension keep IDENTITY. A generator that supplies the wrong set of
     columns for either tier writes silently wrong data.
  2. The shared sensor interval envelope and its one-to-one foot-traffic extension stay
     separate, so other sensing solutions do not inherit traffic-only columns.
  3. Store and zone traffic are TWO metric views. Merging them back into one puts a store
     total and every zone total in the same SUM, and no comment can stop it because a
     metric view cannot require a filter.
  4. conversion_rate is NOT a published measure. Adding one would emit a number computed
     from an item count rather than a basket count.
  5. No person-level column exists anywhere in the package (ADR 0029 — Aggregate-only
     sensing schema with policy-driven shared disclosure).
"""

import ast
import glob
import os
import re

import pytest
import sqlglot
import sqlglot.expressions as E
import yaml

from tools.ordm_config import resolve

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PKG = os.path.join(REPO, "outcome-packages", "connected-store-signals")
TABLES_DIR = os.path.join(PKG, "tables")
GOLD_DIR = os.path.join(PKG, "gold")
MV_DIR = os.path.join(PKG, "metric-views")
CHECKS = os.path.join(PKG, "checks.sql")
COMMENTS = os.path.join(PKG, "comments.sql")
RELATIONSHIPS = os.path.join(PKG, "relationships.sql")
SMART_SHELF_GENERATOR = os.path.join(
    REPO, "runtime", "synthetic-data", "generators", "_smart_shelf.py"
)
GENERATOR_FILES = [
    os.path.join(REPO, "runtime", "synthetic-data", "generators", "connected_store_signals.py"),
    os.path.join(REPO, "runtime", "synthetic-data", "generators", "_rfid.py"),
    SMART_SHELF_GENERATOR,
]

TABLE_FILES = sorted(glob.glob(os.path.join(TABLES_DIR, "*.sql")))
GOLD_FILES = sorted(glob.glob(os.path.join(GOLD_DIR, "*.sql")))
MV_FILES = sorted(glob.glob(os.path.join(MV_DIR, "*.sql")))

_PK_RE = re.compile(r"CONSTRAINT\s+pk_[a-z_]+\s+PRIMARY\s+KEY\s*\(\s*([a-z_]+)\s*\)", re.I)

# table -> generator column-contract constant
COLUMNS_CONST = {
    "store_zone": "STORE_ZONE_COLUMNS",
    "sensing_deployment": "SENSING_DEPLOYMENT_COLUMNS",
    "sensing_disclosure_policy": "SENSING_DISCLOSURE_POLICY_COLUMNS",
    "sensor_device": "SENSOR_DEVICE_COLUMNS",
    "sensor_report_interval": "SENSOR_REPORT_INTERVAL_COLUMNS",
    "foot_traffic_interval_detail": "FOOT_TRAFFIC_INTERVAL_DETAIL_COLUMNS",
    "actuator_capability": "ACTUATOR_CAPABILITY_COLUMNS",
    "evaluation_rule": "EVALUATION_RULE_COLUMNS",
    "automation_action": "AUTOMATION_ACTION_COLUMNS",
    "execution_log": "EXECUTION_LOG_COLUMNS",
    "tagged_item": "TAGGED_ITEM_COLUMNS",
    "rfid_count_session": "RFID_COUNT_SESSION_COLUMNS",
    "rfid_read_event": "RFID_READ_EVENT_COLUMNS",
    "shelf_position_assignment": "SHELF_POSITION_ASSIGNMENT_COLUMNS",
    "shelf_state_observation": "SHELF_STATE_OBSERVATION_COLUMNS",
    "esl_label": "ESL_LABEL_COLUMNS",
    "esl_label_assignment": "ESL_LABEL_ASSIGNMENT_COLUMNS",
    "esl_price_observation": "ESL_PRICE_OBSERVATION_COLUMNS",
}

# The IDENTITY / hash split from ADR 0028. Masters keep IDENTITY (so Delta assigns the
# _sk and the generator must NOT supply it); the high-volume restated fact derives its
# _sk by hash (so the generator MUST supply it).
IDENTITY_TABLES = {
    "store_zone", "sensing_deployment", "sensing_disclosure_policy", "sensor_device",
    # Automation loop: three SCD2 masters plus the moderate-volume append-only
    # execution_log fact. All keep IDENTITY (the generator omits the _sk); ADR 0028's
    # hash-key exception is only for the high-volume, restated sensor_report_interval.
    "actuator_capability", "evaluation_rule", "automation_action", "execution_log",
    "rfid_count_session",
    "shelf_position_assignment", "esl_label", "esl_label_assignment",
}
HASH_SK_TABLES = {
    "sensor_report_interval", "tagged_item", "rfid_read_event",
    "shelf_state_observation", "esl_price_observation",
}
HASH_COLLISION_CHECKS = {
    "sensor_report_interval": "sri_sk_collision",
    "tagged_item": "ti_sk_collision",
    "rfid_read_event": "rre_sk_collision",
    "shelf_state_observation": "sso_sk_collision",
    "esl_price_observation": "eslp_sk_collision",
}
EXTENSION_TABLES = {"foot_traffic_interval_detail"}

SMART_SHELF_ENUM_CONSTS = {
    ("shelf_position_assignment", "assignment_source"): "ASSIGNMENT_SOURCES",
    ("shelf_position_assignment", "assignment_status"): "ASSIGNMENT_STATUSES",
    ("shelf_state_observation", "shelf_state"): "SHELF_STATES",
    ("shelf_state_observation", "zone_source"): "SHELF_ZONE_SOURCES",
    ("shelf_state_observation", "measurement_validity"): "MEASUREMENT_VALIDITIES",
    ("shelf_state_observation", "arrival_completeness"): "ARRIVAL_COMPLETENESS_VALUES",
    ("esl_label", "display_technology"): "DISPLAY_TECHNOLOGIES",
    ("esl_label", "battery_life_class"): "BATTERY_LIFE_CLASSES",
    ("esl_label", "label_status"): "LABEL_STATUSES",
    ("esl_label_assignment", "binding_source"): "BINDING_SOURCES",
    ("esl_label_assignment", "binding_status"): "BINDING_STATUSES",
    ("esl_price_observation", "observation_source"): "PRICE_OBSERVATION_SOURCES",
    ("esl_price_observation", "price_of_record_source"): "PRICE_OF_RECORD_SOURCES",
}

# ADR 0029's never-publish list. Asserted here as a SCHEMA-LEVEL absence, not a masking
# rule: the Enschede decision penalised the CAPABILITY to track absent any evidence of
# tracking, so the defence has to be that the column cannot exist.
FORBIDDEN_COLUMN_FRAGMENTS = [
    "mac_address", "face_", "person_id", "track_id", "journey_path",
    "emotion", "sentiment", "gender", "ethnicity", "age_bracket",
    "reidentification_key", "device_mac",
]


def _text(path):
    return resolve(open(path).read(), "c")  # ${catalog}/${*_schema} -> identifiers


def _create(path):
    return next((s for s in sqlglot.parse(_text(path), read="databricks", error_level="ignore")
                 if isinstance(s, E.Create)), None)


def _generator_constants():
    out = {}
    for path in GENERATOR_FILES:
        mod = ast.parse(open(path).read())
        for node in mod.body:
            if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name) \
                    and isinstance(node.value, ast.List) and all(isinstance(e, ast.Constant) for e in node.value.elts):
                out[node.targets[0].id] = [e.value for e in node.value.elts]
    return out


def _ddl_columns(path):
    return {c.name for c in _create(path).find_all(E.ColumnDef)}


def _metric_doc(filename):
    """Parse one UC metric-view YAML document from its dollar-quoted SQL body."""
    text = open(os.path.join(MV_DIR, filename)).read()
    match = re.search(
        r"WITH\s+METRICS\s+LANGUAGE\s+YAML\s+AS\s*\$\$(.*?)\$\$",
        text,
        re.I | re.S,
    )
    assert match, f"{filename} has no metric-view YAML body"
    return yaml.safe_load(match.group(1))


# ---------- table DDL ----------

@pytest.mark.parametrize("path", TABLE_FILES, ids=[os.path.basename(f) for f in TABLE_FILES])
def test_table_parses_and_has_pk_contract(path):
    create = _create(path)
    assert create is not None, f"{os.path.basename(path)} did not parse as a CREATE TABLE"
    m = _PK_RE.search(open(path).read())
    assert m, f"{os.path.basename(path)} has no CONSTRAINT pk_<t> PRIMARY KEY (<col>)"
    pk_col = m.group(1)
    assert pk_col.endswith("_sk"), f"{os.path.basename(path)} PK is not a surrogate _sk"
    if os.path.basename(path)[:-4] in EXTENSION_TABLES:
        assert pk_col == "sensor_report_interval_sk"
        return
    stem = pk_col[:-len("_sk")]
    assert f"{stem}_id" in _ddl_columns(path), f"{os.path.basename(path)} missing durable {stem}_id"


def test_expected_table_set_present():
    names = {os.path.basename(f)[:-4] for f in TABLE_FILES}
    expected = {
        "store_zone", "sensing_deployment", "sensing_disclosure_policy",
        "sensor_device", "sensor_report_interval", "foot_traffic_interval_detail",
        # Automation loop (IoT Sensor Monitoring): sense -> evaluate -> act -> log.
        "actuator_capability", "evaluation_rule", "automation_action", "execution_log",
        "tagged_item", "rfid_count_session", "rfid_read_event",
        "shelf_position_assignment", "shelf_state_observation", "esl_label",
        "esl_label_assignment", "esl_price_observation",
    }
    assert names == expected, f"table set drift: missing={sorted(expected - names)} extra={sorted(names - expected)}"


def test_sensor_interval_core_and_traffic_extension_are_separated():
    """A traffic column returning to the shared envelope would make every future sensing
    solution inherit a wide sparse schema; a missing detail measure would break the first
    vertical slice."""
    core = _ddl_columns(os.path.join(TABLES_DIR, "sensor_report_interval.sql"))
    detail = _ddl_columns(os.path.join(TABLES_DIR, "foot_traffic_interval_detail.sql"))

    assert {
        "sensor_report_interval_sk", "sensor_report_interval_id",
        "subject_type", "subject_id", "report_type", "aggregation_level",
        "interval_start_ts", "interval_end_ts", "interval_minutes",
        "source_observation_count", "expected_observation_count",
    } <= core
    assert {
        "footfall_count", "entry_count", "exit_count", "passersby_count",
        "counting_unit", "visitor_count_raw", "visitor_count_adjusted",
        "occupancy_snapshot_end", "occupancy_max",
        "dwell_seconds_total", "dwell_count",
    }.isdisjoint(core)
    assert {
        "sensor_report_interval_sk", "footfall_count", "entry_count",
        "exit_count", "dwell_seconds_total", "dwell_count",
    } <= detail


@pytest.mark.parametrize("table", sorted(IDENTITY_TABLES))
def test_master_keeps_identity_surrogate(table):
    """ADR 0028 changed the key derivation only for the high-volume fact. The SCD2
    masters are low-volume and not restated, so ADR 0004 applies to them as written."""
    txt = open(os.path.join(TABLES_DIR, f"{table}.sql")).read()
    assert "GENERATED ALWAYS AS IDENTITY" in txt, f"{table} lost its IDENTITY surrogate"


@pytest.mark.parametrize("table", sorted(HASH_SK_TABLES))
def test_high_volume_fact_uses_hash_surrogate(table):
    """The two halves of ADR 0028 that must hold together: no IDENTITY (it disables
    concurrent transactions and would change on every restatement of the same logical
    row), and a collision guard, because xxhash64 is only 64 bits."""
    txt = open(os.path.join(TABLES_DIR, f"{table}.sql")).read()
    assert "GENERATED ALWAYS AS IDENTITY" not in txt, (
        f"{table} declares an IDENTITY column — ADR 0028 forbids it on this tier because "
        "it disables concurrent transactions and is not stable across restatement")
    check_name = HASH_COLLISION_CHECKS[table]
    assert check_name in open(CHECKS).read(), f"{table} hash surrogate has no collision guard"


def test_no_person_level_columns_anywhere():
    """ADR 0029's structural half. Every DDL column name in the package is checked, not
    just the fact's, because a person-level column on a DIMENSION would be just as much
    of a disclosure."""
    for path in TABLE_FILES:
        for col in _ddl_columns(path):
            for bad in FORBIDDEN_COLUMN_FRAGMENTS:
                assert bad not in col.lower(), (
                    f"{os.path.basename(path)} declares '{col}', which matches the ADR 0029 "
                    f"never-publish fragment '{bad}'")


def _deployed_view_name(path):
    """The object name a gold/metric-view file actually creates (metric views are
    deployed with an `mv_` prefix, so the filename is not the object name)."""
    m = re.search(r"CREATE\s+(?:OR\s+REPLACE\s+)?(?:MATERIALIZED\s+)?VIEW\s+"
                  r"\$\{catalog\}\.\$\{\w+_schema\}\.(\w+)", open(path).read(), re.I)
    assert m, f"{os.path.basename(path)} has no CREATE VIEW for the package schema"
    return m.group(1)


def _person_level_guard_scope():
    """The table_name IN (...) list of the sri_no_person_level_columns check."""
    body = re.search(r"--\s*check:\s*sri_no_person_level_columns\s*\|.*?;",
                     open(CHECKS).read(), re.S | re.I)
    assert body, "sri_no_person_level_columns is missing from checks.sql"
    in_list = re.search(r"table_name\s+IN\s*\((.*?)\)", body.group(0), re.S | re.I)
    assert in_list, (
        "sri_no_person_level_columns must scope itself with `table_name IN (...)`. The "
        "lean per-PR gate deploys every domain into ONE schema (--single_schema pr_<N>), "
        "so filtering on table_schema alone also matches canonical-core tables whose "
        "person-level columns are legitimate (customer.profile.gender) — that reported a "
        "false ADR 0029 violation and failed the deploy gate.")
    return set(re.findall(r"'(\w+)'", in_list.group(1)))


def _pricing_lineage_guard_scope():
    """The css_objects VALUES list used to disambiguate --single_schema ownership."""
    body = re.search(r"--\s*check:\s*css_no_sensing_to_pricing_lineage\s*\|.*?;",
                     open(CHECKS).read(), re.S | re.I)
    assert body, "css_no_sensing_to_pricing_lineage is missing from checks.sql"
    values = re.search(
        r"WITH\s+css_objects\s*\(\s*object_name\s*\)\s+AS\s*\(\s*VALUES(.*?)\)\s*SELECT",
        body.group(0), re.S | re.I)
    assert values, (
        "css_no_sensing_to_pricing_lineage must identify CSS objects by name; lean CI "
        "collapses all schema tokens into one pr_<N> schema")
    return set(re.findall(r"\(\s*'(\w+)'\s*\)", values.group(1)))


def test_person_level_guard_covers_every_package_object():
    """ADR 0029's deployed half must cover the package's WHOLE published surface.

    The check is scoped by object name (see _person_level_guard_scope), which buys
    correctness under the single-schema PR gate but would otherwise let a newly added
    table or view escape the guardrail silently. Views matter most here: the static
    test above reads DDL only, so a gold/metric view is covered by this check alone."""
    expected = {os.path.basename(p)[:-4] for p in TABLE_FILES}
    expected |= {_deployed_view_name(p) for p in GOLD_FILES + MV_FILES}
    scoped = _person_level_guard_scope()
    assert scoped == expected, (
        "sri_no_person_level_columns' table_name list is out of sync with the package.\n"
        f"  missing from the check (NOT guarded): {sorted(expected - scoped)}\n"
        f"  in the check but not in the package:  {sorted(scoped - expected)}")


def test_pricing_lineage_guard_covers_every_package_object():
    """A new CSS object must not silently escape ADR 0030 in collapsed-schema CI."""
    expected = {os.path.basename(p)[:-4] for p in TABLE_FILES}
    expected |= {_deployed_view_name(p) for p in GOLD_FILES + MV_FILES}
    scoped = _pricing_lineage_guard_scope()
    assert scoped == expected, (
        "css_no_sensing_to_pricing_lineage's css_objects list is out of sync.\n"
        f"  missing from the check (NOT guarded): {sorted(expected - scoped)}\n"
        f"  in the check but not in the package:  {sorted(scoped - expected)}")


def test_person_level_guard_excludes_other_domains_objects():
    """The scope must name only THIS package's objects. Under --single_schema every
    domain lands in one database, so listing a canonical-core table here would
    re-introduce the false positive that failed the gate."""
    foreign = {os.path.basename(p)[:-4]
               for p in glob.glob(os.path.join(REPO, "canonical-core", "*", "tables", "*.sql"))}
    overlap = _person_level_guard_scope() & foreign
    assert not overlap, (
        f"the ADR 0029 guard names canonical-core object(s) {sorted(overlap)}; their "
        "person-level columns are legitimate in their own domain and would fail the "
        "single-schema PR deploy gate")


def test_additivity_contract_is_structural():
    """aggregation_level must be NOT NULL. If it were nullable, a row of unknown level
    could be summed with rows of a known level and the additivity contract would be
    advisory rather than structural."""
    txt = open(os.path.join(TABLES_DIR, "sensor_report_interval.sql")).read()
    assert re.search(r"aggregation_level\s+STRING\s+NOT\s+NULL", txt), (
        "aggregation_level must be NOT NULL — it is the column that makes 'footfall does "
        "not sum across zones' a structural fact rather than documentation")


def test_time_contract_has_offset_and_no_local_timestamp():
    """utc_offset_minutes is the DST fix. And there must be NO local wall-clock TIMESTAMP
    column: Databricks TIMESTAMP is TIMESTAMP_LTZ, rendered in the reader's session
    timezone, so a stored local time shifts per consumer."""
    txt = open(os.path.join(TABLES_DIR, "sensor_report_interval.sql")).read()
    assert re.search(r"utc_offset_minutes\s+SMALLINT\s+NOT\s+NULL", txt)
    assert not re.search(r"interval_start_local_ts\s+TIMESTAMP\b", txt), (
        "a local wall-clock TIMESTAMP column reintroduces the LTZ shifting bug")


# ---------- generator <-> DDL ----------

@pytest.mark.parametrize("path", TABLE_FILES, ids=[os.path.basename(f) for f in TABLE_FILES])
def test_generator_columns_match_ddl(path):
    """The generator contract must equal the DDL columns, MINUS the identity surrogate
    where there is one. Getting the hash/identity split wrong here is the specific way
    ADR 0028 breaks silently: _write() would either reject a supplied identity column or
    leave the hash surrogate NULL."""
    table = os.path.basename(path)[:-4]
    gen = set(_generator_constants()[COLUMNS_CONST[table]])
    ddl = _ddl_columns(path)
    if table in IDENTITY_TABLES:
        pk = _PK_RE.search(open(path).read()).group(1)
        ddl = ddl - {pk}
    assert gen == ddl, f"{table} column drift — missing={sorted(ddl - gen)} extra={sorted(gen - ddl)}"


@pytest.mark.parametrize(
    "table,column,const_name",
    [(table, column, const) for (table, column), const in SMART_SHELF_ENUM_CONSTS.items()],
)
def test_smart_shelf_generator_enums_equal_delta_contract(table, column, const_name):
    """Equality guarantees the generator declares every value, not merely a valid subset."""
    relationships = open(RELATIONSHIPS).read()
    match = re.search(
        rf"ALTER\s+TABLE\s+[^;]*\.{table}\s+ADD\s+CONSTRAINT\s+[^;]*"
        rf"\b{column}\b[^;]*?\bIN\s*\(([^)]*)\)",
        relationships,
        re.I,
    )
    assert match, f"no Delta enum constraint found for {table}.{column}"
    ddl_values = set(re.findall(r"'([^']+)'", match.group(1)))
    generated_values = set(_generator_constants()[const_name])
    assert generated_values == ddl_values, (
        f"{table}.{column} enum drift — missing={sorted(ddl_values - generated_values)} "
        f"extra={sorted(generated_values - ddl_values)}"
    )


def test_smart_shelf_seed_volumes_preserve_mandatory_scenarios():
    seeds = yaml.safe_load(open(os.path.join(REPO, "runtime", "synthetic-data", "seeds.yaml")))
    volumes = seeds["domains"]["connected_store_signals"]["volumes"]
    assert volumes["positions_per_store"] >= 3
    assert volumes["products_per_position"] >= 1
    assert volumes["captures_per_day_per_platform"] >= 6
    assert volumes["price_change_observations"] >= 5


def test_smart_shelf_stays_a_plain_helper_under_the_one_css_provider():
    helper_tree = ast.parse(open(SMART_SHELF_GENERATOR).read())
    top_level_functions = {
        node.name for node in helper_tree.body if isinstance(node, ast.FunctionDef)
    }
    assert "run" not in top_level_functions

    main = open(GENERATOR_FILES[0]).read()
    assert main.count("generate_smart_shelf(ctx, cfg)") == 1


def test_smart_shelf_high_volume_generation_is_distributed_and_dbldatagen_backed():
    source = open(SMART_SHELF_GENERATOR).read()
    tree = ast.parse(source)
    banned_methods = {"collect", "toPandas", "createDataFrame", "cache", "persist"}
    offenders = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in banned_methods
    }
    assert not offenders
    assert "Window.orderBy(" not in source, "global unpartitioned window in Smart Shelf helper"

    observation_fn = next(
        node for node in tree.body
        if isinstance(node, ast.FunctionDef)
        and node.name == "generate_shelf_state_observation"
    )
    observation_source = ast.get_source_segment(source, observation_fn)
    assert "dg.DataGenerator(" in observation_source


def test_smart_shelf_ids_and_two_row_misplacement_are_source_stable():
    source = open(SMART_SHELF_GENERATOR).read()
    assert '.withColumn("source_capture_id"' in source
    assert '.withColumn("source_observation_id"' in source
    assert '.withColumn("shelf_state_observation_sk", F.xxhash64("shelf_state_observation_id"))' in source
    assert '.withColumn("esl_price_observation_sk", F.xxhash64("esl_price_observation_id"))' in source
    assert 'F.lit("CAP-MISPLACED-")' in source
    assert "expected = _observation_key(scenario)" in source
    assert "wrong = _observation_key(wrong)" in source


# ---------- gold views ----------

@pytest.mark.parametrize("path", GOLD_FILES, ids=[os.path.basename(f) for f in GOLD_FILES])
def test_gold_view_parses(path):
    stmt = sqlglot.parse_one(_text(path), read="databricks", error_level="ignore")
    assert isinstance(stmt, E.Create), f"{os.path.basename(path)} did not parse as CREATE VIEW"


def test_expected_gold_set_present():
    names = {os.path.basename(f)[:-4] for f in GOLD_FILES}
    expected = {
        "gold_store_traffic_daily_current", "gold_zone_traffic_current",
        "gold_store_traffic_daily_shared", "gold_zone_traffic_shared",
        "gold_zone_traffic_interval_shared",
        "gold_traffic_sales_productivity_current", "gold_css_device_health",
        "gold_css_automation_response",
        "gold_css_environmental_compliance_daily", "gold_css_excursion_episodes",
        "gold_css_rule_effectiveness_daily",
        "gold_item_current_state", "gold_zone_item_presence_current",
        "gold_inventory_accuracy_daily", "gold_inventory_accuracy_daily_latest",
        "gold_count_session_summary",
        "gold_zone_count_coverage", "gold_receiving_verification",
        "gold_rfid_oos_candidates", "gold_unaccounted_exits",
        "gold_item_visibility_daily",
        "gold_shelf_state_current", "gold_osa_daily_current",
        "gold_planogram_compliance_current", "gold_share_of_shelf_current",
        "gold_price_accuracy_current", "gold_observed_oos_episodes",
        "gold_shelf_vs_system_variance_daily",
    }
    assert names == expected, f"gold set drift: missing={sorted(expected - names)} extra={sorted(names - expected)}"


def test_traffic_gold_views_pin_report_type_and_level():
    """The three controls that make ONE wide sparse fact safe (ADR 0032) include
    report_type-scoped gold views. A view that forgot either filter would silently mix
    temperature rows into a footfall total, or mix aggregation levels."""
    for name in ("gold_store_traffic_daily_current", "gold_zone_traffic_current"):
        txt = open(os.path.join(GOLD_DIR, f"{name}.sql")).read()
        assert "report_type = 'gs1:Count'" in txt, f"{name} does not pin report_type"
        assert re.search(r"aggregation_level\s*=\s*'(site|area)'", txt), \
            f"{name} does not pin aggregation_level"


def test_sales_productivity_replaces_the_conversion_surface():
    """Until the canonical model has a transaction or receipt count, even a NULL
    conversion column advertises a semantic surface the model cannot support."""
    assert not os.path.exists(os.path.join(GOLD_DIR, "gold_traffic_conversion_current.sql"))
    txt = open(os.path.join(GOLD_DIR, "gold_traffic_sales_productivity_current.sql")).read()
    assert "sales_per_entry" in txt and "units_per_entry" in txt
    assert "sales_per_footfall" in txt and "units_per_footfall" in txt
    assert "conversion_rate" not in txt
    assert "conversion_numerator_basis" not in txt
    assert "conversion_denominator_basis" not in txt


def test_sales_productivity_metric_view_names_each_denominator_honestly():
    """Entry and footfall are distinct observations and must stay distinct measures."""
    txt = open(os.path.join(MV_DIR, "traffic_sales_productivity.sql")).read()
    assert "SUM(net_revenue) / NULLIF(SUM(entry_count), 0)" in txt
    assert "SUM(net_revenue) / NULLIF(SUM(footfall_count), 0)" in txt
    assert "SUM(units) / NULLIF(SUM(entry_count), 0)" in txt
    assert "SUM(units) / NULLIF(SUM(footfall_count), 0)" in txt
    assert '"sales_per_visit"' not in txt


def test_dwell_is_never_a_stored_average():
    """Dwell is stored as SUM + COUNT so it re-aggregates. A view reading the FACT must
    derive the average from both, and must carry both forward — a pre-computed average
    alone cannot be rolled up to a coarser grain.

    Views that read another gold view rather than the fact are exempt: the derivation
    already happened once, correctly, upstream."""
    for path in GOLD_FILES:
        txt = open(path).read()
        reads_fact = "sensor_report_interval" in txt
        if "avg_dwell_seconds" in txt and reads_fact:
            assert "dwell_seconds_total" in txt and "dwell_count" in txt, (
                f"{os.path.basename(path)} exposes avg_dwell_seconds without the "
                "numerator and denominator it must be derived from")


def test_zone_daily_is_scd2_safe_and_uses_duration_weighted_space():
    """A mid-day zone refit must remain one durable zone-day with an honest density.

    Facts resolve their exact dimension versions through the surrogate key; the gold
    view then consolidates versions by durable id and weights area by measured minutes.
    """
    txt = open(os.path.join(GOLD_DIR, "gold_zone_traffic_current.sql")).read()
    assert re.search(
        r"ON\s+f\.store_zone_sk\s*=\s*z\.store_zone_sk", txt, re.I
    )
    assert re.search(
        r"GROUP\s+BY\s+f\.store_id,\s*f\.store_zone_id,\s*f\.trading_date",
        txt,
        re.I,
    )
    assert "SUM(z.area_sqm * f.interval_minutes)" in txt
    assert "z.is_current" not in txt


def test_sensor_report_interval_clustering_keys_have_delta_statistics():
    """Every liquid-clustering key must have file-skipping statistics.

    Databricks collects statistics for only the first 32 columns by default on
    this deployment path. A wider table must explicitly name any later
    clustering key through delta.dataSkippingStatsColumns.
    """
    path = os.path.join(TABLES_DIR, "sensor_report_interval.sql")
    text = _text(path)
    columns = [column.name for column in _create(path).find_all(E.ColumnDef)]
    cluster_match = re.search(r"CLUSTER\s+BY\s*\(([^)]+)\)", text, re.I)
    assert cluster_match, "sensor_report_interval must declare liquid clustering keys"
    cluster_keys = {
        value.strip().strip("`")
        for value in cluster_match.group(1).split(",")
    }

    stats_match = re.search(
        r"delta\.dataSkippingStatsColumns\s*=\s*'([^']+)'",
        text,
        re.I,
    )
    indexed_count_match = re.search(
        r"delta\.dataSkippingNumIndexedCols['\"]?\s*=\s*['\"]?(\d+)",
        text,
        re.I,
    )
    if stats_match:
        stats_columns = {
            value.strip() for value in stats_match.group(1).split(",")
        }
    else:
        indexed_count = int(indexed_count_match.group(1)) if indexed_count_match else 32
        stats_columns = set(columns[:indexed_count])

    assert cluster_keys <= stats_columns, (
        "liquid clustering keys without Delta statistics: "
        f"{sorted(cluster_keys - stats_columns)}"
    )


# ---------- metric views ----------

def test_smart_shelf_latest_capture_is_ranked_before_enrichment_or_usability():
    text = open(os.path.join(GOLD_DIR, "gold_shelf_state_current.sql")).read()
    ranked = text.split("), latest AS", 1)[0]
    assert "sensor_device" not in ranked
    assert not re.search(r"\bWHERE\b", ranked, re.I)
    assert "WHERE r.state_rank = 1" in text
    assert "LEFT JOIN ${catalog}.${css_schema}.sensor_device" in text


def test_smart_shelf_daily_denominators_keep_unknown_and_unobserved_separate():
    for filename in (
        "gold_osa_daily_current.sql",
        "gold_planogram_compliance_current.sql",
    ):
        text = open(os.path.join(GOLD_DIR, filename)).read()
        for column in (
            "positions_expected" if "planogram" in filename else "expected_positions",
            "positions_observed" if "planogram" in filename else "observed_positions",
            "positions_known", "positions_unknown",
            "positions_unobserved", "observation_coverage_pct", "known_state_pct",
        ):
            assert column in text, f"{filename} omits denominator component {column}"


def test_shelf_inventory_variance_uses_the_days_last_usable_reading():
    text = open(os.path.join(GOLD_DIR, "gold_shelf_vs_system_variance_daily.sql")).read()
    usable = text.split("), usable_position_day AS", 1)[0].split("usable_ranked AS", 1)[1]
    assert "ROW_NUMBER() OVER" in usable
    assert "measurement_validity" in usable and "shelf_state <> 'unknown'" in usable
    assert "observed_position_day" in text
    assert "same-date inventory snapshot" in text


def test_smart_shelf_current_views_propagate_one_named_clock():
    for filename in (
        "gold_shelf_state_current.sql", "gold_osa_daily_current.sql",
        "gold_planogram_compliance_current.sql", "gold_share_of_shelf_current.sql",
        "gold_price_accuracy_current.sql",
    ):
        text = open(os.path.join(GOLD_DIR, filename)).read()
        assert "fresh_as_of_ts" in text, f"{filename} drops the evaluation instant"
        assert "current_timestamp()" not in text, f"{filename} bypasses the named shelf clock"


def test_smart_shelf_metric_view_semantic_metadata_is_complete():
    for filename in (
        "on_shelf_availability.sql", "planogram_compliance.sql", "price_accuracy.sql",
    ):
        doc = _metric_doc(filename)
        assert doc["version"] == 1.1
        for kind in ("fields", "measures"):
            for item in doc[kind]:
                for key in ("display_name", "comment", "synonyms"):
                    assert item.get(key), f"{filename} {item['name']} lacks {key}"


def test_smart_shelf_metric_views_use_durable_ids_and_recomposable_measures():
    docs = {
        name: _metric_doc(name)
        for name in (
            "on_shelf_availability.sql", "planogram_compliance.sql", "price_accuracy.sql",
        )
    }
    for filename, doc in docs.items():
        assert not any(str(field["expr"]).strip().endswith("_sk") for field in doc["fields"]), (
            f"{filename} exposes a version-specific surrogate as a dimension"
        )

    plan_measures = {item["name"]: item["expr"] for item in docs["planogram_compliance.sql"]["measures"]}
    assert "COUNT(DISTINCT CASE" in plan_measures["products_measured"]
    assert "product_id" in plan_measures["products_measured"]

    price_measures = {item["name"]: item["expr"] for item in docs["price_accuracy.sql"]["measures"]}
    assert "COUNT(DISTINCT currency_code) = 1" in price_measures["max_mismatch_amount"]
    assert price_measures["avg_correction_hours"] == (
        "SUM(correction_hours_total) / NULLIF(SUM(labels_corrected), 0)"
    )


@pytest.mark.parametrize("path", MV_FILES, ids=[os.path.basename(f) for f in MV_FILES])
def test_metric_view_yaml_shape(path):
    """UC metric views: version 1.1, a `fields:` block (not `dimensions:`), and a
    `measures:` block. `type:` is not part of the spec."""
    txt = open(path).read()
    assert "WITH METRICS LANGUAGE YAML" in txt
    assert re.search(r"^version:\s*1\.1$", txt, re.M), f"{os.path.basename(path)} missing version: 1.1"
    assert re.search(r"^fields:$", txt, re.M), f"{os.path.basename(path)} uses no fields: block"
    assert re.search(r"^measures:$", txt, re.M), f"{os.path.basename(path)} uses no measures: block"


@pytest.mark.parametrize("path", MV_FILES, ids=[os.path.basename(f) for f in MV_FILES])
def test_metric_view_expressions_resolve_to_source_columns(path):
    """Every field and measure reference must exist in the metric view's gold source."""
    filename = os.path.basename(path)
    doc = _metric_doc(filename)
    source_match = re.search(
        r"\$\{catalog\}\.\$\{\w+_schema\}\.([a-z_]\w*)",
        doc["source"],
        re.I,
    )
    assert source_match, f"{filename} source does not name one local view"
    source_name = source_match.group(1)
    source_path = os.path.join(GOLD_DIR, f"{source_name}.sql")
    assert os.path.exists(source_path), (
        f"{filename} source {source_name} has no local gold SQL"
    )

    create = sqlglot.parse_one(_text(source_path), read="databricks")
    source_columns = set(create.expression.named_selects)
    dangling = {}
    for item in [*doc.get("fields", []), *doc.get("measures", [])]:
        expression = sqlglot.parse_one(item["expr"], read="databricks")
        missing = sorted(
            {column.name for column in expression.find_all(E.Column)}
            - source_columns
        )
        if missing:
            dangling[item["name"]] = missing

    assert not dangling, (
        f"{filename} references columns absent from {source_name}: {dangling}"
    )


def test_traffic_metric_views_are_one_level_each():
    """The two levels must be two OBJECTS, because a metric view cannot require a field.

    An earlier design UNION-ALLed the site and area gold views into one mv_foot_traffic and
    relied on aggregation_level being exposed as a field, with a comment calling it
    'mandatory'. Nothing enforced that: `SELECT footfall FROM mv_foot_traffic` — the shortest
    question a Genie user can ask, and the one Genie generates — returned the store total
    PLUS every zone total, so a store with nine zones reported roughly ten times its
    traffic. Non-additivity across levels can only be enforced by the object boundary, so
    this test pins that neither view can grow a second level back.
    """
    store = open(os.path.join(MV_DIR, "store_foot_traffic.sql")).read()
    zone = open(os.path.join(MV_DIR, "zone_foot_traffic.sql")).read()

    assert not os.path.exists(os.path.join(MV_DIR, "foot_traffic.sql")), (
        "the level-mixing mv_foot_traffic is back; store and zone traffic must stay in "
        "separate metric views")

    for name, txt in (("store_foot_traffic", store), ("zone_foot_traffic", zone)):
        assert "UNION ALL" not in txt.upper(), (
            f"{name} UNION-ALLs more than one source — that is how the level-mixing "
            "defect returns")
        assert not re.search(r"-\s*name:\s*aggregation_level", txt), (
            f"{name} exposes aggregation_level as a groupable field, which only makes "
            "sense if the view holds more than one level")

    assert "aggregation_level = 'site'" in store
    assert "aggregation_level = 'area'" in zone


def test_traffic_averages_are_recomputed_not_averaged():
    """A ratio measure in a metric view must divide summed parts, never average a
    per-row ratio: AVG() of an average weights a near-empty store-day the same as a busy
    one. Occupancy specifically must be weighted by MINUTES, not by interval count:
    different canonical series may use different cadences, so a count weighting can
    silently give a quarter-hour the same say as an hour.
    """
    for name in (
        "store_foot_traffic.sql", "zone_foot_traffic.sql",
        "traffic_sales_productivity.sql",
    ):
        txt = open(os.path.join(MV_DIR, name)).read()
        exprs = "\n".join(re.findall(r"^\s*expr:.*$", txt, re.M))
        if "avg_dwell_seconds" in txt:
            assert "SUM(dwell_seconds_total) / NULLIF(SUM(dwell_count), 0)" in exprs, (
                f"{name} must recompute avg_dwell_seconds from the stored SUM and COUNT")
            assert "AVG(avg_dwell_seconds)" not in exprs, f"{name} averages an average dwell"
        if "name: avg_occupancy" in txt:
            assert "interval_minutes_total" in exprs, (
                f"{name} weights avg_occupancy by something other than interval minutes")
            assert "AVG(avg_occupancy)" not in exprs, f"{name} averages an average occupancy"

    # Only `expr:` lines are inspected. The comments in these files argue AGAINST the wrong
    # aggregation by naming it, so scanning the whole text would fail on the explanation.
    health = "\n".join(re.findall(r"^\s*expr:.*$",
                                  open(os.path.join(MV_DIR, "device_health.sql")).read(), re.M))
    assert "AVG(missing_observation_rate)" not in health, (
        "the primary fleet KPI must divide SUM(received) by SUM(expected); averaging "
        "per-device rates lets a device expecting 4 observations outvote one expecting 400")
    assert "SUM(observations_received)" in health and "SUM(observations_expected)" in health


def test_no_metric_view_publishes_conversion_rate():
    for path in MV_FILES:
        txt = open(path).read()
        assert not re.search(r"-\s*name:\s*conversion_rate", txt), (
            f"{os.path.basename(path)} publishes conversion_rate; ORDM has no transaction "
            "count, so use sales_per_visitor / units_per_visitor instead")


# ---------- data-quality checks ----------

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


def test_dq_checks_well_formed():
    checks = _parse_checks(open(CHECKS).read())
    assert len(checks) >= 30, f"expected a meaningful suite, found {len(checks)}"
    names = [c[0] for c in checks]
    assert len(names) == len(set(names)), "duplicate check names"
    for name, severity, query in checks:
        assert severity in ("error", "warn", "metric")
        scopes_package_by_schema = (
            "${catalog}.${css_schema}." in query or "'${css_schema}'" in query
        )
        scopes_package_by_object = (
            name == "css_no_sensing_to_pricing_lineage"
            and "WITH css_objects(object_name) AS" in query
            and "${catalog}.information_schema.views" in query
        )
        assert scopes_package_by_schema or scopes_package_by_object, \
            f"{name} does not reference the package schema or its explicit object scope"


def test_every_table_has_a_check():
    text = open(CHECKS).read()
    for path in TABLE_FILES:
        t = os.path.basename(path)[:-4]
        assert f"${{catalog}}.${{css_schema}}.{t}" in text, f"no DQ check covers {t}"


def test_the_load_bearing_checks_exist():
    """Named individually because each is the sole enforcement of a decision that is
    otherwise only prose. Losing any one of them would leave an ADR unimplemented."""
    text = open(CHECKS).read()
    required = {
        "sri_sk_collision": "ADR 0028 — hash surrogates need a collision guard",
        "sri_grain_key_wellformed": "the grain key must contain every varying component",
        "sri_canonical_interval_overlap": "canonical rows in one series must not overlap",
        "sri_interval_duration_agreement": "declared cadence must match interval boundaries",
        "sri_series_gap_metric": "uncovered canonical time must remain observable",
        "sri_source_observation_bounds": "source completeness is bounded independently of traffic",
        "sri_source_message_summary_bounds": "interval message summaries cannot be negative",
        "ftid_counting_convention_uniform": "rows summed together must share a convention",
        "ftid_nondirectional_exits_null": "a non-directional sensor cannot report exits",
        "ftid_space_count_requires_detail": "every space count has exactly one traffic detail",
        "ftid_noncount_report_forbids_detail": "other report types cannot carry traffic details",
        "sri_utc_offset_present": "the DST guard",
        "shared_suppression_threshold": "shared traffic applies its effective k threshold",
        "shared_zero_suppression": "shared traffic applies configured zero suppression",
        "shared_dependent_measure_suppression": "shared suppression must cover dependent measures",
        "shared_interval_policy_enforced": "compatibility intervals omit every suppressed row",
        "shared_no_suppression_side_channels": "shared schemas omit reconstructive fields",
        "shared_minimum_interval_granularity": "shared data honors the policy cadence",
        "sdep_external_policy_present": "active people-counting deployments fail closed",
        "sdep_disclosure_policy_key_pair": "policy surrogate and durable id must agree",
        "sdp_effective_window_overlap": "disclosure policy versions cannot overlap",
        "sdep_disclosure_policy_effective": "the referenced policy covers the measured date",
        "sri_no_person_level_columns": "ADR 0029 — the never-publish list is asserted absent",
        "css_no_sensing_to_pricing_lineage": "ADR 0030 — sensing is never upstream of pricing",
        "sdep_dpia_covers_employees": "AEPD/Mercadona — a DPIA must assess employees too",
        "sdep_ai_act_notice_posted": "AI Act Art. 50(3), applies from 2026-08-02",
        "sz_parent_resolves_current": "the recursive self-FK must resolve to a current parent",
        "ti_sk_collision": "RFID registry hash surrogates need a collision guard",
        "rre_sk_collision": "RFID event hash surrogates need a collision guard",
        "rre_registration_pairing": "registered SGTIN reads resolve product while GRAI may not",
        "rcs_calendar_orphan": "session trading dates resolve the logical calendar join",
        "rre_retail_sold_context": "retail_sold outside checkout or portal context is visible",
        "rre_session_integrity": "session-bound reads must agree with their header",
        "rre_zone_source_honesty": "mobile read-point attribution must be explicit",
        "rfid_append_only_schema": "RFID event and registry history is append-only",
    }
    missing = {name: why for name, why in required.items() if f"check: {name}" not in text}
    assert not missing, f"load-bearing checks removed: {missing}"


def test_disclosure_is_policy_driven_and_not_a_base_fact_invariant():
    core = _ddl_columns(os.path.join(TABLES_DIR, "sensor_report_interval.sql"))
    detail = _ddl_columns(os.path.join(TABLES_DIR, "foot_traffic_interval_detail.sql"))
    policy = _ddl_columns(os.path.join(TABLES_DIR, "sensing_disclosure_policy.sql"))
    assert {"privacy_suppressed_flag", "suppression_reason"}.isdisjoint(core | detail)
    assert {
        "audience_code", "k_threshold", "suppress_zero_flag",
        "minimum_interval_minutes",
        "effective_from_date", "effective_to_date", "is_current",
    } <= policy

    for name in ("gold_store_traffic_daily_current.sql", "gold_zone_traffic_current.sql"):
        txt = open(os.path.join(GOLD_DIR, name)).read()
        assert "k_threshold" not in txt and "privacy_suppressed" not in txt

    for name in ("gold_store_traffic_daily_shared.sql", "gold_zone_traffic_shared.sql"):
        txt = open(os.path.join(GOLD_DIR, name)).read()
        assert "k_threshold" in txt and "suppress_zero_flag" in txt
        assert "is_zero_observed" not in {
            s.alias_or_name for s in sqlglot.parse_one(_text(os.path.join(GOLD_DIR, name)),
                                                       read="databricks").expression.expressions
        }


def test_shared_views_resolve_effective_policy_from_the_durable_assignment():
    """A policy-version surrogate must not freeze a durable deployment assignment."""
    for name in (
        "gold_store_traffic_daily_shared.sql",
        "gold_zone_traffic_shared.sql",
        "gold_zone_traffic_interval_shared.sql",
    ):
        text = open(os.path.join(GOLD_DIR, name)).read()
        assert re.search(
            r"d\.external_disclosure_policy_id\s*=\s*"
            r"p\.sensing_disclosure_policy_id",
            text,
            re.I,
        ), f"{name} does not resolve the durable policy assignment"
        assert not re.search(
            r"d\.external_disclosure_policy_sk\s*=\s*"
            r"p\.sensing_disclosure_policy_sk",
            text,
            re.I,
        ), f"{name} freezes disclosure to one policy version"


def test_shared_interval_uses_a_disclosure_safe_grain_key():
    """Neither the readable key nor its hash may encode sensor-device identity."""
    text = open(
        os.path.join(GOLD_DIR, "gold_zone_traffic_interval_shared.sql")
    ).read()
    projected = {
        expression.alias_or_name
        for expression in sqlglot.parse_one(text, read="databricks").expression.expressions
    }
    assert {
        "shared_zone_traffic_interval_sk",
        "shared_zone_traffic_interval_id",
    } <= projected
    assert not {
        "sensor_report_interval_sk",
        "sensor_report_interval_id",
    } & projected
    assert "CAST(UNIX_TIMESTAMP(f.interval_start_ts) AS STRING)" in text
    assert "CAST(f.interval_minutes AS STRING)" in text


def test_shared_side_channel_check_forbids_operational_interval_and_device_keys():
    checks = open(CHECKS).read().lower()
    for column in (
        "sensor_report_interval_sk",
        "sensor_report_interval_id",
        "sensor_device_sk",
        "sensor_device_id",
    ):
        assert re.search(
            rf"shared_no_suppression_side_channels[\s\S]*'{column}'",
            checks,
        ), f"shared side-channel check does not forbid {column}"


def test_shared_policy_names_the_actual_dependent_measure_behavior():
    """The model suppresses every dependent measure in the same cell.

    That is not statistical complementary/secondary-cell suppression, and an
    inert policy flag must not imply that it is configurable.
    """
    policy = _ddl_columns(
        os.path.join(TABLES_DIR, "sensing_disclosure_policy.sql")
    )
    assert "complementary_suppression_flag" not in policy

    checks = open(CHECKS).read()
    assert "shared_dependent_measure_suppression" in checks
    assert "shared_complementary_suppression" not in checks


def test_every_gold_view_column_has_unity_catalog_documentation():
    """Every projected column of every CSS gold view carries a COMMENT ON COLUMN, so the
    deployed metadata, the ODCS contract and Genie all get a description (the shared
    interfaces also rely on it to explain suppression semantics)."""
    comments = open(COMMENTS).read()
    for path in GOLD_FILES:
        view = os.path.basename(path)[:-4]
        create = _create(path)
        assert create is not None, f"{view}: no CREATE statement parsed"
        # .selects resolves a UNION to its first branch's projection.
        projected = {
            expression.alias_or_name
            for expression in create.expression.selects
        }
        documented = set(
            re.findall(
                rf"COMMENT\s+ON\s+COLUMN\s+[^;]*\.{view}\.(\w+)\s+IS",
                comments,
                re.I,
            )
        )
        assert projected == documented, (
            f"{view} comment coverage drift: "
            f"missing={sorted(projected - documented)} "
            f"extra={sorted(documented - projected)}"
        )


# ---------- relationships ----------

def test_price_comparison_currency_contract_is_engine_enforced():
    relationships = open(RELATIONSHIPS).read()
    assert "chk_esl_price_observation_record_currency_pair" in relationships
    assert "chk_esl_price_observation_comparison_currency" in relationships
    assert re.search(
        r"price_of_record\s+IS\s+NOT\s+NULL\s+AND\s+"
        r"price_of_record_currency_code\s+IS\s+NOT\s+NULL",
        relationships,
        re.I,
    )
    assert re.search(
        r"displayed_currency_code\s*=\s*price_of_record_currency_code",
        relationships,
        re.I,
    )


def test_calendar_join_is_logical_not_a_foreign_key():
    """Unity Catalog requires an FK to reference a PK or UNIQUE constraint.
    fiscal_calendar's PK is date_sk and date_key carries no UNIQUE, so an FK to date_key
    would be REJECTED at deploy time. Enforced instead by sri_calendar_orphan."""
    txt = open(RELATIONSHIPS).read()
    assert not re.search(r"FOREIGN\s+KEY\s*\(\s*trading_date\s*\)", txt, re.I), (
        "trading_date -> fiscal_calendar.date_key must stay a LOGICAL join")
    assert "sri_calendar_orphan" in open(CHECKS).read()


def test_no_inline_check_constraints():
    """Databricks does not support inline CHECK in CREATE TABLE; ADD CONSTRAINT is the
    only form, and it is also the idempotent one."""
    for path in TABLE_FILES:
        create_body = open(path).read().split("CREATE TABLE", 1)[1].split(")\nUSING", 1)[0]
        assert not re.search(r"\bCHECK\s*\(", create_body, re.I), \
            f"{os.path.basename(path)} declares an inline CHECK"


# ---------- guardrails ----------

def _authored():
    return glob.glob(os.path.join(PKG, "**", "*.sql"), recursive=True) + [
        os.path.join(PKG, "glossary.md"), os.path.join(PKG, "README.md")]


def test_no_hardcoded_or_license():
    for f in _authored():
        txt = open(f).read()
        assert not re.search(r"https?://[\w.-]*databricks|retail_prod|retail_dev", txt), f"hardcoded ref in {f}"
        assert not re.search(r"Copyright|SPDX-License|Licensed under|All rights reserved", txt, re.I), f"licence in {f}"


def test_no_banned_sql():
    for f in glob.glob(os.path.join(PKG, "**", "*.sql"), recursive=True):
        assert not re.search(r"GROUP\s+BY\s+ALL|\b1\s*=\s*1\b", open(f).read(), re.I), f"banned SQL in {f}"


def test_rfid_session_headers_are_generated_before_linked_events():
    generator = os.path.join(REPO, "runtime", "synthetic-data", "generators", "_rfid.py")
    text = open(generator).read()
    assert '.withColumn("ingest_timestamp", F.col("started_at_ts")' in text
    assert '.withColumn("ingest_timestamp", F.col("ended_at_ts")' not in text


def test_tables_are_tagged():
    for path in TABLE_FILES:
        assert "SET TAGS ('dbx_data_type'" in open(path).read(), \
            f"{os.path.basename(path)} has no dbx_data_type tag"


# Every brand this package's research touched. Named ones are the ones that were actually
# present in review and had to be removed, plus the ones most likely to be reached for next.
_BRANDS = [
    "FootfallCam", "RetailNext", "Xovis", "Hella Aglaia", "ShopperTrak", "Brickstream",
    "V-Count", "Emerson", "Danfoss", "Testo", "Sensitech", "Zebra", "Impinj",
    "Avery Dennison", "Nedap", "Pricer", "VusionGroup", "SES-imagotag", "Hanshow",
    "Mercadona", "Enschede", "Walmart", "Zara", "Lululemon", "Uniqlo",
]


def test_no_vendor_or_company_names_in_the_model():
    """A.14 VENDOR-NEUTRAL, tested here because the repo-wide rule is `status: planned`.

    This package is the one most exposed to the rule: every counting convention it models
    exists BECAUSE vendors disagree, so the natural way to justify a column is to name the
    vendors — and eleven files did. The justification survives without the names ('one
    vendor includes entrants, another excludes them' carries the same design force), and
    the names would ship in published UC comments and in generated sample rows, which is
    where a brand in a model does actual harm. Enforcement has to be local, since the
    global rule is defined at severity error but has no CI test behind it yet.
    """
    targets = _authored() + ["runtime/synthetic-data/generators/connected_store_signals.py"]
    found = []
    for f in targets:
        if not os.path.exists(f):
            continue
        txt = open(f).read()
        for brand in _BRANDS:
            # Word-boundary only; a brand that is also an ordinary English word (Density,
            # for one) is deliberately NOT on the list, because a check that cries wolf on
            # "-- Density measures" gets deleted rather than fixed.
            for m in re.finditer(r"\b" + re.escape(brand) + r"\b", txt):
                line = txt[: m.start()].count("\n") + 1
                found.append(f"{os.path.relpath(f)}:{line}: {brand}")
    assert not found, "vendor or company names in the model (A.14):\n" + "\n".join(found)


def test_traffic_extension_has_a_one_to_one_relationship():
    text = open(RELATIONSHIPS).read()
    assert re.search(
        r"foot_traffic_interval_detail.*?"
        r"FOREIGN\s+KEY\s*\(\s*sensor_report_interval_sk\s*\).*?"
        r"REFERENCES.*?sensor_report_interval\s*\(\s*sensor_report_interval_sk\s*\)",
        text,
        re.I | re.S,
    )
