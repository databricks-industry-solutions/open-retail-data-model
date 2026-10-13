"""The CI shard split (tests/conftest.py, ORDM_TEST_SHARD) must partition the suite: every
test the parallel shards run lands in exactly one shard. A refactor that dropped a file from
every shard would otherwise lose coverage while all four shards stay green."""
import os
import subprocess
import sys

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ARGS = [sys.executable, "-m", "pytest", "tests", "--ignore=tests/standards", "-m", "not writes_repo",
        "--co", "-q", "-p", "no:cacheprovider", "-p", "no:xdist"]


def _collect(shard=None):
    env = {k: v for k, v in os.environ.items() if k != "ORDM_TEST_SHARD"}
    if shard:
        env["ORDM_TEST_SHARD"] = shard
    out = subprocess.run(ARGS, cwd=ROOT, env=env, capture_output=True, text=True, check=True).stdout
    return {line for line in out.splitlines() if "::" in line}


def _shard_count():
    # The count CI actually runs: the `test` job's matrix in the workflow.
    wf = yaml.safe_load(open(os.path.join(ROOT, ".github", "workflows", "databricks-ci.yml")))
    job = wf["jobs"]["test"]
    shards = job["strategy"]["matrix"]["shard"]
    assert shards == list(range(1, len(shards) + 1))
    step = next(s for s in job["steps"] if "ORDM_TEST_SHARD" in (s.get("env") or {}))
    assert step["env"]["ORDM_TEST_SHARD"].endswith(f"/{len(shards)}"), "ORDM_TEST_SHARD disagrees with the matrix"
    assert job["name"].endswith(f"/{len(shards)})"), "the job name disagrees with the matrix"
    return len(shards)


def test_shards_partition_the_parallel_suite():
    n = _shard_count()
    everything = _collect()
    shards = [_collect(f"{k}/{n}") for k in range(1, n + 1)]
    assert everything and all(shards), "every shard must get tests (an empty one exits 5)"
    for i in range(n):
        for j in range(i + 1, n):
            assert not shards[i] & shards[j], f"shards {i + 1} and {j + 1} overlap"
    assert set().union(*shards) == everything


def test_split_does_not_read_the_runner_core_count():
    # Each matrix job computes the split on its own, so it must be a pure function of the
    # collection and the committed timings: reading the runtime worker or core count would
    # let runners of different sizes disagree and silently drop or double-run files. The
    # split uses the constant _WORKERS_PER_SHARD instead.
    src = open(os.path.join(ROOT, "tests", "conftest.py")).read()
    for runtime in ("cpu_count", "PYTEST_XDIST_WORKER_COUNT", "numprocesses", "sched_getaffinity"):
        assert runtime not in src, f"tests/conftest.py reads {runtime}; keep the shard split runner-independent"
