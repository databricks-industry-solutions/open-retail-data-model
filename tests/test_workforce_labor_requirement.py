"""Tests for gold_workforce_labor_requirement's standard selection.

The view INNER JOINs the demand forecast to the ACTIVE labor standards on
(role_code, demand_driver, department_or_zone). Nothing in the schema stops two
concurrently-active standards sharing that key, and a second one would fan the
view out past its declared store x date x interval x zone x role grain — inflating
the SUM(required_labor_hours) / SUM(shortfall_hours) that feed gold_labor_risk and,
through it, gold_store_operational_risk.labor_risk (AI review #133 H1).

ls_active_key_unique reports the condition as a DQ error; the QUALIFY in the view
keeps the result correct meanwhile. These tests run the real gold SQL.
"""

import datetime
import os
from decimal import Decimal

from tools.ordm_config import resolve, view_select_body

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
REQ = os.path.join(REPO, "outcome-packages", "predictive-operations", "gold",
                   "gold_workforce_labor_requirement.sql")

_FORECAST_SCHEMA = ("store_sk int, store_id string, business_date date, "
                    "interval_start_ts timestamp, interval_end_ts timestamp, "
                    "interval_minutes int, department_or_zone string, role_code string, "
                    "demand_driver string, forecast_driver_units decimal(18,4)")
_STANDARD_SCHEMA = ("labor_standard_id string, standard_version string, role_code string, "
                    "demand_driver string, department_or_zone string, interval_minutes int, "
                    "driver_units_per_labor_hour decimal(18,4), "
                    "labor_hours_per_driver_unit decimal(18,6), minimum_headcount int, "
                    "coverage_rationale string, is_active boolean, "
                    "effective_from_date date, is_current boolean")


def _view_body():
    body = view_select_body(resolve(open(REQ).read(), "c", {"predops_schema": "p"}))
    return body.replace("c.p.gold_workforce_demand_forecast", "gold_workforce_demand_forecast") \
               .replace("c.p.labor_standard", "labor_standard")


def _build(spark, standards):
    d = datetime.date(2026, 1, 5)
    fc = [(1, "S1", d, datetime.datetime(2026, 1, 5, 9), datetime.datetime(2026, 1, 5, 10),
           60, "storewide", "cashier", "transaction_count", Decimal("100.0000"))]
    spark.createDataFrame(fc, _FORECAST_SCHEMA).createOrReplaceTempView("gold_workforce_demand_forecast")
    spark.createDataFrame(standards, _STANDARD_SCHEMA).createOrReplaceTempView("labor_standard")
    spark.sql("CREATE OR REPLACE TEMP VIEW req AS " + _view_body())


def _std(sid, version, eff_day, hours_per_unit, *, zone=None, active=True, current=True):
    return (sid, version, "cashier", "transaction_count", zone, 60,
            Decimal("10.0000"), Decimal(hours_per_unit), 1, "r", active,
            datetime.date(2026, 1, eff_day), current)


def test_single_active_standard_yields_one_row(spark):
    _build(spark, [_std("LS-A", "v1", 1, "0.010000")])
    assert spark.sql("SELECT * FROM req").count() == 1


def test_duplicate_active_standards_do_not_fan_out(spark):
    """Two concurrently-active standards on one (role, driver, zone) must still
    produce ONE requirement row -- the defect that inflated labor_risk."""
    _build(spark, [_std("LS-A", "v1", 1, "0.010000"),
                   _std("LS-B", "v2", 2, "0.020000")])
    assert spark.sql("SELECT * FROM req").count() == 1, "QUALIFY must collapse the duplicate"


def test_tie_break_picks_the_highest_version_then_latest_date(spark):
    """ORDER BY standard_version DESC, effective_from_date DESC: v2 wins over v1."""
    _build(spark, [_std("LS-A", "v1", 9, "0.010000"),   # later date, lower version
                   _std("LS-B", "v2", 1, "0.020000")])
    r = spark.sql("SELECT labor_standard_id, labor_standard_version FROM req").collect()[0]
    assert r["labor_standard_id"] == "LS-B"
    assert r["labor_standard_version"] == "v2"


def test_tie_break_is_deterministic_when_version_and_date_tie(spark):
    """Identical version AND date: labor_standard_id DESC keeps the pick stable
    instead of leaving ROW_NUMBER to choose arbitrarily."""
    _build(spark, [_std("LS-A", "v1", 1, "0.010000"),
                   _std("LS-B", "v1", 1, "0.020000")])
    picks = {spark.sql("SELECT labor_standard_id FROM req").collect()[0]["labor_standard_id"]
             for _ in range(3)}
    assert picks == {"LS-B"}


def test_inactive_and_noncurrent_standards_are_excluded(spark):
    _build(spark, [_std("LS-A", "v9", 1, "0.010000", active=False),
                   _std("LS-B", "v8", 1, "0.020000", current=False),
                   _std("LS-C", "v1", 1, "0.030000")])
    r = spark.sql("SELECT labor_standard_id FROM req").collect()
    assert [x["labor_standard_id"] for x in r] == ["LS-C"]
