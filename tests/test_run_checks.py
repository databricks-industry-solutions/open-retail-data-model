"""Tests for the data-quality runner (runtime/data-quality/run_checks.py).

Verifies the scale improvements: error/warn checks are COUNT(*)-wrapped (so the
violation count is computed in-engine, no rows shipped to the driver) and run
concurrently against one Spark session; metric checks return a value; a bad
query degrades to ERROR rather than crashing the run.
"""

import importlib.util
import os
from concurrent.futures import ThreadPoolExecutor

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _load_runner():
    # data-quality has a hyphen, so it is not importable as a package -> load by path.
    spec = importlib.util.spec_from_file_location(
        "ordm_run_checks", os.path.join(REPO, "runtime", "data-quality", "run_checks.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rc = _load_runner()


def _fixture(spark):
    spark.createDataFrame([(1, 5), (2, -3), (3, 5), (4, 5)], "id int, v int").createOrReplaceTempView("ordm_t")


def test_error_check_passes_when_no_violations(spark):
    _fixture(spark)
    assert rc._run_one(spark, "d", "no_nulls", "error", "SELECT * FROM ordm_t WHERE v IS NULL") \
        == ("d", "no_nulls", "error", "PASS", 0)


def test_error_check_fails_and_counts_via_wrap(spark):
    _fixture(spark)
    r = rc._run_one(spark, "d", "neg_v", "error", "SELECT * FROM ordm_t WHERE v < 0")
    assert r[3] == "FAIL" and r[4] == 1     # one negative row, counted by the COUNT(*) wrap


def test_warn_severity(spark):
    _fixture(spark)
    r = rc._run_one(spark, "d", "w", "warn", "SELECT * FROM ordm_t WHERE v < 0")
    assert r[3] == "WARN" and r[4] == 1


def test_count_wrap_handles_group_by_having(spark):
    _fixture(spark)
    # uniqueness-style check: v=5 appears 3x -> one violating GROUP, counted correctly
    q = "SELECT v, COUNT(*) c FROM ordm_t GROUP BY v HAVING COUNT(*) > 1"
    r = rc._run_one(spark, "d", "dup", "error", q)
    assert r[3] == "FAIL" and r[4] == 1


def test_metric_returns_value_not_count(spark):
    _fixture(spark)
    r = rc._run_one(spark, "d", "rows", "metric", "SELECT COUNT(*) AS n FROM ordm_t")
    assert r[3] == "METRIC" and r[4] == 4


def test_bad_query_is_error_not_crash(spark):
    r = rc._run_one(spark, "d", "bad", "error", "SELECT * FROM ordm_no_such_table_xyz")
    assert r[3] == "ERROR"


def test_checks_run_concurrently(spark):
    # _run_one is exactly what run() maps in parallel; many overlap on one session.
    _fixture(spark)
    checks = [("d", f"c{i}", "error", "SELECT * FROM ordm_t WHERE v < 0") for i in range(8)]
    with ThreadPoolExecutor(max_workers=8) as pool:
        res = list(pool.map(lambda c: rc._run_one(spark, *c), checks))
    assert all(r[3] == "FAIL" and r[4] == 1 for r in res)
