-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: foot_traffic_interval_detail
-- Layer: outcome package (gold / interval fact extension)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- One-to-one detail for a sensor_report_interval whose report_type is gs1:Count and
-- subject_type is space. The shared interval key is both this table's primary key and
-- its foreign key, so the extension cannot acquire an independent grain.
--
-- Counts remain operational truth here. Disclosure control is applied only by the
-- explicitly shared gold projections, never at write time.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.foot_traffic_interval_detail (
  sensor_report_interval_sk BIGINT NOT NULL
      COMMENT 'PK and FK to sensor_report_interval.sensor_report_interval_sk. Exactly one detail row is required for each gs1:Count interval.',

  footfall_count        BIGINT COMMENT 'Headline footfall for the interval at the envelope aggregation_level.',
  entry_count           BIGINT COMMENT 'Measured entries.',
  exit_count            BIGINT COMMENT 'Measured exits. NULL, never zero, for a non-directional device.',
  passersby_count       BIGINT COMMENT 'Pass-by traffic interpreted per passby_convention.',
  unique_visitor_count  BIGINT COMMENT 'De-duplicated visitors where supported. Not additive across intervals.',
  is_zero_observed      BOOLEAN COMMENT 'TRUE for a measured zero, distinct from an absent row or offline source.',

  counting_unit         STRING COMMENT 'What one count represents: person, group, device, or object.',
  group_counting_enabled BOOLEAN COMMENT 'TRUE when family or shopping groups are counted as one.',
  unique_visitor_enabled BOOLEAN COMMENT 'TRUE when repeat entries in the configured window are de-duplicated.',
  child_counting_enabled BOOLEAN COMMENT 'TRUE when children are counted.',
  child_height_threshold_cm INT COMMENT 'Effective height threshold separating child from adult.',
  staff_exclusion_enabled BOOLEAN COMMENT 'TRUE when staff are excluded from the published operational footfall.',
  directionality        STRING COMMENT 'Allowed values: bidirectional, unidirectional, none.',
  count_divisor         INT COMMENT 'Configured beam-count divisor; never assume a fixed value.',
  passby_convention     STRING COMMENT 'Allowed values: includes_entrants, excludes_entrants.',

  visitor_count_raw     BIGINT COMMENT 'Count before staff adjustment.',
  staff_count           BIGINT COMMENT 'Staff detections identified in the interval.',
  child_count           BIGINT COMMENT 'Child detections; a subset of footfall_count.',
  visitor_count_adjusted BIGINT COMMENT 'Count after staff adjustment.',
  staff_adjustment_applied BOOLEAN COMMENT 'TRUE when an adjustment was applied to this row.',
  staff_exclusion_method STRING COMMENT 'Method used to exclude staff.',
  staff_exclusion_stage STRING COMMENT 'Allowed values: none, at_sensor, at_aggregation.',
  staff_exclusion_grade STRING COMMENT 'Published accuracy band: high, medium, or low.',

  occupancy_snapshot_end BIGINT COMMENT 'Occupancy at interval end. Semi-additive: take the latest value.',
  occupancy_min         BIGINT COMMENT 'Minimum occupancy observed in the interval.',
  occupancy_max         BIGINT COMMENT 'Maximum occupancy observed in the interval.',
  occupancy_avg         DOUBLE COMMENT 'Mean occupancy in the interval. Roll up weighted by interval duration.',
  cumulative_entries    BIGINT COMMENT 'Running entries since the most recent reset.',
  cumulative_exits      BIGINT COMMENT 'Running exits since the most recent reset.',
  occupancy_adjustment  INT COMMENT 'Signed manual or reconciliation correction.',
  adjustment_source     STRING COMMENT 'Allowed values: manual, reset, reconciliation, vendor_correction.',
  last_reset_local_ts   TIMESTAMP COMMENT 'Source-local timestamp of the most recent cumulative-counter reset.',

  dwell_seconds_total   BIGINT COMMENT 'Sum of dwell seconds across observations; the re-aggregatable numerator.',
  dwell_count           BIGINT COMMENT 'Number of dwell observations; the re-aggregatable denominator.',
  engaged_count         BIGINT COMMENT 'Dwell observations at or above the configured engagement threshold.',
  passing_count         BIGINT COMMENT 'Dwell observations below the configured engagement threshold.',
  engagement_threshold_seconds INT COMMENT 'Threshold separating engaged and passing dwell observations.',

  CONSTRAINT pk_foot_traffic_interval_detail
    PRIMARY KEY (sensor_report_interval_sk)
)
USING DELTA
CLUSTER BY (sensor_report_interval_sk)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals -- one-to-one Foot Traffic measures for a canonical sensor report interval.';

ALTER TABLE ${catalog}.${css_schema}.foot_traffic_interval_detail
  SET TAGS ('dbx_data_type' = 'transactional');
