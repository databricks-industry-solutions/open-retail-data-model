-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- View: gold_activatable_audience_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Promote to a materialized view at
--   deploy time if a low-latency activation surface is needed; definition unchanged.
-- Version: 0.5
-- Generated: 2026-07-23
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- THE ACTIVATION SURFACE: "which customers in segment X may I actually contact for
-- purpose P on channel C?" — the reverse-ETL-ready join a warehouse-native / composable
-- CDP activation platform reads to sync an addressable audience.
--
-- This is the ONE place the THREE governed planes combine (they are kept strictly
-- separate everywhere else, per principle #5 and the behavioral-segmentation design):
--   * TARGETING  — behavioral-segment membership (ACU segment_membership, current as_of).
--   * CONSENT + PREFERENCE + REACHABILITY — the net activation gate
--     (gold_customer_activation_eligibility_current: consent AND preference AND identifier).
-- A customer is activatable for a segment only where an eligible gate row exists, so a
-- segment can NEVER override consent (fail-closed: absence of an eligible gate row = not
-- activatable).
--
-- Grain: one row per (audience_id × profile_id × purpose × channel × jurisdiction). The
-- jurisdiction is part of the grain because the eligibility gate it reads is itself grained
-- by jurisdiction (consent is recorded per jurisdiction — a customer can be eligible under
-- one law and blocked under another for the same purpose×channel). Omitting it would fan out
-- to duplicate (audience, profile, purpose, channel) rows on real multi-jurisdiction data and
-- trip uav_grain_unique — invisible in synthetic data only because the generator assigns one
-- jurisdiction per profile. Joined on the DURABLE profile_id (never profile_sk — the gate's
-- profile_sk is the as-of-consent SCD2 surrogate and may differ from the current profile
-- version; the gate header mandates joining on profile_id). Segment membership is taken at
-- its latest as_of_date.
-- No PII is exposed — pseudonymous profile_id only; identifier resolution happens at the
-- reverse-ETL boundary, not here.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ucv_schema}.gold_activatable_audience_current AS
WITH latest_membership AS (
  -- current membership snapshot per segment: the most recent as_of_date, excluding
  -- rows that have exited the segment.
  -- NOTE (m1): the same latest-minus-exited logic is duplicated at four OTHER sites —
  -- ACU metric-views/segment_performance.sql `latest`, ACU sample-queries.sql (#3 and #6),
  -- and UCV sample-queries.sql #11 (the paid/reverse-ETL onboarding reference) — five in all
  -- counting this one. Keep all in sync; if the membership-currency rule changes, update every
  -- site (no shared-SQL include).
  SELECT m.profile_id, m.audience_id, m.membership_status, m.membership_score
  FROM ${catalog}.${acu_schema}.segment_membership m
  JOIN (
    SELECT audience_id, MAX(as_of_date) AS max_as_of
    FROM ${catalog}.${acu_schema}.segment_membership
    GROUP BY audience_id
  ) mx ON m.audience_id = mx.audience_id AND m.as_of_date = mx.max_as_of
  WHERE m.membership_status IS NULL OR m.membership_status <> 'exited'
)
SELECT
  lm.audience_id,
  a.audience_name,
  lm.profile_id,
  g.purpose_code,
  g.channel_code,
  g.jurisdiction_code,
  lm.membership_status,
  lm.membership_score,
  g.eligible_flag,
  -- Always NULL on this surface by construction: the WHERE filters to eligible_flag
  -- = TRUE, and an eligible eligibility row carries no blocking reason (enforced by
  -- ucv_eligibility_flag_consistency). Kept for schema symmetry with the gate; read
  -- the eligibility table directly if you need blocking reasons for ineligible rows.
  g.blocking_reason_code
FROM latest_membership lm
-- M1: also gate on the DEFINITION-level addressability switch. is_addressable_flag = FALSE
-- marks a segment as analytics/measurement/suppression-only (not for delivery); such a
-- segment must never surface members here even if the per-customer consent gate passes.
-- Fail-closed on the definition as well as the per-customer gate.
JOIN ${catalog}.${marketing_schema}.audience a
  ON a.audience_id = lm.audience_id AND a.is_current = TRUE AND a.is_addressable_flag = TRUE
JOIN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current g
  ON g.profile_id = lm.profile_id
WHERE g.eligible_flag = TRUE
  -- Explicit person-level do-not-target guard (ADR 0028): redundant on the owned path (the
  -- gate already blocks person-suppressed profiles via eligible_flag) but makes this surface
  -- PERSON-LEVEL-DNT-safe on any plane a consumer reverse-ETLs it to, enforcing the cross-plane
  -- do-not-contact contract independently of the gate's purpose/channel coverage. NOTE this is
  -- only the person-level leg: a SELLING/SHARING plane must ALSO apply the purpose-level
  -- do-not-sell/do-not-share opt-out (leg b) - this surface's rows are an opt-IN/fail-closed
  -- SUBSET (safe direction), but do not read DNT-guarded as opt-out-complete. See the
  -- segment_membership activation contract + UCV sample-queries.sql #11.
  AND NOT EXISTS (
    SELECT 1 FROM ${catalog}.${ucv_schema}.gold_person_do_not_target_current dnt
    WHERE dnt.profile_id = lm.profile_id
  );
