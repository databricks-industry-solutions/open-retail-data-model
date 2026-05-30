# ORDM Architecture

## The layered model

ORDM is organized around **two published layers** plus clear boundaries for what stays private.

### Layer 1 — Canonical core (= medallion silver)

The conformed, deduplicated, enterprise view of retail business entities. Normalized (roughly 3NF), with primary keys, foreign keys, and master-data discipline. These are the shared primitives every outcome package builds on — defined **once**, reused everywhere.

Domains (each maps to a Unity Catalog schema and contains one file per table under `tables/`):

| Domain | Folder | Description |
|---|---|---|
| Customer | [`canonical-core/customer/`](../canonical-core/customer/) | Identity, contact, address, consent |
| Product | [`canonical-core/product/`](../canonical-core/product/) | Items, SKUs, hierarchy, brand |
| Order | [`canonical-core/order/`](../canonical-core/order/) | Order header and lines |
| Inventory | [`canonical-core/inventory/`](../canonical-core/inventory/) | Stock positions, movements |
| Store | [`canonical-core/store/`](../canonical-core/store/) | Locations, formats, departments |
| Transaction | [`canonical-core/transaction/`](../canonical-core/transaction/) | POS / sales transactions |

A Customer entity referenced by *Customer 360* and by *Agentic Commerce* is the **same** entity — no redefinition, no drift across outcomes.

### Layer 2 — Outcome packages (= medallion gold + semantic)

Consumption-ready, outcome-aligned bundles. Each package targets one retail business outcome, and each becomes a **Databricks Marketplace listing**. A package contains:

- **Extension tables** (one file per table in `tables/`) — outcome-specific tables not in the canonical core
- **Metric views** (one `.yml` per metric in `metric-views/`) — measures, dimensions, joins, governed by Unity Catalog Business Semantics
- **Agent metadata** (`agent-metadata.yml`) — synonyms, display names, glossary terms so Genie / AI-BI interpret the model in business terms
- **Sample queries, notebook templates, sample dashboards**

### Out of scope (private layers)

| Layer | Why it's not in ORDM |
|---|---|
| **Bronze** | Raw, source-system-shaped — different for every customer |
| **Source-aligned silver** | SAP/Shopify/POS-conformed tables — partner IP (e.g., a partner's SAP→Delta mappings) |
| **Customer extensions** | Customer-specific KPIs, naming, access patterns — built on top of ORDM by the customer |

## Open vs private boundary

This boundary is what lets ORDM be openly published while you keep your source-specific integrations and differentiation private:

```
        PARTNER / CUSTOMER PRIVATE          │            ORDM (OPEN, Apache 2.0)
                                            │
  Source systems → Bronze → Source-aligned  │   Canonical core  →  Outcome packages
                            silver           │   (conformed         (metric views +
  (SAP, Shopify, POS, ingestion logic,       │    entities)          semantics)
   partner accelerators, proprietary maps)   │
                                            │   Synthetic data, docs, examples
```

ORDM ships **no** customer data and **no** code that reaches into customer systems. The only code in ORDM is synthetic-data generators and deployment helpers that run entirely in the adopter's own workspace.

## Why "canonical core / outcome packages" instead of "silver / gold"

The terms "silver" and "gold" mean different things to different audiences (Databricks-strict vs partner usage), which caused real confusion in early discussions. ORDM uses **role-named layers** — "canonical core" and "outcome packages" — that are unambiguous, while noting the medallion equivalents for readers who think in those terms.



## Mapping to Databricks products

| ORDM concept | Databricks implementation |
|---|---|
| Canonical core entities | Delta tables in Unity Catalog, with PK/FK constraints and column comments |
| Outcome package metric views | UC Metric Views (UC Business Semantics, GA early 2026) |
| Agent metadata | UC Business Semantics agent metadata (synonyms, display names) |
| Marketplace listing | Databricks Marketplace data product per outcome package |
| Deployment | Databricks Asset Bundle (`examples/deploy-with-dab/`) |
