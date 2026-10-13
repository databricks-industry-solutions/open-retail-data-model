-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- Table: location_offer
-- Layer: outcome package (silver / reference definition)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- The definition of a location-triggered offer: a promotion delivered when a
-- customer's device reports a trigger against a defined offer_zone, with the
-- frequency/suppression rules and delivery channel that govern it. One row per
-- configured offer. No location or device data lives here — only the rule set.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${promo_schema}.location_offer (
  location_offer_sk       BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  location_offer_id       STRING NOT NULL
                            COMMENT 'Durable natural/business key for the location offer.',

  promotion_id            STRING COMMENT 'Durable promotion business key this offer delivers (logical reference to promotion.promo_id).',
  zone_sk                 BIGINT COMMENT 'FK to offer_zone.zone_sk — the zone whose trigger fires this offer.',

  trigger_type            STRING COMMENT 'What device signal fires the offer. Common values: geofence_enter, geofence_exit, dwell, beacon_proximity (enum enforced in relationships.sql).',
  min_dwell_seconds       INT COMMENT 'Minimum dwell time in seconds; required only for trigger_type=dwell (asserted in checks.sql), NULL otherwise.',
  daily_trigger_cap       INT NOT NULL COMMENT 'Maximum number of times this offer may fire for one customer per day (> 0).',
  suppression_window_hours INT NOT NULL COMMENT 'Hours after a delivery before the same offer may be delivered again to the same customer (>= 0).',
  channel                 STRING COMMENT 'Delivery channel. Common values: push, sms, email, in_app (enum enforced in relationships.sql).',
  offer_start_ts          TIMESTAMP NOT NULL COMMENT 'Offer availability window start (event-time, UTC).',
  offer_end_ts            TIMESTAMP NOT NULL COMMENT 'Offer availability window end (event-time, UTC); must be after offer_start_ts.',
  status                  STRING COMMENT 'Lifecycle state. Common values: draft, active, paused, ended (enum enforced in relationships.sql).',

  -- Audit / provenance (standard block; all timestamps UTC)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source           STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded into the canonical core (UTC, ISO 8601).',

  CONSTRAINT pk_location_offer PRIMARY KEY (location_offer_sk)
)
USING DELTA
CLUSTER BY (promotion_id, zone_sk, status)
-- Deletion vectors speed row-level MERGE/UPDATE (status transitions, corrections).
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Location-triggered offer definitions (trigger, frequency/suppression rules, channel) for the Location-Based Offers use case.';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${promo_schema}.location_offer SET TAGS ('dbx_data_type' = 'reference');
