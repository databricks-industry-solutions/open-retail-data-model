from __future__ import annotations
from .base import Emitter
from ..model import Unit, Table

_GROUP_COLOR = {"silver": "#3b4a59", "gold": "#c4320a"}


class DbmlEmitter(Emitter):
    """Canonical DBML (dbml.org). Deterministic: tables & refs in parse order."""

    def emit(self, unit: Unit, **opts) -> str:
        lines = ["// GENERATED from the DDL by tools/gen_er_diagrams.py — do not edit by hand.",
                 f"Project ordm_{unit.name} {{ Note: '{unit.kind} unit' }}", ""]
        for t in unit.tables:
            lines += self._table(t)
            lines.append("")
        for r in unit.relationships:
            if r.child_cols and r.parent_cols:
                lines.append(f"Ref: {r.child_table}.{r.child_cols[0]} > "
                             f"{r.parent_table}.{r.parent_cols[0]}")
        if unit.tables:
            color = _GROUP_COLOR.get(unit.tables[0].layer, "#3b4a59")
            names = ", ".join(t.name for t in unit.tables)
            lines += ["", f"TableGroup {unit.name} [color: {color}] {{ {names} }}"]
        return "\n".join(lines) + "\n"

    def _table(self, t: Table) -> list[str]:
        rows = [f"Table {t.name} {{"]
        for c in t.columns:
            attrs = []
            if c.name in t.primary_key:
                attrs.append("pk")
            if c.required:
                attrs.append("not null")
            note = (("PII · " if c.is_pii else "") + (c.comment or "")).replace("'", "\\'").strip()
            if note:
                # DBML tooltips are kept short (~120 chars). Truncate on a WORD boundary
                # with an ellipsis rather than a hard mid-word cut, so a long column
                # comment never renders as garbled text (e.g. "...and fall for period").
                if len(note) > 120:
                    note = note[:120].rsplit(" ", 1)[0].rstrip(" ,.;:") + " …"
                attrs.append(f"note: '{note}'")
            a = f" [{', '.join(attrs)}]" if attrs else ""
            rows.append(f"  {c.name} {(c.sql_type or 'string').lower()}{a}")
        rows.append(f"  Note: '{t.role or 'table'} · {t.layer}'")
        rows.append("}")
        return rows
