#!/usr/bin/env python3
"""Freshness check for the committed diagram SVGs (AI review #53 M1).

The `.svg` images are non-deterministic *rendered snapshots* (mermaid's erDiagram edge
routing isn't byte-reproducible — see docs/er-diagrams.md), so this does NOT re-render or
byte-compare them: `render_diagrams.sh` stamps each `.mmd`'s sha into its `.svg`, and this
compares that stamp to the current `.mmd` sha (deterministic, no mermaid-cli). Refresh
stale SVGs with `tools/render_diagrams.sh`.

Two modes: the default run WARNS on a stale/missing SVG and exits 0 (advisory); `--check`
FAILS (exit 1). `make check-svg` and the CI drift guard use `--check` to gate forks and
push-to-main, so a stale SVG cannot merge on the paths that have no auto-render.
"""
from __future__ import annotations
import glob
import hashlib
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def main() -> int:
    # --check: fail (exit 1) on any stale/missing SVG - a hard drift gate. The
    # comparison is a deterministic .mmd-sha stamp, so gating on it is safe despite
    # mermaid's render being non-byte-reproducible. Without it, stays advisory (exit 0).
    strict = "--check" in sys.argv[1:]
    stale: list[tuple[str, str]] = []
    for base in ("docs/diagrams", "canonical-core", "outcome-packages"):
        for mmd in sorted(glob.glob(os.path.join(ROOT, base, "**", "*.mmd"), recursive=True)):
            svg = mmd[:-4] + ".svg"
            current = hashlib.sha256(open(mmd, "rb").read()).hexdigest()
            if not os.path.exists(svg):
                stale.append((mmd, "no rendered .svg"))
                continue
            m = re.search(r"ordm-mmd-sha:([0-9a-f]{64})", open(svg, encoding="utf-8").read())
            if not m:
                stale.append((mmd, ".svg has no embedded source sha"))
            elif m.group(1) != current:
                stale.append((mmd, ".svg is stale — re-render via tools/render_diagrams.sh"))
    level = "error" if strict else "warning"
    for mmd, why in stale:
        print(f"::{level} file={os.path.relpath(mmd, ROOT)}::{why}")
    if stale:
        print(f"{len(stale)} stale/missing SVG snapshot(s)."
              + (" Run tools/render_diagrams.sh (make regen-svg) and commit." if strict else ""))
        return 1 if strict else 0
    print("All diagram SVGs are fresh vs their .mmd source.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
