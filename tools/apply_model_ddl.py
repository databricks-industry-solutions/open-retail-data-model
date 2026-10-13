# ============================================================
# ORDM · Deploy · apply model DDL
# ============================================================
# Applies the ORDM data-model DDL to Unity Catalog in dependency order, so a
# deploy (or a recreated workspace) is one task instead of a hand-run sequence of
# SQL files. Mirrors runtime/data-quality/run_checks.py: it discovers the committed .sql,
# resolves ${catalog}/${*_schema} tokens via the shared resolver (tools.ordm_config,
# which reads databricks.yml), and executes each statement with spark.sql.
#
# Order:  schemas -> core tables -> core relationships -> outcome tables
#         -> outcome relationships -> outcome gold views -> metric views -> comments
# Tables are CREATE TABLE IF NOT EXISTS and relationships are ALTER ... ADD
# CONSTRAINT (not idempotent), so re-runs tolerate "already exists" and continue.
# UC metric views (CREATE VIEW ... WITH METRICS LANGUAGE YAML AS $$...$$) are GA
# plain views and run here (the splitter is $$-aware). comments.sql (COMMENT ON
# COLUMN, the Genie/AI-BI documentation layer) runs last, after its targets exist.
#
# All DDL runs on ONE engine: a SQL warehouse when --warehouse is given (uniform +
# portable — materialized views only create cleanly on a warehouse, not on
# serverless generic compute where the async-refresh registration is unreliable;
# DBSQL also handles the physical DDL: IDENTITY, CLUSTER BY, SET TAGS, ADD
# CONSTRAINT). Without --warehouse it falls back to the job's Spark (local/dry-run).
# The synthetic-data generators and DQ are separate job tasks and always run on Spark.
#
# Parallelism (design 57 PR1, red-team rt01/rt02/rt05/rt07/rt09): within each flat
# phase the statements are grouped BY FILE into units and the units run concurrently
# (tools.ddl_exec.run_units_parallel), while the statements INSIDE a file stay ordered
# so a CREATE precedes its SET TAGS (rt05) and same-object metadata thrash is avoided
# (rt02). The gold fixpoint runs each pass concurrently but keeps its fixpoint semantics
# as the safety net for a parser-invisible dependency (rt09). Failures are folded on the
# main thread and reported in full; shared counters are never mutated from workers.
#
# Intentionally EXCLUDED (documented, not silent):
#   - canonical-core/*/masks.sql : PII column masks (SET MASK) are deploy-gated —
#       they require the `pii_readers` account group and governance grants to
#       exist first — so they are applied out-of-band, not by this job.
#
# Params (widget on Databricks, else env UPPER, else --flag, else default):
#   catalog              (required)  — target Unity Catalog (never hardcoded; guardrail #1)
#   warehouse            (optional)  — SQL warehouse id; routes ALL DDL there via the SDK
#   <token>              (optional)  — override any ${*_schema}, e.g. --customer_schema cust
#   dry_run              (optional)  — "true" to list what WOULD run without a Spark session
#   max_workers          (optional)  — per-file thread-pool width (default 16); the SDK
#                                      connection pool is raised to match (rt01, rt07)
#   demote_materialized  (optional)  — "true" to deploy the 18 MVs as plain views for the
#                                      fast gate / demo (rt06); default OFF (keeps serving MVs)
#   profile              (optional)  — "true" to time each statement and print a per-phase
#                                      summary (count/total/p50/p95) + capture statement_ids
#                                      for a Query History join (rt08); ~zero overhead when off
#   domains              (optional)  — comma-separated domain/package labels for a lean per-PR
#                                      gate; deploy ONLY those (plus the always-on schema
#                                      bootstrap). Any outcome package auto-includes ALL
#                                      canonical-core (its shared dependency). Empty = ALL
#                                      (today's behaviour). Mirrors run_checks.py's `domains`.
#   refresh_gold_tables  (optional)  — post-generate load-only pass for physical gold tables;
#                                      executes their INSERT OVERWRITE statements, then exits.
#
# Runs as a Databricks spark_python_task/notebook, or locally with --dry-run.
# ============================================================
from __future__ import annotations

import glob
import os
import re
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass

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
    return os.path.abspath(os.path.join(start, ".."))


REPO_ROOT = _repo_root()
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)
from tools.ordm_config import (  # noqa: E402
    resolve,
    rfid_clock_expressions,
    rfid_policy_expressions,
    schema_defaults,
    shelf_clock_expressions,
    shelf_policy_expressions,
    single_schema_overrides,
    view_select_body,
)
# Shared parallel primitives (locked contract, design 57 PR1): run_units_parallel fans
# out per-file units concurrently while keeping each unit's statements sequential, retries
# the concurrency-only error classes (its own RETRYABLE_TOKENS), and folds ALL failures on
# the caller's thread; is_retryable classifies those same errors for the hand-rolled gold
# fixpoint; demote_materialized_views rewrites CREATE OR REFRESH MATERIALIZED VIEW ->
# CREATE OR REPLACE VIEW (rt06).
from tools.ddl_exec import (  # noqa: E402
    demote_materialized_views,
    materialized_view_fqns,
    retarget_demoted_alter_tags,
    is_materialized_view_create,
    is_retryable,
    run_units_parallel,
)

# These globs intentionally span EVERY committed package, including ones marked
# Planned in STATUS.md: the deploy applies whatever DDL is committed regardless of
# status (a Planned package with an empty tables/ contributes nothing). This is a
# choice — committing a table into a Planned package puts it in the deploy path.
BOOTSTRAP = os.path.join(REPO_ROOT, "runtime", "examples", "deploy-with-dab", "00_bootstrap_schemas.sql")
CORE_TABLES = os.path.join(REPO_ROOT, "canonical-core", "*", "tables", "*.sql")
CORE_RELS = os.path.join(REPO_ROOT, "canonical-core", "*", "relationships.sql")
OUTCOME_TABLES = os.path.join(REPO_ROOT, "outcome-packages", "*", "tables", "*.sql")
OUTCOME_RELS = os.path.join(REPO_ROOT, "outcome-packages", "*", "relationships.sql")
OUTCOME_GOLD = os.path.join(REPO_ROOT, "outcome-packages", "*", "gold", "*.sql")
# UC metric views (WITH METRICS LANGUAGE YAML AS $$...$$); read gold, applied after it.
METRIC_VIEWS = os.path.join(REPO_ROOT, "outcome-packages", "*", "metric-views", "*.sql")
# COMMENT ON COLUMN docs for the gold views/tables; applied last (targets must exist).
COMMENTS = [os.path.join(REPO_ROOT, "canonical-core", "*", "comments.sql"),
            os.path.join(REPO_ROOT, "outcome-packages", "*", "comments.sql")]

# "already exists" phrasings Databricks/Spark use for a re-added constraint or an
# existing object — treated as an idempotent no-op, not a failure.
_EXISTS = ("already exists", "already been added", "constraint_already_exists",
           "already exist")
# Transient phrasings for a just-created materialized view whose async refresh
# pipeline hasn't registered yet — retryable, not a real failure.
_MV_TRANSIENT = ("not ready for refresh", "try again later", "pipeline entry missing")


def _argv_param(name, default=None):
    # Accept both the underscore token get_param callers use (e.g. demote_materialized)
    # and the hyphenated spelling DABs task params commonly carry (--demote-materialized),
    # so a flag name mismatch cannot silently drop a parameter. A flag with NO following
    # value, or one followed by another --flag, is a bare boolean and resolves to "true"
    # (e.g. --profile, --demote-materialized) so a switch does not need a dummy value.
    flags = {"--" + name, "--" + name.replace("_", "-"), "--" + name.replace("-", "_")}
    argv = sys.argv[1:]
    for i, arg in enumerate(argv):
        for flag in flags:
            if arg == flag:
                nxt = argv[i + 1] if i + 1 < len(argv) else None
                return "true" if (nxt is None or nxt.startswith("--")) else nxt
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


def _statements(sql_text):
    """Split SQL into individual statements on top-level `;`.

    A single quote-aware scanner used for EVERY file, because a tables/ file is
    not one statement: it is a CREATE followed by the CI-mandated
    `ALTER ... SET TAGS ('dbx_data_type' = ...)` (and, on PII masters, several
    more) — spark.sql() runs exactly one statement, so the CREATE and each ALTER
    must be applied separately. A naive `;` split would break on the `;` that can
    appear inside a COMMENT '...' string, so the scanner ignores `;` inside
    single-quoted strings ('' escapes a quote), backtick identifiers, `-- ` line
    comments, `/* */` block comments, and `$$ ... $$` dollar-quoted bodies (used by
    UC metric views: `WITH METRICS LANGUAGE YAML AS $$ <yaml> $$`, whose YAML body
    contains `;`). Comment-only fragments are dropped.
    """
    stmts, buf = [], []
    i, n = 0, len(sql_text)
    in_str = in_tick = in_line = in_block = in_dollar = False
    while i < n:
        c = sql_text[i]
        nxt = sql_text[i + 1] if i + 1 < n else ""
        if in_line:
            buf.append(c)
            if c == "\n":
                in_line = False
        elif in_block:
            buf.append(c)
            if c == "*" and nxt == "/":
                buf.append(nxt); i += 2; in_block = False; continue
        elif in_dollar:  # inside a $$...$$ body: copy verbatim until the closing $$
            buf.append(c)
            if c == "$" and nxt == "$":
                buf.append(nxt); i += 2; in_dollar = False; continue
        elif in_str:
            buf.append(c)
            if c == "'":
                if nxt == "'":  # '' is an escaped quote, still inside the string
                    buf.append(nxt); i += 2; continue
                in_str = False
        elif in_tick:
            buf.append(c)
            if c == "`":
                in_tick = False
        elif c == "-" and nxt == "-":
            in_line = True; buf.append(c)
        elif c == "/" and nxt == "*":
            in_block = True; buf.append(c); buf.append(nxt); i += 2; continue
        elif c == "$" and nxt == "$":
            in_dollar = True; buf.append(c); buf.append(nxt); i += 2; continue
        elif c == "'":
            in_str = True; buf.append(c)
        elif c == "`":
            in_tick = True; buf.append(c)
        elif c == ";":
            stmts.append("".join(buf))
            buf = []
        else:
            buf.append(c)
        i += 1
    stmts.append("".join(buf))

    result = []
    for s in stmts:
        # keep only fragments that have executable SQL (not just -- comment lines)
        body = "\n".join(l for l in s.splitlines() if not l.strip().startswith("--")).strip()
        if body:
            result.append(s.strip())
    return result


def _domain_of(path):
    """The domain/package label for a globbed DDL path: the directory name directly UNDER
    canonical-core/ or outcome-packages/. Examples:
      canonical-core/customer/tables/account.sql       -> 'customer'
      canonical-core/customer/relationships.sql        -> 'customer'
      canonical-core/customer/comments.sql             -> 'customer'
      outcome-packages/unified-customer-view/gold/g.sql-> 'unified-customer-view'
    It anchors on the ROOT dir name rather than a fixed parent-of-parent depth, because the
    depth differs: tables/gold/metric-views files sit one level deeper than the flat
    relationships.sql/comments.sql, so a plain parent-of-parent would mislabel the flat ones
    'canonical-core'/'outcome-packages'. Returns None for a path under neither root (the
    bootstrap schemas file), which is therefore never filtered out."""
    parts = os.path.normpath(path).split(os.sep)
    for anchor in ("canonical-core", "outcome-packages"):
        if anchor in parts:
            i = parts.index(anchor)
            if i + 1 < len(parts):
                return parts[i + 1]
    return None


def _package_schema_keys():
    """{schema_key -> package_label} for every outcome package, derived from the ${<key>_schema}
    token each package CREATEs its own objects under (e.g. bmv -> balancing-margin-and-volume,
    predops -> predictive-operations). Used to resolve a cross-package gold dependency
    (`${bmv_schema}` in another package's gold) back to the sibling package that provides it."""
    key_re = re.compile(
        r"CREATE (?:OR REPLACE |OR REFRESH )?(?:MATERIALIZED )?(?:VIEW|TABLE)"
        r"(?: IF NOT EXISTS)?\s+\$\{catalog\}\.\$\{(\w+)_schema\}", re.IGNORECASE)
    out = {}
    for pkg in glob.glob(os.path.join(REPO_ROOT, "outcome-packages", "*")):
        if not os.path.isdir(pkg):
            continue
        label = os.path.basename(pkg)
        txt = ""
        for f in glob.glob(os.path.join(pkg, "tables", "*.sql")) + glob.glob(os.path.join(pkg, "gold", "*.sql")):
            with open(f) as fh:
                txt += fh.read()
        for key in key_re.findall(txt):
            out[key] = label
    return out


def _sibling_package_deps(pkg, key_to_pkg):
    """The set of OTHER outcome-package labels whose gold `pkg` reads. Scans pkg's gold for
    ${<key>_schema} tokens and maps each to the sibling package that owns that key (via
    _package_schema_keys), excluding pkg's own key and core-only keys."""
    ref_re = re.compile(r"\$\{(\w+)_schema\}")
    deps = set()
    for f in glob.glob(os.path.join(REPO_ROOT, "outcome-packages", pkg, "gold", "*.sql")):
        with open(f) as fh:
            found = ref_re.findall(fh.read())
        for key in found:
            sib = key_to_pkg.get(key)
            if sib and sib != pkg:
                deps.add(sib)
    return deps


def _effective_domain_filter(domains):
    """Resolve a `--domains` request into the SET of domain/package labels to apply, or None
    for 'apply everything' (the default -- byte-identical to today's behaviour).

    `domains` may be a comma-separated string (the CLI/widget form; mirrors
    runtime/data-quality/run_checks.py's `domains` -> `filter_set`) or any iterable of labels. Empty
    or None means no filter.

    Dependency closure -- why the set can GROW past what was asked for:
      * outcome packages depend on canonical-core (their gold reads core tables; relationships
        FK to core), so if ANY requested label is an outcome package, ALL canonical-core is
        pulled in (core is the shared foundation, cheap relative to the packages).
      * a package's gold can also read a SIBLING package's gold (e.g. predictive-operations
        reads bmv/equipment/inventory/risk). Left unresolved, a lean `--domains
        predictive-operations` would hit missing sibling deps and hard-fail (M1). So we
        transitively include sibling outcome packages whose ${*_schema} a requested package's
        gold references, resolved via _package_schema_keys. A core-only request stays narrow."""
    if not domains:
        return None
    if isinstance(domains, str):
        filter_set = {d.strip() for d in domains.split(",") if d.strip()}
    else:
        filter_set = {str(d).strip() for d in domains if str(d).strip()}
    if not filter_set:
        return None
    outcome_pkgs = {os.path.basename(p)
                    for p in glob.glob(os.path.join(REPO_ROOT, "outcome-packages", "*"))
                    if os.path.isdir(p)}
    if filter_set & outcome_pkgs:  # any outcome package requested -> core is the safe minimum
        core_domains = {os.path.basename(p)
                        for p in glob.glob(os.path.join(REPO_ROOT, "canonical-core", "*"))
                        if os.path.isdir(p)}
        filter_set = filter_set | core_domains
        # Transitively pull in sibling outcome packages a requested package's gold reads (M1),
        # so a cross-package-gold package deploys under its own --domains instead of failing.
        key_to_pkg = _package_schema_keys()
        pending = filter_set & outcome_pkgs
        while pending:
            pkg = pending.pop()
            for sib in _sibling_package_deps(pkg, key_to_pkg):
                if sib not in filter_set:
                    filter_set.add(sib)
                    pending.add(sib)
    return filter_set


def _phases(catalog, overrides, demote_materialized=False, domains=None, expressions=None):
    """Yield (phase_label, path, [statements]) in dependency order.

    `demote_materialized` (rt06): when set, each gold file's SQL text is rewritten
    (CREATE OR REFRESH MATERIALIZED VIEW -> CREATE OR REPLACE VIEW) BEFORE splitting,
    so the 18 MVs deploy as plain views for the fast gate/demo. Applied to the whole
    file text before `_statements` so the transform sees intact CREATE headers.

    `domains` (design 57 §5d item 4): a comma-separated string (or iterable) of domain/package
    labels for a lean per-PR gate that deploys ONLY the domains a PR changed. When set, only
    DDL whose domain/package label (see _domain_of) is in the effective filter is discovered.
    The schema BOOTSTRAP is ALWAYS yielded (schemas are cheap and everything needs them), and
    any outcome-package request auto-includes all canonical-core (see _effective_domain_filter).
    Default None/empty = no filter = every phase, byte-identical to today. Filtering happens
    HERE at discovery, so apply()'s fixpoint/deferral/parallelism are entirely unchanged -- we
    only narrow WHICH files enter the phases.
    """
    def res(path, transform=None):
        text = resolve(open(path).read(), catalog, overrides, expressions)
        if transform is not None:
            text = transform(text)
        return _statements(text)

    gold_transform = demote_materialized_views if demote_materialized else None

    # A1: objects this run demotes from MV to plain view. comments.sql still carries
    # `ALTER TABLE <mv> SET TAGS (...)` for them, which Databricks rejects against a
    # view -- failing the whole comments unit and silently dropping the tags. Collected
    # from the gold phase (which is yielded BEFORE comments, so the set is complete by
    # the time the comments phase resolves) and applied only to those fqns.
    demoted_fqns = set()

    filter_set = _effective_domain_filter(domains)

    def keep(path):
        # No filter -> keep everything (today's behaviour). Otherwise keep a path whose
        # domain/package label is in the set; a path with no label (the bootstrap file) is
        # always kept -- but bootstrap is yielded unconditionally below regardless.
        if filter_set is None:
            return True
        label = _domain_of(path)
        return label is None or label in filter_set

    yield "schemas", BOOTSTRAP, res(BOOTSTRAP)  # always: schemas are cheap and everything needs them
    for path in sorted(glob.glob(CORE_TABLES)):
        if keep(path):
            yield "core-table", path, res(path)
    for path in sorted(glob.glob(CORE_RELS)):
        if keep(path):
            yield "core-rels", path, res(path)
    for path in sorted(glob.glob(OUTCOME_TABLES)):
        if keep(path):
            yield "outcome-table", path, res(path)
    for path in sorted(glob.glob(OUTCOME_RELS)):
        if keep(path):
            yield "outcome-rels", path, res(path)
    for path in sorted(glob.glob(OUTCOME_GOLD)):
        if keep(path):
            if demote_materialized:
                demoted_fqns.update(
                    materialized_view_fqns(resolve(open(path).read(), catalog, overrides, expressions)))
            yield "outcome-gold", path, res(path, gold_transform)
    for path in sorted(glob.glob(METRIC_VIEWS)):
        if keep(path):
            yield "metric-views", path, res(path)
    comments_transform = (
        (lambda text: retarget_demoted_alter_tags(text, demoted_fqns))
        if demote_materialized else None)
    for pattern in COMMENTS:
        for path in sorted(glob.glob(pattern)):
            if keep(path):
                yield "comments", path, res(path, comments_transform)


def _spark_runner(spark):
    """Executor: run a statement on the job's Spark session (serverless generic)."""
    return lambda stmt: spark.sql(stmt)


def _is_mv_stmt(stmt):
    """True if the statement creates a materialized view. Used for the terminal barrier:
    only an MV create may cross a phase boundary while still PENDING/RUNNING (its async
    refresh pipeline registers out-of-band); every other statement must reach terminal
    SUCCEEDED first (rt09). Matches the EXECUTABLE `CREATE OR REFRESH MATERIALIZED VIEW`
    phrase, NOT a bare 'materialized view' substring: the splitter keeps a file's header
    comment attached to its CREATE, and many PLAIN views' comments mention materialized
    views ("Promote to a materialized view..."), so a substring test would misclassify
    those plain views and wrongly exempt them from the barrier. A demoted MV (rewritten to
    CREATE OR REPLACE VIEW) also correctly no longer matches and is held to the barrier."""
    return is_materialized_view_create(stmt)


def _poll_terminal(w, statement_id, resp, tries=30, delay=2):
    """Poll get_statement until the statement leaves PENDING/RUNNING (rt09 s2): a non-MV
    CREATE that hit the 50s CONTINUE boundary still uncommitted must reach a terminal
    state before the next phase issues an ALTER/constraint/view that references it, else
    that phase races a TABLE_OR_VIEW_NOT_FOUND. Bounded (~tries*delay s); if it never
    terminalizes, run_units_parallel's retry re-submits the (idempotent) statement."""
    if not statement_id:
        return resp
    for _ in range(tries):
        resp = w.statement_execution.get_statement(statement_id)
        state = str(getattr(resp.status, "state", ""))
        if not any(s in state for s in ("PENDING", "RUNNING")):
            return resp
        time.sleep(delay)
    return resp


def _wh_runner(w, warehouse_id, tls=None):
    """Executor: run a statement on a serverless SQL warehouse via the SDK Statement
    Execution API. All DDL routes here when a warehouse id is given: materialized views
    only create cleanly on a SQL warehouse (not on serverless generic compute, where the
    async refresh pipeline registration is unreliable), and DBSQL handles the physical
    DDL too. The SDK path uses the job's ambient OAuth (no token wiring).

    Terminal-SUCCEEDED barrier (rt09 s2/s3): under concurrent submission a statement can
    still be PENDING/RUNNING at the 50s CONTINUE boundary. That is accepted as ok ONLY for
    an MV create (its refresh runs out-of-band). Every OTHER statement is polled to a
    terminal state (_poll_terminal) and must be SUCCEEDED, so a still-PENDING CREATE never
    lets the next phase hit TABLE_OR_VIEW_NOT_FOUND. When `tls` is a threading.local the
    statement_id is stashed there so --profile can join timings to Query History (rt08)."""
    from databricks.sdk.service.sql import ExecuteStatementRequestOnWaitTimeout as _OWT

    def run(stmt):
        resp = w.statement_execution.execute_statement(
            warehouse_id=warehouse_id, statement=stmt,
            wait_timeout="50s", on_wait_timeout=_OWT.CONTINUE)
        if tls is not None:
            tls.statement_id = getattr(resp, "statement_id", None)
        state = str(getattr(resp.status, "state", ""))  # e.g. 'StatementState.SUCCEEDED'
        is_mv = _is_mv_stmt(stmt)
        # Non-MV statements that did not commit inside the wait window are polled to
        # terminal so the phase barrier means "objects exist," not "map returned."
        if not is_mv and any(s in state for s in ("PENDING", "RUNNING")):
            resp = _poll_terminal(w, getattr(resp, "statement_id", None), resp)
            state = str(getattr(resp.status, "state", ""))
        ok = ("SUCCEEDED", "PENDING", "RUNNING") if is_mv else ("SUCCEEDED",)
        if any(s in state for s in ok):
            return
        # A non-MV that is STILL PENDING/RUNNING after polling exhausted has not
        # committed. Raise a message carrying a retryable token ("concurrent update")
        # so run_units_parallel actually re-submits the idempotent statement (M1) —
        # matching this function's documented recovery path (_poll_terminal) rather
        # than hard-failing on a state that is transient, not a real error.
        if any(s in state for s in ("PENDING", "RUNNING")):
            raise RuntimeError(
                f"warehouse statement did not reach terminal state (concurrent update); state: {state}")
        err = getattr(resp.status, "error", None)
        raise RuntimeError(getattr(err, "message", None) or f"warehouse statement state: {state}")
    return run


def _wh_query(w, warehouse_id):
    """A read runner: execute a query on the warehouse and return its result rows as a list of
    lists (each row a list of stringified cell values), or [] on a TABLE/VIEW-not-found error
    (so a DESCRIBE of an absent table reads as "no columns" rather than raising). Used by the
    schema-reconcile DESCRIBE path; separate from _wh_runner, which is fire-and-check for DDL."""
    from databricks.sdk.service.sql import ExecuteStatementRequestOnWaitTimeout as _OWT

    def run_query(sql):
        resp = w.statement_execution.execute_statement(
            warehouse_id=warehouse_id, statement=sql,
            wait_timeout="50s", on_wait_timeout=_OWT.CONTINUE)
        state = str(getattr(resp.status, "state", ""))
        if any(s in state for s in ("PENDING", "RUNNING")):
            resp = _poll_terminal(w, getattr(resp, "statement_id", None), resp)
            state = str(getattr(resp.status, "state", ""))
        if "SUCCEEDED" not in state:
            err = getattr(resp.status, "error", None)
            msg = getattr(err, "message", "") or ""
            if any(t in msg.upper() for t in ("TABLE_OR_VIEW_NOT_FOUND", "NOT_FOUND", "DOES NOT EXIST")):
                return []
            raise RuntimeError(f"query state {state}: {msg}")
        result = getattr(resp, "result", None)
        return list(getattr(result, "data_array", None) or [])
    return run_query


def _pctl(sorted_vals, pct):
    """Nearest-rank percentile of a pre-sorted list (small N, no numpy dependency)."""
    if not sorted_vals:
        return 0.0
    k = int(round((pct / 100.0) * len(sorted_vals) + 0.5)) - 1
    return sorted_vals[max(0, min(len(sorted_vals) - 1, k))]


class _Profiler:
    """Optional per-statement timing (--profile, rt08). Thread-safe: workers append one
    (phase, t_wall, statement_id) row under a lock; the summary (count/total/p50/p95 per
    phase, in phase order) prints on the main thread at the end. On the warehouse path the
    statement_id is captured so the timings can be joined to Query History. Overhead is
    ~zero when --profile is off (the profiled path is simply never bound)."""

    def __init__(self):
        self._lock = threading.Lock()
        self._rows = []  # [(phase, t_wall, statement_id)]
        self._spans = {}  # phase -> [first start, last end] (perf_counter)

    def record(self, phase, t_wall, statement_id=None, t_start=None):
        with self._lock:
            self._rows.append((phase, t_wall, statement_id))
            if t_start is not None:
                span = self._spans.setdefault(phase, [t_start, t_start + t_wall])
                span[0] = min(span[0], t_start)
                span[1] = max(span[1], t_start + t_wall)

    def report(self):
        if not self._rows:
            return
        by_phase = {}
        for phase, t_wall, _sid in self._rows:
            by_phase.setdefault(phase, []).append(t_wall)
        # `total` sums statement time across threads (it OVERCOUNTS under parallelism);
        # `elapsed` is the phase's wall-clock span (first start to last end), the number
        # that actually adds up to the apply duration.
        print("\n[ordm] --profile: per-phase statement timing (seconds)")
        print(f"  {'phase':16} {'count':>6} {'elapsed':>8} {'total':>10} {'p50':>8} {'p95':>8}")
        for phase, times in by_phase.items():  # insertion order = apply order
            times = sorted(times)
            span = self._spans.get(phase)
            elapsed = f"{span[1] - span[0]:8.1f}" if span else f"{'-':>8}"
            print(f"  {phase:16} {len(times):6d} {elapsed} {sum(times):10.2f} "
                  f"{_pctl(times, 50):8.3f} {_pctl(times, 95):8.3f}")
        sids = [sid for _p, _t, sid in self._rows if sid]
        if sids:
            print(f"  captured {len(sids)} statement_id(s) for a Query History join "
                  f"(first: {sids[0]})")


# A stale object left by an EARLIER deploy exists as the WRONG kind for the statement now
# being applied (Databricks: CREATE OR REPLACE VIEW over an existing materialized view/table,
# or ALTER TABLE over a view). On a CI/CD catalog re-deployed with --demote-materialized this
# is expected (the previous run created real MVs; demote now wants plain views), so drop the
# stale object and re-run. Gated on --demote-materialized only: a serving/prod deploy stays
# strict and must never silently drop a real object.
_KIND_MISMATCH = ("expect_view_not_table", "expect_table_not_view")
_OBJ_FQN_RE = re.compile(
    r"(?:CREATE\s+OR\s+REFRESH\s+MATERIALIZED\s+VIEW|CREATE\s+OR\s+REPLACE\s+VIEW|"
    r"CREATE\s+MATERIALIZED\s+VIEW|CREATE\s+VIEW|CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?|"
    r"ALTER\s+TABLE)\s+([`\w.]+)", re.IGNORECASE)
# True when a statement's FIRST executable keyword is CREATE, tolerating the leading `--`
# header comment / `/* */` block that _statements keeps attached to every fragment. A bare
# re.match(r"\s*CREATE") would fail on that `--` prefix (every committed DDL file has one),
# leaving the kind-mismatch self-heal inert on real input; this skips leading comment lines
# first, mirroring how is_materialized_view_create searches rather than anchors. It must NOT
# match a header'd ALTER (dropping + re-running an ALTER just loses the object).
_LEADING_CREATE_RE = re.compile(
    r"\A(?:\s*(?:--[^\n]*\n|/\*.*?\*/\s*))*\s*CREATE\b", re.IGNORECASE | re.DOTALL)


def _object_fqn(stmt):
    """The fully-qualified object name a CREATE/ALTER statement targets, or None."""
    m = _OBJ_FQN_RE.search(stmt)
    return m.group(1) if m else None


# --- materialized-view refresh (serving deploy; AI review #108 H1, Approach B) --------------
# The daily SERVING deploy creates the gold MVs during apply_ddl BEFORE generate_all loads
# data, and (unlike the demo job) does NOT --demote-materialized, so the MVs materialize
# EMPTY and never recompute. This mode re-runs REFRESH MATERIALIZED VIEW after the data
# loads, in dependency order (a child MV that reads another MV must refresh AFTER its parent),
# so a serving deploy ends with correctly-populated MVs. Read-only structurally: it issues
# only REFRESH, never CREATE/ALTER/DROP. Comments/strings are stripped before edge detection
# so a "materialized view" mention in prose never creates a phantom dependency.
_MV_NAME_RE = re.compile(
    r"CREATE\s+OR\s+REFRESH\s+MATERIALIZED\s+VIEW\s+([`\w.${}]+)", re.IGNORECASE)


def _strip_sql_noise(text):
    """Drop line/block comments and single-quoted string literals so edge detection sees
    only executable SQL (a comment that says 'materialized view ...' is not a dependency)."""
    text = re.sub(r"--[^\n]*", " ", text)
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    text = re.sub(r"'(?:''|[^'])*'", " ", text)
    return text


def _materialized_view_refresh_waves(catalog, overrides):
    """Return the gold materialized views grouped into dependency WAVES (Kahn LEVELS): a list
    of lists of resolved `catalog.schema.name`, where every MV in wave K depends only on MVs in
    waves < K. MVs within one wave are mutually independent, so they can refresh CONCURRENTLY;
    waves run in order so a child never refreshes before its parents. Ties inside a wave break
    by name for determinism. Raises on a cycle (verified acyclic in tests).

    Parsed from the committed gold SQL. The NAME is matched on noise-stripped text so a plain
    view whose COMMENT mentions "CREATE OR REFRESH MATERIALIZED VIEW ... for serving latency"
    (e.g. gold_unified_customer_360_current) is not mistaken for an MV named "for"."""
    mv_reads, short_to_fqn = {}, {}
    for path in sorted(glob.glob(OUTCOME_GOLD)):
        raw = open(path).read()
        clean = _strip_sql_noise(raw)
        m = _MV_NAME_RE.search(clean)
        if not m:
            continue
        fqn = resolve(m.group(1), catalog, overrides)  # ${catalog}.${*_schema}.name -> concrete
        short = fqn.split(".")[-1]
        short_to_fqn[short] = fqn
        mv_reads[short] = raw  # keep body; edges computed once we know all MV short names
    all_names = set(mv_reads)
    edges = {}
    for short, raw in mv_reads.items():
        body = _strip_sql_noise(raw)
        reads = set()
        for ref in re.findall(r"(?:FROM|JOIN)\s+[`\w.${}]*?\.([a-zA-Z_][\w]*)", body):
            if ref in all_names and ref != short:
                reads.add(ref)
        edges[short] = reads
    # Kahn by LEVEL: each iteration emits ALL currently-ready nodes as one wave (deterministic,
    # name-sorted), then marks them done. Independent MVs land in the same wave.
    waves, done = [], set()
    while len(done) < len(all_names):
        ready = sorted(n for n in all_names if n not in done and not (edges[n] - done))
        if not ready:
            raise ValueError(
                f"cyclic materialized-view dependency among: {sorted(all_names - done)}")
        waves.append([short_to_fqn[n] for n in ready])
        done.update(ready)
    return waves


def _materialized_view_refresh_order(catalog, overrides):
    """The gold MVs as a FLAT list in dependency order (parents before children) -- the waves
    concatenated. Retained for callers/tests that only need the linear order; the parallel
    refresh driver uses _materialized_view_refresh_waves directly."""
    return [fqn for wave in _materialized_view_refresh_waves(catalog, overrides) for fqn in wave]


def refresh_materialized_views(run, catalog, overrides, max_workers=16):
    """Issue REFRESH MATERIALIZED VIEW for every gold MV, WAVE BY WAVE (parents-first). Within a
    wave the MVs are mutually independent and refresh CONCURRENTLY (up to max_workers); each wave
    is a barrier so a child never refreshes before its parents. `run` is a statement executor
    (the warehouse or Spark runner). Returns (refreshed, failures). Serving deploy only.

    Parallelizing within a wave is the daily job's biggest remaining win: MV refresh recomputes
    against real data and dominated the deploy (~10 min serial). A REFRESH of independent MVs has
    no ordering constraint, so it maps cleanly onto run_units_parallel (one MV = one single-stmt
    unit). If ANY wave has a failure, later waves are SKIPPED -- refreshing a child against a
    parent that failed to refresh would compute on stale data."""
    waves = _materialized_view_refresh_waves(catalog, overrides)
    total = sum(len(w) for w in waves)
    print(f"[ordm] refreshing {total} materialized view(s) in {len(waves)} dependency wave(s), "
          f"up to {max_workers} concurrent per wave")
    refreshed, failures = 0, []
    for wi, wave in enumerate(waves):
        units = [(fqn, [f"REFRESH MATERIALIZED VIEW {fqn}"]) for fqn in wave]
        exec_one = lambda s: _exec(run, s)  # noqa: E731
        applied, _skipped, wave_failures = run_units_parallel(
            units, exec_one, max_workers=max_workers)
        refreshed += applied
        for f in wave_failures:
            failures.append(f)
            print(f"  FAILED (wave {wi}): {f}")
        print(f"  wave {wi}: refreshed {applied}/{len(wave)} MV(s)")
        if wave_failures:
            remaining = sum(len(w) for w in waves[wi + 1:])
            if remaining:
                print(f"  [ordm] SKIPPING {remaining} downstream MV(s): a parent wave failed, so "
                      f"a child refresh would compute on stale data")
            break
    return refreshed, failures


# --- physical gold-table refresh (post-generate correctness) -----------------------------
# Most gold objects are views (or MVs refreshed below), but Promote with Purpose has two
# deliberately physical snapshot tables so their documented grain can carry a UC primary key.
# Their CREATE + INSERT OVERWRITE files run during apply_ddl, before generate_all replaces the
# base tables. Without a second, load-only pass after generation, DQ reads the prior run's gold
# snapshot even though the current run's base data is correct.
_INSERT_OVERWRITE_RE = re.compile(r"\A\s*INSERT\s+OVERWRITE\b", re.IGNORECASE)


def _gold_table_load_units(catalog, overrides, domains=None, expressions=None):
    """Return per-file INSERT OVERWRITE units for physical gold snapshot tables.

    CREATE/ALTER/COMMENT statements are intentionally excluded: the ordinary apply phase has
    already created and documented the targets. This post-data mode only rematerializes their
    rows from the freshly generated base tables. Domain filtering matches the ordinary deploy.
    """
    filter_set = _effective_domain_filter(domains)
    units = []
    for path in sorted(glob.glob(OUTCOME_GOLD)):
        if filter_set is not None and _domain_of(path) not in filter_set:
            continue
        with open(path) as fh:
            resolved = resolve(fh.read(), catalog, overrides, expressions)
        loads = [
            stmt for stmt in _statements(resolved)
            if _INSERT_OVERWRITE_RE.match(_strip_sql_noise(stmt))
        ]
        if loads:
            units.append((os.path.relpath(path, REPO_ROOT), loads))
    return units


def refresh_gold_tables(run, catalog, overrides, domains=None, expressions=None, max_workers=16):
    """Reload physical gold snapshot tables after generate_all and before DQ."""
    units = _gold_table_load_units(catalog, overrides, domains, expressions)
    print(f"[ordm] refreshing {len(units)} physical gold table load(s) after generation")
    applied, _skipped, failures = run_units_parallel(
        units,
        lambda stmt: _exec(run, stmt),
        max_workers=max_workers,
    )
    return applied, failures


# --- materialized-view DEFINITION reconcile (serving deploy; AI review #108 M2) --------------
# Gold MVs are CREATE OR REFRESH MATERIALIZED VIEW, applied IF-NOT-EXISTS-style, so a re-deploy
# of an MV whose SELECT BODY changed keeps the STALE definition (refresh only recomputes DATA
# against the old body). Unlike plain views (CREATE OR REPLACE, self-healing), an MV needs an
# explicit DROP to pick up a new definition. This reconcile diffs the committed body vs the live
# view_definition and DROPs (only) the drifted MVs, so the apply_ddl step that follows recreates
# them with the new body (and refresh_materialized_views repopulates). Drop-only, same shape as
# the table reconcile. Empirically (all 18 committed MVs) this is FALSE-POSITIVE-FREE: after the
# normalization below, every UNCHANGED MV compares equal, so an unchanged MV is never recreated.
_TRAILING_CLUSTER_BY_ANY = re.compile(r"\s*CLUSTER\s+BY\s*\([^)]*\)\s*;?\s*$", re.IGNORECASE)


def _normalize_view_body(sql):
    """Canonicalize a view/MV SELECT body for definition-drift comparison, returning a stable
    string. Robust to the COSMETIC differences between a committed body and the engine's stored
    view_definition (measured on the reference workspace): the engine keeps the MV's trailing CLUSTER BY (physical
    layout, not semantics) and strips comments, and formats/qualifies differently. We therefore:
      * strip a trailing CLUSTER BY (...) on both sides (layout, changed via ALTER not a rebuild);
      * parse with sqlglot (databricks) and drop all comments;
      * normalize identifier casing; re-emit canonically.
    A comment-only or whitespace/case-only change normalizes EQUAL (no needless recreate); an
    added/removed column, changed filter, or changed expression normalizes DIFFERENT. If the body
    cannot be parsed, return a sentinel unique to the raw text so a parse-failure is treated as
    "changed" (self-heal by recreating) rather than silently skipped."""
    import sqlglot
    from sqlglot.optimizer.normalize_identifiers import normalize_identifiers
    text = _TRAILING_CLUSTER_BY_ANY.sub("", (sql or "").strip())
    try:
        tree = sqlglot.parse_one(text, read="databricks")
        for node in tree.walk():
            node.comments = None
        tree = normalize_identifiers(tree, dialect="databricks")
        return tree.sql(dialect="databricks")
    except Exception:  # noqa: BLE001 -- unparseable -> unique sentinel so it counts as drifted
        return "\x00UNPARSEABLE\x00" + re.sub(r"\s+", " ", text).strip()


def _mv_definition_drifted(committed_body, live_definition):
    """True if the committed MV SELECT body differs (semantically) from the live view_definition,
    per _normalize_view_body. A live_definition of None/"" (MV absent) is treated as drift so a
    missing MV is (re)created. Pure -- no I/O -- so it is exhaustively unit-tested."""
    if not live_definition:
        return True
    return _normalize_view_body(committed_body) != _normalize_view_body(live_definition)


def _committed_materialized_views(catalog, overrides, domains=None):
    """Yield (fqn, committed_select_body) for every committed gold MV, resolved to concrete names.
    Name matched on noise-stripped text (like _materialized_view_refresh_waves) so a plain view
    whose COMMENT mentions 'materialized view' is not mistaken for one. The body is
    view_select_body(resolved) -- the SELECT with the trailing CLUSTER BY already stripped.
    Honors --domains (same as _committed_tables), so an MV reconcile scoped to a domain subset
    only touches that subset's MVs (AI review #108 m2 -- harmless today since the only caller,
    the daily full deploy, passes no --domains, but keeps the two reconcile paths consistent)."""
    filter_set = _effective_domain_filter(domains)
    for path in sorted(glob.glob(OUTCOME_GOLD)):
        if filter_set is not None:
            label = _domain_of(path)
            if not (label is None or label in filter_set):
                continue
        raw = open(path).read()
        m = _MV_NAME_RE.search(_strip_sql_noise(raw))
        if not m:
            continue
        resolved = resolve(raw, catalog, overrides)
        fqn = resolve(m.group(1), catalog, overrides)
        try:
            body = view_select_body(resolved)
        except ValueError as e:
            # An MV whose SELECT body can't be extracted is left OUT of the definition-drift set,
            # so a changed definition there would go undetected. All committed MVs parse today;
            # surface any skip LOUDLY so a future regression is visible, not silent (AI review m2).
            print(f"[ordm] WARNING: reconcile-materialized SKIPPING {fqn} "
                  f"(could not extract its SELECT body: {e}) -- its definition drift is NOT checked")
            continue
        yield fqn, body


def _live_view_definition(run_query, fqn):
    """Read a live view/MV's stored SELECT definition from information_schema.views, or "" if it
    does not exist. `run_query(sql)` returns result rows (each a list); [] -> absent."""
    catalog, schema, name = fqn.split(".")[-3], fqn.split(".")[-2], fqn.split(".")[-1]
    rows = run_query(
        f"SELECT view_definition FROM {catalog}.information_schema.views "
        f"WHERE table_schema = '{schema}' AND table_name = '{name}'")
    if not rows:
        return ""
    first = rows[0]
    return (first[0] if first else "") or ""


def reconcile_materialized_views(run, run_query, catalog, overrides, domains=None):
    """--reconcile_materialized driver (serving deploy; AI review #108 M2): DROP (only) the gold
    MVs whose live definition drifted from the committed SELECT body, so the apply_ddl step that
    runs AFTER recreates them with the new body (CREATE OR REFRESH MATERIALIZED VIEW) and
    refresh_materialized_views repopulates. `run` executes the DROP; `run_query` reads
    information_schema.views. DROP-ONLY (mirrors the table reconcile): unchanged MVs are left live
    (no availability gap; they only REFRESH). Honors --domains for parity with the table reconcile.
    Returns (dropped, unchanged, failures)."""
    committed = list(_committed_materialized_views(catalog, overrides, domains))
    to_drop, unchanged = [], []
    for fqn, body in committed:
        if _mv_definition_drifted(body, _live_view_definition(run_query, fqn)):
            to_drop.append(fqn)
        else:
            unchanged.append(fqn)
    print(f"[ordm] reconcile-materialized (drop-only; apply recreates after): {len(committed)} MV(s); "
          f"{len(to_drop)} definition-drifted (drop), {len(unchanged)} unchanged")
    dropped, failures = 0, []
    for fqn in to_drop:
        # DROP VIEW works for a materialized view too; IF EXISTS so a not-yet-created MV no-ops.
        res = _exec(run, f"DROP MATERIALIZED VIEW IF EXISTS {fqn}")
        if res == "ok":
            dropped += 1
            print(f"  dropped {fqn} (apply will recreate with the new definition)")
        else:
            failures.append(f"{fqn} (drop): {res}")
    return dropped, len(unchanged), failures


# --- schema reconcile + full recreate (serving deploy; AI review #108 H1 table-drift) --------
# Tables use CREATE TABLE IF NOT EXISTS, so a table whose committed DDL changed keeps its OLD
# structure on a re-deploy (silent schema drift). Two opt-in modes fix this, both DATA-SAFE on
# the daily serving path because generate_all re-materializes every table after apply:
#   --reconcile_schema : DESCRIBE each live table, diff columns vs the committed CREATE, and
#                        DROP+recreate ONLY the tables that actually changed (unchanged tables
#                        stay live -> no availability gap). This is the daily default.
#   --recreate         : full nuke -- DROP every managed table then recreate. NOT auto-called;
#                        for an admin clean-reinstall only.
# The diff logic is split into pure, warehouse-free helpers so it is thoroughly unit-testable.

# SQL type aliases that mean the same physical type; normalize so a cosmetic spelling
# difference (INT vs INTEGER, DEC vs DECIMAL) never triggers a spurious recreate. Databricks
# DESCRIBE reports the canonical (right-hand) spelling; committed DDL may use either.
_SQL_TYPE_ALIASES = {
    "INT": "INTEGER", "INTEGER": "INTEGER",
    "LONG": "BIGINT", "BIGINT": "BIGINT",
    "SHORT": "SMALLINT", "SMALLINT": "SMALLINT",
    "BYTE": "TINYINT", "TINYINT": "TINYINT",
    "DEC": "DECIMAL", "NUMERIC": "DECIMAL", "DECIMAL": "DECIMAL",
    "REAL": "FLOAT", "FLOAT": "FLOAT", "DOUBLE": "DOUBLE",
    "BOOL": "BOOLEAN", "BOOLEAN": "BOOLEAN",
    "STRING": "STRING", "TEXT": "STRING",
    "TIMESTAMP": "TIMESTAMP", "TIMESTAMP_NTZ": "TIMESTAMP_NTZ", "DATE": "DATE",
}


def _normalize_sql_type(t):
    """Canonicalize a SQL type for drift comparison: strip whitespace, upper-case, map aliases.
    Parameterized types keep their args (DECIMAL(18,2) stays DECIMAL(18,2)); the base word is
    alias-normalized (DEC(18,2) -> DECIMAL(18,2)). Complex types are normalized RECURSIVELY, so
    the same aliasing applies to inner types too (ARRAY<INT> == ARRAY<INTEGER>,
    MAP<STRING,DEC(9,2)> == MAP<STRING,DECIMAL(9,2)>) -- otherwise a nested INT/INTEGER rename
    would be a false-positive drift (AI review #108 m3). A STRUCT<...>'s field types are
    normalized while field names are preserved. Today no committed table uses a complex type, so
    this is future-proofing; the worst case either way is a harmless extra drop+recreate."""
    if t is None:
        return ""
    s = re.sub(r"\s+", "", str(t)).upper()
    m = re.match(r"([A-Z_]+)(\(.*\)|<.*>)?$", s)
    if not m:
        return s
    base, arg = m.group(1), (m.group(2) or "")
    base = _SQL_TYPE_ALIASES.get(base, base)
    # Recurse into the angle-bracket args of a complex type so inner aliases normalize too.
    # Parenthesized args (DECIMAL(18,2)) are numeric literals, not types -> left verbatim.
    if arg.startswith("<") and arg.endswith(">"):
        inner = ",".join(_normalize_struct_field(p) for p in _split_type_args(arg[1:-1]))
        return f"{base}<{inner}>"
    return base + arg


def _split_type_args(s):
    """Split a complex-type arg list on TOP-LEVEL commas only (depth 0), so nested
    ARRAY<...>/STRUCT<...>/MAP<...> and DECIMAL(p,s) commas stay inside their own group."""
    parts, depth, start = [], 0, 0
    for i, ch in enumerate(s):
        if ch in "<(":
            depth += 1
        elif ch in ">)":
            depth -= 1
        elif ch == "," and depth == 0:
            parts.append(s[start:i])
            start = i + 1
    parts.append(s[start:])
    return [p for p in parts if p != ""]


def _normalize_struct_field(part):
    """Normalize one complex-type arg. A STRUCT field is `NAME:TYPE` -> keep NAME, normalize
    TYPE; anything else (an ARRAY element type, a MAP key/value type) is a bare type -> normalize
    the whole thing. Splits the field name on the FIRST top-level colon only."""
    depth = 0
    for i, ch in enumerate(part):
        if ch in "<(":
            depth += 1
        elif ch in ">)":
            depth -= 1
        elif ch == ":" and depth == 0:
            return f"{part[:i]}:{_normalize_sql_type(part[i + 1:])}"
    return _normalize_sql_type(part)


def _columns_differ(committed, live):
    """Pure comparator. `committed` is [{name, sql_type, ...}] from parse_columns; `live` is
    [{name, sql_type}] read from DESCRIBE. Returns True if the column SET or any column's
    normalized TYPE differs (added, dropped, renamed, or retyped). Order and comments are
    ignored (a reorder/comment-only change is not a structural drift). NULLABILITY is ignored:
    Databricks DESCRIBE does not reliably report it and a NOT NULL change alone does not require
    a table rebuild here (data is regenerated). A live read of [] (table absent) is treated as a
    difference so a missing table is (re)created."""
    if not live:
        return True
    cmap = {c["name"].lower(): _normalize_sql_type(c.get("sql_type")) for c in committed}
    lmap = {c["name"].lower(): _normalize_sql_type(c.get("sql_type")) for c in live}
    return cmap != lmap


def _committed_tables(catalog, overrides, domains=None):
    """Yield (fqn, columns, create_sql) for every COMMITTED managed TABLE (canonical-core +
    outcome-package tables/), resolved to concrete names. `columns` is parse_columns output;
    `create_sql` is the resolved CREATE statement to re-run on a recreate. Honors --domains."""
    from tools.ordm_ddl.parser import parse_table_sql
    filter_set = _effective_domain_filter(domains)
    for glob_pat in (CORE_TABLES, OUTCOME_TABLES):
        for path in sorted(glob.glob(glob_pat)):
            if filter_set is not None:
                label = _domain_of(path)
                if not (label is None or label in filter_set):
                    continue
            raw = open(path).read()
            parsed = parse_table_sql(raw)
            if not parsed or parsed.get("kind") != "table":
                continue
            resolved = resolve(raw, catalog, overrides)
            stmts = _statements(resolved)
            create = next((s for s in stmts if _LEADING_CREATE_RE.search(s)
                           and "CREATE TABLE" in s.upper()), None)
            fqn = _object_fqn(create) if create else None
            if fqn:
                yield fqn, parsed["columns"], create


def _reconcile_table_plan(committed_tables, live_columns_of):
    """Pure planner. `committed_tables` is an iterable of (fqn, columns, create_sql);
    `live_columns_of(fqn)` returns the live [{name, sql_type}] (or [] if the table is absent).
    Returns (to_recreate, unchanged): to_recreate is the list of (fqn, create_sql) whose live
    schema differs from committed (or is absent); unchanged is the list of fqns that match.
    No I/O, no warehouse -- this is the unit-tested core of --reconcile_schema."""
    to_recreate, unchanged = [], []
    for fqn, cols, create_sql in committed_tables:
        if _columns_differ(cols, live_columns_of(fqn)):
            to_recreate.append((fqn, create_sql))
        else:
            unchanged.append(fqn)
    return to_recreate, unchanged


def _describe_columns(run_query, fqn):
    """Read a live table's columns via DESCRIBE, returning [{name, sql_type}] (empty if the
    table does not exist). `run_query(sql)` returns a list of result rows (each a list); the
    driver adapts the SDK statement-execution result to that shape. DESCRIBE TABLE output rows
    are [col_name, data_type, comment]; metadata sections start with a blank/`#` col_name, so
    we stop at the first such row."""
    rows = run_query(f"DESCRIBE TABLE {fqn}")
    cols = []
    for r in rows or []:
        name = (r[0] if r else "") or ""
        if not name.strip() or name.startswith("#"):
            break                       # partition-info / detail section begins
        dtype = r[1] if len(r) > 1 else ""
        cols.append({"name": name, "sql_type": dtype})
    return cols


def reconcile_schema(run, run_query, catalog, overrides, domains=None):
    """--reconcile_schema driver: DROP (only) the managed tables whose live schema drifted from
    committed, so the apply_ddl step that runs AFTER this recreates them cleanly. `run` executes
    the DROP; `run_query` reads DESCRIBE rows.

    CRITICAL (AI review #108 H1): this is DROP-ONLY. It must NOT recreate the table from the bare
    CREATE statement, because ORDM tables carry SET TAGS (dbx_data_type / PII) and cross-table FKs
    (relationships.sql) as SEPARATE statements that a CREATE-only recreate would silently lose.
    Instead the daily job orders reconcile_schema BEFORE apply_ddl, so the full phased apply
    (CREATE TABLE IF NOT EXISTS + SET TAGS + relationships + comments) rebuilds the dropped table
    WITH its tags/FKs/comments. Data is refilled by generate_all. Unchanged tables are left live
    (apply's IF NOT EXISTS no-ops them). Returns (dropped, unchanged, failures)."""
    committed = list(_committed_tables(catalog, overrides, domains))
    to_recreate, unchanged = _reconcile_table_plan(
        committed, lambda fqn: _describe_columns(run_query, fqn))
    print(f"[ordm] reconcile-schema (drop-only; apply recreates after): {len(committed)} managed "
          f"table(s); {len(to_recreate)} drifted (drop), {len(unchanged)} unchanged")
    dropped, failures = 0, []
    for fqn, _create_sql in to_recreate:
        res = _exec(run, f"DROP TABLE IF EXISTS {fqn}")
        if res == "ok":
            dropped += 1
            print(f"  dropped {fqn} (apply will recreate with tags + FKs)")
        else:
            failures.append(f"{fqn} (drop): {res}")
    return dropped, len(unchanged), failures


def recreate_all(run, catalog, overrides, domains=None):
    """--recreate driver (admin clean-reinstall; NEVER auto-called): DROP (only) every managed
    table so a following full apply recreates them from scratch. Like reconcile_schema this is
    DROP-ONLY for the same reason (a CREATE-only recreate would drop SET TAGS + FKs, AI review
    #108 H1); the caller MUST run a normal apply afterwards to recreate tables with their tags,
    relationships, and comments, then generate_all to refill data. Returns (dropped, failures)."""
    committed = list(_committed_tables(catalog, overrides, domains))
    print(f"[ordm] recreate (full nuke, drop-only; run a full apply after): "
          f"{len(committed)} managed table(s)")
    dropped, failures = 0, []
    for fqn, _cols, _create in committed:
        res = _exec(run, f"DROP TABLE IF EXISTS {fqn}")
        if res == "ok":
            dropped += 1
        else:
            failures.append(f"{fqn} (drop): {res}")
    print(f"[ordm] recreate: dropped {dropped}, {len(failures)} failed. Run a full apply next.")
    return dropped, failures


# COMMENT ON COLUMN <catalog>.<schema>.<table>.<column> IS '...' — capture the TABLE
# (drop the trailing .column). Before plain gold views took their comments inline, comments
# were the dominant apply phase, batched ~55/file into only 9 files, so per-file fan-out gave ~9 lanes and the phase was floored
# by the largest file (~113 serial statements). Regrouping by TARGET TABLE lifts that to
# ~50 lanes (one per commented table) while keeping a single table's comments SERIAL in one
# unit -- mandatory, because concurrent metadata commits to the SAME table race and a
# COMMENT can be silently lost (measured on the reference workspace). Floor drops to the biggest per-table
# chain (~38), not the biggest per-file (~113).
# The object token includes ${...} chars when a comment is still unresolved (the applier
# resolves before this runs, but be robust to both forms so grouping never silently no-ops).
_COMMENT_COL_RE = re.compile(r"COMMENT\s+ON\s+COLUMN\s+([`\w.${}]+)", re.IGNORECASE)
# COMMENT ON TABLE <fqn> targets the TABLE itself (a 3-part name, used as-is). It MUST be
# grouped with that table's column comments (H1): a table comment and a column comment both
# metadata-commit the same table, so if the table comment landed in a concurrent per-file
# fallback unit while the column comments were in the per-table unit, the two units could
# commit the same table concurrently and one comment would be silently lost (the exact race
# per-table grouping exists to prevent).
_COMMENT_TBL_RE = re.compile(r"COMMENT\s+ON\s+TABLE\s+([`\w.${}]+)", re.IGNORECASE)


def _comment_target_table(stmt):
    """The fully-qualified TABLE a COMMENT statement targets, so all comments on one table
    group into a single serial unit. For COMMENT ON COLUMN it is the 4-part column name
    minus the trailing .column (-> 3-part table); for COMMENT ON TABLE it is the target name
    as-is. Returns None if the statement is neither (kept as a per-file fallback)."""
    m = _COMMENT_COL_RE.search(stmt)
    if m:
        parts = m.group(1).split(".")
        return ".".join(parts[:-1]) if len(parts) >= 2 else None
    m = _COMMENT_TBL_RE.search(stmt)
    if m:
        return m.group(1)
    return None


def _regroup_comments_by_table(comment_units):
    """Re-split per-FILE comment units into per-TARGET-TABLE units so the comments phase
    fans out per table (~50 lanes) instead of per file (~9). Same-table statements stay
    together in one unit (applied serially by run_units_parallel), preserving the required
    per-table commit serialization. Statement order within a table is preserved. Any
    statement without a recognizable column target (should be none in comments.sql) falls
    back to a per-file unit so nothing is dropped."""
    by_table = {}          # fq_table -> [statements]  (insertion order preserved)
    order = []             # keys in first-seen order for deterministic output
    fallback = []          # (rel, [statements]) for anything not a column comment
    for rel, statements in comment_units:
        leftovers = []
        for stmt in statements:
            tbl = _comment_target_table(stmt)
            if tbl is None:
                leftovers.append(stmt)
                continue
            if tbl not in by_table:
                by_table[tbl] = []
                order.append(tbl)
            by_table[tbl].append(stmt)
        if leftovers:
            fallback.append((rel, leftovers))
    units = [(tbl, by_table[tbl]) for tbl in order]
    units.extend(fallback)
    return units


# A plain view CREATE with no explicit column list (the only shape eligible for inlining),
# and a single-column COMMENT statement with its literal.
_PLAIN_VIEW_RE = re.compile(r"\s*CREATE\s+OR\s+REPLACE\s+VIEW\s+([`\w.]+)\s+AS\b", re.IGNORECASE)
_COMMENT_COL_FULL_RE = re.compile(
    r"\s*COMMENT\s+ON\s+COLUMN\s+([`\w.]+)\.([`\w]+)\s+IS\s+('(?:[^']|'')*')\s*;?\s*$",
    re.IGNORECASE | re.DOTALL)
# Errors that mean the inlined column list itself was wrong: fall back to the original CREATE
# plus separate COMMENT statements. Body errors (UNRESOLVED_COLUMN, AMBIGUOUS_REFERENCE, e.g. an
# upstream view not yet updated) are NOT here: they go straight to the gold fixpoint's retry,
# since the original CREATE would fail the same way.
_INLINE_FALLBACK_TOKENS = ("column_arity_mismatch", "create_view_column", "column_already_exists")


_LEADING_LINE_COMMENTS_RE = re.compile(r"\A(?:\s*--[^\n]*\n)*\s*")


def _body_offset(stmt):
    """Offset of the first SQL token after any leading blank / `--` comment lines (statements
    keep the file header that preceded them)."""
    return _LEADING_LINE_COMMENTS_RE.match(stmt).end()


def _view_output_columns(stmt):
    """Final projection names of a view CREATE, in order, or None when they cannot be known
    exactly (parse failure, a star in the final projection, or a projection that is neither an
    explicit alias nor a plain column). Exactness matters: an inlined column list renames the
    view's outputs BY POSITION, so every name must be the one the warehouse would assign. sqlglot
    guesses a name for some unaliased expressions (`CAST(x AS INT)` -> `x`) that the warehouse
    may not use, which would silently rename the column."""
    import sqlglot
    from sqlglot import exp
    from sqlglot.errors import SqlglotError

    try:
        tree = sqlglot.parse_one(stmt, dialect="databricks")
    except (SqlglotError, ValueError):
        return None
    query = tree.expression if isinstance(tree, exp.Create) else tree
    if query is None or not hasattr(query, "named_selects"):
        return None
    selects = query.selects if hasattr(query, "selects") else []
    if not selects or any(isinstance(e, exp.Star) or (isinstance(e, exp.Column) and e.is_star)
                          for e in selects):
        return None
    if not all(isinstance(e, (exp.Alias, exp.Column)) for e in selects):
        return None
    names = list(query.named_selects)
    if not names or len(names) != len(selects) or len(set(n.lower() for n in names)) != len(names):
        return None
    return names


def _inline_view_comments(gold, comment_units):
    """Fold each plain gold view's COMMENT ON COLUMN statements into its CREATE as a column
    list (`CREATE OR REPLACE VIEW v (c1 COMMENT '...', c2, ...) AS ...`), so the comments
    ride on the CREATE instead of costing one serial warehouse round-trip each. Comments
    were the largest apply phase (one statement per gold column), and a CREATE OR REPLACE
    VIEW resets column comments anyway, so they are always re-applied on every deploy.

    Only views whose exact output columns are known (_view_output_columns) and whose every
    commented column is among them are rewritten; everything else is untouched. Returns
    (gold, comment_units, fallback) where fallback maps each rewritten statement to
    (original statement, [its comment statements]) for _inline_fallback_runner.

    Note: with --demote-materialized (the lean per-PR gate) materialized views become plain
    views and take this inline path; in the daily deploy they stay materialized views and keep
    the separate COMMENT ON COLUMN path. A lean-vs-daily difference in MV column comments
    starts here. The rewrite is skipped under --dry_run, so a dry run prints the original
    statement shape, not what a real apply executes."""
    by_view = {}  # view fqn (lower) -> [(column, literal, statement)]
    for _rel, statements in comment_units:
        for stmt in statements:
            m = _COMMENT_COL_FULL_RE.match(stmt, _body_offset(stmt))
            if m:
                by_view.setdefault(m.group(1).replace("`", "").lower(), []).append(
                    (m.group(2).replace("`", ""), m.group(3), stmt))
    new_gold, fallback, inlined = [], {}, set()
    for rel, stmt in gold:
        m = _PLAIN_VIEW_RE.match(stmt, _body_offset(stmt))
        entries = by_view.get(m.group(1).replace("`", "").lower()) if m else None
        cols = _view_output_columns(stmt) if entries else None
        if not cols:
            new_gold.append((rel, stmt))
            continue
        lit = {}
        for col, literal, _s in entries:
            lit[col.lower()] = literal
        if not set(lit) <= {c.lower() for c in cols}:
            new_gold.append((rel, stmt))  # a comment names a column the view does not output
            continue
        if any("''" in v for v in lit.values()):
            new_gold.append((rel, stmt))  # quote-escaped literals: keep the proven COMMENT path
            continue
        col_list = ",\n  ".join(
            f"`{c}` COMMENT {lit[c.lower()]}" if c.lower() in lit else f"`{c}`" for c in cols)
        rewritten = stmt[:m.end(1)] + f" (\n  {col_list}\n)" + stmt[m.end(1):]
        if _view_output_columns(rewritten) is None:
            new_gold.append((rel, stmt))  # rewrite does not round-trip the parser: leave as is
            continue
        fallback[rewritten] = (stmt, [s for _c, _l, s in entries])
        inlined.update(s for _c, _l, s in entries)
        new_gold.append((rel, rewritten))
    remaining = []
    for rel, statements in comment_units:
        keep = [s for s in statements if s not in inlined]
        if keep:
            remaining.append((rel, keep))
    return new_gold, remaining, fallback


def _inline_fallback_runner(run, fallback, comment_failures=None):
    """Wrap `run` so a rewritten (comment-inlined) view CREATE that fails because of its
    column list re-runs as the ORIGINAL CREATE followed by its separate COMMENT statements.
    Any other error (e.g. a not-yet-created dependency) propagates unchanged so the gold
    fixpoint retries the statement in a later pass. Once the original CREATE succeeds the view
    exists, so a failing COMMENT is appended to `comment_failures` (reported as a comment
    failure) rather than raised: raising would make the fixpoint re-run the whole fallback
    on every pass and file the failure against the gold view."""
    if not fallback:
        return run

    def wrapped(stmt):
        entry = fallback.get(stmt)
        if entry is None:
            return run(stmt)
        try:
            return run(stmt)
        except Exception as exc:  # noqa: BLE001
            if not any(tok in str(exc).lower() for tok in _INLINE_FALLBACK_TOKENS):
                raise
            original, comments = entry
            print(f"[ordm] CREATE with inline column comments failed for {_object_fqn(original)}; "
                  f"retrying without them (original CREATE + {len(comments)} COMMENT statement(s)). "
                  f"If the retry fails the same way, the error is in the view body, not the comments: "
                  f"{str(exc)[:160]}")
            run(original)
            for c in comments:
                try:
                    run(c)
                except Exception as cexc:  # noqa: BLE001
                    print(f"[ordm] fallback COMMENT failed for {_object_fqn(original)} "
                          f"(the view itself was created): {str(cexc)[:160]}")
                    # A transient error (concurrent update, 429) is re-raised so the gold
                    # fixpoint's retry handles it, as it did before; anything else is recorded.
                    if comment_failures is None or is_retryable(str(cexc)):
                        raise
                    comment_failures.append((_object_fqn(original), c,
                                             f"{_object_fqn(original)} (fallback COMMENT): {cexc}"))
            return None

    return wrapped


_ALTER_TABLE_RE = re.compile(r"\s*ALTER\s+TABLE\s+([`\w.]+)", re.IGNORECASE)


def _regroup_alters_by_table(units):
    """Re-split per-FILE relationship units into per-TARGET-TABLE units. A package's
    relationships.sql holds every constraint for the package (up to ~145 ALTERs in one file),
    so per-file fan-out ran each package serially and the biggest file floored the phase
    (measured: outcome-rels elapsed ~ its summed statement time). Constraints on different
    tables are independent -- PKs are inline in CREATE TABLE and a UC FK does not lock its
    parent -- while same-table ALTERs stay in one serial unit (concurrent metadata commits to
    one table race). Order within a table is preserved; a statement with no ALTER TABLE
    target stays in a per-file fallback unit so nothing is dropped. A table unit is labelled
    `<file>::<table>` (the file that first constrains it), so a failure names both."""
    by_table, order, fallback, first_rel = {}, [], [], {}
    for rel, statements in units:
        leftovers = []
        for stmt in statements:
            m = _ALTER_TABLE_RE.match(stmt, _body_offset(stmt))
            if not m:
                leftovers.append(stmt)
                continue
            key = m.group(1).replace("`", "").lower()
            if key not in by_table:
                by_table[key] = []
                order.append(key)
                first_rel[key] = rel
            by_table[key].append(stmt)
        if leftovers:
            fallback.append((rel, leftovers))
    return [(f"{first_rel[t]}::{t}", by_table[t]) for t in order] + fallback


def _drop_any_kind(run, fqn):
    """Drop `fqn` whatever kind it currently is. DROP is kind-specific in Databricks, so try
    each IF EXISTS form and ignore the wrong-kind error; the one matching the object's real
    kind clears it. Safe: IF EXISTS + wrong kind errors with no side effect."""
    for kind in ("MATERIALIZED VIEW", "VIEW", "TABLE"):
        try:
            run(f"DROP {kind} IF EXISTS {fqn}")
        except Exception:  # noqa: BLE001  (wrong-kind / not-found: harmless here)
            pass


def _exec(run, stmt, profiler=None, phase=None, tls=None, drop_on_kind_mismatch=False):
    """Run one statement with the given executor. Returns 'ok', 'exists' (idempotent
    re-run of an existing constraint/object), or the error string. run_units_parallel
    inspects that error string via is_retryable/RETRYABLE_TOKENS and retries the
    concurrency-only classes (rt09) before folding a genuine failure.

    `drop_on_kind_mismatch` (set only under --demote-materialized): if the statement fails
    because the target object exists as the WRONG kind, drop the stale object and re-run
    once, so a re-deploy onto a dirty CI/CD catalog self-heals instead of hard-failing.

    When `profiler` is set (--profile, rt08) the wall time is recorded against `phase`,
    with the warehouse statement_id (stashed on `tls` by _wh_runner) so the timing can be
    joined to Query History. Timing wraps success and failure alike; overhead is ~zero
    when profiler is None."""
    t0 = time.perf_counter() if profiler is not None else 0.0
    try:
        run(stmt)
        return "ok"
    except Exception as exc:  # noqa: BLE001
        low = str(exc).lower()
        if any(tok in low for tok in _EXISTS):
            return "exists"
        # Drop-and-recreate self-heal fires ONLY for a CREATE statement: recreating a
        # dropped object is exactly what the CREATE does. Never for an ALTER (e.g. ADD
        # CONSTRAINT) — dropping the object and re-running the ALTER just finds nothing
        # (TABLE_OR_VIEW_NOT_FOUND). A wrong-KIND object under an ALTER means an earlier
        # CREATE for it failed/was skipped; surface that error rather than destroying it.
        if (drop_on_kind_mismatch and any(tok in low for tok in _KIND_MISMATCH)
                and _LEADING_CREATE_RE.search(stmt)):
            fqn = _object_fqn(stmt)
            if fqn:
                _drop_any_kind(run, fqn)
                try:
                    run(stmt)
                    return "ok"
                except Exception as exc2:  # noqa: BLE001
                    return str(exc2)
        return str(exc)
    finally:
        if profiler is not None:
            sid = getattr(tls, "statement_id", None) if tls is not None else None
            profiler.record(phase or "?", time.perf_counter() - t0, sid, t_start=t0)


def _apply_gold_fixpoint(run, gold, transient_retries=6, transient_delay=15,
                         max_workers=16, profiler=None, phase="outcome-gold", tls=None,
                         drop_on_kind_mismatch=False):
    """Apply gold views (regular + materialized) without pre-computing their DAG.

    Gold views reference other gold views, within and across packages, but
    discovery order is lexicographic, not dependency order. Each pass creates the
    ones whose dependencies already exist and defers the rest; repeat while any
    pass makes progress. Re-attempting a deferred view is safe (a failed CREATE
    created nothing; successes are never retried).

    The fixpoint semantics are RETAINED as the correctness net against a
    parser-invisible dependency (rt09 s3), but each PASS is parallelized: the
    currently-pending views are submitted concurrently to a bounded thread pool.
    Shared state is never mutated from a worker (a worker only runs `_exec` and
    returns its result string); the applied/skipped/still fold happens on this
    thread from the per-future results, so counters and ordering stay correct.

    Two stop conditions when a pass makes NO progress:
      - all remaining errors are MATERIALIZED-VIEW transients (view created, its
        async refresh pipeline not yet registered) or retryable concurrency
        conflicts (rt09 s6) -> sleep and retry, bounded, because the fix is time
        not order;
      - otherwise a genuine missing dependency or cycle -> return the failures.
    Returns (applied, skipped, failures).
    """
    applied = skipped = 0
    pending = list(gold)  # (rel, stmt)
    last_err = {}
    transient_rounds = 0
    while pending:
        still, progressed = [], False
        # Submit the whole pending set concurrently; fold results on this thread.
        if len(pending) == 1 or max_workers <= 1:
            results = [(rel, stmt, _exec(run, stmt, profiler, phase, tls, drop_on_kind_mismatch))
                       for rel, stmt in pending]
        else:
            with ThreadPoolExecutor(max_workers=min(max_workers, len(pending))) as pool:
                futs = [(rel, stmt,
                         pool.submit(_exec, run, stmt, profiler, phase, tls, drop_on_kind_mismatch))
                        for rel, stmt in pending]
                results = [(rel, stmt, fut.result()) for rel, stmt, fut in futs]
        for rel, stmt, res in results:
            if res == "ok":
                applied += 1
                progressed = True
            elif res == "exists":
                skipped += 1
                progressed = True
            else:
                last_err[rel] = res
                still.append((rel, stmt))
        if not progressed:
            retry_ok = still and all(
                is_retryable(last_err[rel])
                or any(t in last_err[rel].lower() for t in _MV_TRANSIENT)
                for rel, _ in still
            )
            if retry_ok and transient_rounds < transient_retries:
                transient_rounds += 1
                print(f"  ...{len(still)} view(s) refreshing/contending; "
                      f"retry {transient_rounds}/{transient_retries} in {transient_delay}s")
                time.sleep(transient_delay)
                pending = still
                continue
            return applied, skipped, sorted(f"{rel}: {last_err[rel]}" for rel, _ in still)
        pending = still
    return applied, skipped, []


# Flat phases whose files are fanned out concurrently (statements within a file stay
# ordered so a CREATE precedes its SET TAGS -- rt05). schemas is a single file (serial);
# outcome-gold goes through the fixpoint; metric-views and comments are deferred (below)
# but dispatched with the same per-file parallelism when their turn comes.
_FLAT_PHASES = ("core-table", "core-rels", "outcome-table", "outcome-rels")


@dataclass(frozen=True)
class DeployConfig:
    """The deploy knobs as ONE value object (design/58). apply()'s parameter list has grown
    to a dozen args threaded through _run_flat / _exec / _wh_runner; this dataclass is the
    seam a future `Deployer` class grows into (see design/58 for the target), and the
    single construction point pip-packaging + a notebook driver will build from. Introduced
    behavior-neutral: apply() keeps its exact signature and builds one of these internally,
    so no caller and no test changes. Do NOT expand responsibilities here yet -- it is a
    struct, not a base class."""
    catalog: str
    warehouse: str | None = None
    overrides: dict | None = None
    dry_run: bool = False
    max_workers: int = 16
    retries: int = 4
    backoff: float = 0.5
    demote_materialized: bool = False
    profile: bool = False
    domains: str | None = None
    refresh_gold_tables: bool = False
    refresh_materialized: bool = False
    reconcile_schema: bool = False
    reconcile_materialized: bool = False
    recreate: bool = False
    rfid_as_of_mode: str = "wall_clock"
    rfid_fixed_freshness_minutes: str = "120"
    rfid_mobile_freshness_minutes: str = "1440"
    rfid_count_target_cadence_days: str = "7"
    rfid_count_lookback_days: str = "30"
    shelf_as_of_mode: str = "wall_clock"
    shelf_fixed_freshness_minutes: str = "120"
    shelf_mobile_freshness_minutes: str = "1440"

    @classmethod
    def from_params(cls):
        """Build from get_param (widget -> env -> --flag -> default) -- the single place
        the CLI/bundle/notebook drivers resolve the deploy knobs. Mirrors
        synthetic-data generators' DeployContext.from_params so the two deploy entry points
        read the same way."""
        # Per-token overrides (--customer_schema ...), then --single_schema collapses ALL
        # tokens to one value (design/59 lean per-PR gate: deploy into one pr_<N> schema).
        # single_schema wins because it is the explicit "one database" request.
        overrides = {k: v for k in schema_defaults() if (v := get_param(k, ""))}
        overrides.update(single_schema_overrides(get_param("single_schema", "")))
        return cls(
            catalog=get_param("catalog", ""),
            warehouse=get_param("warehouse", "") or None,
            overrides=overrides,
            dry_run=str(get_param("dry_run", "")).lower() in ("1", "true", "yes"),
            max_workers=int(get_param("max_workers", "16")),
            demote_materialized=str(get_param("demote_materialized", "")).lower() in ("1", "true", "yes"),
            profile=str(get_param("profile", "")).lower() in ("1", "true", "yes"),
            domains=get_param("domains", "") or None,
            refresh_gold_tables=str(get_param("refresh_gold_tables", "")).lower() in ("1", "true", "yes"),
            refresh_materialized=str(get_param("refresh_materialized", "")).lower() in ("1", "true", "yes"),
            reconcile_schema=str(get_param("reconcile_schema", "")).lower() in ("1", "true", "yes"),
            reconcile_materialized=str(get_param("reconcile_materialized", "")).lower() in ("1", "true", "yes"),
            recreate=str(get_param("recreate", "")).lower() in ("1", "true", "yes"),
            rfid_as_of_mode=get_param("rfid_as_of_mode", "wall_clock"),
            rfid_fixed_freshness_minutes=get_param("rfid_fixed_freshness_minutes", "120"),
            rfid_mobile_freshness_minutes=get_param("rfid_mobile_freshness_minutes", "1440"),
            rfid_count_target_cadence_days=get_param("rfid_count_target_cadence_days", "7"),
            rfid_count_lookback_days=get_param("rfid_count_lookback_days", "30"),
            shelf_as_of_mode=get_param("shelf_as_of_mode", "wall_clock"),
            shelf_fixed_freshness_minutes=get_param("shelf_fixed_freshness_minutes", "120"),
            shelf_mobile_freshness_minutes=get_param("shelf_mobile_freshness_minutes", "1440"),
        )


def _required_schema_names(overrides, domains=None):
    """The distinct schema NAMES the deploy will write to: the schema_defaults() token->name
    mapping updated with `overrides` (so --single_schema pr_<N> collapses to {"pr_<N>"} and any
    per-token override wins). Derived from the SAME config resolve() uses, NOT from the
    hand-maintained bootstrap file -- so the runtime schema-ensure can never drift out of sync
    with the model the way 00_bootstrap_schemas.sql silently did (missing ac_schema ->
    SCHEMA_NOT_FOUND for agentic_commerce). `domains` is accepted for signature symmetry but
    intentionally does NOT narrow the set: creating an unused schema is a harmless idempotent
    no-op, whereas MISSING one is the fatal bug this guards against."""
    mapping = dict(schema_defaults())
    if overrides:
        mapping.update({k: v for k, v in overrides.items() if v})
    return sorted(set(mapping.values()))


def ensure_catalog_and_schemas(run, catalog, overrides, domains=None):
    """Idempotent pre-flight run BEFORE any table/view DDL: make sure the target CATALOG and
    every SCHEMA the DDL will write to already exist. Root-causes the SCHEMA_NOT_FOUND failure
    class where a package's schema is absent (the hand-maintained 00_bootstrap_schemas.sql
    drifted from the config, so a new package's tables tried to CREATE into a schema that was
    never bootstrapped). The schema set comes from _required_schema_names (config+overrides), so
    it stays correct automatically as packages are added.

    Catalog creation is BEST-EFFORT (operator directive: "try to create it"): on a workspace
    where the service principal lacks CREATE CATALOG but the catalog is pre-provisioned, a
    CREATE CATALOG IF NOT EXISTS can be denied even though the catalog is fine -- so a failure
    here only WARNs and continues; the real "can we write here?" signal surfaces on the schema
    creates. Schema creation is authoritative: a failure propagates, since no table DDL can
    succeed without its schema. Returns the number of schemas ensured."""
    try:
        run(f"CREATE CATALOG IF NOT EXISTS {catalog}")
        print(f"[ordm] ensured catalog {catalog} exists")
    except Exception as e:  # noqa: BLE001 -- best-effort; real signal is on the schema creates
        print(f"[ordm] WARNING: CREATE CATALOG IF NOT EXISTS {catalog} did not succeed "
              f"(continuing -- it may be pre-provisioned and not creatable by this principal): {e}")
    schemas = _required_schema_names(overrides, domains)
    for s in schemas:
        run(f"CREATE SCHEMA IF NOT EXISTS {catalog}.{s}")
    print(f"[ordm] ensured {len(schemas)} schema(s) in {catalog}: {', '.join(schemas)}")
    return len(schemas)


def apply(spark, catalog, overrides=None, dry_run=False, warehouse=None, wsclient=None,
          max_workers=16, retries=4, backoff=0.5, demote_materialized=False, profile=False,
          domains=None, rfid_as_of_mode="wall_clock",
          rfid_fixed_freshness_minutes="120", rfid_mobile_freshness_minutes="1440",
          rfid_count_target_cadence_days="7", rfid_count_lookback_days="30",
          shelf_as_of_mode="wall_clock",
          shelf_fixed_freshness_minutes="120", shelf_mobile_freshness_minutes="1440"):
    if not catalog:
        raise ValueError("`catalog` parameter is required (guardrail #1: no hardcoded catalog).")
    overrides = overrides or {}
    expressions = rfid_clock_expressions(rfid_as_of_mode, catalog, overrides)
    expressions.update(rfid_policy_expressions(
        fixed_freshness_minutes=rfid_fixed_freshness_minutes,
        mobile_freshness_minutes=rfid_mobile_freshness_minutes,
        count_target_cadence_days=rfid_count_target_cadence_days,
        count_lookback_days=rfid_count_lookback_days,
    ))
    expressions.update(shelf_clock_expressions(shelf_as_of_mode, catalog, overrides))
    shelf_policies = shelf_policy_expressions(
        fixed_freshness_minutes=shelf_fixed_freshness_minutes,
        mobile_freshness_minutes=shelf_mobile_freshness_minutes,
    )
    # Resolver defaults already carry the shipped shelf policy. Thread only an actual
    # override so adding Smart Shelf does not alter the RFID-only expression contract.
    if shelf_policies != shelf_policy_expressions():
        expressions.update(shelf_policies)
    applied = skipped = failed = 0
    failures = []
    gold = []          # deferred: gold views apply last, in dependency order (fixpoint)
    metric_views = []  # deferred units (rel, [statements]): read gold, apply after fixpoint
    comments = []      # deferred units (rel, [statements]): COMMENT ON COLUMN, applies last

    profiler = _Profiler() if profile else None
    # thread-local statement_id sink for the warehouse path (rt08 profile join); the SDK
    # long-poll runner stashes each statement_id here and _exec reads it on the same thread.
    tls = threading.local() if (warehouse and wsclient and not dry_run) else None

    # All DDL runs on ONE engine: the SQL warehouse when a warehouse id is provided
    # (uniform + portable — materialized views require it, and DBSQL handles the
    # physical DDL too), else the job's Spark (local/dry-run fallback). Synthetic-data
    # generators and DQ are separate job tasks and always run on Spark.
    if warehouse and wsclient and not dry_run:
        run = _wh_runner(wsclient, warehouse, tls=tls)
        print(f"[ordm] applying all DDL on SQL warehouse {warehouse} "
              f"(max_workers={max_workers})")
    else:
        run = _spark_runner(spark) if spark is not None else None

    # Pre-flight: ensure the catalog + every schema the DDL writes to exist, derived from the
    # config (not the hand-maintained bootstrap file), so a package can never CREATE a table
    # into an un-bootstrapped schema again (root-caused a daily-deploy SCHEMA_NOT_FOUND for
    # agentic_commerce). Idempotent (IF NOT EXISTS); skipped on dry-run / no-runner paths.
    ensured_schema_stmts = []
    if run is not None and not dry_run:
        ensure_catalog_and_schemas(run, catalog, overrides, domains)
        ensured_schema_stmts = [f"create schema if not exists {catalog}.{s}".lower()
                                for s in _required_schema_names(overrides, domains)]

    if demote_materialized:
        # Loud, so a future serving/prod target that inherits this flag cannot ship the
        # materialized views as plain views unnoticed (m1). Demote is a demo/CI-only choice.
        print("[ordm] WARNING: --demote-materialized is ACTIVE: materialized views are being "
              "deployed as PLAIN views and stale wrong-kind objects will be dropped+recreated. "
              "This is for the demo/CI catalog only; REMOVE it for a serving/prod deploy.")

    # --domains (design 57 §5d item 4): a lean per-PR gate deploys ONLY the requested domains.
    # State what is actually included -- the set can be BROADER than requested because any
    # outcome package auto-pulls in ALL canonical-core (its shared dependency); the schema
    # bootstrap is always in. Default (no --domains) applies everything, exactly as today.
    effective_domains = _effective_domain_filter(domains)
    if effective_domains is not None:
        print(f"[ordm] --domains filter ACTIVE: applying schemas (always) + domains/packages: "
              f"{', '.join(sorted(effective_domains))} "
              f"(any outcome package pulls in all canonical-core as its shared dependency).")

    def _fold(delta):
        """Fold a (applied, skipped, failures) triple into the run totals. Called only on
        this (main) thread -- workers never touch the shared counters (rt09 s4a/s5)."""
        nonlocal applied, skipped, failed
        a, s, f = delta
        applied += a
        skipped += s
        failed += len(f)
        failures.extend(f)

    # On a --demote-materialized (CI/CD demo) re-deploy, a stale object from a prior run may
    # exist as the wrong kind; drop-and-recreate self-heals it. A serving/prod deploy
    # (demote off) stays strict and never silently drops a real object.
    drop_mismatch = demote_materialized

    def _run_flat(label, units):
        """Dispatch one flat phase's units concurrently (a unit is a file, or a per-target-table
        regroup for relationships and comments; statements within a unit run in order) and
        fold the result. A phase is a barrier: all its units
        finish before the next phase starts (preserves CREATE-before-ALTER across phases)."""
        if not units:
            return
        exec_one = lambda s: _exec(run, s, profiler, label, tls, drop_mismatch)  # noqa: E731
        if label in ("core-rels", "outcome-rels"):
            units = _regroup_alters_by_table(units)
        _fold(run_units_parallel(units, exec_one, max_workers=max_workers,
                                 retries=retries, backoff=backoff))

    # Flat phases arrive contiguously from _phases; accumulate a phase's file-units and
    # flush (dispatch) at the boundary so each flat phase is its own barrier.
    pending_label, pending_units = None, []

    def _flush():
        nonlocal pending_label, pending_units
        if pending_units:
            _run_flat(pending_label, pending_units)
        pending_label, pending_units = None, []

    # Pass `domains` only when a filter is actually requested, so the default (no filter)
    # call stays byte-identical to today -- keeps backward compatibility with any caller (or
    # test) that monkeypatches/wraps _phases with the pre-domains 3-arg signature.
    _phase_kwargs = {"domains": domains} if domains else {}
    if expressions:
        _phase_kwargs["expressions"] = expressions
    for label, path, statements in _phases(catalog, overrides, demote_materialized, **_phase_kwargs):
        rel = os.path.relpath(path, REPO_ROOT)
        leftover = any("${" in s for s in statements)
        note = "  (WARNING: unresolved ${...} token)" if leftover else ""
        print(f"[{label}] {rel} — {len(statements)} statement(s){note}")
        if dry_run:
            applied += len(statements)
            continue
        if label in _FLAT_PHASES:
            if label != pending_label:
                _flush()  # phase changed -> barrier before starting the new one
                pending_label = label
            pending_units.append((rel, statements))
            continue
        _flush()  # any non-flat phase is a barrier after the preceding flat phase
        if label == "schemas":
            # The bootstrap file lists every schema. ensure_catalog_and_schemas already
            # created the ones this run writes to, and under --single_schema all 54 lines
            # resolve to the SAME schema, so skip the ensured ones, de-duplicate the rest,
            # and run what is left concurrently. The key ignores the leading `--` header the
            # splitter keeps on a file's first statement, or that CREATE never matches. Any
            # CREATE left runs before the ALTER SCHEMA lines (predictive optimization), so the
            # CREATE-before-ALTER order does not depend on the pre-flight alone.
            seen, creates, others = set(ensured_schema_stmts), [], []
            for stmt in statements:
                body = stmt[_body_offset(stmt):]
                key = " ".join(body.split()).rstrip(";").strip().lower()
                if key in seen:
                    skipped += 1
                    continue
                seen.add(key)
                bucket = creates if key.startswith("create ") else others
                bucket.append((f"{rel}#{len(creates) + len(others)}", [stmt]))
            exec_one = lambda st: _exec(run, st, profiler, label, tls)  # noqa: E731
            for todo in (creates, others):
                if todo:
                    _fold(run_units_parallel(todo, exec_one, max_workers=max_workers,
                                             retries=retries, backoff=backoff))
        elif label == "outcome-gold":
            gold.extend((rel, s) for s in statements)  # defer to the fixpoint below
        elif label == "metric-views":
            metric_views.append((rel, statements))  # defer until gold exists (per-file unit)
        elif label == "comments":
            comments.append((rel, statements))  # defer until views exist (per-file unit)
    _flush()  # generator ends on the (deferred) comments phase, so this is a no-op safety net

    # Gold views depend on other gold views (cross-package), so apply them last and in
    # dependency order (fixpoint) rather than lexicographic glob order. Each pass runs
    # concurrently, but the fixpoint semantics stay as the net for a parser-invisible dep.
    # Fold view column comments into the gold view CREATEs (one statement per view instead of
    # one per column). Views it cannot rewrite exactly keep the separate COMMENT path below.
    gold_run, fallback_comment_failures = run, []
    if not dry_run and gold and comments:
        gold, comments, inline_fallback = _inline_view_comments(gold, comments)
        if inline_fallback:
            print(f"[ordm] inlined column comments into {len(inline_fallback)} gold view CREATE(s)")
        gold_run = _inline_fallback_runner(run, inline_fallback, fallback_comment_failures)

    if not dry_run and gold:
        _fold(_apply_gold_fixpoint(gold_run, gold, max_workers=max_workers,
                                   profiler=profiler, tls=tls,
                                   drop_on_kind_mismatch=drop_mismatch))
        # De-duplicate by (view, COMMENT statement), keeping the first message: a fallback retried
        # after a transient error re-records the same failure, and the warehouse error text can
        # carry per-attempt ids, so the message itself is not a reliable key.
        first = {}
        for fqn, stmt, msg in fallback_comment_failures:
            first.setdefault((fqn, stmt), msg)
        _fold((0, 0, sorted(first.values())))  # count them in `failed` too

    # Metric views (UC semantic layer) read the gold views, so apply them after the gold
    # fixpoint. Plain views, one per file -> fan out per file.
    if not dry_run and metric_views:
        _run_flat("metric-views", metric_views)

    # Column comments last of all: they COMMENT ON COLUMN of table, materialized-view and
    # non-inlined view columns (most plain gold_ view comments now ride on the CREATE above),
    # so every target exists by now. The sizing below dates from before inlining.
    # Regroup per-FILE units into per-TARGET-TABLE units: comments were the dominant apply
    # phase, batched ~55/file into 9 files, so per-file fan-out gave only ~9 lanes and was
    # floored by the biggest file (~113 serial stmts). Per-table fan-out lifts this to ~50
    # lanes (measured: apply_ddl was flat ~247-270s across 16/24/32 workers + 1/3 clusters
    # because THIS was the ceiling, not warehouse concurrency). Same-table comments stay in
    # one serial unit -- required, since concurrent metadata commits to one table race and a
    # COMMENT is silently lost (measured on the reference workspace).
    if not dry_run and comments:
        _run_flat("comments", _regroup_comments_by_table(comments))

    print(f"\n[ordm] apply-ddl: {applied} applied, {skipped} skipped (already exists), "
          f"{failed} failed{' (DRY RUN)' if dry_run else ''}.")
    if profiler is not None:
        profiler.report()
    if failures:
        raise AssertionError("DDL failures:\n  " + "\n  ".join(sorted(failures)))
    return applied, skipped


def main():
    # One construction point for the deploy knobs (design/58 seam): widget -> env -> --flag.
    cfg = DeployConfig.from_params()

    spark = wsclient = None
    if not cfg.dry_run:
        from pyspark.sql import SparkSession
        spark = SparkSession.builder.getOrCreate()
        if cfg.warehouse:
            from databricks.sdk import WorkspaceClient
            from databricks.sdk.core import Config
            # Size the SDK HTTP connection pool to the thread pool (rt01, rt07): the
            # databricks-sdk sits on a requests HTTPAdapter whose per-host pool caps
            # in-flight requests -- ORDM's SDK pins it to a modest default, so a
            # ThreadPoolExecutor(16) would silently block near ~10 in-flight statements
            # unless the pool is raised. `max_connection_pools` -> HTTPAdapter.pool_maxsize
            # (the in-flight-to-one-host gate); `max_connections_per_pool` ->
            # pool_connections. Set BOTH >= max_workers (with a little headroom) so P is
            # thread-bound, not pool-bound.
            # NOTE (operators): warehouse execution concurrency is ~10 x active clusters,
            # so also pre-scale the serverless warehouse min_clusters to keep P from being
            # autoscale-bound (that wiring lives in databricks.yml, not this file).
            pool = max(cfg.max_workers + 4, 20)
            sdk_cfg = Config(max_connection_pools=pool, max_connections_per_pool=pool)
            wsclient = WorkspaceClient(config=sdk_cfg)  # ambient job auth + sized pool

    # Physical gold snapshot tables are populated during apply_ddl, before generate_all. Reload
    # only their INSERT OVERWRITE statements after generation so DQ never reads the prior run.
    if cfg.refresh_gold_tables:
        if not cfg.catalog:
            raise ValueError("`catalog` is required for --refresh_gold_tables.")
        if not (cfg.warehouse and wsclient):
            raise ValueError("--refresh_gold_tables needs --warehouse.")
        expressions = rfid_clock_expressions(cfg.rfid_as_of_mode, cfg.catalog, cfg.overrides)
        expressions.update(rfid_policy_expressions(
            fixed_freshness_minutes=cfg.rfid_fixed_freshness_minutes,
            mobile_freshness_minutes=cfg.rfid_mobile_freshness_minutes,
            count_target_cadence_days=cfg.rfid_count_target_cadence_days,
            count_lookback_days=cfg.rfid_count_lookback_days,
        ))
        expressions.update(shelf_clock_expressions(cfg.shelf_as_of_mode, cfg.catalog, cfg.overrides))
        shelf_policies = shelf_policy_expressions(
            fixed_freshness_minutes=cfg.shelf_fixed_freshness_minutes,
            mobile_freshness_minutes=cfg.shelf_mobile_freshness_minutes,
        )
        if shelf_policies != shelf_policy_expressions():
            expressions.update(shelf_policies)
        run = _wh_runner(wsclient, cfg.warehouse)
        refreshed, failures = refresh_gold_tables(
            run,
            cfg.catalog,
            cfg.overrides,
            domains=cfg.domains,
            expressions=expressions,
            max_workers=cfg.max_workers,
        )
        print(f"\n[ordm] refresh-gold-tables: {refreshed} loaded, {len(failures)} failed.")
        if failures:
            raise AssertionError("physical gold-table refresh failures:\n  " + "\n  ".join(failures))
        return

    # --refresh_materialized (AI review #108 H1, Approach B): a standalone post-generate_all
    # task for the SERVING deploy that ONLY refreshes the gold MVs (parents-first), so they
    # end populated against real data. Materialized views refresh on a SQL warehouse, so this
    # mode requires --warehouse; it never touches the full apply path.
    if cfg.refresh_materialized:
        if not cfg.catalog:
            raise ValueError("`catalog` is required for --refresh_materialized.")
        if not (cfg.warehouse and wsclient):
            raise ValueError("--refresh_materialized needs --warehouse (MVs refresh on a SQL warehouse).")
        run = _wh_runner(wsclient, cfg.warehouse)
        refreshed, failures = refresh_materialized_views(
            run, cfg.catalog, cfg.overrides, max_workers=cfg.max_workers)
        print(f"\n[ordm] refresh-materialized: {refreshed} refreshed, {len(failures)} failed.")
        if failures:
            raise AssertionError("materialized-view refresh failures:\n  " + "\n  ".join(failures))
        return

    # --recreate (admin clean-reinstall; NEVER auto-called): full nuke -- DROP every managed
    # table (drop-only; a following full apply recreates them WITH tags/FKs/comments, then
    # generate_all refills data). Requires --warehouse.
    if cfg.recreate:
        if not cfg.catalog:
            raise ValueError("`catalog` is required for --recreate.")
        if not (cfg.warehouse and wsclient):
            raise ValueError("--recreate needs --warehouse.")
        run = _wh_runner(wsclient, cfg.warehouse)
        # Ensure the catalog + schemas exist first, so a DROP never hits a missing schema and the
        # follow-up apply has its schemas ready (idempotent).
        ensure_catalog_and_schemas(run, cfg.catalog, cfg.overrides, cfg.domains)
        dropped, failures = recreate_all(run, cfg.catalog, cfg.overrides, domains=cfg.domains)
        if failures:
            raise AssertionError("recreate failures:\n  " + "\n  ".join(failures))
        return

    # --reconcile_materialized only takes effect INSIDE the --reconcile_schema branch below (both
    # run before apply_ddl, and pairing them is how the daily serving task uses them). Guard the
    # standalone form: a bare `--reconcile_materialized` would otherwise match no early-return
    # branch and fall through to a FULL apply() with the flag silently discarded (AI review #108
    # M1). Fail loudly instead of doing the wrong thing.
    if cfg.reconcile_materialized and not cfg.reconcile_schema:
        raise ValueError(
            "--reconcile_materialized must be combined with --reconcile_schema "
            "(it runs inside that reconcile phase, before apply_ddl); it is not a standalone mode.")

    # --reconcile_schema (AI review #108 H1 table-drift; daily serving default): DROP-ONLY the
    # managed tables whose live schema drifted from the committed DDL, so the apply_ddl step that
    # runs AFTER this recreates them (with tags + FKs + comments) via CREATE TABLE IF NOT EXISTS.
    # Without this, a table whose DDL changed keeps its stale structure. Data refilled by
    # generate_all. Requires --warehouse (reads DESCRIBE). MUST be sequenced BEFORE apply_ddl.
    if cfg.reconcile_schema:
        if not cfg.catalog:
            raise ValueError("`catalog` is required for --reconcile_schema.")
        if not (cfg.warehouse and wsclient):
            raise ValueError("--reconcile_schema needs --warehouse (it reads DESCRIBE).")
        run = _wh_runner(wsclient, cfg.warehouse)
        run_query = _wh_query(wsclient, cfg.warehouse)
        # Ensure catalog + schemas first: on a PR's FIRST push the pr_<N> schema does not exist
        # yet, so a DROP TABLE IF EXISTS in it would raise SCHEMA_NOT_FOUND. Creating the schema
        # up front makes the drop a clean no-op (idempotent), and the DESCRIBE reads then return
        # "no columns" for absent tables, so reconcile correctly finds nothing to drop.
        ensure_catalog_and_schemas(run, cfg.catalog, cfg.overrides, cfg.domains)
        dropped, unchanged, failures = reconcile_schema(
            run, run_query, cfg.catalog, cfg.overrides, domains=cfg.domains)
        print(f"\n[ordm] reconcile-schema: {dropped} dropped (apply recreates), {unchanged} "
              f"unchanged, {len(failures)} failed.")
        # --reconcile_materialized (AI review #108 M2): also drop gold MVs whose SELECT DEFINITION
        # drifted, so apply_ddl recreates them with the new body. Serving-only: it is paired with
        # --reconcile_schema on the daily job and NOT passed on the lean gate (which
        # --demote-materialized turns the MVs into plain CREATE-OR-REPLACE views that self-heal),
        # so it never tries to DROP MATERIALIZED VIEW a demoted plain view.
        if cfg.reconcile_materialized:
            mv_dropped, mv_unchanged, mv_failures = reconcile_materialized_views(
                run, run_query, cfg.catalog, cfg.overrides, domains=cfg.domains)
            print(f"[ordm] reconcile-materialized: {mv_dropped} dropped (apply recreates), "
                  f"{mv_unchanged} unchanged, {len(mv_failures)} failed.")
            failures = failures + mv_failures
        if failures:
            raise AssertionError("schema-reconcile failures:\n  " + "\n  ".join(failures))
        return

    apply(spark, cfg.catalog, cfg.overrides, cfg.dry_run, warehouse=cfg.warehouse,
          wsclient=wsclient, max_workers=cfg.max_workers,
          demote_materialized=cfg.demote_materialized, profile=cfg.profile, domains=cfg.domains,
          rfid_as_of_mode=cfg.rfid_as_of_mode,
          rfid_fixed_freshness_minutes=cfg.rfid_fixed_freshness_minutes,
          rfid_mobile_freshness_minutes=cfg.rfid_mobile_freshness_minutes,
          rfid_count_target_cadence_days=cfg.rfid_count_target_cadence_days,
          rfid_count_lookback_days=cfg.rfid_count_lookback_days,
          shelf_as_of_mode=cfg.shelf_as_of_mode,
          shelf_fixed_freshness_minutes=cfg.shelf_fixed_freshness_minutes,
          shelf_mobile_freshness_minutes=cfg.shelf_mobile_freshness_minutes)


if __name__ == "__main__":
    main()
