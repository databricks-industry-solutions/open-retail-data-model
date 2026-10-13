import os
import sys

import pytest

# Make the repo root importable so tests can use the shared resolver
# (tools.ordm_config) — the single source of truth for ${*_schema} tokens.
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)


@pytest.fixture(scope="session")
def spark():
    """A Spark session for executing the real gold SQL against temp-view fixtures.

    Reuse the active session when pytest runs on Databricks; otherwise create a
    local session. The fixture owns and stops only the local session. Skips
    rather than fails only when neither execution mode is available.
    """
    pytest.importorskip("pyspark")
    from pyspark.sql import SparkSession

    session = SparkSession.getActiveSession()
    owns_session = session is None
    if owns_session:
        try:
            session = (
                SparkSession.builder
                .master("local[1]")
                .appName("ordm-sql-tests")
                .config("spark.ui.enabled", "false")
                .config("spark.sql.shuffle.partitions", "1")
                .config("spark.sql.session.timeZone", "UTC")
                .getOrCreate()
            )
        except Exception as exc:
            pytest.skip(f"local Spark unavailable: {type(exc).__name__}: {exc}")

    session.conf.set("spark.sql.shuffle.partitions", "1")
    session.conf.set("spark.sql.session.timeZone", "UTC")
    if owns_session:
        session.sparkContext.setLogLevel("ERROR")
    yield session
    if owns_session:
        session.stop()


def pytest_configure(config):
    config.addinivalue_line(
        "markers",
        "writes_repo: rewrites or adds files in the checkout (a generator --write round-trip); "
        "CI runs these serially, outside the parallel workers, so no other test reads a file "
        "while it is being rewritten",
    )


# Measured seconds per test FILE from CI (tools/ci_test_durations.py turns the shards'
# JUnit reports into this file). Shards are balanced on it; a file it does not list yet
# falls back to an estimate: a test that runs SQL on the local Spark session costs far
# more than a static (parse / file) test.
_DURATIONS_FILE = os.path.join(os.path.dirname(__file__), "ci_test_durations.json")
_SPARK_TEST_SECONDS = 2.0
_STATIC_TEST_SECONDS = 0.25
# Shard 1 also runs the writes_repo tests serially after its parallel run. Per-test seconds
# are summed across a shard's xdist workers, so that serial wall time weighs (workers) times
# against shard 1's share. A CONSTANT (the 2-vCPU runner's worker count), not the runtime
# worker count: every shard must compute the same split whatever runner it lands on.
_WORKERS_PER_SHARD = 2
# On push to main shard 1 also runs the drift guard (`make check-*`, about 2 minutes); every
# matrix job of one run sees the same event, so the split stays shared. (Fork PRs run it too,
# but the event name does not tell a fork from a same-repo PR, so they are not counted.)
_DRIFT_GUARD_SECONDS = 120.0


def _measured():
    """(seconds per test file, serial seconds of the writes_repo step) from CI, or empty."""
    try:
        import json
        with open(_DURATIONS_FILE, encoding="utf-8") as fh:
            data = json.load(fh)
        files = {k: float(v) for k, v in (data.get("files") or {}).items()}
        return files, float(data.get("serial_seconds") or 0)
    except (OSError, ValueError):
        return {}, 0.0


def pytest_collection_modifyitems(config, items):
    """Group each file onto one xdist worker, and keep only this CI shard's tests when
    ORDM_TEST_SHARD="<k>/<n>" is set (1-based).

    Grouping (always, used by `--dist loadgroup`): every test of a file gets that file's
    xdist_group, so module fixtures and per-process caches are built once per file. (Spreading
    a heavy file over workers was tried: on 2 vCPUs the two Spark sessions contend and the
    file's total time doubles.)

    Sharding: whole test FILES go to one shard. Files are assigned greedily, slowest first, to
    the least-loaded WORKER SLOT (n shards x _WORKERS_PER_SHARD workers), so the slowest file
    gets a worker to itself and its shard's other worker an even share; shard = slot's shard.
    Costs are the measured CI seconds per file (tests/ci_test_durations.json), or an estimate
    for a file not measured yet; ties break on the path, so every shard (and every xdist
    worker inside it) computes the same split from the same collection. Unset (local runs),
    every test runs.
    """
    measured, serial_seconds = _measured()
    # xdist registers the xdist_group marker; without it (e.g. the serial `-p no:xdist` step,
    # under --strict-markers) adding the marker would fail collection.
    grouping = config.pluginmanager.hasplugin("xdist")
    for item in items:
        if grouping and not item.get_closest_marker("xdist_group"):
            item.add_marker(pytest.mark.xdist_group(os.path.relpath(str(item.path), REPO_ROOT)))
    spec = os.environ.get("ORDM_TEST_SHARD", "").strip()
    if not spec:
        return
    try:
        k, n = (int(x) for x in spec.split("/"))
    except ValueError:
        raise pytest.UsageError(f"ORDM_TEST_SHARD={spec!r}: expected <k>/<n>, e.g. 2/4") from None
    if not 1 <= k <= n:
        raise pytest.UsageError(f"ORDM_TEST_SHARD={spec!r}: expected <k>/<n> with 1 <= k <= n")
    estimate = {}
    for item in items:
        if item.get_closest_marker("writes_repo"):
            continue  # never runs in the parallel shards (CI runs it serially in shard 1)
        rel = os.path.relpath(str(item.path), REPO_ROOT)
        spark = "spark" in getattr(item, "fixturenames", ())
        estimate[rel] = estimate.get(rel, 0.0) + (_SPARK_TEST_SECONDS if spark else _STATIC_TEST_SECONDS)
    cost = {rel: measured.get(rel, est) for rel, est in estimate.items()}
    w = _WORKERS_PER_SHARD
    slots, shard_of = [0.0] * (n * w), {}
    # Shard 1 runs its serial steps after its parallel run, so both of its worker slots start
    # with that time, capped below an even share so shard 1 always gets tests (an empty shard
    # would exit 5 and fail the job).
    serial = serial_seconds + (_DRIFT_GUARD_SECONDS if os.environ.get("GITHUB_EVENT_NAME") == "push" else 0.0)
    head_start = min(serial, 0.8 * sum(cost.values()) / (n * w))
    for i in range(w):
        slots[i] = head_start
    # Among equally loaded slots prefer the least-loaded SHARD, so the slowest files land on
    # different runners instead of competing for one runner's cores.
    shard_total = [sum(slots[s * w:(s + 1) * w]) for s in range(n)]
    for rel in sorted(cost, key=lambda r: (-cost[r], r)):
        target = min(range(n * w), key=lambda i: (slots[i], shard_total[i // w], i))
        shard_of[rel] = target // w
        slots[target] += cost[rel]
        shard_total[target // w] += cost[rel]
    keep, drop = [], []
    for item in items:
        rel = os.path.relpath(str(item.path), REPO_ROOT)
        # writes_repo tests: the parallel run deselects them with -m; the serial step runs
        # them without ORDM_TEST_SHARD
        (keep if shard_of.get(rel, 0) == k - 1 else drop).append(item)
    if drop:
        config.hook.pytest_deselected(items=drop)
        items[:] = keep
    # xdist hands out file groups in collection order: put the slowest files first so a long
    # file starts at once instead of behind lighter ones (stable sort: a file's tests keep
    # their order).
    items.sort(key=lambda it: -cost.get(os.path.relpath(str(it.path), REPO_ROOT), 0.0))



_TRACKED_SNAPSHOT = None


def _repo_snapshot():
    """Tracked changes, plus untracked files under the generated trees, in the checkout.

    Compares `git status` lines, so it sees a file that BECOMES dirty or appears; a file that
    was already dirty at start and is rewritten again is not seen (CI checkouts are clean).
    """
    import subprocess
    proc = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=REPO_ROOT,
                          capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"warning: the checkout guard is off, `git status` failed: {proc.stderr.strip()}", file=sys.stderr)
    out = proc.stdout.splitlines()
    gen = ("explorer/public/", "contracts/")
    return {line for line in out if not line.startswith("??") or line[3:].startswith(gen)}


def pytest_sessionstart(session):
    # Guard for the parallel CI run (ORDM_TEST_SHARD set): a test that writes into the
    # checkout without the writes_repo marker would race with the tests that read those
    # files. Record the checkout state in the controller (not in each xdist worker).
    global _TRACKED_SNAPSHOT
    if os.environ.get("ORDM_TEST_SHARD") and not os.environ.get("PYTEST_XDIST_WORKER"):
        _TRACKED_SNAPSHOT = _repo_snapshot()


def pytest_sessionfinish(session, exitstatus):
    if _TRACKED_SNAPSHOT is None:
        return
    changed = sorted(_repo_snapshot() ^ _TRACKED_SNAPSHOT)
    if changed:
        session.config.get_terminal_writer().line(
            "error: the parallel test run changed the checkout; mark the test that writes these "
            "files @pytest.mark.writes_repo so CI runs it serially:\n  " + "\n  ".join(changed[:20]),
            red=True)
        session.exitstatus = 1
