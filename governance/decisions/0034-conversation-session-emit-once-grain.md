# ADR 0034 — `conversation_session` is emit-once per durable key; an `active` snapshot is terminal for ORDM

**Status:** Accepted (2026-08-13)

Relates to the Agentic Commerce outcome package (conversational-shopping slice): `conversation_session`.

## Context

`conversation_session` is an append-only analytical fact. Its contract (stated in the table header and glossary) is that a producer emits **exactly one immutable ORDM row per `conversation_session_id`**, at the point the backend decides the session is reportable — usually after close. `checks.sql` enforces this with `cs_business_key_unique` at **error** severity.

The lifecycle enum, however, permits `session_status = 'active'` with a nullable `ended_ts`. That created an unresolved tension flagged in AI review (#90, finding M1): if a producer emits a row while the session is still `active` and then re-emits the same key once the session `completed`, the second emission fails `cs_business_key_unique`. The model had not stated whether an `active` session is reportable, and if so, how a later completion is reconciled.

An idempotent upsert (MERGE on the business key, refreshing the row in place) was considered and rejected: ORDM is the **contract**, not the pipeline, and this fact is explicitly append-only / never-refreshed-in-place. Encoding an upsert would move mutable-state semantics into the published model, which the package's runtime-boundary design (Lakebase/CDC own mutable state; ORDM owns immutable analytical events) exists to prevent.

## Decision

`conversation_session` is **emit-once per `conversation_session_id`**, and an emitted row is **terminal for ORDM** — it is never superseded by a later `active`→`completed` correction.

- A producer chooses a single reporting point per session. If it needs the closed outcome, it **defers emission until close**.
- An `active` (null-`ended_ts`) row is a deliberate point-in-time snapshot for a session that is still open at the producer's reporting cutoff. It is valid and final for ORDM; the producer will not re-emit that key.
- The status and end timestamp must be internally consistent at that single reporting point. This is enforced by `cs_status_ended_ts_consistency` (**error**): a `completed` session has an `ended_ts`; an `active` snapshot has none. `abandoned` / `escalated` may or may not carry an `ended_ts` (a shopper may drop mid-session).

`cs_business_key_unique` remains the guard that a producer has not double-emitted a key.

## Consequences

- The emit-once contract is now explicit and machine-checked, so the `active`-then-`completed` failure mode is a documented producer error rather than an ambiguity in the model.
- Producers that only ever report closed sessions are unaffected; those that snapshot open sessions get a clear, terminal semantics with no in-place refresh.
- If a future consumer genuinely needs successive snapshots of one session (open → closed), that is a **new grain** (a session-state-change fact keyed by session + snapshot time), added alongside — not a mutation of this emit-once fact. Recorded here so the current shape is understood as a decision, not a gap.
