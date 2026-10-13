# ADR 0028 — Cross-plane do-not-target view + multi-purpose activation gate

**Status:** Accepted (2026-07-27)

Follows [ADR 0026](0026-cdp-activation-layer-in-ucv.md) (CDP activation layer in UCV) and [ADR 0027](0027-consent-suppression-overlay.md) (suppression overlay on `customer.consent`). Corrects two gaps found in a post-merge audit of the CDP work (design memo `design/54`).

## Context

ADR 0027 shipped person-level suppression (`deceased`, `fraud`, `do_not_contact`, `legal_objection`) as an overlay on `customer.consent` and claimed those reasons "block EVERY channel" and that a `legal_objection` (GDPR Art.21) is "absolute across channels." Two problems surfaced:

1. **The claim was only true for owned channels.** The single enforcement point — `gold_customer_activation_eligibility_current` — is structurally owned-only: it read only `marketing_*` consent types and hardcoded `purpose_code = 'marketing'`, and its person-level logic lived in an inline, non-reusable `person_suppressed` CTE. The **paid plane** (commerce-media-networks) targets `marketing.audience` directly and onboards people over ACU `segment_membership` (a targeting surface that defers the net gate to UCV). So a person-suppressed customer was correctly dropped from owned email/sms/phone/postal, yet could still be uploaded to a DSP / retail-media network / clean room — a do-not-contact leak with legal weight (Art.21 is an absolute objection). External guidance corroborates: ICO treats a do-not-contact signal as an absolute, separate control that must be honored across all marketing.

2. **Non-marketing activation was un-gateable.** `activation_destination.required_consent_purpose` and `activation_job.purpose_code` enumerate five purposes (`marketing`, `personalization`, `analytics`, `retail_media`, `service`), but the gate could only ever emit `marketing` rows. A destination declaring any other purpose was a legal, DQ-passing row for which the gate produced zero eligible members — declared but structurally dead.

## Decision

### 1. A shared cross-plane do-not-target view

Add `outcome-packages/unified-customer-view/gold/gold_person_do_not_target_current.sql` — a profile-grain, channel/purpose/jurisdiction-agnostic gold **view** projecting the four person-level suppression reasons off `customer.consent` (one row per `profile_id` with an active person-level do-not-target). It is the **single mandatory do-not-target consult for every activation plane**:

- The owned gate (`gold_customer_activation_eligibility_current`) sources it (replacing the inline `person_suppressed` CTE — single source of truth, identical semantics).
- `gold_activatable_audience_current` anti-joins it (belt-and-suspenders: the surface is safe on any plane a consumer syncs it to, independent of gate coverage).
- ACU `segment_membership` carries an **activation contract** in its header: any consumer reverse-ETLing it directly to a non-owned/paid destination MUST anti-join this view first.
- CI enforces it: `ucv_eligibility_person_suppressed_blocked` and `uav_no_person_suppressed` (both severity error) assert no do-not-target profile is ever eligible / activatable.

This adds **zero stored data, zero new FK, zero new table/column/package** — a pure projection over the columns ADR 0027 already shipped. It closes the Art.21 leak by giving the paid plane a governed suppression path where there was none.

### 2. Multi-purpose gate — consent_type → purpose mapping

The gate derives `purpose_code` from `consent_type` instead of hardcoding `'marketing'`:

| `consent.consent_type` | gate `purpose_code` | `channel_code` |
|---|---|---|
| `marketing_email` / `_sms` / `_phone` / `_postal` | `marketing` | email / sms / phone / postal |
| `profiling` | `personalization` | NULL (channel-agnostic) |
| `cookies` | `analytics` | NULL (channel-agnostic) |
| `third_party_sharing` | `retail_media` | NULL (channel-agnostic) |
| `data_sale` | `data_sale` | NULL (channel-agnostic) |
| `data_processing` | *(not consent-gated)* | — |
| *(→ `service`)* | *(not consent-gated)* | — |

The four non-marketing mappings are a deliberate lawful-basis→activation-purpose interpretation: consent to profiling authorizes personalization; cookie/tracking consent authorizes analytics; consent to third-party sharing authorizes retail-media activation; and `data_sale` gates the CCPA/CPRA **do-not-sell** opt-out. They are **channel-agnostic** — reachability is resolved at the reverse-ETL match-key boundary, not on an owned email/sms channel — so those rows carry `channel_code = NULL` and `has_identifier_flag = TRUE`. `data_processing` (an umbrella lawful basis) and `service` (transactional; lawful basis contract/legitimate-interest, not consent) are intentionally not consent-gated (`NULL purpose = not consent-constrained`); mapping both `cookies` and `data_processing` to `analytics` would also collide on the gate grain.

**`third_party_sharing` and `data_sale` are kept as two distinct consent types and two distinct gate purposes** — not folded into one — because CCPA/CPRA treats *share* (disclosure for cross-context behavioral advertising) and *sell* (disclosure for monetary or other valuable consideration) as separate opt-outs (the mandated link reads "Do Not Sell **or Share** My Personal Information"). Folding them would (a) lose a legally-required distinction and (b) collide two rows on the `(profile × purpose × NULL-channel × jurisdiction)` gate grain when a profile holds both consents, tripping `ucv_eligibility_one_row_per_grain`.

After this, five of the six declared purposes are gate-producible. The change is **backward-compatible**: the four `marketing_*` rows are byte-identical to before (purely additive rows for the new purposes).

**Opt-in gate vs opt-out obligation (do-not-sell/share is NOT satisfied by the gate).** The gate
(`gold_customer_activation_eligibility_current`) is **opt-IN / fail-closed**: a `data_sale` /
`retail_media` row resolves eligible ONLY where `consent_status = 'granted'`, so a never-decided
profile is absent from the gate and treated as not-permitted. CCPA/CPRA do-not-sell and do-not-share
are the opposite — **opt-OUT**: absence of an opt-out = permitted; only an explicit withdraw/suppress
removes a profile. So for a never-decided consumer the gate and the opt-out leg return **opposite**
populations. A paid/selling/sharing plane MUST therefore apply the purpose-level opt-out directly
(leg b: drop current `data_sale`/`third_party_sharing` consents that are withdrawn or
suppression-flagged) and must NOT substitute the owned gate for it. The gate's population is a safe
(more conservative) subset for an OWNED opt-in plane, so the direction never leaks; the risk is
silent under-inclusion if the gate is used as an opt-out substitute. This caveat is enforced in prose
at the three contract sites (UCV `sample-queries.sql` #11, CMN README, `segment_membership` header).
**Deferred (option b), surfaced for maintainer decision:** whether to reconcile the gate's
`data_sale`/`retail_media` branch to jurisdiction-scoped opt-out semantics so the gate itself could
serve a selling plane; not done here because it changes the gate's fail-closed philosophy.

## Consequences

- The Art.21 "absolute across channels" claim is now true across every plane once the DNT view is consulted; ADR 0027 §4 wording, `consent.sql`, and the UCV/customer glossaries are reconciled to reference the view.
- Destinations declaring `personalization` / `analytics` / `retail_media` now reconcile against the gate; `activation_job`'s RECONCILIATION SCOPE comment is updated. `gold_activatable_audience_current` and ACU `segment_performance` (which read the gate/surface) will surface more rows — desired, a correct volume change.
- New DQ checks: `ucv_eligibility_purpose_domain`, `ucv_eligibility_person_suppressed_blocked`, `uav_no_person_suppressed`, `dnt_reason_domain`, `dnt_profile_unique`. Regenerated artifacts (model.json, ODCS, ER) show the new view.
- The consent generator seeds all nine consent types (including `data_sale`) across the profile population — a per-profile hash offset rotates the per-profile consent rows through the full vocabulary rather than only the first `consents_per_profile_max` types — so the new gate branches (`personalization`/`analytics`/`retail_media`/`data_sale`) are exercised on generated samples, not only in the Spark unit fixture.

## Alternatives considered

- **Art.21: narrow the ADR-0027 wording only** (say "owned channels" and leave the paid leak). Rejected: honest but leaves a real do-not-contact leak on an unpublished model where a correct fix is cheap.
- **Art.21: a new person-grain do-not-target table/column.** Rejected for v1: the view is sufficient (no stored data), and an erasure-surviving hashed suppression ledger remains the deferred promote target (ADR 0027 §5) for when a second consumer or an erasure-survival requirement makes a separate minimal store necessary.
- **Multi-purpose: leave the three interpretive mappings to adopters** (gate generalizes, mappings behind a note). Considered; ORDM ships the mainstream reading with this ADR recording the rationale, and adopters retune if their lawful-basis interpretation differs.
