-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- View: gold_person_do_not_target_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Promote to a materialized view
--   at deploy time if a low-latency do-not-target lookup is needed; definition unchanged.
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- The profile-grain, CHANNEL/PURPOSE/JURISDICTION-agnostic do-not-target set: every
-- profile carrying a PERSON-level suppression on ANY current consent scope. Person-level
-- reasons (deceased, fraud, do_not_contact, legal_objection; a GDPR Art.21 direct-marketing
-- objection) are absolute at the person level, so this view is the SINGLE do-not-target
-- consult for EVERY activation plane:
--   * the OWNED-channel gate (gold_customer_activation_eligibility_current) sources it, and
--   * any NON-OWNED / PAID activation (retail-media / DSP / clean-room onboarding built over
--     ACU segment_membership) that does not resolve people through the owned gate MUST
--     anti-join it before targeting, so a person-suppressed customer cannot be uploaded to a
--     paid destination (the cross-plane closure of ADR 0027's "blocks every channel" claim;
--     see ADR 0028).
-- Keyed on the durable profile_id only (no jurisdiction predicate) — matching ADR 0027's
-- deliberate, fail-safe cross-jurisdiction propagation (over-suppress rather than risk
-- under-suppressing a do-not-contact signal that carries legal weight). No PII is exposed
-- (pseudonymous profile_id only).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ucv_schema}.gold_person_do_not_target_current AS
SELECT
  profile_id,
  -- Representative reason at a deterministic priority (legal_objection > deceased >
  -- do_not_contact > fraud — do NOT reorder the CASE branches, so the surfaced value is
  -- stable when a profile carries more than one person-level reason across scopes).
  -- PRESENTATIONAL ONLY: all four reasons block IDENTICALLY (a profile in this view is
  -- do-not-target regardless of which reason won) — the ordering carries NO legal precedence
  -- and must not be read as one; it only makes the single displayed reason deterministic.
  -- Read customer.consent for the full set of reasons and scopes.
  CASE
    WHEN MAX(CASE WHEN suppression_reason_code = 'legal_objection' THEN 1 ELSE 0 END) = 1 THEN 'legal_objection'
    WHEN MAX(CASE WHEN suppression_reason_code = 'deceased'        THEN 1 ELSE 0 END) = 1 THEN 'deceased'
    WHEN MAX(CASE WHEN suppression_reason_code = 'do_not_contact'  THEN 1 ELSE 0 END) = 1 THEN 'do_not_contact'
    WHEN MAX(CASE WHEN suppression_reason_code = 'fraud' THEN 1 ELSE 0 END) = 1 THEN 'fraud'
    ELSE NULL  -- defensive only, and UNREACHABLE by construction: the WHERE below pins
               -- suppression_reason_code to exactly these four, so a fifth person-level reason
               -- is filtered out BEFORE this CASE and never reaches ELSE (it simply won't appear
               -- in the view). Adding a new person-level reason therefore means updating BOTH the
               -- WHERE filter and this CASE ladder together -- it does NOT auto-"fail loud" here.
  END AS do_not_target_reason_code
FROM ${catalog}.${customer_schema}.consent
WHERE is_current = TRUE
  AND COALESCE(suppression_indicator, FALSE) = TRUE
  AND suppression_reason_code IN ('deceased', 'fraud', 'do_not_contact', 'legal_objection')
GROUP BY profile_id;
-- Grain: one row per profile_id with an active person-level do-not-target.
