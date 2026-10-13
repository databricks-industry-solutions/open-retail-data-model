-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- View: gold_share_of_shelf_current
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Ideal Lakebase serving projection.
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- ============================================================
-- GRAIN: one row per store × category × brand at the latest observed state.
--
-- Share-of-shelf = brand facings / total category facings, on a FACINGS basis (the
-- research-declared basis; cm/area bases are adopter variants). ADDITIVE ONLY within
-- one store × category at one evaluation instant: shares must never be summed across
-- categories, stores, or points in time — the denominator changes under you. The
-- category facings total is repeated on every row so a consumer can re-derive and so
-- the additivity boundary is visible in the data.
--
-- Sourced from gold_shelf_state_current: usable, non-stale rows only (an unknown or
-- stale position contributes no facings — that is a coverage fact, not a zero share).
-- Brand/category resolve through the version-pinned product _sk (§A.16).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.gold_share_of_shelf_current AS
WITH usable AS (
  SELECT
    s.store_id,
    p.category,
    p.brand,
    s.observed_facing_count,
    s.fresh_as_of_ts
  FROM ${catalog}.${css_schema}.gold_shelf_state_current s
  JOIN ${catalog}.${product_schema}.product p
    ON s.product_sk = p.product_sk
  WHERE s.is_usable
    AND NOT s.is_stale
    AND s.observed_facing_count IS NOT NULL
    AND p.category IS NOT NULL
), brand_level AS (
  SELECT
    store_id,
    category,
    brand,
    SUM(observed_facing_count) AS brand_facing_count,
    MAX(fresh_as_of_ts) AS fresh_as_of_ts
  FROM usable
  GROUP BY store_id, category, brand
)
SELECT
  store_id,
  category,
  brand,
  brand_facing_count,
  SUM(brand_facing_count) OVER (PARTITION BY store_id, category) AS category_facing_count,
  brand_facing_count
    / NULLIF(SUM(brand_facing_count) OVER (PARTITION BY store_id, category), 0) AS share_of_shelf_pct,
  fresh_as_of_ts
FROM brand_level;
