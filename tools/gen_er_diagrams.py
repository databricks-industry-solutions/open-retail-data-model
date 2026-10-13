"""Generate ER diagrams (Mermaid source + DBML) for every ORDM unit and inject a
<picture> block into each folder README. SVGs are rendered from the .mmd by a
separate step (tools/render_diagrams.sh); this tool writes the text artifacts.
  python tools/gen_er_diagrams.py --write   # regenerate .mmd/.dbml + README <picture>
  python tools/gen_er_diagrams.py --check   # exit 1 if any text artifact is stale
Sibling of tools/gen_conformance_matrix.py."""
from __future__ import annotations
import argparse, os, sys

# Make the repo root importable when the script is run directly
# (python tools/gen_er_diagrams.py) rather than as a module.
_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

from tools.ordm_ddl.discovery import UnitDiscovery
from tools.ordm_ddl.parser import DdlParser
from tools.ordm_ddl.emitters.dbml import DbmlEmitter
from tools.ordm_ddl.emitters.mermaid import MermaidEmitter

START, END = "<!-- ORDM:ERD:START -->", "<!-- ORDM:ERD:END -->"

def _picture(name: str) -> str:
    return (f"{START}\n"
            f"<picture>\n"
            f'  <source media="(prefers-color-scheme: dark)" srcset="diagrams/{name}.dark.svg">\n'
            f'  <img alt="{name} — entity relationships (ORDM)" src="diagrams/{name}.light.svg">\n'
            f"</picture>\n\n"
            f"<sub>Generated from the DDL · "
            f'<a href="diagrams/{name}.light.svg">full SVG</a> · '
            f'Mermaid <a href="diagrams/{name}.light.mmd">light</a>/'
            f'<a href="diagrams/{name}.dark.mmd">dark</a> · '
            f'<a href="diagrams/{name}.dbml">DBML</a></sub>\n'
            f"{END}\n")

def _placeholder() -> str:
    # Empty stub package (no tables yet): a blank SVG reads as broken on the folder
    # page, so show a note instead of a <picture> (#53 M2).
    return (f"{START}\n"
            f"_No entities yet — the ER diagram appears once this package has tables._\n"
            f"{END}\n")

def _inject(readme: str, block: str) -> str:
    if START in readme and END in readme:
        before = readme.split(START)[0]
        after = readme.split(END, 1)[1]
        # _picture already ends with "{END}\n"; strip the one newline the
        # previous write left after END so the replacement is idempotent.
        if after.startswith("\n"):
            after = after[1:]
        return before + block + after
    return readme.rstrip() + "\n\n## Entity relationships\n\n" + block

def _text_artifacts(unit) -> dict:
    ddir = os.path.join(unit.dir, "diagrams")
    mer, dbml = MermaidEmitter(), DbmlEmitter()
    return {
        os.path.join(ddir, f"{unit.name}.light.mmd"): mer.emit(unit, theme="light"),
        os.path.join(ddir, f"{unit.name}.dark.mmd"):  mer.emit(unit, theme="dark"),
        os.path.join(ddir, f"{unit.name}.dbml"):      dbml.emit(unit),
    }

def build(write: bool):
    """Regenerate the text artifacts. Returns (changed, failures, expected_paths)."""
    parser = DdlParser()
    changed = False
    failures = []
    expected = set()
    for unit_dir in UnitDiscovery().find(None):
        unit_name = os.path.basename(unit_dir)
        try:
            unit = parser.parse_unit(unit_dir)
            readme_path = os.path.join(unit_dir, "README.md")
            readme = open(readme_path, encoding="utf-8").read() if os.path.exists(readme_path) else f"# {unit.name}\n"
            if unit.tables:
                arts = _text_artifacts(unit)
                arts[readme_path] = _inject(readme, _picture(unit.name))
                expected.update(os.path.abspath(p) for p in arts if p.endswith((".mmd", ".dbml")))
            else:
                # Empty stub package (no tables yet): a blank SVG reads as broken on the
                # folder page, so emit a placeholder note and no diagram artifacts (#53 M2).
                # Its stale .mmd/.dbml/.svg (if any) are cleaned up as orphans on --write.
                arts = {readme_path: _inject(readme, _placeholder())}
            for path, content in arts.items():
                have = open(path, encoding="utf-8").read() if os.path.exists(path) else None
                if have != content:
                    changed = True
                    if write:
                        os.makedirs(os.path.dirname(path), exist_ok=True)
                        with open(path, "w", encoding="utf-8") as fh:
                            fh.write(content)
        except Exception as exc:  # a parser regression must FAIL the gate, not warn (#53 M2)
            failures.append((unit_name, exc))
            print(f"::error::failed to process unit '{unit_name}': {exc}", file=sys.stderr)
    return changed, failures, expected

def _orphans(expected: set) -> list:
    """Per-unit .mmd/.dbml diagram artifacts on disk that no current unit generates —
    e.g. left behind by a deleted/renamed unit. Excludes the hand-authored
    docs/diagrams/ overview. (#53 M2)"""
    import glob
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    orph = []
    for base in ("canonical-core", "outcome-packages"):
        for p in glob.glob(os.path.join(root, base, "**", "diagrams", "*"), recursive=True):
            if p.endswith((".mmd", ".dbml")) and os.path.abspath(p) not in expected:
                orph.append(p)
    return sorted(orph)

def main() -> int:
    ap = argparse.ArgumentParser(description="Generate ORDM ER diagrams (Mermaid + DBML).")
    ap.add_argument("--check", action="store_true", help="exit 1 if artifacts are stale/orphaned")
    ap.add_argument("--write", action="store_true", help="regenerate artifacts + README blocks")
    args = ap.parse_args()
    changed, failures, expected = build(write=args.write)
    rc = 0
    if failures:
        print(f"::error::{len(failures)} unit(s) failed to process — see errors above.", file=sys.stderr)
        rc = 1
    orphans = _orphans(expected)
    if orphans and args.write:
        # On --write, reconcile the tree: delete the stale .mmd/.dbml, and for a .mmd
        # also its rendered .svg sibling (e.g. left by a unit that lost its last table — #53 M2).
        for o in orphans:
            to_remove = [o] + ([o[:-len(".mmd")] + ".svg"] if o.endswith(".mmd") else [])
            for p in to_remove:
                if os.path.exists(p):
                    os.remove(p)
            print(f"removed orphaned diagram artifact: {os.path.relpath(o, os.getcwd())}")
    elif orphans:
        print("::error::orphaned diagram artifacts (no current unit generates them; run --write to remove):", file=sys.stderr)
        for o in orphans:
            print(f"  {o}", file=sys.stderr)
        rc = 1
    if args.check and changed:
        print("ER diagrams are stale. Run: python tools/gen_er_diagrams.py --write")
        rc = 1
    return rc

if __name__ == "__main__":
    sys.exit(main())
