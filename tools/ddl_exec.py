# ============================================================
# ORDM · Deploy · parallel DDL execution
# ============================================================
# Factors the parallel-execution and retry concerns out of apply_model_ddl.py so
# the applier can fan independent DDL files across threads without owning the
# concurrency machinery. Pure module: no pyspark/SDK imports at the top, so it
# imports in a plain pytest exactly like the applier does.
#
# Three concerns live here, each pinned to a red-team finding on design/57:
#
#   RETRYABLE_TOKENS / is_retryable (rt09) - the error CLASSES that PARALLEL
#     submission manufactures (Delta/UC concurrent-commit conflicts, lock
#     contention, Statement Execution API 429s). These are distinct from the
#     applier's _EXISTS tuple (an "already exists" is an idempotent no-op, count
#     it skipped) and _MV_TRANSIENT tuple (a just-created MV whose async refresh
#     has not registered). A concurrent-update must be RETRIED, never swallowed,
#     or we declare success on a statement that never committed.
#
#   demote_materialized_views (rt06) - for the demo/fast deploy, rewrite
#     'CREATE OR REFRESH MATERIALIZED VIEW' to 'CREATE OR REPLACE VIEW'. The
#     tables are tiny and nothing needs materialization, and this erases the
#     empty-MV-refresh correctness trap (MVs are created at apply time against
#     empty tables, before the generators run, so a materialized snapshot would
#     be wrong-and-empty). Idempotent; leaves a plain view and a bare
#     'MATERIALIZED VIEW' mention inside a comment untouched.
#
#   run_units_parallel (rt02, rt05, rt09) - a unit is an independent ordered group
#     (a file, or a per-target-table regroup), never split across threads: a file's
#     CREATE must precede its own SET TAGS,
#     and same-object DDL split across threads thrashes UC metadata locks. So
#     statements WITHIN a unit run sequentially; independent units run
#     concurrently. Failures are folded in the MAIN thread and every failed unit
#     is reported (not just the first to raise).
# ============================================================
from __future__ import annotations

import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

# Lowercase substrings that mark a transient/concurrency error worth retrying.
# These are the error classes that PARALLEL submission manufactures and that the
# applier's existing _EXISTS / _MV_TRANSIENT tuples do NOT cover (rt09). Do not
# fold these into _EXISTS: an "exists" is a no-op (count skipped); a
# concurrent-update must be re-run with backoff, not treated as success.
RETRYABLE_TOKENS = (
    "concurrent_update",                # UC/Delta concurrent-commit (token form)
    "concurrent update",                # UC/Delta concurrent-commit (spaced form)
    "concurrentmodification",           # ConcurrentModificationException
    "concurrentappend",                 # ConcurrentAppendException
    "metadatachanged",                  # MetadataChangedException
    "protocolchanged",                  # ProtocolChangedException
    "concurrent_schema_evolution",      # concurrent schema evolution
    "could not acquire lock",           # commit lock contention
    "lock timeout",                     # commit lock contention
    "being modified by another",        # generic UC concurrent-modify phrasing
    "deadlock",                         # metadata-store deadlock
    "operation failed due to a concurrent",  # generic UC concurrent phrasing
    "rate limit",                       # Statement Execution API throttling
    "too many requests",                # Statement Execution API throttling
    "429",                              # Statement Execution API throttling
)

# CREATE OR REFRESH MATERIALIZED VIEW -> CREATE OR REPLACE VIEW, case-insensitive
# and whitespace-tolerant (any run of whitespace, including newlines, between the
# keywords). Matches only the full leading keyword phrase, so a bare
# 'MATERIALIZED VIEW' inside a comment or a plain 'CREATE OR REPLACE VIEW' never
# matches, and the rewritten text cannot match again (idempotent).
_MV_CREATE_RE = re.compile(
    r"CREATE\s+OR\s+REFRESH\s+MATERIALIZED\s+VIEW", re.IGNORECASE
)


def is_retryable(err_str: str) -> bool:
    """True if err_str (any case) contains a RETRYABLE_TOKENS substring."""
    low = str(err_str).lower()
    return any(tok in low for tok in RETRYABLE_TOKENS)


def is_materialized_view_create(stmt: str) -> bool:
    """True only if the statement's EXECUTABLE text is a materialized-view create,
    i.e. it contains the leading `CREATE OR REFRESH MATERIALIZED VIEW` phrase (the
    same anchored phrase demote_materialized_views rewrites). Matching the full
    keyword phrase - NOT a bare 'materialized view' substring - is deliberate: a
    file's header comment is kept attached to its CREATE by the splitter, and many
    PLAIN views carry comments that mention materialized views ("Promote to a
    materialized view at deploy time"). A substring test would misclassify those
    plain views as MVs and wrongly exempt them from the terminal-SUCCEEDED barrier
    (rt09 s2). A demoted MV (rewritten to CREATE OR REPLACE VIEW) also correctly
    returns False here even though its comment still says "materialized view"."""
    return bool(_MV_CREATE_RE.search(stmt))


def demote_materialized_views(sql_text: str) -> str:
    """Rewrite 'CREATE OR REFRESH MATERIALIZED VIEW' -> 'CREATE OR REPLACE VIEW'
    (case-insensitive, whitespace-tolerant), leaving everything else
    byte-identical. For the demo/fast deploy: tiny data, nothing needs
    materialization, and it erases the empty-MV-refresh correctness trap (rt06).
    Idempotent, and does NOT touch a plain 'CREATE OR REPLACE VIEW' or a
    'MATERIALIZED VIEW' substring inside a comment/string. Returns the input
    unchanged if no such statement is present."""
    return _MV_CREATE_RE.sub("CREATE OR REPLACE VIEW", sql_text)


# The FQN a materialized-view create targets, captured from the same anchored
# keyword phrase _MV_CREATE_RE matches so the two can never disagree about what
# counts as an MV. The name may be backtick-quoted or dotted; ${...} tokens are
# already resolved by the time _phases hands text here, but the character class
# tolerates them so the helper is usable on unresolved text too.
_MV_CREATE_TARGET_RE = re.compile(
    r"CREATE\s+OR\s+REFRESH\s+MATERIALIZED\s+VIEW\s+([A-Za-z0-9_.`${}]+)",
    re.IGNORECASE,
)


def materialized_view_fqns(sql_text: str):
    """The set of fully-qualified names created as materialized views in sql_text.

    Used to learn WHICH objects a run demoted, so the comments phase can retarget
    only those. Names are lowercased and stripped of backticks so a later lookup is
    case- and quoting-insensitive (Unity Catalog identifiers are case-insensitive)."""
    return {m.group(1).replace("`", "").lower()
            for m in _MV_CREATE_TARGET_RE.finditer(sql_text)}


def retarget_demoted_alter_tags(sql_text: str, demoted_fqns) -> str:
    """Rewrite 'ALTER TABLE <fqn>' -> 'ALTER VIEW <fqn>' for exactly the fqns in
    demoted_fqns, leaving every other ALTER TABLE byte-identical (A1).

    Why: --demote-materialized deploys an MV as a plain VIEW, but comments.sql still
    carries `ALTER TABLE <mv> SET TAGS (...)` for it. Databricks rejects ALTER TABLE
    against a view, so the whole comments unit fails and the object silently loses its
    tags. Retargeting is scoped to the fqns the SAME run demoted, so a real table's
    ALTER TABLE is never touched and a non-demoted run is a no-op.

    Idempotent: the output contains ALTER VIEW for those fqns, which no longer matches
    the ALTER TABLE pattern. Returns the input unchanged when demoted_fqns is empty."""
    if not demoted_fqns:
        return sql_text
    wanted = {str(f).replace("`", "").lower() for f in demoted_fqns}

    def _sub(m):
        name = m.group(2).replace("`", "").lower()
        return (m.group(1) + m.group(2)) if name not in wanted else (
            m.group(1).replace("TABLE", "VIEW").replace("table", "view") + m.group(2))

    # Capture the ALTER TABLE keyword run and the target name separately so only the
    # keyword is rewritten and the name's original spelling/quoting is preserved.
    return re.sub(r"(\bALTER\s+TABLE\s+)([A-Za-z0-9_.`${}]+)", _sub, sql_text,
                  flags=re.IGNORECASE)


def _run_unit(rel, statements, exec_one, retries, backoff):
    """Run ONE unit's statements sequentially. Returns
    (applied:int, skipped:int, failure_or_None:str|None).

    On an error string: if is_retryable, re-run the SAME statement up to
    `retries` times with exponential backoff (backoff * 2**attempt, capped ~8s).
    If it still errors, or the error is non-retryable, STOP this unit and return
    a 'rel: err' failure without running the rest of the unit's statements."""
    applied = skipped = 0
    for stmt in statements:
        res = exec_one(stmt)
        attempt = 0
        while res not in ("ok", "exists") and is_retryable(res) and attempt < retries:
            time.sleep(min(backoff * (2 ** attempt), 8.0))
            res = exec_one(stmt)
            attempt += 1
        if res == "ok":
            applied += 1
        elif res == "exists":
            skipped += 1
        else:
            # non-retryable, or retryable-but-exhausted: stop this unit here.
            return applied, skipped, f"{rel}: {res}"
    return applied, skipped, None


def run_units_parallel(units, exec_one, max_workers=16, retries=4, backoff=0.5):
    """Execute independent UNITS concurrently; statements WITHIN a unit run
    SEQUENTIALLY.

    units: list of (label:str, statements:list[str]). A unit is an independent
      group whose statements must stay ordered: usually a FILE, or a per-target-
      table regroup (relationships, comments) or a single statement (schemas).
      Never split a unit across threads (rt05: a file's CREATE must precede its
      own SET TAGS; rt02: same-object DDL split across threads thrashes UC
      metadata locks).
    exec_one(stmt) -> 'ok' | 'exists' | <error string>  (identical to the
      applier's _exec once bound to a runner; 'ok'/'exists' are success, anything
      else is an error).

    Units run concurrently via ThreadPoolExecutor(max_workers). Each future
    returns (applied, skipped, failure_or_None); results are folded in the MAIN
    thread (never mutate shared counters from workers, rt09). Each 'ok' counts as
    applied, each 'exists' as skipped.

    Returns (applied:int, skipped:int, failures:list[str]) where failures is
    SORTED and contains EVERY failed unit (not just the first to raise, rt09)."""
    applied = skipped = 0
    failures = []
    units = list(units)
    if not units:
        return applied, skipped, failures

    workers = max(1, min(max_workers, len(units)))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [
            pool.submit(_run_unit, rel, statements, exec_one, retries, backoff)
            for rel, statements in units
        ]
        for fut in as_completed(futures):
            u_applied, u_skipped, failure = fut.result()  # folded in main thread
            applied += u_applied
            skipped += u_skipped
            if failure is not None:
                failures.append(failure)

    failures.sort()
    return applied, skipped, failures
