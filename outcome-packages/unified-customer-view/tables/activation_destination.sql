-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- Table: activation_destination
-- Layer: outcome package (gold reference dimension)
-- Version: 0.5
-- Generated: 2026-07-24
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-24
-- ============================================================
-- The destination-connector CATALOG: one governed row per place an activatable
-- audience can be published (reverse-ETL / CDP activation platform, ad-platform
-- audience upload, ESP/SMS, clean room, file export). A DEFINITION/config catalog
-- only — never member lists, never the runs themselves (activation runs are the
-- activation_job fact; membership is ACU segment_membership).
--
-- Completes the CDP activation layer (ADR 0026) on top of the shipped targeting +
-- gating half: marketing.audience (what is published), ACU segment_membership (who),
-- and UCV gold_activatable_audience_current (who may be contacted — the consent gate).
-- This table names WHERE a job publishes; activation_job records each run.
--
-- Per-destination consent semantics live here as attributes: required_consent_purpose
-- + required_channel declare the purpose×channel a job to this destination must gate
-- on, so the fail-closed enforcement in gold_activatable_audience_current is
-- destination-aware. This is config, not enforcement — the gate is still the view.
--
-- Grain: one row per destination connector (activation_destination_id). A small,
-- static lookup (Type 1; no SCD) — a run's point-in-time purpose/channel is captured
-- on the activation_job fact, so the catalog does not version. No metrics on the
-- reference (principle #9): run counts / match rates are the activation_job fact.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ucv_schema}.activation_destination (
  activation_destination_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  activation_destination_id STRING NOT NULL
                          COMMENT 'Durable business key / destination-connector code (e.g., dsp_ca_prod, esp_01). The stable key activation_job references and reverse-ETL diffs on.',

  destination_name        STRING COMMENT 'Human-readable destination name.',
  destination_platform    STRING COMMENT 'The activation platform (free text, adopter-defined — vendor-neutral schema, so no CHECK enum). Categorical examples: a DSP, a social platform, a search/ad platform, a retail-media network, a data onboarder / identity-resolution provider, an ESP, an SMS gateway, a push service, a clean room, object storage, or a custom webhook.',
  connector_kind          STRING COMMENT 'How audiences reach the destination. Allowed values: reverse_etl, api_push, file_export, clean_room_match, managed_connector.',
  match_key_type          STRING COMMENT 'The identity key this destination is synced on (governs which hashed identifier a job exports). Allowed values: email_hash, phone_hash, maid, people_based_id, platform_user_id, custom_audience_id, first_party_id.',
  required_consent_purpose STRING COMMENT 'The marketing purpose a job to this destination must gate on (joins the eligibility gate purpose). NULL = not purpose-constrained (a multi-purpose destination; the aj_destination_purpose_channel_match check does not fire). Allowed values: marketing, personalization, analytics, retail_media, data_sale, service.',
  required_channel        STRING COMMENT 'The channel a job to this destination activates on (joins the eligibility gate channel; the consent-channel values email/sms/phone/postal align with the gate, the rest are non-gated channels). NULL = not channel-constrained (a multi-channel destination such as an ESP; the match check does not fire). Allowed values: email, sms, phone, postal, push, web, in_app, ctv, social, display, search.',
  data_residency_region   STRING COMMENT 'Region the destination processes data in, for residency governance (ISO 3166-1 alpha-2 or a region label; NULL if not constrained).',
  is_addressable_flag     BOOLEAN COMMENT 'TRUE if the destination currently accepts audience publishes (a disabled connector stays in the catalog for lineage but is not addressable).',
  owner_team              STRING COMMENT 'Vendor-neutral label of the team that owns/operates this connector.',

  -- Audit / provenance (standard block; required on reference tables, standard §8)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_activation_destination PRIMARY KEY (activation_destination_sk)
)
USING DELTA
CLUSTER BY (activation_destination_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Unified Customer View — activation destination connector catalog (Type 1). The single source of truth for where an activatable audience can publish; runs are the activation_job fact.';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${ucv_schema}.activation_destination SET TAGS ('dbx_data_type' = 'reference');
