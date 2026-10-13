-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- View: gold_product_discovery_candidate_current
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- Current product candidate surface for organic intent product discovery.
-- Combines active product attributes, current list price, and the latest
-- product-store inventory signal when available. This is an analytical serving
-- view, not an operational vector index or application state store. Products
-- without a current inventory signal are retained but are not treated as buyable.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.gold_product_discovery_candidate_current AS
WITH latest_inventory AS (
  SELECT
    inventory_position_sk,
    inventory_position_id,
    product_sk,
    product_id,
    store_sk,
    store_id,
    date_key,
    units_on_hand_eod,
    is_stockout,
    size_availability_pct,
    ROW_NUMBER() OVER (
      PARTITION BY product_id, store_id
      ORDER BY date_key DESC, inventory_position_sk DESC
    ) AS rn
  FROM ${catalog}.${inventory_schema}.inventory_position
),
current_list_price AS (
  SELECT
    product_sk,
    product_id,
    amount AS current_list_price_amount,
    currency_code,
    ROW_NUMBER() OVER (
      PARTITION BY product_id
      ORDER BY effective_from_date DESC, product_price_sk DESC
    ) AS rn
  FROM ${catalog}.${product_schema}.product_price
  WHERE price_type = 'list'
    AND is_current = TRUE
)
SELECT
  p.product_id,
  p.gtin,
  p.sku,
  p.style_id,
  p.product_name,
  p.brand,
  p.category,
  p.subcategory,
  p.department,
  p.color,
  p.size,
  p.unit_of_measure,
  COALESCE(lp.current_list_price_amount, p.list_price) AS current_list_price_amount,
  COALESCE(lp.currency_code, p.currency_code) AS currency_code,
  li.store_id,
  li.date_key AS latest_inventory_date,
  li.units_on_hand_eod AS units_available,
  COALESCE(li.is_stockout = FALSE AND li.units_on_hand_eod > 0, FALSE) AS is_available_flag,
  li.size_availability_pct,
  p.product_status
FROM ${catalog}.${product_schema}.product p
LEFT JOIN current_list_price lp
  ON p.product_id = lp.product_id
 AND lp.rn = 1
LEFT JOIN latest_inventory li
  ON p.product_id = li.product_id
 AND li.rn = 1
WHERE p.is_current = TRUE
  AND p.product_status = 'active';
