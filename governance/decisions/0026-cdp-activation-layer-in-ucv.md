# ADR 0026 — CDP activation layer (destination catalog + activation/touch facts) in Unified Customer View

**Status:** Accepted (2026-07-24)

Builds on [ADR 0022](0022-promote-audience-to-silver-marketing.md) (the shared `marketing.audience` segment definition) and [ADR 0024](0024-gold-to-gold-coupling-acu-ucv.md) (gold→gold coupling between ACU and UCV); relates to the behavioral-segmentation work (PR #87) that shipped ACU `segment_membership` and UCV `gold_activatable_audience_current`.

## Context

The retail CDP outcome is delivered in ORDM as **Unified Customer View (UCV) ∘ Actionable Customer Understanding (ACU)**, not as a standalone `cdp` package — a `cdp` package would re-define an outcome that already has a home, the one-outcome-one-package anti-pattern. PR #87 shipped the **targeting + gating** half of that CDP model:

- `marketing.audience` — shared, versioned segment/audience definitions (ADR 0022).
- ACU `segment_membership` — who is in each segment (append-only as-of snapshots).
- UCV `gold_activatable_audience_current` — who may actually be contacted (targeting ∘ consent ∘ preference ∘ reachability; fail-closed).

A retail CDP reference brief requires more than targeting: it names `activation_destination`, `fact_activation_job`, and `fact_campaign_touch` as first-class entities — *where* an audience publishes, an *audit* of each publish, and the *interaction history* that results. Until these exist the UCV `CDP` use-case is **blocked**: an audience can be gated but there is no governed record of activating it or of the touches it produced.

The activation-execution layer is single-outcome (it serves the CDP/UCV outcome), it consumes existing conformed definitions rather than redefining them, and it has no second consumer today. Per CONTRIBUTING §6 (the ≥2-outcome promotion test), that places it in an **outcome package**, not canonical core.

## Decision

**Add the CDP activation-execution layer as three gold tables in the `unified-customer-view` outcome package**, because UCV already owns the activation surface (`gold_activatable_audience_current`) and the blocked `CDP` use-case.

1. **`activation_destination`** — a Type-1 gold **reference** dimension: the connector catalog (one row per destination an activatable audience can publish to). Carries per-destination gate config (`required_consent_purpose`, `required_channel`, `match_key_type`) so the fail-closed gate is destination-aware. `dbx_data_type = 'reference'`; config only, never member lists (principle #9).

2. **`activation_job`** — an append-only gold **transactional** fact: one row per (audience × destination × jurisdiction × run). Records `requested / eligible / blocked / exported` member counts and `match_rate`. `blocked_member_count = requested − eligible` is the **all-cause** count of members the gate removed (consent, preference, reachability, *or* suppression) — deliberately **not** named `suppressed`, since that would re-collapse the governed states ADR 0027 keeps distinct (a consumer must not read it as a do-not-contact rate). It **audits** the consent gate, it does not perform it — the gate stays `gold_activatable_audience_current`. The invariants `exported ≤ eligible ≤ requested` and `requested − eligible = blocked` are DQ errors (`aj_counts_monotonic`, `aj_blocked_reconciles`), making the gate's effect observable.

   **Jurisdiction scope.** The gate is jurisdiction-grained (consent is per-jurisdiction), so `activation_job` carries a nullable `jurisdiction_code`: when set, the counts are scoped to one regime and reconcile against the gate; when NULL, they are a jurisdiction-agnostic roll-up across regimes (acceptable for adopters without multi-regime residency needs). It also gives **informational** residency traceability against a residency-constrained destination (`data_residency_region`), but that is deliberately **not** DQ-reconciled (unlike the purpose/channel match, which is): a regulatory-regime code and a processing-region label do not map 1:1, so a hard check would false-positive. Because the counts are adopter-supplied, ORDM ships the scope column + grain but not a producer.

3. **`campaign_touch`** — an append-only gold **transactional** fact: one row per owned/CRM interaction (send, open, click, unsubscribe, conversion), sourced from an activation. Deliberately **distinct from CMN `media_event`** (paid ad-delivery exposures): `campaign_touch` is the owned messaging plane, keyed to the resolved `profile_id`; `media_event` is the paid retail-media plane. Consent is carried per touch as governance evidence.

4. **Layering.** All three are gold and reference **downward only**: `activation_job` → `marketing.audience` (gold→silver, allowed) and → `activation_destination` (gold→gold, same package); `campaign_touch` → `customer.profile` (gold→silver), → `marketing.audience` / `marketing.promotion` (gold→silver), and → `activation_job` (gold→gold). No canonical-core table references the activation layer (LAYER-INTEGRITY preserved).

5. **Keys.** Facts use the uniform nullable `_sk` + durable `_id` FK-pair shape (like CMN `media_event`), with informational FKs on the `_sk` and per-`_sk` orphan DQ checks — chosen over ACU `segment_membership`'s durable-`_id`-only shape because these are analytics/audit facts, not a reverse-ETL sync surface.

6. **No UCV metric views.** UCV is engine-neutral by design (metrics are glossary definitions, not UC Metric Views — `test_engine_neutral_no_metric_views`). Activation KPIs (`activation_export_rate`, `activation_block_rate`, `activation_match_rate`, `campaign_touch_count`, `campaign_reach`) are added as engine-neutral glossary definitions plus metric-severity DQ checks, consistent with the package.

7. **Adopter-owned producers.** Like `customer_profile_snapshot`, ORDM ships the schema + DQ contract, not a synthetic producer; the DQ checks pass vacuously on empty tables and validate whatever an adopter's activation/campaign job writes.

## Consequences

- The UCV `CDP` use-case moves **blocked → in-progress**; the CDP loop (define → target → gate → activate → audit → touch) is now expressible end-to-end.
- CDP is delivered as UCV ∘ ACU with **no `cdp` package** and no new outcome package (12 packages unchanged).
- `activation_destination.required_consent_purpose` / `required_channel` make destination-level consent enforcement auditable (enforced by `aj_destination_purpose_channel_match`); `activation_job.blocked_member_count` surfaces the gate's all-cause effect per run.
- Generated artifacts (model.json, ODCS, ER diagrams/SVGs) regenerate to show the three tables under `unified_customer_view`.

## Alternatives considered

- **A standalone `cdp` / customer-activation outcome package.** Rejected: re-homes an outcome UCV already owns and forces the new-package signoff process; the activation layer's only consumer today is the CDP/UCV outcome (CONTRIBUTING §6 keeps single-outcome extensions in the owning package).
- **Fold `campaign_touch` into CMN `media_event`.** Rejected: conflates paid ad-delivery exposures with owned CRM outreach — different planes, different keys (hashed clean-room ids vs. resolved `profile_id`), different consent semantics.
- **Model `activation_destination` as an SCD2 `master`.** Rejected for v1: connector config history is nice-to-have, and each run's point-in-time purpose/channel is already captured on `activation_job`; a Type-1 `reference` catalog (no `ref_` name prefix, matching the `delivery_channel` reference convention) keeps the surface small. Promote to SCD2 if config-lineage audit becomes a requirement.
