-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- Table: offer_event
-- Layer: outcome package (silver / transactional event)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- The delivery/engagement event log for location-based offers: one row per
-- trigger, suppression, delivery, open, or redemption. Customers appear ONLY as
-- a pseudonymous key (customer_id) — never a device identifier, coordinate, or
-- location trail; PII is concentrated in the customer core, never here. Every
-- delivery-class event (delivered/opened/redeemed) carries consent_verified.
-- Append-only event fact (no SCD2).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${promo_schema}.offer_event (
  offer_event_sk        BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  offer_event_id        STRING NOT NULL
                          COMMENT 'Durable event key assigned by the emitting system (ULID/UUID); the idempotency key for replay and de-duplication.',
  location_offer_sk     BIGINT NOT NULL COMMENT 'FK to location_offer.location_offer_sk — the offer that fired.',
  customer_id           STRING NOT NULL COMMENT 'Pseudonymous customer key (logical reference to customer profile.profile_id). No PII, no device id, no location trail.',
  store_id              STRING NOT NULL COMMENT 'Durable store business key where the event occurred (logical reference to store.store_id).',

  event_ts              TIMESTAMP NOT NULL COMMENT 'When the event occurred (event-time, UTC, ISO 8601).',
  event_type            STRING COMMENT 'Event kind. Common values: triggered, suppressed, delivered, opened, redeemed (enum enforced in relationships.sql).',
  suppression_reason    STRING COMMENT 'Why a trigger was suppressed; set only when event_type=suppressed, NULL otherwise. Common values: no_consent, daily_cap, quiet_hours, frequency_window (enum enforced in relationships.sql).',
  transaction_id        STRING COMMENT 'Durable sales-transaction business key for redemption attribution (logical reference to transaction sales.sales_id); NULL when not a redemption.',
  consent_verified      BOOLEAN NOT NULL COMMENT 'TRUE when marketing consent was verified for this customer at event time; must be TRUE for every delivered/opened/redeemed event.',

  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'Timestamp this row was loaded into the canonical core (UTC, ISO 8601).',

  CONSTRAINT pk_offer_event PRIMARY KEY (offer_event_sk)
)
USING DELTA
CLUSTER BY (location_offer_sk, store_id, event_type)
-- Deletion vectors speed row-level MERGE/UPDATE (late-arriving corrections).
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Location-based offer delivery/engagement events (pseudonymous keys; consent-verified deliveries) for the Location-Based Offers use case.';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${promo_schema}.offer_event SET TAGS ('dbx_data_type' = 'transactional');
