-- ============================================================
-- ORDM · Canonical Core · Inventory domain · data-quality checks
-- Version: 0.5
-- Generated: 2026-06-23
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-23 by @ojasvi-goyal-03
-- ============================================================
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report
-- a value and never fail the run.
-- ============================================================

-- check: inv_pos_pk_unique | severity: error
SELECT inventory_position_sk
FROM ${catalog}.${inventory_schema}.inventory_position
GROUP BY inventory_position_sk
HAVING COUNT(*) > 1;

-- check: inv_pos_grain_unique | severity: error
SELECT product_id, store_id, date_key
FROM ${catalog}.${inventory_schema}.inventory_position
GROUP BY product_id, store_id, date_key
HAVING COUNT(*) > 1;

-- check: inv_pos_product_fk_orphan | severity: error
SELECT i.* FROM ${catalog}.${inventory_schema}.inventory_position i
LEFT JOIN ${catalog}.${product_schema}.product p ON i.product_sk = p.product_sk
WHERE p.product_sk IS NULL AND i.product_sk IS NOT NULL;

-- check: inv_pos_store_fk_orphan | severity: error
SELECT i.* FROM ${catalog}.${inventory_schema}.inventory_position i
LEFT JOIN ${catalog}.${store_schema}.store s ON i.store_sk = s.store_sk
WHERE s.store_sk IS NULL AND i.store_sk IS NOT NULL;

-- check: inv_pos_nonnegative_units | severity: error
-- Physical inventory cannot be negative.
SELECT * FROM ${catalog}.${inventory_schema}.inventory_position
WHERE units_on_hand_eod < 0 OR units_on_hand_sod < 0;

-- check: inv_pos_stockout_pct_domain | severity: error
-- percentage domain must be between 0 and 1.
SELECT * FROM ${catalog}.${inventory_schema}.inventory_position
WHERE stockout_pct_day < 0.0 OR stockout_pct_day > 1.0
   OR size_availability_pct < 0.0 OR size_availability_pct > 1.0;

-- check: inv_pos_rowcount | severity: metric
SELECT COUNT(*) AS inv_pos_rows FROM ${catalog}.${inventory_schema}.inventory_position;

-- check: inv_pos_stockout_rate_global | severity: metric
SELECT ROUND(AVG(CASE WHEN is_stockout = TRUE THEN 1.0 ELSE 0.0 END), 4) AS global_stockout_rate
FROM ${catalog}.${inventory_schema}.inventory_position;
