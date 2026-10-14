---
name: ordm-data-modeling
description: Author or adapt ORDM-conformant retail data models. Use when creating a new canonical-core domain or outcome package in the Open Retail Data Model, or when adapting and extending ORDM to a customer's own environment (mapping their source systems, adding custom entities, tailoring outcome KPIs) while staying conformant to ORDM standards.
---

# ORDM data modeling

Use this skill to author a new ORDM data model or to adapt ORDM to a specific environment. It does not restate the rules. The single source of truth for the rules is the standard, and you read it first.

## Step 0: read the standard, do not restate it

Before writing any DDL, read these in the repo you are working in (or in a checkout of the Open Retail Data Model):

- `docs/data-model-standards.md` is the authoritative rule set: the mandates (CI-enforced), the design principles (judgment), what is flexible, and the full naming conventions. Follow it. If a customer requirement conflicts with a mandate, surface the conflict rather than silently breaking the rule.
- `CONTRIBUTING.md` is the process and the worked examples (sections 5, 6, 7, 11).
- `standards/rules.yaml`, if present, is the machine-readable registry of the enforceable rules, each with an id. Cite rule ids when you explain a choice.

Never copy the rules into this skill or into a customer doc. Link to the standard so there is one source of truth.

## The two-layer model

ORDM has a canonical core (the conformed silver entities, shared and reused) and outcome packages (gold plus UC Metric Views and agent metadata, one per business outcome, sitting on top of the core). The first question for anything you add is which layer it belongs to. Use the placement decision tree in CONTRIBUTING section 6: if the entity is referenced by more than one outcome, carries master or dimension semantics rather than metrics, and has no outbound dependency on an outcome-specific table, it is canonical core; otherwise it is an outcome package. Canonical core is silver and must never declare a foreign key into a gold or outcome schema.

## Authoring a new domain or outcome package

Follow the worked example in CONTRIBUTING section 11 and the artifact checklist in section 7. In short:

1. Decide the layer and the owning domain or package, and open the matching issue.
2. Branch with the convention (`core/<domain>-<topic>` or `outcome/<package>-<topic>`).
3. Write one CREATE per `.sql` file under the fixed layout. Apply the standard: the primary-key contract (BIGINT identity `<stem>_sk` plus durable STRING `<stem>_id`, constraint `pk_<table>`, where `<stem>` names the entity's grain/role and defaults to the table name — ADR 0011), strict typing (DECIMAL for money, DOUBLE only for derived ratios and non-monetary continuous values), SCD2 columns on masters, the layer-appropriate audit block, the required `dbx_data_type` tag and `dbx_pii_*` tags, and enforced CHECK constraints for type-category enums.
4. Declare single-column foreign keys against the parent surrogate key in `relationships.sql`. Do not FK out of the customer root, and never FK from canonical core into a gold or outcome schema.
5. Add at least one data-quality check in `checks.sql`, plus an FK-orphan check on facts and a single-reporting-currency check on monetary facts.
6. Add a glossary entry and a seeded synthetic-data generator whose columns and enum values match the DDL.
7. Put the provenance header on every file. No license body in the DDL.
8. Run the local checks before opening the PR: `make regen` (then commit the regenerated artifacts), `make check`, `pytest -q` and `python runtime/data-quality/run_checks.py`. Update STATUS.md and the folder README in the same PR (docs in sync).

For an outcome package, add extension tables only (never redefine a core entity), put derived metrics in UC Metric Views or gold views with populated agent metadata, and consume the canonical core rather than copying it.

## Adapting ORDM to a customer environment (meet them where they are)

The goal is to fit ORDM to the customer's data landscape without breaking conformance or polluting the open model.

- Keep the canonical core conformant. Map the customer's source columns onto the core entities rather than reshaping the core to match a source. The core stays the intersection of universal concepts, not the union of one customer's columns.
- Add the customer's genuinely custom entities as extensions in their own schema or as outcome-package extension tables, tagged and typed to the standard. Do not bloat the shared core with single-customer attributes.
- Use the token resolver for the customer's catalog and schema names (`${catalog}.${<domain>_schema}`); never hardcode.
- Tailor outcome packages to the customer's KPIs by adjusting metric views and agent metadata, while leaving the core entities they consume unchanged.
- Keep anything proprietary or source-specific (bronze, source-aligned silver, ingestion code, real data) out of any contribution back to ORDM. That material stays in the customer's private repo.
- When the customer's need reveals a genuinely shared gap, propose it back to ORDM as a new core entity or outcome package through the normal contribution flow, rather than forking.

## What to hand back

For an authoring task, a set of conformant `.sql` files plus relationships, checks, glossary, samples, and the doc-sync updates, ready for a PR. For an adaptation task, the mapping from the customer's sources to the core, the list of custom extensions kept separate, and a short note on any mandate the customer's environment cannot meet so a human can decide. Always state which rule ids or standard sections you applied.
