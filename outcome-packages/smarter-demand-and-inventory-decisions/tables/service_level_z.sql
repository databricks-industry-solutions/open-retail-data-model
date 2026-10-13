-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- Table: service_level_z
-- Layer: outcome package (extension table / reference)
-- Version: 0.5
-- Generated: 2026-07-22
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-22
-- ============================================================
-- Cycle-service-level -> z-score (inverse standard-normal) lookup, plus the
-- unit-normal loss integral L(z) used to size safety stock for a FILL-RATE
-- (Type II / beta) target. This is a small deterministic reference seeded from the
-- standard normal distribution; it exists so the safety-stock sizing reference
-- (notebook-templates/safety_stock_sizing.sql) can DERIVE safety stock from a
-- service-level target instead of hardcoding a z of 1.65.
--
--   - cycle_service_level path: SS = z * sqrt(LT*sigma_d^2 + D^2*sigma_LT^2)
--   - fill_rate path: choose the z whose loss_function_l_z satisfies
--       E[shortage per cycle] = sigma_dl * L(z) = (1 - fill_rate) * expected_cycle_demand
-- ============================================================


CREATE TABLE IF NOT EXISTS ${catalog}.${sdi_schema}.service_level_z (
  service_level_z_sk      BIGINT GENERATED ALWAYS AS IDENTITY
                            COMMENT 'Surrogate key.',
  service_level_z_id      STRING NOT NULL
                            COMMENT 'Durable business key (service level as basis points, e.g. SLZ-9500).',

  service_level_pct       DECIMAL(6,5) NOT NULL
                            COMMENT 'Cycle service level / non-stockout probability (0-1).',
  z_score                 DOUBLE NOT NULL
                            COMMENT 'Inverse standard-normal quantile for service_level_pct (safety factor).',
  loss_function_l_z       DOUBLE
                            COMMENT 'Standard-normal unit loss integral L(z) = phi(z) - z*(1-Phi(z)); used for fill-rate (Type II) sizing.',

  -- Audit / provenance (reference table block; standard §8)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified (UTC, ISO 8601).',
  record_source           STRING    COMMENT 'Originating system of record.',
  load_timestamp          TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_service_level_z PRIMARY KEY (service_level_z_sk)
)
USING DELTA
CLUSTER BY (service_level_z_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Service-level to z-score and unit-normal loss lookup for safety-stock sizing.';

ALTER TABLE ${catalog}.${sdi_schema}.service_level_z SET TAGS ('dbx_data_type' = 'reference');
ALTER TABLE ${catalog}.${sdi_schema}.service_level_z ADD CONSTRAINT chk_slz_pct_range CHECK (service_level_pct BETWEEN 0 AND 1);
