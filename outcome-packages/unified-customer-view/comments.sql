-- ============================================================
-- ORDM · Outcome Package · Unified Customer View · column comments
-- Version: 0.5 · Generated: 2026-07-10 · LLM-generated: true · Reviewed: 2026-07-10
-- Column-level documentation for the gold views (Genie / AI-BI / UC metadata,
-- and the source of column descriptions in the generated ODCS contract).
-- COMMENT ON COLUMN is standard SQL — consistent with the engine-neutral choice.
-- Run AFTER the views exist.
-- ============================================================

-- ========== gold_unified_customer_360_current ==========

COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.profile_sk IS 'Customer surrogate key (join target).';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.profile_id IS 'Durable pseudonymous customer business key.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.household_size IS 'Number of current profiles sharing this household (outcome-layer roll-up).';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.active_identifier_count IS 'Count of current, active resolved identifiers for the customer.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.resolved_identity_confidence IS 'Identity-resolution confidence in [0,1]: the highest match_confidence across the current active identity links of the customer.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.has_email_flag IS 'TRUE if an active email contact point exists.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.has_phone_flag IS 'TRUE if an active phone contact point exists.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.has_mailable_address_flag IS 'TRUE if an active postal address exists.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.jurisdiction_primary_code IS 'Governing privacy region from primary address (ISO 3166).';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.consent_marketing_flag IS 'Summary: any marketing consent granted (see eligibility view for the per-channel, jurisdiction-resolved gate).';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.consent_personalization_flag IS 'Summary: profiling/personalization consent granted.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.consent_third_party_sharing_flag IS 'Summary: third-party-sharing consent granted.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.consented_purpose_count IS 'Count of distinct consent types currently granted.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.email_contactable_flag IS 'Summary: has email AND email marketing consent AND not opted out.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.sms_contactable_flag IS 'Summary: has phone AND sms marketing consent AND not opted out.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.marketing_eligible_flag IS 'Summary marketing-reachability: marketing consent granted AND customer active.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.preferred_channel_code IS 'Highest-ranked opted-in communication channel.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.customer_status_code IS 'Lifecycle status: prospect, active, inactive, closed.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.profile_completeness_score IS 'Populated key attributes / required, in [0,1].';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.reachability_score IS 'Activation-readiness across channels, in [0,1].';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_unified_customer_360_current.fresh_as_of_ts IS 'View evaluation timestamp (UTC).';

-- ========== gold_customer_activation_eligibility_current ==========

COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current.profile_sk IS 'Customer surrogate key.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current.profile_id IS 'Durable pseudonymous customer business key.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current.purpose_code IS 'Processing purpose derived from consent_type (ADR 0028): marketing, personalization, analytics, retail_media, or data_sale (CCPA do-not-sell).';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current.channel_code IS 'Owned channel for marketing purposes (email, sms, phone, postal); NULL for the channel-agnostic non-marketing purposes (personalization/analytics/retail_media), which activate via a match key at the reverse-ETL boundary.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current.jurisdiction_code IS 'Consent jurisdiction scope, ISO 3166 (GDPR vs CCPA/CPRA).';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current.consent_granted_flag IS 'Current consent is granted for this purpose x channel x jurisdiction.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current.preference_allows_flag IS 'Customer has not opted out of this channel in preferences. For the channel-agnostic non-marketing purposes (channel NULL) this is vacuously TRUE — channel preference does not constrain a channel-agnostic purpose (ADR 0028).';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current.has_identifier_flag IS 'A valid identifier/contact exists for the channel. For the channel-agnostic non-marketing purposes (personalization/analytics/retail_media, channel NULL) this is vacuously TRUE — reachability is resolved at the reverse-ETL match-key boundary, not here (ADR 0028).';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current.eligible_flag IS 'Net permission: consent AND preference AND identifier. For channel-agnostic non-marketing purposes eligible_flag does NOT imply an owned identifier exists (has_identifier is vacuously TRUE); match-key reachability is resolved downstream.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current.is_suppressed_flag IS 'A do-not-contact suppression overlay applies to this scope (consent.suppression_indicator); overrides granted consent.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current.blocking_reason_code IS 'First failing rule when not eligible, suppression first: suppressed, withdrawn, consent_denied, preference_opt_out, no_identifier.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current.evaluated_ts IS 'View evaluation timestamp (UTC).';

-- ---------- gold_activatable_audience_current (reverse-ETL-ready activation surface) ----------
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_activatable_audience_current.audience_id IS 'Durable segment/audience key (marketing.audience) being activated.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_activatable_audience_current.audience_name IS 'Human-readable segment name.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_activatable_audience_current.profile_id IS 'Durable, pseudonymous customer key — the single stable activation/join key (identifier resolution happens at the reverse-ETL boundary, not here).';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_activatable_audience_current.purpose_code IS 'Activation purpose from the eligibility gate (ADR 0028): marketing, personalization, analytics, retail_media, or data_sale (CCPA do-not-sell).';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_activatable_audience_current.channel_code IS 'Owned channel for marketing purposes (email, sms, phone, postal); NULL for the channel-agnostic non-marketing purposes (personalization/analytics/retail_media/data_sale), which activate via a match key at the reverse-ETL boundary.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_activatable_audience_current.jurisdiction_code IS 'Consent jurisdiction scope passed through from the gate.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_activatable_audience_current.membership_status IS 'Segment membership state (realized/existing) from segment_membership.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_activatable_audience_current.membership_score IS 'Optional membership confidence/propensity from segment_membership.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_activatable_audience_current.eligible_flag IS 'Always TRUE here (the view exposes only gate-eligible rows); kept for consumer clarity.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_activatable_audience_current.blocking_reason_code IS 'From the gate; NULL for eligible rows.';

-- gold_person_do_not_target_current (cross-plane do-not-target set, ADR 0028)
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_person_do_not_target_current.profile_id IS 'Durable pseudonymous customer key of a profile carrying an active person-level do-not-target suppression; the anti-join key every activation plane consults.';
COMMENT ON COLUMN ${catalog}.${ucv_schema}.gold_person_do_not_target_current.do_not_target_reason_code IS 'Representative person-level suppression reason at legal-weight priority (legal_objection > deceased > do_not_contact > fraud); read customer.consent for the full set of reasons and scopes.';
