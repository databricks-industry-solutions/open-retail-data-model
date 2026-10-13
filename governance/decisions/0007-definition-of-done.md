# ADR 0007 — Definition of Done and the status ladder

**Status:** Accepted (2026-06-28)

## Context
`STATUS.md` and the ownership tracker used four status values (Planned / In progress / Review complete / Published) without a written definition, so "done" was ambiguous — e.g. whether merging a PR means "reviewed", and whether a package with tables but no UC Metric Views counts as done. The artifact rules existed (CONTRIBUTING §7, standard §13) but were not tied to the lifecycle states.

## Decision
Adopt an explicit [Definition of Done](../../docs/definition-of-done.md):
- The status ladder states are defined. **Merging to staging `main` with the full MUST tier + a reviewer = 🟢 Review complete** (CONTRIBUTING §9: "merging here is acceptance into staging"). **✅ Published is reserved** for the deliberate promotion to the public repo.
- "Done" is tiered: **MUST** (the §7 artifact checklist + enforced mandates + a reviewer) is required to merge / mark 🟢; **SHOULD** (UC Metric Views with agent metadata, §13) is the phased v1.x bar required before ✅ Published; **NICE-TO-HAVE** is everything beyond.

## Consequences
- `docs/definition-of-done.md` is the reference; `STATUS.md` and `CONTRIBUTING.md` §7 link to it.
- A deliverable is not ✅ Published-grade until its UC Metric Views + metadata land, even though those don't block the first merge.
- Existing 🟡 In-progress items should be checked against the MUST tier and the gaps backfilled before they move to 🟢.
