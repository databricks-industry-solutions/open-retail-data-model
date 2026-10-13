"""Deployment contract tests for the RFID and Smart Shelf evaluation clocks."""

from pathlib import Path

import pytest
import yaml

from tools.apply_model_ddl import DeployConfig, apply
from tools.ordm_config import (
    resolve,
    rfid_clock_expressions,
    rfid_policy_expressions,
    shelf_clock_expressions,
    shelf_policy_expressions,
)


REPO = Path(__file__).resolve().parents[1]


def test_rfid_clock_defaults_to_wall_clock():
    sql = "SELECT ${rfid_as_of_ts} AS fresh_as_of_ts"
    assert resolve(sql, "retail") == "SELECT current_timestamp() AS fresh_as_of_ts"


def test_rfid_data_max_clock_is_resolved_from_the_rfid_event_fact():
    expressions = rfid_clock_expressions(
        "data_max",
        "demo_catalog",
        {"css_schema": "demo_css"},
    )
    resolved = resolve(
        "SELECT ${rfid_as_of_ts} AS fresh_as_of_ts",
        "demo_catalog",
        {"css_schema": "demo_css"},
        expressions,
    )

    assert "MAX(event_ts)" in resolved
    assert "demo_catalog.demo_css.rfid_read_event" in resolved
    assert "current_timestamp()" in resolved  # empty-table fallback


def test_rfid_clock_rejects_arbitrary_sql():
    with pytest.raises(ValueError, match="rfid_as_of_mode"):
        rfid_clock_expressions("(SELECT secret FROM somewhere)", "demo_catalog")


def test_shelf_clock_defaults_to_wall_clock():
    sql = "SELECT ${shelf_as_of_ts} AS fresh_as_of_ts"
    assert resolve(sql, "retail") == "SELECT current_timestamp() AS fresh_as_of_ts"


def test_shelf_data_max_clock_covers_state_and_price_evidence():
    expressions = shelf_clock_expressions(
        "data_max",
        "demo_catalog",
        {"css_schema": "demo_css"},
    )
    resolved = resolve(
        "SELECT ${shelf_as_of_ts} AS fresh_as_of_ts",
        "demo_catalog",
        {"css_schema": "demo_css"},
        expressions,
    )

    assert "MAX(observation_ts)" in resolved
    assert "demo_catalog.demo_css.shelf_state_observation" in resolved
    assert "MAX(observed_at_ts)" in resolved
    assert "demo_catalog.demo_css.esl_price_observation" in resolved
    assert "current_timestamp()" in resolved


def test_shelf_clock_rejects_arbitrary_sql():
    with pytest.raises(ValueError, match="shelf_as_of_mode"):
        shelf_clock_expressions("(SELECT secret FROM somewhere)", "demo_catalog")


def test_rfid_policy_defaults_resolve_to_positive_integer_literals():
    sql = (
        "SELECT ${rfid_fixed_freshness_minutes}, "
        "${rfid_mobile_freshness_minutes}, "
        "${rfid_count_target_cadence_days}, "
        "${rfid_count_lookback_days}"
    )
    assert resolve(sql, "retail") == "SELECT 120, 1440, 7, 30"


def test_rfid_policy_overrides_are_validated_and_resolved():
    expressions = rfid_policy_expressions(
        fixed_freshness_minutes="90",
        mobile_freshness_minutes="720",
        count_target_cadence_days="5",
        count_lookback_days="28",
    )
    resolved = resolve(
        "SELECT ${rfid_fixed_freshness_minutes}, "
        "${rfid_mobile_freshness_minutes}, "
        "${rfid_count_target_cadence_days}, "
        "${rfid_count_lookback_days}",
        "retail",
        expressions=expressions,
    )
    assert resolved == "SELECT 90, 720, 5, 28"


def test_shelf_policy_overrides_are_validated_and_resolved():
    expressions = shelf_policy_expressions(
        fixed_freshness_minutes="90",
        mobile_freshness_minutes="720",
    )
    resolved = resolve(
        "SELECT ${shelf_fixed_freshness_minutes}, ${shelf_mobile_freshness_minutes}",
        "retail",
        expressions=expressions,
    )
    assert resolved == "SELECT 90, 720"


@pytest.mark.parametrize("value", ["0", "-1", "1.5", "7; DROP TABLE x", ""])
def test_rfid_policy_rejects_non_positive_integer_sql(value):
    with pytest.raises(ValueError, match="positive integer"):
        rfid_policy_expressions(count_target_cadence_days=value)


@pytest.mark.parametrize("value", ["0", "-1", "1.5", "7; DROP TABLE x", ""])
def test_shelf_policy_rejects_non_positive_integer_sql(value):
    with pytest.raises(ValueError, match="positive integer"):
        shelf_policy_expressions(fixed_freshness_minutes=value)


def test_deploy_config_reads_the_validated_rfid_clock_mode(monkeypatch):
    monkeypatch.delenv("RFID_AS_OF_MODE", raising=False)
    monkeypatch.setattr(
        "sys.argv",
        ["apply_model_ddl.py", "--catalog", "demo_catalog", "--rfid_as_of_mode", "data_max"],
    )

    assert DeployConfig.from_params().rfid_as_of_mode == "data_max"


def test_deploy_config_reads_rfid_policy_values(monkeypatch):
    monkeypatch.setattr(
        "sys.argv",
        [
            "apply_model_ddl.py",
            "--catalog", "demo_catalog",
            "--rfid_fixed_freshness_minutes", "90",
            "--rfid_mobile_freshness_minutes", "720",
            "--rfid_count_target_cadence_days", "5",
            "--rfid_count_lookback_days", "28",
        ],
    )

    config = DeployConfig.from_params()
    assert config.rfid_fixed_freshness_minutes == "90"
    assert config.rfid_mobile_freshness_minutes == "720"
    assert config.rfid_count_target_cadence_days == "5"
    assert config.rfid_count_lookback_days == "28"


def test_apply_threads_the_data_max_expression_into_sql_discovery(monkeypatch):
    captured = {}

    def fake_phases(catalog, overrides, demote_materialized=False, expressions=None):
        captured["expressions"] = expressions
        return iter(())

    monkeypatch.setattr("tools.apply_model_ddl._phases", fake_phases)
    apply(None, "demo_catalog", dry_run=True, rfid_as_of_mode="data_max")

    assert "MAX(event_ts)" in captured["expressions"]["rfid_as_of_ts"]


def test_apply_threads_validated_rfid_policy_into_sql_discovery(monkeypatch):
    captured = {}

    def fake_phases(catalog, overrides, demote_materialized=False, expressions=None):
        captured["expressions"] = expressions
        return iter(())

    monkeypatch.setattr("tools.apply_model_ddl._phases", fake_phases)
    apply(
        None,
        "demo_catalog",
        dry_run=True,
        rfid_fixed_freshness_minutes="90",
        rfid_mobile_freshness_minutes="720",
        rfid_count_target_cadence_days="5",
        rfid_count_lookback_days="28",
    )

    assert captured["expressions"] == {
        "rfid_fixed_freshness_minutes": "90",
        "rfid_mobile_freshness_minutes": "720",
        "rfid_count_target_cadence_days": "5",
        "rfid_count_lookback_days": "28",
    }


def test_apply_threads_only_non_default_shelf_policy_overrides(monkeypatch):
    captured = {}

    def fake_phases(catalog, overrides, demote_materialized=False, expressions=None):
        captured["expressions"] = expressions
        return iter(())

    monkeypatch.setattr("tools.apply_model_ddl._phases", fake_phases)
    apply(
        None,
        "demo_catalog",
        dry_run=True,
        shelf_fixed_freshness_minutes="90",
        shelf_mobile_freshness_minutes="720",
    )

    assert captured["expressions"] == {
        "rfid_fixed_freshness_minutes": "120",
        "rfid_mobile_freshness_minutes": "1440",
        "rfid_count_target_cadence_days": "7",
        "rfid_count_lookback_days": "30",
        "shelf_fixed_freshness_minutes": "90",
        "shelf_mobile_freshness_minutes": "720",
    }


def test_bundle_passes_rfid_clock_mode_only_to_the_demo_apply_task():
    bundle = yaml.safe_load((REPO / "databricks.yml").read_text())
    assert bundle["variables"]["rfid_as_of_mode"]["default"] == "wall_clock"

    demo_tasks = bundle["resources"]["jobs"]["deploy_ordm"]["tasks"]
    demo_apply = next(task for task in demo_tasks if task["task_key"] == "apply_ddl")
    demo_parameters = demo_apply["spark_python_task"]["parameters"]
    flag_index = demo_parameters.index("--rfid_as_of_mode")
    assert demo_parameters[flag_index + 1] == "${var.rfid_as_of_mode}"

    serving_tasks = bundle["resources"]["jobs"]["deploy_ordm_daily"]["tasks"]
    serving_apply = next(task for task in serving_tasks if task["task_key"] == "apply_ddl")
    assert "--rfid_as_of_mode" not in serving_apply["spark_python_task"]["parameters"]


def test_lean_ci_evaluates_historical_rfid_data_at_data_max():
    wf = REPO / ".github" / "workflows" / "ordm-lean-pr-deploy.yml"
    if not (REPO / "tools" / "publish" / "manifest.yaml").exists():
        pytest.skip("public tree: ordm-lean-pr-deploy.yml is staging-only")
    workflow = wf.read_text()
    apply_step = workflow.split("- name: Apply DDL", 1)[1].split("- name:", 1)[0]
    assert "--rfid_as_of_mode data_max" in apply_step


def test_bundle_passes_rfid_policy_to_demo_and_serving_apply_tasks():
    bundle = yaml.safe_load((REPO / "databricks.yml").read_text())
    expected = {
        "rfid_fixed_freshness_minutes": "120",
        "rfid_mobile_freshness_minutes": "1440",
        "rfid_count_target_cadence_days": "7",
        "rfid_count_lookback_days": "30",
    }
    for variable, default in expected.items():
        assert str(bundle["variables"][variable]["default"]) == default

    jobs = bundle["resources"]["jobs"]
    for job_name in ("deploy_ordm", "deploy_ordm_daily"):
        apply_task = next(
            task for task in jobs[job_name]["tasks"]
            if task["task_key"] == "apply_ddl"
        )
        parameters = apply_task["spark_python_task"]["parameters"]
        for variable in expected:
            flag_index = parameters.index(f"--{variable}")
            assert parameters[flag_index + 1] == f"${{var.{variable}}}"


def test_bundle_passes_shelf_clock_and_policy_without_changing_serving_clock_mode():
    bundle = yaml.safe_load((REPO / "databricks.yml").read_text())
    expected = {
        "shelf_as_of_mode": "wall_clock",
        "shelf_fixed_freshness_minutes": "120",
        "shelf_mobile_freshness_minutes": "1440",
    }
    for variable, default in expected.items():
        assert str(bundle["variables"][variable]["default"]) == default

    jobs = bundle["resources"]["jobs"]
    demo_apply = next(
        task for task in jobs["deploy_ordm"]["tasks"]
        if task["task_key"] == "apply_ddl"
    )
    demo_parameters = demo_apply["spark_python_task"]["parameters"]
    for variable in expected:
        flag_index = demo_parameters.index(f"--{variable}")
        assert demo_parameters[flag_index + 1] == f"${{var.{variable}}}"

    serving_apply = next(
        task for task in jobs["deploy_ordm_daily"]["tasks"]
        if task["task_key"] == "apply_ddl"
    )
    serving_parameters = serving_apply["spark_python_task"]["parameters"]
    assert "--shelf_as_of_mode" not in serving_parameters
    for variable in ("shelf_fixed_freshness_minutes", "shelf_mobile_freshness_minutes"):
        flag_index = serving_parameters.index(f"--{variable}")
        assert serving_parameters[flag_index + 1] == f"${{var.{variable}}}"


def test_rfid_clock_scope_and_configurable_window_contracts_are_explicit():
    gold = REPO / "outcome-packages" / "connected-store-signals" / "gold"
    visibility = (gold / "gold_item_visibility_daily.sql").read_text()
    coverage = (gold / "gold_zone_count_coverage.sql").read_text()

    assert visibility.count("${rfid_as_of_ts}") == 2
    assert "${rfid_as_of_ts}" not in coverage
    assert "ADR 0038" in coverage and "wall clock" in coverage

    assert "${rfid_count_target_cadence_days}" in coverage
    assert "${rfid_count_lookback_days}" in coverage
    assert "count_sessions_in_lookback" in coverage
    assert "count_lookback_days" in coverage
    assert "count_sessions_last_30_days" not in coverage

    presence = (gold / "gold_zone_item_presence_current.sql").read_text()
    assert "derived_presence_state = 'present'" in presence
    assert "freshness_age_minutes <= freshness_window_minutes" not in presence


def test_new_connected_store_headers_have_review_dates():
    package = REPO / "outcome-packages" / "connected-store-signals"
    pending = sorted(
        path.relative_to(REPO).as_posix()
        for folder in ("tables", "gold", "metric-views")
        for path in (package / folder).glob("*.sql")
        if "Last reviewed: pending" in path.read_text()
    )
    assert pending == []
