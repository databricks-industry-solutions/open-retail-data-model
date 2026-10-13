# ADR 0001 — ORDM covers both canonical core (silver) and outcome packages (gold)

**Status:** Accepted (2026-05-26)

## Context
Early framing positioned ORDM as gold-only. A working-group discussion surfaced that the conformed entities the model needs ARE silver by Databricks' definition, and that "silver"/"gold" mean different things to different audiences.

## Decision
ORDM publishes **both** layers, role-named to avoid medallion-vocabulary disputes:
- **Canonical core** (= silver) — conformed business entities
- **Outcome packages** (= gold + semantic) — metric views + semantics per outcome, as Marketplace listings

Bronze + source-aligned silver stay partner-private. "As applicable" — not every domain ships both in v1.

## Consequences
- Resolves the silver/gold confusion; aligns with UC Business Semantics (GA early 2026).
- Each Marketplace listing = canonical-core slice + outcome-package bundle.
