-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: esl_label_assignment
-- Layer: outcome package (gold / dimensional, association-tagged)
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- License: see repository LICENSE.md
-- ============================================================
-- The label ↔ product ↔ position BINDING lifecycle: pair, unassign, replace, verify.
-- A first-class slowly changing relationship, not an attribute on the label — a
-- displayed price is only attributable to a product BECAUSE a binding was current at
-- the observation instant, and audits ask for the binding that applied AT THE TIME.
--
-- One label displays one product at a time: at most one current binding per
-- esl_label_id (esla_one_current_per_label, error severity, cross-row so it lives in
-- checks.sql not Delta).
--
-- GTIN and GS1 Digital Link URI live here, on the binding: they are the shelf-edge
-- join keys of the Sunrise 2027 estate and belong to the label-product pairing, not
-- to either endpoint alone.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.esl_label_assignment (
  esl_label_assignment_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  esl_label_assignment_id STRING NOT NULL
                          COMMENT 'Durable binding key: esl_label_id|product_id|store_zone_id. Re-pairing the same triple resumes the same durable identity with a new version.',

  esl_label_sk          BIGINT NOT NULL COMMENT 'FK to the label endpoint version bound.',
  esl_label_id          STRING NOT NULL COMMENT 'Durable label endpoint identifier.',
  product_sk            BIGINT NOT NULL COMMENT 'FK to the product version in effect when this version was written.',
  product_id            STRING NOT NULL COMMENT 'Durable product business key this label displays.',
  store_sk              BIGINT NOT NULL COMMENT 'FK to the store version in effect when this version was written.',
  store_id              STRING NOT NULL COMMENT 'Durable store business key.',
  store_zone_sk         BIGINT NOT NULL COMMENT 'FK to the shelf-position zone version where the bound label is placed.',
  store_zone_id         STRING NOT NULL COMMENT 'Durable shelf-position zone id of the label placement.',

  encoded_gtin          STRING COMMENT 'The GTIN as ENCODED at the shelf edge for this binding — a snapshot of what the label carries, not an identity authority. Core product.gtin remains authoritative; a warn-severity check surfaces disagreement, because a wrong encoding is exactly the shelf-edge defect this layer exists to catch (Sunrise 2027 join key).',
  encoded_digital_link_uri STRING COMMENT 'The GS1 Digital Link URI as RENDERED by the label where qr_capable — shelf-edge snapshot, same authority rule as encoded_gtin (Sunrise 2027 lead syntax).',

  binding_source        STRING COMMENT 'How the binding was made. Allowed values: platform, manual.',
  is_binding_verified   BOOLEAN COMMENT 'TRUE when the pairing was verified after assignment (scan-back or platform verification workflow).',
  binding_status        STRING COMMENT 'Allowed values: active, suspended, retired.',

  -- Instant-grained validity. Labels get re-paired DURING the trading day (reset,
  -- replacement, verification workflows), and a displayed-price observation attributes
  -- through the binding current at an exact UTC instant — date-grained SCD2 alone makes
  -- a same-day rebind ambiguous.
  valid_from_ts         TIMESTAMP NOT NULL COMMENT 'Inclusive UTC instant this binding version took effect. The version grain key.',
  valid_to_ts           TIMESTAMP COMMENT 'Exclusive UTC instant this binding stopped applying; NULL for the current version.',

  -- SCD2 versioning (principle #8) — repo-standard date columns, DERIVED from the
  -- instant validity above; kept so the binding reads like every other master in
  -- date-grained tooling.
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective. Derived: CAST(valid_from_ts AS DATE).',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version. Derived from valid_to_ts.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_esl_label_assignment PRIMARY KEY (esl_label_assignment_sk)
)
USING DELTA
CLUSTER BY (esl_label_assignment_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals ESL binding lifecycle (SCD2): label × product × shelf-position pairing that makes a displayed price attributable. At most one current binding per label (DQ-enforced).';

ALTER TABLE ${catalog}.${css_schema}.esl_label_assignment SET TAGS ('dbx_data_type' = 'association');
