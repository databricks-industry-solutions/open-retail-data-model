# ============================================================
# ORDM · CI · changed-domain detector
# ============================================================
# Given the files a PR changed, return the set of domain/package LABELS touched --
# the directory name directly under canonical-core/ or outcome-packages/. The lean
# per-PR CI gate (design/59) feeds this comma-separated list to apply_model_ddl
# --domains, generate_all --include, and run_checks --domains, so a PR deploys only
# what it changed. A change outside those two roots (docs, CI, tools, tests) maps to
# NO label, so a docs-only PR yields an empty set and the gate no-ops (green, fast).
#
# Pure stdlib, no git required in-process: paths come from `git diff --name-only`
# (the workflow runs that) piped on stdin, or from `--paths a,b,c`, or the function
# arg. This keeps it unit-testable without a live repo.
#
# Usage:
#   git diff --name-only origin/main...HEAD | python3 tools/changed_domains.py
#   python3 tools/changed_domains.py --paths canonical-core/customer/tables/x.sql
#   python3 tools/changed_domains.py --json     # {"domains": [...], "any": bool}
# ============================================================
from __future__ import annotations

import argparse
import json
import sys

# The two roots whose immediate child directory is a domain/package label.
_ROOTS = ("canonical-core", "outcome-packages")


def changed_domains(paths):
    """Return the sorted, de-duplicated list of domain/package labels among `paths`.

    A label is the directory name directly under canonical-core/ or outcome-packages/
    (e.g. 'canonical-core/customer/tables/x.sql' -> 'customer';
    'outcome-packages/unified-customer-view/gold/g.sql' -> 'unified-customer-view').
    Paths under neither root contribute nothing.

    Intentional (AI review #108 m1): ANY file under a domain dir selects that domain, including
    a docs-only edit (e.g. canonical-core/customer/glossary.md) or a comment-only .sql tweak. The
    lean gate is fast and advisory, so over-selecting is the safe default -- a comment change can
    still break the DDL parse/regen, and skipping it risks a false green. We deliberately do NOT
    filter by file type here."""
    labels = set()
    for raw in paths:
        p = raw.strip().strip('"')
        if not p:
            continue
        parts = p.replace("\\", "/").split("/")
        # need a NON-EMPTY child dir AND a path segment beyond it (a file lives under the
        # label dir); 'outcome-packages/' or 'canonical-core/README.md' are not domain changes.
        if len(parts) >= 3 and parts[0] in _ROOTS and parts[1]:
            labels.add(parts[1])
    return sorted(labels)


def _read_paths(args):
    if args.paths:
        return [p for p in args.paths.split(",")]
    # else read newline-separated paths from stdin (git diff --name-only)
    return sys.stdin.read().splitlines()


def main():
    ap = argparse.ArgumentParser(description="Map changed file paths to ORDM domain labels.")
    ap.add_argument("--paths", help="Comma-separated paths (else read newline-separated from stdin).")
    ap.add_argument("--json", action="store_true",
                    help="Emit {'domains': [...], 'any': bool} instead of a bare CSV.")
    args = ap.parse_args()

    domains = changed_domains(_read_paths(args))
    if args.json:
        print(json.dumps({"domains": domains, "any": bool(domains)}))
    else:
        # Bare comma-separated list (empty line = no model domains changed). The workflow
        # captures this and no-ops the deploy gate when it is empty.
        print(",".join(domains))


if __name__ == "__main__":
    main()
