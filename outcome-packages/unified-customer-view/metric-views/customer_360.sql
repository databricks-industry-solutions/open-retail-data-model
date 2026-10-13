-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- Metric View: customer_360
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-12
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-12
-- ============================================================
-- The customer-grain KPIs of the UCV glossary ("Metrics (definitions)") as a UC
-- Metric View over gold_unified_customer_360_current, one row per current unified
-- customer. Serves the Customer 360 and Identity Resolution use cases: customer
-- count, identity confidence and coverage, consent, per-channel contactability,
-- household coverage, reachability and profile completeness.
--
-- Every rate is a share of customers (AVG of a 0/1 indicator = SUM/COUNT at
-- customer grain), so it rolls up correctly by any dimension. No person-level
-- field: profile_id is not a dimension. The glossary's avg_household_size is
-- defined over DISTINCT households, and the 360 view carries no household key,
-- so it is not a measure here (a per-customer average would over-weight large
-- households).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ucv_schema}.mv_customer_360
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Customer 360 and identity-resolution KPIs over the current unified customer view: customer count, identity confidence and coverage, consent, contactability, household coverage, reachability and profile completeness."
source: >
  SELECT
    c360.jurisdiction_primary_code,
    c360.customer_status_code,
    c360.household_size,
    c360.active_identifier_count,
    c360.resolved_identity_confidence,
    c360.consent_marketing_flag,
    c360.consent_personalization_flag,
    c360.consent_third_party_sharing_flag,
    c360.email_contactable_flag,
    c360.sms_contactable_flag,
    c360.reachability_score,
    c360.profile_completeness_score
  FROM ${catalog}.${ucv_schema}.gold_unified_customer_360_current c360

fields:
  - name: jurisdiction_primary_code
    expr: jurisdiction_primary_code
    display_name: "Primary Jurisdiction"
    comment: "The customer's governing privacy region (ISO 3166), from the primary address. Per-purpose consent precision lives in the eligibility view."
    synonyms: ["jurisdiction", "privacy_region", "region"]
  - name: customer_status_code
    expr: customer_status_code
    display_name: "Customer Status"
    comment: "Lifecycle status of the unified customer."
    synonyms: ["status", "lifecycle_status"]

measures:
  - name: active_customer_count
    expr: COUNT(*)
    display_name: "Active Customer Count"
    comment: "Count of current unified customers (glossary active_customer_count)."
    synonyms: ["customer_count", "unified_customers"]
  - name: avg_identity_confidence
    expr: AVG(resolved_identity_confidence)
    display_name: "Avg Identity Confidence"
    comment: "Mean resolved-identity confidence in [0,1]: per customer, the highest match_confidence across current active identity links (glossary avg_identity_confidence)."
    synonyms: ["identity_confidence", "match_confidence"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
  - name: identity_coverage_rate
    expr: AVG(CASE WHEN active_identifier_count > 0 THEN 1.0 ELSE 0 END)
    display_name: "Identity Coverage Rate"
    comment: "Share of customers with at least one active resolved identifier (glossary identity_coverage_rate)."
    synonyms: ["identity_coverage", "resolved_share"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: consent_marketing_rate
    expr: AVG(CASE WHEN consent_marketing_flag THEN 1.0 ELSE 0 END)
    display_name: "Marketing Consent Rate"
    comment: "Share of customers with marketing consent granted, the 360 summary (granted anywhere). Use mv_cdp_activation_eligibility for the per-purpose x channel x jurisdiction permission (glossary consent_marketing_rate)."
    synonyms: ["marketing_consent", "opt_in_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: consent_personalization_rate
    expr: AVG(CASE WHEN consent_personalization_flag THEN 1.0 ELSE 0 END)
    display_name: "Personalization Consent Rate"
    comment: "Share of customers with personalization consent granted (same definition as consent_marketing_rate, for the personalization purpose)."
    synonyms: ["personalization_consent"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: consent_third_party_sharing_rate
    expr: AVG(CASE WHEN consent_third_party_sharing_flag THEN 1.0 ELSE 0 END)
    display_name: "Third-Party Sharing Consent Rate"
    comment: "Share of customers with third-party sharing consent granted (same definition as consent_marketing_rate, for the third-party sharing purpose)."
    synonyms: ["sharing_consent", "third_party_consent"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: email_contactable_rate
    expr: AVG(CASE WHEN email_contactable_flag THEN 1.0 ELSE 0 END)
    display_name: "Email Contactable Rate"
    comment: "Share of customers contactable by email (glossary contactable_rate, email channel)."
    synonyms: ["email_reach", "emailable_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: sms_contactable_rate
    expr: AVG(CASE WHEN sms_contactable_flag THEN 1.0 ELSE 0 END)
    display_name: "SMS Contactable Rate"
    comment: "Share of customers contactable by SMS (glossary contactable_rate, sms channel)."
    synonyms: ["sms_reach", "textable_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: household_coverage
    expr: AVG(CASE WHEN household_size IS NOT NULL THEN 1.0 ELSE 0 END)
    display_name: "Household Coverage Rate"
    comment: "Share of customers assigned to a household (glossary household_coverage)."
    synonyms: ["household_coverage_rate", "householded_share"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: avg_reachability_score
    expr: AVG(reachability_score)
    display_name: "Avg Reachability Score"
    comment: "Mean activation readiness: per customer, the fraction of channels (email/sms/postal) with consent, preference and an identifier present (glossary avg_reachability_score)."
    synonyms: ["reachability", "activation_readiness"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
  - name: avg_profile_completeness
    expr: AVG(profile_completeness_score)
    display_name: "Avg Profile Completeness"
    comment: "Mean fraction of key profile attributes populated (name, dob, email, address) (glossary avg_profile_completeness)."
    synonyms: ["profile_completeness", "data_completeness"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
$$;
