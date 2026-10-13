"""Pure-logic tests for the single-scan FOLD BUILDER in runtime/data-quality/run_checks.py.

Many error/warn checks read the SAME table with only a different WHERE predicate;
folding collapses each such group into ONE CASE-SUM scan while still attributing a
violation back to its exact check. These tests exercise the pure builder
(_analyze_foldable / _build_folded_query / _fold_checks) with plain data -- NO
Spark: run_checks imports pyspark lazily (only in main()), so it loads by file
path here without a JVM (pyspark is not installed in CI's unit env).
"""

import importlib.util
import os

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _load_runner():
    # `data-quality` has a hyphen -> not importable as a package; load by path.
    # This must NOT require pyspark at import time (it imports lazily in main()).
    spec = importlib.util.spec_from_file_location(
        "ordm_run_checks_fold", os.path.join(REPO, "runtime", "data-quality", "run_checks.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rc = _load_runner()

T = "cat.customer.profile"   # a stand-in fully-qualified table


# ---- (a) three same-table SELECT*+WHERE checks fold into one 3-column scan ----

def test_three_same_table_checks_fold_into_one_query():
    checks = [
        ("customer", "a_nulls", "error", "SELECT * FROM %s WHERE x IS NULL" % T),
        ("customer", "b_negative", "error", "SELECT * FROM %s WHERE v < 0" % T),
        ("customer", "c_domain", "warn", "SELECT * FROM %s WHERE s NOT IN ('a','b')" % T),
    ]
    folded, standalone = rc._fold_checks(checks)
    assert standalone == []
    assert len(folded) == 1                              # one scan for the one table
    label, from_clause, group = folded[0]
    assert label == "customer" and from_clause == T
    assert len(group) == 3

    sql, name_to_col = rc._build_folded_query(from_clause, group)
    # one scan of the table, three CASE-SUM columns keyed by check name
    assert sql.count(" FROM ") == 1
    assert sql.strip().endswith("FROM " + T)
    assert sql.count("SUM(CASE WHEN") == 3
    for name, pred in (("a_nulls", "x IS NULL"), ("b_negative", "v < 0"),
                       ("c_domain", "s NOT IN ('a','b')")):
        assert ("(%s)" % pred) in sql                    # exact predicate preserved
        assert ("AS `%s`" % name) in sql                 # aliased by check name (backticked, m1)
    assert set(name_to_col.values()) == {"a_nulls", "b_negative", "c_domain"}


# ---- (b) uniqueness (GROUP BY/HAVING), JOIN, and metric are NOT folded --------

def test_join_group_by_and_metric_not_folded():
    join = ("customer", "fk_orphan", "error",
            "SELECT a.* FROM cat.customer.address a\n"
            "LEFT JOIN cat.customer.profile p ON a.profile_sk = p.profile_sk\n"
            "WHERE a.profile_sk IS NOT NULL AND p.profile_sk IS NULL")
    grpby = ("customer", "bk_unique", "error",
             "SELECT profile_id, COUNT(*) c FROM %s\n"
             "WHERE is_current = true GROUP BY profile_id HAVING COUNT(*) > 1" % T)
    metric = ("customer", "suppressed_rate", "metric",
              "SELECT AVG(v) AS r FROM %s WHERE is_current = true" % T)
    folded, standalone = rc._fold_checks([join, grpby, metric])
    assert folded == []                                  # none are foldable
    names = {n for _, n, _, _ in standalone}
    assert names == {"fk_orphan", "bk_unique", "suppressed_rate"}
    # and the analyzer rejects each individually
    assert rc._analyze_foldable("error", join[3]) is None
    assert rc._analyze_foldable("error", grpby[3]) is None
    assert rc._analyze_foldable("metric", metric[3]) is None


def test_subquery_and_no_where_and_setop_not_folded():
    # NOT EXISTS subquery (FK-orphan variant) -> not a single scan
    subq = ("bmv", "orphan", "error",
            "SELECT cp.* FROM cat.bmv.competitor_price cp\n"
            "WHERE cp.product_sk IS NOT NULL AND NOT EXISTS (\n"
            "  SELECT 1 FROM cat.bmv.product p WHERE p.product_sk = cp.product_sk)")
    nowhere = ("customer", "allrows", "error", "SELECT * FROM %s" % T)
    setop = ("customer", "u", "error",
             "SELECT * FROM %s WHERE v < 0 UNION SELECT * FROM %s WHERE v > 9" % (T, T))
    folded, standalone = rc._fold_checks([subq, nowhere, setop])
    assert folded == []
    assert {n for _, n, _, _ in standalone} == {"orphan", "allrows", "u"}


# ---- (c) different tables produce separate folded queries ---------------------

def test_different_tables_produce_separate_queries():
    t2 = "cat.customer.address"
    checks = [
        ("customer", "p1", "error", "SELECT * FROM %s WHERE a IS NULL" % T),
        ("customer", "p2", "error", "SELECT * FROM %s WHERE b IS NULL" % T),
        ("customer", "a1", "error", "SELECT * FROM %s WHERE c IS NULL" % t2),
    ]
    folded, standalone = rc._fold_checks(checks)
    assert standalone == []
    assert len(folded) == 2                               # one per distinct table
    by_table = {from_clause: group for _, from_clause, group in folded}
    assert set(by_table) == {T, t2}
    assert {n for n, _, _ in by_table[T]} == {"p1", "p2"}
    assert {n for n, _, _ in by_table[t2]} == {"a1"}


def test_same_table_different_alias_kept_apart():
    # An alias makes the FROM clause differ; conservative grouping keeps them in
    # separate scans (never merges an ambiguous case). Both still fold (of one).
    checks = [
        ("d", "bare", "error", "SELECT * FROM %s WHERE x IS NULL" % T),
        ("d", "aliased", "error", "SELECT p.* FROM %s p WHERE p.x IS NULL" % T),
    ]
    folded, _ = rc._fold_checks(checks)
    assert len(folded) == 2
    assert {fc for _, fc, _ in folded} == {T, T + " p"}


# ---- (d) column -> check-name map round-trips (attribution is exact) ----------

def test_column_to_check_name_round_trips():
    group = [
        ("chk_alpha", "error", "x IS NULL"),
        ("chk_beta", "warn", "y < 0"),
        ("chk_gamma", "error", "z NOT IN ('a')"),
    ]
    sql, name_to_col = rc._build_folded_query(T, group)
    # aliases in the SQL are exactly the map's keys, and map back to check names
    assert list(name_to_col.keys()) == ["chk_alpha", "chk_beta", "chk_gamma"]
    assert list(name_to_col.values()) == ["chk_alpha", "chk_beta", "chk_gamma"]
    for alias, name in name_to_col.items():
        assert ("AS `%s`" % alias) in sql                 # backticked alias (m1)
        assert alias == name                              # identity attribution contract
    # empty-table safety: SUM over zero rows is NULL, COALESCE'd to 0 (== COUNT(*))
    assert sql.count("COALESCE(SUM(") == 3


# ---- (e) a single foldable check on a table still folds (fold-of-one) ---------

def test_single_foldable_check_still_works():
    checks = [("customer", "solo", "error", "SELECT * FROM %s WHERE q IS NULL" % T)]
    folded, standalone = rc._fold_checks(checks)
    assert standalone == []
    assert len(folded) == 1
    label, from_clause, group = folded[0]
    assert (label, from_clause) == ("customer", T)
    sql, name_to_col = rc._build_folded_query(from_clause, group)
    assert sql.count("SUM(CASE WHEN") == 1
    assert name_to_col == {"solo": "solo"}


# ---- name-collision safety: same name in one group -> demote to standalone -----

def test_duplicate_name_in_group_demoted_to_standalone():
    checks = [
        ("d", "dup", "error", "SELECT * FROM %s WHERE a IS NULL" % T),
        ("d", "dup", "error", "SELECT * FROM %s WHERE b IS NULL" % T),
        ("d", "ok", "error", "SELECT * FROM %s WHERE c IS NULL" % T),
    ]
    folded, standalone = rc._fold_checks(checks)
    # the collided name runs standalone (no aliased-column clash); the unique one folds
    assert {n for _, n, _, _ in standalone} == {"dup"}
    assert len(standalone) == 2
    assert len(folded) == 1
    assert {n for n, _, _ in folded[0][2]} == {"ok"}


# ---- comment-stripping: header/desc lines never leak into the predicate -------

def test_leading_comment_lines_are_ignored():
    q = "-- a description line\nSELECT * FROM %s\nWHERE x IS NULL" % T
    info = rc._analyze_foldable("error", q)
    assert info is not None
    from_clause, predicate = info
    assert from_clause == T
    assert predicate == "x IS NULL"


def test_trailing_order_by_limit_qualify_not_folded():
    """m4 (AI review): a fold-SHAPED check (single table, no join/group-by) that still
    carries a trailing ORDER BY / LIMIT / QUALIFY / WINDOW after its WHERE must NOT fold,
    or the clause lands inside SUM(CASE WHEN (<pred> ORDER BY ...)) -> a syntax error that
    fails the whole table's folded group. No committed check hits this; guard it anyway."""
    assert rc._analyze_foldable("error", "SELECT * FROM c.s.t WHERE x IS NULL") == ("c.s.t", "x IS NULL")
    for tail in ("ORDER BY y", "LIMIT 10", "QUALIFY row_number() OVER (ORDER BY y) = 1"):
        assert rc._analyze_foldable("error", f"SELECT * FROM c.s.t WHERE x IS NULL {tail}") is None


def test_run_folded_falls_back_standalone_on_scan_failure():
    """M2: if a folded scan fails (e.g. one bad predicate), _run_folded must NOT degrade
    the whole group to ERROR -- it re-runs each check standalone via _run_one so only the
    genuine offender errors and the rest still PASS/FAIL. A fake spark fails the folded
    multi-CASE-SUM scan but succeeds the per-check COUNT(*) wrap."""
    class _FakeSpark:
        def sql(self, q):
            if q.count("SUM(CASE WHEN") > 1:          # the folded multi-column scan
                raise Exception("[PARSE] folded scan blew up")
            # standalone path: _run_one wraps as SELECT COUNT(*) ... ordm_chk
            class _Row:
                def __getitem__(self, k): return 0     # 0 violations -> PASS
                def __call__(self, *a): return self
            class _DF:
                def first(self_inner): return {"n": 0}
            return _DF()
    group = [("chk_a", "error", "x IS NULL"), ("chk_b", "error", "y < 0")]
    results = rc._run_folded(_FakeSpark(), "customer", "cat.customer.profile", group)
    # each check attributed individually (not one blanket ERROR for the whole group)
    assert {r[1] for r in results} == {"chk_a", "chk_b"}
    assert all(r[3] == "PASS" for r in results)        # standalone re-run succeeded per check


# ---- (l) --domains scoping via discover() + --single_schema resolution (design/59) ----

def test_discover_filter_set_scopes_to_requested_domains():
    """run_checks --domains scopes the DQ run to a subset: discover(filter_set) yields only
    checks.sql whose directory label is in the set (the lean per-PR gate runs DQ for just the
    PR's domains). No filter -> everything."""
    all_labels = {label for label, _ in rc.discover()}
    assert "customer" in all_labels, "expected the customer domain's checks.sql"
    scoped = list(rc.discover(filter_set={"customer"}))
    assert scoped, "customer must have a checks.sql"
    assert {label for label, _ in scoped} == {"customer"}
    # a label not present yields nothing (never raises)
    assert list(rc.discover(filter_set={"does_not_exist"})) == []


def test_single_schema_resolves_check_sql_into_one_schema():
    """Under --single_schema, run_checks resolves every ${*_schema} token in a checks.sql to
    the one pr_<N> schema (same seam as apply/generators), so the DQ queries hit exactly the
    schema the lean gate deployed into. Uses the shared resolver, no Spark."""
    from tools.ordm_config import single_schema_overrides, resolve
    overrides = single_schema_overrides("pr_77")
    # a representative check body referencing two different domain schema tokens
    sql = ("SELECT * FROM ${catalog}.${customer_schema}.account;\n"
           "SELECT * FROM ${catalog}.${bmv_schema}.gold_sales_actuals;")
    out = resolve(sql, "ordm_cicd", overrides)
    assert "ordm_cicd.pr_77.account" in out
    assert "ordm_cicd.pr_77.gold_sales_actuals" in out
    assert "${" not in out                              # every token resolved


# ---- static lint: no LIMIT-then-UNION precedence trap in any committed checks.sql ----

def test_no_check_has_limit_immediately_before_union():
    """In Spark, `SELECT ... FROM t LIMIT 1 UNION ALL SELECT ...` binds LIMIT to the WHOLE
    union set, not the individual SELECT -- so a per-branch `LIMIT 1` intended to sample one
    row per feed instead caps the ENTIRE union at 1 row. This silently broke
    early-risk-detection.freshness_all_feeds_present (its 3-feed count was capped at 1, so
    `< 3` always FAILED, surfacing once the serving deploy ran DQ at --fail_on error). The fix
    is to PARENTHESIZE each branch: `(SELECT ... LIMIT 1) UNION ALL (SELECT ... LIMIT 1)`.
    Guard every committed checks.sql so the trap cannot reappear. Pure text scan, no Spark."""
    import glob
    import re
    offenders = []
    for f in sorted(glob.glob(os.path.join(REPO, "**", "checks.sql"), recursive=True)):
        lines = open(f).read().splitlines()
        for i, ln in enumerate(lines):
            # a line ending in `LIMIT <n>` whose NEXT non-blank line starts with UNION/INTERSECT/EXCEPT
            if re.search(r"\bLIMIT\s+\d+\s*$", ln.strip()):
                j = i + 1
                while j < len(lines) and not lines[j].strip():
                    j += 1
                if j < len(lines) and re.match(r"^\s*(UNION|INTERSECT|EXCEPT)\b", lines[j], re.I):
                    rel = os.path.relpath(f, REPO)
                    offenders.append(f"{rel}:{i + 1}")
    assert not offenders, (
        "LIMIT binds to the whole set operation, not the branch -- parenthesize each branch "
        "(SELECT ... LIMIT n): " + "; ".join(offenders))
