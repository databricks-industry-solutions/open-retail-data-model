"""Typed, source-of-truth-neutral model of an ORDM unit (a domain or package),
produced by DdlParser and consumed by every Emitter. Stdlib only."""
from __future__ import annotations
from dataclasses import dataclass

PII_TAG_PREFIX = "dbx_pii"

@dataclass(frozen=True)
class Column:
    name: str
    sql_type: str = ""
    required: bool = False
    comment: str = ""
    tags: tuple[str, ...] = ()
    enum_values: tuple[str, ...] = ()

    @property
    def is_pii(self) -> bool:
        return any(t.startswith(PII_TAG_PREFIX) for t in self.tags)

@dataclass(frozen=True)
class Relationship:
    child_table: str
    child_cols: tuple[str, ...]
    parent_table: str
    parent_cols: tuple[str, ...]
    declared_fk: bool = True

@dataclass(frozen=True)
class Check:
    name: str
    table: str
    column: str | None
    severity: str = "error"
    enum_values: tuple[str, ...] = ()
    query: str = ""

@dataclass(frozen=True)
class Table:
    name: str
    schema_token: str
    columns: list[Column]
    primary_key: tuple[str, ...] = ()
    role: str = ""
    comment: str = ""
    layer: str = "silver"
    materialized: bool = True
    scd2: bool = False

    @property
    def pk_columns(self) -> tuple[str, ...]:
        return self.primary_key

    def column(self, name: str) -> Column | None:
        return next((c for c in self.columns if c.name == name), None)

@dataclass(frozen=True)
class Unit:
    name: str
    kind: str
    tables: list[Table]
    relationships: list[Relationship]
    checks: list[Check]
    dir: str = ""
    has_glossary: bool = False

    @property
    def is_core(self) -> bool:
        return self.kind == "core"
