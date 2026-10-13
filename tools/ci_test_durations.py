#!/usr/bin/env python3
"""Turn the CI shards' JUnit reports into tests/ci_test_durations.json (seconds per test file).

tests/conftest.py balances the `unit + spark tests` shards on these measured times, so a
shard is not overloaded with the slow Spark files. Refresh it when the shards drift apart:

  gh run download <ORDM CI run id> -p 'junit-*' -D /tmp/junit-<run id>
  python tools/ci_test_durations.py /tmp/junit-<run id>/*/*.xml [/tmp/junit-<other run id>/*/*.xml ...]

Per-file times vary up to about 2x between runs (the shard's two xdist workers contend for a
2-vCPU runner), so pass the reports of two or more runs: each run's reports sit in their own
directory (as `gh run download -D` lays them out), and the tool averages per file across the
runs that measured it.

A file the JSON does not list yet falls back to the estimate in tests/conftest.py. The
serial reports from shard 1 (junit-writes-repo.xml, junit-conformance-serial.xml) are not
per-file costs: those tests never run in the parallel shards. Their total is recorded as
`serial_seconds`, the extra work shard 1 does after its parallel run, so the balancer
gives shard 1 less to do.

Limit: a file runs on ONE xdist worker (an xdist_group per file), so the slowest file
(tests/test_foot_traffic.py, 300-550 s depending on the runner) is a floor on its shard's
wall time; the balancer gives it a worker of its own. Spreading such a file over workers was
tried and doubled its total time (two Spark sessions contending on 2 vCPUs); making the file
itself cheaper, or splitting it into two files, is what would lower the floor.
"""
import json
import os
import sys
import xml.etree.ElementTree as ET

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(REPO_ROOT, "tests", "ci_test_durations.json")


def _file_of(classname: str) -> str | None:
    """'tests.test_x.TestY' -> 'tests/test_x.py' (the longest dotted prefix that is a file)."""
    parts = classname.split(".")
    for i in range(len(parts), 0, -1):
        rel = os.path.join(*parts[:i]) + ".py"
        if os.path.exists(os.path.join(REPO_ROOT, rel)):
            return rel
    return None


def main(paths: list[str]) -> int:
    if not paths:
        print(__doc__)
        return 2
    # run directory (junit-<run id>/junit-<k>/<report>.xml -> junit-<run id>) -> totals
    runs: dict[str, dict] = {}
    for path in paths:
        run = os.path.dirname(os.path.dirname(os.path.abspath(path)))
        acc = runs.setdefault(run, {"files": {}, "serial": 0.0})
        cases = list(ET.parse(path).getroot().iter("testcase"))
        if "writes-repo" in os.path.basename(path) or "serial" in os.path.basename(path):
            acc["serial"] += sum(float(c.get("time") or 0) for c in cases)
            continue
        for case in cases:
            rel = _file_of(case.get("classname", ""))
            if rel:
                acc["files"][rel] = acc["files"].get(rel, 0.0) + float(case.get("time") or 0)
    seconds: dict[str, float] = {}
    for rel in {r for acc in runs.values() for r in acc["files"]}:
        vals = [acc["files"][rel] for acc in runs.values() if rel in acc["files"]]
        seconds[rel] = sum(vals) / len(vals)
    serials = [acc["serial"] for acc in runs.values() if acc["serial"]]
    serial = sum(serials) / len(serials) if serials else 0.0
    shard_reports = [p for p in paths if os.path.basename(p).startswith("junit-shard-")]
    if len(shard_reports) < 4 * len(runs):
        print(f"warning: {len(shard_reports)} junit-shard-*.xml report(s) among the inputs; the files of a "
              "missing shard drop out and fall back to estimates", file=sys.stderr)
    if not any("writes-repo" in os.path.basename(p) for p in paths):
        print("warning: no junit-writes-repo.xml among the inputs; serial_seconds will be 0 and "
              "shard 1 will be loaded as if it had no serial step", file=sys.stderr)
    data = {
        "generated_by": "tools/ci_test_durations.py",
        "serial_seconds": round(serial, 1),
        "files": {rel: round(seconds[rel], 1) for rel in sorted(seconds)},
    }
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    print(f"wrote {os.path.relpath(OUT, REPO_ROOT)}: {len(seconds)} files, {sum(seconds.values()):.0f}s total, "
          f"averaged over {len(runs)} run(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
