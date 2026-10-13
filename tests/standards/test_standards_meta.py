"""Meta-test: bind the rules registry, the CI checks, and the standard together.

This is the anti-drift lock. It fails if:
  - an enforced rule has no implementing check (prose claims enforcement, code does not back it),
  - a check maps to a rule that is not marked enforced (orphan or mis-tagged check),
  - the conformance matrix in the standard is stale versus the registry.

So you cannot change the rules in one place and forget the others.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
RULES = yaml.safe_load((REPO_ROOT / "standards" / "rules.yaml").read_text())

# import the conformance module and the matrix generator by path
sys.path.insert(0, str(REPO_ROOT / "tools"))
import gen_conformance_matrix as gen  # noqa: E402


def _load_conformance_module():
    path = REPO_ROOT / "tests" / "standards" / "test_standards_conformance.py"
    spec = importlib.util.spec_from_file_location("ordm_conformance", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_every_enforced_rule_has_a_test():
    conf = _load_conformance_module()
    enforced = [r for r in RULES["rules"] if r.get("status") == "enforced"]
    problems = []
    for r in enforced:
        test = r.get("test")
        if not test:
            problems.append(f"{r['id']}: status enforced but no `test` in the registry")
            continue
        func = test.split("::")[-1]
        if not hasattr(conf, func):
            problems.append(f"{r['id']}: `test` names {func}, which does not exist in the conformance module")
        if conf.ENFORCES.get(func) != r["id"]:
            problems.append(f"{r['id']}: {func} is not mapped to this rule in ENFORCES")
    assert not problems, "Enforced rules without a backing check:\n" + "\n".join(problems)


def test_no_orphan_checks():
    conf = _load_conformance_module()
    enforced_ids = {r["id"] for r in RULES["rules"] if r.get("status") == "enforced"}
    problems = []
    for func, rule_id in conf.ENFORCES.items():
        if rule_id not in enforced_ids:
            problems.append(f"{func} enforces {rule_id}, which is not an enforced rule in the registry")
    assert not problems, "Checks that do not map to an enforced rule:\n" + "\n".join(problems)


def test_known_exceptions_reference_real_rules():
    ids = {r["id"] for r in RULES["rules"]}
    problems = [
        e for e in (RULES.get("known_exceptions") or []) if e.get("rule") not in ids
    ]
    assert not problems, f"known_exceptions reference unknown rule ids: {problems}"


def test_conformance_matrix_in_standard_is_current():
    text = gen.STANDARD_PATH.read_text()
    expected = gen.render_matrix(RULES).strip()
    actual = gen.current_block(text).strip()
    assert actual == expected, (
        "The conformance matrix in docs/data-model-standards.md is stale.\n"
        "Regenerate it with: python tools/gen_conformance_matrix.py --write"
    )
