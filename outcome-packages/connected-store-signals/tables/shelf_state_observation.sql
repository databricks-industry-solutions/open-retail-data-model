-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: shelf_state_observation
-- Layer: outcome package (gold / restatable observation fact)
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- License: see repository LICENSE.md
-- ============================================================
-- The OBSERVED state of one product at one shelf-position zone from one capture by one
-- sensing platform (fixed weight shelf, fixed camera, or mobile/robot CV sweep).
-- Multi-measure positional state — facings, unit estimate, weight, since-prior
-- pick/put activity — with status flags and per-row quality.
--
-- TWO-ROW MISPLACEMENT MODEL: one physical capture may yield SEVERAL product rows
-- sharing its source_capture_id. Expected product absent from its position -> an
-- out_of_stock row for THAT product; a wrong product detected at the position -> a
-- misplaced row for the DETECTED product whose captured assignment names the violated
-- expectation (assignment product <> row product is the definition of misplacement).
-- Position expects cereal, detergent found: cereal row out_of_stock + detergent row
-- misplaced, same source_capture_id — both the missing and the wrong product stay
-- discoverable. BOTH ROWS ARE MANDATORY: the publishing pipeline synthesizes the
-- expected-product row even from detections-only platforms (it knows the expected
-- product from the violated assignment). Enforced at error severity by
-- sso_misplaced_sibling_present.
--
-- OUTSIDE THE ENVELOPE (ADR 0039, on ADR 0036 precedent): the envelope's scalar
-- one-subject contract cannot carry (facings × product × position × flags) without
-- composite subject identifiers that erode its EPCIS-shaped auditability. This fact
-- reuses the envelope's CONTRACTS — UTC-instant time with store-local derivations, the
-- two orthogonal quality axes, restatement columns, Bronze raw pointers — without
-- inserting envelope rows. Slot-scoped interval series remain the reserved tri-party
-- seam (ADR 0036); pick/put_count_since_prior are nullable and additively supersedable
-- when that seam lands.
--
-- RESTATABLE, not append-only: CV pipelines re-infer past captures when models are
-- retrained; restatement_version and restated_at_timestamp mirror the envelope.
--
-- KEY (ADR 0028 — hash surrogate keys for high-volume gold facts):
-- xxhash64(shelf_state_observation_id), durable id authoritative,
-- sso_sk_collision at error severity. The identity component is the SOURCE CAPTURE ID,
-- deliberately not timestamp-to-the-second: a restatable CV fact re-inferred from the
-- same capture must restate the SAME row (an epoch-second id would duplicate on a
-- shifted timestamp and collide on same-second double captures). ADR 0028's epoch-space
-- rule governs ids where a timestamp IS a grain component — here it is not one.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.shelf_state_observation (
  shelf_state_observation_sk BIGINT NOT NULL
                       COMMENT 'Surrogate join key: xxhash64(shelf_state_observation_id). The durable id is authoritative and collision-guarded.',
  shelf_state_observation_id STRING NOT NULL
                       COMMENT 'Durable grain key: store_zone_id|product_id|sensor_device_id|source_capture_id. product_id uses the _ALL sentinel only for a position-level capture that cannot resolve a product.',
  source_capture_id  STRING NOT NULL
                       COMMENT 'Platform identifier for the physical capture (CV frame/inference id, weight-event window id, sweep-pass segment). Groups the several product rows one capture may yield (two-row misplacement model) and keeps restatement idempotent under CV re-inference.',

  shelf_position_assignment_sk BIGINT COMMENT 'FK to the expected-state assignment version in effect at observation time. NULL only when the position had no current assignment.',
  shelf_position_assignment_id STRING COMMENT 'Durable assignment key captured at observation time, so compliance stays evaluable after the assignment re-versions (ADR 0025).',

  store_sk           BIGINT NOT NULL COMMENT 'FK to the store version in effect at observation time.',
  store_id           STRING NOT NULL COMMENT 'Durable store business key.',
  store_zone_sk      BIGINT NOT NULL COMMENT 'FK to the shelf-position zone version observed.',
  store_zone_id      STRING NOT NULL COMMENT 'Durable shelf-position zone id (store_zone.zone_type = shelf_position).',
  product_sk         BIGINT COMMENT 'Product version resolved at write. NULL when product_id carries the _ALL sentinel or resolution failed.',
  product_id         STRING NOT NULL COMMENT 'Durable product business key observed or expected at this position; _ALL sentinel for unresolved position-level captures.',
  sensor_device_sk   BIGINT NOT NULL COMMENT 'FK to the capturing device version in effect at observation time.',
  sensor_device_id   STRING NOT NULL COMMENT 'Durable capturing device business key. Provenance is part of identity: two platforms may observe the same position at the same instant.',
  sensing_deployment_sk BIGINT NOT NULL COMMENT 'FK to the governing sensing deployment version (ADR 0031).',
  sensing_deployment_id STRING NOT NULL COMMENT 'Durable sensing deployment business key.',

  observation_ts      TIMESTAMP NOT NULL COMMENT 'Capture or sweep-completion instant as UTC. Observations are instants, not intervals; cadence gaps are measured in gold, never imputed here.',
  store_timezone      STRING COMMENT 'IANA store timezone used to derive local business fields.',
  utc_offset_minutes  SMALLINT NOT NULL COMMENT 'Store UTC offset in minutes at observation_ts.',
  trading_date        DATE NOT NULL COMMENT 'Business date of observation_ts. Logical join to fiscal_calendar.date_key.',
  hour_of_day         TINYINT COMMENT 'Store-local observation hour, 0 through 23.',

  shelf_state         STRING NOT NULL COMMENT 'Evaluated state at capture: in_stock, low_stock, out_of_stock, misplaced, unknown. low_stock uses min_facing_threshold recorded on this row; misplaced means the product on THIS row was detected at a position assigned to a different product (the captured assignment names the violated expectation); unknown means the platform could not evaluate and all measures are NULL, never zero.',
  observed_facing_count INT COMMENT 'Facings visibly presented at capture. NULL when shelf_state = unknown.',
  min_facing_threshold  INT COMMENT 'The assignment min_facing_count evaluated at write, recorded so the low_stock classification stays explainable after the assignment re-versions.',
  estimated_unit_count  DOUBLE COMMENT 'Weight-derived unit estimate (total weight / calibrated per-SKU unit weight). An estimate carrying uncertainty, not a count; NULL for platforms without declared unit-estimation capability.',
  estimated_weight_grams DOUBLE COMMENT 'Observed net weight in grams. NULL for non-weight platforms.',
  pick_count_since_prior INT COMMENT 'Pick events since the prior capture of this position by this device. NULL for platforms that cannot detect events (mirrors ftid_nondirectional_exits_null honesty). Raw events stay in Bronze behind raw_data_uri.',
  put_count_since_prior  INT COMMENT 'Putback events since the prior capture of this position by this device. NULL for platforms that cannot detect events.',

  is_gap_detected     BOOLEAN COMMENT 'TRUE when the platform flagged a visible gap/void at this position.',
  is_misplaced_detected BOOLEAN COMMENT 'On an expected-product row: TRUE when something else was detected sitting at this position (the detected product gets its own misplaced-state row sharing this source_capture_id).',
  is_price_tag_mismatch_detected BOOLEAN COMMENT 'TRUE when shelf CV flagged the displayed price tag against the expected one. Bridges to the ESL layer; the authoritative price comparison lives in esl_price_observation.',

  zone_source         STRING NOT NULL COMMENT 'How the position zone was attributed: device_placement, operator_declared, platform_localization. Fixed sensors use device_placement; robot sweeps use platform_localization (RFID vocabulary reused).',
  attribution_confidence DOUBLE NOT NULL COMMENT 'Confidence in assigning the capture to the stated position zone, in [0,1]. 1.0 for fixed device placement.',

  measurement_validity  STRING COMMENT 'Was the sensor telling the truth. Allowed values: valid, degraded, invalid, imputed. Occluded captures are never valid.',
  arrival_completeness  STRING COMMENT 'Has the data landed. Allowed values: complete, incomplete, late_arrived, precheck.',
  confidence_score      DOUBLE COMMENT 'Detector confidence for this capture, [0,1], where supplied.',
  is_occluded           BOOLEAN COMMENT 'TRUE when the view of the position was blocked at capture (CV platforms).',
  coverage_ratio        DOUBLE COMMENT 'Fraction of the expected extent for this position actually observed in this capture, [0,1]. Matters most for mobile sweeps with partial coverage.',

  restatement_version   INT COMMENT 'Monotonic per grain key. CV pipelines re-infer past captures after model retrains; this fact is restatable, not append-only.',
  restated_at_timestamp TIMESTAMP COMMENT 'When this version of the row was written (UTC). NULL for the first version.',

  raw_data_uri        STRING COMMENT 'Pointer to raw capture evidence (image crops, weight event stream) in Bronze, outside ORDM.',
  ingest_timestamp    TIMESTAMP COMMENT 'When the observation arrived in the lakehouse (UTC).',
  record_source       STRING COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp      TIMESTAMP COMMENT 'When this row was loaded (UTC).',

  CONSTRAINT pk_shelf_state_observation PRIMARY KEY (shelf_state_observation_sk)
)
USING DELTA
CLUSTER BY (trading_date, store_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals restatable positional shelf-state fact at shelf-position zone × product × capture instant × device grain. Outside the sensor_report_interval envelope by design (ADR 0039 / ADR 0036).';

ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation SET TAGS ('dbx_data_type' = 'transactional');
