-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: sensor_report_interval
-- Layer: outcome package (gold / interval aggregate fact)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- The shared interval envelope for Connected Store Signals. One aggregated measurement
-- of one report_type over one subject over one interval. Type-specific, additive
-- measures live in one-to-one extension tables; Foot Traffic is the first extension.
-- ADR 0032.
--
-- This entity was RELOCATED from commerce-media-networks.store_zone_interval and
-- generalised in the same move (ADR 0033). CMN reads it back cross-package via
-- gold<->gold (ADR 0024) through commerce-media-networks/gold/store_zone_interval.sql,
-- which reproduces the retired column shape for one release.
--
-- This table deliberately contains only fields reusable across the Foot Traffic, IoT
-- Sensor Monitoring, RFID Tracking, and Smart Shelf solutions. A gs1:Count row must
-- have exactly one foot_traffic_interval_detail row; non-count reports must not have
-- one. Those contracts are enforced in checks.sql.
--
-- KEY: xxhash64 of the durable id, NOT IDENTITY (ADR 0028 — Hash surrogate keys for
-- high-volume gold event facts). Databricks documents that
-- "declaring an identity column on a Delta Lake table disables concurrent
-- transactions". This table is also RESTATED on late arrival, so a recomputable key is
-- what makes restatement idempotent -- a monotonic IDENTITY would change on every
-- recomputation of the same logical row.
--
-- TIME: the UTC instant plus IANA zone plus utc_offset_minutes. There is deliberately
-- NO store-local timestamp column: Databricks TIMESTAMP is TIMESTAMP_LTZ, normalised
-- to UTC on write and rendered in the READER's session timezone, so storing local
-- wall-clock in it means the value shifts per consumer -- silently breaking the exact
-- semantics the column would exist to provide. TIMESTAMP_NTZ is the correct type but
-- is Public Preview, needs a table-feature protocol upgrade, and has zero precedent in
-- this repo. Local time is rendered in the gold layer.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.sensor_report_interval (
  -- ---------- Keys (CSS-KEY-CONTRACT, ADR 0028 — Hash surrogate keys for high-volume gold event facts) ----------
  sensor_report_interval_sk BIGINT NOT NULL
                          COMMENT 'Surrogate key: xxhash64(sensor_report_interval_id). NOT an identity column -- see ADR 0028, Hash surrogate keys for high-volume gold event facts. The durable _id is the authoritative key; this is a join convenience guarded by sri_sk_collision.',
  sensor_report_interval_id STRING NOT NULL
                          COMMENT 'Durable grain key: subject_type|subject_id|report_type|aggregation_level|interval_minutes|unix_timestamp(interval_start_ts)|sensor_device_id. Every namespace and varying grain component is present. The interval is EPOCH SECONDS, not a rendered timestamp: TIMESTAMP is LTZ, so a rendered form would make the durable id depend on the writer session timezone and a restatement under a different zone would insert rather than update.',

  -- ---------- Subject: the EPCIS "What" ----------
  subject_type          STRING NOT NULL COMMENT 'What kind of thing was measured. Allowed values: epc, gln, grai, point, space. Foot traffic is space.',
  subject_id            STRING NOT NULL COMMENT 'Identifier of the measured subject, interpreted per subject_type.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk.',
  store_id              STRING COMMENT 'Durable store business key.',
  store_zone_sk         BIGINT COMMENT 'FK to store_zone.store_zone_sk.',
  store_zone_id         STRING COMMENT 'Durable zone id. The SCD2-safe join key (ADR 0025).',
  product_sk            BIGINT COMMENT 'FK to product.product_sk. NULL for space subjects; populated for item- or shelf-scoped reports.',
  product_id            STRING COMMENT 'Durable product business key. NULL for space subjects.',
  -- The asset dimension, carried on the FACT and not only on sensor_device. Cold-chain rows
  -- are ABOUT a refrigeration unit, so "temperature history for this asset" is the primary
  -- question this table answers for IoT Sensor Monitoring -- and routing it through the
  -- device registry means a sensor re-pointed at a different case rewrites the history of
  -- both. Denormalised here for the same reason store_sk is: the subject of the measurement
  -- belongs to the measurement. NULL for space subjects and for ambient sensing.
  equipment_sk          BIGINT COMMENT 'FK to equipment.equipment_sk when the reported subject is a maintained asset (a refrigeration case, an HVAC unit). NULL for space subjects and ambient sensing.',
  equipment_id          STRING COMMENT 'Durable equipment business key. NULL for space subjects and ambient sensing.',

  -- ---------- Measurement type: CBV sensor-property vocabulary ----------
  report_type           STRING NOT NULL COMMENT 'GS1 CBV sensor-property CURIE. Allowed values: gs1:Count, gs1:Temperature, gs1:RelativeHumidity, gs1:Power, gs1:Energy, gs1:Mass, gs1:Illuminance, gs1:VolumeFraction. Foot traffic is gs1:Count. NOTE there is no CBV type for CO2 -- use gs1:VolumeFraction with the substance identified, never an invented air_quality_co2.',

  -- ---------- Values: the EPCIS sensorReport field set ----------
  value                 DOUBLE COMMENT 'The reported value for report_type over the interval.',
  min_value             DOUBLE COMMENT 'EPCIS minValue over the interval.',
  max_value             DOUBLE COMMENT 'EPCIS maxValue over the interval.',
  mean_value            DOUBLE COMMENT 'EPCIS meanValue over the interval.',
  s_dev                 DOUBLE COMMENT 'EPCIS sDev. Valid only alongside mean_value (sri_epcis_field_pairing).',
  perc_rank             DOUBLE COMMENT 'EPCIS percRank -- the percentile requested.',
  perc_value            DOUBLE COMMENT 'EPCIS percValue -- the value at perc_rank. Valid only alongside perc_rank.',
  string_value          STRING  COMMENT 'EPCIS stringValue, for non-numeric reports.',
  boolean_value         BOOLEAN COMMENT 'EPCIS booleanValue, for binary reports such as door open/closed.',

  -- ---------- Units ----------
  uom                   STRING COMMENT 'UN/CEFACT Recommendation 20 common code, e.g. CEL, KWH, WTT, H87, P1. The interchange form.',
  unit_iri              STRING COMMENT 'QUDT unit IRI. The internal canonical unit reference -- UN/CEFACT codes are ambiguous across contexts, QUDT is not.',

  -- ---------- Additivity (CSS-ADDITIVITY-CONTRACT) ----------
  -- The single most important column for correctness. Footfall DOES NOT SUM ACROSS
  -- ZONES: a shopper traversing five zones is counted five times. One vendor ships
  -- three separate cubes (site/area/device) for exactly this reason, and its
  -- site-level definition is "main entrance only". No vendor publishes a zone-fusion
  -- reconciliation method, because store-level uniqueness needs either entrance-only
  -- counting or whole-store re-identification. Making the level a mandatory grain
  -- column turns "you must not sum these" from documentation into structure.
  aggregation_level     STRING NOT NULL COMMENT 'The level this row is measured AT -- never sum across values of this column. Allowed values: site, entrance, area, device, subject. A store total requires aggregation_level = site, NOT a SUM over area rows.',
  source_observation_count BIGINT COMMENT 'Number of source observations received for this interval. Derived from source cadence and delivery completeness, never from the measured value or shopper count.',
  expected_observation_count BIGINT COMMENT 'Number of source observations expected under the effective source cadence for this interval.',

  -- ---------- Time (CSS-INTERVAL-CONTRACT) ----------
  interval_start_ts     TIMESTAMP NOT NULL COMMENT 'Interval start as a UTC instant. The ONLY safe ordering and join key.',
  interval_end_ts       TIMESTAMP COMMENT 'Interval end as a UTC instant (EPCIS endTime).',
  interval_minutes      INT NOT NULL COMMENT 'Canonical interval length in minutes and part of the grain key. A series has one non-overlapping cadence; alternate vendor rollups remain outside this additive fact.',
  store_timezone        STRING COMMENT 'IANA timezone name, e.g. America/New_York. Not an offset -- the zone, so DST history is derivable.',
  utc_offset_minutes    SMALLINT NOT NULL COMMENT 'Offset from UTC in minutes at interval_start_ts, e.g. -240 vs -300. THE DST FIX: it makes the autumn fold unambiguous, so the duplicated hour yields two distinct rows instead of colliding once a year. No people-counting vendor publishes a DST convention, so this is ours to define.',
  trading_date          DATE NOT NULL COMMENT 'Business date of the interval. Joins to fiscal_calendar.date_key as a LOGICAL join, not an FK -- see relationships.sql.',
  trading_day_offset    SMALLINT COMMENT '-1 / 0 / +1. Non-zero for stores trading past midnight, where the calendar date and the trading date diverge.',
  hour_of_day           INT COMMENT 'Local hour 0-23, derived from interval_start_ts + utc_offset_minutes.',
  day_part              STRING COMMENT 'Allowed values: pre_open, morning, midday, afternoon, evening, late.',
  is_partial_interval   BOOLEAN COMMENT 'TRUE if the interval is not yet closed, or was truncated by opening/closing hours.',
  is_dst_transition     BOOLEAN COMMENT 'Convenience flag for the DST fold/gap. No longer load-bearing now that utc_offset_minutes is present.',
  time_mode             STRING COMMENT 'Allowed values: within_operating_hours, all_day. Vendors expose this per metric rather than per feed, so it belongs on the row.',

  -- ---------- Quality (CSS-QUALITY-CONTRACT) ----------
  -- Two ORTHOGONAL axes, not one score. At least one vendor ships them separately, correctly:
  -- a sensor with batteries removed for 15 minutes produces an interval that is
  -- INVALID BUT COMPLETE; a still-open current interval is VALID BUT INCOMPLETE.
  measurement_validity  STRING COMMENT 'Was the sensor telling the truth. Allowed values: valid, degraded, invalid, imputed.',
  arrival_completeness  STRING COMMENT 'Has the data landed. Allowed values: complete, incomplete, late_arrived, precheck.',
  is_imputed            BOOLEAN COMMENT 'TRUE if the value was modelled rather than measured. Only one surveyed vendor documents that it imputes at all; model it explicitly rather than inheriting it silently.',
  uptime_ratio          DOUBLE COMMENT 'Fraction of the interval the device was online, [0,1].',
  coverage_ratio        DOUBLE COMMENT 'Fraction of the subject expected sensors that reported, [0,1].',
  confidence_score      DOUBLE COMMENT 'Vendor or model confidence, [0,1], where supplied.',
  sensor_online_flag    BOOLEAN COMMENT 'TRUE if the device was online for the interval.',
  is_capped             BOOLEAN COMMENT 'TRUE if the value hit the device detection ceiling. A capped peak is NOT an exact peak.',
  capped_count_limit    INT     COMMENT 'The ceiling that was hit, when is_capped is TRUE.',
  ingest_timestamp      TIMESTAMP COMMENT 'When the row was ingested (UTC). With interval_start_ts this gives arrival latency.',
  latency_seconds       INT     COMMENT 'Seconds between interval end and ingest. Feeds gold_css_device_health.',
  restatement_version   INT     COMMENT 'Monotonic per grain key. These feeds are NOT append-only: vendors publish a late-data status that later resolves, and document sensors checking in with data hours or days old.',
  restated_at_timestamp TIMESTAMP COMMENT 'When this version of the row was written (UTC). NULL for the first version.',

  -- ---------- Provenance: the EPCIS "How" / sensorMetadata ----------
  sensor_device_sk      BIGINT COMMENT 'FK to sensor_device.sensor_device_sk. NULL for a cross-device aggregate.',
  sensor_device_id      STRING COMMENT 'Durable device id, and part of the grain key. A cross-device aggregate uses the explicit sentinel _ALL, NEVER NULL -- a NULL inside a concatenated key silently collapses rows.',
  sensing_deployment_sk BIGINT COMMENT 'FK to sensing_deployment.sensing_deployment_sk -- the governance record that applied at measurement time (ADR 0031).',
  sensing_deployment_id STRING COMMENT 'Durable deployment id. The SCD2-safe join key.',
  device_metadata_uri   STRING COMMENT 'EPCIS deviceMetadata -- calibration and accuracy context for this reading.',
  raw_data_uri          STRING COMMENT 'EPCIS rawData -- pointer to the sub-interval pulses in bronze, outside ORDM. EPCIS itself states it SHOULD NOT carry raw sensor data; this is the sanctioned pattern.',
  data_processing_method_uri STRING COMMENT 'EPCIS dataProcessingMethod -- how raw observations became this aggregate.',
  biz_rules_uri         STRING COMMENT 'EPCIS bizRules -- the threshold or rule that was applied, e.g. the excursion rule version.',

  -- ---------- Interval-level source-message summary ----------
  -- Raw per-message sequence and quality fields remain in Bronze. The aggregate fact
  -- carries only summaries whose grain matches the interval.
  source_session_id         STRING COMMENT 'Source session identifier effective for the interval, when one session covers the interval.',
  source_message_count      BIGINT COMMENT 'Number of source messages delivered for the interval.',
  sequence_gap_count        BIGINT COMMENT 'Number of source messages inferred missing from sequence gaps.',
  duplicate_delivery_count BIGINT COMMENT 'Number of duplicate source-message deliveries in the interval.',
  historical_message_count BIGINT COMMENT 'Number of delivered source messages marked as buffered or historical.',
  bad_quality_message_count BIGINT COMMENT 'Number of delivered source messages carrying bad or stale source quality.',

  -- ---------- Audit / provenance ----------
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_sensor_report_interval PRIMARY KEY (sensor_report_interval_sk)
)
USING DELTA
CLUSTER BY (trading_date, store_id, report_type)
TBLPROPERTIES (
  delta.enableDeletionVectors = true,
  'delta.dataSkippingNumIndexedCols' = '33'
)
COMMENT 'Connected Store Signals -- reusable interval envelope, EPCIS 2.0 sensorReport-shaped and discriminated by report_type + subject_type. Type-specific measures use one-to-one extensions. ADR 0032.';

ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval SET TAGS ('dbx_data_type' = 'transactional');
