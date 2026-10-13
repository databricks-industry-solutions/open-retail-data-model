# ADR 0027 — Suppression as an overlay on the consent master (not a separate ledger)

**Status:** Accepted (2026-07-24)

Relates to the customer-identity core slice and the Unified Customer View activation gate (`gold_customer_activation_eligibility_current`), which had reserved a `suppressed` blocking reason it never produced.

## Context

A retail CDP reference brief treats **suppression** — a do-not-contact signal that must block activation even when consent is granted — as a first-class governed state, distinct from consent, preference, and eligibility ("Do not treat consent, preference, suppression, and eligibility as one field on a profile; those are distinct governed states"). ICO direct-marketing guidance treats a do-not-contact/suppression signal as a *separate, minimal* record that should be retained to screen future contact even when the underlying record is erased (a GDPR Art.17(3) retention basis). ORDM's v1 overlay-on-consent (below) is a warehouse-native approximation of that pattern for the common case; a fully erasure-surviving, identifier-hash-keyed store is the deferred promote target (see item 5), so this ADR does **not** claim the overlay itself survives a hard profile erasure.

Crucially, the brief does **not** model suppression as a standalone table. Its gold inventory has no `suppression`/`fact_suppression` entity; instead suppression lives as **attributes on the consent-state dimension** (`dim_consent_state` purpose: "Lawful basis, channel consent, **suppression**, opt-out, activation gates"; its DDL carries `suppression_indicator BOOLEAN` + `suppression_reason_code STRING`), plus derived permission flags (`is_activation_permitted`), a retention rule, a metric (`suppression_leakage_rate`), and a DQ check (`NOT (suppressed AND is_activation_permitted)`).

ORDM had anticipated this: the activation gate documented a `suppressed` blocking reason as **reserved but never produced**, pending a suppression source. An earlier proposal to build a standalone `suppression_ledger` outcome table was rejected as an over-build not grounded in the brief (the brief models suppression on consent, and no second consumer exists to justify a shared entity).

## Decision

**Model suppression as an overlay on the canonical-core `customer.consent` master**, and produce the `suppressed` reason in the activation gate.

1. **Two additive columns on `consent`** (nullable; existing rows unaffected):
   - `suppression_indicator BOOLEAN` — TRUE suppresses activation on this consent scope (purpose × channel) even when `consent_status = 'granted'`.
   - `suppression_reason_code STRING` — governed enum: `unsubscribe / hard_bounce / spam_complaint / legal_objection / deceased / fraud / do_not_contact / list_hygiene` (CHECK in `relationships.sql` per NO-INLINE-CHECK).

2. **Suppression is a distinct governed state (principle #5), NOT folded into `consent_status`.** A withdrawal (`consent_status = 'withdrawn'`) is the customer revoking permission; a suppression is an operational/legal do-not-contact overlay (hard bounce, complaint, direct-marketing objection, deceased). They coexist and mean different things.

3. **Suppression overrides consent in the gate.** `gold_customer_activation_eligibility_current` now reads `suppression_indicator`, exposes `is_suppressed_flag`, sets `eligible_flag = consent AND preference AND identifier AND NOT suppressed`, and emits `suppressed` as the **highest-priority** `blocking_reason_code` (before `withdrawn`). The `blocking_reason_code` enum and the `ucv_eligibility_flag_consistency` invariant already permitted `suppressed`.

4. **Two suppression scopes — CHANNEL-level vs PERSON-level (review H1).** Because the overlay lives on the per-channel consent row (`profile × consent_type × jurisdiction`), a naive per-scope read would let a person-level reason recorded on one channel leak an un-suppressed sibling channel (a `deceased` flag on the email row leaving SMS eligible — a real do-not-contact leak with legal weight). The reasons are therefore split by scope and the gate enforces it:
   - **CHANNEL-level** (`unsubscribe`, `hard_bounce`, `spam_complaint`, `list_hygiene`) block only the scope they sit on.
   - **PERSON-level** (`deceased`, `fraud`, `do_not_contact`, `legal_objection` — GDPR direct-marketing objection is absolute at the person level) block **every owned channel the gate evaluates** for the profile. The gate's `person_suppressed` CTE propagates them across the per-channel consent scopes, so a person-level flag on any one current consent row suppresses the whole profile on the owned plane without requiring adopters to replicate it onto every row. The gate itself only governs owned marketing channels; enforcing the person-level do-not-target signal on the **paid** plane (retail-media / DSP / clean-room onboarding, which targets `marketing.audience` directly) is the job of the shared `gold_person_do_not_target_current` view (ADR 0028) — so "absolute across every plane" is true only once that view is consulted, which ADR 0028 makes mandatory.

   Person-level propagation also crosses **jurisdictions** (review M1): the `person_suppressed` CTE keys on `profile_id` alone, so a person-level flag recorded on an EU scope also suppresses that profile's US-CA scopes. This is **deliberate and fail-safe** — deceased/fraud/do_not_contact apply universally, and honoring a `legal_objection` across regimes over-suppresses (never harmful) rather than risk under-suppressing a do-not-contact signal (which carries legal weight). Adopters needing strictly regime-scoped objection handling would add a jurisdiction predicate to the propagation and record the objection per applicable regime; ORDM ships the conservative default.

5. **Why not a standalone ledger.** A separate suppression table is not in the brief, has no second consumer today, and would split a governed state the brief keeps on consent. If a distinct multi-source suppression ledger with entry/exit history and erasure-surviving hashes is later required (≥2 consumers, e.g. CMN + campaign ops), promote it then — the same promote-on-second-consumer path as `audience` (ADR 0022). Recorded here so it isn't re-litigated.

## Consequences

- The activation gate's reserved `suppressed` reason is now produced; a granted-but-suppressed customer is correctly **not activatable** (and drops from `gold_activatable_audience_current`, which exposes only eligible rows).
- Consent DQ gains `consent_suppression_reason_domain`, `consent_suppression_consistency` (a reason requires the indicator), and a `consent_suppressed_rate` metric; the UCV `suppression_rate` metric moves from *reserved* to defined.
- The synthetic generator seeds ~6% of consent scopes as suppressed so the block path is exercised.
- Erasure handling: suppression evidence lives on the retained consent record; a full suppression-preserving erasure workflow (pseudonymize identifiers, keep the do-not-contact signal) is a deploy-time concern, not schema.

## Alternatives considered

- **Standalone `suppression_ledger` table.** Rejected: not in the brief, no second consumer, splits a governed state the brief models on consent. Documented promote path if that changes.
- **Fold suppression into `consent_status` (e.g. a `suppressed` status).** Rejected: violates principle #5 — a suppressed customer may still hold a valid granted/withdrawn legal decision; collapsing them loses the lawful-basis state and the operational reason.
