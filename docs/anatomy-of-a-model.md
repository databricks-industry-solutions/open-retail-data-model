# Anatomy of an ORDM model

This is the map of **what ORDM ships, what each model is made of, and how to consume it** — start
here if you're adopting, extending, or reviewing the model.

## Two layers

ORDM is organized in two layers, each a folder of self-contained units:

- **Canonical core** (`canonical-core/`) — the **silver** layer: 15 conformed business domains
  (Customer, Product, Store, Order, Transaction, Payment, Inventory, Supplier, Procurement, Marketing,
  Logistics, Equipment, Calendar, Labor, Interaction). These are the shared, reusable primitives — defined once, joined everywhere.
- **Outcome packages** (`outcome-packages/`) — the **gold + semantic** layer: 12 packages, one per
  retail business outcome. Each builds *on top of* the core with gold views and UC metric views; it
  never redefines a core entity.

A **unit** = one domain or one package = one folder = (at deploy time) one Unity Catalog schema.

## What a unit folder contains

Every domain/package folder follows the same layout. Authored files are the source of truth; the
`diagrams/` folder is generated.

| Path | What it is | Authored / generated |
|---|---|---|
| `tables/<table>.sql` | one `CREATE TABLE` per entity — columns, types, comments, `PRIMARY KEY`, `SET TAGS` (role, PII). **The source of truth.** | authored |
| `relationships.sql` | Unity Catalog foreign keys (informational) + enum `CHECK` constraints | authored |
| `checks.sql` | data-quality assertions (run by `runtime/data-quality/run_checks.py`) | authored |
| `glossary.md` | business terms for the unit | authored |
| `masks.sql` | UC column masks enforcing the `dbx_pii_*` tags | authored |
| `gold/*.sql`, `metric-views/*.sql` | (outcome packages) gold views + UC metric views on the core | authored |
| `comments.sql` | (outcome packages) agent metadata — synonyms, display names, glossary terms for Genie / AI-BI interpretation | authored |
| `sample-queries.sql` | (outcome packages) example queries demonstrating the outcome | authored |
| `notebook-templates/` | (outcome packages) starter Databricks notebooks for the outcome | authored |
| `use-cases.yaml` | (outcome packages) the business use cases the package enables, as `use_cases: [{name, status, tables?}]` where `status` is one of `blocked` / `in-progress` / `planned` / `done`. Names + status only (no owners). The optional `tables:` maps a use case to the gold tables that serve it. Tables can be local (in this unit) or cross-package references using syntax `"package-name.table_name"` (validated against the referenced unit's real gold tables). Local references drive the explorer's L1 grouping and the use-case -> core lineage reveal. That lineage, and each use case's derived `consumes` domains, is the core tables its gold views read plus every core table reached by following declared FKs from a non-core table they read (transitively, across packages), so it is FK-reachable rather than only what the SQL joins. An ingredient or association table's own lineage in that view is narrower: only the core tables its own declared FKs reference directly. Cross-package references are shown as linked cards in the explorer. Surfaced in the explorer under the package. Note: this per-use-case status is a **planning** signal and is independent of the package's DoD maturity in `STATUS.md` (a use case can be `done` while its package is still 🟡 In progress). | authored |
| `diagrams/<unit>.*` | the generated ER diagram artifacts (see below) | **generated** |

## The generated formats — one parse, five projections

A model change touches exactly one place: the **DDL**. From a single parse of that DDL
(`tools/ordm_ddl`), the toolchain emits several projections — each for a different consumer. They are
all **CI-generated** and **drift-gated** (CI regenerates and fails if any committed artifact is stale),
so they **cannot diverge**: there is one source, and everything else is derived.

| Format | What it's for | Who consumes it |
|---|---|---|
| **`.sql` (DDL)** | the model itself — the source of truth | Databricks (deployed to Unity Catalog) |
| **`model.json`** | the structured model | the interactive [model explorer](er-diagrams.md#the-interactive-explorer); also the most diff-readable view of a change |
| **`.mmd` (Mermaid)** | the diagram source that renders the committed SVG; a GitHub-native fallback | `mermaid-cli` (render) |
| **`.svg` (light + dark)** | the themed image that renders **inline on the GitHub folder page** | anyone browsing the repo |
| **`.dbml`** | portable, tool-agnostic ER interchange | paste into [dbdiagram.io](https://dbdiagram.io) / publish via dbdocs / import with `@dbml/core` or PyDBML |

**Why keep five?** Each reaches a different audience with zero extra work on their part (browse on
GitHub, explore interactively, or take the `.dbml` to another tool), and — because they are one
generator's output behind a drift gate — the usual "more formats, more drift" risk does not apply here.
See [ADR 0012](../governance/decisions/0012-model-visualization.md) for the decision record.

## How to consume it

- **Deploy the model** to your Unity Catalog with the Databricks Asset Bundle in [`runtime/examples/`](../runtime/examples/):
  `databricks bundle deploy` then `databricks bundle run deploy_ordm`.
- **Browse the diagrams** inline — open any domain/package folder on GitHub; its `README.md` renders the
  ER diagram (light/dark). See [ER diagrams](er-diagrams.md) for how they're generated.
- **Explore interactively** — the [model explorer](er-diagrams.md#the-interactive-explorer) (a hosted
  static site) lets you navigate the value-chain landing → per-unit ER → table detail (with Matrix and
  Graph views, filter/search, and a minimap), see columns/PII/keys, and jump to the glossary and data
  contract for any table.
- **Take it to another tool** — a unit's `diagrams/<unit>.dbml` pastes straight into dbdiagram.io.
- **Data contracts** — optional [ODCS](odcs-integration.md) contracts under `contracts/odcs/` describe
  each unit for contract-aware tooling.
- **Synthetic data** — [`runtime/synthetic-data/`](../runtime/synthetic-data/) populates the model with no source data.

## Standards & governance

Every unit conforms to [the data-model standards](data-model-standards.md) and moves through the
[Definition of Done](definition-of-done.md) status ladder. Structure, naming, and scope decisions are
recorded as ADRs in [`governance/decisions/`](../governance/decisions/).
