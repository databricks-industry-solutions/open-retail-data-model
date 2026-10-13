-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- Table: suggested_action
-- Layer: outcome package (gold / append-only event fact)
-- Version: 0.5
-- Generated: 2026-08-29
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-29
-- ============================================================
-- The normalized Next Best Action queue: disparate triggers (a VIP dwelling in a
-- high-value zone, an empty high-margin shelf, a BOPIS order nearing SLA, a spill)
-- are normalized into a single prioritized task per row and routed to one associate.
--
-- Grain: one APPEND-ONLY row per action GENERATED. The row records the action as it
-- was dispatched and is never restated (§0 — no mutable workflow/application
-- write-state lives in ORDM). The action's LIFECYCLE (accepted / rejected / deferred /
-- completed / expired) is the append-only action_response_log; the "live" open queue
-- and each action's current state are DERIVED from that log in
-- gold_associate_action_queue_current, not stored as a mutable status here.
--
-- priority_score is the dynamic Business Value Score AT GENERATION (base_score x
-- context multipliers). Time-decay (decay_type) is applied downstream in the gold
-- queue view from generated_timestamp, so the stored score never has to be rewritten.
--
-- Adopter-owned schema: ORDM ships the schema + the DQ contract. Demo instances include
-- synthetic data (deterministically derived from canonical-core entities and business
-- logic); adopter data replaces it in production. Triggers are MAPPED, not redefined here:
-- the source Sensor_Event maps to connected-store-signals telemetry, POS_Transaction to
-- transaction.sales, and Digital_Interaction to interaction.touchpoint; trigger_source
-- records which class fired. The customer/product/store context are FKs into the
-- canonical core; the target zone is a logical reference to store_zone.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${aasa_schema}.suggested_action (
  suggested_action_sk   BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per generated action.',
  suggested_action_id   STRING NOT NULL
                          COMMENT 'Durable business key for the action. Stable; joined by the response log and outcome.',

  generated_timestamp   TIMESTAMP NOT NULL COMMENT 'When the engine generated/dispatched the action (UTC, ISO 8601). The business event time and the decay origin.',

  associate_sk          BIGINT COMMENT 'FK to associate.associate_sk — the routed associate (version at dispatch). NULL when the action was generated but not yet routed.',
  associate_id          STRING COMMENT 'Durable associate business key. The SCD2-safe join/aggregation key. NULL while unrouted.',
  store_sk              BIGINT COMMENT 'FK to store.store_sk (version current at dispatch).',
  store_id              STRING COMMENT 'Durable store business key.',
  store_zone_id         STRING COMMENT 'Durable zone id of the action''s target location. LOGICAL reference to connected-store-signals.store_zone.store_zone_id (not a hard cross-package FK; deploy-order independent).',
  profile_sk            BIGINT COMMENT 'FK to customer.profile.profile_sk — the customer the action concerns. NULL for customer-agnostic tasks (restock, cleaning).',
  profile_id            STRING COMMENT 'Durable, pseudonymous customer business key. NULL for customer-agnostic tasks.',
  product_sk            BIGINT COMMENT 'FK to product.product.product_sk — the product the action concerns. NULL when not product-specific.',
  product_id            STRING COMMENT 'Durable product business key. NULL when not product-specific.',

  action_type           STRING NOT NULL COMMENT 'The task class. Allowed values: customer_assist, restock_shelf, bopis_fulfill, safety_loss_prevention, maintenance_cleaning, price_check, queue_bust, clienteling.',
  trigger_source        STRING COMMENT 'What fired the action. Allowed values: ble_beacon_dwell, pos_inventory_decrement, order_management_system, sensor_event, digital_interaction, schedule, manual.',
  base_score            INT    COMMENT 'Hierarchy-of-needs base score in [0,100] before dynamic multipliers/decay (e.g. safety_loss_prevention 90, bopis_fulfill 75, customer_assist 60, restock_shelf 40, maintenance_cleaning 20). See glossary.',
  priority_score        DOUBLE COMMENT 'Dynamic Business Value Score in [0,100] AT GENERATION (base_score x context multipliers), before time decay. The gold queue view applies decay_type from generated_timestamp to derive the current, rank-on score. Non-monetary.',
  decay_type            STRING COMMENT 'Relevance-decay curve the queue view applies to priority_score. Allowed values: linear, exponential, immediate_nullification, none. See glossary.',
  context_payload       STRING COMMENT 'Schemaless JSON payload the associate app renders (location, customer_context, product_context, suggested_dialogue, ...). Stored as a JSON string so new task types need no schema migration; common shapes are documented in glossary.md.',
  expiration_timestamp  TIMESTAMP COMMENT 'When the action becomes stale/un-actionable (UTC). NULL for tasks that persist until completed. The queue view drops actions past this instant.',

  -- Audit / provenance (fact block; all timestamps UTC, ISO 8601)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_suggested_action PRIMARY KEY (suggested_action_sk)
)
USING DELTA
CLUSTER BY (store_id, associate_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM AI-Assisted Store Associates — append-only record of each generated Next Best Action routed to an associate (lifecycle derived from action_response_log). Adopter-owned; schema + DQ contract.';

ALTER TABLE ${catalog}.${aasa_schema}.suggested_action SET TAGS ('dbx_data_type' = 'transactional');
