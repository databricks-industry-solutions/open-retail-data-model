# The CDP model in ORDM — a composition, not a package

ORDM delivers the retail **Customer Data Platform (CDP)** outcome as a **composition of existing
pieces**, not as a standalone `cdp` package. A single package would re-home an outcome that already
has owners and would be the one-outcome-one-package anti-pattern (see [ADR 0026](../governance/decisions/0026-cdp-activation-layer-in-ucv.md)).
This page is the map: it names the four pieces, the loop they form, and where each lives — so the CDP
model is discoverable in one place even though it deliberately spans the core and two packages.

## The loop: define → target → govern → gate → activate → audit

| Stage | Entity | Home | What it does |
|---|---|---|---|
| **Define** | `audience` | canonical core · `marketing` | The shared, versioned segment/audience **definitions** (SCD2). [ADR 0022](../governance/decisions/0022-promote-audience-to-silver-marketing.md). |
| **Target** | `segment_membership`, `gold_customer_behavioral_attributes` | outcome package · **Actionable Customer Understanding (ACU)** | Who is in each segment (append-only as-of snapshots) + the wide, agent-discoverable trait surface a CDP segments on. Targeting plane only — carries no consent. |
| **Govern** | `consent` (+ suppression overlay) | canonical core · `customer` | The single source of truth for consent, preference, and the do-not-contact **suppression** overlay ([ADR 0027](../governance/decisions/0027-consent-suppression-overlay.md)). Person-level do-not-target is projected as `gold_person_do_not_target_current` and consulted by **every** activation plane ([ADR 0028](../governance/decisions/0028-cross-plane-do-not-target-and-multi-purpose-gate.md)). |
| **Gate** | `gold_customer_activation_eligibility_current`, `gold_activatable_audience_current` | outcome package · **Unified Customer View (UCV)** | The net-permission gate (`eligible = consent ∧ preference ∧ identifier ∧ ¬ suppressed`) and the fail-closed activation surface (targeting ∘ gate). |
| **Activate** | `activation_destination`, `activation_job` | outcome package · **UCV** | The connector catalog (where an audience publishes) and the append-only audit of each publish (requested / eligible / blocked / exported counts + sync/retraction telemetry). [ADR 0026](../governance/decisions/0026-cdp-activation-layer-in-ucv.md). |
| **Touch** | `campaign_touch` | outcome package · **UCV** | The owned/CRM interaction history that results (send / open / click / unsubscribe / conversion), distinct from paid `media_event`. |

## Why it is split this way

- **Definitions are shared, so they live in the core** (`marketing.audience`) — many outcomes reference them (§6 ≥2-consumer test).
- **Segmentation (ACU) and activation (UCV) are distinct outcomes** with distinct owners; ADR 0024 couples them gold→gold rather than merging them.
- **Consent/suppression is core** (`customer.consent`) because it is the single source of truth every plane must honor — including the paid plane, via the shared do-not-target view (ADR 0028).
- **No `cdp` package**: the activation-execution layer is single-outcome (it serves the CDP/UCV outcome) and consumes existing definitions rather than redefining them, so it belongs in the owning UCV package.

## Cross-plane governance (the important guarantee)

A person-level do-not-target signal (`deceased`, `fraud`, `do_not_contact`, `legal_objection` — a GDPR
Art.21 objection is absolute) blocks activation on **every** plane, not just owned channels. The owned
gate and any paid / non-owned onboarding both consult `gold_person_do_not_target_current` (ADR 0028).
On the **owned** plane this is enforced in CI: `ucv_eligibility_person_suppressed_blocked` and
`uav_no_person_suppressed` assert no do-not-target profile is ever eligible or activatable. On a **paid /
non-owned reverse-ETL** plane — adopter-owned onboarding that ORDM cannot execute — the guarantee is an
**adopter obligation**: the consumer must anti-join `gold_person_do_not_target_current` before targeting,
per the activation contract in `segment_membership`'s header. ORDM ships the governed set and the contract;
it cannot CI-enforce a sync it does not run.

## See also

- Package READMEs: [Unified Customer View](../outcome-packages/unified-customer-view/README.md) · [Actionable Customer Understanding](../outcome-packages/actionable-customer-understanding/README.md)
- [Outcome map](outcome-map.md) — the 12 retail outcome pillars
- ADRs [0022](../governance/decisions/0022-promote-audience-to-silver-marketing.md) · [0024](../governance/decisions/0024-gold-to-gold-coupling-acu-ucv.md) · [0026](../governance/decisions/0026-cdp-activation-layer-in-ucv.md) · [0027](../governance/decisions/0027-consent-suppression-overlay.md) · [0028](../governance/decisions/0028-cross-plane-do-not-target-and-multi-purpose-gate.md)
