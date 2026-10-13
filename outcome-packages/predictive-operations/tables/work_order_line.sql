-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · In-Store Equipment Maintenance use case
-- Table: work_order_line
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-15
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-29 by @sreekanthmunigati
-- ============================================================
-- Line-level detail within a work order: individual parts used,
-- labor entries, or service charges. Allows cost breakdown and
-- parts-usage analysis.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${predops_schema}.work_order_line (
  work_order_line_sk    BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  work_order_line_id    STRING NOT NULL
                          COMMENT 'Durable natural/business key for the line.',

  work_order_sk         BIGINT COMMENT 'FK to work_order.work_order_sk.',
  work_order_id         STRING NOT NULL COMMENT 'Durable work order business key.',

  line_type             STRING NOT NULL COMMENT 'Type of line item. Allowed values: part, labor, service, other.',
  part_number           STRING COMMENT 'Part number (populated when line_type = part).',
  part_description      STRING COMMENT 'Description of the part or service.',
  quantity              DECIMAL(10,2) COMMENT 'Quantity used (units for parts, hours for labor).',
  unit_cost             DECIMAL(12,2) COMMENT 'Cost per unit in base currency.',
  line_total            DECIMAL(12,2) COMMENT 'Total cost for this line (quantity x unit_cost) in base currency.',

  currency_code         STRING NOT NULL COMMENT 'Reporting/base currency for cost columns, ISO 4217 alpha-3.',

  -- Audit / provenance
  record_source         STRING    COMMENT 'Originating system (CMMS, EAM, or manual entry).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_work_order_line PRIMARY KEY (work_order_line_sk)
)
USING DELTA
CLUSTER BY (work_order_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Work order line items: parts, labor, and service charges for equipment maintenance.';

ALTER TABLE ${catalog}.${predops_schema}.work_order_line SET TAGS ('dbx_data_type' = 'transactional');

ALTER TABLE ${catalog}.${predops_schema}.work_order_line ADD CONSTRAINT chk_wol_line_type CHECK (line_type IN ('part', 'labor', 'service', 'other'));
