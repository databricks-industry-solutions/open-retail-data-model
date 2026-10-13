-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection
-- File: relationships.sql
-- Version: 0.5
-- Generated: 2026-06-30
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-30 by @sreekanthmunigati
-- ============================================================
-- Cross-schema relationships for the disruption detection extension
-- tables. UC foreign keys are informational (NOT ENFORCED). Run
-- AFTER the canonical-core logistics, supplier, product, store,
-- and inventory domains exist.
-- ============================================================

-- disruption_event -> disruption_rule
ALTER TABLE ${catalog}.${risk_schema}.disruption_event
  ADD CONSTRAINT fk_de_disruption_rule
  FOREIGN KEY (disruption_rule_sk) REFERENCES ${catalog}.${risk_schema}.disruption_rule (disruption_rule_sk);

-- disruption_event -> shipment (canonical core)
ALTER TABLE ${catalog}.${risk_schema}.disruption_event
  ADD CONSTRAINT fk_de_shipment
  FOREIGN KEY (shipment_sk) REFERENCES ${catalog}.${logistics_schema}.shipment (shipment_sk);

-- disruption_event -> supplier (canonical core)
ALTER TABLE ${catalog}.${risk_schema}.disruption_event
  ADD CONSTRAINT fk_de_supplier
  FOREIGN KEY (supplier_sk) REFERENCES ${catalog}.${supplier_schema}.supplier (supplier_sk);

-- disruption_event -> product (canonical core)
ALTER TABLE ${catalog}.${risk_schema}.disruption_event
  ADD CONSTRAINT fk_de_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

-- disruption_event -> store (canonical core)
ALTER TABLE ${catalog}.${risk_schema}.disruption_event
  ADD CONSTRAINT fk_de_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

-- disruption_event -> lane (canonical core)
ALTER TABLE ${catalog}.${risk_schema}.disruption_event
  ADD CONSTRAINT fk_de_lane
  FOREIGN KEY (lane_sk) REFERENCES ${catalog}.${logistics_schema}.lane (lane_sk);

-- disruption_alert -> disruption_event
ALTER TABLE ${catalog}.${risk_schema}.disruption_alert
  ADD CONSTRAINT fk_da_disruption_event
  FOREIGN KEY (disruption_event_sk) REFERENCES ${catalog}.${risk_schema}.disruption_event (disruption_event_sk);

-- disruption_alert -> disruption_rule
ALTER TABLE ${catalog}.${risk_schema}.disruption_alert
  ADD CONSTRAINT fk_da_disruption_rule
  FOREIGN KEY (disruption_rule_sk) REFERENCES ${catalog}.${risk_schema}.disruption_rule (disruption_rule_sk);
