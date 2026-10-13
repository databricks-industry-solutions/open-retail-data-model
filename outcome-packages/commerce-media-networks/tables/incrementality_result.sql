-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- Table: incrementality_result
-- Layer: outcome package (extension table)
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Append-only, one row per experiment × measurement snapshot × metric ×
-- analysis slice, with PAIRED treatment and control cells. The conformed
-- incrementality-result fact deduping three brief designs (SP
-- g_rm_incrementality_result, MM + INCR incrementality_result). Carries the
-- causal outputs: lift, iROAS, confidence interval, p-value, significance, and
-- sample sizes. NOT person-level (statistical output) but competitively
-- sensitive → supplier-restricted and threshold-suppressed before disclosure.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${cmn_schema}.incrementality_result (
  incrementality_result_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key.',
  incrementality_result_id STRING NOT NULL
                          COMMENT 'Durable natural/business key for the result.',

  experiment_sk         BIGINT COMMENT 'FK to cmn.experiment.experiment_sk.',
  experiment_id         STRING COMMENT 'Durable experiment business key.',
  treatment_cell_sk     BIGINT COMMENT 'FK to cmn.experiment_cell.experiment_cell_sk — the treatment cell.',
  treatment_cell_id     STRING COMMENT 'Durable treatment-cell business key.',
  control_cell_sk       BIGINT COMMENT 'FK to cmn.experiment_cell.experiment_cell_sk — the control cell.',
  control_cell_id       STRING COMMENT 'Durable control-cell business key.',
  campaign_sk           BIGINT COMMENT 'FK to cmn.campaign.campaign_sk (the campaign under test).',
  campaign_id           STRING COMMENT 'Durable campaign business key.',
  advertiser_sk     BIGINT COMMENT 'FK to cmn.advertiser.advertiser_sk.',
  advertiser_id     STRING COMMENT 'Durable advertiser business key.',
  product_sk            BIGINT COMMENT 'FK to product.product_sk (or ALL for overall).',
  product_id            STRING COMMENT 'Durable product business key; ALL when not applicable.',

  snapshot_date         DATE NOT NULL COMMENT 'Measurement snapshot date (cluster key).',
  metric_name           STRING NOT NULL COMMENT 'Metric evaluated. Allowed values: incremental_sales, incremental_units, roas, conversion_rate, reach.',
  analysis_level        STRING COMMENT 'Slice level of the result. Allowed values: overall, store, geo, product, category, vendor.',

  observed_treatment_value DECIMAL(18,4) COMMENT 'Observed metric value in the treatment cell.',
  observed_control_value   DECIMAL(18,4) COMMENT 'Observed metric value in the control cell.',
  counterfactual_value  DECIMAL(18,4) COMMENT 'Estimated counterfactual (what treatment would have been without media).',
  incremental_sales_amount DECIMAL(18,2) COMMENT 'Incremental sales, in the reporting/base currency.',
  incremental_margin_amount DECIMAL(18,2) COMMENT 'Incremental margin, in the reporting/base currency.',
  media_spend_amount    DECIMAL(18,2) COMMENT 'Media spend attributed to the treatment, in the reporting/base currency.',
  currency_code         STRING COMMENT 'Amount currency, ISO 4217 alpha-3 (single reporting currency).',
  lift_pct              DECIMAL(9,4) COMMENT 'Relative lift of treatment over control, percent.',
  iroas_value           DECIMAL(12,4) COMMENT 'Incremental ROAS = incremental_sales / media_spend.',
  confidence_level_pct  DECIMAL(5,2) COMMENT 'Confidence level of the interval, percent (e.g. 95.00).',
  ci_lower_value        DECIMAL(18,4) COMMENT 'Lower bound of the confidence interval for the estimate.',
  ci_upper_value        DECIMAL(18,4) COMMENT 'Upper bound of the confidence interval for the estimate.',
  p_value               DECIMAL(9,6) COMMENT 'p-value of the treatment-vs-control test.',
  statistical_significance_flag BOOLEAN COMMENT 'TRUE if the result is statistically significant at the confidence level.',
  sample_size_treatment BIGINT COMMENT 'Treatment-cell sample size.',
  sample_size_control   BIGINT COMMENT 'Control-cell sample size.',
  methodology           STRING COMMENT 'Causal method used. Allowed values: randomized_control, matched_market, synthetic_control, difference_in_differences, other.',
  suppressed_flag       BOOLEAN COMMENT 'TRUE if suppressed for disclosure (below threshold / policy).',

  -- Audit / provenance (append-only fact block; all timestamps UTC)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_incrementality_result PRIMARY KEY (incrementality_result_sk)
)
USING DELTA
CLUSTER BY (snapshot_date, experiment_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Commerce Media Networks — conformed incrementality result fact (lift/iROAS/CI/p-value, append-only).';

ALTER TABLE ${catalog}.${cmn_schema}.incrementality_result SET TAGS ('dbx_data_type' = 'transactional');
