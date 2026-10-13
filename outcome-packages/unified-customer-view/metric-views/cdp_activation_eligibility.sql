-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- Metric View: cdp_activation_eligibility
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-12
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-12
-- ============================================================
-- The CDP eligibility-gate KPIs of the UCV glossary as a UC Metric View over
-- gold_customer_activation_eligibility_current (ADR 0026 / ADR 0028), one row per
-- customer x purpose x channel x jurisdiction. Answers "how much of the base may we
-- activate, for which purpose and channel, and what blocks the rest".
--
-- Each rate is a share of gate rows (AVG of a 0/1 indicator = SUM/COUNT at the
-- view's grain), so it rolls up by purpose, channel, jurisdiction or blocking
-- reason. A customer contributes one row per purpose x channel x jurisdiction:
-- these are permission shares, not customer counts. No person-level field.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ucv_schema}.mv_cdp_activation_eligibility
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "CDP activation-gate KPIs: share of customer x purpose x channel rows with consent granted, eligible to activate, and suppressed, by purpose, channel, jurisdiction and blocking reason."
source: >
  SELECT
    elig.purpose_code,
    elig.channel_code,
    elig.jurisdiction_code,
    elig.blocking_reason_code,
    elig.consent_granted_flag,
    elig.eligible_flag,
    elig.is_suppressed_flag
  FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current elig

fields:
  - name: purpose_code
    expr: purpose_code
    display_name: "Activation Purpose"
    comment: "Consent purpose evaluated by the gate (for example marketing, personalization, retail_media, data_sale)."
    synonyms: ["purpose", "consent_purpose"]
  - name: channel_code
    expr: channel_code
    display_name: "Channel"
    comment: "Contact channel the permission applies to; NULL for channel-agnostic purposes."
    synonyms: ["channel", "medium"]
  - name: jurisdiction_code
    expr: jurisdiction_code
    display_name: "Jurisdiction"
    comment: "ISO 3166 jurisdiction the consent is resolved as-of."
    synonyms: ["jurisdiction", "privacy_region"]
  - name: blocking_reason_code
    expr: blocking_reason_code
    display_name: "Blocking Reason"
    comment: "First failing rule when not eligible, suppression first: suppressed / withdrawn / consent_denied / preference_opt_out / no_identifier. NULL when eligible."
    synonyms: ["block_reason", "ineligibility_reason"]

measures:
  - name: gate_row_count
    expr: COUNT(*)
    display_name: "Gate Rows"
    comment: "Count of customer x purpose x channel x jurisdiction rows the gate evaluated."
    synonyms: ["permission_rows", "evaluated_rows"]
  - name: consent_granted_rate_by_purpose
    expr: AVG(CASE WHEN consent_granted_flag THEN 1.0 ELSE 0 END)
    display_name: "Consent Granted Rate"
    comment: "Share of purpose x channel rows with consent granted (glossary consent_granted_rate_by_purpose)."
    synonyms: ["consent_rate", "consent_granted_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: eligible_rate
    expr: AVG(CASE WHEN eligible_flag THEN 1.0 ELSE 0 END)
    display_name: "Activation Eligible Rate"
    comment: "Share of purpose x channel rows that are activation-eligible: consent granted AND preference allows AND an identifier is present AND not suppressed (glossary eligible_rate)."
    synonyms: ["activatable_rate", "eligibility_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: suppression_rate
    expr: AVG(CASE WHEN is_suppressed_flag THEN 1.0 ELSE 0 END)
    display_name: "Suppression Rate"
    comment: "Share of purpose x channel rows blocked by a do-not-contact suppression overlay, which overrides granted consent (glossary suppression_rate)."
    synonyms: ["suppressed_rate", "do_not_contact_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
$$;
