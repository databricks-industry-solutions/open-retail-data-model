-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- Table: customer_profile_snapshot
-- Layer: outcome package (gold / extension table)
-- Version: 0.5
-- Generated: 2026-07-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-10
-- ============================================================
-- Append-only point-in-time snapshot of a customer's unified-view state:
-- identity, consent, preference, and household roll-ups captured at a
-- moment in time. Supports audit, model reproducibility, and pre-campaign
-- readiness (freeze the eligible population before an activation run).
--
-- Grain: one row per profile per snapshot_date (append-only fact; no SCD2).
-- Keyed on the customer SURROGATE; carries only DERIVED aggregates and NO
-- raw PII (no names / loyalty / household identifiers) — those stay in the
-- governed canonical-core customer dimension.
--
-- All measures here are roll-ups of the thin customer core
-- (profile, identity_link, consent, channel_preference, household). Behavioral,
-- commerce, and segment/audience columns from the source briefs are
-- deliberately omitted — they need data outside the thin core (deferred).
--
-- Producer: this is an ADOPTER-OWNED append. ORDM ships the table + the DQ
-- contract, not a synthetic producer — a snapshot is a point-in-time freeze the
-- adopter's activation/ETL job writes on its own cadence (there is no
-- deterministic seed to reproduce). The `cps_*` checks in checks.sql are
-- therefore SCHEMA / CONTRACT GUARDS: they validate whatever rows the adopter
-- appends (and pass vacuously on an empty table by design), not a shipped dataset.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ucv_schema}.customer_profile_snapshot (
  customer_profile_snapshot_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per snapshot row.',
  customer_profile_snapshot_id STRING NOT NULL
                          COMMENT 'Durable business key for the snapshot (e.g. profile_id + snapshot_date).',

  -- Resolved customer (FK to canonical-core profile)
  profile_sk            BIGINT COMMENT 'FK to customer.profile.profile_sk (the profile version snapshotted).',
  profile_id            STRING NOT NULL
                          COMMENT 'Durable business key of the customer (pseudonymous; not a name).',

  snapshot_date         DATE   NOT NULL COMMENT 'Business date this snapshot represents (ISO 8601 date). Part of the grain.',
  snapshot_reason_code  STRING COMMENT 'Why the snapshot was taken. Allowed values: scheduled, pre_campaign, ad_hoc, audit.',

  -- Identity roll-ups (from identity_link)
  active_identifier_count      INT COMMENT 'Count of current, active resolved identifiers mapped to this profile.',
  resolved_identity_confidence DECIMAL(5,4) COMMENT 'Summary identity-resolution confidence in [0,1] over active links (max/weighted).',

  -- Consent + preference roll-ups (from consent, channel_preference)
  consented_channel_count      INT COMMENT 'Count of channels with a current granted consent for this profile.',

  -- Household roll-up (from household membership; the count deferred off the master)
  household_size               INT COMMENT 'Number of profiles currently sharing this household (outcome-layer roll-up).',

  -- Readiness scores (derived; explainable, not ML)
  profile_completeness_score   DECIMAL(5,4) COMMENT 'Populated required attributes / required attributes, in [0,1].',
  reachability_score           DECIMAL(5,4) COMMENT 'Activation-readiness across channels (consent + preference + identifier presence), in [0,1].',

  customer_status_code         STRING COMMENT 'Lifecycle status snapshotted from profile. Allowed values: prospect, active, inactive, closed.',

  -- Audit / provenance (standard block; all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_customer_profile_snapshot PRIMARY KEY (customer_profile_snapshot_sk)
)
USING DELTA
CLUSTER BY (profile_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Unified Customer View — append-only per-customer snapshot of identity/consent/preference/household roll-ups (no raw PII).';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${ucv_schema}.customer_profile_snapshot SET TAGS ('dbx_data_type' = 'transactional');
