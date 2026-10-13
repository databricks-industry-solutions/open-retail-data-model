-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- Table: data_share_consumption
-- Layer: outcome package (extension table / transactional fact)
-- Version: 0.5
-- Generated: 2026-08-03
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-03
-- ============================================================
-- The METER: what a licensed partner actually consumed of a data product, and what
-- that consumption billed. Append-only usage fact, pre-aggregated to one row per
-- subscription × data product × usage date, so a partner's daily activity is one row
-- rather than a per-query event stream (this is the billing/reporting grain, not an
-- access log — the access log is an operational concern outside the model).
--
-- consumption_units is denominated in the product's consumption_unit (query,
-- row_scanned, report_delivery, api_call); billable_amount is the money that usage
-- earned, already resolved against the subscription's commercial terms so revenue
-- never has to be re-derived downstream from a rate card. billable_amount is
-- deliberately stored rather than computed on read: a flat/tiered subscription bills
-- the same amount regardless of units, so units × rate would be wrong for three of
-- the four pricing models.
--
-- Fiscal period is carried as a DEGENERATE key (fiscal_year + fiscal_period), not a
-- fiscal_calendar FK — matching the Joint Demand Planning precedent, where
-- fiscal_week_id is a degenerate week key. fiscal_calendar's PK is date_sk at DAY
-- grain, so there is no period-grain row to FK onto; the pair stays join-compatible
-- with fiscal_calendar.fiscal_year / .fiscal_period for enrichment.
--
-- Supplier-safe: the consuming party is a governance PRINCIPAL, never a person. No
-- person-level data.
--
-- SCOPE: this use case reports revenue EARNED, it does not issue or settle invoices. There
-- is therefore deliberately no invoice/settlement reference on this fact. Adding one would
-- imply an invoice entity (document number, issue/due dates, tax, payment state, credit
-- notes) that nothing here models, and would make the meter's grain ambiguous — a billing
-- run groups many usage days onto one invoice line, so the reference belongs on a separate
-- invoice-line table keyed to this one, not as a column here. Deferred with invoicing and
-- revenue-share settlement (see glossary.md).
--
-- Grain: one row per (subscription × data product × usage date).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${dss_schema}.data_share_consumption (
  data_share_consumption_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  data_share_consumption_id STRING NOT NULL
                          COMMENT 'Durable natural/business key (grain hash: subscription, product, usage date).',

  data_product_subscription_sk BIGINT COMMENT 'FK to data_product_subscription.data_product_subscription_sk (the licence this usage billed under).',
  data_product_subscription_id STRING COMMENT 'Durable subscription business key.',
  principal_id          STRING NOT NULL COMMENT 'Governance principal that consumed the data (denormalized from the subscription so the row filter and usage reporting need no join).',
  data_product_sk       BIGINT COMMENT 'FK to data_product.data_product_sk.',
  data_product_id       STRING COMMENT 'Durable data-product business key.',
  supplier_sk           BIGINT COMMENT 'FK to supplier.supplier_sk (the supplier whose data was consumed); NULL when the licence is all-supplier and the usage is not attributable to one.',
  supplier_id           STRING COMMENT 'Durable supplier business key; NULL when not attributable to one supplier.',

  usage_date            DATE NOT NULL COMMENT 'Business date the consumption occurred (cluster key).',
  fiscal_year           INT COMMENT 'NRF 4-5-4 fiscal year of usage_date (degenerate key; join-compatible with fiscal_calendar.fiscal_year).',
  fiscal_period         INT COMMENT 'NRF fiscal period / retail month (1-12) of usage_date (degenerate key; join-compatible with fiscal_calendar.fiscal_period).',

  access_channel        STRING COMMENT 'How the data was accessed. Allowed values: share, api, file_export, dashboard.',
  consumption_units     BIGINT COMMENT 'Metered usage for the day, in the data product consumption_unit.',
  billed_query_count    BIGINT COMMENT 'Number of billable requests behind consumption_units (reported for transparency; not itself the billing basis).',
  billable_amount       DECIMAL(18,2) COMMENT 'Money this day of consumption earned, already resolved against the subscription commercial terms. Stored rather than computed: a subscription_flat or tiered licence bills the same regardless of units, so units x rate would be wrong for three of the four pricing models.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',

  threshold_suppressed_flag BOOLEAN COMMENT 'TRUE if any measure on this SOURCE usage row was threshold-suppressed before it was recorded. Set upstream, at ingestion. Not to be confused with gold_data_product_revenue.usage_suppressed_flag, which is decided IN the gold view when a period aggregate falls below the entitled floor: rows flagged here are excluded before aggregation, whereas that flag marks an aggregate that was computed and then withheld.',

  -- Audit / provenance (append-only fact block; all timestamps UTC)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_data_share_consumption PRIMARY KEY (data_share_consumption_sk)
)
USING DELTA
CLUSTER BY (usage_date, data_product_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Data Sharing with Suppliers — metered data-product consumption and the revenue it billed (append-only).';

ALTER TABLE ${catalog}.${dss_schema}.data_share_consumption SET TAGS ('dbx_data_type' = 'transactional');
