"""Guard: every link the explorer's model.json renders must resolve to a file
actually staged under explorer/public/, so the deployed site serves it instead
of dead-ending on the SPA fallback.

This is the regression net for the dead Contract/Glossary links: model.json
emits contract_path / glossary_path, the panel renders them as links, and
tools/gen_model_json.py stages the referenced files into explorer/public/ under
the same relative path. If any emitted path has no staged file, the link is
dead — fail here rather than shipping it.
"""
import json
import os
import sys

import pytest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from tools import gen_model_json  # noqa: E402
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
    The expected bytes are the source as staging writes it: contracts verbatim,
    glossaries with links out of the site made absolute (gen_model_json.staged_bytes).
    """
    staged_set = {path for _, _, path in _linked_paths()}
    drifted = []
    for name, key, path in _linked_paths():
        source = os.path.join(REPO_ROOT, path)
        staged = os.path.join(PUBLIC, path)
        if not (os.path.isfile(source) and os.path.isfile(staged)):
            continue  # existence is the sibling test's job
        with open(staged, "rb") as fh:
            if fh.read() != gen_model_json.staged_bytes(source, path, staged_set):
                drifted.append(f"{name}.{key} -> {path}")
    assert not drifted, (
        "staged explorer/public/ copies have drifted from their repo-root source "
        "(run: python tools/gen_model_json.py --write): " + ", ".join(drifted)
    )


def test_relative_links_in_staged_glossaries_resolve_on_the_site():
    """A relative link inside a staged glossary must point at another staged file:
    resolved against explorer/public/, anything else names a file the site does not
    carry. Links to such repo files are rewritten to absolute source-repo URLs at
    staging. Only inline [text](target) links are checked (see gen_model_json._MD_LINK)."""
    broken = []
    for name, key, path in _linked_paths():
        if key != "glossary_path":
            continue
        staged = os.path.join(PUBLIC, path)
        if not os.path.isfile(staged):
            continue
        text = open(staged, encoding="utf-8").read()
        for m in gen_model_json._MD_LINK.finditer(text):
            target = m.group(2)
            if gen_model_json.is_external_target(target):
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(staged), target.split("#")[0]))
            if not os.path.exists(resolved):
                broken.append(f"{path}: {target}")
    assert not broken, "staged glossary links to files the site does not serve:\n  " + "\n  ".join(broken)


def test_staging_rewrites_only_links_that_leave_the_site(tmp_path, monkeypatch):
    src = tmp_path / "canonical-core" / "x" / "glossary.md"
    src.parent.mkdir(parents=True)
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "standards.md").write_text("s")
    (tmp_path / "canonical-core" / "y").mkdir()
    (tmp_path / "canonical-core" / "y" / "glossary.md").write_text("g")
    src.write_text("[a](../../docs/standards.md#rule) [b](../y/glossary.md) [c](#local) "
                   "[d](https://example.com/x) [e](../../missing.md) [f](../../docs/)\n")
    monkeypatch.setattr(gen_model_json, "ROOT", str(tmp_path))
    out = gen_model_json.staged_bytes(str(src), "canonical-core/x/glossary.md",
                                      {"canonical-core/x/glossary.md", "canonical-core/y/glossary.md"}).decode()
    blob = gen_model_json.SOURCE_TREE_URL.replace("/tree/", "/blob/", 1)
    tree = gen_model_json.SOURCE_TREE_URL
    assert out == (f"[a]({blob}/docs/standards.md#rule) [b](../y/glossary.md) [c](#local) "
                   f"[d](https://example.com/x) [e](../../missing.md) [f]({tree}/docs)\n")


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
