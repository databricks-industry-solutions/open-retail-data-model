-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_osa_daily_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- ============================================================
-- GRAIN: one row per store × trading_date × category.
--
-- OSA is an EXPECTED-VS-OBSERVED ratio: the denominator is the assignment-derived
-- expected set (positions with an assignment effective on the trading date), never a
-- property of observations alone.
--
-- DENOMINATOR HONESTY (H2): the day's LAST capture per position wins regardless of
-- validity — an unknown or invalid newest capture makes the position UNKNOWN for the
-- day, it never resurrects an earlier good reading. Known / unknown / unobserved are
-- separated: availability ratios compute over KNOWN positions only;
-- positions_unknown counts expected positions whose last capture could not evaluate;
-- positions_unobserved counts expected positions with no capture at all (a coverage
-- gap — an unobserved shelf is unknown, not available). observation_coverage_pct and
-- known_state_pct publish the denominators' honesty next to the headline ratio.
--
-- Two failure classes stay split (full OOS vs low-stock), and the intraday masking
-- problem is exposed rather than averaged away: positions_oos_any_time counts positions
-- EVER observed out-of-stock during the day, while the end-of-day figures use the day's
-- last usable state (research §1: daily averages mask the failure window).
--
-- Category resolves through the version-pinned product _sk on the observation (§A.16).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_osa_daily_current AS
WITH obs AS (
  -- Rank over ALL captures of the day: no validity/state filter before ranking (H2).
  SELECT
    o.store_id,
    o.trading_date,
    o.store_zone_id,
    o.product_id,
    p.category,
    o.shelf_state,
    o.measurement_validity,
    ROW_NUMBER() OVER (
      PARTITION BY o.store_zone_id, o.product_id, o.trading_date
      ORDER BY o.observation_ts DESC, o.ingest_timestamp DESC, o.shelf_state_observation_id DESC
    ) AS day_rank,
    MAX(CASE WHEN COALESCE(o.measurement_validity, 'valid') <> 'invalid'
                  AND o.shelf_state = 'out_of_stock' THEN 1 ELSE 0 END) OVER (
      PARTITION BY o.store_zone_id, o.product_id, o.trading_date
    ) AS was_oos_any_time
  FROM ${catalog}.${css_schema}.shelf_state_observation o
  LEFT JOIN ${catalog}.${product_schema}.product p
    ON o.product_sk = p.product_sk
  WHERE o.observation_ts <= CAST(${shelf_as_of_ts} AS TIMESTAMP)
), position_day AS (
  SELECT
    *,
    COALESCE(measurement_validity, 'valid') <> 'invalid' AND shelf_state <> 'unknown' AS is_known
  FROM obs WHERE day_rank = 1
), assignment_days AS (
  -- Generate every assignment-covered day through the named evaluation clock. The
  -- expected estate, not observation arrival, owns the date spine so a complete
  -- sensing outage remains visible as zero observed positions and 0% coverage.
  -- EDGE (mid-day re-slot): the effective window is tested at DATE grain here, not at the
  -- instant-valid grain the assignment carries. If one physical position is re-slotted to a
  -- different product mid-day, both products remain expected for that day because the durable
  -- assignment identities differ; repeated versions of one identity are ranked below.
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
    p.category,
    a.assignment_status,
    a.valid_from_ts,
    a.shelf_position_assignment_sk
  FROM ${catalog}.${css_schema}.shelf_position_assignment a
  LEFT JOIN ${catalog}.${product_schema}.product p
    ON a.product_sk = p.product_sk
  WHERE a.valid_from_ts <= CAST(${shelf_as_of_ts} AS TIMESTAMP)
    AND (a.valid_to_ts IS NULL OR a.valid_to_ts > a.valid_from_ts)
), expected_ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY store_id, trading_date, store_zone_id, product_id
      ORDER BY valid_from_ts DESC, shelf_position_assignment_sk DESC
    ) AS assignment_rank
  FROM assignment_days
), expected AS (
  SELECT *
  FROM expected_ranked
  WHERE assignment_rank = 1
    AND COALESCE(assignment_status, 'active') = 'active'
)
SELECT
  e.store_id,
  e.trading_date,
  e.category,
  COUNT(*) AS expected_positions,
  COUNT(pd.store_zone_id) AS observed_positions,
  COUNT(*) - COUNT(pd.store_zone_id) AS positions_unobserved,
  SUM(CASE WHEN pd.is_known THEN 1 ELSE 0 END) AS positions_known,
  SUM(CASE WHEN pd.store_zone_id IS NOT NULL AND NOT pd.is_known THEN 1 ELSE 0 END) AS positions_unknown,
  SUM(CASE WHEN pd.is_known AND pd.shelf_state IN ('in_stock', 'low_stock') THEN 1 ELSE 0 END) AS positions_available_eod,
  SUM(CASE WHEN pd.is_known AND pd.shelf_state = 'low_stock' THEN 1 ELSE 0 END) AS positions_low_stock_eod,
  SUM(CASE WHEN pd.is_known AND pd.shelf_state = 'out_of_stock' THEN 1 ELSE 0 END) AS positions_oos_eod,
  -- NOTE: near-always 0 by construction. Under the two-row misplacement model a 'misplaced'
  -- row is for the DETECTED wrong product, which is outside this position's expected set and so
  -- rarely survives the expected-set join below (it fires only when a product is misplaced onto
  -- a slot it is itself assigned to). Misplacement is surfaced authoritatively in
  -- gold_planogram_compliance_current (is_position_compliant) — read that for the real signal.
  SUM(CASE WHEN pd.is_known AND pd.shelf_state = 'misplaced' THEN 1 ELSE 0 END) AS positions_misplaced_eod,
  SUM(COALESCE(pd.was_oos_any_time, 0)) AS positions_oos_any_time,
  -- The known-restricted counter, exposed so the metric view can recompute the intraday
  -- floor from sums without re-deriving row-level knowledge (fan-out-proof).
  SUM(CASE WHEN pd.is_known THEN COALESCE(pd.was_oos_any_time, 0) ELSE 0 END) AS positions_known_oos_any_time,
  -- Availability over KNOWN positions only (H2): unknown and unobserved never inflate OSA.
  SUM(CASE WHEN pd.is_known AND pd.shelf_state IN ('in_stock', 'low_stock') THEN 1 ELSE 0 END)
    / NULLIF(SUM(CASE WHEN pd.is_known THEN 1 ELSE 0 END), 0) AS osa_pct_eod,
  -- The intraday floor over known positions: never observed OOS at any point that day.
  (SUM(CASE WHEN pd.is_known THEN 1 ELSE 0 END)
     - SUM(CASE WHEN pd.is_known THEN COALESCE(pd.was_oos_any_time, 0) ELSE 0 END))
    / NULLIF(SUM(CASE WHEN pd.is_known THEN 1 ELSE 0 END), 0) AS osa_pct_intraday_floor,
  -- Denominator honesty, published beside the headline.
  COUNT(pd.store_zone_id) / NULLIF(COUNT(*), 0) AS observation_coverage_pct,
  SUM(CASE WHEN pd.is_known THEN 1 ELSE 0 END) / NULLIF(COUNT(pd.store_zone_id), 0) AS known_state_pct,
  CAST(${shelf_as_of_ts} AS TIMESTAMP) AS fresh_as_of_ts
FROM expected e
LEFT JOIN position_day pd
  ON e.store_id = pd.store_id
 AND e.trading_date = pd.trading_date
 AND e.store_zone_id = pd.store_zone_id
 AND e.product_id = pd.product_id
GROUP BY e.store_id, e.trading_date, e.category;
