-- ============================================================
-- ORDM · Outcome Package · Unified Customer View · data-quality checks
-- Version: 0.5 · Generated: 2026-07-10 · LLM-generated: true · Reviewed: 2026-07-10
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report a
-- value and never fail the run. Run by runtime/data-quality/run_checks.py.
-- ============================================================

-- ========== customer_profile_snapshot ==========
-- Schema / contract guards for an ADOPTER-OWNED append (no shipped producer):
-- these validate whatever rows the adopter's snapshot job writes and pass
-- vacuously on an empty table by design (see the table banner).

-- check: cps_keys_not_null | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.customer_profile_snapshot
WHERE customer_profile_snapshot_sk IS NULL OR customer_profile_snapshot_id IS NULL
   OR profile_id IS NULL;

-- check: cps_grain_unique | severity: error
-- Grain guard: one row per (profile_id, snapshot_date) as the banner promises.
SELECT profile_id, snapshot_date, COUNT(*) AS n
FROM ${catalog}.${ucv_schema}.customer_profile_snapshot
GROUP BY profile_id, snapshot_date HAVING COUNT(*) > 1;

-- check: cps_pk_unique | severity: error
SELECT customer_profile_snapshot_sk, COUNT(*) AS n
FROM ${catalog}.${ucv_schema}.customer_profile_snapshot
GROUP BY customer_profile_snapshot_sk
HAVING COUNT(*) > 1;

-- check: cps_profile_fk_orphan | severity: error
-- Every snapshot must reference an existing profile (by surrogate FK).
SELECT s.* FROM ${catalog}.${ucv_schema}.customer_profile_snapshot s
LEFT JOIN ${catalog}.${customer_schema}.profile p ON s.profile_sk = p.profile_sk
WHERE s.profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: cps_profile_businesskey_orphan | severity: error
SELECT s.* FROM ${catalog}.${ucv_schema}.customer_profile_snapshot s
LEFT JOIN (SELECT DISTINCT profile_id FROM ${catalog}.${customer_schema}.profile) p
  ON s.profile_id = p.profile_id
WHERE p.profile_id IS NULL;

-- check: cps_snapshot_reason_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.customer_profile_snapshot
WHERE snapshot_reason_code IS NOT NULL
  AND snapshot_reason_code NOT IN ('scheduled', 'pre_campaign', 'ad_hoc', 'audit');

-- check: cps_status_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.customer_profile_snapshot
WHERE customer_status_code IS NOT NULL
  AND customer_status_code NOT IN ('prospect', 'active', 'inactive', 'closed');

-- check: cps_scores_in_range | severity: error
-- Confidence and readiness scores are probabilities in [0,1].
SELECT * FROM ${catalog}.${ucv_schema}.customer_profile_snapshot
WHERE (resolved_identity_confidence IS NOT NULL AND resolved_identity_confidence NOT BETWEEN 0 AND 1)
   OR (profile_completeness_score IS NOT NULL AND profile_completeness_score NOT BETWEEN 0 AND 1)
   OR (reachability_score IS NOT NULL AND reachability_score NOT BETWEEN 0 AND 1);

-- ========== gold views — no-raw-PII guard ==========

-- check: ucv_no_raw_pii | severity: error
-- The gold views must NOT expose raw PII columns (loyalty/household ids, names,
-- dob, contact values). PII stays in the governed dimension; views key on the
-- surrogate/durable pseudonymous profile_id.
SELECT table_name, column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${ucv_schema}'
  AND table_name IN ('gold_unified_customer_360_current',
                     'gold_customer_activation_eligibility_current',
                     'gold_person_do_not_target_current')
  AND column_name IN ('loyalty_id', 'household_id', 'first_name', 'middle_name',
                      'last_name', 'date_of_birth', 'name_prefix', 'name_suffix',
                      'contact_value', 'identifier_value_hash');

-- ========== gold_unified_customer_360_current ==========

-- check: ucv_360_scores_in_range | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.gold_unified_customer_360_current
WHERE (resolved_identity_confidence IS NOT NULL AND resolved_identity_confidence NOT BETWEEN 0 AND 1)
   OR (profile_completeness_score IS NOT NULL AND profile_completeness_score NOT BETWEEN 0 AND 1)
   OR (reachability_score IS NOT NULL AND reachability_score NOT BETWEEN 0 AND 1);

-- check: ucv_360_one_row_per_customer | severity: error
-- Grain guard: one current row per resolved customer.
SELECT profile_id, COUNT(*) AS n
FROM ${catalog}.${ucv_schema}.gold_unified_customer_360_current
GROUP BY profile_id
HAVING COUNT(*) > 1;

-- check: ucv_360_customer_count | severity: metric
-- Reports the size of the unified customer population.
SELECT COUNT(*) AS unified_customer_count
FROM ${catalog}.${ucv_schema}.gold_unified_customer_360_current;

-- ========== gold_customer_activation_eligibility_current ==========

-- check: ucv_eligibility_one_row_per_grain | severity: error
-- Grain guard (mirrors the 360 one-row check): one row per customer x purpose x
-- channel x jurisdiction.
SELECT profile_id, purpose_code, channel_code, jurisdiction_code, COUNT(*) AS n
FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current
GROUP BY profile_id, purpose_code, channel_code, jurisdiction_code
HAVING COUNT(*) > 1;

-- check: ucv_eligibility_blocking_reason_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current
WHERE blocking_reason_code IS NOT NULL
  AND blocking_reason_code NOT IN ('consent_denied', 'withdrawn', 'preference_opt_out',
                                   'no_identifier', 'suppressed');

-- check: ucv_eligibility_flag_consistency | severity: error
-- eligible_flag TRUE must have no blocking reason; FALSE must have one.
SELECT * FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current
WHERE (eligible_flag = TRUE  AND blocking_reason_code IS NOT NULL)
   OR (eligible_flag = FALSE AND blocking_reason_code IS NULL);

-- check: ucv_eligibility_purpose_domain | severity: error
-- The gate purpose must be one of the consent-derived activation purposes (ADR 0028):
-- marketing / personalization / analytics / retail_media / data_sale. service + data_processing
-- are not consent-gated, so they never appear here. Guards the consent_type -> purpose mapping.
SELECT * FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current
WHERE purpose_code IS NULL
   OR purpose_code NOT IN ('marketing', 'personalization', 'analytics', 'retail_media', 'data_sale');

-- check: ucv_eligibility_purpose_channel_pairing | severity: error
-- The gate is only correct if purpose and channel stay paired (ADR 0028): the marketing
-- purpose is a purpose x owned-channel compound, so it must carry a non-NULL channel_code;
-- the channel-agnostic purposes (personalization / analytics / retail_media / data_sale) must
-- carry a NULL channel_code (they activate via a match key, not an owned email/sms/phone/postal
-- channel). purpose_code and channel_code are derived from consent_type in two parallel
-- CASE expressions, so this asserts the load-bearing invariant that ties them together: if a
-- future edit drifts one branch (a new marketing_* type added to purpose but not channel, or
-- a non-marketing purpose accidentally emitting a channel) the other checks still pass while
-- the consent gate silently mis-gates. Equivalent to (purpose='marketing') = (channel NOT NULL).
SELECT * FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current
WHERE (purpose_code =  'marketing' AND channel_code IS NULL)
   OR (purpose_code <> 'marketing' AND channel_code IS NOT NULL);

-- check: ucv_eligibility_person_suppressed_blocked | severity: error
-- Cross-plane do-not-target enforcement (ADR 0028): no profile in the shared do-not-target
-- set may ever resolve eligible on the owned gate. Makes "person-level suppression blocks
-- every plane" a machine-checked invariant, not just prose.
SELECT g.* FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current g
JOIN ${catalog}.${ucv_schema}.gold_person_do_not_target_current dnt
  ON dnt.profile_id = g.profile_id
WHERE g.eligible_flag = TRUE;

-- check: ucv_eligible_rate | severity: metric
-- Share of customer x purpose x channel rows that are activation-eligible.
SELECT ROUND(AVG(CASE WHEN eligible_flag THEN 1.0 ELSE 0.0 END), 4) AS eligible_rate
FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current;

-- check: ucv_suppression_rate | severity: metric
-- The suppression_rate KPI (glossary): share of purpose x channel rows blocked by a
-- do-not-contact suppression overlay.
SELECT ROUND(AVG(CASE WHEN is_suppressed_flag THEN 1.0 ELSE 0.0 END), 4) AS suppression_rate
FROM ${catalog}.${ucv_schema}.gold_customer_activation_eligibility_current;

-- ---------- gold_activatable_audience_current (targeting x gate join, ADR 0022) ----------

-- check: uav_grain_unique | severity: error
-- One row per (audience_id x profile_id x purpose x channel x jurisdiction). Jurisdiction is
-- part of the grain because the eligibility gate is grained by jurisdiction (consent is
-- per-jurisdiction) — a profile eligible in >1 jurisdiction for one purpose x channel is an
-- expected shape, not a duplicate.
SELECT audience_id, profile_id, purpose_code, channel_code, jurisdiction_code
FROM ${catalog}.${ucv_schema}.gold_activatable_audience_current
GROUP BY audience_id, profile_id, purpose_code, channel_code, jurisdiction_code
HAVING COUNT(*) > 1;

-- check: uav_all_eligible | severity: error
-- The activation surface exposes ONLY gate-eligible rows (a segment never overrides consent).
SELECT * FROM ${catalog}.${ucv_schema}.gold_activatable_audience_current
WHERE eligible_flag <> TRUE OR eligible_flag IS NULL;

-- check: uav_no_raw_pii | severity: error
SELECT column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${ucv_schema}'
  AND table_name = 'gold_activatable_audience_current'
  AND column_name IN ('loyalty_id', 'household_id', 'first_name', 'middle_name',
                      'last_name', 'date_of_birth', 'email', 'phone_number');

-- check: uav_no_person_suppressed | severity: error
-- The activation surface must never expose a person-level do-not-target profile (ADR 0028).
-- Belt-and-suspenders with the gate's own suppression block: this asserts the surface itself
-- is PERSON-LEVEL-DNT-safe on any plane (owned or paid), independent of the gate's purpose
-- coverage. This is the person-level leg ONLY: a selling/sharing plane must also apply the
-- purpose-level do-not-sell/do-not-share opt-out (leg b); see the segment_membership contract.
SELECT a.* FROM ${catalog}.${ucv_schema}.gold_activatable_audience_current a
JOIN ${catalog}.${ucv_schema}.gold_person_do_not_target_current dnt
  ON dnt.profile_id = a.profile_id;

-- check: uav_activatable_rowcount | severity: metric
SELECT COUNT(*) AS activatable_rows FROM ${catalog}.${ucv_schema}.gold_activatable_audience_current;

-- ---------- gold_person_do_not_target_current (cross-plane do-not-target set, ADR 0028) ----------

-- check: dnt_reason_domain | severity: error
-- The representative reason must be one of the four person-level suppression reasons.
SELECT * FROM ${catalog}.${ucv_schema}.gold_person_do_not_target_current
WHERE do_not_target_reason_code IS NULL
   OR do_not_target_reason_code NOT IN ('deceased', 'fraud', 'do_not_contact', 'legal_objection');

-- check: dnt_profile_unique | severity: error
-- One row per profile_id (the view groups by profile_id).
SELECT profile_id FROM ${catalog}.${ucv_schema}.gold_person_do_not_target_current
GROUP BY profile_id HAVING COUNT(*) > 1;

-- check: dnt_reason_completeness | severity: error
-- Fail-loud coupling guard (ADR 0028): every CURRENT person-level suppression in
-- customer.consent MUST appear in the do-not-target view. The view pins the four
-- person-level reasons in its WHERE, and consent's chk_consent_suppression_reason
-- pins the same set independently -- if a future PR adds a new person-level reason to
-- consent but forgets the view's WHERE, that suppression would silently fail to
-- propagate to ANY plane (a do-not-contact leak by omission that dnt_reason_domain,
-- which only guards the view's OUTPUT, cannot catch). This asserts no such profile is
-- missing from the view. NOTE: keep the reason list here in sync with the view + the
-- consent CHECK -- it is the third pin, and it is the one that fails loud.
SELECT DISTINCT c.profile_id
FROM ${catalog}.${customer_schema}.consent c
LEFT JOIN ${catalog}.${ucv_schema}.gold_person_do_not_target_current dnt
  ON dnt.profile_id = c.profile_id
WHERE c.is_current = TRUE
  AND COALESCE(c.suppression_indicator, FALSE) = TRUE
  AND c.suppression_reason_code IN ('deceased', 'fraud', 'do_not_contact', 'legal_objection')
  AND dnt.profile_id IS NULL;

-- ========== activation_destination (CDP activation layer, ADR 0026) ==========

-- check: ad_keys_not_null | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.activation_destination
WHERE activation_destination_sk IS NULL OR activation_destination_id IS NULL;

-- check: ad_id_unique | severity: error
-- Type-1 grain guard: one row per destination connector.
SELECT activation_destination_id, COUNT(*) AS n
FROM ${catalog}.${ucv_schema}.activation_destination
GROUP BY activation_destination_id HAVING COUNT(*) > 1;

-- check: ad_pk_unique | severity: error
SELECT activation_destination_sk, COUNT(*) AS n
FROM ${catalog}.${ucv_schema}.activation_destination
GROUP BY activation_destination_sk HAVING COUNT(*) > 1;

-- (no ad_platform_domain: destination_platform is free, adopter-defined text — vendor-neutral
-- schema, so it is deliberately not domain-constrained.)

-- check: ad_connector_kind_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.activation_destination
WHERE connector_kind IS NOT NULL
  AND connector_kind NOT IN ('reverse_etl', 'api_push', 'file_export', 'clean_room_match', 'managed_connector');

-- check: ad_required_purpose_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.activation_destination
WHERE required_consent_purpose IS NOT NULL
  AND required_consent_purpose NOT IN ('marketing', 'personalization', 'analytics', 'retail_media', 'data_sale', 'service');

-- check: ad_required_channel_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.activation_destination
WHERE required_channel IS NOT NULL
  AND required_channel NOT IN ('email', 'sms', 'phone', 'postal', 'push', 'web', 'in_app', 'ctv', 'social', 'display', 'search');

-- check: ad_destination_count | severity: metric
SELECT COUNT(*) AS destination_count
FROM ${catalog}.${ucv_schema}.activation_destination;

-- ========== activation_job (CDP activation layer, ADR 0026) ==========

-- check: aj_keys_not_null | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.activation_job
WHERE activation_job_sk IS NULL OR activation_job_id IS NULL
   OR job_run_ts IS NULL OR job_run_date IS NULL OR job_status IS NULL;

-- check: aj_grain_unique | severity: error
-- Grain guard: one row per (audience_id, activation_destination_id, jurisdiction_code,
-- job_run_ts). jurisdiction_code is nullable (an agnostic roll-up), so COALESCE it. NOTE:
-- the durable activation_job_id (aj_id_unique) is the PRIMARY row-uniqueness guarantee; this
-- composite key includes a TIMESTAMP (job_run_ts) and is a business-grain sanity check.
SELECT audience_id, activation_destination_id,
       COALESCE(jurisdiction_code, '') AS jurisdiction_code, job_run_ts, COUNT(*) AS n
FROM ${catalog}.${ucv_schema}.activation_job
GROUP BY audience_id, activation_destination_id, COALESCE(jurisdiction_code, ''), job_run_ts
HAVING COUNT(*) > 1;

-- check: aj_pk_unique | severity: error
SELECT activation_job_sk, COUNT(*) AS n
FROM ${catalog}.${ucv_schema}.activation_job
GROUP BY activation_job_sk HAVING COUNT(*) > 1;

-- check: aj_id_unique | severity: error
-- Durable business key guard (sibling convention: every fact guards its <stem>_id, so a
-- duplicate id can't silently fan out the *_businesskey_orphan joins that resolve on it).
SELECT activation_job_id, COUNT(*) AS n
FROM ${catalog}.${ucv_schema}.activation_job
GROUP BY activation_job_id HAVING COUNT(*) > 1;

-- check: aj_audience_fk_orphan | severity: error
SELECT j.* FROM ${catalog}.${ucv_schema}.activation_job j
LEFT JOIN ${catalog}.${marketing_schema}.audience a ON j.audience_sk = a.audience_sk
WHERE j.audience_sk IS NOT NULL AND a.audience_sk IS NULL;

-- check: aj_audience_businesskey_orphan | severity: error
SELECT j.* FROM ${catalog}.${ucv_schema}.activation_job j
LEFT JOIN (SELECT DISTINCT audience_id FROM ${catalog}.${marketing_schema}.audience) a
  ON j.audience_id = a.audience_id
WHERE j.audience_id IS NOT NULL AND a.audience_id IS NULL;

-- check: aj_destination_fk_orphan | severity: error
SELECT j.* FROM ${catalog}.${ucv_schema}.activation_job j
LEFT JOIN ${catalog}.${ucv_schema}.activation_destination d ON j.activation_destination_sk = d.activation_destination_sk
WHERE j.activation_destination_sk IS NOT NULL AND d.activation_destination_sk IS NULL;

-- check: aj_destination_businesskey_orphan | severity: error
SELECT j.* FROM ${catalog}.${ucv_schema}.activation_job j
LEFT JOIN (SELECT DISTINCT activation_destination_id FROM ${catalog}.${ucv_schema}.activation_destination) d
  ON j.activation_destination_id = d.activation_destination_id
WHERE j.activation_destination_id IS NOT NULL AND d.activation_destination_id IS NULL;

-- check: aj_status_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.activation_job
WHERE job_status NOT IN ('queued', 'running', 'succeeded', 'partial', 'failed', 'cancelled');

-- check: aj_failure_reason_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.activation_job
WHERE failure_reason_code IS NOT NULL
  AND failure_reason_code NOT IN ('none', 'auth_error', 'quota_exceeded', 'schema_mismatch', 'consent_block', 'provider_error', 'timeout');

-- check: aj_counts_nonneg | severity: error
-- Member counts are non-negative.
SELECT * FROM ${catalog}.${ucv_schema}.activation_job
WHERE (requested_member_count  IS NOT NULL AND requested_member_count  < 0)
   OR (eligible_member_count   IS NOT NULL AND eligible_member_count   < 0)
   OR (blocked_member_count    IS NOT NULL AND blocked_member_count    < 0)
   OR (exported_member_count   IS NOT NULL AND exported_member_count   < 0)
   OR (removed_member_count    IS NOT NULL AND removed_member_count    < 0)
   OR (delivered_member_count  IS NOT NULL AND delivered_member_count  < 0)
   OR (rejected_member_count   IS NOT NULL AND rejected_member_count   < 0);

-- check: aj_counts_monotonic | severity: error
-- Consent gate is fail-closed: a job can never export more than eligible, and never
-- eligible more than requested. exported <= eligible <= requested. The destination-side
-- accept/reject split (delivered, rejected) can never exceed what was exported.
SELECT * FROM ${catalog}.${ucv_schema}.activation_job
WHERE (eligible_member_count IS NOT NULL AND requested_member_count IS NOT NULL
        AND eligible_member_count > requested_member_count)
   OR (exported_member_count IS NOT NULL AND eligible_member_count IS NOT NULL
        AND exported_member_count > eligible_member_count)
   OR (delivered_member_count IS NOT NULL AND exported_member_count IS NOT NULL
        AND delivered_member_count > exported_member_count)
   OR (rejected_member_count IS NOT NULL AND exported_member_count IS NOT NULL
        AND rejected_member_count > exported_member_count)
   -- delivered + rejected reconcile to exported (activation_job.sql): their sum cannot exceed it.
   OR (delivered_member_count IS NOT NULL AND rejected_member_count IS NOT NULL
        AND exported_member_count IS NOT NULL
        AND delivered_member_count + rejected_member_count > exported_member_count);

-- check: aj_blocked_reconciles | severity: error
-- blocked_member_count is DEFINED as requested - eligible (ADR 0026 §2 / column comment) — the
-- ALL-CAUSE count of members the gate removed, not suppression-specific. Enforce that identity
-- so the column can't silently disagree with the counts it derives from (which would skew
-- activation_block_rate). Only where all three are populated.
SELECT * FROM ${catalog}.${ucv_schema}.activation_job
WHERE requested_member_count IS NOT NULL
  AND eligible_member_count  IS NOT NULL
  AND blocked_member_count   IS NOT NULL
  AND (requested_member_count - eligible_member_count) <> blocked_member_count;

-- check: aj_match_rate_in_range | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.activation_job
WHERE match_rate IS NOT NULL AND match_rate NOT BETWEEN 0 AND 1;

-- check: aj_destination_purpose_channel_match | severity: error
-- A run's purpose/channel MUST match the destination's declared required_consent_purpose /
-- required_channel (activation_job.sql + activation_destination.sql document this invariant;
-- it's what makes the consent gate destination-aware). Enforce it where both sides are set.
SELECT j.* FROM ${catalog}.${ucv_schema}.activation_job j
JOIN ${catalog}.${ucv_schema}.activation_destination d
  ON j.activation_destination_id = d.activation_destination_id
WHERE (d.required_consent_purpose IS NOT NULL AND j.purpose_code IS NOT NULL
        AND j.purpose_code <> d.required_consent_purpose)
   OR (d.required_channel IS NOT NULL AND j.channel_code IS NOT NULL
        AND j.channel_code <> d.required_channel);

-- check: aj_export_rate | severity: metric
-- Share of eligible members actually exported across runs (activation efficiency).
SELECT ROUND(
  SUM(exported_member_count) / NULLIF(SUM(eligible_member_count), 0), 4) AS export_rate
FROM ${catalog}.${ucv_schema}.activation_job;

-- check: aj_block_rate | severity: metric
-- The activation_block_rate KPI (glossary): all-cause share of requested members the gate
-- removed. Ratio-of-sums, not an avg of per-run rates.
SELECT ROUND(
  SUM(blocked_member_count) / NULLIF(SUM(requested_member_count), 0), 4) AS block_rate
FROM ${catalog}.${ucv_schema}.activation_job;

-- check: aj_match_rate | severity: metric
-- The activation_match_rate KPI (glossary): member-weighted provider match rate across
-- exports. Ratio-of-sums (matched estimate / exported), not an avg of per-run rates. The
-- denominator counts only exports with a KNOWN match_rate — including NULL-match exports would
-- dilute the rate toward 0 (review m1).
SELECT ROUND(
  SUM(exported_member_count * match_rate)
  / NULLIF(SUM(CASE WHEN match_rate IS NOT NULL THEN exported_member_count END), 0), 4) AS match_rate
FROM ${catalog}.${ucv_schema}.activation_job;

-- check: aj_job_timestamps_ordered | severity: error
-- Run lifecycle: completion cannot precede start.
SELECT * FROM ${catalog}.${ucv_schema}.activation_job
WHERE job_started_ts IS NOT NULL AND job_completed_ts IS NOT NULL
  AND job_completed_ts < job_started_ts;

-- check: aj_delete_only_exports_nothing | severity: error
-- A delete_only run retracts members and publishes none, so exported_member_count must be
-- 0/NULL (removed_member_count carries the retraction). Keeps the new sync telemetry as
-- self-consistent as the reconciled counts.
SELECT * FROM ${catalog}.${ucv_schema}.activation_job
WHERE sync_mode = 'delete_only' AND COALESCE(exported_member_count, 0) <> 0;

-- check: aj_consent_implies_suppression | severity: error
-- Flag-CONSISTENCY only, NOT proof the consult happened: both flags are adopter-supplied, so
-- this cannot verify that the do-not-target anti-join actually ran (ORDM does not run the sync).
-- What it asserts: a run claiming is_consent_enforced_flag=TRUE (eligible slice sourced from
-- gold_activatable_audience_current, which anti-joins the DNT view by construction) must not
-- ALSO claim it did not apply suppression — that pairing is self-contradictory. Reject it.
SELECT * FROM ${catalog}.${ucv_schema}.activation_job
WHERE is_consent_enforced_flag = TRUE AND COALESCE(is_suppression_applied_flag, FALSE) = FALSE;

-- check: aj_suppression_applied_rate | severity: metric
-- Observability for the ADR 0028 cross-plane contract: share of runs that recorded the
-- person-level do-not-target consult (is_suppression_applied_flag). NOT an error gate — the
-- flag is adopter-supplied and the paid-plane obligation cannot be CI-proven — but a low rate
-- surfaces runs that may have skipped the do-not-target anti-join, worth review.
SELECT ROUND(AVG(CASE WHEN is_suppression_applied_flag THEN 1.0 ELSE 0.0 END), 4) AS suppression_applied_rate
FROM ${catalog}.${ucv_schema}.activation_job;

-- ========== campaign_touch (CDP activation layer, ADR 0026) ==========

-- check: ct_keys_not_null | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.campaign_touch
WHERE campaign_touch_sk IS NULL OR campaign_touch_id IS NULL
   OR touch_ts IS NULL OR touch_date IS NULL OR touch_direction IS NULL OR touch_type IS NULL;

-- check: ct_grain_unique | severity: error
-- Grain guard: one row per (profile_id, promo_id, channel_code, touch_ts, touch_type).
-- channel_code is part of the grain — a multi-channel campaign firing e.g. an email AND a push
-- send for the same profile/promo at the same touch_ts are two legit touches, not a duplicate
-- (review M1). profile_id / promo_id / channel_code are nullable, so COALESCE them — else
-- NULL <> NULL would let duplicates slip the guard. The durable campaign_touch_id (ct_id_unique)
-- is the primary row-uniqueness guarantee; this is the business-grain sanity check.
SELECT COALESCE(profile_id, '') AS profile_id, COALESCE(promo_id, '') AS promo_id,
       COALESCE(channel_code, '') AS channel_code, touch_ts, touch_type, COUNT(*) AS n
FROM ${catalog}.${ucv_schema}.campaign_touch
GROUP BY COALESCE(profile_id, ''), COALESCE(promo_id, ''), COALESCE(channel_code, ''), touch_ts, touch_type
HAVING COUNT(*) > 1;

-- check: ct_pk_unique | severity: error
SELECT campaign_touch_sk, COUNT(*) AS n
FROM ${catalog}.${ucv_schema}.campaign_touch
GROUP BY campaign_touch_sk HAVING COUNT(*) > 1;

-- check: ct_id_unique | severity: error
-- Durable business key guard (sibling convention): campaign_touch_id is per INTERACTION
-- EVENT and must be unique at row grain — one row per touch_type, so send/delivery/open/click
-- are distinct touches with distinct ids (a repeated platform message id belongs in
-- external_campaign_id, not here). Also protects ct_activation_job_businesskey_orphan.
SELECT campaign_touch_id, COUNT(*) AS n
FROM ${catalog}.${ucv_schema}.campaign_touch
GROUP BY campaign_touch_id HAVING COUNT(*) > 1;

-- check: ct_profile_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${ucv_schema}.campaign_touch t
LEFT JOIN ${catalog}.${customer_schema}.profile p ON t.profile_sk = p.profile_sk
WHERE t.profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: ct_profile_businesskey_orphan | severity: error
SELECT t.* FROM ${catalog}.${ucv_schema}.campaign_touch t
LEFT JOIN (SELECT DISTINCT profile_id FROM ${catalog}.${customer_schema}.profile) p
  ON t.profile_id = p.profile_id
WHERE t.profile_id IS NOT NULL AND p.profile_id IS NULL;

-- check: ct_audience_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${ucv_schema}.campaign_touch t
LEFT JOIN ${catalog}.${marketing_schema}.audience a ON t.audience_sk = a.audience_sk
WHERE t.audience_sk IS NOT NULL AND a.audience_sk IS NULL;

-- check: ct_audience_businesskey_orphan | severity: error
SELECT t.* FROM ${catalog}.${ucv_schema}.campaign_touch t
LEFT JOIN (SELECT DISTINCT audience_id FROM ${catalog}.${marketing_schema}.audience) a
  ON t.audience_id = a.audience_id
WHERE t.audience_id IS NOT NULL AND a.audience_id IS NULL;

-- check: ct_promotion_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${ucv_schema}.campaign_touch t
LEFT JOIN ${catalog}.${marketing_schema}.promotion pr ON t.promo_sk = pr.promo_sk
WHERE t.promo_sk IS NOT NULL AND pr.promo_sk IS NULL;

-- check: ct_promotion_businesskey_orphan | severity: error
SELECT t.* FROM ${catalog}.${ucv_schema}.campaign_touch t
LEFT JOIN (SELECT DISTINCT promo_id FROM ${catalog}.${marketing_schema}.promotion) pr
  ON t.promo_id = pr.promo_id
WHERE t.promo_id IS NOT NULL AND pr.promo_id IS NULL;

-- check: ct_activation_job_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${ucv_schema}.campaign_touch t
LEFT JOIN ${catalog}.${ucv_schema}.activation_job j ON t.activation_job_sk = j.activation_job_sk
WHERE t.activation_job_sk IS NOT NULL AND j.activation_job_sk IS NULL;

-- check: ct_activation_job_businesskey_orphan | severity: error
SELECT t.* FROM ${catalog}.${ucv_schema}.campaign_touch t
LEFT JOIN (SELECT DISTINCT activation_job_id FROM ${catalog}.${ucv_schema}.activation_job) j
  ON t.activation_job_id = j.activation_job_id
WHERE t.activation_job_id IS NOT NULL AND j.activation_job_id IS NULL;

-- check: ct_direction_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.campaign_touch
WHERE touch_direction NOT IN ('outbound', 'inbound');

-- check: ct_type_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.campaign_touch
WHERE touch_type NOT IN ('send', 'delivery', 'open', 'click', 'bounce', 'unsubscribe', 'reply', 'conversion', 'complaint');

-- check: ct_channel_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.campaign_touch
WHERE channel_code IS NOT NULL
  AND channel_code NOT IN ('email', 'sms', 'push', 'direct_mail', 'web', 'in_app', 'call_center', 'in_store');

-- check: ct_delivery_status_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.campaign_touch
WHERE delivery_status_code IS NOT NULL
  AND delivery_status_code NOT IN ('queued', 'sent', 'delivered', 'bounced', 'failed', 'suppressed');

-- check: ct_consent_status_domain | severity: error
SELECT * FROM ${catalog}.${ucv_schema}.campaign_touch
WHERE consent_status IS NOT NULL
  AND consent_status NOT IN ('granted', 'denied', 'unknown');

-- check: ct_touch_count | severity: metric
SELECT COUNT(*) AS campaign_touch_count FROM ${catalog}.${ucv_schema}.campaign_touch;

-- check: ct_campaign_reach | severity: metric
-- The campaign_reach KPI (glossary): distinct customers touched.
SELECT COUNT(DISTINCT profile_id) AS campaign_reach FROM ${catalog}.${ucv_schema}.campaign_touch;

-- check: ct_delivered_to_denied | severity: metric
-- GOVERNANCE SIGNAL (design-gap self-review): this audit fact's purpose is consent governance,
-- so surface the violation it can capture — outbound CONTACT acts (send / delivery) to a customer
-- whose consent_status was 'denied' at touch time = a do-not-contact breach recorded in the data.
-- Scoped to the contact acts on purpose: the send/delivery IS the breach; downstream engagement
-- (open/click) and inbound responses (conversion/reply) are consequences of that send, not
-- separate breaches, and counting them would double-count or cross the direction classification
-- (the banner groups conversion as inbound). Metric-severity, not a hard fail: adopter-recorded
-- history to review, not a model defect; a non-zero value warrants investigation.
SELECT COUNT(*) AS delivered_to_denied
FROM ${catalog}.${ucv_schema}.campaign_touch
WHERE touch_direction = 'outbound' AND consent_status = 'denied'
  AND touch_type IN ('send', 'delivery');

-- check: ct_activation_job_audience_consistency | severity: error
-- Closed-loop integrity (design-gap self-review): a touch sourced from an activation run must
-- carry that run's audience. When both campaign_touch.activation_job_id and audience_id are set,
-- they must agree with the referenced activation_job.audience_id — otherwise the
-- touch → job → audience lineage is internally inconsistent.
SELECT t.* FROM ${catalog}.${ucv_schema}.campaign_touch t
JOIN ${catalog}.${ucv_schema}.activation_job j ON t.activation_job_id = j.activation_job_id
WHERE t.audience_id IS NOT NULL AND j.audience_id IS NOT NULL
  AND t.audience_id <> j.audience_id;
