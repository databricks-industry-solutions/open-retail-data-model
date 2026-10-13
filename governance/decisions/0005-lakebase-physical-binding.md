# ADR 0005 — Lakebase as a second physical binding

**Status:** Accepted (2026-06-28). (Proposed 2026-06-22.)

> **Accepted refinement (2026-06-28):** ORDM publishes the **canonical core** from one logical model into **two physical bindings** — Delta/Lakehouse and Lakebase/Postgres — with the Lakebase binding rolled out for the **transactional spine first** (transaction, order, inventory, loyalty) and expanding as the generator matures. **Gold and outcome-package tables and metric views are Delta/Lakehouse only.** Bindings are **generated from the logical model, not hand-authored**; operational/application write-state tables and applications themselves are out of scope. The standard (§0 "Physical bindings") and the Definition of Done reflect this.

## Context

ORDM today models only the analytical Lakehouse layer: tables are Delta DDL where PK/FK/UNIQUE constraints are *informational* (unenforced by the engine). That is correct for analytics, but it leaves out the operational/transactional side that real retail apps need.

Databricks Lakebase is a managed Postgres OLTP engine. Its physical model genuinely diverges from Delta: it **enforces** primary keys, foreign keys, and indexes, and it adds `pgvector`. Databricks' own LTAP architecture runs the transactional (Postgres/ACID) and analytical (Delta/Lakehouse) engines as separate physical stores over shared Unity Catalog governance. So a model that wants to serve both app-serving and analytics cannot assume one physical shape fits both.

Incumbent retail standards already split this way: ARTS ships an OLTP Operational Data Model plus a separate dimensional Data Warehouse Model; Teradata and Oracle layer physical models off a logical one. An adversarial check confirmed that synced tables do *not* remove the need for a distinct OLTP model.

## Decision (proposed)

Publish ORDM as a **logical model that generates two physical bindings**:

1. **Lakehouse binding** — Delta tables in Unity Catalog (today's model; informational constraints).
2. **Lakebase binding** — Postgres OLTP (enforced PK/FK + indexes + pgvector), for new / lakehouse-adjacent transactional apps. Not aimed at lift-and-shift of tier-1 POS/OMS.

The logical model (a plain-text, generative spec) is the source of truth; both physical bindings derive from it mechanically, so they cannot drift. Scope the transactional spine to where it earns its place first (transaction, order, inventory, loyalty).

## Consequences

- Versioning/CI must gate **both** bindings: a change is breaking if it is breaking on *either*. Lakebase generally raises the bar (enforced constraints make column drops, NOT NULL adds, and type narrowing hard failures where Delta would silently allow them). See the Lakebase dual-binding rule in §1 of the [schema versioning policy](../../docs/versioning-policy.md).
- New artifact types appear (a logical spec + a Lakebase DDL binding) that the conformance gates do not yet cover.
- Makes the logical model the top of the hierarchy; updates the layer/hierarchy and principles docs on acceptance.

## Open questions (the discussion)

- OLTP design point: normalized transactional spine vs denormalized serving shape.
- How much schema-level divergence is required vs handled by LTAP storage sync.
- Logical-model format/toolchain (DBML vs YAML) as the generative source.
- Generality check vs Microsoft CDM / IBM Retail before publishing the logical layer as canonical.
- Which domains get a Lakebase binding in the first cut.

Full background: the D11 research memo and the working-group design notes; the published rule now lives in the [schema versioning policy](../../docs/versioning-policy.md). Comments welcome on this PR.
