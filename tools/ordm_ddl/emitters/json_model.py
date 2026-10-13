from __future__ import annotations
import json
import os
import yaml
from .base import Emitter
from ..model import Unit, Table

# Repo root: two levels up from this file (tools/ordm_ddl/emitters/json_model.py)
_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

# The repo's GitHub tree root. Each unit's `source_url` (the explorer panel's GitHub
# link) is this plus the unit's repo-relative folder, so moving the repo is a one-line
# change here followed by `make regen`.
SOURCE_TREE_URL = "https://github.com/databricks-industry-solutions/open-retail-data-model/tree/main"

# Planning-tier use-case statuses (per-package use-cases.yaml). A single source
# of truth mirrored by the explorer's status styling.
_USE_CASE_STATUSES = frozenset({"blocked", "in-progress", "planned", "done"})


def _repo_rel(path: str) -> str:
    """Return a forward-slash repo-relative path, stripping the repo root prefix."""
    try:
        rel = os.path.relpath(path, _REPO_ROOT)
    except ValueError:
        # On Windows, relpath can fail across drives; fall back to basename path
        rel = path
    return rel.replace("\\", "/")


def _contract_path(unit_name: str) -> str | None:
    """Repo-relative path to a unit's ODCS contract, or None when it does not yet
    exist. The explorer only renders a Contract link when this is non-null, so a
    planned unit with no contract shows no dead link."""
    rel = f"contracts/odcs/{unit_name}.odcs.yaml"
    return rel if os.path.exists(os.path.join(_REPO_ROOT, rel)) else None


def _load_use_cases(unit_dir: str, gold_tables: frozenset[str] = frozenset(),
                    all_units: dict[str, frozenset[str]] | None = None) -> list[dict]:
    """Read a package's use-cases.yaml planning tier into [{name, status, tables, foreign_tables}].

    Empty list if the file is absent (the common case for core domains and for
    packages that have not declared any use cases yet). Order is preserved from
    the file, so the emitted JSON is deterministic. Owners are never read — the
    manifest carries names + status (+ an optional table mapping) only, by design.

    The optional per-use-case `tables:` list scopes which of the unit's gold
    tables serve a use case (absent = []). Tables can be local (in this unit) or
    cross-package references using syntax "package.table_name". Every listed name
    is VALIDATED: local tables against `gold_tables` (the unit's actual gold tables),
    and cross-package refs validated using `all_units`. A typo or a renamed table
    fails loud (mirrors the parser's no-silent-drops invariant) naming the file,
    use case, and bad table, so `--check` catches drift.

    Fails loud on a malformed manifest, an unknown status, or a `tables:` entry
    that is not a gold table in this unit or a valid cross-package reference,
    rather than silently dropping it.
    """
    if not unit_dir:
        return []
    path = os.path.join(unit_dir, "use-cases.yaml")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    raw = data.get("use_cases") or []
    if not isinstance(raw, list):
        raise ValueError(
            f"{_repo_rel(path)}: 'use_cases' must be a list, got {type(raw).__name__}"
        )
    out: list[dict] = []
    all_units = all_units or {}
    for i, entry in enumerate(raw):
        if not isinstance(entry, dict) or "name" not in entry or "status" not in entry:
            raise ValueError(
                f"{_repo_rel(path)}: use_cases[{i}] must be a mapping with 'name' and 'status'"
            )
        status = str(entry["status"])
        if status not in _USE_CASE_STATUSES:
            raise ValueError(
                f"{_repo_rel(path)}: use_cases[{i}] status {status!r} is not one of "
                f"{sorted(_USE_CASE_STATUSES)}"
            )
        name = str(entry["name"])
        tables_raw = entry.get("tables") or []
        if not isinstance(tables_raw, list):
            raise ValueError(
                f"{_repo_rel(path)}: use_cases[{i}] ({name!r}) 'tables' must be a "
                f"list, got {type(tables_raw).__name__}"
            )
        tables = [str(t) for t in tables_raw]
        local_tables = []
        foreign_tables = []

        for t in tables:
            if "." in t:
                # Cross-package reference: "<package>.<gold_view>"
                pkg_name, table_name = t.split(".", 1)
                if pkg_name == os.path.basename(os.path.normpath(unit_dir)):
                    raise ValueError(
                        f"{_repo_rel(path)}: use case {name!r} lists {t!r}, a qualified "
                        f"reference to its OWN package; use the bare name {table_name!r}"
                    )
                if pkg_name not in all_units:
                    raise ValueError(
                        f"{_repo_rel(path)}: use case {name!r} references package {pkg_name!r}, "
                        f"which is not a known package. Known packages: {sorted(all_units.keys())}"
                    )
                if table_name not in all_units[pkg_name]:
                    raise ValueError(
                        f"{_repo_rel(path)}: use case {name!r} references table {table_name!r} "
                        f"in package {pkg_name!r}, which does not exist. Known gold tables in "
                        f"{pkg_name}: {sorted(all_units[pkg_name])}"
                    )
                foreign_tables.append({"unit": pkg_name, "table": table_name})
            else:
                # Local table reference
                if t not in gold_tables:
                    raise ValueError(
                        f"{_repo_rel(path)}: use case {name!r} lists table {t!r}, which "
                        f"is not a gold table in this unit. Known gold tables: "
                        f"{sorted(gold_tables)}"
                    )
                local_tables.append(t)

        out.append({
            "name": name,
            "status": status,
            "tables": local_tables,
            "foreign_tables": foreign_tables
        })
    return out


class JsonModelEmitter(Emitter):
    """Serialize a Unit to the explorer's JSON. Deterministic (sort_keys, parse order)."""

    def __init__(self):
        """Initialize with empty all_units mapping, to be populated before emitting."""
        self.all_units: dict[str, frozenset[str]] = {}

    def unit_dict(self, unit: Unit) -> dict:
        unit_rel_dir = _repo_rel(unit.dir)
        # Gold tables in this unit — the valid target set for a use case's
        # `tables:` mapping (validated in _load_use_cases; a bad name fails loud).
        gold_tables = frozenset(t.name for t in unit.tables if t.layer == "gold")
        return {
            "name": unit.name,
            "kind": unit.kind,
            "tables": [self._table(t) for t in unit.tables],
            "relationships": [
                {
                    "child_table": r.child_table,
                    "child_cols": list(r.child_cols),
                    "parent_table": r.parent_table,
                    "parent_cols": list(r.parent_cols),
                    "declared_fk": r.declared_fk,
                }
                for r in unit.relationships
            ],
            "checks": [
                {
                    "name": c.name,
                    "table": c.table,
                    "column": c.column,
                    "severity": c.severity,
                }
                for c in unit.checks
            ],
            "glossary_path": (
                unit_rel_dir + "/glossary.md" if unit.has_glossary else None
            ),
            # Only link a contract that actually exists on disk. A path to a
            # not-yet-authored ODCS file would render a Contract link in the panel
            # that dead-ends (nothing to stage/serve), so it is null until the
            # contract is written — mirroring how glossary_path is null when absent.
            "contract_path": _contract_path(unit.name),
            # The unit's folder on GitHub (README, use-cases.yaml, DDL), linked from the
            # explorer panel. Unlike glossary/contract it is not staged: it points at the
            # source repo, so it is an absolute URL rather than a site-relative path.
            "source_url": f"{SOURCE_TREE_URL}/{unit_rel_dir}",
            # Planning tier: the business use cases this package enables, read from
            # the package's use-cases.yaml (empty for core domains / packages with
            # no manifest). Names + status + an optional gold-`tables:` mapping —
            # no owners in the published model. Each listed table is validated
            # against this unit's gold tables or cross-package references (a bad name fails loud).
            "use_cases": _load_use_cases(unit.dir, gold_tables, self.all_units),
        }

    def _table(self, t: Table) -> dict:
        return {
            "name": t.name,
            # Table-level COMMENT (from CREATE TABLE ... COMMENT '...'), surfaced so the
            # explorer can show it on hover; per-column comments are already emitted below.
            "comment": t.comment,
            "role": t.role,
            "layer": t.layer,
            "materialized": t.materialized,
            "scd2": t.scd2,
            "columns": [
                {
                    "name": c.name,
                    "type": c.sql_type,
                    "pk": c.name in t.primary_key,
                    "fk": False,
                    "pii": c.is_pii,
                    "enum_values": list(c.enum_values),
                    "comment": c.comment,
                }
                for c in t.columns
            ],
        }

    def emit(self, unit: Unit, **opts) -> str:
        return json.dumps(self.unit_dict(unit), indent=2, sort_keys=True) + "\n"
