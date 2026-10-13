-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_planogram_compliance_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- ============================================================
-- GRAIN: one row per store × trading_date × product (SKU-level compliance detail).
--
-- Four compliance dimensions per position-day (right product present, right position,
-- right facing count, right price tag), evaluated on the day's LAST capture per
-- position — selected over ALL captures (H2: an unknown/invalid newest capture makes
-- the position non-evaluable for the day; it never resurrects an earlier good reading).
-- Denominators are EVALUABLE positions per dimension (a NULL dimension never counts as
-- compliant or violating), so the four percentages are honest under partial sensing.
-- Expected, observed, known, unknown, and unobserved counts plus coverage rates are
-- published beside them; an unobserved expected position is never silently compliant.
--
-- BMV reconciliation (ADR 0040, read-only gold-to-gold per ADR 0024): Σ expected facings
-- per store × product is compared against BMV planogram allocation intent
-- (allocated_facings). Divergence is FLAGGED, never corrected; neither package writes
-- the other. The BMV row resolves is_current because allocation intent is a current
-- question; the CSS expected state resolves as-of the observation.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_planogram_compliance_current AS
WITH obs AS (
  -- Rank over ALL captures of the day (H2); usability judged after selection.
  SELECT
    o.store_id,
    o.trading_date,
    o.store_zone_id,
    o.product_id,
    o.shelf_state,
    o.measurement_validity,
    o.observed_facing_count,
    o.is_misplaced_detected,
    o.is_price_tag_mismatch_detected,
    a.expected_facing_count,
    ROW_NUMBER() OVER (
      PARTITION BY o.store_zone_id, o.product_id, o.trading_date
      ORDER BY o.observation_ts DESC, o.ingest_timestamp DESC, o.shelf_state_observation_id DESC
    ) AS day_rank
  FROM ${catalog}.${css_schema}.shelf_state_observation o
  LEFT JOIN ${catalog}.${css_schema}.shelf_position_assignment a
    ON o.shelf_position_assignment_sk = a.shelf_position_assignment_sk
  WHERE o.observation_ts <= CAST(${shelf_as_of_ts} AS TIMESTAMP)
), position_day AS (
  SELECT
    *,
    COALESCE(measurement_validity, 'valid') <> 'invalid' AND shelf_state <> 'unknown' AS is_known,
    CASE WHEN COALESCE(measurement_validity, 'valid') = 'invalid' OR shelf_state = 'unknown'
         THEN CAST(NULL AS BOOLEAN)
         ELSE shelf_state IN ('in_stock', 'low_stock') END AS is_presence_compliant,
    CASE WHEN COALESCE(measurement_validity, 'valid') = 'invalid' OR shelf_state = 'unknown'
              OR is_misplaced_detected IS NULL
         THEN CAST(NULL AS BOOLEAN)
         ELSE NOT is_misplaced_detected END AS is_position_compliant,
    CASE WHEN COALESCE(measurement_validity, 'valid') = 'invalid' OR shelf_state = 'unknown'
              OR expected_facing_count IS NULL OR observed_facing_count IS NULL
         THEN CAST(NULL AS BOOLEAN)
         ELSE observed_facing_count >= expected_facing_count END AS is_facing_compliant,
    CASE WHEN COALESCE(measurement_validity, 'valid') = 'invalid' OR shelf_state = 'unknown'
              OR is_price_tag_mismatch_detected IS NULL
         THEN CAST(NULL AS BOOLEAN)
         ELSE NOT is_price_tag_mismatch_detected END AS is_price_tag_compliant
  FROM obs WHERE day_rank = 1
), assignment_days AS (
  -- The assignment estate owns the day spine. Expanding its validity through the
  -- named evaluation clock preserves store-days with no observations at all.
  SELECT
    a.store_id,
    EXPLODE(SEQUENCE(
      CAST(a.valid_from_ts AS DATE),
      CAST(LEAST(
        COALESCE(a.valid_to_ts - INTERVAL 1 MICROSECOND,
                 CAST(${shelf_as_of_ts} AS TIMESTAMP)),
        CAST(${shelf_as_of_ts} AS TIMESTAMP)
      ) AS DATE)
    )) AS trading_date,
    a.store_zone_id,
    a.product_id,
    a.expected_facing_count,
    a.assignment_status,
    a.valid_from_ts,
    a.shelf_position_assignment_sk
  FROM ${catalog}.${css_schema}.shelf_position_assignment a
  WHERE a.valid_from_ts <= CAST(${shelf_as_of_ts} AS TIMESTAMP)
    AND (a.valid_to_ts IS NULL OR a.valid_to_ts > a.valid_from_ts)
), expected_ranked AS (
  -- Build the expected estate independently of observations. Rank assignment versions
  -- before applying status so a newer suspended/retired version cannot resurrect an
  -- older active one.
  SELECT
    a.store_id,
    a.trading_date,
    a.store_zone_id,
    a.product_id,
    a.expected_facing_count,
    a.assignment_status,
    ROW_NUMBER() OVER (
      PARTITION BY a.store_id, a.trading_date, a.store_zone_id, a.product_id
      ORDER BY a.valid_from_ts DESC, a.shelf_position_assignment_sk DESC
    ) AS assignment_rank
  FROM assignment_days a
), expected AS (
  SELECT *
  FROM expected_ranked
  WHERE assignment_rank = 1
    AND COALESCE(assignment_status, 'active') = 'active'
), position_eval AS (
  SELECT
    e.store_id,
    e.trading_date,
    e.store_zone_id,
    e.product_id,
    e.expected_facing_count,
    pd.store_zone_id IS NOT NULL AS is_observed,
    pd.is_known,
    pd.observed_facing_count,
    pd.is_presence_compliant,
    pd.is_position_compliant,
    pd.is_facing_compliant,
    pd.is_price_tag_compliant
  FROM expected e
  LEFT JOIN position_day pd
    ON e.store_id = pd.store_id
   AND e.trading_date = pd.trading_date
   AND e.store_zone_id = pd.store_zone_id
   AND e.product_id = pd.product_id
), product_day AS (
  SELECT
    store_id,
    trading_date,
    product_id,
    COUNT(*) AS positions_expected,
    SUM(CASE WHEN is_observed THEN 1 ELSE 0 END) AS positions_observed,
    SUM(CASE WHEN NOT is_observed THEN 1 ELSE 0 END) AS positions_unobserved,
    SUM(CASE WHEN is_observed AND is_known THEN 1 ELSE 0 END) AS positions_known,
    SUM(CASE WHEN is_observed AND NOT is_known THEN 1 ELSE 0 END) AS positions_unknown,
    SUM(expected_facing_count) AS expected_facings_total,
    SUM(CASE WHEN is_observed AND is_known THEN observed_facing_count END) AS observed_facings_total,
    COUNT(is_presence_compliant) AS presence_evaluable,
    SUM(CASE WHEN is_presence_compliant THEN 1 ELSE 0 END) AS presence_compliant,
    COUNT(is_position_compliant) AS position_evaluable,
    SUM(CASE WHEN is_position_compliant THEN 1 ELSE 0 END) AS position_compliant,
    COUNT(is_facing_compliant) AS facing_evaluable,
    SUM(CASE WHEN is_facing_compliant THEN 1 ELSE 0 END) AS facing_compliant,
    COUNT(is_price_tag_compliant) AS price_tag_evaluable,
    SUM(CASE WHEN is_price_tag_compliant THEN 1 ELSE 0 END) AS price_tag_compliant,
    SUM(CASE WHEN is_presence_compliant AND is_position_compliant
              AND is_facing_compliant AND is_price_tag_compliant THEN 1 ELSE 0 END) AS fully_compliant_positions,
    SUM(CASE WHEN is_presence_compliant IS NOT NULL AND is_position_compliant IS NOT NULL
              AND is_facing_compliant IS NOT NULL AND is_price_tag_compliant IS NOT NULL
             THEN 1 ELSE 0 END) AS fully_evaluable_positions
  FROM position_eval
  GROUP BY store_id, trading_date, product_id
)
SELECT
  pd.store_id,
  pd.trading_date,
  pd.product_id,
  pd.positions_expected,
  pd.positions_observed,
  pd.positions_unobserved,
  pd.positions_known,
  pd.positions_unknown,
  pd.positions_observed / NULLIF(pd.positions_expected, 0) AS observation_coverage_pct,
  pd.positions_known / NULLIF(pd.positions_observed, 0) AS known_state_pct,
  pd.expected_facings_total,
  pd.observed_facings_total,
  pd.presence_evaluable,
  pd.presence_compliant,
  pd.presence_compliant / NULLIF(pd.presence_evaluable, 0) AS presence_compliance_pct,
  pd.position_evaluable,
  pd.position_compliant,
  pd.position_compliant / NULLIF(pd.position_evaluable, 0) AS position_compliance_pct,
  pd.facing_evaluable,
  pd.facing_compliant,
  pd.facing_compliant / NULLIF(pd.facing_evaluable, 0) AS facing_compliance_pct,
  pd.price_tag_evaluable,
  pd.price_tag_compliant,
  pd.price_tag_compliant / NULLIF(pd.price_tag_evaluable, 0) AS price_tag_compliance_pct,
  pd.fully_evaluable_positions,
  pd.fully_compliant_positions,
  pd.fully_compliant_positions / NULLIF(pd.fully_evaluable_positions, 0) AS overall_compliance_pct,

  -- ADR 0040 reconciliation: execution expectation vs BMV allocation intent. Read-only;
  -- a divergence is a conversation between space planning and store execution, not a
  -- correction either package may make.
  pg.allocated_facings AS bmv_allocated_facings,
  CASE WHEN pg.allocated_facings IS NULL OR pd.expected_facings_total IS NULL THEN CAST(NULL AS BOOLEAN)
       ELSE pd.expected_facings_total <> pg.allocated_facings END AS is_allocation_divergent,
  CAST(${shelf_as_of_ts} AS TIMESTAMP) AS fresh_as_of_ts
FROM product_day pd
LEFT JOIN ${catalog}.${bmv_schema}.planogram pg
  ON pd.store_id = pg.store_id
 AND pd.product_id = pg.product_id
 AND pg.is_current = TRUE;
