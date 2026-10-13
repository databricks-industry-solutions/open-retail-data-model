-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- View: gold_customer_activation_eligibility_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Promote to a materialized view
--   at deploy time if a low-latency activation gate is needed; definition unchanged.
-- Version: 0.5
-- Generated: 2026-07-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- The net-permission gate: "can I contact this customer for purpose X on
-- channel Y?" Grain: one row per customer x purpose x channel (x jurisdiction),
-- specifically per EVALUABLE consent decision — a row exists only where the customer
-- holds a GATE-MAPPED consent record (the four marketing_* types plus profiling / cookies /
-- third_party_sharing / data_sale; ADR 0028). A "never asked" customer (no consent on record)
-- is intentionally ABSENT here (neither eligible nor consent_denied): absence means
-- "no decision to evaluate", and an activation gate must treat unknown consent as
-- NOT eligible (do not infer eligibility from absence).
-- Combines the THREE distinct governed states the briefs insist must not be
-- collapsed (principle #5): consent (legal permission), preference (soft opt-out /
-- channel), and reachability (a valid identifier/contact for the channel).
--
-- Jurisdiction: this view PASSES THROUGH `consent.jurisdiction_code` (the
-- jurisdiction recorded on the consent decision). It does NOT yet resolve a
-- governing jurisdiction from the customer's residency/address — that resolution
-- is a deferred follow-up; treat `jurisdiction_code` as the consent's own scope.
--
-- Cross-view joins: this view's `profile_sk` is passed through from `consent` and
-- is therefore the SCD2 surrogate as-of the consent version — it may not equal the
-- CURRENT profile version's `profile_sk` used by gold_unified_customer_360_current.
-- Join across the two views on the durable `profile_id`, not `profile_sk`.
--
--   eligible_flag = consent_granted AND preference_allows AND has_identifier
--
-- purpose is derived from consent_type (ADR 0028): the four marketing_* types map to
-- purpose=marketing on their owned channel (email/sms/phone/postal); profiling ->
-- personalization, cookies -> analytics, third_party_sharing -> retail_media, data_sale ->
-- data_sale are CHANNEL-AGNOSTIC (channel_code NULL — activated by a match key at the
-- reverse-ETL boundary). third_party_sharing (CCPA do-not-SHARE) and data_sale (CCPA
-- do-not-SELL) are DISTINCT purposes, not folded together: they are separate legal opt-outs,
-- and merging them would collide two rows on the (profile x purpose x NULL-channel x
-- jurisdiction) grain. data_processing and service are not consent-gated. blocking_reason_code names
-- the first failing rule. Suppression is the HIGHEST-priority block: a do-not-contact overlay
-- that OVERRIDES granted consent, so eligible_flag = consent AND preference AND
-- identifier AND NOT suppressed.
--
-- Suppression has TWO scopes (review H1) — because the overlay lives on the per-channel
-- consent row (profile x consent_type x jurisdiction), a naive per-scope read would let a
-- PERSON-level reason recorded on one channel leak an un-suppressed sibling channel:
--   * CHANNEL-level reasons (unsubscribe, hard_bounce, spam_complaint, list_hygiene) block
--     only the scope they sit on — a bounced email must not silence SMS.
--   * PERSON-level reasons (deceased, fraud, do_not_contact, legal_objection) block EVERY
--     channel for the profile — sourced from the shared gold_person_do_not_target_current
--     view (ADR 0028), the single do-not-target consult both this owned gate AND any paid /
--     non-owned activation plane use, so a deceased/global-DNC customer can never resolve
--     eligible on any channel or plane.
-- DEPENDENCY: this gate READS gold_person_do_not_target_current (ADR 0028) for the
-- person-level suppression set (the person_suppressed CTE), so that view must exist and
-- refresh before/with this one.
-- No PII is exposed.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current AS
WITH consent_pc AS (
  SELECT
    profile_sk,
    profile_id,
    -- Purpose is derived from consent_type (ADR 0028). The marketing_* types are
    -- purpose x channel compound (marketing on a specific owned channel); the non-marketing
    -- types are purpose-only and CHANNEL-AGNOSTIC (activated via a match key at the
    -- reverse-ETL boundary, so they carry no owned email/sms/phone/postal channel). This
    -- lets destinations declaring personalization/analytics/retail_media be gate-producible
    -- instead of structurally un-gateable. data_processing (umbrella lawful basis) and
    -- service (transactional; lawful basis contract/legitimate-interest, not consent) are
    -- intentionally NOT consent-gated here — NULL purpose = not consent-constrained.
    CASE consent_type
      WHEN 'marketing_email'     THEN 'marketing'
      WHEN 'marketing_sms'       THEN 'marketing'
      WHEN 'marketing_phone'     THEN 'marketing'
      WHEN 'marketing_postal'    THEN 'marketing'
      WHEN 'profiling'           THEN 'personalization'
      WHEN 'cookies'             THEN 'analytics'
      WHEN 'third_party_sharing' THEN 'retail_media'
      WHEN 'data_sale'           THEN 'data_sale'
    END AS purpose_code,
    CASE consent_type
      WHEN 'marketing_email'  THEN 'email'
      WHEN 'marketing_sms'    THEN 'sms'
      WHEN 'marketing_phone'  THEN 'phone'
      WHEN 'marketing_postal' THEN 'postal'
      -- non-marketing purposes are channel-agnostic: channel_code stays NULL.
    END AS channel_code,
    jurisdiction_code,
    consent_status,
    COALESCE(suppression_indicator, FALSE) AS suppression_indicator
  FROM ${catalog}.${customer_schema}.consent
  WHERE is_current = TRUE
    AND consent_type IN ('marketing_email', 'marketing_sms', 'marketing_phone',
                         'marketing_postal', 'profiling', 'cookies', 'third_party_sharing',
                         'data_sale')
),
person_suppressed AS (
  -- Person-level do-not-target set, single-sourced from the shared do-not-target view
  -- (gold_person_do_not_target_current) so the owned gate and the paid plane can never
  -- diverge (was an inline CTE here; centralized per ADR 0028). Semantics identical: keyed
  -- on profile_id, propagates a person-level reason (deceased/fraud/do_not_contact/
  -- legal_objection) across every channel, purpose, and jurisdiction for the profile.
  SELECT profile_id
  FROM ${catalog}.${ucv_schema}.gold_person_do_not_target_current
),
pref AS (
  -- Channel-level soft opt-out ONLY. topic_subscription / format are SUB-channel
  -- (per-topic / per-format) preferences: an unsubscribe there narrows targeting
  -- but is NOT a channel opt-out (core DDL: a topic is_subscribed=FALSE is a soft
  -- topic opt-out, NOT a channel/consent withdrawal). Excluding them stops a
  -- single-topic unsubscribe from silently dropping the whole channel (review H1);
  -- the legal channel gate is consent, handled above.
  SELECT profile_id, channel,
         MIN(CASE WHEN is_subscribed = FALSE THEN 0 ELSE 1 END) AS pref_allows
  FROM ${catalog}.${customer_schema}.channel_preference
  WHERE is_current = TRUE
    AND preference_type NOT IN ('topic_subscription', 'format')
  GROUP BY profile_id, channel
),
contacts AS (
  SELECT profile_id,
         MAX(CASE WHEN contact_type = 'email' THEN 1 ELSE 0 END) AS has_email,
         MAX(CASE WHEN contact_type IN ('mobile_phone', 'landline_phone') THEN 1 ELSE 0 END) AS has_phone,
         MAX(CASE WHEN contact_type = 'mobile_phone' THEN 1 ELSE 0 END) AS has_mobile  -- SMS needs a mobile, not a landline
  FROM ${catalog}.${customer_schema}.contact
  WHERE contact_status = 'active'
  GROUP BY profile_id
),
addr AS (
  SELECT profile_id, MAX(CASE WHEN address_status = 'active' THEN 1 ELSE 0 END) AS has_address
  FROM ${catalog}.${customer_schema}.address
  WHERE is_current = TRUE
  GROUP BY profile_id
),
evaluated AS (
  SELECT
    c.profile_sk,
    c.profile_id,
    c.purpose_code,
    c.channel_code,
    c.jurisdiction_code,
    -- Fail-CLOSED on unknown consent: any status that is not an explicit 'granted'
    -- (including NULL / pending / expired) resolves to NOT granted, so the row is
    -- blocked (consent_denied), never NULL. A NULL flag would make eligible_flag NULL,
    -- pass ucv_eligibility_flag_consistency vacuously, and drop the row out of BOTH the
    -- eligible and blocked populations (fail-open) — contradicting the "unknown ⇒ not
    -- eligible" banner above (review M2).
    COALESCE(c.consent_status = 'granted', FALSE) AS consent_granted_flag,
    (COALESCE(pf.pref_allows, 1) = 1)    AS preference_allows_flag,
    CASE c.channel_code
      WHEN 'email'  THEN COALESCE(ct.has_email, 0) = 1
      WHEN 'sms'    THEN COALESCE(ct.has_mobile, 0) = 1
      WHEN 'phone'  THEN COALESCE(ct.has_phone, 0) = 1
      WHEN 'postal' THEN COALESCE(ad.has_address, 0) = 1
      ELSE TRUE  -- channel-agnostic purpose (personalization/analytics/retail_media):
                 -- reachability is resolved at the reverse-ETL match-key boundary, not here.
    END                                  AS has_identifier_flag,
    -- Channel-level suppression on THIS scope OR any person-level suppression for the
    -- profile (propagated across every channel) — review H1.
    (c.suppression_indicator OR ps.profile_id IS NOT NULL) AS is_suppressed_flag,
    c.consent_status
  FROM consent_pc c
  LEFT JOIN pref              pf ON c.profile_id = pf.profile_id AND c.channel_code = pf.channel
  LEFT JOIN contacts          ct ON c.profile_id = ct.profile_id
  LEFT JOIN addr              ad ON c.profile_id = ad.profile_id
  LEFT JOIN person_suppressed ps ON c.profile_id = ps.profile_id
  WHERE c.purpose_code IS NOT NULL   -- keep every mapped purpose row; non-marketing rows
                                     -- carry a NULL channel (they are channel-agnostic).
)
SELECT
  profile_sk,
  profile_id,
  purpose_code,
  channel_code,
  jurisdiction_code,
  consent_granted_flag,
  preference_allows_flag,
  has_identifier_flag,
  is_suppressed_flag,
  (consent_granted_flag AND preference_allows_flag AND has_identifier_flag
     AND NOT is_suppressed_flag) AS eligible_flag,
  CASE
    -- Suppression overrides everything: a do-not-contact overlay blocks even granted consent.
    WHEN is_suppressed_flag             THEN 'suppressed'
    WHEN consent_status = 'withdrawn'   THEN 'withdrawn'
    WHEN NOT consent_granted_flag       THEN 'consent_denied'
    WHEN NOT preference_allows_flag     THEN 'preference_opt_out'
    WHEN NOT has_identifier_flag        THEN 'no_identifier'
    ELSE NULL
  END AS blocking_reason_code,
  current_timestamp() AS evaluated_ts
FROM evaluated;
