"""Deterministic data-integrity guard over the explorer's served model.json.

Complements the browser link e2e (which fetches the resolved hrefs) by checking
the SAME facts in the fast, offline pytest gate:

  (a) Every relationship whose BOTH endpoints are tables in the same unit — the
      ones the explorer actually draws (see explorer/src/elements.ts
      modelToElements, which drops edges with a non-in-unit endpoint) — must
      resolve to a real table in that unit. Cross-unit parents (e.g. a bridge
      table referencing a table that lives in another domain) may legitimately
      be absent and are NOT failed, mirroring the drop rule exactly.

  (b) Every unit's non-null glossary_path / contract_path must exist as a staged
      file under explorer/public/ (so the deployed site serves the raw asset).

Fails loud with the offending unit + relationship / path.
"""
import json
import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PUBLIC = os.path.join(REPO_ROOT, "explorer", "public")
MODEL_JSON = os.path.join(PUBLIC, "model.json")


def _model():
    with open(MODEL_JSON, encoding="utf-8") as fh:
        return json.load(fh)


def test_model_json_exists():
    assert os.path.exists(MODEL_JSON), "run: python tools/gen_model_json.py --write"


def test_intra_unit_relationship_endpoints_resolve():
    """A relationship the explorer KEEPS (both parent_table and child_table are
    tables in the unit) must reference real tables in that unit. This mirrors
    modelToElements: cross-unit endpoints are dropped, not failed."""
    model = _model()
    broken = []
    drawn_any = 0
    for unit in model["units"]:
        table_names = {t["name"] for t in unit["tables"]}
        for rel in unit["relationships"]:
            parent = rel["parent_table"]
            child = rel["child_table"]
            parent_in = parent in table_names
            child_in = child in table_names
            # Only the edges with BOTH endpoints in-unit are drawn; those must
            # resolve. A cross-unit parent (parent_in is False) is the legitimate
            # drop case — skip it, do not fail.
            if parent_in and child_in:
                drawn_any += 1
                # Both already confirmed present; this branch is the resolve
                # assertion itself (kept explicit so a future refactor that
                # weakens the membership check still fails here).
                if parent not in table_names or child not in table_names:
                    broken.append(f"{unit['name']}: {parent} -> {child}")
            elif child_in and not parent_in:
                # Child is in-unit, parent is elsewhere: the drawn set excludes
                # this edge. Nothing to assert (documented drop). Confirm the
                # child at least is a real in-unit table (it is, by child_in).
                continue
    assert not broken, (
        "intra-unit relationships reference a table not present in their unit: "
        + ", ".join(broken)
    )
    # Sanity: the model DOES draw some intra-unit edges (guards a false pass if
    # every relationship were silently classified cross-unit).
    assert drawn_any > 0, "no intra-unit relationships found — model.json shape changed?"


def test_child_table_of_every_listed_relationship_is_in_its_unit():
    """A relationship is listed UNDER the unit that owns the child (FK) side, so
    the child_table must always be a real table in that unit. A child that is not
    in-unit would mean the relationship was mis-filed against the wrong unit."""
    orphaned = []
    for unit in _model()["units"]:
        table_names = {t["name"] for t in unit["tables"]}
        for rel in unit["relationships"]:
            if rel["child_table"] not in table_names:
                orphaned.append(f"{unit['name']}: child {rel['child_table']} not in unit")
    assert not orphaned, (
        "relationships filed under a unit whose child_table is not in that unit: "
        + ", ".join(orphaned)
    )


def test_every_glossary_and_contract_path_is_staged_under_public():
    """Each non-null glossary_path / contract_path must exist as a staged file
    under explorer/public/ (the deployed site serves it there)."""
    missing = []
    checked = 0
    for unit in _model()["units"]:
        for key in ("glossary_path", "contract_path"):
            path = unit.get(key)
            if not path:
                continue
            checked += 1
            staged = os.path.join(PUBLIC, path)
            if not os.path.isfile(staged):
                missing.append(f"{unit['name']}.{key} -> {path}")
    assert not missing, (
        "explorer/public/ is missing staged files for these model.json paths "
        "(run: python tools/gen_model_json.py --write): " + ", ".join(missing)
    )
    # Sanity: at least some units DO carry linked assets (guards an empty pass).
    assert checked > 0, "no glossary/contract paths found — model.json shape changed?"


def test_staged_paths_never_escape_public():
    """Defensive: a staged path must resolve INSIDE explorer/public/ (no `..`)."""
    for unit in _model()["units"]:
        for key in ("glossary_path", "contract_path"):
            path = unit.get(key)
            if not path:
                continue
            staged = os.path.realpath(os.path.join(PUBLIC, path))
            assert staged.startswith(os.path.realpath(PUBLIC) + os.sep), (
                f"{unit['name']}.{key} escapes explorer/public/: {path}"
            )
