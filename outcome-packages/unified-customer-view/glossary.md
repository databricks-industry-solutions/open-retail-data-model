# Unified Customer View — Business Glossary

> Status: 🟢 Review complete (0.5) · Last reviewed: 2026-10-07

Vendor-neutral; follows the ORDM [data model standards](../../docs/data-model-standards.md). Built entirely
on the thin customer core — no product/transaction/campaign data.

## Tables & views

| Object | Grain | Description |
|---|---|---|
| `customer_profile_snapshot` | One row per profile per snapshot_date | Append-only point-in-time snapshot of identity/consent/preference/household roll-ups. Extension table; no raw PII. |
| `gold_unified_customer_360_current` | One current row per customer | Conformed 360 summary keyed on the customer surrogate; identity, consent, preference, household roll-ups. No raw PII. |
| `gold_customer_activation_eligibility_current` | One row per customer × purpose × channel | Net-permission gate: `eligible_flag` = consent granted AND preference allows AND a valid identifier exists, with `blocking_reason_code`. |
| `gold_activatable_audience_current` | One row per audience × profile × purpose × channel × jurisdiction (channel is NULL for the channel-agnostic non-marketing purposes) | The activation surface: behavioral-segment membership (ACU `segment_membership`, latest as-of) joined to the net eligibility gate, keyed on the durable `profile_id`. Fail-closed — a customer appears only where an eligible gate row exists and the segment is addressable. Also independently anti-joins the shared person-level do-not-target set (`gold_person_do_not_target_current`, ADR 0028) so it is DNT-safe on any plane a consumer syncs it to. Person-level DNT only — a selling/sharing plane must still apply the purpose-level do-not-sell/share opt-out (leg b). No raw PII. |
| `gold_person_do_not_target_current` | One row per profile with an active person-level do-not-target | The cross-plane do-not-target set (ADR 0028): profiles carrying a person-level suppression (`deceased` / `fraud` / `do_not_contact` / `legal_objection`; a GDPR Art.21 objection is absolute). The owned gate sources it and any paid / non-owned activation plane must anti-join it, so a person-suppressed customer is blocked everywhere, not just owned channels. Keyed on the durable `profile_id`; no raw PII. |
| `activation_destination` | One row per destination connector | *(CDP activation layer, ADR 0026)* Type-1 catalog of where an activatable audience can publish (reverse-ETL / ad platform / ESP-SMS / clean room / file export). `required_consent_purpose` × `required_channel` make the gate destination-aware. Config only — never member lists. |
| `activation_job` | One row per audience × destination × jurisdiction × run | *(CDP activation layer, ADR 0026)* Append-only audit of each audience-to-destination publish: requested / eligible / blocked / exported member counts and match rate, scoped to a `jurisdiction_code`. `blocked` is all-cause (consent, preference, reachability, or suppression) — not suppression-specific. Also records the **write operation** (`sync_mode`: full_refresh / incremental_upsert / delete_only) and **retraction** count (`removed_member_count` — members pulled from a prior export for do-not-sell / DSAR / newly-suppressed, the delete leg that propagates a suppression downstream), a destination **delivered / rejected** accept split, run **start / complete** timestamps, and two gate-provenance flags (`is_consent_enforced_flag`, `is_suppression_applied_flag` — the latter must be TRUE on a paid/non-owned plane per the ADR 0028 cross-plane contract). Audits the fail-closed gate (`exported ≤ eligible ≤ requested`); does not perform it. |
| `campaign_touch` | One row per profile × promotion × touch_ts × touch_type | *(CDP activation layer, ADR 0026)* Append-only owned/CRM interaction history (sends, opens, clicks, unsubscribes, conversions) sourced from an activation. Distinct from paid CMN `media_event`. Keyed on the pseudonymous `profile_id`; no raw PII. |
| `profile` / `identity_link` / `consent` / `channel_preference` / `household` / `contact` / `address` | — | *(canonical-core)* the customer core this package rolls up. |
| `audience` / `promotion` | — | *(canonical-core marketing)* the shared segment definition (ADR 0022) and offer/campaign the activation layer references. |

## Key concepts

| Term | Definition |
|---|---|
| **360 summary vs. eligibility gate** | The 360 view's consent flags are a customer-level *summary* ("granted anywhere"). The authoritative per-purpose × channel permission — resolved as-of `jurisdiction_code` — is `gold_customer_activation_eligibility_current`. |
| **Activation eligibility** | `eligible_flag = consent_granted AND preference_allows AND has_identifier AND NOT suppressed`. Consent (legal), preference (soft opt-out), reachability (a valid identifier), and suppression (a do-not-contact overlay) are four distinct governed states and are never collapsed (principle #5). |
| **`blocking_reason_code`** | First failing rule when not eligible, suppression first: `suppressed` / `withdrawn` / `consent_denied` / `preference_opt_out` / `no_identifier`. `suppressed` is a do-not-contact overlay (`consent.suppression_indicator`) that **overrides granted consent**, distinct from the customer withdrawing consent. Channel-level reasons (bounce, complaint, unsubscribe) block one channel; person-level reasons (deceased, fraud, do_not_contact, legal_objection) block **all** channels for the profile (the gate propagates them across scopes — review H1). |
| **`resolved_identity_confidence`** | Identity-resolution confidence in [0,1]: the highest `match_confidence` across a customer's current `active` identity links. |
| **`reachability_score`** | Fraction of channels (email/sms/postal) a customer is reachable on = consent + preference + identifier present. |
| **`profile_completeness_score`** | Fraction of key attributes populated (name, dob, email, address). |
| **`jurisdiction_primary_code`** | The customer's governing privacy region (from primary address); consent precision lives in the eligibility view's `jurisdiction_code`. |

## Metrics (definitions)

These KPIs are captured **engine-neutrally** — definition, grain, and expression — so any consumer can
implement them (dbt metrics, Cube, a BI semantic layer, or Databricks UC Metric Views). The package ships
them as UC Metric Views in `metric-views/` (`mv_customer_360`, `mv_cdp_activation_eligibility`,
`mv_cdp_activation_jobs`, `mv_cdp_campaign_touch`). `avg_household_size` is defined over distinct
households, which the 360 view does not key, so it is not one of the metric-view measures; for the
same reason `mv_customer_360` slices by customer status and jurisdiction but not by household or
household type. `contactable_rate` ships per channel as `email_contactable_rate` and
`sms_contactable_rate`; every other metric above ships under its own name. The views add
supporting counts (rows, runs, members) and the personalization and third-party sharing consent
rates, which follow the `consent_marketing_rate` definition.

| Metric | Definition | Grain / dimensions | Expression (over the gold views) |
|---|---|---|---|
| `active_customer_count` | Count of current unified customers. | customer · dims: status, jurisdiction, household | `COUNT(*)` over `gold_unified_customer_360_current` |
| `avg_identity_confidence` | Mean resolved-identity confidence. | customer | `AVG(resolved_identity_confidence)` |
| `identity_coverage_rate` | Share of customers with ≥1 active resolved identifier. | customer | `AVG(CASE WHEN active_identifier_count > 0 THEN 1.0 ELSE 0 END)` |
| `consent_marketing_rate` | Share of customers with marketing consent granted. | customer · dims: jurisdiction | `AVG(CASE WHEN consent_marketing_flag THEN 1.0 ELSE 0 END)` |
| `contactable_rate` | Share contactable per channel. | customer × channel | `AVG(<channel>_contactable_flag)` |
| `household_coverage` | Share of customers assigned to a household. | customer · dims: household_type | `AVG(CASE WHEN household_size IS NOT NULL THEN 1.0 ELSE 0 END)` |
| `avg_household_size` | Mean household size. | household | `AVG(household_size)` over distinct households |
| `avg_reachability_score` | Mean activation-readiness. | customer | `AVG(reachability_score)` |
| `avg_profile_completeness` | Mean profile completeness. | customer | `AVG(profile_completeness_score)` |
| `consent_granted_rate_by_purpose` | Share of purpose×channel rows with consent granted. | customer × purpose × channel · dims: jurisdiction | `AVG(CASE WHEN consent_granted_flag THEN 1.0 ELSE 0 END)` over the eligibility view |
| `eligible_rate` | Share of purpose×channel rows that are activation-eligible. | customer × purpose × channel · dims: purpose, channel, jurisdiction | `AVG(CASE WHEN eligible_flag THEN 1.0 ELSE 0 END)` |
| `suppression_rate` | Share of purpose×channel rows blocked by a do-not-contact suppression overlay. | customer × purpose × channel · dims: jurisdiction | `AVG(CASE WHEN is_suppressed_flag THEN 1.0 ELSE 0 END)` over the eligibility view |
| `activation_export_rate` | Share of gate-eligible members actually exported (activation efficiency). | destination × audience | `SUM(exported_member_count) / SUM(eligible_member_count)` over `activation_job` (ratio-of-sums) |
| `activation_block_rate` | Share of requested members the eligibility gate removed for ANY reason (consent, preference, reachability, or suppression) — an all-cause block rate, NOT suppression-specific. | destination × audience · dims: purpose, channel, jurisdiction | `SUM(blocked_member_count) / SUM(requested_member_count)` over `activation_job` |
| `activation_match_rate` | Member-weighted provider match rate across exports (denominator counts only exports with a known match_rate). | destination | `SUM(exported_member_count * match_rate) / SUM(CASE WHEN match_rate IS NOT NULL THEN exported_member_count END)` over `activation_job` |
| `campaign_touch_count` | Count of campaign interactions. | profile × promotion · dims: channel, direction, touch_type | `COUNT(*)` over `campaign_touch` |
| `campaign_reach` | Distinct customers touched by a campaign. | promotion | `COUNT(DISTINCT profile_id)` over `campaign_touch` |

## Standards used

| Concept | Standard |
|---|---|
| Dates / timestamps | ISO 8601 (UTC) |
| Jurisdiction / country | ISO 3166 (`jurisdiction_code`, `jurisdiction_primary_code`) |
| Privacy scoping | GDPR / CCPA-CPRA (consent resolved as-of jurisdiction) |

## Deferred (documented, not built)

The suppression ledger; a
`fact_behavior_event` clickstream fact (raw event collection is out of scope per the CDP brief); and any
360 field needing transaction/product/store data (LTV, purchase recency, affinity, preferred store).
(Segment/audience membership and the activation surface are BUILT: `audience` is a silver master, ACU ships
`segment_membership`, and `gold_activatable_audience_current` is the activation join. The **activation layer**
is now BUILT too, ADR 0026: `activation_destination`, `activation_job`, and `campaign_touch` — shipped as
schema + DQ contract, adopter-owned producers like `customer_profile_snapshot`.) See
[`docs/design/customer-identity/`](../../docs/design/customer-identity/).
