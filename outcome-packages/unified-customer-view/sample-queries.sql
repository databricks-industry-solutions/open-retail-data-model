-- ============================================================
-- ORDM · Outcome Package · Unified Customer View · sample queries
-- Version: 0.5 · Generated: 2026-07-10 · LLM-generated: true · Reviewed: 2026-07-10
-- Illustrative read patterns against the gold views. Substitute ${catalog}
-- and ${ucv_schema} at deploy time. No raw PII is available in these surfaces.
-- ============================================================

-- 1. The 360 summary for a sample of customers.
SELECT profile_id, household_size, active_identifier_count, resolved_identity_confidence,
       consent_marketing_flag, email_contactable_flag, sms_contactable_flag,
       preferred_channel_code, reachability_score, profile_completeness_score
FROM ${catalog}.${ucv_schema}.gold_unified_customer_360_current
ORDER BY reachability_score DESC
LIMIT 25;

-- 2. Marketing-reachable population by primary jurisdiction.
SELECT jurisdiction_primary_code,
       COUNT(*)                                                   AS customers,
       SUM(CASE WHEN marketing_eligible_flag THEN 1 ELSE 0 END)    AS marketing_eligible,
       ROUND(AVG(CASE WHEN marketing_eligible_flag THEN 1.0 ELSE 0 END), 4) AS eligible_rate
FROM ${catalog}.${ucv_schema}.gold_unified_customer_360_current
GROUP BY jurisdiction_primary_code
ORDER BY customers DESC;

-- 3. Who can I email for marketing right now? (the activation gate)
SELECT profile_id, jurisdiction_code
FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current
WHERE purpose_code = 'marketing' AND channel_code = 'email' AND eligible_flag = TRUE;

-- 4. Why are customers blocked, by channel? (drives data/consent remediation)
SELECT channel_code, blocking_reason_code, COUNT(*) AS blocked
FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current
WHERE eligible_flag = FALSE
GROUP BY channel_code, blocking_reason_code
ORDER BY channel_code, blocked DESC;

-- 4b. Suppression overlay: customers who granted consent but are do-not-contact
-- suppressed (would be wrongly mailed if suppression were ignored). ADR 0027.
SELECT channel_code, COUNT(*) AS suppressed_despite_consent
FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current
WHERE is_suppressed_flag = TRUE AND consent_granted_flag = TRUE
GROUP BY channel_code
ORDER BY suppressed_despite_consent DESC;

-- 5. Eligible reach per channel (the eligible_rate metric, materialized ad hoc).
SELECT channel_code,
       COUNT(*)                                              AS evaluated,
       ROUND(AVG(CASE WHEN eligible_flag THEN 1.0 ELSE 0 END), 4) AS eligible_rate
FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current
GROUP BY channel_code
ORDER BY channel_code;

-- 6. Household coverage and average household size.
SELECT ROUND(AVG(CASE WHEN household_size IS NOT NULL THEN 1.0 ELSE 0 END), 4) AS household_coverage,
       ROUND(AVG(household_size), 2)                                           AS avg_household_size
FROM ${catalog}.${ucv_schema}.gold_unified_customer_360_current;

-- ============================================================
-- CDP activation layer (ADR 0026)
-- ============================================================

-- 7. Activation efficiency by destination: how much audience cleared the consent gate
--    and was exported, and how much the gate blocked (all-cause). Ratio-of-sums, never per-run avg.
SELECT d.destination_platform,
       COUNT(*)                                                              AS runs,
       SUM(j.requested_member_count)                                         AS requested,
       SUM(j.eligible_member_count)                                          AS eligible,
       SUM(j.exported_member_count)                                          AS exported,
       ROUND(SUM(j.exported_member_count) / NULLIF(SUM(j.eligible_member_count), 0),  4) AS export_rate,
       ROUND(SUM(j.blocked_member_count)  / NULLIF(SUM(j.requested_member_count), 0), 4) AS block_rate
FROM ${catalog}.${ucv_schema}.activation_job j
LEFT JOIN ${catalog}.${ucv_schema}.activation_destination d
  ON j.activation_destination_id = d.activation_destination_id
WHERE j.job_status = 'succeeded'
GROUP BY d.destination_platform
ORDER BY exported DESC;

-- 8. Latest activation run per audience × destination (reproducible snapshot lineage).
SELECT audience_id, activation_destination_id, membership_as_of_date, job_status,
       requested_member_count, eligible_member_count, exported_member_count, match_rate
FROM ${catalog}.${ucv_schema}.activation_job j
QUALIFY ROW_NUMBER() OVER (
          PARTITION BY audience_id, activation_destination_id
          ORDER BY job_run_ts DESC) = 1;

-- 9. Campaign touch funnel by channel (owned/CRM outreach; distinct from paid media_event).
SELECT channel_code,
       COUNT(*)                                                          AS touches,
       COUNT(DISTINCT profile_id)                                        AS reached_customers,
       SUM(CASE WHEN touch_type = 'delivery'   THEN 1 ELSE 0 END)        AS delivered,
       SUM(CASE WHEN touch_type = 'open'       THEN 1 ELSE 0 END)        AS opens,
       SUM(CASE WHEN touch_type = 'click'      THEN 1 ELSE 0 END)        AS clicks,
       SUM(CASE WHEN touch_type = 'conversion' THEN 1 ELSE 0 END)        AS conversions
FROM ${catalog}.${ucv_schema}.campaign_touch
WHERE touch_direction = 'outbound'
GROUP BY channel_code
ORDER BY touches DESC;

-- 10. Closed loop: touches traced back to the activation run and its destination.
SELECT t.campaign_touch_id, t.profile_id, t.touch_type, t.channel_code,
       j.activation_destination_id, j.audience_id, j.membership_as_of_date
FROM ${catalog}.${ucv_schema}.campaign_touch t
JOIN ${catalog}.${ucv_schema}.activation_job j
  ON t.activation_job_id = j.activation_job_id
WHERE t.consent_status = 'granted'
LIMIT 50;

-- 11. Paid / reverse-ETL onboarding (ADR 0028): the two suppressions a PAID plane MUST write
-- when it syncs segment_membership directly (bypassing the owned gate). This is the load-bearing
-- cross-plane contract, and it has TWO legs — anti-joining the do-not-target view ALONE is NOT
-- sufficient for a selling/sharing plane:
--   (a) PERSON-level do-not-target (purpose-agnostic): a deceased / legal-objection /
--       do_not_contact / fraud customer is dropped on every plane (gold_person_do_not_target_current).
--   (b) PURPOSE-level do-not-sell / do-not-share (CCPA/CPRA opt-out): a paid plane that DISCLOSES
--       personal information for cross-context advertising (share) or for consideration (sell) must
--       also drop anyone who has opted OUT of the matching purpose — a current data_sale (do-not-sell)
--       or third_party_sharing (do-not-share) consent that is withdrawn OR suppression-flagged. The
--       do-not-target view does NOT cover this: it is scoped to the four person-level reasons and
--       ignores consent, so leg (b) is exactly the gap it leaves for the sell/share purposes.
-- (Opt-out semantics, per CCPA/CPRA: absence of an opt-out = permitted; an explicit withdraw/suppress
-- = do-not-sell/share. Scope the consent check by jurisdiction_code for a GDPR opt-in regime.)
-- NOTE — do NOT substitute the owned gate here: gold_customer_activation_eligibility_current is
-- opt-IN / fail-closed (a data_sale/retail_media row is eligible ONLY where consent_status='granted',
-- so a never-decided profile is ABSENT = not eligible), whereas leg (b) above is opt-OUT (a
-- never-decided profile passes NOT EXISTS = permitted). For a never-decided consumer they return
-- OPPOSITE populations; the gate is the safe/conservative choice for an OWNED opt-in plane, but a
-- selling/sharing plane governed by CCPA opt-out MUST use leg (b), not the gate. Copy this shape
-- into any reverse-ETL / clean-room job.
WITH latest_membership AS (
  -- Current membership per SEGMENT: the audience's most recent snapshot, minus exited rows.
  -- Grain is MAX(as_of_date) GROUP BY audience_id (NOT per profile+audience) — matching the
  -- canonical rule in gold_activatable_audience_current / ACU segment_performance, because an
  -- exit can be represented by ABSENCE in the newer snapshot, so a per-(profile,audience) max
  -- would resurrect a profile the latest audience snapshot dropped.
  SELECT m.profile_id, m.audience_id
  FROM ${catalog}.${acu_schema}.segment_membership m
  JOIN (SELECT audience_id, MAX(as_of_date) AS max_as_of
        FROM ${catalog}.${acu_schema}.segment_membership GROUP BY audience_id) mx
    ON m.audience_id = mx.audience_id AND m.as_of_date = mx.max_as_of
  WHERE m.membership_status IS NULL OR m.membership_status <> 'exited'
)
SELECT lm.profile_id, lm.audience_id
FROM latest_membership lm
-- leg (a): person-level do-not-target, every plane.
WHERE NOT EXISTS (
    SELECT 1 FROM ${catalog}.${ucv_schema}.gold_person_do_not_target_current dnt
    WHERE dnt.profile_id = lm.profile_id
  )
-- leg (b): purpose-level do-not-sell / do-not-share opt-out, selling/sharing planes.
  AND NOT EXISTS (
    SELECT 1 FROM ${catalog}.${customer_schema}.consent c
    WHERE c.profile_id = lm.profile_id
      AND c.is_current = TRUE
      AND c.consent_type IN ('data_sale', 'third_party_sharing')
      AND (c.consent_status = 'withdrawn' OR c.suppression_indicator = TRUE)
  );
