-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Store Performance use case
-- Table: store_risk_score
-- Layer: outcome package (extension table · scored-output fact)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27 by @sreekanthmunigati
-- ============================================================
-- Append-only, store x as_of_date snapshot of the Store Operational Risk
-- Score and its six per-domain sub-scores. This is the durable, queryable
-- HISTORY of scores a scoring pipeline writes; gold_store_operational_risk
-- is the live computation over the current inputs.
--
-- Grain:   one row per store per as_of_date (a daily snapshot).
-- Type:    transactional / append-only. NO SCD2 — the audit block is
--          record_source + load_timestamp only (standards §A.8). as_of_date
--          conforms to fiscal_calendar.date_key. store_sk carries the CURRENT
--          store version (the gold view scores as-of today over current-state
--          inputs); a backfill pipeline scoring historical dates should resolve
--          the version effective at as_of_date instead.
--
-- HONESTY (ADR 0028): the score is a transparent, expert-weighted HEURISTIC
-- INDEX (0-100), not a calibrated probability. score_method distinguishes the
-- shipped heuristic rows ('heuristic') from rows a model-backed pipeline may
-- write later ('model'). predicted_impact_amount is reserved for that pipeline
-- and is NULL in the shipped heuristic.
--
-- labor_risk is populated when Workforce Optimization / canonical-core labor
-- is present (ADR 0043). cx_risk remains deferred (NULL) until a customer-
-- experience source lands. Missing sub-scores are excluded from the composite
-- denominator (missing = unknown, not safe).
--
-- LIMITATION (v1): the fact persists the tier and the per-domain sub-scores, but
-- NOT the escalation reason. A HIGH driven by the worst-domain floor is
-- reconstructable (the critical sub-score is stored); a HIGH driven purely by the
-- gold view's steep-sales-decline escalator is NOT — sales_trend_risk is a gold
-- intermediate, not persisted here. A pipeline that needs full reconstructability
-- should add an escalation_reason column; v1 leaves it out (the heuristic seed
-- path exercises only the worst-domain floor).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${predops_schema}.store_risk_score (
  store_risk_score_sk    BIGINT GENERATED ALWAYS AS IDENTITY
                           COMMENT 'Surrogate key.',
  store_risk_score_id    STRING NOT NULL
                           COMMENT 'Durable natural/business key for the score snapshot at the table grain (store x as_of_date x score_method), e.g. "<store_id>|<as_of_date>|<score_method>". score_method is part of the key so a future model-backed row does not collide with the heuristic row for the same store/date.',

  store_sk               BIGINT COMMENT 'FK to store.store_sk. Carries the CURRENT store version (the gold view scores as-of today); a historical-backfill pipeline should resolve the version effective at as_of_date. Nullable only if an adopter pipeline scores a store absent from the dimension (tolerated by the srs_store_fk_orphan check); the shipped gold view always populates it. Join on the durable store_id, not this per-deployment surrogate.',
  store_id               STRING NOT NULL COMMENT 'Durable store business key.',
  as_of_date             DATE   NOT NULL COMMENT 'Snapshot date; conforms to fiscal_calendar.date_key (ISO 8601).',
  horizon_days           INT    NOT NULL COMMENT 'Declared forward assessment horizon in days (7 in v1) — the label the score is interpreted against, uniform across a snapshot so scores are comparable. Not a claim every input is windowed to 7 days; sub-score observation windows differ by domain (see design spec §4.7).',

  -- Composite (secondary triage roll-up; the six sub-scores are the primary diagnosis)
  operational_risk_score DOUBLE COMMENT 'Store Operational Risk Score, 0-100, higher = riskier. Heuristic index, NOT a probability.',
  operational_risk_tier  STRING NOT NULL COMMENT 'Risk tier. Allowed values: UNKNOWN, LOW, MEDIUM, HIGH, CRITICAL. UNKNOWN = no domain sub-score was present (domains_scored = 0), so the store is unscored, not low-risk (missing = unknown, not safe).',
  domains_scored         INT    COMMENT 'How many domains had a present (non-NULL) sub-score feeding the composite. Max is 5 when labor is present (cx still deferred); 0 means the store is unscored (tier UNKNOWN).',
  top_risk_domains       STRING COMMENT 'Up-to-3 domains with the largest weighted contribution (the Diagnose step), comma-separated.',

  -- Per-domain sub-scores (each 0-100, higher = riskier; NULL = unknown, excluded from composite)
  inventory_risk         DOUBLE COMMENT 'Inventory domain sub-score (from gold_inventory_risk). 0-100 or NULL.',
  supply_chain_risk      DOUBLE COMMENT 'Supply-chain domain sub-score (from gold_procurement_risk). 0-100 or NULL.',
  sales_margin_risk      DOUBLE COMMENT 'Sales/margin domain sub-score (from BMV gold). 0-100 or NULL.',
  equipment_risk         DOUBLE COMMENT 'Equipment domain sub-score (from gold_equipment_health). 0-100 or NULL.',
  labor_risk             DOUBLE COMMENT 'Labor/workforce domain sub-score from gold_labor_risk (0-100). NULL when unscored.',
  cx_risk                DOUBLE COMMENT 'Customer-experience domain sub-score. DEFERRED — always NULL until a CX source lands.',

  -- Scoring method + reserved model-backed columns (honesty contract, ADR 0028)
  score_method           STRING NOT NULL COMMENT 'How the score was produced. Allowed values: heuristic, model.',
  model_version          STRING COMMENT 'Version of the model that produced the row when score_method = model; NULL for heuristic rows.',
  predicted_impact_amount DECIMAL(18,2) COMMENT 'Estimated business impact (e.g. lost sales) in currency_code. Reserved for a model/adopter pipeline; NULL in the shipped heuristic.',
  currency_code          STRING COMMENT 'Reporting currency for predicted_impact_amount, ISO 4217 alpha-3; NULL when predicted_impact_amount is NULL.',

  -- Audit / provenance (append-only fact: record_source + load_timestamp only)
  record_source          STRING    COMMENT 'Originating system or pipeline that produced this score.',
  load_timestamp         TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_store_risk_score PRIMARY KEY (store_risk_score_sk)
)
USING DELTA
CLUSTER BY (store_id, as_of_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Append-only store x as_of_date snapshot of the Store Operational Risk Score (heuristic index) and its per-domain sub-scores. Store Performance use case, Predictive Operations. See ADR 0028.';

ALTER TABLE ${catalog}.${predops_schema}.store_risk_score SET TAGS ('dbx_data_type' = 'transactional');

ALTER TABLE ${catalog}.${predops_schema}.store_risk_score ADD CONSTRAINT chk_srs_tier CHECK (operational_risk_tier IN ('UNKNOWN', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'));
ALTER TABLE ${catalog}.${predops_schema}.store_risk_score ADD CONSTRAINT chk_srs_method CHECK (score_method IN ('heuristic', 'model'));
ALTER TABLE ${catalog}.${predops_schema}.store_risk_score ADD CONSTRAINT chk_srs_score_range CHECK (operational_risk_score IS NULL OR (operational_risk_score BETWEEN 0 AND 100));
ALTER TABLE ${catalog}.${predops_schema}.store_risk_score ADD CONSTRAINT chk_srs_horizon CHECK (horizon_days > 0);
ALTER TABLE ${catalog}.${predops_schema}.store_risk_score ADD CONSTRAINT chk_srs_impact CHECK (predicted_impact_amount IS NULL OR predicted_impact_amount >= 0);
