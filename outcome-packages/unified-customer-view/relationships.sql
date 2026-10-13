-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- File: relationships.sql
-- Version: 0.5
-- Generated: 2026-07-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-10
-- ============================================================
-- Informational (NOT ENFORCED) foreign keys from the package extension table
-- to the canonical-core customer domain, plus enum CHECK constraints. Run AFTER
-- the canonical-core customer tables exist. FKs are declared on the surrogate
-- (_sk), the parent's primary key.
-- ============================================================

-- customer_profile_snapshot -> profile (canonical core)
ALTER TABLE ${catalog}.${ucv_schema}.customer_profile_snapshot
  ADD CONSTRAINT fk_cps_profile
  FOREIGN KEY (profile_sk) REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);

-- ------------------------------------------------------------
-- Logical relationship on the durable business key (NOT a UC FK):
--   customer_profile_snapshot.profile_id -> profile.profile_id (is_current = TRUE)
-- ------------------------------------------------------------

-- ============================================================
-- Enum / state-domain CHECK constraints (always-on enforcement).
-- Lists match the "Allowed values" in each column comment.
-- ============================================================
ALTER TABLE ${catalog}.${ucv_schema}.customer_profile_snapshot
  ADD CONSTRAINT chk_cps_snapshot_reason
  CHECK (snapshot_reason_code IS NULL OR snapshot_reason_code IN ('scheduled', 'pre_campaign', 'ad_hoc', 'audit'));

ALTER TABLE ${catalog}.${ucv_schema}.customer_profile_snapshot
  ADD CONSTRAINT chk_cps_status
  CHECK (customer_status_code IS NULL OR customer_status_code IN ('prospect', 'active', 'inactive', 'closed'));

-- ============================================================
-- CDP activation layer (ADR 0026): activation_destination, activation_job,
-- campaign_touch. Informational (NOT ENFORCED) FKs on the surrogate (_sk) to the
-- parent's primary key, plus enum CHECK constraints (NO-INLINE-CHECK: enums live
-- here, never inline in the CREATE). activation_destination is a root reference
-- catalog (no outbound FK).
-- ============================================================

-- ---------- activation_job -> marketing.audience (silver) + activation_destination (gold, same package) ----------
ALTER TABLE ${catalog}.${ucv_schema}.activation_job
  ADD CONSTRAINT fk_activation_job_audience
  FOREIGN KEY (audience_sk) REFERENCES ${catalog}.${marketing_schema}.audience (audience_sk);

ALTER TABLE ${catalog}.${ucv_schema}.activation_job
  ADD CONSTRAINT fk_activation_job_destination
  FOREIGN KEY (activation_destination_sk) REFERENCES ${catalog}.${ucv_schema}.activation_destination (activation_destination_sk);

-- ---------- campaign_touch -> profile (core) + audience/promotion (silver) + activation_job (gold, same package) ----------
ALTER TABLE ${catalog}.${ucv_schema}.campaign_touch
  ADD CONSTRAINT fk_campaign_touch_profile
  FOREIGN KEY (profile_sk) REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);

ALTER TABLE ${catalog}.${ucv_schema}.campaign_touch
  ADD CONSTRAINT fk_campaign_touch_audience
  FOREIGN KEY (audience_sk) REFERENCES ${catalog}.${marketing_schema}.audience (audience_sk);

ALTER TABLE ${catalog}.${ucv_schema}.campaign_touch
  ADD CONSTRAINT fk_campaign_touch_promotion
  FOREIGN KEY (promo_sk) REFERENCES ${catalog}.${marketing_schema}.promotion (promo_sk);

ALTER TABLE ${catalog}.${ucv_schema}.campaign_touch
  ADD CONSTRAINT fk_campaign_touch_activation_job
  FOREIGN KEY (activation_job_sk) REFERENCES ${catalog}.${ucv_schema}.activation_job (activation_job_sk);

-- ------------------------------------------------------------
-- Logical relationships on durable business keys (NOT UC FKs):
--   activation_job.audience_id            -> marketing.audience.audience_id (is_current = TRUE)
--   activation_job.activation_destination_id -> activation_destination.activation_destination_id (is_current = TRUE)
--   campaign_touch.profile_id             -> profile.profile_id (is_current = TRUE)
--   campaign_touch.audience_id            -> marketing.audience.audience_id (is_current = TRUE)
--   campaign_touch.promo_id           -> marketing.promotion.promo_id (is_current = TRUE)
--   campaign_touch.activation_job_id      -> activation_job.activation_job_id
-- ------------------------------------------------------------

-- ---------- activation_destination enums ----------
-- NOTE: destination_platform is intentionally NOT enum-constrained — it is free,
-- adopter-defined text (vendor-neutral schema; vendor names live only as comment
-- examples, matching the CMN media_platform precedent). No chk_ad_platform.
ALTER TABLE ${catalog}.${ucv_schema}.activation_destination
  ADD CONSTRAINT chk_ad_connector_kind
  CHECK (connector_kind IS NULL OR connector_kind IN ('reverse_etl', 'api_push', 'file_export', 'clean_room_match', 'managed_connector'));

ALTER TABLE ${catalog}.${ucv_schema}.activation_destination
  ADD CONSTRAINT chk_ad_match_key_type
  CHECK (match_key_type IS NULL OR match_key_type IN ('email_hash', 'phone_hash', 'maid', 'people_based_id', 'platform_user_id', 'custom_audience_id', 'first_party_id'));

ALTER TABLE ${catalog}.${ucv_schema}.activation_destination
  ADD CONSTRAINT chk_ad_required_purpose
  CHECK (required_consent_purpose IS NULL OR required_consent_purpose IN ('marketing', 'personalization', 'analytics', 'retail_media', 'data_sale', 'service'));

ALTER TABLE ${catalog}.${ucv_schema}.activation_destination
  ADD CONSTRAINT chk_ad_required_channel
  CHECK (required_channel IS NULL OR required_channel IN ('email', 'sms', 'phone', 'postal', 'push', 'web', 'in_app', 'ctv', 'social', 'display', 'search'));

-- ---------- activation_job enums ----------
ALTER TABLE ${catalog}.${ucv_schema}.activation_job
  ADD CONSTRAINT chk_aj_status
  CHECK (job_status IN ('queued', 'running', 'succeeded', 'partial', 'failed', 'cancelled'));

ALTER TABLE ${catalog}.${ucv_schema}.activation_job
  ADD CONSTRAINT chk_aj_purpose
  CHECK (purpose_code IS NULL OR purpose_code IN ('marketing', 'personalization', 'analytics', 'retail_media', 'data_sale', 'service'));

ALTER TABLE ${catalog}.${ucv_schema}.activation_job
  ADD CONSTRAINT chk_aj_channel
  CHECK (channel_code IS NULL OR channel_code IN ('email', 'sms', 'phone', 'postal', 'push', 'web', 'in_app', 'ctv', 'social', 'display', 'search'));

ALTER TABLE ${catalog}.${ucv_schema}.activation_job
  ADD CONSTRAINT chk_aj_failure_reason
  CHECK (failure_reason_code IS NULL OR failure_reason_code IN ('none', 'auth_error', 'quota_exceeded', 'schema_mismatch', 'consent_block', 'provider_error', 'timeout'));

ALTER TABLE ${catalog}.${ucv_schema}.activation_job
  ADD CONSTRAINT chk_aj_sync_mode
  CHECK (sync_mode IS NULL OR sync_mode IN ('full_refresh', 'incremental_upsert', 'delete_only'));

-- ---------- campaign_touch enums ----------
ALTER TABLE ${catalog}.${ucv_schema}.campaign_touch
  ADD CONSTRAINT chk_ct_direction
  CHECK (touch_direction IN ('outbound', 'inbound'));

ALTER TABLE ${catalog}.${ucv_schema}.campaign_touch
  ADD CONSTRAINT chk_ct_type
  CHECK (touch_type IN ('send', 'delivery', 'open', 'click', 'bounce', 'unsubscribe', 'reply', 'conversion', 'complaint'));

ALTER TABLE ${catalog}.${ucv_schema}.campaign_touch
  ADD CONSTRAINT chk_ct_channel
  CHECK (channel_code IS NULL OR channel_code IN ('email', 'sms', 'push', 'direct_mail', 'web', 'in_app', 'call_center', 'in_store'));

ALTER TABLE ${catalog}.${ucv_schema}.campaign_touch
  ADD CONSTRAINT chk_ct_delivery_status
  CHECK (delivery_status_code IS NULL OR delivery_status_code IN ('queued', 'sent', 'delivered', 'bounced', 'failed', 'suppressed'));

ALTER TABLE ${catalog}.${ucv_schema}.campaign_touch
  ADD CONSTRAINT chk_ct_consent_status
  CHECK (consent_status IS NULL OR consent_status IN ('granted', 'denied', 'unknown'));
