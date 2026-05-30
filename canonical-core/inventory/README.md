# Canonical Core — Inventory

> Status: ⚪ Planned

The conformed **Inventory** entity. Part of the ORDM [canonical core](../README.md).

## Contents

| File | Purpose |
|---|---|
| `tables.sql` | CREATE TABLE DDL (snake_case, column comments) |
| `relationships.sql` | Intra-entity FK constraints |
| `glossary.md` | Business terms for this entity |
| `samples/` | Small synthetic sample rows |

## Design notes

Follows the ORDM [data model principles](../../docs/data-model-principles.md): vendor-neutral comments, strict typing, no derived metrics on master tables, thin cross-entity FKs, SCD where applicable.

_TODO: add tables.sql_
