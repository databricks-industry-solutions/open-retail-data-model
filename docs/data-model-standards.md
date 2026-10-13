# ORDM data model standards and principles

These are the normative conventions every ORDM contribution follows. They keep the model vendor-neutral, consistent, deployable, and easy to adopt. This document is the single source of truth for the rules. CONTRIBUTING.md is the lightweight process guide and points here. Where the two disagree, this document wins and the guide is fixed in the same PR.

How to read this. The rules come in two kinds. Mandates are enforced, machine-checked in CI where possible, and a contribution that breaks one does not merge. Design principles guide modeling judgment and are adjudicated by a reviewer rather than a script. A smaller set of choices is deliberately left flexible and listed near the end. A rule earns mandate status only if it can be checked mechanically or adjudicated cleanly, and only if our own reference contributions can pass it.

## 0. Scope: canonical core (silver) and outcome packages (gold), as applicable

ORDM publishes two layers, role-named to avoid medallion-vocabulary disputes.

Canonical core, which equals a Databricks-strict silver layer, holds the conformed business entities (Customer, Product, Order, Transaction, Inventory, Store, and so on), pragmatically normalized, with informational keys and MDM-style discipline. These are the shared primitives every listing builds on.

Outcome packages, which equal gold plus semantics, are the marketplace listings. Each is a bundle: a subset of canonical core plus UC Metric Views, agent metadata, denormalized analytical views, and a glossary, all aligned to one business outcome.

What ORDM does not publish: source integration (bronze and source-aligned silver, which is customer-specific ingest from SAP, Shopify, POS, and the like); customer extensions (customer-built KPIs, dashboards, and access rules on top of ORDM); operational or application write-state tables (preference overrides, agent feedback, workflow state, and the like); and applications themselves — apps are not an ORDM contribution type, so any app that needs operational state owns those tables outside ORDM.

As applicable means not every domain ships both layers in v1. Publish what is mature and expand iteratively. A domain might launch with canonical core only, or with a single outcome package only, depending on partner readiness.

Physical bindings (ADR 0005, accepted 2026-06-28). The canonical core is published from a single logical model that generates two physical bindings: Delta/Lakehouse and Lakebase/Postgres (the latter for OLTP serving, with enforced PK/FK and pgvector). The Lakebase binding is rolled out for the **transactional spine first** (transaction, order, inventory, loyalty) and expands as the generator matures. **Gold and outcome-package tables and metric views are Delta/Lakehouse only.** Bindings are generated, not hand-authored.

## A. Mandates

### 1. Canonical artifact format

Every canonical-core table and every outcome-package table or view ships as executable SQL DDL, one CREATE statement per file. Both `CREATE TABLE IF NOT EXISTS` and `CREATE OR REPLACE TABLE` are accepted; prefer `IF NOT EXISTS` for canonical masters since `OR REPLACE` drops data. Markdown is never the committed form of a table. Narrative, research, and rationale go to design or docs directories, never under a tables directory. CI rejects any markdown file under a tables directory and any SQL file with more than one CREATE statement.

### 2. File layout

The layout is fixed and CI-validated. Canonical core uses `canonical-core/<domain>/` with `tables/<table>.sql`, `relationships.sql`, `checks.sql`, an optional `masks.sql`, and `glossary.md` (sample rows come from the domain's generator under `runtime/synthetic-data/`). Outcome packages use `outcome-packages/<package>/` with `tables/`, `gold/`, `metric-views/`, `checks.sql`, `comments.sql`, `glossary.md`, an optional `use-cases.yaml` (planning-tier use cases, non-scored — see [ADR 0013](../governance/decisions/0013-use-cases-planning-artifact.md)), and `notebook-templates/`. These are layout **slots** — where a file goes *if* present — not a required-artifact list; the required artifacts are the MUST tier in the [Definition of Done](definition-of-done.md) (e.g. a domain is documented by inline `COMMENT`s in its `CREATE TABLE`, so it needs no separate `comments.sql`; and a seeded generator satisfies the samples requirement). One entity equals one owning file equals one layer. A given entity is defined in exactly one file in exactly one layer.

### 3. Layer integrity (the one hard blocker)

Canonical core is silver and must never declare a foreign key into a gold or outcome schema. The core stands alone and never depends on a member that exists only once a gold dimension deploys. CI parses relationships and fails if any canonical-core FK target resolves to an outcome-package schema. The tree self-FK case (item hierarchy, category, org charts) is an explicit named exception so legitimate hierarchies are not flagged.

### 4. Primary keys

Every canonical-core master and dimension has a surrogate primary key, `BIGINT GENERATED ALWAYS AS IDENTITY`, named `<stem>_sk`, with constraint `pk_<table>`, plus a durable STRING business key named `<stem>_id`. The `<stem>` names the entity's grain or role and is applied **consistently** wherever that entity is joined; it defaults to the table name but need not equal it, and a small set of documented conventions deliberately differ (see "Key-stem naming by grain/role" below, and ADR 0011). `GENERATED BY DEFAULT` is permitted only for documented migration or backfill paths. STRING hash or UUID surrogates are not adopted for canonical core. Note the IDENTITY concurrency caveat: `GENERATED ALWAYS` disables concurrent transactions, so reserve it for masters, dimensions, and moderate-volume facts, which is a further reason the durable business key stays a separate column.

### 5. Foreign keys and constraints

Foreign keys are single-column, declared in `relationships.sql` against the parent surrogate key, named `fk_<child>_<parent>`. Business-key joins are not declared as UC foreign keys, because under SCD2 the business key is not unique. UC primary, foreign, and unique constraints are informational and unenforced by the engine; integrity is guaranteed by CI plus synthetic-data regeneration. RELY is applied selectively only on masters and dimensions that CI guarantees valid, with NORELY the default; RELY is never blanket-applied, because RELY on dirty data produces silently wrong results. CHECK and NOT NULL are the only engine-enforced integrity primitives. Referential-integrity enforcement is on the Databricks roadmap; the model does not depend on it today.

**Reference completeness (CI-gated by `FK-COMPLETENESS`).** Every canonical-core table that references another core entity (masters included, e.g. `account -> profile`) must carry a `<stem>_sk` surrogate for that parent and declare the informational FK on it: `fk_<child>_<parent>`, single-column, on the parent's `_sk` primary key, NORELY by default (RELY only where CI guarantees the data valid). This closes the SCD2 gap directly: because the business key `<stem>_id` is not unique under SCD2, a reference expressed only on `<stem>_id` cannot be declared as a UC FK, so it is invisible to Catalog-Explorer ERD, BI auto-relationships, the optimizer, and generated docs. When the parent is SCD2, the `<stem>_sk` surrogate is resolved as-of the referencing row's effective date — the parent version in effect at that time — matching how the sales, inventory, and shipment facts resolve their `_sk` FKs; `product_price.product_sk` resolves as-of `effective_from_date`, and `account.primary_contact_profile_sk` resolves as-of the account version's `effective_from_date`. When the parent is an append-only transactional fact (not SCD2), the surrogate is a straight FK with no version ambiguity — e.g. `shipment_line.po_line_sk -> purchase_order_line.po_line_sk`. A cross-entity reference modeled only on a business key `<stem>_id` with no `<stem>_sk` is therefore a **defect** — add the surrogate and declare the FK — **not** an exemption. Named exceptions (not defects): self-FK hierarchies (a table referencing its own PK stem, e.g. `parent_account_id -> account`); natural-code reference/lookups keyed on their ISO/standard code rather than a minted surrogate (currency, country, unit_of_measure, channel — see the reference/code-table convention in §D); and references whose parent is not a single modeled entity, which carry no `<stem>_sk` to declare an FK on — either a **degenerate/header-grain** reference to a concept the core models only at a finer grain (e.g. `payment.order_id` and `shipment.po_id`, where order and purchase-order exist only at line grain as `customer_order_line` / `purchase_order_line`; the operational order/PO number is retained as a degenerate `*_id` per the fact-key convention above), or a **polymorphic** reference that can resolve to more than one entity (e.g. `lane.origin_location_id` / `lane.destination_location_id`, where a location may be a store, distribution center, or supplier site). This last class is outside the deterministic gate by construction (the `_id` prefix matches no single PK stem) and is adjudicated in review — either by modeling the missing parent entity or by accepting the reference as degenerate. Role-qualified references (`destination_store_sk -> store`, `primary_contact_profile_sk -> profile`) are in scope: they carry the role-prefixed surrogate and declare the FK on it. The check uses the ADR-0011 PK-stem map (not naive table names) so date/calendar and role-qualified keys are not false-positived. The gate runs at `error` with zero tracked exceptions **among surrogate-declarable references** (those whose parent is a single modeled entity); the degenerate/header-grain and polymorphic references above sit outside the gate by construction and are not tracked debt. Any future surrogate-declarable `_id`-only gap that cannot be fixed immediately is recorded as a visible exception in `standards/rules.yaml` (a bare PK stem or a precise `<table>.<column>` signature) until its surrogate lands.

### 6. Strict typing

No STRING for numeric or temporal data, machine-gated in CI. Counts, ranks, and points are INT or BIGINT. Dates are DATE, instants are TIMESTAMP, flags are BOOLEAN.

The float-versus-decimal choice is split by purpose. Money (amounts, prices, costs, exchange rates) is DECIMAL with grain-aware scale: unit-grain prices and costs DECIMAL(18,4), extended and aggregate amounts DECIMAL(18,2), fx_rate DECIMAL(18,8). FLOAT and DOUBLE are not used for stored monetary columns, because IEEE-754 cannot represent most decimal fractions exactly, so sums drift by fractions of a unit and equality and reconciliation become unreliable across the volumes a shared retail spec aggregates. The cost is modest: at precision 18 or less, Spark stores the value as a 64-bit long rather than an arbitrary-precision type, so monetary columns are on the fast path.

DOUBLE is allowed and encouraged where it is the right tool: for derived ratios and intermediate compute in the gold and metric layers (cast inside the view), and for non-monetary continuous values such as latitude and longitude, rates, fractions, scores, and percentages where exact reconciliation is not the point. DECIMAL stays acceptable for those too, so existing DECIMAL(9,6) or DECIMAL(5,2) choices need not change.

CI lints STRING-typed columns whose name matches count, quantity, rank, score, points, or amount, and flags FLOAT or DOUBLE on monetary column names (amount, price, cost, revenue, fee, balance, and the like). It does not flag FLOAT or DOUBLE on non-monetary columns. STRUCT, ARRAY, and MAP are allowed for hierarchy in dimensions, but ship a flattened view alongside, since some BI tools reject complex or VARIANT types.

On TIMESTAMP and timezone: Databricks TIMESTAMP is timezone-aware and session-localized on read, so a UTC storage rule is a convention CI cannot enforce on a plain TIMESTAMP. Where instant semantics must be unambiguous, declare TIMESTAMP_NTZ explicitly and document the contract per column. Treat the UTC rule as a convention, not a CI-enforced contract, unless TIMESTAMP_NTZ is used.

### 7. Enumerations

Type categories use enforced Delta CHECK constraints, not just comments, since CHECK is engine-enforced and comments are not. For example `payment_method_type IN (card, cash, wallet, gift_card, store_credit, bnpl)`. CHECK expressions use no UDFs, aggregates, or window functions. Brand- and provider-specific values such as card_brand or wallet_provider stay free STRING with a comment listing common values. Each enum needs an evolution path: adding a value requires ALTER TABLE DROP and ADD CONSTRAINT plus a coordinated change, so enums that churn should be promoted to a reference table in the reference domain rather than living as a hard CHECK. CHECK constraints are always declared with `ALTER TABLE ... ADD CONSTRAINT ... CHECK (...)`, never inline in the `CREATE TABLE`: Databricks supports only PRIMARY KEY and FOREIGN KEY constraints inline, so an inline CHECK fails to parse at deploy time (CI-enforced by `NO-INLINE-CHECK`).

### 8. SCD Type 2 on masters, with a layer-aware audit block

Masters carry effective_from_date, effective_to_date, and is_current. The audit block is layer-aware: created_timestamp and source_updated_timestamp are required on master and reference tables, while facts and append-only event logs require only record_source and load_timestamp. Append-only facts do not carry SCD2 columns, and copy-pasted SCD2 justification comments do not belong on them. Static reference data defaults to Type 1; high-value masters may use Type 6. The boolean flag is `is_current`. The `dbx_data_type` tag (master, transactional, reference, association) is required on every table so this rule is machine-checkable.

### 9. No derived metrics on masters or dimensions

Aggregates (total_lifetime_orders, last_purchase_date), predictive scores (cltv_score, churn_risk_score), and survey results (nps_score) are forbidden on master and dimension tables. They live only in outcome-package metric views or gold materialized views. CI will flag known derived-column-name patterns on tables tagged master (planned; not yet CI-gated). This holds regardless of column type; it is not about a typing leak. Putting derived values on masters creates write amplification and consistency bugs.

### 10. Thin root and inbound-only cross-domain FKs

Customer is a root entity. Almost nothing FKs out of customer; facts FK into the dimensions, never the reverse. CI will enforce an outbound-FK ceiling on customer (planned; not yet CI-gated). Cross-entity foreign keys are single-column, never composite.

### 11. Tags and PII

The `dbx_data_type` tag is required on every table. The `dbx_pii_*` tags (name, email, phone, dob, address, financial, identifier, and so on) are mandatory on PII columns and feed UC Governed Tags plus ABAC masking and row filters. The fuller dbx-prefixed vocabulary (dbx_subdomain, optional dbx_division, dbx_value_regex, dbx_business_glossary_term, dbx_self_ref_fk, dbx_association_edges) is recommended. These ORDM tags map onto Databricks-native governance where a native concept exists (ADR 0010): certification uses the system tag `system.certification_status` (`certified`|`deprecated`, set via `SET TAG`); `dbx_pii_*` are declarative deploy-time signals that coexist with the reserved `class.*` tags Databricks Data Classification auto-applies from data scanning (ORDM does not set `class.*` — it is a reserved system namespace); `dbx_subdomain` maps to a UC Domains governed tag (`{parent}/{subdomain}`) applied as an optional account-level overlay (the UC Domains overlay, PR #40); and `dbx_business_glossary_term` maps to the UC Glossary object. ORDM's own tag keys never use the reserved `system.`/`class.`/`sap.` prefixes. Agent-applied tags require SME review before merge. On payment card data: only tokenized payment instruments are stored, never raw PAN or cardholder name, and customer and transaction schemas carry an explicit cardholder-data-out-of-scope statement.

### 12. Data quality

Every table has at least one DQ check. Every fact has an FK-orphan check and every monetary fact has a single-reporting-currency check. CI does not yet verify this coverage (`DQ-FACT-COVERAGE`, planned). Checks use the parseable convention `-- check: <name> | severity: error|warn|metric`, run cluster-free and COUNT-wrapped, and CI fails on any error-severity check. Static consistency tests assert that synthetic-generator column lists match the DDL, generator enum values are a subset of declared allowed values, no catalog or workspace is hardcoded, no banned SQL appears, and no license header sits in authored DDL. SCD2 checks assert current-open, non-current-closed, and start-before-end.

### 13. Metric views (phased, v1.x hardening target)

Outcome KPIs live in `metric-views/` or `gold/`, never on masters. Where metric views are used, they ship as UC Metric Views (WITH METRICS LANGUAGE YAML), one file per view, and must populate agent metadata: synonyms, display_name, format, and comment. The v1.x bar is full UC Metric Views with populated metadata for all outcome KPIs. This is phased rather than gated on the first merge, because neither reference contribution ships it fully today. Populated agent metadata is the differentiator and the thing to push toward, not a reason to block a first merge. No raw aggregate or derived-metric SQL lives outside metric views or gold. Business glossary: each domain/package `glossary.md` is the authoritative term source and is authored UC-Glossary-ready — terms may declare SKOS-style relationships (broader / narrower / related / synonyms) so they map onto the UC Glossary object and feed Genie Ontology (ADR 0010); SKOS is the pragmatic bar, full OWL is out of scope.

### 14. Provenance and licensing

Every published file carries a provenance header: domain, version tag (the value in [`VERSION`](../VERSION), or v1_ecm), generation date, LLM-generated flag, last-human-reviewed date and reviewer, and a license reference comment. CI does not yet verify the header (`PROVENANCE-HEADER`, planned). No copyright or license body lives in authored DDL (already enforced by the static model-consistency tests). Comments and identifiers are vendor-neutral. CI does not yet check this (`VENDOR-NEUTRAL`, planned). A repo NOTICE declares independent authorship, inspired by ARTS ODM, GS1, ISO, and public retail data models, and is not a redistribution of any copyrighted standard.

### 15. Multi-partner repo governance

A multi-partner repo needs four rules that pure modeling standards miss. Contribution throughput: cap tables per PR, set a review SLA, and split review so mechanical gates run first and humans adjudicate only substance, because slow throughput means the curated core never ships. Schema versioning and deprecation: a backward-incompatible change to a published canonical table (rename, type change, drop column) requires a schema-version bump and a deprecation window, or downstream ABAC, Genie, and metric-view consumers break silently. Inbound contribution licensing: contributions are accepted under the repo's Apache-2.0 license (inbound = outbound), with no CLA or DCO sign-off required for now (revisit only if external contribution volume grows); and content is not borrowed from any upstream repo that lacks an explicit compatible license, since an unlicensed repo is all-rights-reserved. Self-FK exception: the tree self-FK carve-out is a first-class named exception in the FK-graph CI rule.

### 16. SCD2 join contract in consuming views

A gold or metric view that reads an SCD2 master must resolve the correct version the right way, and the right way is cheap. ORDM facts already carry an ingest-resolved, version-specific surrogate (`sales.product_sk` is "the product version in effect at the sale"), so a fact-to-dimension join on the dimension's primary-key `_sk` is a plain 1:1 equi-join that is already as-of-correct: no range join, no `is_current` filter, nothing to tune. This is the default, and it is both correct and fast.

A range/as-of predicate (`fact.date >= dim.effective_from_date AND (dim.effective_to_date IS NULL OR fact.date < dim.effective_to_date)`) is reserved for the narrow case of joining a fact to a history table on a non-primary-key `_sk` (a price/cost history keyed on `product_price_sk`, not `product_sk`); such a predicate is portable ANSI SQL and auto-triggers the Databricks range-join optimization, so it needs no engine-specific hint in shipped SQL, and the target dimensions are small enough to broadcast anyway.

Four things are defects, caught by CI: (a) joining an SCD2 table on one of its non-PK `_sk` columns with no version predicate (fan-out over every version); (b) equating two `_sk` and also filtering `is_current = TRUE` in the same join (the version-specific `_sk` already pins the version, so the filter silently drops historical-version fact rows); (c) `GROUP BY` or window `PARTITION BY` a version-specific `_sk` with no date/period key (a re-versioned entity fragments across groups and rolling windows reset at each boundary — aggregate and partition on the durable `_id`); and (d) `COUNT(DISTINCT _sk)` / `approx_count_distinct` over an SCD2 `_sk` (a re-versioned entity is double-counted — count the durable `_id`). Metric views must not expose a bare SCD2 `_sk` as a groupable `dimension`, because the surrogate is version-specific and per-deployment; expose the durable `_id`. The durable `_id`, not the `_sk`, is the portable cross-deployment join key.

## B. Design principles

These guide modeling judgment and are adjudicated in review rather than by a script.

Shared common layer plus outcome-specific extensions. The twelve outcomes are not twelve data domains. Customer, Product, Location, and Transaction are defined once in the shared core, and each outcome adds only the tables and metric views unique to it. Customer 360 and a shopping assistant both reference the same Customer entity, so there are no redefinitions and no drift across listings.

Truly minimum-viable. Customer is profile, address, contact, and consent, plus an optional account for B2B, not ten tables and hundreds of columns. The public retail data models cover customer in roughly 60 to 80 attributes; that is the target, not the union of every vendor's opinions.

One source of truth per concept. A concept like marketing consent lives in exactly one place (the consent table), not duplicated across profile, account, and contact. Communication preferences live in their own table. No redundant opt-in flags on masters.

No god-tables. Each table is one coherent business concept. The EAV anti-pattern (one preference table conflating a dozen unrelated concerns) is split into focused tables, with a small attribute table for the long tail.

Domains organized by entity, not by use case. The customer domain is identity, contact, address, and consent. Segments and scores live in a marketing or customer-intelligence domain. Regulator-facing consent lives in a privacy or compliance domain. The domain folder name equals the UC schema name.

PCI placement. Tokenized payment instruments live in a vault-adjacent finance schema, not on the customer master. Storing cardholder name on customer would put the customer schema in PCI scope.

Catalog discipline. Catalog and schema are injected as tokens, never hardcoded, so different deployments do not collide and deployment order never silently matters.

Clustering key selection. Liquid Clustering is the physical layout, with `CLUSTER BY AUTO` the zero-tuning default an adopter should prefer once a table has representative query workload (AUTO needs Predictive Optimization plus enough scan telemetry to pick keys, which a freshly deployed table lacks — which is why the shipped tables set explicit keys). When keys are explicit, cluster on the columns the table is actually filtered, joined, or MERGEd on (surrogate and business keys, dates), and never exceed four (under roughly 10 TB, extra keys dilute skipping). Unlike partitioning, Liquid Clustering is multi-dimensional and order-independent, so key order does not matter and low-cardinality keys are fine: combining several low-cardinality keys, or a low-cardinality key with a higher-cardinality one, skips well when those are the columns queries filter on. The one thing not to do is cluster on a continuous measure that is only ever selected — a percentage, rate, score, or money amount — because it is never a filter or join predicate, so it earns no data-skipping and just spends a key slot; that case is enforced by the CLUSTER-KEY-TYPE conformance rule. One soft caution rather than a rule: a mutable low-cardinality lifecycle enum (status, severity) as the sole clustering key can churn the layout as rows change state, so prefer a stable key (a surrogate/business key or date) alongside it; keeping the enum as a query predicate is also fine. Never partition below roughly 1 TB (cluster instead). Deletion vectors are auto-enabled by Liquid Clustering, and Predictive Optimization (auto OPTIMIZE, VACUUM, ANALYZE) is recommended on Unity Catalog managed tables. As guidance rather than a rule: data-skipping statistics cover the first 32 columns, so on a wide table (more than about 32 columns) place long free-text columns after the filter columns — most ORDM tables are narrower than that, so this rarely applies.

A reference data model is the intersection of universal concepts with extensibility hooks for everything else, not the union of every retailer's opinions. Inverting that union is the job.

## C. What ORDM leaves flexible

The profile_core and profile_pii physical split is optional; with ABAC, inline PII plus column masks is acceptable, so log the per-table call. Silver internal modeling style (3NF or Inmon versus Data Vault) is flexible for an adopter's private integration layer; ORDM publishes a pragmatically denormalized conformed core. Physical layout (clustering, partitioning) is recommended, never mandated, with one narrow exception: clustering on a continuous measure is a CI error (the CLUSTER-KEY-TYPE mandate), because such a key can never help data-skipping; the same mandate also caps a clause at four keys and rejects a cluster key that is not a declared column (both are pre-deploy correctness guards, not layout opinions). §B "Clustering key selection" gives the key-selection guidance, with Liquid Clustering and CLUSTER BY AUTO the zero-tuning default. One Big Table and denormalized serving views are allowed in the gold layer only. Reference value sourcing is recommended to ground reference domains in ISO, GS1, and UN/CEFACT. Cross-layer enum casing is a deliberate choice to note in the naming guide, not an initial CI blocker. ODCS contracts are generated from the DDL and drift-checked in CI; ODPS is a future target. Lakeflow pipeline and ingestion code is out of scope. Several domain-scope calls (store versus location, supplier and employee v1 versus v1.x, a party supertype, a price or cost master, payment-domain placement, the transaction grain split) are open decisions for the working group, recorded as ADRs in `governance/decisions/`, not standards to harden now.

## D. Naming conventions

All identifiers are lowercase snake_case, everywhere. Use the long form of every suffix: `_code` not `_cd`, `_amount` not `_amt`, `_flag` not `_flg`, plus `_timestamp`, `_date`, `_quantity`.

Schemas and domains. A canonical-core domain folder name equals its UC schema name, a short business noun (customer, product, store, transaction, supplier, procurement, payment, calendar). The one exception is the order domain, whose folder is `order` (singular) but whose UC schema is `orders` (plural), because `order` is a reserved word; this is deliberate and documented. An outcome-package schema is the full outcome slug in snake_case (promote_with_purpose, early_risk_detection, actionable_customer_understanding, data_sharing_with_suppliers), so it never collides with a core domain.

Tables in canonical core are bare snake_case business nouns with no `dim_` or `fact_` prefix; the classification lives in the required `dbx_data_type` tag, not in the name. Masters and dimensions are singular nouns (profile, product, supplier, store). Facts are named for the event or grain (sales, payment, customer_order_line, purchase_order_line, inventory_position, inventory_movement). Reference tables are the concept itself (currency, country, unit_of_measure, channel, fiscal_calendar, fx_rate). Association and bridge tables are named for the relationship and tagged association, with a `_bridge` or `_membership` suffix where it reads clearly.

Tables and views in outcome packages. Extension tables are bare snake_case nouns, same rule as core (promotion, promotion_scope). Gold materialized views carry a `gold_` prefix followed by the subject (gold_customer_ltv, gold_supplier_scorecard, gold_category_growth), which keeps derived and serving objects obvious at a glance. UC Metric Views ship one file per view under `metric-views/`, named for the subject, with the view object in the package's metrics schema.

Columns. The surrogate primary key is `<stem>_sk` (BIGINT IDENTITY) and the durable business key is `<stem>_id` (STRING), where `<stem>` names the entity's grain/role (see "Key-stem naming by grain/role" below). Foreign-key columns carry the bare target key name with no `_fk` suffix (product_sk, store_sk). Booleans use the `is_*` form. The audit block uses the fixed names created_timestamp, source_updated_timestamp, record_source, load_timestamp; SCD2 masters add effective_from_date, effective_to_date, is_current.

Key-stem naming by grain/role. The `<stem>` in `<stem>_sk` / `<stem>_id` names the entity's grain or role and must be used **consistently** wherever that entity is joined; it is not required to be a character-for-character copy of the physical table name (this matches Kimball, dbt, Data Vault, and the SQL style guide — none mandate stem = table name; the rule is consistency of the stem). The stem defaults to the table name; the cases below deliberately differ and are **documented, intentional conventions — not defects**, so linters and automated/AI reviewers should not flag them (a reviewer verifies the stem is used consistently, not that it equals the table name):

- **Date / calendar dimension → date-stemmed.** The calendar dimension keys on the **date grain** — the natural `date_key` today, with the `date_sk` surrogate + `date_id` durable key landing under #46 — not on the table name (`fiscal_calendar`). Kimball explicitly exempts the date dimension from the surrogate rule, and every reference model (TPC-DS `d_date_sk`, AdventureWorks `DateKey`) stems the key on the date grain, never the table; a table-matching `fiscal_calendar_sk` would be the outlier.
- **Reference / code tables → the natural code.** Small, stable ISO/standard-code lookups (currency, country, unit-of-measure, channel) use their natural code as the durable key where practical (`currency_id = 'USD'` per ISO 4217, `country_id = 'US'` per ISO 3166) rather than minting a meaningless surrogate. ORDM currently carries these code sets as inline `*_code` columns with allowed-value comments rather than as standalone dimensions; if promoted to a table, key on the code.
- **Entity split across role tables (no supertype table).** A business entity may be modeled as several role tables rather than one — the "customer" is `profile` (person) + `account` (organization), not a single `customer` table. Each role table keys conventionally on its own stem (`profile_sk`, `account_sk`); there is deliberately no `customer` table or `customer_sk`, because "customer" is a role/view over the two. Don't flag the absence of a `customer` table/key as a naming defect (a party/customer supertype is open working-group work). Separately, genuine **role reuse** — one dimension joined under multiple roles (e.g. `order_date` / `ship_date` both resolving to the date dimension) — uses role-qualified stems, applied consistently.
- **Facts carry a uniform surrogate `<stem>_sk` — a deliberate ORDM deviation.** Classic Kimball keys a fact on the composite of its dimension FKs plus a degenerate dimension (e.g. TPC-DS `store_sales` = `(ss_item_sk, ss_ticket_number)`), and treats a fact surrogate as an optional ETL convenience, not the logical PK. ORDM instead gives **every** table — facts included — the same `<stem>_sk` identity PK. This is an intentional house convention (one uniform key shape so generators, the Lakebase binding's enforced PK/FK, and downstream joins never special-case a table); the fact's grain is still asserted by its FK columns + a DQ uniqueness check, and the operational identifier (order/ticket/payment number) is retained as a degenerate `*_id`.

Constraints follow `pk_<table>`, `fk_<child>_<parent>`, and `chk_<table>_<rule>`.

Functions, such as column-mask functions, are verb-led and describe what they do (mask_pii_text, mask_pii_date, mask_pii_decimal) and live in `masks.sql`.

Tags use the `dbx_` prefix (dbx_data_type, dbx_pii_name, dbx_pii_email, dbx_subdomain, dbx_value_regex); `dbx_` is ORDM's own namespace and must never collide with Databricks' reserved `system.`/`class.`/`sap.` prefixes (ADR 0010).

Files. One CREATE statement per `.sql` file, and the file is named exactly for the object it defines (profile.sql, sales.sql, gold_customer_ltv.sql).

Enum value casing. Lowercase is recommended for stored enum values across layers; pick one direction deliberately rather than mixing lowercase core enums with uppercase gold enums.

## Conformance matrix

The rules below are tracked as data in `standards/rules.yaml`, which is the single source of truth. The CI checks enforce the rules marked enforced, and this table is generated from the registry, so the prose, the checks, and this matrix cannot drift. The generator is `tools/gen_conformance_matrix.py` and `tests/standards/test_standards_meta.py` fails if any of the three disagree.

<!-- CONFORMANCE-MATRIX:START (generated by tools/gen_conformance_matrix.py; do not edit by hand) -->

| Rule ID | Title | Section | Layer | Severity | Status | Enforced by |
|---|---|---|---|---|---|---|
| `ARTIFACT-NO-MD-UNDER-TABLES` | No markdown under a tables/ directory | A.1 | static | error | enforced | `test_no_markdown_under_tables` |
| `ARTIFACT-ONE-CREATE` | One CREATE statement per file | A.1 | static | error | enforced | `test_one_create_per_file` |
| `CLUSTER-KEY-TYPE` | Clustering keys are filter/join columns, not continuous measures | B | static | error | enforced | `test_cluster_key_type` |
| `FK-COMPLETENESS` | Reference completeness — cross-entity references are FKs on a surrogate | A.5 | static | error | enforced | `test_fk_completeness` |
| `LAYER-INTEGRITY` | Canonical core never FKs into a gold or outcome schema | A.3 | static | error | enforced | `test_layer_integrity` |
| `NO-INLINE-CHECK` | CHECK constraints via ALTER, never inline in CREATE TABLE | A.7 | static | error | enforced | `test_no_inline_check` |
| `PK-CONTRACT` | Surrogate primary key is a named BIGINT identity | A.4 | static | error | enforced | `test_pk_contract` |
| `SCD2-JOIN-CONTRACT` | Gold and metric views resolve SCD2 history correctly | A.16 | static | error | enforced | `test_scd2_join_contract` |
| `TAGS-DATA-TYPE` | dbx_data_type tag required on every table | A.11 | static | error | enforced | `test_tags_data_type` |
| `TYPING-MONEY` | Strict typing, money is DECIMAL not FLOAT or DOUBLE | A.6 | static | error | enforced | `test_typing_money` |
| `DQ-FACT-COVERAGE` | Every fact has an orphan and single-currency check | A.12 | spark | error | planned | - |
| `NAMING-CONSTRAINTS` | Constraint and identifier naming | D | static | warn | planned | - |
| `NO-DERIVED-ON-MASTER` | No derived metrics on master or dimension tables | A.9 | static | warn | planned | - |
| `PROVENANCE-HEADER` | Provenance header present, no license body in DDL | A.14 | static | error | planned | - |
| `THIN-ROOT-FK-CEILING` | Thin customer root, inbound-only FKs | A.10 | static | warn | planned | - |
| `VENDOR-NEUTRAL` | Vendor-neutral comments and names | A.14 | static | error | planned | - |

Tracked exceptions (excused until fixed): 29.
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/gold/gold_price_actuals.sql::history-fanout
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/metric-views/aggregation_features.sql::reverse-bug
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/metric-views/trend_features.sql::reverse-bug
- `SCD2-JOIN-CONTRACT`: outcome-packages/promote-with-purpose/gold/gold_trade_promotion.sql::reverse-bug
- `SCD2-JOIN-CONTRACT`: outcome-packages/promote-with-purpose/gold/gold_promo_roi_by_category.sql::reverse-bug
- `SCD2-JOIN-CONTRACT`: outcome-packages/actionable-customer-understanding/gold/gold_customer_ltv.sql::frag-groupby
- `SCD2-JOIN-CONTRACT`: outcome-packages/early-risk-detection/gold/gold_procurement_risk.sql::frag-groupby
- `SCD2-JOIN-CONTRACT`: outcome-packages/early-risk-detection/gold/gold_supplier_scorecard.sql::frag-groupby
- `SCD2-JOIN-CONTRACT`: outcome-packages/promote-with-purpose/gold/gold_promo_roi_by_category.sql::frag-groupby
- `SCD2-JOIN-CONTRACT`: outcome-packages/promote-with-purpose/gold/gold_trade_promotion.sql::frag-groupby
- `SCD2-JOIN-CONTRACT`: outcome-packages/promote-with-purpose/gold/gold_weekly_baseline.sql::frag-groupby
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/gold/gold_assortment_optimization.sql::frag-partition
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/gold/gold_bucket_features.sql::frag-partition
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/gold/gold_price_actuals.sql::frag-partition
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/gold/gold_promotional_features.sql::frag-partition
- `SCD2-JOIN-CONTRACT`: outcome-packages/promote-with-purpose/gold/gold_trade_promotion.sql::frag-partition
- `SCD2-JOIN-CONTRACT`: outcome-packages/promote-with-purpose/gold/gold_weekly_baseline.sql::frag-partition
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/gold/gold_promotional_features.sql::distinct-count-sk
- `SCD2-JOIN-CONTRACT`: outcome-packages/data-sharing-with-suppliers/gold/gold_category_growth.sql::distinct-count-sk
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/metric-views/aggregation_features.sql::sk-dimension
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/metric-views/assortment_performance.sql::sk-dimension
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/metric-views/assortment_recommendations.sql::sk-dimension
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/metric-views/competitor_analysis.sql::sk-dimension
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/metric-views/lagging_features.sql::sk-dimension
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/metric-views/outcome_variables.sql::sk-dimension
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/metric-views/price_actuals.sql::sk-dimension
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/metric-views/rolling_features.sql::sk-dimension
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/metric-views/sales_actuals.sql::sk-dimension
- `SCD2-JOIN-CONTRACT`: outcome-packages/balancing-margin-and-volume/metric-views/trend_features.sql::sk-dimension

<!-- CONFORMANCE-MATRIX:END -->

## What good looks like

A reference data model is the intersection of universal concepts, with extensibility hooks for everything else. The opposite, the union of every retailer's opinions, is exactly what is not useful. ORDM's job is to invert that, and these standards are how it stays inverted as more partners contribute.
