"""Guard: every link the explorer's model.json renders must resolve to a file
actually staged under explorer/public/, so the deployed site serves it instead
of dead-ending on the SPA fallback.

This is the regression net for the dead Contract/Glossary links: model.json
emits contract_path / glossary_path, the panel renders them as links, and
tools/gen_model_json.py stages the referenced files into explorer/public/ under
the same relative path. If any emitted path has no staged file, the link is
dead — fail here rather than shipping it.
"""
import filecmp
import json
import os

import pytest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PUBLIC = os.path.join(REPO_ROOT, "explorer", "public")
MODEL_JSON = os.path.join(PUBLIC, "model.json")


def _linked_paths():
    with open(MODEL_JSON, encoding="utf-8") as fh:
        model = json.load(fh)
    pairs = []
    for unit in model["units"]:
        for key in ("contract_path", "glossary_path"):
            path = unit.get(key)
            if path:
                pairs.append((unit["name"], key, path))
    return pairs


def test_model_json_exists():
    assert os.path.exists(MODEL_JSON), "run: python tools/gen_model_json.py --write"


def test_every_linked_path_is_staged_under_public():
    missing = []
    for name, key, path in _linked_paths():
        # Links are repo-relative; the served copy lives under explorer/public/.
        staged = os.path.join(PUBLIC, path)
        if not os.path.isfile(staged):
            missing.append(f"{name}.{key} -> {path}")
    assert not missing, (
        "explorer/public/ is missing staged files for these model.json links "
        "(run: python tools/gen_model_json.py --write): " + ", ".join(missing)
    )


def test_staged_files_match_their_source_byte_for_byte():
    """Content parity, not just existence: a staged public copy that has drifted
    from its repo-root source (an edited contract/glossary that was not re-staged)
    must fail HERE, not only in the CI `gen_model_json.py --check` byte comparison.
    """
    drifted = []
    for name, key, path in _linked_paths():
        source = os.path.join(REPO_ROOT, path)
        staged = os.path.join(PUBLIC, path)
        if not (os.path.isfile(source) and os.path.isfile(staged)):
            continue  # existence is the sibling test's job
        if not filecmp.cmp(source, staged, shallow=False):
            drifted.append(f"{name}.{key} -> {path}")
    assert not drifted, (
        "staged explorer/public/ copies have drifted from their repo-root source "
        "(run: python tools/gen_model_json.py --write): " + ", ".join(drifted)
    )


def test_at_least_the_expected_link_kinds_are_present():
    # Sanity: the model does link contracts and glossaries (guards against an
    # empty-list false pass if link emission silently breaks).
    kinds = {key for _, key, _ in _linked_paths()}
    assert "contract_path" in kinds
    assert "glossary_path" in kinds


def test_staged_paths_stay_inside_public():
    # Defensive: a link path must never escape the served tree (e.g. via "..").
    for name, key, path in _linked_paths():
        staged = os.path.realpath(os.path.join(PUBLIC, path))
        assert staged.startswith(os.path.realpath(PUBLIC) + os.sep), (
            f"{name}.{key} escapes explorer/public/: {path}"
        )
