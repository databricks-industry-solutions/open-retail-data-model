"""Pin tools/changed_domains.py — the lean per-PR CI gate's changed-domain detector.

A PR's changed files map to the domain/package LABELS the gate deploys (design/59): the
directory directly under canonical-core/ or outcome-packages/. Paths outside those two
roots (docs, CI, tools, tests) map to nothing, so a docs-only PR yields an empty set and
the gate no-ops. conftest.py puts the repo root on sys.path.
"""
from tools.changed_domains import changed_domains


def test_core_and_outcome_paths_map_to_labels():
    paths = [
        "canonical-core/customer/tables/profile.sql",
        "canonical-core/customer/comments.sql",              # same label, deduped
        "outcome-packages/unified-customer-view/gold/g.sql",
    ]
    assert changed_domains(paths) == ["customer", "unified-customer-view"]


def test_paths_outside_the_two_roots_are_ignored():
    paths = [
        "docs/foo.md", "README.md", ".github/workflows/x.yml",
        "tools/apply_model_ddl.py", "tests/test_x.py", "explorer/public/model.json",
    ]
    assert changed_domains(paths) == []          # docs/CI-only PR -> empty -> gate no-ops


def test_multi_domain_pr_yields_multiple_sorted_labels():
    paths = [
        "outcome-packages/commerce-media-networks/tables/ad_group.sql",
        "canonical-core/interaction/tables/touchpoint.sql",
        "canonical-core/marketing/relationships.sql",
    ]
    assert changed_domains(paths) == ["commerce-media-networks", "interaction", "marketing"]


def test_dedup_and_sorted():
    paths = ["canonical-core/store/tables/store.sql",
             "canonical-core/store/checks.sql",
             "canonical-core/product/tables/product.sql"]
    assert changed_domains(paths) == ["product", "store"]


def test_empty_and_blank_inputs():
    assert changed_domains([]) == []
    assert changed_domains(["", "  ", "\n"]) == []


def test_root_file_without_a_label_is_ignored():
    # a file directly in the root (no <label>/ segment) is not a domain change
    assert changed_domains(["canonical-core/README.md", "outcome-packages/"]) == []


# ---- integration seam (AI review #108 H1): every label changed_domains emits must be
# accepted by ALL THREE consumers -- apply --domains, generate_all --include, DQ --domains.
# The gate feeds one changed-domains list to all three; a label accepted by two but rejected
# by the third (e.g. actionable-customer-understanding -> generate_all) hard-fails the gate.

def _every_real_label():
    """Every real domain/package directory label, from the two roots on disk."""
    import glob, os
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    labels = []
    for root in ("canonical-core", "outcome-packages"):
        for p in glob.glob(os.path.join(repo, root, "*")):
            if os.path.isdir(p):
                labels.append(os.path.basename(p))
    return sorted(labels)


def test_every_changed_domain_label_is_accepted_by_all_three_tools():
    """No label a PR can produce may raise in any of the three scoped tools. Packages whose
    directory name differs from the generator/schema key (ACU, promote-with-purpose) or that
    have no generator at all (unified-customer-view) must resolve, not ValueError (H1)."""
    import sys, os
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    sys.path.insert(0, os.path.join(repo, "runtime", "synthetic-data", "generators"))
    from _registry import GENERATORS, select
    from tools.apply_model_ddl import _effective_domain_filter

    for label in _every_real_label():
        # 1. generate_all --include (the seam H1 broke): must NOT raise.
        select(GENERATORS, label)
        # 2. apply --domains: resolves to a non-empty filter set (label + any deps/core).
        f = _effective_domain_filter(label)
        assert f and label in f, f"apply --domains dropped {label}"
        # 3. DQ --domains uses the same dir label as its discover() filter_set -> trivially
        #    the label itself; assert it is a real dir (discover would find its checks.sql if any).
        assert label in _every_real_label()
