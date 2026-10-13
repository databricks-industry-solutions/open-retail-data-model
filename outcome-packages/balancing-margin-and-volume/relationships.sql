-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume
-- File: relationships.sql
-- Version: 0.5
-- Generated: 2026-06-29
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-29 by @ojasvi-goyal-03
-- ============================================================
-- Relationships for the Balancing Margin and Volume structures. 
-- UC foreign keys are informational (NOT ENFORCED) and reference 
-- the parent surrogate PK.
-- ============================================================

-- Note: The gold_assortment_optimization and gold_sales_actuals views structurally 
-- depend on canonical inventory.inventory_position for KPI inputs (units_on_hand_eod, 
-- units_received_today), but as materialized views, no strict FKs are enforced here.

-- competitor_price -> competitor / product (surrogate FKs)
ALTER TABLE ${catalog}.${bmv_schema}.competitor_price
  ADD CONSTRAINT fk_competitor_price_competitor
  FOREIGN KEY (competitor_sk) REFERENCES ${catalog}.${bmv_schema}.competitor (competitor_sk);

ALTER TABLE ${catalog}.${bmv_schema}.competitor_price
  ADD CONSTRAINT fk_competitor_price_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

-- product_relationship -> product / related_product (surrogate FKs)
ALTER TABLE ${catalog}.${bmv_schema}.product_relationship
  ADD CONSTRAINT fk_product_relationship_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${bmv_schema}.product_relationship
  ADD CONSTRAINT fk_product_relationship_related_product
  FOREIGN KEY (related_product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

-- planogram -> store / product (surrogate FKs / durable IDs)
ALTER TABLE ${catalog}.${bmv_schema}.planogram
  ADD CONSTRAINT fk_planogram_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

ALTER TABLE ${catalog}.${bmv_schema}.planogram
  ADD CONSTRAINT fk_planogram_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);
