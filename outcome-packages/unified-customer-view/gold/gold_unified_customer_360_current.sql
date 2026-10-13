-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- View: gold_unified_customer_360_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). A deployment may promote it to
--   CREATE OR REFRESH MATERIALIZED VIEW for serving latency; the definition is
--   unchanged. Kept as a plain view here so the model stays portable.
-- Version: 0.5
-- Generated: 2026-07-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-10
-- ============================================================
-- One current row per resolved customer: a conformed 360 summary built ONLY
-- from the thin customer core (profile, identity_link, consent,
-- channel_preference, contact, address, household). Keyed on the customer
-- SURROGATE; no raw PII (names / dob / loyalty / household ids / contact
-- values) is exposed -- those stay in the governed dimension.
--
-- Scope: identity, consent, preference, and household roll-ups only. Fields
-- needing transaction / product / store data (LTV, purchase recency, affinity,
-- preferred store) and segment/audience membership are OUT OF SCOPE (deferred).
--
-- Consent note: the flags here are a customer-level SUMMARY ("granted anywhere").
-- The authoritative per-purpose x channel gate that resolves consent as-of
-- jurisdiction is gold_customer_activation_eligibility_current.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ucv_schema}.gold_unified_customer_360_current AS
WITH cur_profile AS (
  SELECT profile_sk, profile_id, household_id, customer_status,
         first_name, last_name, date_of_birth
  FROM ${catalog}.${customer_schema}.profile
  WHERE is_current = TRUE
),
hh_size AS (
  SELECT household_id, CAST(COUNT(*) AS INT) AS household_size
  FROM ${catalog}.${customer_schema}.profile
  WHERE is_current = TRUE AND household_id IS NOT NULL
  GROUP BY household_id
),
ident AS (
  SELECT profile_id,
         COUNT(*) AS active_identifier_count,
         MAX(match_confidence) AS resolved_identity_confidence
  FROM ${catalog}.${customer_schema}.identity_link
  WHERE is_current = TRUE AND link_status = 'active'
  GROUP BY profile_id
),
contacts AS (
  SELECT profile_id,
         MAX(CASE WHEN contact_type = 'email' THEN 1 ELSE 0 END) AS has_email,
         MAX(CASE WHEN contact_type IN ('mobile_phone', 'landline_phone') THEN 1 ELSE 0 END) AS has_phone,
         MAX(CASE WHEN contact_type = 'mobile_phone' THEN 1 ELSE 0 END) AS has_mobile  -- SMS needs a mobile
  FROM ${catalog}.${customer_schema}.contact
  WHERE contact_status = 'active'
  GROUP BY profile_id
),
addr AS (
  SELECT profile_id,
         MAX(CASE WHEN address_status = 'active' THEN 1 ELSE 0 END) AS has_address,
         MAX(CASE WHEN is_primary = TRUE AND address_status = 'active' THEN country_code END) AS primary_country_code
  FROM ${catalog}.${customer_schema}.address
  WHERE is_current = TRUE
  GROUP BY profile_id
),
cons AS (
  SELECT profile_id,
         MAX(CASE WHEN consent_type LIKE 'marketing%' AND consent_status = 'granted' THEN 1 ELSE 0 END) AS marketing_granted,
         MAX(CASE WHEN consent_type = 'marketing_email' AND consent_status = 'granted' THEN 1 ELSE 0 END) AS email_consent,
         MAX(CASE WHEN consent_type = 'marketing_sms' AND consent_status = 'granted' THEN 1 ELSE 0 END) AS sms_consent,
         MAX(CASE WHEN consent_type = 'profiling' AND consent_status = 'granted' THEN 1 ELSE 0 END) AS profiling_granted,
         MAX(CASE WHEN consent_type = 'third_party_sharing' AND consent_status = 'granted' THEN 1 ELSE 0 END) AS third_party_granted,
         COUNT(DISTINCT CASE WHEN consent_status = 'granted' THEN consent_type END) AS consented_type_count
  FROM ${catalog}.${customer_schema}.consent
  WHERE is_current = TRUE
  GROUP BY profile_id
),
pref AS (
  -- Channel opt-out is a CHANNEL-level soft signal only; topic_subscription /
  -- format are sub-channel (a topic/format unsubscribe narrows targeting, it does
  -- NOT drop the channel — core DDL). Scoping the opt-out to non-sub-channel
  -- preferences stops a single-topic unsubscribe from clearing contactability
  -- (review H1). The `preferred_channel` positive choice is read as-is.
  SELECT profile_id,
         MAX(CASE WHEN preference_type = 'preferred_channel' AND is_subscribed = TRUE THEN channel END) AS preferred_channel_code,
         MAX(CASE WHEN channel = 'email' AND is_subscribed = FALSE
                   AND preference_type NOT IN ('topic_subscription', 'format') THEN 1 ELSE 0 END) AS email_opt_out,
         MAX(CASE WHEN channel = 'sms' AND is_subscribed = FALSE
                   AND preference_type NOT IN ('topic_subscription', 'format') THEN 1 ELSE 0 END) AS sms_opt_out
  FROM ${catalog}.${customer_schema}.channel_preference
  WHERE is_current = TRUE
  GROUP BY profile_id
)
SELECT
  p.profile_sk,
  p.profile_id,
  hs.household_size,
  COALESCE(id.active_identifier_count, 0) AS active_identifier_count,
  id.resolved_identity_confidence,
  (COALESCE(c.has_email, 0) = 1)   AS has_email_flag,
  (COALESCE(c.has_phone, 0) = 1)   AS has_phone_flag,
  (COALESCE(a.has_address, 0) = 1) AS has_mailable_address_flag,
  a.primary_country_code           AS jurisdiction_primary_code,
  (COALESCE(cn.marketing_granted, 0) = 1)   AS consent_marketing_flag,
  (COALESCE(cn.profiling_granted, 0) = 1)   AS consent_personalization_flag,
  (COALESCE(cn.third_party_granted, 0) = 1) AS consent_third_party_sharing_flag,
  COALESCE(cn.consented_type_count, 0)      AS consented_purpose_count,
  (COALESCE(c.has_email, 0) = 1 AND COALESCE(cn.email_consent, 0) = 1 AND COALESCE(pr.email_opt_out, 0) = 0) AS email_contactable_flag,
  (COALESCE(c.has_mobile, 0) = 1 AND COALESCE(cn.sms_consent, 0) = 1 AND COALESCE(pr.sms_opt_out, 0) = 0)     AS sms_contactable_flag,
  (COALESCE(cn.marketing_granted, 0) = 1 AND p.customer_status = 'active') AS marketing_eligible_flag,
  pr.preferred_channel_code,
  p.customer_status AS customer_status_code,
  ROUND((
      (CASE WHEN p.first_name IS NOT NULL THEN 1 ELSE 0 END)
    + (CASE WHEN p.last_name IS NOT NULL THEN 1 ELSE 0 END)
    + (CASE WHEN p.date_of_birth IS NOT NULL THEN 1 ELSE 0 END)
    + COALESCE(c.has_email, 0)
    + COALESCE(a.has_address, 0)
  ) / 5.0, 4) AS profile_completeness_score,
  ROUND((
      (CASE WHEN COALESCE(c.has_email, 0) = 1 AND COALESCE(cn.email_consent, 0) = 1 AND COALESCE(pr.email_opt_out, 0) = 0 THEN 1 ELSE 0 END)
    + (CASE WHEN COALESCE(c.has_mobile, 0) = 1 AND COALESCE(cn.sms_consent, 0) = 1 AND COALESCE(pr.sms_opt_out, 0) = 0 THEN 1 ELSE 0 END)
    + COALESCE(a.has_address, 0)
  ) / 3.0, 4) AS reachability_score,
  current_timestamp() AS fresh_as_of_ts
FROM cur_profile p
LEFT JOIN hh_size  hs ON p.household_id = hs.household_id
LEFT JOIN ident    id ON p.profile_id = id.profile_id
LEFT JOIN contacts c  ON p.profile_id = c.profile_id
LEFT JOIN addr     a  ON p.profile_id = a.profile_id
LEFT JOIN cons     cn ON p.profile_id = cn.profile_id
LEFT JOIN pref     pr ON p.profile_id = pr.profile_id;
