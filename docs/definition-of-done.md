# Definition of Done

This page defines the lifecycle states a domain or outcome package moves through, and what "done" means at each gate. It is the shared vocabulary behind `STATUS.md` and the ownership tracker. The field-level rules live in [`data-model-standards.md`](data-model-standards.md); the artifact checklist lives in [`CONTRIBUTING.md`](../CONTRIBUTING.md) §7; review gates in §9.

## Status ladder

| Status | Meaning | Entry criteria |
|---|---|---|
| ⚪ **Planned** | Identified, not started. | Listed in `STATUS.md` / the tracker with an owner (or owner TBD). |
| 🟡 **In progress** | Being built; some artifacts exist but the MUST tier is incomplete. | At least one real artifact committed (a table, a check, a draft). Not all MUST items present. |
| 🔵 **Nearing complete** | Substantially built (roughly 75%+ of the MUST tier) but not yet review-complete — one or two MUST items or a final review still outstanding. A progress signal between 🟡 and 🟢, not a merge gate. | Most MUST items present and merged; a named, small remainder (e.g. one missing use-case build or a pending review pass). |
| 🟢 **Review complete** | Merged to `main` in the working repository with the full MUST tier and a recorded sign-off by the assigned reviewer. **This is what acceptance means** (CONTRIBUTING §9); a merge alone is not enough. | MUST tier complete + green CI + a recorded sign-off by the assigned reviewer (a review-signoff issue linked in the Sign-off column of `REVIEWERS.md`). |
| ✅ **Published** | Promoted to the public `databricks-industry-solutions/open-retail-data-model` repo. A deliberate maintainer step, never automatic. | Review complete **+** the SHOULD tier (UC Metric Views with agent metadata for outcome KPIs) **+** maintainer promotion. A self-reviewed deliverable also needs a second, independent reviewer's sign-off, except in the initial public release ([GOVERNANCE.md](../GOVERNANCE.md)). |

🟢 **Review complete** is a merge plus a recorded sign-off by the assigned reviewer (a review-signoff issue linked in the Sign-off column of `REVIEWERS.md`), and being listed as Reviewer alone is not a sign-off, so a deliverable without a recorded sign-off stays at 🔵. ✅ Published is reserved for the public-repo promotion.

## What "done" requires (MUST / SHOULD / NICE)

### MUST — required to merge and mark 🟢 Review complete (CI-gated where possible)

**Canonical-core entity** (CONTRIBUTING §7, standard §A):
- table `.sql` with the provenance header; PK contract (`<stem>_sk` BIGINT identity + `pk_<table>` + durable STRING `<stem>_id`, where the stem names the entity grain/role per ADR 0011 — defaults to the table name); the layer-appropriate audit block; SCD2 columns on masters; the `dbx_data_type` tag and `dbx_pii_*` tags where applicable.
- an entry in `relationships.sql`; enum/state columns enforced with Delta `CHECK`.
- at least one DQ check in `checks.sql`, **plus an FK-orphan check on every fact and a single-reporting-currency check on every monetary fact**.
- a `glossary.md` entry.
- synthetic **samples or a seeded generator** whose column list and enum values match the DDL.
- docs-sync in the same PR (`STATUS.md`, the folder README, `glossary.md`; §8).
- green CI (the enforced mandates) + a human reviewer (`REVIEWERS.md`).

**Outcome package** (CONTRIBUTING §7):
- extension tables that **consume** the canonical core, never redefine it.
- a README stating the business outcome; `checks.sql` (incl. FK-orphan + single-currency on monetary facts) and `glossary.md`; sample queries or a notebook template.
- docs-sync + green CI + a reviewer.

> Not scored (neither MUST nor SHOULD nor NICE): an outcome package may also carry a `use-cases.yaml` — the planning-tier business use cases it enables (name + status), surfaced in the explorer. It never affects completeness% (see [ADR 0013](../governance/decisions/0013-use-cases-planning-artifact.md)).

### SHOULD — expected, phased (v1.x), reviewer-adjudicated, NOT a first-merge blocker

- **UC Metric Views** for all outcome KPIs: `WITH METRICS LANGUAGE YAML`, one file per view under `metric-views/`, with populated **agent metadata** (synonyms, `display_name`, format, comment). The standard (§13) calls this the differentiator and the v1.x bar. A package can be 🟢 Review complete on its tables without metric views, but is **not ✅ Published-grade** until they land.
- **Lakebase binding** for canonical-core **transactional-spine** entities (transaction, order, inventory, loyalty): the generated Lakebase/Postgres binding from the shared logical model (ADR 0005). Phased — it depends on the logical-model→bindings generator, so it's not a first-merge blocker, but a spine entity is **not ✅ Published-grade** until its Lakebase binding lands. The initial release (0.5) published `transaction`, `order` and `inventory` before the generator existed, so their binding is a recorded deferral (see the note in `STATUS.md`), and they score 85% on the formula below until it lands; loyalty is not yet its own entity (only `profile.loyalty_id`). Other core domains have no Lakebase SHOULD yet, and gold/outcome tables are **Delta-only** (never a Lakebase binding).

### NICE-TO-HAVE — scored on a separate scale, never folded into Done%

NICE items are **not** part of the completeness % (which is MUST + SHOULD only). They are tracked on a separate **Nice-to-haves: `N of M`** scale, where `M` is the subset *applicable to that domain/package type* — so a small dimension like `calendar` (small `M`) is never penalized for nice-to-haves that don't apply. The `N/M` count is **always shown** so a contributor sees exactly which items remain, but it confers a tier/standing only once the MUST tier is 100% — nice-to-haves can never move Done% or let an incomplete domain out-rank a done one.

ORDM *authors* the artifact; several of these need elevated rights or compute to *deploy*, so they are optional by nature and flagged accordingly — **do not assume an adopter has admin**. (The repo's `N/M` counts the artifact being authored, independent of any deployment's privileges.)

- **Genie Agent** (fka Genie Space) definition per package — instructions + scoped data + sample questions. *Deploy needs a Genie Agent in the workspace.*
- **Certified** — the UC `system.certification_status = 'certified'` governed tag, set declaratively via `SET TAG`, marking the entity an authoritative source. *Deploy needs governed-tag `ASSIGN` rights and is deployment-specific. Candidate to promote to SHOULD if the working group makes it part of the publication bar.*
- **ODCS/ODPS data contract** per package — built on the open Data Contract Standard (tooling via the `databrickslabs/ontos` Labs project; not a first-party GA contract object).
- **Reference AI/BI dashboard** (Lakeview) on the package's metric views — zero metric drift, since it binds to the certified measures.
- **Data-quality monitor** spec per core fact — UC Data Quality Monitoring (fka Lakehouse Monitoring): a profile type (snapshot/timeseries/inference) + freshness/completeness/drift. *Runs compute in the adopter's workspace.*
- **PII masking demo** — UC column masks on `dbx_pii_*` columns in `masks.sql`, as a worked example of governance-by-default (not full coverage). *Deploy needs mask-function + ABAC rights.* The `dbx_pii_*` tags are ORDM's declarative deploy-time signal and coexist with the reserved `class.*` tags Databricks Data Classification auto-applies from data scanning (ADR 0010); ORDM does not set `class.*`.
- **pgvector serving spec** — an embedding column + a Lakebase synced table — **only** for packages that serve a live agent/app needing low-latency retrieval (e.g. agentic-commerce). *Deploy needs Lakebase.*
- **Liquid clustering** — `CLUSTER BY` keys (or `CLUSTER BY AUTO`) on large tables.
- **Documented** — table and column `COMMENT`s populated (high value for Genie, discovery, and the auto Genie Ontology).
- **Fuller `dbx_` tag vocabulary** — `dbx_subdomain` (maps to a UC Domains governed tag `{parent}/{subdomain}`), `dbx_value_regex`, `dbx_business_glossary_term` (maps to the UC Glossary object), …; richer notebook templates. See ADR 0010 for the native-feature mapping.

Baseline (a standard, not a scored item): ORDM tables are **Unity Catalog managed** tables.

On "ontology": Databricks' Genie Ontology is *auto-inferred*, not hand-authored — there is no ontology file to ship. ORDM earns ontology value indirectly by shipping certified metric views + glossary terms + certification tags, which the ontology ranks as high-authority sources.

## Completeness %

A progress number (0–100) for a domain or package, measuring how close it is to ✅ Published. It scores **MUST + SHOULD only**; NICE-TO-HAVE items are tracked separately on the **Nice-to-haves `N/M`** scale above and never enter this %. The **% is progress; the status ladder is the gate** — an item is only 🟢 when *every* MUST item is present, so something with a missing MUST is not yet 🟢 no matter how high the %: a substantially-built item (roughly 75%+ of MUST) sits at 🔵 Nearing complete, a less-built one at 🟡, and ✅ needs 100% **plus** a maintainer promotion.

**Formula** — score the artifact checklist, MUST weighted 85%, SHOULD 15%:

```
completeness% = round( 100 × [ 0.85 × (MUST present / MUST total)
                             + 0.15 × (SHOULD present / SHOULD total) ] )
```

Most canonical-core domains have no SHOULD tier, so drop the SHOULD term and renormalize: `completeness% = round(100 × MUST present / MUST total)`. The exception is the **transactional-spine** entities (transaction, order, inventory, loyalty), whose SHOULD tier is the **Lakebase binding** (ADR 0005) — score them with the full formula (MUST 85% + Lakebase binding 15%). Outcome packages' SHOULD is metric views; neither they nor non-spine core carry a Lakebase binding.

**The checklist items (each = 1 point in its tier):**

*Canonical-core domain — 9 MUST; SHOULD = a Lakebase binding for transactional-spine entities (transaction, order, inventory, loyalty), otherwise none:*
1. table `.sql` (one CREATE, provenance header) · 2. PK contract (`<stem>_sk` identity + `pk_<table>` + durable `<stem>_id`; stem = grain/role, ADR 0011) · 3. audit block (+ SCD2 on masters) · 4. `dbx_data_type` (+ `dbx_pii_*` where applicable) · 5. `relationships.sql` (FKs + enum CHECKs) · 6. `checks.sql` (≥1 DQ + FK-orphan on facts + single-currency on monetary facts) · 7. `glossary.md` · 8. synthetic samples or a DDL-matching generator · 9. docs-sync (STATUS + README current).

*Outcome package — 6 MUST, 1 SHOULD:*
MUST — 1. extension table(s) consuming core (one CREATE, header) · 2. PK contract + `dbx_data_type` on new tables · 3. `relationships.sql` + enum CHECKs (as applicable) · 4. `checks.sql` (incl. FK-orphan + single-currency on monetary facts) · 5. `glossary.md` + README stating the outcome · 6. sample queries or notebook template + docs-sync.
SHOULD — UC Metric Views for the KPIs with populated agent metadata (synonyms, display_name, format, comment).

**Status mapping:** all MUST present → **85% (outcome) / 100% (core) = 🟢-eligible** (with a reviewer); + SHOULD → **100% = ✅-eligible** (with maintainer promotion); partial MUST, substantially built (~75%+) → 🔵; smaller partial MUST → 🟡; nothing built → ⚪.

**Worked examples:** a core domain with everything but a generator and with STATUS not updated = 7/9 = **78% (two MUST gaps)** — substantially built, so **🔵 Nearing complete**, not yet 🟢. A domain only about half-built (a few MUST items) = **🟡 In progress**. An outcome package with all 6 MUST but no metric views = 0.85×(6/6)+0.15×0 = **85% → 🟢-eligible**, not yet ✅.

Reviewers track this % per item, plus the separate **Nice-to-haves `N/M`** count (the applicable NICE items present, always shown; tier only when MUST = 100%).

## Model coverage vs Done% (advisory, never a gate)

Done% above measures whether the required **artifacts** are present (table + PK + tags + checks + glossary + docs). It deliberately does **not** measure whether the **model** is complete — so a domain with a single well-formed table can read 100%. That is correct: the artifacts are all there.

Whether a model has the *right* shape is a separate, advisory signal, and it is **not** carried by a static in-repo list. The advisory AI reviewer may add a **"🧩 Model coverage"** note — the tier below `m` (minor) — with three lenses that keep the model at the minimum-viable intersection in both directions: **missing** (a required element absent — an entity, identity/join key, or column/attribute — necessity, not richness); **fit/placement** (an element too specific for the shared core → a decline-able "consider an outcome extension" question, or a shared primitive stuck in one gold outcome → "consider promoting to core"; the action is the author's, never a removal directive); and **non-obvious key/grain** (a semantic key or grain smell CI cannot catch, posed as clarity). It tests each against external, open, vendor-neutral references (the vetted allow-list in `standards/grounding-sources.yaml`), fetched deterministically and capped. The subtractive lenses carry a higher bar (default silence, grounding may only *clear*, cap 1). It is fail-open and **never** blocks a merge or changes Done%.

This exists to catch the obvious case (e.g. an inventory position snapshot with no movement fact) **without** pushing toward the union of every schema — ORDM is the intersection. It never flags thinness itself: a small, deliberate model is correct. If an omission is intentional, record the decision (e.g. an ADR in [`governance/decisions/`](../governance/decisions/)) and note it on the PR so the reviewer does not re-raise it.

## Quick gate summary

- Can't merge → fails the MUST tier or CI. Keep it ⚪/🟡.
- Merged + reviewed → 🟢 Review complete (= 100% core / 85% outcome).
- 🟢 + metric views + maintainer promotion → ✅ Published (= 100%).
