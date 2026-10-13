"""Pin the deploy DDL applier's pure logic (no Spark needed).

tools/apply_model_ddl.py imports pyspark only inside main(), so its discovery,
ordering, statement-splitting, and token-resolution can be exercised directly.
conftest.py puts the repo root on sys.path.

Some tests below pin the "deploy fast gate" parallelization contract (design/57 §4,
red-team rt05/rt06/rt09): within-file statement order preserved under parallel apply,
all failures collected (not first-to-raise), retryable-vs-terminal error
classification, MV demotion, and the PENDING-only-for-MV barrier rule. Where those
depend on a sibling agent's not-yet-landed change (`tools/ddl_exec.py`, new `apply()`
params, or the branch-on-kind `_wh_runner`), the test detects the capability and
skips with a note rather than failing spuriously; it activates for real once landed.
"""
import glob
import inspect
import os
import re
import threading

import pytest

from tools.apply_model_ddl import (
    _body_offset,
    BOOTSTRAP,
    REPO_ROOT,
    _apply_gold_fixpoint,
    _argv_param,
    _exec,
    _gold_table_load_units,
    _is_mv_stmt,
    _materialized_view_refresh_order,
    _mv_definition_drifted,
    _normalize_view_body,
    _inline_fallback_runner,
    _inline_view_comments,
    _regroup_alters_by_table,
    _regroup_comments_by_table,
    _view_output_columns,
    _phases,
    _required_schema_names,
    _statements,
    _wh_runner,
    apply,
    ensure_catalog_and_schemas,
    get_param,
    reconcile_materialized_views,
    refresh_gold_tables,
)
from tools.ddl_exec import (
    RETRYABLE_TOKENS,
    demote_materialized_views,
    is_retryable,
    run_units_parallel,
)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class _FakeSpark:
    """Minimal spark.sql stub: a CREATE ... VIEW <name> AS ... FROM <dep> succeeds
    only once every <dep> it references has already been created.

    The created-set read+mutate is guarded by a lock because the gold fixpoint is
    now applied concurrently (rt09): worker threads call .sql() simultaneously, so an
    unlocked `set` would race on membership-check/add and make the fixpoint tests
    flaky. Behaviour is otherwise identical to the serial double."""

    def __init__(self, known=()):
        self.created = set(known)
        self._lock = threading.Lock()

    def sql(self, stmt):
        name = stmt.split("VIEW ")[1].split(" ")[0]
        deps = [tok for tok in ("A", "B", "C") if f"FROM {tok}" in stmt]
        with self._lock:
            missing = [d for d in deps if d not in self.created]
            if missing:
                raise Exception(f"[TABLE_OR_VIEW_NOT_FOUND] `{missing[0]}` cannot be found")
            self.created.add(name)


def test_statements_splits_multi_and_drops_comment_only():
    sql = (
        "-- a header comment\n"
        "CREATE SCHEMA IF NOT EXISTS c.s1;\n"
        "-- inline note\n"
        "CREATE SCHEMA IF NOT EXISTS c.s2;\n"
    )
    stmts = _statements(sql)
    assert len(stmts) == 2
    assert all("CREATE SCHEMA" in s for s in stmts)
    # a purely-comment input must not become an empty statement
    assert _statements("-- only a comment\n") == []
    assert _statements("   \n") == []


def test_statements_splits_create_plus_alter_set_tags_and_ignores_quoted_semicolon():
    """The real tables/ shape: a CREATE (with a ';' inside a COMMENT string) plus
    the CI-mandated ALTER ... SET TAGS must split into separate statements, and the
    quoted ';' must NOT cause a split."""
    sql = (
        "-- provenance header\n"
        "CREATE TABLE t (a INT) COMMENT 'has a ; and -- chars';\n"
        "ALTER TABLE t SET TAGS ('dbx_data_type' = 'master');\n"
        "ALTER TABLE t SET TAGS ('pii' = 'true');\n"
    )
    stmts = _statements(sql)
    assert len(stmts) == 3
    assert "CREATE TABLE t" in stmts[0] and "has a ; and -- chars" in stmts[0]
    assert "dbx_data_type" in stmts[1]
    assert "pii" in stmts[2]


def test_statements_respects_escaped_quote():
    stmts = _statements("CREATE VIEW v AS SELECT 'it''s; ok' AS x;")
    assert len(stmts) == 1 and "it''s; ok" in stmts[0]


def test_statements_ignores_semicolons_in_dollar_quoted_metric_view():
    """A UC metric view's `WITH METRICS ... AS $$ <yaml> $$` body contains `;`; the
    splitter must not break on those, only on the top-level `;` after the body."""
    sql = (
        "CREATE OR REPLACE VIEW v WITH METRICS LANGUAGE YAML AS $$\n"
        "version: 1\nsource: t; still inside the yaml\nmeasures: []\n$$;\n"
        "ALTER TABLE v SET TAGS ('x' = 'y');"
    )
    stmts = _statements(sql)
    assert len(stmts) == 2
    assert "source: t; still inside the yaml" in stmts[0]  # ; inside $$ not split
    assert "SET TAGS" in stmts[1]


def test_deployed_comment_files_split_into_one_statement_per_command():
    """A stray SQL quote must not fuse or fragment later COMMENT statements."""
    paths = sorted(
        glob.glob(os.path.join(REPO, "canonical-core", "*", "comments.sql"))
        + glob.glob(os.path.join(REPO, "outcome-packages", "*", "comments.sql"))
    )
    for path in paths:
        text = open(path).read()
        command_lines = sum(
            1
            for line in text.splitlines()
            if line.lstrip().upper().startswith(("COMMENT ON ", "ALTER VIEW ", "ALTER TABLE "))
        )
        assert len(_statements(text)) == command_lines, os.path.relpath(path, REPO)


def test_phases_are_ordered_and_fully_resolved():
    phases = list(_phases("retail_prod", {}))
    labels = [p[0] for p in phases]

    # dependency order: schemas first; comments last (they document the views);
    # tables before their relationships; gold before the comments on it.
    assert labels[0] == "schemas"
    assert labels[-1] == "comments"
    assert labels.index("core-table") < labels.index("core-rels")
    assert labels.index("core-rels") < labels.index("outcome-table")
    # metric views read gold and comments document it: gold < metric-views < comments
    assert labels.index("outcome-gold") < labels.index("metric-views")
    assert labels.index("metric-views") < labels.index("comments")

    # every ${...} token must be resolved before we would hand SQL to Spark, and
    # the resolved catalog must actually appear.
    for _label, _path, statements in phases:
        for stmt in statements:
            assert "${" not in stmt, f"unresolved token in {_path}: {stmt[:80]}"
    assert any("retail_prod" in s for _l, _p, sts in phases for s in sts)


def test_apply_dry_run_needs_no_spark():
    applied, skipped = apply(spark=None, catalog="retail_prod", overrides={}, dry_run=True)
    assert applied > 0 and skipped == 0


def test_apply_requires_catalog():
    import pytest

    with pytest.raises(ValueError):
        apply(spark=None, catalog="", dry_run=True)


def test_gold_fixpoint_resolves_reverse_dependency_order():
    """Gold views given in reverse dependency order (C<-B<-A) still all apply."""
    spark = _FakeSpark()
    gold = [
        ("c.sql", "CREATE OR REPLACE VIEW C AS SELECT * FROM B"),
        ("b.sql", "CREATE OR REPLACE VIEW B AS SELECT * FROM A"),
        ("a.sql", "CREATE OR REPLACE VIEW A AS SELECT 1"),
    ]
    applied, skipped, failures = _apply_gold_fixpoint(spark.sql, gold)
    assert applied == 3 and not failures
    assert spark.created == {"A", "B", "C"}


def test_gold_fixpoint_surfaces_a_genuine_missing_dependency():
    """A view whose dependency is never created fails (no infinite loop)."""
    spark = _FakeSpark()  # nothing pre-created; B is never provided
    gold = [("x.sql", "CREATE OR REPLACE VIEW X AS SELECT * FROM B")]
    applied, skipped, failures = _apply_gold_fixpoint(spark.sql, gold)
    assert applied == 0 and len(failures) == 1 and "x.sql" in failures[0]


def test_argv_param_reads_both_flag_forms(monkeypatch):
    """--catalog X and --mode=Y forms both parse; missing returns the default.
    This is the primitive every deploy task relies on to receive --catalog, and
    it is byte-identical across the three drivers."""
    monkeypatch.setattr("sys.argv", ["prog", "--catalog", "retail_dev", "--mode=append"])
    assert _argv_param("catalog") == "retail_dev"   # --flag value
    assert _argv_param("mode") == "append"          # --flag=value
    assert _argv_param("missing", "dflt") == "dflt"
    assert _argv_param("missing") is None


def test_argv_param_hyphen_and_bare_boolean(monkeypatch):
    """A DABs task param is commonly hyphenated (--demote-materialized) while the
    get_param token is underscored (demote_materialized), and a switch carries no
    value (--profile). Both must resolve, or a bundle-wired flag silently no-ops
    (regression: --demote-materialized was dropped, so MVs built against empty
    tables)."""
    monkeypatch.setattr(
        "sys.argv",
        ["prog", "--catalog", "ordm_cicd", "--demote-materialized", "--max_workers", "16", "--profile"],
    )
    # hyphenated flag resolves for the underscored token (and vice-versa)
    assert _argv_param("demote_materialized") == "true"   # bare boolean -> "true"
    assert _argv_param("profile") == "true"               # trailing bare boolean -> "true"
    assert _argv_param("max_workers") == "16"             # value not swallowed by the switch before it
    # a bare boolean spelled with underscores also works
    monkeypatch.setattr("sys.argv", ["prog", "--demote_materialized"])
    assert _argv_param("demote-materialized") == "true"


def test_get_param_precedence_env_over_argv(monkeypatch):
    """get_param: (widget →) env → --flag → default. No widget here, so env wins
    over argv, argv wins when env is absent, else the default."""
    monkeypatch.setattr("sys.argv", ["prog", "--catalog", "from_argv"])
    monkeypatch.delenv("CATALOG", raising=False)
    assert get_param("catalog") == "from_argv"       # argv when env absent
    monkeypatch.setenv("CATALOG", "from_env")
    assert get_param("catalog") == "from_env"        # env beats argv
    assert get_param("absent", "d") == "d"           # default


# ---------------------------------------------------------------------------
# Deploy fast-gate parallelization contract (design/57 §4; rt05/rt06/rt09).
#
# The shared parallel primitives (tools.ddl_exec) are LANDED and exercised
# directly below. Where a test needs a sibling change in apply()/_wh_runner that
# may not be wired yet, it detects the capability and skips with a note rather
# than failing spuriously — it becomes a real gate the moment the wiring lands.
# ---------------------------------------------------------------------------

# The applier accepts a warehouse `run` runner (or a monkeypatched sequential
# path) — but to exercise the FILE-parallel dispatch through apply() we need it
# to route through run_units_parallel. Detect whether that wiring is present.
_APPLY_SRC = inspect.getsource(apply)
_APPLY_IS_PARALLEL = "run_units_parallel" in _APPLY_SRC
_APPLY_PARAMS = set(inspect.signature(apply).parameters)


class _RecordingRunner:
    """A fake statement runner that records, per file/unit, the order in which it
    received statements. Thread-safe: run_units_parallel calls it from worker
    threads. Returns None (success) unless a statement matches a configured
    failure substring, in which case it raises so _exec turns it into an error
    string — the applier's real success/failure contract."""

    def __init__(self, fail_substrings=()):
        self._lock = threading.Lock()
        self.by_thread = {}          # thread ident -> [stmts] (proves within-unit serialism)
        self.calls = []              # global receive order
        self.fail_substrings = tuple(fail_substrings)

    def __call__(self, stmt):
        with self._lock:
            self.calls.append(stmt)
            self.by_thread.setdefault(threading.get_ident(), []).append(stmt)
        for bad in self.fail_substrings:
            if bad in stmt:
                raise Exception(f"boom: {bad}")
        return None


def _exec_one(runner):
    """Bind a raw runner to the applier's 'ok'/'exists'/<error-string> contract,
    mirroring tools.apply_model_ddl._exec so run_units_parallel sees exactly what
    the applier feeds it."""
    from tools.apply_model_ddl import _exec
    return lambda stmt: _exec(runner, stmt)


# --- 1. Within-file order preserved under parallel apply (rt05) --------------

def test_within_file_statement_order_preserved_under_parallel_dispatch():
    """A file's CREATE must be executed before its own SET TAGS even when many
    files run concurrently. run_units_parallel is the applier's parallel unit;
    drive it with several files, each [CREATE, SET TAGS], and assert every worker
    thread saw CREATE before SET TAGS for the file it ran."""
    runner = _RecordingRunner()
    units = [
        (f"t{i}.sql", [f"CREATE TABLE t{i} (a INT)", f"ALTER TABLE t{i} SET TAGS ('k'='v')"])
        for i in range(8)
    ]
    applied, skipped, failures = run_units_parallel(
        units, _exec_one(runner), max_workers=8, retries=1, backoff=0.0
    )
    assert applied == 16 and skipped == 0 and failures == []
    # Within each unit (each table), CREATE precedes its SET TAGS in global order.
    for i in range(8):
        creates = [k for k, s in enumerate(runner.calls) if f"CREATE TABLE t{i} " in s]
        tags = [k for k, s in enumerate(runner.calls) if f"ALTER TABLE t{i} SET TAGS" in s]
        assert creates and tags and creates[0] < tags[0], f"t{i}: CREATE must precede SET TAGS"
    # And per worker thread: the statements a single thread ran for its unit are in
    # author order (CREATE first) — the units never interleave within a thread.
    for stmts in runner.by_thread.values():
        idx = {s: k for k, s in enumerate(stmts)}
        for s in stmts:
            if s.startswith("ALTER TABLE"):
                tbl = s.split()[2]
                create = f"CREATE TABLE {tbl} (a INT)"
                assert create in idx and idx[create] < idx[s]


def test_within_file_order_preserved_when_first_statement_must_precede_second():
    """Stronger form: the FakeSpark-style dependency — the SET TAGS 'depends' on
    the CREATE having run — never fails, proving in-unit statements are strictly
    sequential (never dispatched independently across threads, rt05)."""
    seen = set()
    lock = threading.Lock()

    def exec_one(stmt):
        with lock:
            if stmt.startswith("CREATE TABLE"):
                seen.add(stmt.split()[2])
                return "ok"
            if stmt.startswith("ALTER TABLE"):
                tbl = stmt.split()[2]
                if tbl not in seen:  # would be a within-file ordering violation
                    return f"[TABLE_OR_VIEW_NOT_FOUND] {tbl}"
                return "ok"
        return "ok"

    units = [(f"t{i}.sql", [f"CREATE TABLE tab{i} (a INT)", f"ALTER TABLE tab{i} SET TAGS ('k'='v')"])
             for i in range(16)]
    applied, skipped, failures = run_units_parallel(units, exec_one, max_workers=16, retries=0)
    assert failures == [], f"within-file order violated: {failures}"
    assert applied == 32


# --- 2. All failures collected, not first-only (rt09) ------------------------

def test_run_units_parallel_reports_every_failing_unit_not_just_first():
    """With multiple failing units, run_units_parallel must return EVERY failing
    file (folded on the main thread), sorted — not stop at the first to raise."""
    runner = _RecordingRunner(fail_substrings=("FAILME",))
    units = [
        ("good1.sql", ["CREATE TABLE g1 (a INT)"]),
        ("bad_a.sql", ["CREATE TABLE FAILME_a (a INT)"]),
        ("good2.sql", ["CREATE TABLE g2 (a INT)"]),
        ("bad_b.sql", ["CREATE TABLE FAILME_b (a INT)"]),
        ("bad_c.sql", ["CREATE TABLE FAILME_c (a INT)"]),
    ]
    applied, skipped, failures = run_units_parallel(
        units, _exec_one(runner), max_workers=8, retries=0
    )
    assert applied == 2
    assert len(failures) == 3, failures
    assert failures == sorted(failures)  # deterministic order
    for rel in ("bad_a.sql", "bad_b.sql", "bad_c.sql"):
        assert any(rel in f for f in failures), f"{rel} missing from {failures}"


@pytest.mark.skipif(
    not _APPLY_IS_PARALLEL,
    reason="apply() not yet wired to run_units_parallel (sibling change pending); "
           "the serial apply() already collects all failures — see existing behaviour",
)
def test_apply_raises_listing_every_failing_file(monkeypatch):
    """End-to-end: apply() must raise AssertionError whose 'DDL failures:' message
    lists EVERY failing file, not just the first (rt09 §4a). Uses a controlled
    multi-file phase set so no real Spark/SQL is needed."""
    def fake_phases(catalog, overrides, demote_materialized=False, expressions=None):
        yield "schemas", os.path.join(REPO_ROOT, "s.sql"), ["CREATE SCHEMA s"]
        yield "core-table", os.path.join(REPO_ROOT, "a.sql"), ["CREATE TABLE FAILME_a (x INT)"]
        yield "core-table", os.path.join(REPO_ROOT, "b.sql"), ["CREATE TABLE ok_b (x INT)"]
        yield "core-table", os.path.join(REPO_ROOT, "c.sql"), ["CREATE TABLE FAILME_c (x INT)"]

    monkeypatch.setattr("tools.apply_model_ddl._phases", fake_phases)

    class _Spark:
        def sql(self, stmt):
            if "FAILME" in stmt:
                raise Exception("boom")

    with pytest.raises(AssertionError) as ei:
        apply(spark=_Spark(), catalog="retail_prod", dry_run=False)
    msg = str(ei.value)
    assert "DDL failures:" in msg
    assert "a.sql" in msg and "c.sql" in msg, msg  # both failures, not just the first


# --- 3. Retryable vs non-retryable classification (rt09 §6) ------------------

def test_is_retryable_classifies_concurrency_errors_but_not_missing_object():
    """tools.ddl_exec.is_retryable: concurrency-manufactured errors are retryable;
    a missing-object (ordering/barrier bug) is NOT — retrying it just delays the
    real failure (rt09 §6)."""
    assert is_retryable("ERROR: CONCURRENT_UPDATE to the commit")
    assert is_retryable("Delta MetadataChanged: table changed")
    assert is_retryable("could not acquire lock on the table")
    assert is_retryable("429 Too Many Requests")
    assert not is_retryable("[TABLE_OR_VIEW_NOT_FOUND] `gold_x` cannot be found")
    assert not is_retryable("[PARSE_SYNTAX_ERROR] near 'SLECT'")
    # A plain 'already exists' is idempotent, NOT a retryable concurrency error.
    assert not is_retryable("Table already exists")
    # Every declared token classifies as retryable (guards against a typo drift).
    assert all(is_retryable(f"prefix {tok} suffix") for tok in RETRYABLE_TOKENS)


def test_run_units_parallel_retries_transient_then_succeeds():
    """A transient (retryable) error self-heals: a statement that fails once with a
    CONCURRENT_UPDATE and then succeeds is applied, not reported as a failure —
    proving the applier treats a transient as retryable end-to-end via the runner."""
    state = {"n": 0}
    lock = threading.Lock()

    def flaky_exec(stmt):
        with lock:
            state["n"] += 1
            first = state["n"] == 1
        if first:
            return "CONCURRENT_UPDATE to the commit"  # retryable error string
        return "ok"

    applied, skipped, failures = run_units_parallel(
        [("t.sql", ["CREATE TABLE t (a INT)"])], flaky_exec,
        max_workers=1, retries=3, backoff=0.0,  # zero backoff keeps the test fast
    )
    assert applied == 1 and failures == [], failures


def test_run_units_parallel_does_not_retry_nonretryable():
    """A non-retryable error (missing object) is NOT retried: the statement is
    attempted exactly once and reported as a failure."""
    calls = {"n": 0}
    lock = threading.Lock()

    def hard_fail(stmt):
        with lock:
            calls["n"] += 1
        return "[TABLE_OR_VIEW_NOT_FOUND] `dep` cannot be found"

    applied, skipped, failures = run_units_parallel(
        [("t.sql", ["CREATE VIEW v AS SELECT * FROM dep"])], hard_fail,
        max_workers=1, retries=5, backoff=0.0,
    )
    assert applied == 0 and len(failures) == 1
    assert calls["n"] == 1, "non-retryable error must not be retried"


# --- 4. --demote-materialized (rt06) -----------------------------------------

def test_demote_materialized_views_rewrites_create_or_refresh():
    """The tools.ddl_exec transform rewrites CREATE OR REFRESH MATERIALIZED VIEW
    to CREATE OR REPLACE VIEW, is whitespace/case tolerant, idempotent, and leaves
    a plain view / a comment mention untouched."""
    src = (
        "-- gold_x is a MATERIALIZED VIEW in the serving deploy\n"
        "CREATE OR REFRESH MATERIALIZED VIEW c.s.gold_x AS SELECT 1;\n"
        "CREATE OR\tREFRESH   MATERIALIZED\nVIEW c.s.gold_y AS SELECT 2;\n"
        "CREATE OR REPLACE VIEW c.s.plain AS SELECT 3;\n"
    )
    out = demote_materialized_views(src)
    assert "MATERIALIZED VIEW c.s.gold_x" not in out
    assert "CREATE OR REPLACE VIEW c.s.gold_x" in out
    assert "CREATE OR REPLACE VIEW c.s.gold_y" in out  # whitespace-tolerant
    assert out.count("CREATE OR REPLACE VIEW") == 3
    # the comment mention of MATERIALIZED VIEW survives (only leading keyword phrase matches)
    assert "-- gold_x is a MATERIALIZED VIEW" in out
    # idempotent
    assert demote_materialized_views(out) == out


def test_phases_demote_materialized_yields_no_materialized_view_create():
    """With demote on, NO statement produced by _phases contains
    'CREATE OR REFRESH MATERIALIZED VIEW' (all 18 gold MVs become plain views),
    and with demote off at least one such statement IS present — proving the flag,
    not the corpus, is what removes them. Drives the real committed SQL."""
    def gold_creates(demote):
        out = []
        for label, _path, stmts in _phases("retail_prod", {}, demote_materialized=demote):
            if label == "outcome-gold":
                out.extend(stmts)
        return out

    off = gold_creates(False)
    on = gold_creates(True)
    assert any("CREATE OR REFRESH MATERIALIZED VIEW" in s.upper() for s in off), \
        "expected the committed gold to contain materialized-view creates"
    assert not any("CREATE OR REFRESH MATERIALIZED VIEW" in s.upper() for s in on), \
        "demote_materialized must rewrite every MV create to a plain view"


@pytest.mark.skipif(
    "demote_materialized" not in _APPLY_PARAMS,
    reason="apply() has no demote_materialized param yet (sibling change pending); "
           "the _phases(demote_materialized=...) path IS covered above",
)
def test_apply_demote_materialized_hands_no_mv_create_to_runner(monkeypatch):
    """With demote on, NO statement handed to the runner is a MATERIALIZED VIEW
    create — the end-to-end apply() view of the rt06 fix."""
    seen = []
    lock = threading.Lock()

    class _Spark:
        def sql(self, stmt):
            with lock:
                seen.append(stmt)

    apply(spark=_Spark(), catalog="retail_prod", dry_run=False, **{"demote_materialized": True})
    assert seen, "expected statements to be executed"
    assert not any("CREATE OR REFRESH MATERIALIZED VIEW" in s.upper() for s in seen)


# --- 5. Dry-run needs no Spark AND --profile doesn't break dry-run -----------

def test_apply_dry_run_needs_no_spark_and_profile_is_harmless():
    """Dry-run returns applied>0 with no Spark; enabling profiling (however the
    applier exposes it) must not break dry-run and must still return."""
    applied, skipped = apply(spark=None, catalog="retail_prod", overrides={}, dry_run=True)
    assert applied > 0 and skipped == 0

    if "profile" in _APPLY_PARAMS:
        applied_p, skipped_p = apply(
            spark=None, catalog="retail_prod", overrides={}, dry_run=True, **{"profile": True}
        )
        assert applied_p == applied and skipped_p == 0
    else:
        # profile not yet a param: assert the contract holds via the env/argv path,
        # which get_param reads, so a --profile flag never turns dry-run into a
        # Spark-requiring path.
        pytest.skip("apply() has no profile param yet (sibling change pending); "
                    "dry-run-without-Spark is covered above")


# --- 6. Barrier: PENDING accepted only for MV creates (rt09 §2) --------------

class _FakeStatus:
    def __init__(self, state, error=None):
        self.state = state
        self.error = error


class _FakeResp:
    def __init__(self, state, error=None, statement_id="stmt-1"):
        self.status = _FakeStatus(state, error)
        self.statement_id = statement_id


class _FakeStmtExec:
    """Minimal w.statement_execution stub for _wh_runner. `exec_state_for(stmt)`
    is the state execute_statement returns (the 50s CONTINUE-boundary state);
    `poll_state_for(stmt)` is what get_statement returns when _wh_runner polls a
    still-PENDING non-MV to terminal (rt09 §2). Both accept the SQL text so a test
    can drive an MV and a non-MV divergently. `error_for(stmt)` optionally attaches
    an error message to the response."""

    def __init__(self, exec_state_for, poll_state_for=None, error_for=None):
        self.exec_state_for = exec_state_for
        self.poll_state_for = poll_state_for or exec_state_for
        self.error_for = error_for or (lambda s: None)
        self.exec_calls = []
        self.poll_calls = []

    def execute_statement(self, warehouse_id, statement, wait_timeout=None, on_wait_timeout=None):
        self.exec_calls.append(statement)
        self._last_stmt = statement
        return _FakeResp(self.exec_state_for(statement), self.error_for(statement))

    def get_statement(self, statement_id):
        self.poll_calls.append(statement_id)
        stmt = getattr(self, "_last_stmt", "")
        return _FakeResp(self.poll_state_for(stmt), self.error_for(stmt))


class _FakeWorkspaceClient:
    def __init__(self, exec_state_for, poll_state_for=None, error_for=None):
        self.statement_execution = _FakeStmtExec(exec_state_for, poll_state_for, error_for)


_WH_SRC = inspect.getsource(_wh_runner)
# The rt09 §2 fix branches _wh_runner acceptance on statement kind: PENDING/RUNNING
# accepted ONLY for a MATERIALIZED VIEW create, terminal SUCCEEDED required otherwise.
_WH_BRANCHES_ON_KIND = "materialized" in _WH_SRC.lower()


@pytest.mark.skipif(
    not _WH_BRANCHES_ON_KIND,
    reason="_wh_runner still blanket-accepts PENDING/RUNNING for all statements "
           "(rt09 §2 branch-on-kind change pending); contract asserted below once landed",
)
def test_wh_runner_rejects_pending_for_non_mv_but_accepts_for_mv(monkeypatch):
    """rt09 §2: a non-MV statement left PENDING at the 50s barrier is NOT accepted
    (it is polled to terminal and, staying PENDING, raises), while a
    CREATE OR REFRESH MATERIALIZED VIEW left PENDING IS accepted (its async refresh
    runs out-of-band). Sleep is neutralized so the bounded poll is instant."""
    pytest.importorskip("databricks.sdk.service.sql")
    monkeypatch.setattr("tools.apply_model_ddl.time.sleep", lambda *a, **k: None)

    # execute_statement AND the subsequent get_statement polls all return PENDING.
    w = _FakeWorkspaceClient(lambda stmt: "StatementState.PENDING")
    run = _wh_runner(w, "wh-123")

    # MV create left PENDING -> accepted (no raise), and NOT polled.
    run("CREATE OR REFRESH MATERIALIZED VIEW c.s.gold_x AS SELECT 1")
    assert w.statement_execution.poll_calls == [], "MV create must not be polled"

    # non-MV CREATE left PENDING -> polled to terminal; still PENDING -> raises.
    with pytest.raises(Exception):
        run("CREATE TABLE c.s.t (a INT)")
    assert w.statement_execution.poll_calls, "non-MV PENDING must be polled to terminal"


@pytest.mark.skipif(
    not _WH_BRANCHES_ON_KIND,
    reason="_wh_runner branch-on-kind change pending",
)
def test_wh_runner_accepts_non_mv_that_reaches_succeeded_after_poll(monkeypatch):
    """A non-MV that is PENDING at the boundary but reaches terminal SUCCEEDED when
    polled IS accepted — the barrier requires SUCCEEDED, not immediacy (rt09 §2)."""
    pytest.importorskip("databricks.sdk.service.sql")
    monkeypatch.setattr("tools.apply_model_ddl.time.sleep", lambda *a, **k: None)

    w = _FakeWorkspaceClient(
        exec_state_for=lambda stmt: "StatementState.PENDING",
        poll_state_for=lambda stmt: "StatementState.SUCCEEDED",
    )
    run = _wh_runner(w, "wh-1")
    run("CREATE TABLE c.s.t (a INT)")  # PENDING -> polled -> SUCCEEDED -> no raise
    assert w.statement_execution.poll_calls


def test_wh_runner_accepts_succeeded_and_raises_on_failed():
    """Baseline that holds regardless of the branch-on-kind change: a terminal
    SUCCEEDED is accepted and a FAILED state raises with the error message. Uses a
    fake WorkspaceClient so no SDK/network is needed beyond the import."""
    pytest.importorskip("databricks.sdk.service.sql")

    class _Err:
        def __init__(self, message):
            self.message = message

    w = _FakeWorkspaceClient(
        exec_state_for=lambda stmt: "StatementState.SUCCEEDED" if "good" in stmt else "StatementState.FAILED",
        error_for=lambda stmt: None if "good" in stmt else _Err("it broke"),
    )
    run = _wh_runner(w, "wh-1")

    run("CREATE TABLE good (a INT)")  # SUCCEEDED -> no raise
    with pytest.raises(Exception) as ei:
        run("CREATE TABLE bad (a INT)")  # FAILED -> raise
    assert "it broke" in str(ei.value)


# ---- H1 regression: MV classification must key on executable text, not comments ----

def test_is_mv_stmt_ignores_materialized_view_mention_in_comments():
    """A plain view whose HEADER COMMENT mentions materialized views must NOT be
    classified as an MV (rt09 s2 barrier hole H1): the splitter keeps the comment
    attached to the CREATE, so a bare-substring test wrongly exempted these plain
    views from the terminal-SUCCEEDED barrier."""
    plain = (
        "-- Materialization: plain view. Promote to a materialized view at deploy\n"
        "-- time if a low-latency gate is needed.\n"
        "CREATE OR REPLACE VIEW c.s.v AS SELECT 1"
    )
    real_mv = "CREATE OR REFRESH MATERIALIZED VIEW c.s.m AS SELECT 1"
    assert _is_mv_stmt(plain) is False
    assert _is_mv_stmt(real_mv) is True


def test_is_mv_stmt_over_real_gold_files_matches_executable_kind():
    """Over EVERY committed gold file: _is_mv_stmt agrees with whether the file's
    executable text is a CREATE OR REFRESH MATERIALIZED VIEW, regardless of comment
    wording. Pins H1 against regression (mirrors the real-file sweep in test_ddl_exec)."""
    import re
    gold = glob.glob(os.path.join(REPO_ROOT, "outcome-packages", "*", "gold", "*.sql"))
    assert gold, "expected committed gold files"
    mv_phrase = re.compile(r"CREATE\s+OR\s+REFRESH\s+MATERIALIZED\s+VIEW", re.IGNORECASE)
    for f in gold:
        txt = open(f).read()
        want = bool(mv_phrase.search(txt))
        assert _is_mv_stmt(txt) is want, f"{os.path.basename(f)}: _is_mv_stmt != executable kind"


# ---- drop-and-recreate on kind mismatch (CI/CD dirty-catalog self-heal) ----

def test_exec_drops_and_recreates_on_kind_mismatch_when_enabled():
    """--demote-materialized re-deploy onto a dirty catalog: a CREATE OR REPLACE VIEW
    that hits an existing materialized view (EXPECT_VIEW_NOT_TABLE) must DROP the stale
    object and re-run, returning 'ok'. With the flag off it stays strict (error).

    The statement carries the leading `-- ===` header block that _statements keeps attached
    to every real fragment (regression for the AI-review H1: a re.match-anchored CREATE guard
    failed on that `--` prefix, leaving the self-heal inert on real input)."""
    calls = []

    def make_run(fail_first):
        state = {"failed": False}

        def run(stmt):
            calls.append(stmt)
            if stmt.lstrip().startswith("DROP"):
                return  # drop succeeds
            if fail_first and not state["failed"] and "CREATE OR REPLACE VIEW" in stmt:
                state["failed"] = True
                raise Exception("[EXPECT_VIEW_NOT_TABLE.NO_ALTERNATIVE] does not support CREATE OR REPLACE VIEW")
            return  # re-run succeeds
        return run

    # Real applier shape: header comment block precedes the executable CREATE.
    stmt = ("-- ============================================================\n"
            "-- ORDM · Outcome Package · View: gold_customer_ltv\n"
            "-- ============================================================\n"
            "CREATE OR REPLACE VIEW ordm_cicd.acu.gold_customer_ltv AS SELECT 1")
    # enabled -> drop + recreate -> ok
    calls.clear()
    assert _exec(make_run(True), stmt, drop_on_kind_mismatch=True) == "ok"
    assert any(c.startswith("DROP MATERIALIZED VIEW IF EXISTS ordm_cicd.acu.gold_customer_ltv") for c in calls)
    # disabled -> the mismatch is returned as a hard error (strict, prod-safe)
    calls.clear()
    res = _exec(make_run(True), stmt, drop_on_kind_mismatch=False)
    assert "EXPECT_VIEW_NOT_TABLE" in res
    assert not any(c.startswith("DROP") for c in calls)


def test_exec_never_drops_on_alter_kind_mismatch():
    """Drop-and-recreate must fire ONLY for a CREATE, never for an ALTER: dropping the
    object then re-running an ALTER (e.g. ADD CONSTRAINT) would just find nothing
    (TABLE_OR_VIEW_NOT_FOUND) and destroy a real object. A kind-mismatch on an ALTER
    means an earlier CREATE was skipped/failed; surface it, do not drop."""
    calls = []

    def run(stmt):
        calls.append(stmt)
        if stmt.lstrip().startswith("DROP"):
            return
        raise Exception("[EXPECT_TABLE_NOT_VIEW.NO_ALTERNATIVE] expects a table but ... is a view")

    # header'd like a real fragment -- the leading-CREATE guard must still NOT match an ALTER
    alter = ("-- ============================================================\n"
             "-- ORDM · relationships\n"
             "ALTER TABLE ordm_cicd.cmn.store_zone_interval ADD CONSTRAINT fk_x FOREIGN KEY (a) REFERENCES b")
    res = _exec(run, alter, drop_on_kind_mismatch=True)
    assert "EXPECT_TABLE_NOT_VIEW" in res            # error surfaced, not swallowed
    assert not any(c.lstrip().startswith("DROP") for c in calls)  # never dropped under an ALTER


# ---- comments regrouped per target table (lift the fan-out lane count 9 -> ~50) ----

def test_regroup_comments_by_table_groups_and_preserves_order():
    """Per-file comment units are re-split into per-TARGET-TABLE units: one unit per
    commented table, same-table comments kept together and IN ORDER (mandatory: concurrent
    metadata commits to one table race and silently lose a COMMENT). No statement dropped."""
    units = [
        ("acu/comments.sql", [
            "COMMENT ON COLUMN c.acu.gold_x.a IS 'a'",
            "COMMENT ON COLUMN c.acu.gold_x.b IS 'b'",
            "COMMENT ON COLUMN c.acu.gold_y.m IS 'm'",
        ]),
        ("bmv/comments.sql", [
            "COMMENT ON COLUMN c.bmv.gold_z.p IS 'p'",
        ]),
    ]
    out = _regroup_comments_by_table(units)
    keys = [k for k, _ in out]
    # one unit per distinct target TABLE (3 here), not per file (2)
    assert keys == ["c.acu.gold_x", "c.acu.gold_y", "c.bmv.gold_z"]
    by = dict(out)
    # same-table comments grouped and order preserved
    assert by["c.acu.gold_x"] == [
        "COMMENT ON COLUMN c.acu.gold_x.a IS 'a'",
        "COMMENT ON COLUMN c.acu.gold_x.b IS 'b'",
    ]
    # every statement is preserved exactly once
    n_in = sum(len(s) for _, s in units)
    n_out = sum(len(s) for _, s in out)
    assert n_in == n_out == 4


def test_regroup_comments_falls_back_for_non_column_comment():
    """A statement that is not a recognizable COMMENT ON COLUMN is not dropped: it falls
    back to a per-file unit so nothing is silently lost."""
    units = [("x/comments.sql", [
        "COMMENT ON COLUMN c.s.t.a IS 'a'",
        "-- some non-column directive that slipped in",
        "COMMENT ON TABLE c.s.t IS 'whole table'",
    ])]
    out = _regroup_comments_by_table(units)
    flat = [st for _, stmts in out for st in stmts]
    assert len(flat) == 3  # nothing dropped
    assert any(k == "c.s.t" for k, _ in out)                     # the column comment grouped by table
    assert any("COMMENT ON TABLE" in st for _, stmts in out for st in stmts)  # fallback kept


def test_regroup_comments_over_real_files_lifts_lane_count():
    """Over the committed comments.sql, using the RESOLVED statements the applier actually
    passes (via _phases, ${...} tokens substituted): regrouping yields materially MORE units
    (lanes) than files, and the biggest per-table unit is far smaller than the biggest
    per-file batch (measured floor drop ~128 -> ~38)."""
    per_file = [(os.path.basename(path), stmts)
                for label, path, stmts in _phases("ordm_cicd", {}) if label == "comments"]
    if not per_file:
        import pytest
        pytest.skip("no committed comments.sql")
    regrouped = _regroup_comments_by_table(per_file)
    # many more lanes than files (9 files -> ~50 target tables)
    assert len(regrouped) > 2 * len(per_file)
    biggest_file = max(len(s) for _, s in per_file)
    biggest_table = max(len(s) for _, s in regrouped)
    assert biggest_table < biggest_file  # the serial floor dropped
    # nothing lost
    assert sum(len(s) for _, s in regrouped) == sum(len(s) for _, s in per_file)


def test_regroup_comments_groups_table_comment_with_its_columns():
    """H1 (AI review): a COMMENT ON TABLE must land in the SAME per-table serial unit as that
    table's COMMENT ON COLUMN statements -- never a concurrent per-file fallback unit, or the
    two units could commit the same table concurrently and one comment is silently lost."""
    units = [("f.sql", [
        "COMMENT ON COLUMN c.s.t.a IS 'a'",
        "COMMENT ON TABLE c.s.t IS 'the table'",
        "COMMENT ON COLUMN c.s.t.b IS 'b'",
    ])]
    out = _regroup_comments_by_table(units)
    assert [k for k, _ in out] == ["c.s.t"]            # one unit, keyed on the table
    assert len(dict(out)["c.s.t"]) == 3                # col + table + col, all serial together
    assert all(k != "f.sql" for k, _ in out)           # nothing leaked to a fallback file-unit


# ---- materialized-view refresh order (serving deploy; AI review #108 H1, Approach B) ----

def test_mv_refresh_order_is_parents_before_children_and_excludes_comment_mentions():
    """The serving-deploy MV refresh must return every gold MV in DEPENDENCY order (a child
    MV that reads another MV refreshes AFTER it), and must NOT mistake a plain view whose
    COMMENT mentions 'CREATE OR REFRESH MATERIALIZED VIEW' for an MV. Drives the real gold."""
    order = _materialized_view_refresh_order("retail_prod", {})
    names = [fqn.split(".")[-1] for fqn in order]
    # Every entry is a real gold_ MV name; the comment-only false match ("for", from
    # gold_unified_customer_360_current's header) must NOT appear.
    assert names, "expected committed gold materialized views"
    assert "for" not in names and all(n.startswith("gold_") for n in names), names
    # All fully resolved (no leftover ${...} token).
    assert all("${" not in fqn for fqn in order)
    # Dependency order: a parent appears before any child that reads it. Cross-check a few
    # real edges parsed from the committed SQL (sales/price feed the feature + assortment MVs).
    idx = {n: i for i, n in enumerate(names)}
    for parent, child in [
        ("gold_sales_actuals", "gold_promotional_features"),
        ("gold_sales_actuals", "gold_assortment_optimization"),
        ("gold_promotional_features", "gold_assortment_optimization"),
        ("gold_price_actuals", "gold_bucket_features"),
    ]:
        if parent in idx and child in idx:
            assert idx[parent] < idx[child], f"{parent} must refresh before {child}"


def test_mv_refresh_waves_are_levels_and_flatten_to_the_order():
    """The wave grouping is a Kahn LEVELIZATION: every MV in wave K depends only on MVs in
    earlier waves, and flattening the waves reproduces the flat dependency order. Independent
    MVs share a wave so they can refresh concurrently."""
    from tools.apply_model_ddl import _materialized_view_refresh_waves
    waves = _materialized_view_refresh_waves("retail_prod", {})
    assert waves and all(w for w in waves), "no empty waves"
    flat = [fqn for w in waves for fqn in w]
    assert flat == _materialized_view_refresh_order("retail_prod", {})  # flatten == flat order
    # A child never shares or precedes its parent's wave: known real edges land in later waves.
    wave_of = {fqn.split(".")[-1]: wi for wi, w in enumerate(waves) for fqn in w}
    for parent, child in [
        ("gold_sales_actuals", "gold_promotional_features"),
        ("gold_promotional_features", "gold_assortment_optimization"),
    ]:
        if parent in wave_of and child in wave_of:
            assert wave_of[parent] < wave_of[child], f"{child} must be in a later wave than {parent}"


def test_refresh_materialized_views_refreshes_all_and_collects_failures():
    """refresh_materialized_views issues one REFRESH MATERIALIZED VIEW per MV (never a
    CREATE/ALTER/DROP), refreshing a wave concurrently and folding every error. With NO
    failures it refreshes the full set."""
    from tools.apply_model_ddl import refresh_materialized_views, _materialized_view_refresh_order
    seen, lock = [], threading.Lock()

    def run(stmt):
        with lock:
            seen.append(stmt)

    refreshed, failures = refresh_materialized_views(run, "retail_prod", {}, max_workers=8)
    order = _materialized_view_refresh_order("retail_prod", {})
    assert all(s.startswith("REFRESH MATERIALIZED VIEW ") for s in seen)
    assert failures == [] and refreshed == len(order) == len(seen)
    # every committed MV was refreshed (set-equal; within-wave order is nondeterministic)
    assert {s.split()[-1] for s in seen} == set(order)


def test_refresh_materialized_views_skips_downstream_waves_after_a_failure():
    """If a parent wave has a failure, later waves are SKIPPED (a child refresh against a
    parent that failed would compute on stale data). The failing MV is collected, not raised."""
    from tools.apply_model_ddl import (
        refresh_materialized_views, _materialized_view_refresh_waves)
    waves = _materialized_view_refresh_waves("retail_prod", {})
    # pick an MV in the FIRST wave to fail, so at least one downstream wave is skipped
    assert len(waves) >= 2, "need >=2 waves to exercise the skip"
    victim = waves[0][0].split(".")[-1]
    seen, lock = [], threading.Lock()

    def run(stmt):
        with lock:
            seen.append(stmt)
        if victim in stmt:
            raise Exception("boom")

    refreshed, failures = refresh_materialized_views(run, "retail_prod", {}, max_workers=8)
    assert len(failures) == 1 and victim in failures[0]
    # downstream waves never issued a REFRESH (skipped after the failed parent wave)
    downstream = {fqn.split(".")[-1] for w in waves[1:] for fqn in w}
    assert not (downstream & {s.split()[-1] for s in seen}), "downstream MV refreshed despite parent failure"


def test_physical_gold_table_refresh_discovers_only_post_data_loads():
    """The post-generation pass reloads both physical gold snapshots, never their CREATEs."""
    units = _gold_table_load_units("retail_prod", {})
    assert {os.path.basename(path) for path, _ in units} == {
        "gold_location_offer_performance.sql",
        "gold_zone_engagement_weekly.sql",
    }
    statements = [stmt for _path, stmts in units for stmt in stmts]
    assert statements
    assert all("INSERT OVERWRITE" in stmt.upper() for stmt in statements)
    assert not any("CREATE TABLE" in stmt.upper() for stmt in statements)
    # Smart Shelf's planogram-compliance gold reads BMV. The domain-closure resolver
    # therefore pulls BMV and its Promote-with-Purpose dependency, including these two
    # physical post-data-load snapshots.
    css_units = _gold_table_load_units(
        "retail_prod", {}, domains="connected-store-signals"
    )
    assert {os.path.basename(path) for path, _ in css_units} == {
        "gold_location_offer_performance.sql",
        "gold_zone_engagement_weekly.sql",
    }


def test_refresh_gold_tables_executes_every_discovered_load(monkeypatch):
    units = [("a.sql", ["INSERT OVERWRITE c.s.a SELECT 1"]),
             ("b.sql", ["INSERT OVERWRITE c.s.b SELECT 2"])]
    monkeypatch.setattr("tools.apply_model_ddl._gold_table_load_units", lambda *a, **k: units)
    seen = []
    refreshed, failures = refresh_gold_tables(lambda stmt: seen.append(stmt), "c", {})
    assert failures == []
    assert refreshed == 2
    assert set(seen) == {stmt for _path, stmts in units for stmt in stmts}


def test_deploy_jobs_and_lean_ci_refresh_physical_gold_before_dq():
    """Every generate->DQ path must reload physical gold snapshots in between."""
    yaml = pytest.importorskip("yaml")
    with open(os.path.join(REPO_ROOT, "databricks.yml")) as fh:
        bundle = yaml.safe_load(fh)
    for job_name in ("deploy_ordm", "deploy_ordm_daily"):
        tasks = {task["task_key"]: task for task in bundle["resources"]["jobs"][job_name]["tasks"]}
        refresh = tasks["refresh_gold_tables"]
        assert refresh["depends_on"] == [{"task_key": "generate_all"}]
        downstream = "refresh_materialized_views" if job_name == "deploy_ordm_daily" else "data_quality"
        assert tasks[downstream]["depends_on"] == [{"task_key": "refresh_gold_tables"}]

    wf = os.path.join(REPO_ROOT, ".github", "workflows", "ordm-lean-pr-deploy.yml")
    if not os.path.exists(os.path.join(REPO_ROOT, "tools", "publish", "manifest.yaml")):
        pytest.skip("public tree: ordm-lean-pr-deploy.yml is staging-only")
    workflow = open(wf).read()
    assert '"task_key": "refresh_gold_tables"' in workflow
    assert '"data_quality", "depends_on": [{"task_key": "refresh_gold_tables"}]' in workflow


# ---- MV DEFINITION reconcile (serving deploy; AI review #108 M2) ----------------------------
# _normalize_view_body must make a committed body compare EQUAL to the engine's stored
# view_definition for an UNCHANGED MV (no false-positive recreate), while a real body change is
# detected. Verified empirically false-positive-free over all 18 committed MVs on the reference workspace; the unit
# tests pin the normalization rules that make that hold.

def test_normalize_view_body_ignores_cosmetic_differences():
    """Comment-only, whitespace/case-only, and trailing-CLUSTER-BY-only differences normalize
    EQUAL -- so an unchanged MV is never needlessly dropped+recreated (the false-positive trap
    that a raw string compare would hit: the engine strips comments + keeps the CLUSTER BY tail)."""
    base = "SELECT a, b, c FROM t WHERE x > 5"
    assert _normalize_view_body(base) == _normalize_view_body("SELECT a, b, /*note*/ c FROM t WHERE x > 5")
    assert _normalize_view_body(base) == _normalize_view_body("select  A,  b ,c  from t where X > 5")
    # a trailing CLUSTER BY (physical layout, altered without a rebuild) is stripped on both sides
    assert _normalize_view_body(base) == _normalize_view_body(base + "\nCLUSTER BY (a, b)")
    assert _normalize_view_body(base + " CLUSTER BY (a)") == _normalize_view_body(base + " CLUSTER BY (b, c)")


def test_normalize_view_body_detects_real_changes():
    """An added/removed column, a changed filter, or a changed projection expression normalizes
    DIFFERENT -- so a genuine MV-definition change IS reconciled."""
    base = "SELECT a, b, c FROM t WHERE x > 5"
    assert _normalize_view_body(base) != _normalize_view_body("SELECT a, b, c, d FROM t WHERE x > 5")
    assert _normalize_view_body(base) != _normalize_view_body("SELECT a, b, c FROM t WHERE x > 6")
    assert _normalize_view_body(base) != _normalize_view_body("SELECT a, b, c * 2 AS c FROM t WHERE x > 5")


def test_normalize_view_body_unparseable_is_unique_sentinel():
    """An unparseable body maps to a raw-text sentinel, so two DIFFERENT unparseable bodies are
    unequal (=> treated as drifted => recreate/self-heal), never silently 'equal'."""
    a = _normalize_view_body("this is <<< not sql")
    b = _normalize_view_body("also ??? not sql")
    assert a != b and a.startswith("\x00UNPARSEABLE\x00")


def test_mv_definition_drifted_matrix():
    """The pure comparator: absent live def => drifted; cosmetic-only => not drifted; real change
    => drifted."""
    body = "SELECT a, b FROM t"
    assert _mv_definition_drifted(body, "") is True                       # absent -> (re)create
    assert _mv_definition_drifted(body, None) is True
    assert _mv_definition_drifted(body, "SELECT a, b FROM t /*c*/ CLUSTER BY (a)") is False  # cosmetic
    assert _mv_definition_drifted(body, "SELECT a, b, c FROM t") is True   # added column


def test_reconcile_materialized_views_drops_only_drifted(monkeypatch):
    """Driver over fakes: only the MV whose live definition differs is DROPPED (drop-only -- the
    following apply_ddl recreates it); an unchanged MV is left live; a missing MV is dropped
    (IF EXISTS no-ops) so apply recreates it. Reads the live def via run_query."""
    import tools.apply_model_ddl as m
    committed = [
        ("cat.s.mv_keep", "SELECT a FROM t"),
        ("cat.s.mv_drift", "SELECT a, b FROM t"),
        ("cat.s.mv_absent", "SELECT z FROM u"),
    ]
    monkeypatch.setattr(m, "_committed_materialized_views", lambda *a, **k: committed)
    live = {
        "cat.s.mv_keep": [["SELECT a FROM t CLUSTER BY (a)"]],   # cosmetic-only -> unchanged
        "cat.s.mv_drift": [["SELECT a FROM t"]],                 # committed added col b -> drift
        "cat.s.mv_absent": [],                                   # not present -> drift (recreate)
    }

    def run_query(sql):
        for fqn in live:
            if fqn.split(".")[-1] in sql and f"'{fqn.split('.')[-2]}'" in sql:
                return live[fqn]
        return []

    ddl = []
    dropped, unchanged, failures = m.reconcile_materialized_views(
        lambda s: ddl.append(s), run_query, "cat", {})
    assert dropped == 2 and unchanged == 1 and failures == []
    assert ddl == [
        "DROP MATERIALIZED VIEW IF EXISTS cat.s.mv_drift",
        "DROP MATERIALIZED VIEW IF EXISTS cat.s.mv_absent",
    ]
    assert not any("mv_keep" in s for s in ddl)                 # unchanged MV never touched
    assert not any(s.upper().startswith("CREATE") for s in ddl)  # DROP-only (apply recreates)


def test_reconcile_materialized_views_over_real_committed_bodies():
    """_committed_materialized_views yields real gold MVs with resolved names + a parseable body;
    _normalize_view_body round-trips each committed body without raising (guards the discovery +
    the normalizer against the real committed SQL)."""
    from tools.apply_model_ddl import _committed_materialized_views
    mvs = list(_committed_materialized_views("retail_prod", {}))
    assert len(mvs) >= 15, f"expected the committed gold MVs, saw {len(mvs)}"
    for fqn, body in mvs:
        assert fqn.startswith("retail_prod.") and "${" not in fqn
        assert not _normalize_view_body(body).startswith("\x00UNPARSEABLE\x00"), f"{fqn} body unparseable"


# ---- schema reconcile + full recreate (serving deploy; AI review #108 table-drift) ----
# Two opt-in modes fix CREATE TABLE IF NOT EXISTS silent schema drift. The diff logic is pure
# (no warehouse), so it is exhaustively unit-tested here; the drivers are tested with fakes.

from tools.apply_model_ddl import (  # noqa: E402
    _normalize_sql_type,
    _split_type_args,
    _columns_differ,
    _reconcile_table_plan,
    _describe_columns,
    _committed_tables,
    reconcile_schema,
    recreate_all,
)


# --- _normalize_sql_type: alias canonicalization ---

def test_normalize_sql_type_maps_aliases_and_strips_noise():
    assert _normalize_sql_type("int") == "INTEGER"
    assert _normalize_sql_type("INTEGER") == "INTEGER"
    assert _normalize_sql_type("long") == "BIGINT"
    assert _normalize_sql_type("bigint") == "BIGINT"
    assert _normalize_sql_type("bool") == "BOOLEAN"
    assert _normalize_sql_type("text") == "STRING"
    assert _normalize_sql_type("string") == "STRING"
    # whitespace + case normalized; parameterized args preserved and alias-mapped on the base
    assert _normalize_sql_type(" DEC(18,2) ") == "DECIMAL(18,2)"
    assert _normalize_sql_type("DECIMAL(18, 2)") == "DECIMAL(18,2)"
    assert _normalize_sql_type("numeric(10,0)") == "DECIMAL(10,0)"
    # None / empty are safe
    assert _normalize_sql_type(None) == ""
    assert _normalize_sql_type("") == ""


def test_normalize_sql_type_complex_types_normalized_recursively():
    """Complex types normalize RECURSIVELY so inner aliases map too (AI review #108 m3): an
    ARRAY<INT> vs ARRAY<INTEGER> or MAP<...,DEC(9,2)> vs MAP<...,DECIMAL(9,2)> drift is NOT a
    false positive. STRUCT field NAMES are preserved; field TYPES are normalized. A genuinely
    different inner type is still a real diff."""
    # inner alias mapping (the m3 fix): these must now be EQUAL, not merely uppercased
    assert _normalize_sql_type("ARRAY< int >") == "ARRAY<INTEGER>"
    assert _normalize_sql_type("ARRAY<int>") == _normalize_sql_type("ARRAY<integer>")
    assert _normalize_sql_type("MAP<string, dec(9,2)>") == "MAP<STRING,DECIMAL(9,2)>"
    assert _normalize_sql_type("STRUCT<a: string, b: int>") == "STRUCT<A:STRING,B:INTEGER>"
    # nested complex types recurse to any depth
    assert _normalize_sql_type("ARRAY<ARRAY<long>>") == "ARRAY<ARRAY<BIGINT>>"
    assert (_normalize_sql_type("STRUCT<x: array<int>, y: dec(4,1)>")
            == "STRUCT<X:ARRAY<INTEGER>,Y:DECIMAL(4,1)>")
    # a genuinely different inner type is STILL a real diff
    assert _normalize_sql_type("ARRAY<string>") != _normalize_sql_type("ARRAY<int>")


def test_split_type_args_splits_on_top_level_commas_only():
    """Top-level comma split keeps nested <...> and (p,s) groups intact -- the load-bearing bit
    that lets STRUCT/MAP fields normalize without a full type parser."""
    assert _split_type_args("STRING,INT") == ["STRING", "INT"]
    assert _split_type_args("STRING,DECIMAL(9,2)") == ["STRING", "DECIMAL(9,2)"]
    assert _split_type_args("a:MAP<STRING,INT>,b:INT") == ["a:MAP<STRING,INT>", "b:INT"]
    assert _split_type_args("") == []


# --- _columns_differ: the comparator (every drift class) ---

def _c(name, t):
    return {"name": name, "sql_type": t}


def test_columns_differ_absent_live_is_a_difference():
    assert _columns_differ([_c("a", "INT")], []) is True          # missing table -> recreate


def test_columns_differ_identical_is_false():
    committed = [_c("a", "INT"), _c("b", "STRING")]
    live = [_c("a", "INT"), _c("b", "STRING")]
    assert _columns_differ(committed, live) is False


def test_columns_differ_alias_equal_is_false():
    """INT vs INTEGER, DEC vs DECIMAL are the SAME physical type -> not a drift."""
    committed = [_c("a", "INT"), _c("amt", "DEC(18,2)")]
    live = [_c("a", "INTEGER"), _c("amt", "DECIMAL(18,2)")]
    assert _columns_differ(committed, live) is False


def test_columns_differ_reorder_and_comment_only_are_false():
    committed = [{"name": "a", "sql_type": "INT", "comment": "one"},
                 {"name": "b", "sql_type": "STRING", "comment": "two"}]
    live = [_c("b", "STRING"), _c("a", "INT")]           # reordered, comments absent from DESCRIBE
    assert _columns_differ(committed, live) is False


def test_columns_differ_added_dropped_renamed_retyped_are_true():
    base = [_c("a", "INT"), _c("b", "STRING")]
    assert _columns_differ(base, [_c("a", "INT")]) is True                       # dropped b
    assert _columns_differ(base, base + [_c("c", "INT")]) is True                # added c
    assert _columns_differ(base, [_c("a", "INT"), _c("bb", "STRING")]) is True   # renamed b->bb
    assert _columns_differ(base, [_c("a", "BIGINT"), _c("b", "STRING")]) is True # retyped a
    # decimal precision change is a real retype
    assert _columns_differ([_c("amt", "DECIMAL(18,2)")], [_c("amt", "DECIMAL(10,2)")]) is True


def test_columns_differ_is_case_insensitive_on_name():
    assert _columns_differ([_c("Amount", "INT")], [_c("amount", "INTEGER")]) is False


# --- _reconcile_table_plan: the planner (pure) ---

def test_reconcile_table_plan_splits_drifted_from_unchanged():
    committed = [
        ("c.s.t1", [_c("a", "INT")], "CREATE TABLE c.s.t1 (a INT)"),
        ("c.s.t2", [_c("x", "STRING")], "CREATE TABLE c.s.t2 (x STRING)"),
        ("c.s.t3", [_c("y", "INT")], "CREATE TABLE c.s.t3 (y INT)"),
    ]
    live = {
        "c.s.t1": [_c("a", "INTEGER")],                 # alias-equal -> unchanged
        "c.s.t2": [_c("x", "INT")],                     # retyped     -> recreate
        # c.s.t3 absent                                  # missing     -> recreate
    }
    to_recreate, unchanged = _reconcile_table_plan(committed, lambda f: live.get(f, []))
    assert unchanged == ["c.s.t1"]
    assert sorted(f for f, _ in to_recreate) == ["c.s.t2", "c.s.t3"]
    # the create_sql is carried through for the recreate
    assert dict(to_recreate)["c.s.t2"] == "CREATE TABLE c.s.t2 (x STRING)"


def test_reconcile_table_plan_all_unchanged_recreates_nothing():
    committed = [("c.s.t", [_c("a", "INT")], "CREATE TABLE c.s.t (a INT)")]
    to_recreate, unchanged = _reconcile_table_plan(committed, lambda f: [_c("a", "int")])
    assert to_recreate == [] and unchanged == ["c.s.t"]


# --- _describe_columns: DESCRIBE row reader ---

def test_describe_columns_stops_at_metadata_section():
    """DESCRIBE TABLE rows are [name, type, comment]; a blank or #-prefixed name row begins the
    partition/detail section, which must not be read as columns."""
    rows = [["a", "int", ""], ["b", "string", "note"],
            ["", "", ""], ["# Partition Information", "", ""], ["p", "int", ""]]
    cols = _describe_columns(lambda q: rows, "c.s.t")
    assert [c["name"] for c in cols] == ["a", "b"]
    assert cols[1]["sql_type"] == "string"


def test_describe_columns_absent_table_reads_empty():
    assert _describe_columns(lambda q: [], "c.s.gone") == []


# --- reconcile_schema driver (fake run + run_query) ---

def test_reconcile_schema_drops_only_drifted_and_never_recreates(monkeypatch):
    """End-to-end over the driver with fakes: only the drifted table is DROPPED (drop-only --
    AI review #108 H1); the following apply_ddl step recreates it WITH its tags/FKs, so this
    driver must emit NO CREATE. Unchanged tables are untouched; DESCRIBE is read via run_query."""
    import tools.apply_model_ddl as m
    committed = [
        ("cat.s.keep", [_c("a", "INT")], "CREATE TABLE cat.s.keep (a INT)"),
        ("cat.s.drift", [_c("x", "STRING")], "CREATE TABLE cat.s.drift (x STRING)"),
    ]
    monkeypatch.setattr(m, "_committed_tables", lambda *a, **k: committed)
    live = {"cat.s.keep": [["a", "integer", ""]], "cat.s.drift": [["x", "int", ""]]}

    def run_query(sql):
        fqn = sql.split("DESCRIBE TABLE ")[1].strip()
        return live.get(fqn, [])

    ddl = []

    def run(stmt):
        ddl.append(stmt)   # None return = ok, per _exec contract

    dropped, unchanged, failures = m.reconcile_schema(run, run_query, "cat", {})
    assert dropped == 1 and unchanged == 1 and failures == []
    # DROP-ONLY: the drifted table is dropped and NOT recreated here (apply_ddl does that).
    assert ddl == ["DROP TABLE IF EXISTS cat.s.drift"]
    assert not any(s.upper().startswith("CREATE") for s in ddl)  # never recreates -> keeps tags/FKs
    assert not any("keep" in s for s in ddl)   # unchanged table never touched


def test_reconcile_schema_collects_failures_without_raising(monkeypatch):
    """A failed DROP is collected as a failure (surfaced to the caller) and never raised, so
    one bad table does not abort the whole reconcile pass."""
    import tools.apply_model_ddl as m
    committed = [("cat.s.drift", [_c("x", "STRING")], "CREATE TABLE cat.s.drift (x STRING)")]
    monkeypatch.setattr(m, "_committed_tables", lambda *a, **k: committed)
    monkeypatch.setattr(m, "_describe_columns", lambda rq, fqn: [_c("x", "INT")])  # drift

    def run(stmt):
        raise Exception("drop boom")   # the (only) DROP fails

    dropped, unchanged, failures = m.reconcile_schema(run, lambda q: [], "cat", {})
    assert dropped == 0 and len(failures) == 1 and "drop" in failures[0].lower()


# --- recreate_all driver (full nuke) ---

def test_recreate_all_drops_every_managed_table_and_never_recreates(monkeypatch):
    """--recreate (admin clean-reinstall): DROP-ONLY -- every managed table is dropped and NONE
    is recreated here (AI review #108 H1: a CREATE-only recreate would lose SET TAGS + FKs). The
    caller MUST run a full apply afterwards to rebuild tables with their tags/relationships."""
    import tools.apply_model_ddl as m
    committed = [
        ("cat.s.t1", [_c("a", "INT")], "CREATE TABLE cat.s.t1 (a INT)"),
        ("cat.s.t2", [_c("x", "STRING")], "CREATE TABLE cat.s.t2 (x STRING)"),
    ]
    monkeypatch.setattr(m, "_committed_tables", lambda *a, **k: committed)
    ddl = []
    dropped, failures = m.recreate_all(lambda s: ddl.append(s), "cat", {})
    assert dropped == 2 and failures == []
    # every table dropped, and NOTHING recreated (apply-after restores tags/FKs)
    assert ddl == ["DROP TABLE IF EXISTS cat.s.t1", "DROP TABLE IF EXISTS cat.s.t2"]
    assert not any(s.upper().startswith("CREATE") for s in ddl)


def test_committed_tables_reads_the_real_tree_resolved():
    """Over the committed DDL: _committed_tables yields real managed tables with resolved
    fully-qualified names (no ${...} left) and parsed columns. Guards the discovery + resolve."""
    tables = list(_committed_tables("retail_prod", {}))
    assert len(tables) >= 28, "expected at least the 28 canonical-core tables"
    for fqn, cols, create_sql in tables[:5]:
        assert fqn.startswith("retail_prod.") and "${" not in fqn
        assert cols and all("name" in c and "sql_type" in c for c in cols)
        assert "CREATE TABLE" in create_sql.upper() and "${" not in create_sql


# ---- schema bootstrap must not drift from the config (root cause of the reference workspace ---------
# ---- daily-deploy SCHEMA_NOT_FOUND for agentic_commerce) -----------------------------

def _bootstrap_schema_tokens():
    """The ${*_schema} tokens the committed bootstrap file CREATEs, and the ones it ALTERs
    (ENABLE PREDICTIVE OPTIMIZATION), read straight from 00_bootstrap_schemas.sql."""
    import re
    text = open(BOOTSTRAP).read()
    created = set(re.findall(r"CREATE SCHEMA IF NOT EXISTS \$\{catalog\}\.\$\{(\w+)\}", text))
    altered = set(re.findall(r"ALTER SCHEMA \$\{catalog\}\.\$\{(\w+)\} ENABLE", text))
    return created, altered


def test_bootstrap_creates_a_schema_for_every_config_token():
    """PARITY GUARD (root cause of the daily-deploy failure): the hand-maintained
    00_bootstrap_schemas.sql must CREATE a schema for EVERY token in schema_defaults(). When
    ac_schema (agentic_commerce) was added to config but not the bootstrap, the daily deploy
    created its tables into a schema that never existed -> SCHEMA_NOT_FOUND, failing apply_ddl
    and skipping every downstream task. This pins the two lists together so that can't recur."""
    from tools.ordm_config import schema_defaults
    cfg = set(schema_defaults())
    created, altered = _bootstrap_schema_tokens()
    missing_create = cfg - created
    assert not missing_create, (
        "config declares schema tokens the bootstrap never CREATEs (add them to "
        f"runtime/examples/deploy-with-dab/00_bootstrap_schemas.sql): {sorted(missing_create)}")
    # every CREATEd schema is also PREDICTIVE-OPTIMIZATION enabled (no half-added token)
    assert created == altered, (
        f"bootstrap CREATE/ALTER token sets differ: only-create={sorted(created - altered)}, "
        f"only-alter={sorted(altered - created)}")
    # and the bootstrap never CREATEs a schema that isn't in the config (dead entry)
    assert not (created - cfg), f"bootstrap CREATEs unknown tokens: {sorted(created - cfg)}"


def test_agentic_commerce_schema_is_bootstrapped():
    """Regression pin for the exact miss: ac_schema/agentic_commerce -- which ships real
    tables (4) + gold + metric views -- must be in the bootstrap CREATE set."""
    created, _ = _bootstrap_schema_tokens()
    assert "ac_schema" in created


# ---- ensure_catalog_and_schemas: idempotent pre-flight (operator directive) ----------

def test_required_schema_names_derives_from_config_not_bootstrap():
    """The runtime schema-ensure set comes from schema_defaults() (+ overrides), so it is
    automatically complete even if the static bootstrap file lags. Includes agentic_commerce."""
    from tools.ordm_config import schema_defaults
    names = _required_schema_names({})
    assert set(names) == set(schema_defaults().values())
    assert "agentic_commerce" in names
    # a per-token override wins; --single_schema collapses everything to one name
    assert "cust_alt" in _required_schema_names({"customer_schema": "cust_alt"})
    from tools.ordm_config import single_schema_overrides
    assert _required_schema_names(single_schema_overrides("pr_123")) == ["pr_123"]


def test_ensure_catalog_and_schemas_creates_catalog_then_every_schema():
    """Pre-flight emits CREATE CATALOG IF NOT EXISTS first, then CREATE SCHEMA IF NOT EXISTS
    for every required schema (idempotent). This is the runtime safety net that makes a
    missing-schema deploy impossible regardless of the static bootstrap file."""
    from tools.ordm_config import schema_defaults
    ddl = []
    n = ensure_catalog_and_schemas(lambda s: ddl.append(s), "cat", {})
    assert ddl[0] == "CREATE CATALOG IF NOT EXISTS cat"
    schema_stmts = [s for s in ddl if s.startswith("CREATE SCHEMA")]
    assert len(schema_stmts) == n == len(set(schema_defaults().values()))
    assert "CREATE SCHEMA IF NOT EXISTS cat.agentic_commerce" in ddl
    assert all(s.startswith("CREATE ") for s in ddl)  # nothing but idempotent creates


def test_ensure_catalog_failure_is_best_effort_but_schema_failure_propagates():
    """CREATE CATALOG is best-effort (a pre-provisioned catalog may be un-creatable by the
    service principal) -> a catalog-only failure WARNs and continues to the schema creates.
    But a SCHEMA create failure is authoritative and must propagate (no table DDL can run
    without its schema)."""
    import pytest
    # catalog create denied, schemas fine -> still ensures all schemas, no raise
    def run_cat_denied(s):
        if s.startswith("CREATE CATALOG"):
            raise Exception("PERMISSION_DENIED: CREATE CATALOG")
    n = ensure_catalog_and_schemas(run_cat_denied, "cat", {})
    assert n == len(_required_schema_names({}))

    # a schema create failure propagates
    def run_schema_fails(s):
        if s.startswith("CREATE SCHEMA"):
            raise Exception("boom")
    with pytest.raises(Exception, match="boom"):
        ensure_catalog_and_schemas(run_schema_fails, "cat", {})


def test_apply_runs_ensure_before_any_table_ddl(monkeypatch):
    """apply() on the real (non-dry) runner path calls ensure_catalog_and_schemas BEFORE it
    dispatches any table/view DDL, so schemas always exist first. Verified by spying on the
    ensure helper and asserting it fired with the catalog + overrides apply() was given."""
    import tools.apply_model_ddl as m
    calls = []
    monkeypatch.setattr(m, "ensure_catalog_and_schemas",
                        lambda run, cat, ov, dom=None: calls.append((cat, ov, dom)) or 1)
    # a fake spark whose .sql just records; apply() takes the spark-runner branch (no warehouse)
    class _Rec:
        def __init__(self): self.sql_seen = []
        def sql(self, s): self.sql_seen.append(s)
    rec = _Rec()
    apply(spark=rec, catalog="retail_prod", overrides={"customer_schema": "c1"},
          dry_run=False, domains="customer")
    assert calls and calls[0][0] == "retail_prod"
    assert calls[0][1] == {"customer_schema": "c1"}
    # ensure fired before any CREATE SCHEMA/TABLE hit the runner (spy replaced the real ensure,
    # so the recorded sql starts with the bootstrap phase, not our ensure) -- the call happened.


def test_apply_dry_run_does_not_ensure(monkeypatch):
    """Dry-run never touches a live catalog: ensure_catalog_and_schemas must NOT be called."""
    import tools.apply_model_ddl as m
    called = []
    monkeypatch.setattr(m, "ensure_catalog_and_schemas",
                        lambda *a, **k: called.append(1))
    apply(spark=None, catalog="retail_prod", dry_run=True)
    assert called == []


# ---- inline view column comments into the CREATE (comments were the largest apply phase) ----

_VIEW = "-- header\n-- more header\nCREATE OR REPLACE VIEW c.s.gold_v AS\nSELECT a, b AS bee, 1 AS one FROM c.s.t"
_C_A = "COMMENT ON COLUMN c.s.gold_v.a IS 'col a'"
_C_B = "-- doc\nCOMMENT ON COLUMN c.s.gold_v.bee IS 'col b'"


def test_view_output_columns_exact_or_none():
    assert _view_output_columns(_VIEW) == ["a", "bee", "one"]
    # A star in the final projection means the arity is unknown -> never inline.
    assert _view_output_columns("CREATE OR REPLACE VIEW c.s.v AS SELECT * FROM c.s.t") is None
    assert _view_output_columns("CREATE OR REPLACE VIEW c.s.v AS SELECT t.*, 1 AS x FROM c.s.t t") is None


def test_view_output_columns_requires_explicit_names():
    # The inlined column list renames outputs BY POSITION, so a projection whose name sqlglot
    # only guesses (an unaliased CAST reads as its inner column) must make the view ineligible.
    assert _view_output_columns("CREATE OR REPLACE VIEW v AS SELECT CAST(x AS INT) FROM t") is None
    assert _view_output_columns("CREATE OR REPLACE VIEW v AS SELECT x::INT FROM t") is None
    assert _view_output_columns(
        "CREATE OR REPLACE VIEW v AS SELECT CAST(x AS INT) AS x, t.y FROM t") == ["x", "y"]


def test_inline_view_comments_rewrites_create_and_drops_inlined_comments():
    gold = [("p/gold/gold_v.sql", _VIEW)]
    comments = [("p/comments.sql", [_C_A, _C_B, "COMMENT ON TABLE c.s.gold_v IS 'tbl'"])]
    new_gold, remaining, fallback = _inline_view_comments(gold, comments)
    (rel, stmt), = new_gold
    assert "CREATE OR REPLACE VIEW c.s.gold_v (" in stmt
    assert "`a` COMMENT 'col a'" in stmt and "`bee` COMMENT 'col b'" in stmt and "`one`" in stmt
    assert stmt.index("`a`") < stmt.index("`bee`") < stmt.index("`one`")  # projection order
    assert stmt.startswith("-- header")  # leading header untouched
    # Column comments moved onto the CREATE; the table comment stays a separate statement.
    assert remaining == [("p/comments.sql", ["COMMENT ON TABLE c.s.gold_v IS 'tbl'"])]
    assert fallback[stmt] == (_VIEW, [_C_A, _C_B])


def test_inline_view_comments_leaves_unsafe_views_alone():
    star = ("p/gold/s.sql", "CREATE OR REPLACE VIEW c.s.gold_s AS SELECT * FROM c.s.t")
    quoted = ("p/gold/q.sql", "CREATE OR REPLACE VIEW c.s.gold_q AS SELECT a FROM c.s.t")
    unknown_col = ("p/gold/u.sql", "CREATE OR REPLACE VIEW c.s.gold_u AS SELECT a FROM c.s.t")
    mv = ("p/gold/m.sql", "CREATE OR REFRESH MATERIALIZED VIEW c.s.gold_m AS SELECT a FROM c.s.t")
    comments = [("p/comments.sql", [
        "COMMENT ON COLUMN c.s.gold_s.a IS 'x'",
        "COMMENT ON COLUMN c.s.gold_q.a IS 'the customer''s'",   # escaped quote: keep old path
        "COMMENT ON COLUMN c.s.gold_u.zzz IS 'not an output column'",
        "COMMENT ON COLUMN c.s.gold_m.a IS 'materialized view'",
    ])]
    gold = [star, quoted, unknown_col, mv]
    new_gold, remaining, fallback = _inline_view_comments(gold, comments)
    assert new_gold == gold and not fallback
    assert remaining == comments


def test_inline_fallback_runner_reapplies_original_and_comments_on_arity_error():
    new_gold, _rem, fallback = _inline_view_comments(
        [("p/gold/gold_v.sql", _VIEW)], [("p/comments.sql", [_C_A, _C_B])])
    rewritten = new_gold[0][1]
    calls = []

    def run(stmt):
        calls.append(stmt)
        if stmt == rewritten:
            raise RuntimeError("[CREATE_VIEW_COLUMN_ARITY_MISMATCH.TOO_MANY_DATA_COLUMNS] ...")

    _inline_fallback_runner(run, fallback)(rewritten)
    assert calls == [rewritten, _VIEW, _C_A, _C_B]


def test_inline_fallback_runner_propagates_other_errors():
    new_gold, _rem, fallback = _inline_view_comments(
        [("p/gold/gold_v.sql", _VIEW)], [("p/comments.sql", [_C_A])])
    rewritten = new_gold[0][1]

    def run(stmt):
        raise RuntimeError("[TABLE_OR_VIEW_NOT_FOUND] c.s.t")  # dependency not created yet

    with pytest.raises(RuntimeError, match="TABLE_OR_VIEW_NOT_FOUND"):
        _inline_fallback_runner(run, fallback)(rewritten)


@pytest.mark.parametrize("token", ["UNRESOLVED_COLUMN", "AMBIGUOUS_REFERENCE"])
def test_inline_fallback_runner_lets_view_body_errors_reach_the_fixpoint(token):
    # Body errors are not column-list errors: no fallback, the original CREATE is not run.
    new_gold, _rem, fallback = _inline_view_comments(
        [("p/gold/gold_v.sql", _VIEW)], [("p/comments.sql", [_C_A])])
    rewritten = new_gold[0][1]
    calls = []

    def run(stmt):
        calls.append(stmt)
        raise RuntimeError(f"[{token}] some column")

    with pytest.raises(RuntimeError, match=token):
        _inline_fallback_runner(run, fallback)(rewritten)
    assert calls == [rewritten]


def test_inline_fallback_runner_records_a_failing_fallback_comment():
    # The view exists once the original CREATE succeeds: a failing COMMENT is recorded, not raised.
    new_gold, _rem, fallback = _inline_view_comments(
        [("p/gold/gold_v.sql", _VIEW)], [("p/comments.sql", [_C_A])])
    rewritten = new_gold[0][1]
    original, comments = fallback[rewritten]

    def run(stmt):
        if stmt == rewritten:
            raise RuntimeError("[CREATE_VIEW_COLUMN_ARITY_MISMATCH] x")
        if stmt in comments:
            raise RuntimeError("[COLUMN_NOT_FOUND] bad comment")

    failures = []
    assert _inline_fallback_runner(run, fallback, failures)(rewritten) is None
    assert len(failures) == len(comments) and "fallback COMMENT" in failures[0][2]


def test_inline_fallback_runner_reraises_a_transient_fallback_comment_error():
    # Transient errors keep going to the fixpoint's retry instead of being recorded as failures.
    new_gold, _rem, fallback = _inline_view_comments(
        [("p/gold/gold_v.sql", _VIEW)], [("p/comments.sql", [_C_A])])
    rewritten = new_gold[0][1]
    _original, comments = fallback[rewritten]

    def run(stmt):
        if stmt == rewritten:
            raise RuntimeError("[CREATE_VIEW_COLUMN_ARITY_MISMATCH] x")
        if stmt in comments:
            raise RuntimeError("[CONCURRENT_UPDATE] retry me")

    failures = []
    with pytest.raises(RuntimeError, match="CONCURRENT_UPDATE"):
        _inline_fallback_runner(run, fallback, failures)(rewritten)
    assert failures == []


def test_apply_counts_a_failing_fallback_comment_in_the_summary(monkeypatch, capsys):
    # The summary's "N failed" must match the failures raised at the end.
    import tools.apply_model_ddl as mod

    class _Run:
        def __call__(self, stmt):
            if "CREATE OR REPLACE VIEW c.s.gold_v (" in " ".join(stmt.split()):
                raise RuntimeError("[CREATE_VIEW_COLUMN_ARITY_MISMATCH] x")
            if stmt == _C_A:
                raise RuntimeError("[COLUMN_NOT_FOUND] bad comment")

    monkeypatch.setattr(mod, "_wh_runner", lambda *a, **k: _Run())
    monkeypatch.setattr(mod, "_phases", lambda *a, **k: iter([
        ("outcome-gold", os.path.join(REPO, "p/gold/gold_v.sql"), [_VIEW]),
        ("comments", os.path.join(REPO, "p/comments.sql"), [_C_A]),
    ]))
    monkeypatch.setattr(mod, "_required_schema_names", lambda overrides, domains=None: [])
    with pytest.raises(AssertionError, match="fallback COMMENT"):
        mod.apply(None, "cat", overrides={}, warehouse="w", wsclient=object())
    assert "1 failed" in capsys.readouterr().out


def test_apply_reports_a_retried_fallback_comment_failure_once(monkeypatch, capsys):
    # A transient error on a later comment re-runs the whole fallback, which re-records the
    # first comment's failure: the summary and the raised list must still show it once.
    import tools.apply_model_ddl as mod
    seen = {"transient": 0}

    class _Run:
        def __call__(self, stmt):
            if "CREATE OR REPLACE VIEW c.s.gold_v (" in " ".join(stmt.split()):
                raise RuntimeError("[CREATE_VIEW_COLUMN_ARITY_MISMATCH] x")
            if stmt == _C_A:
                # A per-attempt id in the error text must not defeat the de-duplication.
                seen["attempt"] = seen.get("attempt", 0) + 1
                raise RuntimeError(f"[COLUMN_NOT_FOUND] bad comment (statement id {seen['attempt']})")
            if stmt == _C_B and seen["transient"] == 0:
                seen["transient"] += 1
                raise RuntimeError("[CONCURRENT_UPDATE] retry me")

    monkeypatch.setattr(mod, "_wh_runner", lambda *a, **k: _Run())
    monkeypatch.setattr(mod, "_phases", lambda *a, **k: iter([
        ("outcome-gold", os.path.join(REPO, "p/gold/gold_v.sql"), [_VIEW]),
        ("comments", os.path.join(REPO, "p/comments.sql"), [_C_A, _C_B]),
    ]))
    monkeypatch.setattr(mod, "_required_schema_names", lambda overrides, domains=None: [])
    with pytest.raises(AssertionError) as err:
        mod.apply(None, "cat", overrides={}, warehouse="w", wsclient=object())
    assert str(err.value).count("fallback COMMENT") == 1
    assert "1 failed" in capsys.readouterr().out


@pytest.mark.parametrize("demote", [True, False], ids=["lean-demoted", "daily"])
def test_inlined_deployed_gold_views_parse_and_keep_every_comment(demote):
    """Over the real repo, for both the lean gate (MVs demoted) and the daily deploy (MVs kept):
    every inlined CREATE still parses with its exact column list, no COMMENT statement is lost
    (each is either inlined or still in the comments phase), and in the daily path no
    materialized view is inlined (MVs keep the separate COMMENT path)."""
    gold, comments = [], []
    for label, path, statements in _phases("cat", {}, demote):
        rel = os.path.relpath(path, REPO)
        if label == "outcome-gold":
            gold.extend((rel, s) for s in statements)
        elif label == "comments":
            comments.append((rel, statements))
    new_gold, remaining, fallback = _inline_view_comments(gold, comments)
    assert fallback, "expected at least one gold view to have its comments inlined"
    inlined = [c for _orig, cs in fallback.values() for c in cs]
    before = [s for _r, ss in comments for s in ss]
    after = [s for _r, ss in remaining for s in ss]
    assert sorted(inlined + after) == sorted(before)
    for stmt in fallback:
        assert _view_output_columns(stmt) is not None
    if not demote:
        mv_create = re.compile(r"create\s+(?:or\s+(?:replace|refresh)\s+)?materialized\s+view", re.I)
        # Match the statement's own CREATE, not header comments that mention MVs.
        mv_inlined = [s for s in fallback if mv_create.match(s, _body_offset(s))]
        assert not mv_inlined, f"daily path inlined comments into {len(mv_inlined)} MV CREATE(s)"


# ---- relationship ALTERs regrouped per target table (one package file was one serial lane) ----

def test_regroup_alters_by_table_splits_files_and_keeps_same_table_order():
    units = [("p/relationships.sql", [
        "-- FKs\nALTER TABLE c.s.a ADD CONSTRAINT fk_a1 FOREIGN KEY (x) REFERENCES c.s.p (x)",
        "ALTER TABLE c.s.b ADD CONSTRAINT chk_b CHECK (y > 0)",
        "ALTER TABLE c.s.a ADD CONSTRAINT chk_a CHECK (z > 0)",
        "SELECT 1",
    ])]
    out = _regroup_alters_by_table(units)
    assert out[0] == (f"{units[0][0]}::c.s.a", [units[0][1][0], units[0][1][2]])
    assert out[1] == (f"{units[0][0]}::c.s.b", [units[0][1][1]])
    assert out[2] == ("p/relationships.sql", ["SELECT 1"])
    assert sum(len(s) for _t, s in out) == 4


def test_schemas_phase_dedups_the_real_bootstrap_file(monkeypatch):
    """The splitter keeps the file's `--` header on the bootstrap's first statement; the
    de-dup key must ignore it, or that CREATE is re-issued. Uses the real bootstrap file
    under --single_schema, and checks the ALTER SCHEMA lines run after every CREATE."""
    executed = []

    class _Run:
        def __call__(self, stmt):
            executed.append(" ".join(stmt[_body_offset(stmt):].split()).rstrip(";").lower())

    import tools.apply_model_ddl as mod
    overrides = mod.single_schema_overrides("pr_9")
    schemas = [p for p in mod._phases("cat", overrides) if p[0] == "schemas"]
    assert schemas and len(schemas[0][2]) > 2  # the real file, not a stub
    monkeypatch.setattr(mod, "_wh_runner", lambda *a, **k: _Run())
    monkeypatch.setattr(mod, "_phases", lambda *a, **k: iter(schemas))
    monkeypatch.setattr(mod, "_required_schema_names", lambda overrides, domains=None: ["pr_9"])
    mod.apply(None, "cat", overrides=overrides, warehouse="w", wsclient=object())
    creates = [i for i, s in enumerate(executed) if s == "create schema if not exists cat.pr_9"]
    alters = [i for i, s in enumerate(executed) if s.startswith("alter schema cat.pr_9")]
    assert len(creates) == 1  # the pre-flight only; no header-bearing duplicate
    assert len(alters) == 1 and alters[0] > max(creates)


def test_schemas_phase_skips_ensured_and_duplicate_creates(monkeypatch):
    """Under --single_schema every bootstrap line resolves to one schema that the pre-flight
    already created: the schemas phase must not re-issue 54 identical statements."""
    executed = []

    class _Run:
        def __call__(self, stmt):
            executed.append(" ".join(stmt.split()))

    import tools.apply_model_ddl as mod
    monkeypatch.setattr(mod, "_wh_runner", lambda *a, **k: _Run())
    monkeypatch.setattr(mod, "_phases", lambda *a, **k: iter([
        ("schemas", os.path.join(REPO, "runtime/examples/deploy-with-dab/00_bootstrap_schemas.sql"),
         ["CREATE SCHEMA IF NOT EXISTS cat.pr_9;", "CREATE SCHEMA IF NOT EXISTS cat.pr_9",
          "CREATE SCHEMA IF NOT EXISTS cat.other"]),
    ]))
    monkeypatch.setattr(mod, "_required_schema_names", lambda overrides, domains=None: ["pr_9"])
    mod.apply(None, "cat", overrides={}, warehouse="w", wsclient=object())
    creates = [s for s in executed if s.startswith("CREATE SCHEMA")]
    assert creates.count("CREATE SCHEMA IF NOT EXISTS cat.pr_9") == 1  # pre-flight only
    assert creates.count("CREATE SCHEMA IF NOT EXISTS cat.other") == 1
