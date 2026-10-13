"""Tests for gold_workforce_coverage_gap.

The view's coverage aggregation was originally written as two CORRELATED SCALAR
SUBQUERIES of the form `SUM(CASE WHEN s.ts < r.ts ...)`, which puts outer (r) and
local (s) references inside one aggregate. Spark and Databricks BOTH reject that
with UNSUPPORTED_SUBQUERY_EXPRESSION_CATEGORY.AGGREGATE_FUNCTION_MIXED_OUTER_LOCAL_REFERENCES,
so the view failed to create at deploy time on every engine — it was never
merely a Databricks quirk. It is now a JOIN + GROUP BY over a DISTINCT interval
spine.

These tests run the REAL gold SQL against temp-view fixtures with hand-computed
answers, so both the analyzability and the arithmetic stay guarded.
"""

import datetime
import os
from decimal import Decimal

import pytest

from tools.ordm_config import resolve, view_select_body

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GAP = os.path.join(REPO, "outcome-packages", "predictive-operations", "gold",
                   "gold_workforce_coverage_gap.sql")

_SUBS = [
    ("c.p.gold_workforce_labor_requirement", "gold_workforce_labor_requirement"),
    ("c.p.workforce_schedule_recommendation", "workforce_schedule_recommendation"),
    ("c.l.labor_schedule", "labor_schedule"),
]

_REQ_SCHEMA = ("store_sk int, store_id string, business_date date, "
               "interval_start_ts timestamp, interval_end_ts timestamp, "
               "department_or_zone string, role_code string, required_headcount int, "
               "required_labor_hours decimal(18,4), demand_driver string")
_SCHED_SCHEMA = ("store_id string, role_code string, department_or_zone string, "
                 "shift_start_ts timestamp, shift_end_ts timestamp, "
                 "scheduled_hours decimal(18,4), schedule_status string")
_REC_SCHEMA = ("store_id string, role_code string, department_or_zone string, "
               "shift_start_ts timestamp, shift_end_ts timestamp, "
               "assigned_hours decimal(18,4), recommendation_status string")


def _view_body():
    body = view_select_body(resolve(open(GAP).read(), "c", {"predops_schema": "p",
                                                            "labor_schema": "l"}))
    for a, b in _SUBS:
        body = body.replace(a, b)
    return body


def _ts(h, m=0, day=5):
    return datetime.datetime(2026, 1, day, h, m)


def _build(spark):
    d = datetime.date(2026, 1, 5)
    # Two demand_driver rows share ONE interval: the fan-out trap. A second
    # interval has no coverage at all.
    req = [
        (1, "S1", d, _ts(9), _ts(13), "storewide", "cashier", 2, Decimal("8.0000"), "transaction_count"),
        (1, "S1", d, _ts(9), _ts(13), "storewide", "cashier", 2, Decimal("4.0000"), "minimum_coverage"),
        (1, "S1", d, _ts(18), _ts(22), "storewide", "cashier", 1, Decimal("4.0000"), "transaction_count"),
    ]
    sched = [
        # overlaps 09:00-11:00 -> 2h
        ("S1", "cashier", "storewide", _ts(8), _ts(11), Decimal("3.0000"), "published"),
        # overlaps 12:00-13:00 -> 1h
        ("S1", "cashier", "storewide", _ts(12), _ts(16), Decimal("4.0000"), "published"),
        # different day: contributes nothing
        ("S1", "cashier", "storewide", _ts(9, day=6), _ts(17, day=6), Decimal("8.0000"), "published"),
        # right shape, wrong status: must be excluded by the sched CTE filter
        ("S1", "cashier", "storewide", _ts(9), _ts(13), Decimal("4.0000"), "draft"),
    ]
    rec = [
        ("S1", "cashier", "storewide", _ts(10), _ts(12), Decimal("2.0000"), "proposed"),
        ("S1", "cashier", "storewide", _ts(9), _ts(13), Decimal("4.0000"), "rejected"),  # excluded
        # ACCEPTED: already published into labor_schedule above (the 12:00-16:00
        # row), so counting it here too would double-count the same shift.
        ("S1", "cashier", "storewide", _ts(12), _ts(16), Decimal("4.0000"), "accepted"),
    ]
    spark.createDataFrame(req, _REQ_SCHEMA).createOrReplaceTempView("gold_workforce_labor_requirement")
    spark.createDataFrame(sched, _SCHED_SCHEMA).createOrReplaceTempView("labor_schedule")
    spark.createDataFrame(rec, _REC_SCHEMA).createOrReplaceTempView("workforce_schedule_recommendation")
    spark.sql("CREATE OR REPLACE TEMP VIEW gap AS " + _view_body())


def test_view_is_analyzable(spark):
    """The old correlated-aggregate form failed ANALYSIS outright; creating the
    view from the real SQL is itself the regression guard."""
    _build(spark)
    assert spark.sql("SELECT * FROM gap").count() == 3


def test_overlap_hours_are_clipped_to_the_interval(spark):
    """A shift contributes only the part inside the interval, and a shift on a
    different day contributes nothing."""
    _build(spark)
    rows = spark.sql("""
        SELECT DISTINCT scheduled_hours, recommended_hours, covered_hours
        FROM gap WHERE required_headcount = 2
    """).collect()
    assert len(rows) == 1, "both requirement rows must see identical coverage"
    # 08:00-11:00 clips to 2h, 12:00-16:00 clips to 1h; the 2026-01-06 shift and
    # the 'draft' shift contribute nothing.
    assert float(rows[0]["scheduled_hours"]) == 3.0
    # 10:00-12:00 sits wholly inside the interval; the 'rejected' one is excluded.
    assert float(rows[0]["recommended_hours"]) == 2.0
    assert float(rows[0]["covered_hours"]) == 5.0


def test_coverage_is_not_multiplied_across_demand_drivers(spark):
    """Requirements are per demand_driver but coverage is keyed per interval. The
    view does not carry demand_driver through, so the two requirement rows appear
    as two output rows distinguished by required_labor_hours -- each must carry
    the interval's coverage ONCE, not the sum of both rows' matches."""
    _build(spark)
    rows = spark.sql("""
        SELECT required_labor_hours, scheduled_hours FROM gap
        WHERE required_headcount = 2
        ORDER BY required_labor_hours
    """).collect()
    assert len(rows) == 2
    assert [float(r["required_labor_hours"]) for r in rows] == [4.0, 8.0]
    assert {float(r["scheduled_hours"]) for r in rows} == {3.0}


def test_uncovered_interval_reports_zero_not_null(spark):
    """No overlapping shift means no join match; COALESCE must surface 0, exactly
    as the old CASE ... ELSE 0 did."""
    _build(spark)
    r = spark.sql("""
        SELECT scheduled_hours, recommended_hours, shortfall_hours, shortfall_severity
        FROM gap WHERE required_headcount = 1
    """).collect()[0]
    assert float(r["scheduled_hours"]) == 0.0
    assert float(r["recommended_hours"]) == 0.0
    assert float(r["shortfall_hours"]) == 4.0
    assert r["shortfall_severity"] == "critical"


def test_shortfall_and_severity_on_a_partially_covered_interval(spark):
    _build(spark)
    r = spark.sql("""
        SELECT required_labor_hours, covered_hours, shortfall_hours, shortfall_severity
        FROM gap
        WHERE required_headcount = 2 AND required_labor_hours = 8.0
    """).collect()[0]
    # required 8h, covered 5h -> 3h short, 62.5% covered -> 'medium'
    assert float(r["shortfall_hours"]) == 3.0
    assert r["shortfall_severity"] == "medium"


def test_accepted_recommendation_is_not_double_counted(spark):
    """An accepted recommendation is published into labor_schedule, so it is already
    in scheduled_hours. Counting it in recommended_hours too overstated coverage and
    deflated labor_risk; only 'proposed' contributes to the recommended term."""
    _build(spark)
    r = spark.sql("""
        SELECT DISTINCT scheduled_hours, recommended_hours, covered_hours
        FROM gap WHERE required_headcount = 2
    """).collect()[0]
    # 12:00-16:00 is published AND accepted: it must be counted once, in sched.
    assert float(r["scheduled_hours"]) == 3.0
    assert float(r["recommended_hours"]) == 2.0, "accepted must not add a second time"
    assert float(r["covered_hours"]) == 5.0
