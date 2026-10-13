-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: rfid_read_event
-- Layer: outcome package (gold / append-only event fact)
-- Version: 0.5
-- Generated: 2026-08-18
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-19
-- ============================================================
-- One upstream-deduplicated RFID visibility event per EPC × device × UTC second.
-- Sub-second RF pings collapse upstream; last-seen business context wins and raw
-- evidence remains in Bronze. The row is append-only and is never restated.
--
-- KEY (ADR 0028 — Hash surrogate keys for high-volume gold event facts):
-- xxhash64(rfid_read_event_id), with the durable id authoritative
-- and rre_sk_collision at error severity. Deployments approaching one billion
-- events should use ADR 0028 — Hash surrogate keys for high-volume gold event facts — and
-- its SHA-256 escape hatch.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.rfid_read_event (
  rfid_read_event_sk BIGINT NOT NULL
                       COMMENT 'Surrogate join key: xxhash64(rfid_read_event_id). The durable id is authoritative and collision-guarded.',
  rfid_read_event_id STRING NOT NULL
                       COMMENT 'Durable grain key: tagged_item_id|unix_timestamp(event_ts)|sensor_device_id.',

  tagged_item_sk     BIGINT COMMENT 'Nullable FK to tagged_item. NULL only for an explicitly unregistered EPC.',
  tagged_item_id     STRING NOT NULL COMMENT 'Observed EPC Pure Identity URI, including for unregistered EPCs.',
  is_unregistered_epc BOOLEAN NOT NULL COMMENT 'TRUE when the observed EPC has no commissioned tagged_item registry row.',
  product_sk         BIGINT COMMENT 'Product version resolved at write. NULL only for an unregistered or unresolved EPC.',
  product_id         STRING COMMENT 'Durable product business key resolved at write.',

  store_sk           BIGINT NOT NULL COMMENT 'FK to the store version in effect at event time.',
  store_id           STRING NOT NULL COMMENT 'Durable store business key.',
  store_zone_sk      BIGINT NOT NULL COMMENT 'FK to the event-level read-point zone version.',
  store_zone_id      STRING NOT NULL COMMENT 'Durable event-level read-point zone id.',
  sensor_device_sk   BIGINT NOT NULL COMMENT 'FK to the reader device version in effect at event time.',
  sensor_device_id   STRING NOT NULL COMMENT 'Durable reader device business key.',
  sensing_deployment_sk BIGINT NOT NULL COMMENT 'FK to the governing sensing deployment version.',
  sensing_deployment_id STRING NOT NULL COMMENT 'Durable sensing deployment business key.',
  rfid_count_session_sk BIGINT COMMENT 'Nullable FK to rfid_count_session for count-bound reads.',
  rfid_count_session_id STRING COMMENT 'Durable count-session key. NULL for free reads.',
  shipment_line_sk   BIGINT COMMENT 'Nullable FK to shipment_line when a receiving read carries an EPCIS business-transaction association.',
  shipment_line_id   STRING COMMENT 'Durable shipment-line business key. NULL for reads outside a receiving association.',

  event_ts            TIMESTAMP NOT NULL COMMENT 'Business event time as a UTC instant.',
  first_seen_ts       TIMESTAMP NOT NULL COMMENT 'First raw ping in the upstream collapse window (UTC).',
  last_seen_ts        TIMESTAMP NOT NULL COMMENT 'Last raw ping in the upstream collapse window (UTC); its business context wins.',
  store_timezone      STRING COMMENT 'IANA store timezone used to derive local business fields.',
  utc_offset_minutes  SMALLINT NOT NULL COMMENT 'Store UTC offset in minutes at event_ts.',
  trading_date        DATE NOT NULL COMMENT 'Business date of event_ts. Logical join to fiscal_calendar.date_key.',
  hour_of_day         TINYINT COMMENT 'Store-local event hour, 0 through 23.',

  biz_step_uri        STRING COMMENT 'Full GS1 CBV business-step URI from the supported RFID subset.',
  disposition_uri     STRING COMMENT 'Full GS1 CBV disposition URI from the supported RFID subset.',
  zone_source         STRING NOT NULL COMMENT 'How the read-point zone was resolved: device_placement, operator_declared, platform_localization.',
  direction_code      STRING NOT NULL COMMENT 'Observed movement direction: in, out, unknown, not_applicable.',
  direction_confidence DOUBLE COMMENT 'Directional attribution confidence in [0,1]. NULL when direction is not applicable.',
  attribution_confidence DOUBLE NOT NULL COMMENT 'Confidence in assigning the RF read to the stated read point, in [0,1].',
  is_stray_suspect    BOOLEAN NOT NULL COMMENT 'TRUE when RF bleed makes location attribution suspect; excluded from presence gold.',

  antenna_id          STRING COMMENT 'Winning reader antenna identifier; provenance detail, not a separate registry.',
  read_count          BIGINT NOT NULL COMMENT 'Number of raw RF pings collapsed into this visibility event.',
  duplicate_delivery_count BIGINT COMMENT 'Duplicate source deliveries suppressed for this event.',
  rssi_peak_dbm       DOUBLE COMMENT 'Peak received signal strength in dBm across collapsed pings.',
  raw_data_uri        STRING COMMENT 'Pointer to raw RF-ping evidence in Bronze.',

  ingest_timestamp    TIMESTAMP NOT NULL COMMENT 'When the event arrived in the lakehouse (UTC); may be much later than event_ts for offline readers.',
  record_source       STRING COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp      TIMESTAMP COMMENT 'When this row was loaded (UTC).',

  CONSTRAINT pk_rfid_read_event PRIMARY KEY (rfid_read_event_sk)
)
USING DELTA
CLUSTER BY (trading_date, store_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals append-only EPCIS ObjectEvent-shaped RFID visibility fact at EPC × reader × second grain.';

ALTER TABLE ${catalog}.${css_schema}.rfid_read_event SET TAGS ('dbx_data_type' = 'transactional');
