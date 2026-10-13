# ADR 0030 — Agent representation and consent are logical (non-FK) references, not surrogate FKs

**Status:** Accepted (2026-08-01)

Relates to the Agentic Commerce outcome package (agent-to-agent slice): `a2a_agent` (`represented_profile_id`, `represented_store_id`) and `a2a_mandate` (`consent_id`).

## Context

ORDM's FK-completeness rule is that a cross-entity reference carried as a surrogate `_sk` MUST declare a Unity Catalog FK; an `_id`-only reference with no `_sk` is the "business-key trap" and is only acceptable when it is a **deliberate, documented** logical link (not an oversight). Three columns in the A2A slice are `_id`-only by design and need that decision recorded so a reviewer (human or AI) does not read them as missing FKs:

- **`a2a_agent.represented_profile_id`** — the customer profile a buyer agent acts for.
- **`a2a_agent.represented_store_id`** — the store a seller agent acts for.
- **`a2a_mandate.consent_id`** — the customer consent decision authorizing automated purchasing.

Two properties make a version-specific surrogate FK the wrong tool here:

1. **Registration precedes resolution.** An agent is often registered (and begins negotiating) before its principal is resolved to an in-model surrogate. A hard `_sk` FK would force resolution at write time or leave the row unwritable.
2. **The targets are SCD2.** `customer.profile`, `store`, and `customer.consent` are versioned. A `_sk` binds to exactly one version, but "the customer this agent represents" and "the consent that authorizes this mandate" are **version-independent** business facts — the agent represents the person, not a specific dated snapshot of their profile row.

## Decision

Model these three as **durable business-key references only** — the `_id` with no `_sk` and no declared UC FK — and validate them with **warn-level business-key orphan checks** in `checks.sql` rather than a database constraint.

- The hard, version-specific relationships still exist where a point-in-time bind is correct: `a2a_session` carries `buyer_profile_sk` + `store_sk` (declared FKs), and `a2a_mandate` carries `buyer_profile_sk` + `a2a_agent_sk` (declared FKs). Those are the transactional edges.
- `represented_*_id` on `a2a_agent` is the **soft registry link** (which principal the agent stands for), exactly one populated per `agent_role` (enforced by the representation-consistency check).
- `consent_id` on `a2a_mandate` is the **authorization link** to the SCD2 consent master; the mandate is the durable grant, the consent decision is its lawful basis, and both evolve independently.

Each column's header comment states it is a logical reference (not a UC FK) and why; this ADR is the single place the pattern is justified so it is not re-litigated per column.

## Consequences

- `standards-conformance` FK-completeness passes: these are declared-intentional logical links, not undeclared `_sk` FKs.
- Referential integrity for the three links is enforced at **warn** severity (orphan checks), not as a blocking DB constraint — consistent with treating them as soft/registry links that may legitimately point at a not-yet-loaded or historical principal.
- If a future consumer needs point-in-time-correct consent-to-mandate binding (e.g. "which consent version was in force when this mandate was granted"), add a `consent_sk` alongside `consent_id` and a declared FK at that time — the same promote-when-a-second-consumer-appears path used elsewhere. Recorded here so the current `_id`-only shape is understood as a decision, not a gap.
