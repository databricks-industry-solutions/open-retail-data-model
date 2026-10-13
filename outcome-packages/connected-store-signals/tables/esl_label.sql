-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: esl_label
-- Layer: outcome package (gold / dimensional, master-tagged)
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- License: see repository LICENSE.md
-- ============================================================
-- Registry of electronic shelf label ENDPOINTS: the addressable e-ink/LCD price tags
-- below a gateway. A DEDICATED dimension, not sensor_device rows (owner-adjudicated,
-- design note §10): labels number thousands per store versus dozens of devices, their
-- attributes diverge from calibration-class sensors, and SCD2 churn at label scale
-- would bloat the shared device registry. The GATEWAY is the sensor_device
-- (device_type = esl_gateway, device_role actuate/both); labels hang off it by FK —
-- one registry principle preserved at the device tier.
--
-- Battery LEVEL is fast-moving telemetry (device-health gold); battery CAPABILITY
-- (expected life class) is registry data and lives here.
--
-- This table records display endpoints only. What a label DISPLAYED is the
-- append-only esl_price_observation fact; no price command, schedule, or campaign
-- entity exists in the open model (ADR 0041, extending ADR 0030).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.esl_label (
  esl_label_sk          BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  esl_label_id          STRING NOT NULL
                          COMMENT 'Durable label endpoint identifier (vendor serial or platform label id, vendor-neutral form).',

  store_sk              BIGINT NOT NULL COMMENT 'FK to the store version in effect when this version was written.',
  store_id              STRING NOT NULL COMMENT 'Durable store business key.',
  sensor_device_sk      BIGINT NOT NULL COMMENT 'FK to the gateway/access-point device version this label is homed to (sensor_device.device_type = esl_gateway).',
  sensor_device_id      STRING NOT NULL COMMENT 'Durable gateway device business key.',

  display_technology    STRING COMMENT 'Display hardware class. Allowed values: eink_mono, eink_multicolor, lcd, segment.',
  display_model         STRING COMMENT 'Vendor-neutral model designation for the endpoint hardware.',
  display_size_inches   DOUBLE COMMENT 'Diagonal display size in inches.',
  battery_life_class    STRING COMMENT 'Expected battery lifetime class from the vendor specification. Allowed values: under_3y, y3_to_5, y5_to_10, over_10y. Battery LEVEL is telemetry, not registry.',
  is_nfc_capable        BOOLEAN COMMENT 'TRUE when the endpoint carries an NFC touchpoint. Shopper NFC interactions are out of Smart Shelf scope (interaction domain).',
  is_qr_capable         BOOLEAN COMMENT 'TRUE when the endpoint can render QR / GS1 Digital Link codes (Sunrise 2027 estate).',

  label_status          STRING COMMENT 'Allowed values: active, inactive, faulty, retired.',
  commissioned_date     DATE   COMMENT 'When the endpoint entered service.',
  decommissioned_date   DATE   COMMENT 'When the endpoint left service. NULL while in service.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_esl_label PRIMARY KEY (esl_label_sk)
)
USING DELTA
CLUSTER BY (esl_label_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals ESL endpoint registry (SCD2): display capability and gateway homing for electronic shelf labels. Displayed state lives in esl_price_observation; no actuation surface (ADR 0041).';

ALTER TABLE ${catalog}.${css_schema}.esl_label SET TAGS ('dbx_data_type' = 'master');
