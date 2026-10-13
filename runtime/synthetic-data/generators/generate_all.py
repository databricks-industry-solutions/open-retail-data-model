# ============================================================
# ORDM · Synthetic data · generate_all orchestrator
# ============================================================
# One serverless task that runs every generator in dependency order, so the
# environment (dbldatagen / pyyaml) is installed ONCE per job instead of once per
# generator task. It builds the shared DeployContext, computes dependency WAVES from
# the declarative registry (_registry.py), and calls each generator's run(ctx).
#
# WAVES (Kahn levels): generators with no unmet dependency run in the same wave,
# concurrently on the shared SparkSession via a ThreadPoolExecutor. Spark is
# thread-safe for concurrent action submission, so the tiny per-generator jobs overlap
# on the one warm session (no per-generator compute/session acquisition, unlike a
# for_each task). Concurrent jobs share the default FIFO scheduler pool; the overlap
# comes from independent threads submitting simultaneously, not from FAIR scheduling
# (which we do not set). Waves run STRICTLY in order and a wave fully
# finishes before the next starts, because a later wave reads an earlier wave's
# tables. This replaces the old fully-serial `for spec in topo_sort(...)` loop; the
# critical path drops from the sum of all generators to the sum of the slowest
# generator per wave (design/57, rt04).
#
# An optional `--include <keys>` runs a domain subset plus its transitive upstream
# generators. It takes a comma-separated list of schema keys or generator names,
# analogous to run_checks --domains (though generate_all additionally pulls the
# subset's upstream generators, which the DQ runner does not); the filtered set is
# then waved the same way.
#
# Trade-off vs. one-task-per-generator: a failure in any generator aborts this
# single task, and a re-run re-executes the whole chain from the start (there is no
# per-generator restart-from-failure granularity). That is safe under the default
# `overwrite` mode (idempotent full reload); running `--mode append` forfeits the
# rerun-idempotency this relies on. It buys installing the serverless environment
# ONCE per job instead of once per generator task.
# ============================================================

import importlib
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor

from pyspark.sql import SparkSession

try:
    from _common import get_param
    from _context import DeployContext
    from _registry import GENERATORS, select, waves
except ImportError:  # importable as siblings when run as a spark_python_task / notebook
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import get_param
    from _context import DeployContext
    from _registry import GENERATORS, select, waves


def _run_generator(spec, ctx):
    """Import and run one generator on the shared session. Returns (spec, error):
    error is None on success, else the caught exception. Exceptions are RETURNED
    (folded on the main thread) rather than raised in the worker so that one
    generator's failure never silently loses the others' failures in the same wave."""
    t0 = time.time()
    print(f"[ordm]   -> start: {spec.name}")
    try:
        importlib.import_module(spec.name).run(ctx)
    except Exception as exc:  # fold, don't raise from the worker thread
        print(f"[ordm]   !! FAILED: {spec.name} after {time.time() - t0:.1f}s: {exc}",
              file=sys.stderr)
        return spec, exc
    print(f"[ordm]   <- done:  {spec.name} in {time.time() - t0:.1f}s")
    return spec, None


def main():
    ctx = DeployContext.from_params(SparkSession.builder.getOrCreate())
    if ctx.mode == "append":
        # The single-task design relies on `overwrite` idempotency: a failure partway
        # through the chain is recovered by simply re-running (each generator reloads).
        # `append` forfeits that — a rerun re-appends the already-written upstream
        # tables. Warn loudly rather than silently double-load.
        print("[ordm] WARNING: generate_all with --mode append is NOT rerun-safe: a "
              "mid-chain failure + rerun re-appends already-written upstream tables. "
              "Use the default 'overwrite' unless you specifically intend incremental "
              "appends and will manage reruns yourself.", file=sys.stderr)
    include = get_param("include", "")
    selected = select(GENERATORS, include)
    plan = waves(selected)
    total = sum(len(w) for w in plan)
    summary = " | ".join(
        f"W{i}: " + ", ".join(s.name for s in wave) for i, wave in enumerate(plan))
    print(f"[ordm] generate_all: {total} generator(s) in {len(plan)} dependency wave(s)"
          + (f"  (include={include})" if include else "") + f"\n[ordm]   {summary}")

    # M1 (AI review #108): a requested label that has NO generator (e.g. unified-customer-view
    # ships none) resolves to a benign no-op here -- but a scoped lean-CI run would then load
    # NO data and run DQ over EMPTY tables, so a "green" DQ signal for such a package is NOT a
    # real data-quality signal. Say so loudly so the operator is not misled. (A generator-less
    # label produces no generators AND pulls in no upstreams via provides, so include-set-empty
    # after select == that case.)
    if include and total == 0:
        print(f"[ordm] WARNING: --include={include} selected ZERO generators (the requested "
              "domain/package ships no synthetic-data generator). No data was loaded; any "
              "downstream DQ for it runs against EMPTY tables and is NOT a real data signal.",
              file=sys.stderr)

    for i, wave in enumerate(plan):
        names = [s.name for s in wave]
        print(f"[ordm] ===== wave {i} ({len(wave)} generator(s)): {', '.join(names)} =====")
        t0 = time.time()
        # Run the wave's generators concurrently on the one shared SparkSession. Their
        # `provides` are disjoint by construction (topo_sort/waves enforce a single
        # provider per key), so same-wave generators never write the same table.
        with ThreadPoolExecutor(max_workers=len(wave)) as pool:
            results = list(pool.map(lambda s: _run_generator(s, ctx), wave))
        failures = [(spec, err) for spec, err in results if err is not None]
        print(f"[ordm] ===== wave {i} finished in {time.time() - t0:.1f}s "
              f"({len(wave) - len(failures)}/{len(wave)} ok) =====")
        if failures:
            # Raise AFTER the wave with ALL failures named — never leave a later wave
            # running against incomplete upstream data from a failed earlier wave.
            detail = "; ".join(f"{spec.name}: {err}" for spec, err in failures)
            raise RuntimeError(
                f"[ordm] generate_all: {len(failures)} generator(s) failed in wave {i}: "
                f"{detail}")
    print("[ordm] generate_all complete.")


if __name__ == "__main__":
    main()
