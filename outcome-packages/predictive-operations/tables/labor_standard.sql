-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Workforce Optimization
-- Table: labor_standard
-- Layer: outcome package (extension table / versioned config)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10
-- ============================================================
-- Versioned, data-driven workload-to-labor rules. Never hardcode
-- store-specific staffing math in pipeline code — encode it here.
-- SCD2 so standard changes are historically auditable.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${predops_schema}.labor_standard (
  labor_standard_sk     BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  labor_standard_id     STRING NOT NULL
                          COMMENT 'Durable business key for the standard (stable across versions).',

  standard_version      STRING NOT NULL COMMENT 'Configuration version label (e.g. v1, 2026-Q3).',
  role_code             STRING NOT NULL
                          COMMENT 'Role the standard applies to. Allowed values: cashier, sales_associate, fulfillment, inventory, supervisor.',
  demand_driver         STRING NOT NULL
                          COMMENT 'Demand driver. Allowed values: transaction_count, foot_traffic, pickup_orders, receiving_units, store_open_coverage, minimum_coverage.',
  department_or_zone    STRING
                          COMMENT 'Optional department/zone scope; NULL or storewide = all zones.',
  interval_minutes      INT NOT NULL COMMENT 'Planning interval length in minutes (default 30).',

  driver_units_per_labor_hour DECIMAL(18,4) NOT NULL
                          COMMENT 'How many driver units one labor hour covers (e.g. 30 transactions per cashier hour). Must be positive except for coverage drivers.',
  labor_hours_per_driver_unit DECIMAL(18,6)
                          COMMENT 'Optional inverse form (hours per driver unit). When set, used preferentially over driver_units_per_labor_hour.',
  minimum_headcount     INT NOT NULL COMMENT 'Minimum headcount required whenever the store is open for this role/zone.',
  coverage_rationale    STRING NOT NULL COMMENT 'Human-readable explanation of why this standard exists.',

  is_active             BOOLEAN NOT NULL COMMENT 'TRUE when this version may be applied.',
  effective_from_date   DATE NOT NULL COMMENT 'SCD2: inclusive start date.',
  effective_to_date     DATE COMMENT 'SCD2: exclusive end date; NULL for current.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  created_timestamp        TIMESTAMP COMMENT 'When the standard was created (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the standard was last modified (UTC, ISO 8601).',
  record_source         STRING COMMENT 'Originating system of record.',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_labor_standard PRIMARY KEY (labor_standard_sk)
)
USING DELTA
CLUSTER BY (role_code, demand_driver)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Versioned workload-to-labor standards for Workforce Optimization. Data-driven configuration, not hardcoded pipeline logic.';

ALTER TABLE ${catalog}.${predops_schema}.labor_standard SET TAGS ('dbx_data_type' = 'reference');

ALTER TABLE ${catalog}.${predops_schema}.labor_standard ADD CONSTRAINT chk_lstd_role CHECK (role_code IN ('cashier', 'sales_associate', 'fulfillment', 'inventory', 'supervisor'));
ALTER TABLE ${catalog}.${predops_schema}.labor_standard ADD CONSTRAINT chk_lstd_driver CHECK (demand_driver IN ('transaction_count', 'foot_traffic', 'pickup_orders', 'receiving_units', 'store_open_coverage', 'minimum_coverage'));
ALTER TABLE ${catalog}.${predops_schema}.labor_standard ADD CONSTRAINT chk_lstd_interval CHECK (interval_minutes > 0);
ALTER TABLE ${catalog}.${predops_schema}.labor_standard ADD CONSTRAINT chk_lstd_driver_units CHECK (driver_units_per_labor_hour > 0);
ALTER TABLE ${catalog}.${predops_schema}.labor_standard ADD CONSTRAINT chk_lstd_min_hc CHECK (minimum_headcount >= 0);
