-- ============================================================
-- ORDM · Canonical Core · Customer domain
-- File: checks.sql  (data-quality assertions)
-- Version: 0.5
-- Generated: 2026-06-09
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-09
-- ============================================================
-- Each assertion SELECTs the VIOLATING rows. 0 rows returned = PASS.
-- Run by runtime/data-quality/run_checks.py, which substitutes ${catalog} and
-- ${customer_schema} (= the domain name) and fails the run if any error-severity
-- check returns rows. Format per check:
--   -- check: <name> | severity: error|warn
--   -- <one-line description>
--   <SELECT ...>;   (ends with a semicolon)
-- ============================================================

-- ---------- profile ----------

-- check: profile_keys_not_null | severity: error
-- Surrogate key, business key, SCD2 start date and current flag are mandatory.
SELECT * FROM ${catalog}.${customer_schema}.profile
WHERE profile_sk IS NULL OR profile_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: profile_business_key_unique_current | severity: error
-- A business key must resolve to at most one current version.
SELECT profile_id, COUNT(*) AS current_versions
FROM ${catalog}.${customer_schema}.profile
WHERE is_current = true
GROUP BY profile_id
HAVING COUNT(*) > 1;

-- check: profile_customer_status_domain | severity: error
-- customer_status must be within the declared enum.
SELECT * FROM ${catalog}.${customer_schema}.profile
WHERE customer_status IS NOT NULL
  AND customer_status NOT IN ('prospect', 'active', 'inactive', 'closed');

-- check: profile_scd2_current_open | severity: error
-- The current version must have an open (NULL) end date; non-current must be closed.
SELECT * FROM ${catalog}.${customer_schema}.profile
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: profile_scd2_date_order | severity: error
-- When set, the end date must be strictly after the start date.
SELECT * FROM ${catalog}.${customer_schema}.profile
WHERE effective_to_date IS NOT NULL
  AND effective_to_date <= effective_from_date;

-- check: profile_household_fk_orphan | severity: error
-- When set, the household surrogate FK must reference an existing household.
SELECT p.* FROM ${catalog}.${customer_schema}.profile p
LEFT JOIN ${catalog}.${customer_schema}.household h ON p.household_sk = h.household_sk
WHERE p.household_sk IS NOT NULL AND h.household_sk IS NULL;

-- check: profile_household_businesskey_orphan | severity: warn
-- When set, the durable household business key should exist on household.
-- WARN (not error) by design — asymmetric with the identity_link / channel_preference
-- business-key-orphan checks, which are error: those are children whose parent
-- (profile) is a hard prerequisite, so a missing parent is a real integrity fault.
-- Here profile is the parent and household is an optional, independently-loaded
-- dimension that may lag profile ingestion; a not-yet-loaded household is expected
-- transient state, not a defect.
SELECT p.* FROM ${catalog}.${customer_schema}.profile p
LEFT JOIN (SELECT DISTINCT household_id FROM ${catalog}.${customer_schema}.household) h
  ON p.household_id = h.household_id
WHERE p.household_id IS NOT NULL AND h.household_id IS NULL;

-- ---------- address ----------

-- check: address_keys_not_null | severity: error
SELECT * FROM ${catalog}.${customer_schema}.address
WHERE address_sk IS NULL OR address_id IS NULL OR profile_id IS NULL
   OR is_current IS NULL;

-- check: address_profile_fk_orphan | severity: error
-- Every address must reference an existing profile (by surrogate FK).
SELECT a.* FROM ${catalog}.${customer_schema}.address a
LEFT JOIN ${catalog}.${customer_schema}.profile p ON a.profile_sk = p.profile_sk
WHERE a.profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: address_profile_businesskey_orphan | severity: error
-- The durable owner business key must also exist on profile.
SELECT a.* FROM ${catalog}.${customer_schema}.address a
LEFT JOIN (SELECT DISTINCT profile_id FROM ${catalog}.${customer_schema}.profile) p
  ON a.profile_id = p.profile_id
WHERE p.profile_id IS NULL;

-- check: address_type_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.address
WHERE address_type IS NOT NULL
  AND address_type NOT IN ('billing', 'shipping', 'home', 'work', 'other');

-- check: address_country_code_iso | severity: warn
-- ISO 3166-1 alpha-2 is two characters.
SELECT * FROM ${catalog}.${customer_schema}.address
WHERE country_code IS NOT NULL AND LENGTH(country_code) <> 2;

-- ---------- contact ----------

-- check: contact_keys_not_null | severity: error
SELECT * FROM ${catalog}.${customer_schema}.contact
WHERE contact_sk IS NULL OR contact_id IS NULL OR profile_id IS NULL
   OR contact_type IS NULL OR contact_value IS NULL;

-- check: contact_profile_businesskey_orphan | severity: error
SELECT c.* FROM ${catalog}.${customer_schema}.contact c
LEFT JOIN (SELECT DISTINCT profile_id FROM ${catalog}.${customer_schema}.profile) p
  ON c.profile_id = p.profile_id
WHERE p.profile_id IS NULL;

-- check: contact_type_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.contact
WHERE contact_type NOT IN ('email', 'mobile_phone', 'landline_phone', 'fax');

-- check: contact_email_shape | severity: warn
-- Email contact points should look like an email address.
SELECT * FROM ${catalog}.${customer_schema}.contact
WHERE contact_type = 'email' AND contact_value NOT LIKE '%@%.%';

-- ---------- consent ----------

-- check: consent_keys_not_null | severity: error
SELECT * FROM ${catalog}.${customer_schema}.consent
WHERE consent_sk IS NULL OR consent_id IS NULL OR profile_id IS NULL
   OR consent_type IS NULL OR consent_status IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: consent_profile_businesskey_orphan | severity: error
SELECT c.* FROM ${catalog}.${customer_schema}.consent c
LEFT JOIN (SELECT DISTINCT profile_id FROM ${catalog}.${customer_schema}.profile) p
  ON c.profile_id = p.profile_id
WHERE p.profile_id IS NULL;

-- check: consent_type_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.consent
WHERE consent_type NOT IN ('marketing_email', 'marketing_sms', 'marketing_phone',
  'marketing_postal', 'data_processing', 'third_party_sharing', 'data_sale', 'profiling', 'cookies');

-- check: consent_status_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.consent
WHERE consent_status NOT IN ('granted', 'withdrawn', 'pending', 'expired');

-- check: consent_single_current_per_type | severity: error
-- Single source of truth: at most one current consent per (profile, type, jurisdiction).
-- jurisdiction_code is nullable (global/unspecified); COALESCE so NULLs group together.
SELECT profile_id, consent_type, COALESCE(jurisdiction_code, '') AS jurisdiction_code, COUNT(*) AS current_rows
FROM ${catalog}.${customer_schema}.consent
WHERE is_current = true
GROUP BY profile_id, consent_type, COALESCE(jurisdiction_code, '')
HAVING COUNT(*) > 1;

-- check: consent_scd2_current_open | severity: error
-- The current version must have an open (NULL) end date; non-current must be closed.
-- (Consent is an SCD2 date-grained master like profile/household/channel_preference; the
-- activation gate now depends on consent SCD2 integrity, so it carries the same guards.)
SELECT * FROM ${catalog}.${customer_schema}.consent
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: consent_scd2_date_order | severity: error
-- When set, the end date must be strictly after the start date.
SELECT * FROM ${catalog}.${customer_schema}.consent
WHERE effective_to_date IS NOT NULL
  AND effective_to_date <= effective_from_date;

-- check: consent_suppression_reason_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.consent
WHERE suppression_reason_code IS NOT NULL
  AND suppression_reason_code NOT IN ('unsubscribe', 'hard_bounce', 'spam_complaint',
    'legal_objection', 'deceased', 'fraud', 'do_not_contact', 'list_hygiene');

-- check: consent_suppression_consistency | severity: error
-- A suppression reason is meaningful only when the scope is actually suppressed. This guard
-- is ONE-DIRECTIONAL BY DESIGN (reason ⇒ indicator, not the reverse): an indicator=TRUE with
-- a NULL reason is a valid CHANNEL-scope-only suppression that blocks its own scope but will
-- NOT propagate person-wide — person-level propagation in the activation gate keys on the
-- reason (deceased/fraud/do_not_contact/legal_objection), so an uncategorized suppression
-- deliberately stays channel-local.
SELECT * FROM ${catalog}.${customer_schema}.consent
WHERE suppression_reason_code IS NOT NULL AND COALESCE(suppression_indicator, FALSE) = FALSE;

-- check: consent_suppressed_rate | severity: metric
-- Share of current consent scopes carrying an active suppression overlay.
SELECT ROUND(AVG(CASE WHEN COALESCE(suppression_indicator, FALSE) THEN 1.0 ELSE 0 END), 4) AS suppressed_rate
FROM ${catalog}.${customer_schema}.consent
WHERE is_current = true;

-- ---------- account ----------

-- check: account_keys_not_null | severity: error
SELECT * FROM ${catalog}.${customer_schema}.account
WHERE account_sk IS NULL OR account_id IS NULL OR is_current IS NULL;

-- check: account_type_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.account
WHERE account_type IS NOT NULL
  AND account_type NOT IN ('business', 'government', 'education', 'nonprofit', 'reseller');

-- check: account_credit_limit_nonnegative | severity: error
SELECT * FROM ${catalog}.${customer_schema}.account
WHERE credit_limit_amount IS NOT NULL AND credit_limit_amount < 0;

-- check: account_primary_contact_fk_orphan | severity: error
-- The declared FK is on the surrogate: every non-null primary-contact surrogate must reference an existing profile.
SELECT a.* FROM ${catalog}.${customer_schema}.account a
LEFT JOIN ${catalog}.${customer_schema}.profile p ON a.primary_contact_profile_sk = p.profile_sk
WHERE a.primary_contact_profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: account_primary_contact_orphan | severity: error
-- A named primary contact must exist as a profile.
SELECT a.* FROM ${catalog}.${customer_schema}.account a
LEFT JOIN (SELECT DISTINCT profile_id FROM ${catalog}.${customer_schema}.profile) p
  ON a.primary_contact_profile_id = p.profile_id
WHERE a.primary_contact_profile_id IS NOT NULL AND p.profile_id IS NULL;

-- check: account_no_self_parent | severity: error
-- An account cannot be its own parent.
SELECT * FROM ${catalog}.${customer_schema}.account
WHERE parent_account_id IS NOT NULL AND parent_account_id = account_id;

-- ---------- household ----------

-- check: household_keys_not_null | severity: error
SELECT * FROM ${catalog}.${customer_schema}.household
WHERE household_sk IS NULL OR household_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: household_business_key_unique_current | severity: error
-- A business key must resolve to at most one current version.
SELECT household_id, COUNT(*) AS current_versions
FROM ${catalog}.${customer_schema}.household
WHERE is_current = true
GROUP BY household_id
HAVING COUNT(*) > 1;

-- check: household_type_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.household
WHERE household_type IS NOT NULL
  AND household_type NOT IN ('family', 'single', 'shared', 'business', 'other');

-- check: household_status_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.household
WHERE household_status IS NOT NULL
  AND household_status NOT IN ('active', 'inactive');

-- check: household_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${customer_schema}.household
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: household_scd2_date_order | severity: error
SELECT * FROM ${catalog}.${customer_schema}.household
WHERE effective_to_date IS NOT NULL
  AND effective_to_date <= effective_from_date;

-- ---------- identity_link ----------

-- check: identity_link_keys_not_null | severity: error
SELECT * FROM ${catalog}.${customer_schema}.identity_link
WHERE identity_link_sk IS NULL OR identity_link_id IS NULL OR profile_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: identity_link_business_key_unique_current | severity: error
SELECT identity_link_id, COUNT(*) AS current_versions
FROM ${catalog}.${customer_schema}.identity_link
WHERE is_current = true
GROUP BY identity_link_id
HAVING COUNT(*) > 1;

-- check: identity_link_profile_fk_orphan | severity: error
-- Every link must resolve to an existing profile (by surrogate FK).
SELECT il.* FROM ${catalog}.${customer_schema}.identity_link il
LEFT JOIN ${catalog}.${customer_schema}.profile p ON il.profile_sk = p.profile_sk
WHERE il.profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: identity_link_profile_businesskey_orphan | severity: error
-- The durable resolved-customer business key must also exist on profile.
SELECT il.* FROM ${catalog}.${customer_schema}.identity_link il
LEFT JOIN (SELECT DISTINCT profile_id FROM ${catalog}.${customer_schema}.profile) p
  ON il.profile_id = p.profile_id
WHERE p.profile_id IS NULL;

-- check: identity_link_identifier_type_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.identity_link
WHERE identifier_type IS NOT NULL
  AND identifier_type NOT IN ('email_hash', 'phone_hash', 'device_id', 'cookie_id',
    'maid', 'loyalty_id', 'login_id', 'customer_id');

-- check: identity_link_match_method_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.identity_link
WHERE match_method IS NOT NULL
  AND match_method NOT IN ('deterministic', 'probabilistic', 'declared', 'manual');

-- check: identity_link_status_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.identity_link
WHERE link_status IS NOT NULL
  AND link_status NOT IN ('active', 'superseded', 'suppressed');

-- check: identity_link_single_active_profile_per_identifier | severity: error
-- Resolution guarantee: a current, active identifier must resolve to ONE profile.
-- superseded/suppressed links are excluded (they exist precisely to hold the losers).
SELECT identifier_type, identifier_value_hash, COUNT(DISTINCT profile_id) AS profiles
FROM ${catalog}.${customer_schema}.identity_link
WHERE is_current = true AND link_status = 'active'
  AND identifier_value_hash IS NOT NULL
GROUP BY identifier_type, identifier_value_hash
HAVING COUNT(DISTINCT profile_id) > 1;

-- check: identity_link_confidence_range | severity: error
-- Match confidence is a probability in [0,1].
SELECT * FROM ${catalog}.${customer_schema}.identity_link
WHERE match_confidence IS NOT NULL
  AND (match_confidence < 0 OR match_confidence > 1);

-- check: identity_link_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${customer_schema}.identity_link
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: identity_link_scd2_date_order | severity: error
SELECT * FROM ${catalog}.${customer_schema}.identity_link
WHERE effective_to_date IS NOT NULL
  AND effective_to_date <= effective_from_date;

-- ---------- channel_preference ----------

-- check: channel_preference_keys_not_null | severity: error
SELECT * FROM ${catalog}.${customer_schema}.channel_preference
WHERE channel_preference_sk IS NULL OR channel_preference_id IS NULL OR profile_id IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: channel_preference_business_key_unique_current | severity: error
SELECT channel_preference_id, COUNT(*) AS current_versions
FROM ${catalog}.${customer_schema}.channel_preference
WHERE is_current = true
GROUP BY channel_preference_id
HAVING COUNT(*) > 1;

-- check: channel_preference_profile_fk_orphan | severity: error
SELECT cp.* FROM ${catalog}.${customer_schema}.channel_preference cp
LEFT JOIN ${catalog}.${customer_schema}.profile p ON cp.profile_sk = p.profile_sk
WHERE cp.profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: channel_preference_profile_businesskey_orphan | severity: error
SELECT cp.* FROM ${catalog}.${customer_schema}.channel_preference cp
LEFT JOIN (SELECT DISTINCT profile_id FROM ${catalog}.${customer_schema}.profile) p
  ON cp.profile_id = p.profile_id
WHERE p.profile_id IS NULL;

-- check: channel_preference_channel_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.channel_preference
WHERE channel IS NOT NULL
  AND channel NOT IN ('email', 'sms', 'phone', 'postal', 'push', 'in_app', 'web');

-- check: channel_preference_type_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.channel_preference
WHERE preference_type IS NOT NULL
  AND preference_type NOT IN ('contact_frequency', 'topic_subscription', 'format', 'preferred_channel');

-- check: channel_preference_frequency_period_domain | severity: error
SELECT * FROM ${catalog}.${customer_schema}.channel_preference
WHERE frequency_period IS NOT NULL
  AND frequency_period NOT IN ('day', 'week', 'month');

-- check: channel_preference_scd2_current_open | severity: error
SELECT * FROM ${catalog}.${customer_schema}.channel_preference
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: channel_preference_scd2_date_order | severity: error
SELECT * FROM ${catalog}.${customer_schema}.channel_preference
WHERE effective_to_date IS NOT NULL
  AND effective_to_date <= effective_from_date;

-- check: channel_preference_single_current_singlevalue | severity: error
-- Per-channel single-valued types hold ONE current row per (profile, channel,
-- preference_type): a customer has one frequency cap and one format per channel.
-- preference_value is NOT a discriminator here. (topic_subscription is multi-valued
-- and preferred_channel is a cross-channel choice — see the next two checks.)
SELECT profile_id, channel, preference_type, COUNT(*) AS current_rows
FROM ${catalog}.${customer_schema}.channel_preference
WHERE is_current = true
  AND preference_type IN ('contact_frequency', 'format')
GROUP BY profile_id, channel, preference_type
HAVING COUNT(*) > 1;

-- check: channel_preference_single_preferred_channel | severity: error
-- preferred_channel names the ONE channel a customer prefers — a choice ACROSS
-- channels, so at most one current row per profile (the grain ignores `channel`,
-- which here holds the chosen channel, not a scope). Prevents "prefers two
-- channels at once."
SELECT profile_id, COUNT(*) AS current_rows
FROM ${catalog}.${customer_schema}.channel_preference
WHERE is_current = true AND preference_type = 'preferred_channel'
GROUP BY profile_id
HAVING COUNT(*) > 1;

-- check: channel_preference_single_current_topic | severity: error
-- topic_subscription is multi-valued: multiple concurrent topics per channel are
-- valid (grain includes preference_value), but the SAME topic must not be current
-- twice. COALESCE so NULL topics group together.
SELECT profile_id, channel, COALESCE(preference_value, '') AS preference_value, COUNT(*) AS current_rows
FROM ${catalog}.${customer_schema}.channel_preference
WHERE is_current = true
  AND preference_type = 'topic_subscription'
GROUP BY profile_id, channel, COALESCE(preference_value, '')
HAVING COUNT(*) > 1;

-- check: channel_preference_frequency_cap_nonnegative | severity: error
-- A frequency cap, when expressed, cannot be negative.
SELECT * FROM ${catalog}.${customer_schema}.channel_preference
WHERE frequency_cap_per_period IS NOT NULL AND frequency_cap_per_period < 0;
