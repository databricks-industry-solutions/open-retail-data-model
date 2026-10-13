from __future__ import annotations
from .base import Emitter
from ..model import Unit, Table

_THEME = {"light": '%%{init: {"theme":"default"}}%%',
          "dark":  '%%{init: {"theme":"dark"}}%%'}
_CLASSDEF = {
    "light": ["    classDef core fill:#e9eef3,stroke:#3b4a59,color:#101d29;",
              "    classDef gold fill:#fce3d6,stroke:#c4320a,color:#4a1b0a;"],
    "dark":  ["    classDef core fill:#2b3a49,stroke:#8aa4bd,color:#eef4fa;",
              "    classDef gold fill:#5a2e1e,stroke:#f0996a,color:#ffe8db;"],
}


class MermaidEmitter(Emitter):
    """Hybrid Mermaid source. Core units -> erDiagram; outcome units -> flowchart.
    Returns raw mermaid text (no ``` fences)."""
    MAX_ATTRS = 8

    def emit(self, unit: Unit, theme: str = "light", **opts) -> str:
        body = self._er(unit) if unit.is_core else self._flow(unit, theme)
        return _THEME[theme] + "\n" + body + "\n"

    def _fk_cols(self, unit: Unit) -> dict[str, set]:
        m: dict[str, set] = {}
        for r in unit.relationships:
            m.setdefault(r.child_table, set()).update(r.child_cols)
        return m

    def _er(self, unit: Unit) -> str:
        fk = self._fk_cols(unit)
        lines = ["erDiagram"]
        for r in unit.relationships:
            if r.declared_fk and r.child_cols:
                lines.append(f'    {r.parent_table} ||--o{{ {r.child_table} : "{r.child_cols[0]}"')
        for t in unit.tables:
            lines.append(f"    {t.name} {{")
            lines += self._er_rows(t, fk.get(t.name, set()))
            lines.append("    }")
        return "\n".join(lines)

    def _er_rows(self, t: Table, fk_cols: set) -> list[str]:
        rows, shown = [], 0
        for c in t.columns:
            key = "PK" if c.name in t.primary_key else ("FK" if c.name in fk_cols else "")
            keyish = bool(key) or c.name.endswith(("_sk", "_id"))
            if not keyish and shown >= self.MAX_ATTRS:
                continue
            if not keyish:
                shown += 1
            typ = (c.sql_type or "string").split("(")[0].strip().lower() or "string"
            marks = "PII" if c.is_pii else ("enum" if c.enum_values else "")
            comment = f' "{marks}"' if marks else ""
            rows.append(f"        {typ} {c.name} {key}{comment}".rstrip())
        return rows

    def _flow(self, unit: Unit, theme: str) -> str:
        lines = ["flowchart TB"]
        for t in unit.tables:
            cls = "gold" if t.layer == "gold" else "core"
            keycols = [c.name for c in t.columns
                       if c.name in t.primary_key or c.name.endswith(("_sk", "_id"))][:4]
            label = t.name + (("<br/>" + " · ".join(keycols)) if keycols else "")
            lines.append(f'    {t.name}["{label}"]:::{cls}')
        for r in unit.relationships:
            lines.append(f"    {r.parent_table} --> {r.child_table}")
        lines += _CLASSDEF[theme]
        return "\n".join(lines)
