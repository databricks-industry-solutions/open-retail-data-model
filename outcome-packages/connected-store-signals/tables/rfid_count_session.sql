-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: rfid_count_session
-- Layer: outcome package (gold / transactional header)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- One bounded RFID count session. The header is written before or in the same
-- batch as its events. It carries identity and the honest full_store/partial
-- scope claim; observed units and zone coverage are derived from read events.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.rfid_count_session (
  rfid_count_session_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key for the bounded RFID count session.',
  rfid_count_session_id STRING NOT NULL
                          COMMENT 'Durable key: store_id|source_session_id.',
  source_session_id     STRING NOT NULL
                          COMMENT 'Source session identifier. For fixed windows without one: count_method|primary sensor_device_id or _ALL|unix_timestamp(started_at_ts).',

  store_sk              BIGINT NOT NULL COMMENT 'FK to store.store_sk.',
  store_id              STRING NOT NULL COMMENT 'Durable store business key.',
  primary_sensor_device_sk BIGINT COMMENT 'Nullable FK to the initiating or primary sensor_device version. The complete device set derives from events.',
  primary_sensor_device_id STRING COMMENT 'Durable id of the initiating or primary device.',

  count_method          STRING NOT NULL COMMENT 'RFID count method. Allowed values: handheld_sweep, fixed_window, robot_sweep.',
  scope_type            STRING NOT NULL COMMENT 'Representable scope claim. full_store has a derivable zone plan; partial makes no plan claim.',
  started_at_ts         TIMESTAMP NOT NULL COMMENT 'Session start as a UTC instant.',
  ended_at_ts           TIMESTAMP NOT NULL COMMENT 'Session end as a UTC instant.',
  store_timezone        STRING COMMENT 'IANA store timezone used to derive trading_date and hour_of_day.',
  utc_offset_minutes    SMALLINT NOT NULL COMMENT 'Store UTC offset in minutes at started_at_ts.',
  trading_date          DATE NOT NULL COMMENT 'Business date of the session start; logical join to fiscal_calendar.date_key, enforced by rcs_calendar_orphan.',
  hour_of_day           TINYINT COMMENT 'Store-local hour at session start, 0 through 23.',

  raw_data_uri          STRING COMMENT 'Optional pointer to the source session manifest in Bronze.',
  ingest_timestamp      TIMESTAMP COMMENT 'When the session header arrived in the lakehouse (UTC).',
  record_source         STRING COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC).',

  CONSTRAINT pk_rfid_count_session PRIMARY KEY (rfid_count_session_sk)
)
USING DELTA
CLUSTER BY (store_id, started_at_ts)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals bounded RFID count-session header; coverage and census are derived from linked read events.';

ALTER TABLE ${catalog}.${css_schema}.rfid_count_session SET TAGS ('dbx_data_type' = 'transactional');
