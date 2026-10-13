# ============================================================
# ORDM · Data-quality framework · check runner
# Version: 0.5
# Generated: 2026-06-09
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-06-09
# ============================================================
# Discovers the check files (canonical-core/<domain>/checks.sql and
# outcome-packages/<pkg>/checks.sql), resolves ${catalog} and the
# ${<domain>_schema} tokens via the shared resolver (tools/ordm_config.py,
# which reads databricks.yml), runs each assertion via spark.sql, and reports.
# Each assertion SELECTs violating rows; 0 rows = PASS. The run FAILS (raises)
# if any `error`-severity check returns rows; `warn`-severity checks are
# reported but do not fail the run.
#
# Runs as a Databricks notebook/job task. Parameters (widgets):
#   catalog  (required)   — target Unity Catalog (never hardcoded; guardrail #1)
#   domains  (optional)   — comma-separated domains to check; default: all found
#   fail_on  (optional)   — "error" (default; fail on error-severity checks),
#                           "warn" (also fail on warnings), or "none" (report-only,
#                           never fail — for a partially-populated demo deploy)
# ============================================================

import glob
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor

# NOTE: pyspark is imported lazily in main() (the only place a SparkSession is
# constructed). The pure helpers below -- parse_checks, discover, and the fold
# builder (_fold_checks / _build_folded_query) -- take/return plain data and
# never touch Spark, so this module imports (and is unit-testable) without a JVM.

def _repo_root():
    """Repo/bundle root. `__file__` is unset when a serverless spark_python_task
    runs this file as the entry script, so fall back to sys.argv[0], then walk up
    to the directory that holds databricks.yml (present in the synced bundle)."""
    try:
        start = os.path.dirname(os.path.abspath(__file__))
    except NameError:
        start = os.path.dirname(os.path.abspath(sys.argv[0])) if sys.argv and sys.argv[0] else os.getcwd()
    d = start
    for _ in range(10):
        if os.path.isfile(os.path.join(d, "databricks.yml")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return os.path.abspath(os.path.join(start, "..", ".."))


REPO_ROOT = _repo_root()
CANONICAL_GLOB = os.path.join(REPO_ROOT, "canonical-core", "*", "checks.sql")
OUTCOME_GLOB = os.path.join(REPO_ROOT, "outcome-packages", "*", "checks.sql")
HEADER_RE = re.compile(r"^--\s*check:\s*(?P<name>[\w]+)\s*\|\s*severity:\s*(?P<sev>error|warn|metric)\s*$",
                       re.IGNORECASE)

# Single source of truth for ${catalog}/${*_schema} resolution (reads the
# schema names from databricks.yml). Same resolver used by the tests.
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)
from tools.ordm_config import resolve, schema_defaults, single_schema_overrides  # noqa: E402


def _argv_param(name, default=None):
    """Read `--name value` or `--name=value` from argv (for a spark_python_task)."""
    flag = "--" + name
    argv = sys.argv[1:]
    for i, arg in enumerate(argv):
        if arg == flag and i + 1 < len(argv):
            return argv[i + 1]
        if arg.startswith(flag + "="):
            return arg[len(flag) + 1:]
    return default


def get_param(name, default=None):
    """Widget (notebook) -> env -> `--name` CLI flag (spark_python_task) -> default."""
    try:
        return dbutils.widgets.get(name)  # noqa: F821 (injected in notebooks)
    except Exception:
        pass
    if name.upper() in os.environ:
        return os.environ[name.upper()]
    return _argv_param(name, default)


def parse_checks(sql_text):
    """Yield (name, severity, query) tuples from a checks.sql file.

    A check starts at a `-- check: <name> | severity: <sev>` header and its
    query runs until the terminating semicolon.
    """
    checks = []
    current = None
    buf = []
    for line in sql_text.splitlines():
        m = HEADER_RE.match(line.strip())
        if m:
            current = (m.group("name"), m.group("sev").lower())
            buf = []
            continue
        if current is None:
            continue
        if line.strip().startswith("--"):
            continue  # description / comment line
        buf.append(line)
        if ";" in line:
            query = "\n".join(buf).strip().rstrip(";").strip()
            if query:
                checks.append((current[0], current[1], query))
            current = None
            buf = []
    return checks


def discover(filter_set=None):
    """Yield (label, path) for every checks.sql — canonical-core domains and
    outcome packages alike. SQL uses ${<domain>_schema} tokens resolved by the
    shared resolver, so no per-file schema bookkeeping is needed here."""
    for path in sorted(glob.glob(CANONICAL_GLOB)) + sorted(glob.glob(OUTCOME_GLOB)):
        label = os.path.basename(os.path.dirname(path))
        if filter_set and label not in filter_set:
            continue
        yield label, path


def _run_one(spark, label, name, severity, query):
    """Execute one check. error/warn checks are COUNT(*)-wrapped so the violation
    count is computed in-engine and NO rows are shipped to the driver; metric
    checks return their scalar value. Returns (label, name, severity, status, value)."""
    try:
        if severity == "metric":
            row = spark.sql(query).first()
            return (label, name, severity, "METRIC", row[0] if row is not None else None)
        violations = spark.sql(f"SELECT COUNT(*) AS n FROM (\n{query}\n) ordm_chk").first()["n"]
        status = "PASS" if violations == 0 else ("FAIL" if severity == "error" else "WARN")
        return (label, name, severity, status, violations)
    except Exception as exc:  # a malformed / under-deployed check is itself a failure
        return (label, name, severity, "ERROR", str(exc))


# ------------------------------------------------------------------
# Single-scan folding (perf). Many error/warn checks read the SAME table with
# only a different WHERE predicate; each is its own Spark job today and, on tiny
# demo data, job-submission overhead dominates. We fold every FOLDABLE check that
# targets the same (label, table) into ONE scan that computes each check's
# violation count as its own aggregate column, then map each column back to its
# check so a violation still reports the exact (label, name, severity, status,
# violations) tuple it would have reported standalone. These helpers are PURE
# (plain data in/out, no Spark) so they are unit-testable without a JVM.
# ------------------------------------------------------------------

# A check body is FOLDABLE when it is a single-table row predicate:
#   SELECT * FROM <table>  (or  SELECT <alias>.* FROM <table> <alias>)  WHERE <pred>
# with NO subquery, NO JOIN, NO GROUP BY / HAVING, and NO set operation. The
# violation predicate is exactly the text after WHERE.
_FOLD_PROJ_RE = re.compile(r"\A\s*select\s+(?:\*|[a-z_]\w*\s*\.\s*\*)\s+from\b",
                           re.IGNORECASE)
_SAFE_IDENT_RE = re.compile(r"\A[A-Za-z_]\w*\Z")


def _strip_sql_comments(query):
    """Drop whole-line `--` comments (parse_checks already excludes header/desc
    lines, but strip defensively so the shape match sees only SQL)."""
    return "\n".join(l for l in query.splitlines() if not l.strip().startswith("--"))


def _analyze_foldable(severity, query):
    """Return (from_clause, predicate) if `query` is a foldable single-table row
    predicate, else None. Conservative by design: anything ambiguous -> None
    (runs standalone, unchanged). NEVER changes which rows count as violations."""
    if severity == "metric":
        return None
    body = _strip_sql_comments(query).strip()
    # A mid-line `--` (rare) could comment out part of a one-line predicate once we
    # re-embed it; refuse to fold rather than risk it.
    if not body or "--" in body:
        return None
    low = body.lower()
    if not _FOLD_PROJ_RE.match(body):
        return None                                   # not a `SELECT * / alias.* FROM` shape
    if len(re.findall(r"\bselect\b", low)) != 1:
        return None                                   # subquery / derived table / CTE -> not one scan
    if re.search(r"\bjoin\b", low):
        return None                                   # cross-table -> not foldable
    if re.search(r"\bgroup\s+by\b", low) or re.search(r"\bhaving\b", low):
        return None                                   # aggregate/uniqueness -> not a row predicate
    if re.search(r"\b(?:union|intersect|except)\b", low):
        return None                                   # set operation -> not one scan
    mw = re.search(r"\bwhere\b", body, re.IGNORECASE)
    if not mw:
        return None                                   # `SELECT * FROM t` w/ no WHERE: all rows violate -> skip
    mf = re.search(r"\bfrom\b", body[:mw.start()], re.IGNORECASE)
    if not mf:
        return None
    from_clause = re.sub(r"\s+", " ", body[mf.end():mw.start()]).strip()
    predicate = body[mw.end():].strip()
    if not from_clause or not predicate:
        return None
    # The predicate is everything after WHERE. A trailing ORDER BY / LIMIT / QUALIFY /
    # WINDOW / set-op would fold into `SUM(CASE WHEN (<pred> ORDER BY ...) ...)` -- a syntax
    # error that fails the whole table's folded group. No committed check has one today
    # (they only appear inside excluded subqueries), so this is latent; refuse to fold when
    # present, mirroring the conservatism already applied to JOIN/GROUP BY/set-ops above.
    if re.search(r"\b(?:order\s+by|limit|qualify|window)\b", predicate, re.IGNORECASE):
        return None
    return from_clause, predicate


def _build_folded_query(from_clause, group):
    """Build ONE single-scan query for a group of foldable checks over the same
    FROM clause. `group` is a list of (name, severity, predicate). Returns
    (sql, name_to_col) where name_to_col maps each result column alias back to its
    check name (identity here, since aliases are the check names, but returned as
    the explicit attribution contract). COALESCE(...,0) so an empty table reports
    0 violations (SUM over zero rows is NULL) -- matching the COUNT(*) semantics of
    the standalone path exactly."""
    cols = []
    name_to_col = {}
    for name, _severity, predicate in group:
        # Backtick the alias so a future check name that collides with a SQL reserved word
        # cannot break the whole folded group (m1). Names are \w+ (HEADER_RE), so there is
        # no backtick to escape inside them.
        alias = "`%s`" % name
        cols.append(
            "COALESCE(SUM(CASE WHEN (%s) THEN 1 ELSE 0 END), 0) AS %s" % (predicate, alias))
        name_to_col[name] = name
    sql = "SELECT " + ", ".join(cols) + " FROM " + from_clause
    return sql, name_to_col


def _fold_checks(checks):
    """Partition (label, name, severity, query) checks into folded groups and
    standalone checks. Returns (folded, standalone):
      folded     -> list of (label, from_clause, group), group = [(name, sev, pred)]
      standalone -> list of (label, name, severity, query)  (run exactly as today)
    Foldable checks are grouped by (label, from_clause) so each group scans one
    table once. A group of one folds trivially (== the original, safe). A check
    whose name is not unique within its group, or is not a safe SQL identifier, is
    demoted to standalone to avoid a column-alias collision."""
    groups = {}   # (label, from_clause) -> [(name, severity, predicate, query)]
    standalone = []
    for label, name, severity, query in checks:
        info = _analyze_foldable(severity, query)
        if info is None or not _SAFE_IDENT_RE.match(name):
            standalone.append((label, name, severity, query))
            continue
        from_clause, predicate = info
        groups.setdefault((label, from_clause), []).append((name, severity, predicate, query))

    folded = []
    for (label, from_clause), members in groups.items():
        names = [m[0] for m in members]
        dup = {n for n in names if names.count(n) > 1}
        group = []
        for name, severity, predicate, query in members:
            if name in dup:
                standalone.append((label, name, severity, query))  # keep separate on collision
            else:
                group.append((name, severity, predicate))
        if group:
            folded.append((label, from_clause, group))
    return folded, standalone


def _run_folded(spark, label, from_clause, group):
    """Execute one folded single-scan query and attribute each aggregate column
    back to its check. Returns a LIST of (label, name, severity, status, value)
    tuples -- one per check in `group` -- identical to what standalone runs would
    produce. If the scan fails, every check in the group degrades to ERROR (as it
    would have standalone), so no check is silently lost."""
    try:
        sql, name_to_col = _build_folded_query(from_clause, group)
        row = spark.sql(sql).first()
        sev_by_name = {name: sev for name, sev, _ in group}
        results = []
        for idx, (_alias, name) in enumerate(name_to_col.items()):
            violations = row[idx] if row is not None else 0
            if violations is None:
                violations = 0
            severity = sev_by_name[name]
            status = "PASS" if violations == 0 else ("FAIL" if severity == "error" else "WARN")
            results.append((label, name, severity, status, violations))
        return results
    except Exception:  # noqa: BLE001
        # Fold-then-fallback (M2): one bad predicate would otherwise degrade EVERY check in
        # the group to ERROR, losing attribution vs. the standalone path. Re-run each check
        # standalone via _run_one so only the genuinely-failing check(s) report ERROR and the
        # rest still PASS/FAIL correctly. The fallback reconstructs each check's original
        # single-table query (SELECT * FROM <from_clause> WHERE <predicate>), which _run_one
        # then COUNT(*)-wraps exactly as it does an un-folded check.
        return [_run_one(spark, label, name, severity,
                         "SELECT * FROM %s WHERE %s" % (from_clause, predicate))
                for name, severity, predicate in group]


def run(spark, catalog, filter_set=None, fail_on="error", schema_overrides=None, max_parallel=8):
    if not catalog:
        raise ValueError("`catalog` parameter is required (guardrail #1: no hardcoded catalog).")
    schema_overrides = schema_overrides or {}

    # Collect every check (optionally for a single domain -- filter_set={label} --
    # so the deploy can stream DQ per domain as its data lands), then run them
    # CONCURRENTLY against the one Spark session. Same-table single-scan checks are
    # FOLDED into one CASE-SUM query each (many small jobs -> one scan), and the
    # remaining uniqueness/join/metric/no-where checks run standalone exactly as
    # before. Folding applies within a single-domain call too. Both the folded
    # queries and the standalone checks go through the SAME ThreadPoolExecutor, so
    # max_parallel still governs submit concurrency.
    checks = []
    for label, path in discover(filter_set):
        text = resolve(open(path).read(), catalog, schema_overrides)
        for name, severity, query in parse_checks(text):
            checks.append((label, name, severity, query))

    folded, standalone = _fold_checks(checks)

    def _work(item):
        kind, payload = item
        if kind == "fold":
            return _run_folded(spark, *payload)          # -> list of per-check tuples
        return [_run_one(spark, *payload)]               # -> single-element list

    units = [("fold", f) for f in folded] + [("one", s) for s in standalone]
    with ThreadPoolExecutor(max_workers=max(1, max_parallel)) as pool:
        results = [r for batch in pool.map(_work, units) for r in batch]

    for label, name, severity, status, value in sorted(results, key=lambda r: (r[0], r[1])):
        if status == "METRIC":
            print(f"  [{label}] {name:42} METRIC value={value}")
        elif status == "ERROR":
            print(f"  [{label}] {name:42} ERROR  {value}")
        else:
            print(f"  [{label}] {name:42} {status:5} violations={value}")

    failed = [r for r in results
              if r[3] in ("ERROR", "FAIL")
              or (fail_on == "warn" and r[3] == "WARN")]

    print(f"\n[ordm] data-quality: {len(results)} checks, {len(failed)} failing "
          f"(fail_on={fail_on}).")
    if failed:
        names = ", ".join(f"{lbl}.{n}" for lbl, n, *_ in failed)
        # fail_on=none is report-only: surface every violation but never raise. Used
        # by the demo deploy, where the model is only partially populated (not every
        # domain has a generator) so a legitimately-empty domain must not red the run.
        if fail_on == "none":
            print(f"[ordm] report-only (fail_on=none): NOT failing despite: {names}")
        else:
            raise AssertionError(f"Data-quality checks failed: {names}")
    return results


def run_domain(spark, catalog, label, fail_on="error", schema_overrides=None, max_parallel=8):
    """Run data quality for ONE domain/package (`label`) and return only that
    domain's results. Thin convenience wrapper over run(filter_set={label}) for the
    per-domain streaming deploy: it can fire DQ for a domain the moment that
    domain's data lands, rather than waiting for every domain. Folding still applies
    within the single-domain call. Orchestration (deciding WHEN each domain is
    ready) is the deploy's job, not this runner's."""
    return run(spark, catalog, filter_set={label}, fail_on=fail_on,
               schema_overrides=schema_overrides, max_parallel=max_parallel)


def main():
    from pyspark.sql import SparkSession
    spark = SparkSession.builder.getOrCreate()
    catalog = get_param("catalog", "")
    domains = get_param("domains", "")
    fail_on = get_param("fail_on", "error")
    filter_set = [d.strip() for d in domains.split(",") if d.strip()] or None
    overrides = {k: get_param(k, "") for k in schema_defaults()}
    overrides = {k: v for k, v in overrides.items() if v}
    # --single_schema collapses ALL schema tokens to one value so DQ checks a PR's domains
    # in the same single pr_<N> schema the apply step wrote to (design/59 lean per-PR gate).
    overrides.update(single_schema_overrides(get_param("single_schema", "")))
    max_parallel = int(get_param("max_parallel", "8"))
    run(spark, catalog, filter_set, fail_on, overrides, max_parallel)


if __name__ == "__main__":
    main()
