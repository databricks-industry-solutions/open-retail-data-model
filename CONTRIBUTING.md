# Contributing to ORDM

This is a small, partner-first working group, so the process stays light. Jump in. We add structure as volume grows. The four things that always hold are synthetic data only, vendor-neutral content, one file per table, and docs kept in sync.

ORDM is an open, partner-first retail data foundation (Apache-2.0 on publication) with two layers. The canonical core is the set of conformed business entities (the strict silver layer: Customer, Product, Store, Order, Transaction, Inventory, and so on). The outcome packages are the retail outcomes, each a thin set of extension tables plus UC Metric Views and agent metadata that sit on top of the core. Keep this canonical-core and outcome-package vocabulary, since it is fixed by the charter.

This is the public ORDM repository. Issues and pull requests from forks are welcome. ORDM is developed in a working repository that the maintainers publish from: a pull request opened here is reviewed here, applied to the working repository with your authorship kept, and lands in the next publication commit with you credited as its author or co-author. Contributions are accepted under the Apache-2.0 license of this repository.

The single source of truth for the rules is [`docs/data-model-standards.md`](docs/data-model-standards.md), the ORDM data model standards. This guide operationalizes that standard and points to it rather than restating it. Where the two disagree, the standard wins and this guide is fixed in the same PR.

## 1. The 60-second version

1. Open or claim an issue.
2. Branch with the naming convention in section 4.
3. Build to the fixed folder layout, one file per table, in section 5.
4. Run the local checks (`pytest -q` and `runtime/data-quality/run_checks.py`).
5. Open a PR with the template, link the issue, and ping a reviewer.

Two non-negotiables up front. Use synthetic data only, with no customer data, no partner-proprietary or source-specific material, and no secrets. Commit tables as executable `.sql`, never as markdown.

## 2. Before you start, pick what you are contributing

There are four kinds of contribution, matching the Layer checkboxes in the PR template. A canonical-core entity or domain. An outcome package (tables, metric views, agent metadata). Synthetic data. Docs, governance, or tooling.

Answer one question first. Is this a shared, conformed business entity reused across many outcomes, or is it specific to one outcome and made of metrics, denormalized serving views, and extension tables on top of the core? The worked test: Customer 360 and a shopping assistant both reference the same Customer entity, so Customer is canonical core. Sponsored-placement tables or foot-traffic facts serve one outcome, so they are an outcome package.

Keep scope disciplined. ORDM is the intersection of universal concepts with extension hooks, not the union of every vendor's tables. The customer master is a handful of tables in roughly the 60 to 80 attribute range, not a 300-column, 22-table union. Not every domain ships both layers in v1; publish what is mature and scaffold the rest with a status README.

Out of scope for this repo: bronze and source-aligned silver (SAP, Shopify, POS-conformed), customer-built gold or KPIs, ingestion and pipeline code, real or customer-derived sample data, partner-proprietary mappings, operational or application write-state tables (preference overrides, agent feedback, workflow state), and applications themselves (apps are not a contribution type — an app owns its own state outside ORDM).

## 3. Open an issue first

An issue keeps the small group from colliding and creates the paper trail reviewers and the promotion queue rely on. Use the matching template under `.github/ISSUE_TEMPLATE/`: `new-domain` for a new canonical-core entity, `new-outcome-package`, `change-proposal`, or `review-signoff`.

For a new canonical-core entity, answer the new-domain prompts: the entity, why it belongs in the shared core rather than an outcome package, key attributes, relationships to existing entities, and the proposed owner and reviewer. One entity equals one owning file equals one layer, so before claiming, check `STATUS.md` and `REVIEWERS.md` to confirm the entity is not already owned or in flight. Customer and Product are never defined twice.

Docs-only tweaks can skip the issue and go straight to a PR. Anything that changes structure, naming, scope, or a convention needs an issue so it can be discussed and, if it is a decision, logged as an ADR. A core-versus-outcome placement disagreement gets raised here, not discovered in review (see section 6).

## 4. Branch and PR flow

Branch off `main` using the prefix convention so parallel work is visible. Use `core/<domain>-<topic>` for canonical-core work and `outcome/<package>-<topic>` for an outcome package. `<domain>` is a folder under `canonical-core/`, `<package>` is a folder under `outcome-packages/`, and `<topic>` is a short hyphenated description, usually the table or metric.

| Branch | Means |
|---|---|
| `core/customer-profile-table` | adding the `profile` table to `customer` |
| `core/inventory-stock-position-table` | adding `inventory_position` to `inventory` |
| `core/order-relationships` | adding or fixing foreign keys in `order` |
| `outcome/agentic-commerce-metrics` | adding metric views to `agentic-commerce` |
| `outcome/unified-customer-view-clv-metric` | adding a CLV metric to `unified-customer-view` |

One file per table plus folder-named branches means two people in the same domain differ in `<topic>` and in files, so they do not collide. Open a PR with `.github/PULL_REQUEST_TEMPLATE.md`, fill the Layer section and checklist, link the issue with `Closes #__`, and request a domain reviewer per `REVIEWERS.md`. Merge on a reviewer approval; docs-only tweaks may go straight to `main`. Maintainers (Databricks FE, RCT) hold merge. The canonical core has a single owner; outcome packages keep their own owners. Keep PRs small, ideally one table or one metric view each.

## 5. Where things go

The layout is the structural contract. Once you have seen one folder you know them all.

Canonical-core domain (maps to a UC schema):
```
canonical-core/<domain>/
├── README.md            overview + status
├── tables/<table>.sql   ONE CREATE TABLE PER FILE
├── relationships.sql    UC PK/FK declarations for the domain
├── checks.sql           data-quality assertions
├── glossary.md          business terms
└── masks.sql            optional UC column masks
```

Sample rows come from the domain's generator under `runtime/synthetic-data/generators/`, not from a
committed `samples/` folder.

Outcome package (maps to a Marketplace listing):
```
outcome-packages/<package>/
├── README.md            what outcome it serves + status
├── tables/<table>.sql   extension tables only, never re-declaring core entities
├── metric-views/        one file per UC Metric View (WITH METRICS LANGUAGE YAML)
├── comments.sql         Genie/agent synonyms, display names, format, glossary terms
├── gold/                materialized views
├── filters.sql          optional UC row filters (deploy-gated, like masks.sql)
├── checks.sql
├── glossary.md
├── use-cases.yaml       (optional) business use cases the package enables (name + status)
├── sample-queries.sql
└── notebook-templates/
```

The hard layout rules CI enforces: markdown is forbidden under any `tables/` directory (narrative and research go to `docs/`, design notes under `docs/design/`); a `.sql` file may contain only one CREATE statement; one entity is defined in exactly one file in exactly one layer. Program-level homes: `docs/` for architecture, principles, and glossary; `governance/decisions/` for ADRs; `tools/` for the config resolver, generators and checks; `runtime/data-quality/run_checks.py`; `tests/` for cluster-free static tests; `runtime/synthetic-data/generators/` for data generators; `ops/` for operational/CI infra that is not part of the data model (kept in the pre-publication repository, not published); `contracts/` for generated data contracts (e.g. the optional ODCS export in `contracts/odcs/`).

## 6. The core-versus-outcome promotion process

This is the decision the working group keeps re-arguing, so here is a deterministic procedure.

The boundary, in one line: canonical core is silver and must never declare a foreign key into a gold or outcome schema, and the core must stand alone, with no dependency on a member that only exists once a gold dimension deploys. This is the single layer-inversion blocker that has shown up in a real PR (a silver sales fact with an FK up into a gold promotion schema, plus a NO_PROMO member that only exists in gold).

The placement decision tree, in order. Is the entity referenced by more than one outcome? Does it carry conformed master or dimension semantics (identity, product, store, calendar) rather than metrics? Does it have no outbound dependency on any outcome-specific table? If all three are yes, it is canonical core. If it is metrics, denormalized serving, or single-outcome extension tables, it is an outcome package.

Promotion path when something starts in an outcome and proves to be shared. Open a change-proposal issue, get the affected outcome owners and the canonical-core owner to agree, move the table into the correct canonical-core domain as its own `.sql` file, convert any string or hash keys to the BIGINT identity contract, strip derived metrics, then re-point the outcome package to consume it. Record the move as an ADR in `governance/decisions/`.

Two standard fixes for a silver-to-gold FK. Option A, promote the dimension into a shared canonical-core domain so the core entity can reference it within silver. Option B, drop the declared FK from canonical core and keep only a documented logical relationship resolved inside the outcome package. Either way the core must deploy on its own. If owners disagree on placement, the canonical-core owner makes the call, logs it as an ADR, and the default is to keep the core thin and push breadth into outcome packages.

## 6a. Refine committed entities; do not replace or redefine them

Before publication, you are encouraged to improve an already-committed table, domain, or core entity — adding attributes, fixing a check, tightening a type — **directly in its owning file**. Refinement is additive and occasionally corrective. It is **not** a wholesale replacement, and it never means standing up a second, parallel definition of the same entity (one entity equals one owning file). Overlapping and even breaking changes are normal pre-publication and get reconciled on the path to publish; once a domain or package is published, the [schema versioning policy](docs/versioning-policy.md) governs changes. So when a contribution re-models something already in the core (for example a customer profile, product, store, or consent), fold the useful parts into the committed table rather than keeping a parallel one.

## 7. What every contribution must contain

A contribution is done when it ships the right artifacts for its type. The field-level rules (the PK contract, SCD2 columns, the audit block, typing, tags, constraints) live in the standard, [`docs/data-model-standards.md`](docs/data-model-standards.md); this is the artifact checklist. The lifecycle states and the must / should / nice-to-have tiers behind "done" are defined in [`docs/definition-of-done.md`](docs/definition-of-done.md).

A canonical-core entity ships the table `.sql` (with its provenance header, the BIGINT identity surrogate PK plus durable business key, the layer-appropriate audit block, SCD2 columns on masters, and the required `dbx_data_type` and `dbx_pii_*` tags), an entry in `relationships.sql`, at least one DQ check in `checks.sql` (plus an FK-orphan check on facts and a single-currency check on monetary facts), a `glossary.md` entry, and small synthetic samples or a generator. A generator exposes a `run(ctx: DeployContext)` entrypoint and is registered as a `GenSpec` in `runtime/synthetic-data/generators/_registry.py` (declaring the schema keys it `provides`/`depends_on`) — an unregistered generator will not run under the `generate_all` deploy task.

An outcome package ships extension tables only (consuming, never redefining, core entities), UC Metric Views as the home for derived metrics with populated agent metadata, a README stating the outcome, checks and glossary, optionally a `use-cases.yaml` listing the business use cases it enables (`use_cases: [{name, status, tables?}]`, status one of blocked / in-progress / planned / done; the optional `tables:` maps a use case to the gold tables that serve it, which drives the explorer's L1 grouping and the use-case -> core lineage reveal; surfaced in the explorer; not a scored MUST), and sample queries or a notebook template.

Synthetic data ships deterministic, seeded generators whose column lists and enum values match the DDL, with no real or customer-derived data and FK-correct child rows.

Docs sync is part of this contract, not an afterthought (see section 8).

## 8. Keep docs in sync

Any change to structure, process, naming, or scope updates the docs in the same PR. If a teammate reading only the docs would be surprised by your change, the docs are not done.

Before opening a PR, check `README.md` (homepage, what is inside, quick links); `STATUS.md` (flip the domain or package status and add yourself, never leaving a shipped domain marked Planned and never advertising a stub as shipped — the README's status badge and status tables, plus the per-folder "> Status:" lines in each domain/package README and glossary, are all **generated** from `STATUS.md` by `tools/gen_status.py`, so edit `STATUS.md` and run `make regen`, never hand-edit those blocks; the outcome-package **Use cases** column is likewise generated, from each package's `use-cases.yaml` via `model.json`, so flipping a use case's status is also a `make regen` trigger); `docs/architecture.md` (if layers, domains, or layout changed); `docs/data-model-standards.md` (if a rule changed or was added); `CONTRIBUTING.md` or `GOVERNANCE.md` (if the workflow changed); and the relevant folder README. A `glossary.md` keeps pace with the tables shipped in its domain or package. A folder-specific status note (for example, which tables are still in review) goes on a separate `> ` line right after the `> Status:` line (such as `> Note: identity slice in review`) or as plain text below it, never on the status line itself and never as a second `> Status:` line: the generator rewrites the status line from `STATUS.md`, keeps only a `· Last reviewed: YYYY-MM-DD` or `· Marketplace listing: <state>` suffix on it, and removes any later `> Status:` line in the header as a duplicate. Finalized structure, naming, or scope decisions get an ADR in `governance/decisions/`.

## 9. Review gates

Two tiers, so it is clear what is automatic versus human.

Automated CI gates run on every PR to `main` (see `.github/workflows/databricks-ci.yml`). A `base-must-be-main` check fails any PR not targeting main (no stacked PRs); it is not yet required due to no branch protection. A cluster-free static gate runs sqlglot-based consistency tests: generator columns match the DDL, generator enum values are a subset of declared allowed values, no catalog or workspace is hardcoded, no banned SQL appears, and no license headers sit in authored files. The `test` job (4 shards, reported as one `unit + spark tests` check; see `docs/testing.md`) enforces the machine-checkable mandates from the rules registry (`standards/rules.yaml`): one CREATE per file, no markdown under tables, layer integrity, the primary-key contract, strict typing, no inline CHECK constraints, required data-type tags, SCD2 join correctness, FK completeness, and clustering-key type discipline. A meta-test keeps the registry, the checks, and the standard's conformance matrix from drifting. A Databricks-native dependency guardrail fails the build if a non-Databricks engine is introduced. Then a bundle validate, deploy, and destroy step verifies the model actually loads. The full picture, and how to run each layer, is in [`docs/testing.md`](docs/testing.md).

CI lint expectations you can pre-empt locally. Enforced by CI: strict typing (no STRING for numeric columns; no FLOAT or DOUBLE on monetary columns), no inline CHECK constraints, the silver-never-FKs-gold check, one-CREATE-per-file and no-markdown-under-tables checks, the primary-key contract, the required `dbx_data_type` tag, SCD2 join correctness, FK completeness, and clustering-key type discipline. Planned (not yet CI-gated): provenance headers, vendor-neutral comments, constraint naming (`fk_`/`chk_`/`is_*`), no derived-metric column patterns on tables tagged `dbx_data_type=master`, the thin-customer-root outbound-FK ceiling, and fact-level DQ coverage. [`standards/rules.yaml`](standards/rules.yaml) is the full list.

The human review gate: a domain reviewer in `REVIEWERS.md` signs off before an entity enters the publication queue, focusing on substance (placement, grain, naming, principle conformance) since CI covers mechanics. The assigned reviewer records the verdict in a review-signoff issue (`.github/ISSUE_TEMPLATE/review-signoff.md`), and that issue is linked in the Sign-off column of `REVIEWERS.md`; a 🟢 status needs that recorded sign-off, not just an assigned Reviewer, and `tools/gen_status.py --check` enforces it. An owner may review their own deliverable if the self-review is disclosed (in the sign-off issue or the Self-reviews note in `REVIEWERS.md`); see [GOVERNANCE.md](GOVERNANCE.md) for when ✅ Published then needs a second, independent reviewer. The second sign-off goes in the same Sign-off cell (`#A, #B`). Once `INITIAL_PUBLICATION_SELF_REVIEW` is switched off after the initial public release, `gen_status.py --check` fails a ✅ row whose Owner is also its Reviewer with only one sign-off; it checks the count, not who signed.

Run it locally so CI is not the first place you see a failure: `pip install -r requirements-dev.txt`, then `pytest -q` for the required suite, `pytest -q tests/standards` for the standards-conformance suite, `make check` to confirm every generated artifact is in sync with the source, and `python runtime/data-quality/run_checks.py` for the DQ assertions. See [`docs/testing.md`](docs/testing.md) for what each layer does.

Keeping the repo in sync: the hand-authored input (the DDL, `relationships.sql`, the gold-view SQL, `use-cases.yaml`, the glossaries) is the single source of truth; everything else — the ODCS contracts, the ER diagram sources, `explorer/public/model.json` (schema, FK, and the use-case -> core lineage), the conformance matrix, and the README status surfaces (count badge + status tables, from `STATUS.md`) — is GENERATED from it. Run **`make regen`** after any model change and commit the result (then `make regen-svg` if you touched an ER diagram); CI runs **`make check`** and fails if any committed artifact drifted, and on same-repo PRs the `regen-artifacts` job runs **`make regen-ci`** to regenerate and commit them for you. The rendered SVGs are drift-gated too, by a deterministic sha stamp (`make check-svg`, part of `make check`), so no derived file type can silently fall out of sync. One consequence for **fork** contributors: same-repo PRs get their SVGs auto-rendered by the `regen-artifacts` job, but a fork PR that edits an ER diagram will fail the drift guard until you run `make regen-svg` locally and commit the result (that render needs Node + mermaid-cli; the `check-svg` gate itself is pure-python and needs neither). Adding a new derived artifact means adding its generator to the `Makefile` once, in `regen-ci` (which both your local `make regen` and that CI job call), so it is regenerated and gated everywhere without touching the workflow. Two exceptions are gated by the standards-conformance job rather than auto-committed (because they touch human-edited prose): the conformance matrix and the README status surfaces both live in `make regen`/`make check` but not the auto-commit subset. The README Contributors grid is generated in the working repository.

Publication: maintainers publish accepted work in curated batches, never automatically. Each publication commit names the people who wrote that work as its author or co-authors.

## 10. The rules that matter

This is a digest. The full, authoritative rule set with rationale is the standard, [`docs/data-model-standards.md`](docs/data-model-standards.md).

Do this: one file per table, executable `.sql`; silver never FKs into gold; BIGINT GENERATED ALWAYS AS IDENTITY surrogate PK plus durable STRING business key; strict typing with DECIMAL(18,x) for stored money and DOUBLE for derived ratios and non-monetary continuous values; enum and type categories as enforced Delta CHECK constraints, with brand and provider values left as free STRING; SCD2 on masters with the layer-aware audit block; no derived metrics on master or dimension tables; thin customer root with inbound-only cross-entity FKs; required `dbx_data_type` and `dbx_pii_*` tags; UC PK and FK informational only (integrity from CI plus synthetic regen); provenance header and NOTICE-based attribution on every file; vendor-neutral comments; snake_case identifiers with `pk_`, `fk_<child>_<parent>`, `chk_` prefixes, `is_*` booleans, and FK columns carrying the bare target key name.

Log a decision rather than force a shape on these: the profile_core and profile_pii split is optional given ABAC; physical layout (liquid clustering with CLUSTER BY AUTO) is recommended, never mandated, with the one CLUSTER-KEY-TYPE exception (clustering on a continuous measure is a CI error); OBT and denormalized serving views are allowed only in the gold layer; ODCS contracts are generated and drift-checked in CI, while ODPS is a future target.

## 11. Worked example

Add a canonical-core table end to end. Open the new-domain issue for `inventory_position`. Branch `core/inventory-stock-position-table`. Create `canonical-core/inventory/tables/inventory_position.sql` with the provenance header, BIGINT identity PK, typed columns, and `dbx_data_type=transactional`. Add the FK to `relationships.sql` against the product and store parents. Add an FK-orphan check to `checks.sql`. Add the glossary entry. Add a seeded generator with a `run(ctx)` entrypoint and register its `GenSpec` in `runtime/synthetic-data/generators/_registry.py`. Update `STATUS.md` and the inventory README. Run `pytest -q` and `run_checks.py`. Open the PR with the template, link the issue, and request the Inventory reviewer.

Add an outcome metric. Branch `outcome/unified-customer-view-clv-metric`. Add `metric-views/customer_ltv.sql` as a UC Metric View consuming the canonical customer entity, with no re-declaration of core tables. Populate agent metadata (synonyms, display name, format). Add `sample-queries.sql` and a notebook template. Confirm no derived metric leaked onto a master. Update the package README and `STATUS.md`. Open the PR and request a reviewer.

The two most common rejection causes to avoid: misfiling outcome (gold) content under `canonical-core/` (route it to the right `outcome-packages/` scaffold), and shipping a multi-table markdown design doc instead of one-CREATE-per-file `.sql` (put the narrative in `docs/` (design notes under `docs/design/`) and extract per-table `.sql`).

## 12. Help and pointers

Ping the domain owner or reviewer in `REVIEWERS.md`, the canonical-core owner for placement and promotion calls, and maintainers for merge and publication questions. Discussion belongs in Issues, not in committed files.

An AI skill makes this easier: `ordm-data-modeling` authors or adapts a conformant model. It uses the open Agent Skills format, is in [`.agents/skills/`](.agents/skills/) and [`.claude/skills/`](.claude/skills/), and is available as soon as you open this repo in Claude Code, GitHub Copilot or OpenAI Codex. See [`docs/ai-skills.md`](docs/ai-skills.md) to plug it into your own or a customer repo.

Reference links: [`docs/data-model-standards.md`](docs/data-model-standards.md) (the standard), [`docs/ai-skills.md`](docs/ai-skills.md) (the AI skill), [`docs/architecture.md`](docs/architecture.md), [`GOVERNANCE.md`](GOVERNANCE.md), [`REVIEWERS.md`](REVIEWERS.md), [`STATUS.md`](STATUS.md), [`governance/decisions/`](governance/decisions/), and the issue and PR templates.

The process is intentionally light while the group is small. Jump in, and we add structure as volume grows.
