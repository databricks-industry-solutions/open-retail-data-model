-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: shelf_position_assignment
-- Layer: outcome package (gold / dimensional, association-tagged)
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- License: see repository LICENSE.md
-- ============================================================
-- The EXPECTED state of the shelf edge: which product belongs at which shelf-position
-- zone, with how many facings, over what validity period. Smart Shelf's observed
-- facts are only meaningful against this slot-level execution contract (ADR 0040).
--
-- Boundary with BMV planogram (ADR 0040): balancing-margin-and-volume.planogram owns
-- ALLOCATION INTENT at store × product grain (allocated_facings, allocated_sqft).
-- This table owns EXECUTION-LEVEL EXPECTED STATE at shelf-position × product grain.
-- Different grain, different question, different owner. Compliance gold may reconcile
-- the two read-only (gold-to-gold, ADR 0024); neither table writes the other and no FK
-- crosses the boundary — planogram_id below is a logical reference only (cf. ADR 0030-a
-- logical non-FK references).
--
-- Adopters without slot-level planogram systems still operate this table with
-- assignment_source = manual or vendor.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.shelf_position_assignment (
  shelf_position_assignment_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  shelf_position_assignment_id STRING NOT NULL
                          COMMENT 'Durable natural key: store_zone_id|product_id. One current version per shelf-position zone and product.',

  store_sk              BIGINT NOT NULL COMMENT 'FK to the store version in effect when this version was written.',
  store_id              STRING NOT NULL COMMENT 'Durable store business key.',
  store_zone_sk         BIGINT NOT NULL COMMENT 'FK to the shelf-position zone version (store_zone.zone_type = shelf_position).',
  store_zone_id         STRING NOT NULL COMMENT 'Durable shelf-position zone id. The zone carries the aisle/bay ancestry via hierarchy_path.',
  product_sk            BIGINT NOT NULL COMMENT 'FK to the product version in effect when this version was written.',
  product_id            STRING NOT NULL COMMENT 'Durable product business key expected at this position.',

  expected_facing_count INT COMMENT 'Facings this product should present at this position per the expected state.',
  min_facing_count      INT COMMENT 'Low-stock threshold: observed facings below this and above zero classify as low_stock at evaluation time.',
  facing_sequence       INT COMMENT 'Optional left-to-right sequence of this product within its bay, where the source system provides it.',

  assignment_source     STRING COMMENT 'Provenance of the expected state. Allowed values: planogram, manual, vendor. Adopters without slot-level planograms operate on manual or vendor.',
  planogram_id          STRING COMMENT 'Logical reference to the BMV planogram business key this assignment was derived from, when assignment_source = planogram. Not a FK: BMV planogram is allocation intent at a different grain (ADR 0040); reconciliation is read-only gold-to-gold (ADR 0024).',

  assignment_status     STRING COMMENT 'Allowed values: active, suspended, retired.',

  -- Instant-grained validity. Shelf observations resolve expected state at an exact UTC
  -- instant, and same-day re-slotting during a reset is real: date-grained SCD2 alone
  -- cannot say which of two same-day versions a 14:05 capture should be judged against.
  valid_from_ts         TIMESTAMP NOT NULL COMMENT 'Inclusive UTC instant this version became the expected state. The version grain key.',
  valid_to_ts           TIMESTAMP COMMENT 'Exclusive UTC instant this version stopped applying; NULL for the current version.',

  -- SCD2 versioning (principle #8) — repo-standard date columns, DERIVED from the
  -- instant validity above (effective_from_date = CAST(valid_from_ts AS DATE)); kept so
  -- the assignment reads like every other master in date-grained tooling.
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective. Derived: CAST(valid_from_ts AS DATE).',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version. Derived from valid_to_ts.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_shelf_position_assignment PRIMARY KEY (shelf_position_assignment_sk)
)
USING DELTA
CLUSTER BY (shelf_position_assignment_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals slot-level expected shelf state (SCD2): product, expected and minimum facings per shelf-position zone. Execution contract for Smart Shelf compliance; distinct from BMV planogram allocation intent (ADR 0040).';

ALTER TABLE ${catalog}.${css_schema}.shelf_position_assignment SET TAGS ('dbx_data_type' = 'association');
