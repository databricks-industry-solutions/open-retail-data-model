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
| Calendar | [`canonical-core/calendar/`](../canonical-core/calendar/) | NRF 4-5-4 retail fiscal calendar (conformed time dimension) |
| Supplier | [`canonical-core/supplier/`](../canonical-core/supplier/) | Suppliers / vendors (GS1 GLN) |
| Procurement | [`canonical-core/procurement/`](../canonical-core/procurement/) | Purchase-order lines (order + receipt + defect + price) |
| Payment | [`canonical-core/payment/`](../canonical-core/payment/) | Payments, refunds, adjustments |
| Marketing | [`canonical-core/marketing/`](../canonical-core/marketing/) | Trade-promotion dimension (mechanics, funding, lift/spend) |
| Logistics | [`canonical-core/logistics/`](../canonical-core/logistics/) | Lanes, shipments, tracking (carrier checkpoints, streaming-ready) |
| Equipment | [`canonical-core/equipment/`](../canonical-core/equipment/) | In-store assets and telemetry (refrigeration, HVAC, POS terminals, kiosks) |
| Labor | [`canonical-core/labor/`](../canonical-core/labor/) | Employees, labor planning, schedules |
| Interaction | [`canonical-core/interaction/`](../canonical-core/interaction/) | Omnichannel customer touchpoints (online and offline interaction events) |

A Customer entity referenced by *Customer 360* and by *Agentic Commerce* is the **same** entity — no redefinition, no drift across outcomes.

### Layer 2 — Outcome packages (= medallion gold + semantic)

Consumption-ready, outcome-aligned bundles. Each package targets one retail business outcome, and each becomes a **Databricks Marketplace listing**. A package contains:

- **Extension tables** (one file per table in `tables/`) — outcome-specific tables not in the canonical core
- **Metric views** (one `.sql` per metric view in `metric-views/`) — measures, dimensions, joins, governed by Unity Catalog Business Semantics
- **Agent metadata** (`comments.sql`) — synonyms, display names, glossary terms so Genie / AI-BI interpret the model in business terms
- **Sample queries and notebook templates** (`sample-queries.sql`, `notebook-templates/`) — example SQL and starter notebooks for the outcome
- **Generated ER diagrams** (`diagrams/`) — Mermaid `.mmd` / DBML / SVG derived from the DDL by `tools/gen_er_diagrams.py` (a drift-gated artifact; see [er-diagrams.md](er-diagrams.md)). Canonical-core domains carry the same `diagrams/` folder.

### Out of scope (private layers)

| Layer | Why it's not in ORDM |
|---|---|
| **Bronze** | Raw, source-system-shaped — different for every customer |
| **Source-aligned silver** | SAP/Shopify/POS-conformed tables — partner IP (e.g., a partner's SAP→Delta mappings) |
| **Customer extensions** | Customer-specific KPIs, naming, access patterns — built on top of ORDM by the customer |

## Open vs private boundary

This boundary is the core IP-safety principle (Charter §7). It is what lets ORDM be openly published while partners keep their differentiation:

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

See the [program decision record](../governance/decisions/0001-layer-positioning.md) for the full rationale.

## Mapping to Databricks products

| ORDM concept | Databricks implementation |
|---|---|
| Canonical core entities | Delta tables in Unity Catalog, with PK/FK constraints and column comments |
| Outcome package metric views | UC Metric Views (UC Business Semantics) |
| Agent metadata | UC Business Semantics agent metadata (synonyms, display names) |
| Marketplace listing | Databricks Marketplace data product per outcome package |
| Deployment | Databricks Asset Bundle — the root `databricks.yml` `deploy_ordm` job (schema bootstrap lives in `runtime/examples/deploy-with-dab/`) |

## Unity Catalog Domains (optional governance polish)

Unity Catalog **Domains** let an organization group data assets by business purpose and surface them on the account **Discover page**, with curated ownership and certification. Because ORDM's layout is already organized by business domain and outcome, that structure maps cleanly onto UC Domains — so an account admin can mirror ORDM into the Discover page with no extra modeling. This is **optional**: ORDM deploys and is fully usable (canonical core, outcome packages, metric views, Marketplace listings) without any of it. Domains only add a browsing and stewardship overlay on top.

Two properties of UC Domains shape how ORDM treats them:

- **Account-level, not workspace/catalog-scoped.** Domains apply to the whole account, not to a single workspace or catalog. Creating and assigning them is an **account-admin governance action**, done once per account and spanning workspaces — a different layer from ORDM's catalog-scoped `deploy_ordm` bundle. So `deploy_ordm` neither creates nor requires domains.
- **Public Preview, built on governed tags, managed in the UI.** Domains are in Public Preview and are built on Unity Catalog governed tags, managed on the Discover page. There is no public create API for them today, so ORDM does not automate their creation. (Preview status and capabilities move — re-check the current [Databricks docs](https://docs.databricks.com/aws/en/discover/discover-page) at adoption time.)

### The mapping is derived, not declared

ORDM does **not** ship a hand-maintained domains manifest (there is no `governance/domains.yaml` or equivalent). A checked-in mapping file would be the same drift-prone anti-pattern ORDM avoids elsewhere: it would duplicate the folder structure and go stale. Instead the ORDM domain to UC Domain mapping is **derived 1:1 from the repository layout**:

| ORDM structure | UC Domain |
|---|---|
| each `canonical-core/<domain>/` (the authoritative set is exactly the folders there, read from the tree; the Layer-1 table earlier in this doc lists today's domains for orientation only) | one domain per canonical-core domain |
| each `outcome-packages/<package>/` (the [outcome pillars](outcome-map.md); the set is exactly the folders there, read from the tree) | one domain per outcome package |
| the model as a whole | an optional parent "ORDM" domain, with the core domains and outcome packages as subdomains |

The list of domains is therefore always exactly the set of folders under `canonical-core/` and `outcome-packages/` — read it from the tree, not from a manifest. Naming convention: a top-level domain uses the folder name (optionally prefixed, e.g. `ordm_<domain>`) so the Discover page mirrors the repo; a subdomain (e.g. core domains / packages under the parent "ORDM" domain) uses the UC `{parentDomainTag}/{subdomainName}` governed-tag convention — the tag-key mechanism is specified by [ADR 0010](../governance/decisions/0010-governed-tag-and-semantic-alignment.md) (governed-tag & semantic alignment). This doc owns the hierarchy/folder mapping; ADR 0010 owns how those map onto governed-tag keys. See [ADR 0009](../governance/decisions/0009-uc-domains-derived-no-manifest.md) for the decision record.

### Account-admin steps

Applied out-of-band by an account admin (or a curator with the `MANAGE DISCOVERY` permission), once per account:

1. **Enable the previews.** An account admin enables the "Domains and Discover Page" preview (account-level) and the "Discover Page" preview (workspace-level).
2. **Create one domain per folder.** On the Discover page, use **Create domain** for each `canonical-core/<domain>` and each `outcome-packages/<package>` — the domain set is exactly the folder tree (per above). Optionally create a parent "ORDM" domain and nest the rest as subdomains. Each domain is backed by a governed tag. Note: a `⚪ Planned` package (per `STATUS.md`) bootstraps no schema yet (see `runtime/examples/deploy-with-dab/00_bootstrap_schemas.sql`), so its domain has nothing to assign in step 3 — defer creating it until the package ships, or expect an intentionally empty domain until then.
3. **Assign the deployed assets.** Assign each ORDM schema (and its tables) to its domain — either from the domain page via **Add to Domain**, or by applying the domain's governed tag to the schema. ORDM deploys one Unity Catalog schema per canonical-core domain and per shipped outcome package, so assignment is schema-level in both layers.
4. **Publish** the domain pages so the organization can browse ORDM by business purpose on the Discover page.

If and when Databricks ships an account-level API for domains, these steps can be generated directly from the folder list (the mapping is already derivable) — but that is a convenience, not a prerequisite.
