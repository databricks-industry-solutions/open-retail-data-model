-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- Table: activation_job
-- Layer: outcome package (gold / transactional)
-- Version: 0.5
-- Generated: 2026-07-24
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- Append-only, one row per activation RUN: a given audience version published to a
-- given destination as of a given membership snapshot. The audit fact that closes the
-- CDP loop (ADR 0026) — it records that an audience was activated, how many members
-- were requested vs. eligible vs. actually exported, and how many the eligibility gate
-- blocked. Immutable per run; a re-run is a new row.
--
-- CONSENT ENFORCEMENT IS AUDITED HERE, NOT PERFORMED HERE. The gate is
-- gold_activatable_audience_current (targeting ∘ consent ∘ preference ∘ reachability,
-- fail-closed). A job publishes only the eligible slice, and this row is the evidence:
--   requested_member_count = raw segment size (ACU segment_membership at as_of_date)
--   eligible_member_count  = members with an eligible gate row for the destination's
--                            required_consent_purpose × required_channel × jurisdiction
--   blocked_member_count   = requested − eligible: members the gate removed for ANY reason
--                            (consent, preference, reachability, OR suppression). ALL-CAUSE,
--                            NOT suppression-specific — do not read it as a do-not-contact
--                            count; ADR 0027 keeps those governed states distinct.
--   exported_member_count  = actually sent to the destination (≤ eligible)
-- A job can never export more than eligible — a violation is a DQ error (checks.sql).
-- RECONCILIATION SCOPE: the gate derives purpose from the full consent-type set (ADR 0028) —
-- marketing (channels email/sms/phone/postal), personalization, analytics, and retail_media
-- reconcile against it. `service` (transactional; not consent-gated) and non-owned channels
-- (push, web, social, …) still have no gate row, so those counts are adopter-supplied.
-- CHANNEL-AGNOSTIC PURPOSES: the gate emits personalization/analytics/retail_media rows with
-- channel_code = NULL (reachability resolves at the reverse-ETL match-key boundary), so for
-- those purposes eligible_member_count reconciles against the gate on purpose x jurisdiction
-- ONLY (not channel), and a channel-agnostic destination should leave required_channel NULL
-- (so aj_destination_purpose_channel_match does not fire). Reconciling such a destination on a
-- concrete channel would find no NULL-channel gate row and wrongly read as zero-eligible.
--
-- Grain: one row per (audience_id × activation_destination_id × jurisdiction_code ×
-- job_run_ts). jurisdiction_code scopes the counts to one regulatory regime so they
-- reconcile against the jurisdiction-grained gate and a residency-constrained destination
-- (NULL = a jurisdiction-agnostic roll-up across regimes). Nullable _sk + durable _id FK
-- pairs to the shared audience definition (marketing.audience) and the destination catalog
-- (activation_destination); membership_as_of_date pins which ACU segment_membership
-- snapshot was exported so a run is reproducible.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ucv_schema}.activation_job (
  activation_job_sk     BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per run row.',
  activation_job_id     STRING NOT NULL
                          COMMENT 'Durable natural/business key for the activation run. Composed from the full grain: audience_id + activation_destination_id + jurisdiction_code + job_run_ts (a NULL jurisdiction is its own agnostic scope) — so two runs differing only by jurisdiction get distinct ids. If minted opaquely instead, it must still be unique at that grain (aj_id_unique).',

  -- What was published (shared silver definition) + where (gold reference catalog)
  audience_sk           BIGINT COMMENT 'FK to marketing.audience.audience_sk — the published audience/segment version.',
  audience_id           STRING COMMENT 'Durable audience business key.',
  activation_destination_sk BIGINT COMMENT 'FK to ucv.activation_destination.activation_destination_sk — where the audience was published.',
  activation_destination_id STRING COMMENT 'Durable destination business key.',

  membership_as_of_date DATE COMMENT 'The ACU segment_membership snapshot date this run exported (pins reproducibility to a frozen membership).',
  job_run_ts            TIMESTAMP NOT NULL COMMENT 'When the activation run executed at source (UTC, ISO 8601).',
  job_run_date          DATE NOT NULL COMMENT 'Business date of the run (cluster key).',
  job_status            STRING NOT NULL COMMENT 'Terminal or in-flight run state. Allowed values: queued, running, succeeded, partial, failed, cancelled.',

  purpose_code          STRING COMMENT 'Processing purpose this activation served — must match the destination required_consent_purpose. Allowed values: marketing, personalization, analytics, retail_media, data_sale, service.',
  channel_code          STRING COMMENT 'Channel this activation targeted — must match the destination required_channel. The consent-channel values email/sms/phone/postal align with the eligibility gate (so those runs reconcile against it); the rest are channels the gate does not evaluate today. Allowed values: email, sms, phone, postal, push, web, in_app, ctv, social, display, search.',
  jurisdiction_code     STRING COMMENT 'Regulatory regime the counts are scoped to (ISO 3166 country/subdivision, or a regional code such as EU — matching consent.jurisdiction_code), so eligible_member_count reconciles against the jurisdiction-grained gate. It ALSO gives informational residency traceability against a residency-constrained destination (activation_destination.data_residency_region), but the two are NOT DQ-reconciled: a regulatory-regime code and a processing-region label do not map 1:1 (e.g. regime EU vs region a specific country). NULL = a jurisdiction-agnostic roll-up across regimes.',

  requested_member_count  BIGINT COMMENT 'Raw segment size at membership_as_of_date, before the consent gate (>= 0).',
  eligible_member_count   BIGINT COMMENT 'Members with an eligible gate row for this purpose × channel × jurisdiction (>= 0, <= requested_member_count).',
  blocked_member_count    BIGINT COMMENT 'Members the eligibility gate removed for ANY reason — consent, preference, reachability, OR suppression (>= 0) = requested_member_count - eligible_member_count. ALL-CAUSE, NOT suppression-specific (ADR 0027 keeps those states distinct); a genuinely suppression-scoped count is a future per-reason breakout.',
  exported_member_count   BIGINT COMMENT 'Members actually published to the destination (>= 0, <= eligible_member_count).',
  match_rate              DECIMAL(5,4) COMMENT 'Provider match rate for exported members (0..1); NULL if the destination does not report one.',

  -- Sync semantics + delete-propagation audit (do-not-sell / DSAR retraction). A CDP
  -- activation is not only an additive push: a suppressed/erased member must also be
  -- RETRACTED from a destination they were previously exported to. sync_mode names the
  -- operation and removed_member_count records the retraction so that propagation is auditable.
  sync_mode               STRING COMMENT 'The write operation this run performed against the destination audience. Allowed values: full_refresh, incremental_upsert, delete_only. delete_only / the delete leg of an upsert is how do-not-sell / DSAR retractions propagate.',
  removed_member_count    BIGINT COMMENT 'Members RETRACTED from the destination this run (do-not-sell / DSAR / newly-suppressed members removed from a prior export) (>= 0). NULL if the run did not retract (e.g. a first full_refresh).',
  -- Destination-side outcome split: exported = handed to the destination; the destination
  -- may then accept or reject some (bad key, opt-out on its side). delivered + rejected
  -- cannot exceed exported (they sum to it only when the provider reports every per-member
  -- outcome; a partial report leaves the remainder unclassified). Bounded by aj_counts_monotonic.
  delivered_member_count  BIGINT COMMENT 'Exported members the destination ACCEPTED / delivered (>= 0, <= exported_member_count). NULL if the destination reports no accept/reject split.',
  rejected_member_count   BIGINT COMMENT 'Exported members the destination REJECTED (bad key, provider-side opt-out, format error) (>= 0, <= exported_member_count). NULL if not reported.',
  -- Run-lifecycle telemetry (latency / freshness): job_run_ts is the run instant; these
  -- bound the actual execution window so adopters can monitor sync latency and freshness.
  job_started_ts          TIMESTAMP COMMENT 'When the run STARTED executing (UTC, ISO 8601); NULL if not captured. With job_completed_ts gives run duration / freshness.',
  job_completed_ts        TIMESTAMP COMMENT 'When the run FINISHED (UTC, ISO 8601); NULL while in-flight or if not captured.',
  -- Gate-provenance flags: assert the consent gate was actually applied for this run, so a
  -- run that bypassed the gate (or ran on a plane the gate does not cover) is observable.
  is_consent_enforced_flag  BOOLEAN COMMENT 'Three-valued, and the states are distinct (do not conflate FALSE with NULL). TRUE = the eligible slice for this run was produced by the consent gate (gold_activatable_audience_current), which anti-joins the do-not-target view by construction, so TRUE REQUIRES is_suppression_applied_flag = TRUE (enforced by aj_consent_implies_suppression). FALSE = the adopter ASSERTS the gate was NOT the source (a plane the gate does not evaluate; see RECONCILIATION SCOPE) — the strongest scrutinize-this-run signal. NULL = provenance simply not recorded (unknown), weaker than FALSE but still not gate-attested. Audit consumers should treat FALSE and NULL separately.',
  is_suppression_applied_flag BOOLEAN COMMENT 'TRUE if person-level do-not-target suppression (gold_person_do_not_target_current, ADR 0028) was consulted for this run. On non-owned/paid planes this must be TRUE for the run to be compliant with the cross-plane do-not-contact contract.',

  destination_audience_ref STRING COMMENT 'The provider-side audience identifier returned by the destination (vendor-neutral, no PII, no member lists).',
  failure_reason_code   STRING COMMENT 'Why a failed/partial run did not complete. Allowed values: none, auth_error, quota_exceeded, schema_mismatch, consent_block, provider_error, timeout.',
  model_version         STRING COMMENT 'Version of the activation job runner / rule set that produced this run (audit / reproducibility). NULL if not applicable.',

  -- Audit / provenance (append-only fact block; all timestamps UTC)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_activation_job PRIMARY KEY (activation_job_sk)
)
USING DELTA
-- Cluster by destination then run date: the common read is "runs to destination X over time".
CLUSTER BY (activation_destination_id, job_run_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Unified Customer View — activation/export run audit fact (append-only). Records each audience-to-destination publish and its consent-gate counts; the gate itself is gold_activatable_audience_current.';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${ucv_schema}.activation_job SET TAGS ('dbx_data_type' = 'transactional');
