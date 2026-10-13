"""Pin tools/ddl_exec.py — the parallel-execution + retry logic the deploy DDL
applier factors out. Pure module (no Spark/SDK), so exercised directly.

Covers the three red-team concerns:
  - is_retryable (rt09): the concurrency error classes parallelism manufactures,
    and the classes it must NOT retry (a missing object is an ordering bug).
  - demote_materialized_views (rt06): CREATE OR REFRESH MATERIALIZED VIEW ->
    CREATE OR REPLACE VIEW, incl. over the real committed gold SQL.
  - run_units_parallel (rt02, rt05, rt09): file-level fan-out with in-file order,
    bounded retry, per-unit stop-on-failure, and all-failures folded in-thread.

conftest.py puts the repo root on sys.path.
"""
import glob
import os
import re
import threading

import pytest

from tools.ddl_exec import (
    RETRYABLE_TOKENS,
    demote_materialized_views,
    is_retryable,
    materialized_view_fqns,
    retarget_demoted_alter_tags,
    run_units_parallel,
)

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
_MV_CREATE_RE = re.compile(r"CREATE\s+OR\s+REFRESH\s+MATERIALIZED\s+VIEW", re.IGNORECASE)


# --------------------------------------------------------------------------- #
# is_retryable                                                                #
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize(
    "err",
    [
        "[DELTA_CONCURRENT_UPDATE] concurrent update to the table",
        "ConcurrentModificationException: conflicting transaction",
        "MetadataChangedException while committing",
        "ProtocolChangedException detected",
        "ConcurrentAppendException on partition",
        "Could not acquire lock on the table within timeout",
        "Transaction aborted due to deadlock",
        "HTTP 429 Too Many Requests",
        "Operation failed due to a concurrent transaction; please retry",
    ],
)
def test_is_retryable_true_for_each_token_class(err):
    assert is_retryable(err) is True
    # case-insensitive
    assert is_retryable(err.upper()) is True
    assert is_retryable(err.lower()) is True


def test_is_retryable_false_for_plain_and_not_found():
    # a plain, benign message
    assert is_retryable("statement succeeded") is False
    # an ordering/barrier bug — must NOT be blindly retried (rt09)
    assert is_retryable("[TABLE_OR_VIEW_NOT_FOUND] `foo` cannot be found") is False


def test_retryable_tokens_is_a_tuple_of_lowercase():
    assert isinstance(RETRYABLE_TOKENS, tuple) and RETRYABLE_TOKENS
    assert all(tok == tok.lower() for tok in RETRYABLE_TOKENS)


# --------------------------------------------------------------------------- #
# demote_materialized_views                                                   #
# --------------------------------------------------------------------------- #
def test_demote_rewrites_mixed_case_and_extra_spaces():
    sql = "create   OR  Refresh    MATERIALIZED\n VIEW cat.sch.v AS SELECT 1"
    out = demote_materialized_views(sql)
    assert "CREATE OR REPLACE VIEW cat.sch.v AS SELECT 1" in out
    assert not _MV_CREATE_RE.search(out)


def test_demote_is_idempotent():
    sql = "CREATE OR REFRESH MATERIALIZED VIEW v AS SELECT 1"
    once = demote_materialized_views(sql)
    twice = demote_materialized_views(once)
    assert once == twice
    assert once == "CREATE OR REPLACE VIEW v AS SELECT 1"


def test_demote_leaves_plain_view_untouched():
    sql = "CREATE OR REPLACE VIEW v AS SELECT 1"
    assert demote_materialized_views(sql) == sql


def test_demote_leaves_materialized_view_in_comment_untouched():
    sql = (
        "-- Promote this to a MATERIALIZED VIEW later; also see gold_x\n"
        "CREATE OR REPLACE VIEW v AS SELECT 1"
    )
    out = demote_materialized_views(sql)
    assert out == sql  # byte-identical: neither the comment nor the plain view change


def test_demote_noop_when_absent():
    sql = "SELECT 1 FROM t WHERE x = 'MATERIALIZED VIEW'"
    assert demote_materialized_views(sql) == sql


def test_demote_over_real_gold_files_and_still_parses():
    """Run the demotion over the real committed gold DDL that carries an actual
    CREATE OR REFRESH MATERIALIZED VIEW, assert the statement is gone,
    and assert the result still parses on the Databricks dialect."""
    sqlglot = pytest.importorskip("sqlglot")
    pattern = os.path.join(REPO_ROOT, "outcome-packages", "*", "gold", "*.sql")
    files = [
        f for f in sorted(glob.glob(pattern))
        if "MATERIALIZED VIEW" in open(f, encoding="utf-8").read().upper()
        and _MV_CREATE_RE.search(open(f, encoding="utf-8").read())
    ]
    assert files, "expected at least one real MV file"
    for f in files:
        text = open(f, encoding="utf-8").read()
        assert _MV_CREATE_RE.search(text), f
        out = demote_materialized_views(text)
        assert "CREATE OR REFRESH MATERIALIZED VIEW" not in out.upper(), f
        assert not _MV_CREATE_RE.search(out), f
        stmt = sqlglot.parse_one(out, read="databricks", error_level="ignore")
        assert stmt is not None, f"demoted {f} no longer parses"


# --------------------------------------------------------------------------- #
# run_units_parallel                                                          #
# --------------------------------------------------------------------------- #
class _Recorder:
    """Thread-safe fake exec_one. Records call order and can be scripted to
    return a retryable string for the first N calls of a given statement, or to
    fail (retryable / non-retryable) on a given statement."""

    def __init__(self, retry_first=None, fail_nonretryable=None, fail_retryable=None,
                 exists=()):
        self._lock = threading.Lock()
        self.calls = []                       # order of every stmt seen
        self._retry_first = dict(retry_first or {})   # stmt -> remaining retryable returns
        self._fail_nonretryable = set(fail_nonretryable or ())
        self._fail_retryable = set(fail_retryable or ())
        self._exists = set(exists)

    def __call__(self, stmt):
        with self._lock:
            self.calls.append(stmt)
            if stmt in self._fail_nonretryable:
                return "[TABLE_OR_VIEW_NOT_FOUND] missing dep"
            if stmt in self._fail_retryable:
                return "concurrent update conflict"
            if self._retry_first.get(stmt, 0) > 0:
                self._retry_first[stmt] -= 1
                return "ConcurrentAppendException: retry me"
            if stmt in self._exists:
                return "exists"
            return "ok"


def test_within_unit_order_preserved():
    rec = _Recorder()
    units = [("t.sql", ["CREATE TABLE t", "ALTER TABLE t SET TAGS ('x'='y')"])]
    applied, skipped, failures = run_units_parallel(
        units, rec, retries=3, backoff=0.001)
    assert (applied, skipped, failures) == (2, 0, [])
    assert rec.calls == ["CREATE TABLE t", "ALTER TABLE t SET TAGS ('x'='y')"]


def test_independent_units_all_applied():
    rec = _Recorder()
    units = [(f"u{i}.sql", [f"CREATE TABLE t{i}"]) for i in range(20)]
    applied, skipped, failures = run_units_parallel(
        units, rec, max_workers=8, retries=3, backoff=0.001)
    assert applied == 20 and skipped == 0 and failures == []
    assert len(rec.calls) == 20


def test_retryable_error_is_retried_then_succeeds():
    # first 2 calls of the CREATE return a retryable string, 3rd returns ok
    rec = _Recorder(retry_first={"CREATE TABLE t": 2})
    units = [("t.sql", ["CREATE TABLE t"])]
    applied, skipped, failures = run_units_parallel(
        units, rec, retries=3, backoff=0.001)
    assert applied == 1 and skipped == 0 and failures == []
    assert rec.calls.count("CREATE TABLE t") == 3  # 1 initial + 2 retries


def test_retryable_exhausted_records_single_failure():
    rec = _Recorder(fail_retryable={"CREATE TABLE t"})
    units = [("t.sql", ["CREATE TABLE t", "ALTER TABLE t SET TAGS ('x'='y')"])]
    applied, skipped, failures = run_units_parallel(
        units, rec, retries=3, backoff=0.001)
    assert applied == 0 and skipped == 0
    assert len(failures) == 1 and failures[0].startswith("t.sql: ")
    # exhausted after 1 initial + 3 retries; the later SET TAGS never runs
    assert rec.calls.count("CREATE TABLE t") == 4
    assert "ALTER TABLE t SET TAGS ('x'='y')" not in rec.calls


def test_nonretryable_stops_unit_and_collects_all_failures_sorted():
    """A non-retryable error stops its unit after exactly one failure and does not
    run that unit's later statements; other units still complete; all failures are
    collected and SORTED."""
    rec = _Recorder(fail_nonretryable={"CREATE TABLE b", "CREATE TABLE a"})
    units = [
        ("a.sql", ["CREATE TABLE a", "ALTER TABLE a SET TAGS ('x'='y')"]),
        ("b.sql", ["CREATE TABLE b", "ALTER TABLE b SET TAGS ('x'='y')"]),
        ("c.sql", ["CREATE TABLE c"]),
    ]
    applied, skipped, failures = run_units_parallel(
        units, rec, max_workers=4, retries=3, backoff=0.001)
    assert applied == 1  # only c
    assert skipped == 0
    assert len(failures) == 2
    assert failures == sorted(failures)
    assert failures[0].startswith("a.sql: ") and failures[1].startswith("b.sql: ")
    # not blindly retried (rt09): each failing CREATE ran exactly once
    assert rec.calls.count("CREATE TABLE a") == 1
    assert rec.calls.count("CREATE TABLE b") == 1
    # the later SET TAGS on the failed units never executed
    assert "ALTER TABLE a SET TAGS ('x'='y')" not in rec.calls
    assert "ALTER TABLE b SET TAGS ('x'='y')" not in rec.calls


def test_exists_counts_as_skipped():
    rec = _Recorder(exists={"CREATE TABLE t"})
    units = [("t.sql", ["CREATE TABLE t", "ALTER TABLE t SET TAGS ('x'='y')"])]
    applied, skipped, failures = run_units_parallel(
        units, rec, retries=3, backoff=0.001)
    assert applied == 1 and skipped == 1 and failures == []


def test_empty_units_is_noop():
    applied, skipped, failures = run_units_parallel([], lambda s: "ok")
    assert (applied, skipped, failures) == (0, 0, [])


# ---------------------------------------------------------------------------
# A1: retargeting tag DDL for MVs a run demoted to plain views.
# ---------------------------------------------------------------------------

_DEMOTED = "cat.aasa.gold_associate_product_inventory_current"
_REAL_TABLE = "cat.aasa.associate_context_event"


def test_retarget_rewrites_alter_table_for_a_demoted_fqn():
    """(a) A demoted MV's tag DDL becomes ALTER VIEW so it applies to the plain
    view --demote-materialized actually created."""
    sql = f"ALTER TABLE {_DEMOTED} SET TAGS ('dbx_data_type' = 'transactional');"
    out = retarget_demoted_alter_tags(sql, {_DEMOTED})
    assert out == f"ALTER VIEW {_DEMOTED} SET TAGS ('dbx_data_type' = 'transactional');"


def test_retarget_leaves_a_non_demoted_table_untouched():
    """(b) A real table in the same file keeps ALTER TABLE — the rewrite is scoped
    to the fqns this run demoted, not to every ALTER TABLE it sees."""
    sql = (f"ALTER TABLE {_DEMOTED} SET TAGS ('a' = 'b');\n"
           f"ALTER TABLE {_REAL_TABLE} SET TAGS ('c' = 'd');")
    out = retarget_demoted_alter_tags(sql, {_DEMOTED})
    assert f"ALTER VIEW {_DEMOTED} SET TAGS" in out
    assert f"ALTER TABLE {_REAL_TABLE} SET TAGS" in out
    assert "ALTER VIEW " + _REAL_TABLE not in out


def test_retarget_is_idempotent_and_noop_without_demotions():
    """(c) Re-running over its own output changes nothing, and an empty demoted set
    (a normal, non-demoting deploy) returns the input byte-identical."""
    sql = (f"ALTER TABLE {_DEMOTED} SET TAGS ('a' = 'b');\n"
           f"ALTER TABLE {_REAL_TABLE} SET TAGS ('c' = 'd');")
    once = retarget_demoted_alter_tags(sql, {_DEMOTED})
    assert retarget_demoted_alter_tags(once, {_DEMOTED}) == once
    assert retarget_demoted_alter_tags(sql, set()) == sql


def test_retarget_matching_is_case_and_backtick_insensitive():
    """UC identifiers are case-insensitive and the DDL may be backtick-quoted, so a
    demoted fqn is recognised regardless of spelling; the original spelling survives."""
    sql = "alter table `cat`.`aasa`.`gold_associate_product_inventory_current` SET TAGS ('a'='b');"
    out = retarget_demoted_alter_tags(sql, {_DEMOTED.upper()})
    assert out.lower().startswith("alter view ")
    assert "`cat`.`aasa`.`gold_associate_product_inventory_current`" in out


def test_materialized_view_fqns_reads_the_demoted_set_from_gold_sql():
    """The demoted set is learned from the same anchored phrase demote rewrites, so a
    plain view whose COMMENT merely mentions a materialized view is not collected."""
    gold = ("-- Promote to a materialized view at deploy time.\n"
            "CREATE OR REPLACE VIEW cat.aasa.gold_plain AS SELECT 1;\n"
            f"CREATE OR REFRESH MATERIALIZED VIEW {_DEMOTED} AS SELECT 1;")
    assert materialized_view_fqns(gold) == {_DEMOTED}
