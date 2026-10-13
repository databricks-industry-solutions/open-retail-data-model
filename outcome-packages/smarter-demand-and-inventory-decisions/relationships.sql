-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- File: relationships.sql
-- Layer: outcome package (informational FKs)
-- Version: 0.5
-- Generated: 2026-07-21
-- ============================================================
-- Cross-schema relationships for extension tables. UC foreign keys
-- are informational (NOT ENFORCED). Run AFTER canonical-core domains
-- and outcome-package tables exist.
-- ============================================================

-- planning_unit -> core dimensions
ALTER TABLE ${catalog}.${sdi_schema}.planning_unit
  ADD CONSTRAINT fk_pu_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);
ALTER TABLE ${catalog}.${sdi_schema}.planning_unit
  ADD CONSTRAINT fk_pu_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${sdi_schema}.planning_unit
  ADD CONSTRAINT fk_pu_account
  FOREIGN KEY (account_sk) REFERENCES ${catalog}.${customer_schema}.account (account_sk);

-- planning_unit_segment -> planning_unit
ALTER TABLE ${catalog}.${sdi_schema}.planning_unit_segment
  ADD CONSTRAINT fk_pus_planning_unit
  FOREIGN KEY (planning_unit_sk) REFERENCES ${catalog}.${sdi_schema}.planning_unit (planning_unit_sk);

-- demand forecasting chain
ALTER TABLE ${catalog}.${sdi_schema}.demand_forecast
  ADD CONSTRAINT fk_df_model_run
  FOREIGN KEY (model_run_sk) REFERENCES ${catalog}.${sdi_schema}.forecast_model_run (model_run_sk);
ALTER TABLE ${catalog}.${sdi_schema}.demand_forecast
  ADD CONSTRAINT fk_df_planning_unit
  FOREIGN KEY (planning_unit_sk) REFERENCES ${catalog}.${sdi_schema}.planning_unit (planning_unit_sk);
ALTER TABLE ${catalog}.${sdi_schema}.forecast_component
  ADD CONSTRAINT fk_fc_demand_forecast
  FOREIGN KEY (demand_forecast_sk) REFERENCES ${catalog}.${sdi_schema}.demand_forecast (demand_forecast_sk);
ALTER TABLE ${catalog}.${sdi_schema}.forecast_adjustment
  ADD CONSTRAINT fk_fa_planning_unit
  FOREIGN KEY (planning_unit_sk) REFERENCES ${catalog}.${sdi_schema}.planning_unit (planning_unit_sk);
ALTER TABLE ${catalog}.${sdi_schema}.forecast_accuracy
  ADD CONSTRAINT fk_fac_planning_unit
  FOREIGN KEY (planning_unit_sk) REFERENCES ${catalog}.${sdi_schema}.planning_unit (planning_unit_sk);
ALTER TABLE ${catalog}.${sdi_schema}.order_forecast
  ADD CONSTRAINT fk_of_planning_unit
  FOREIGN KEY (planning_unit_sk) REFERENCES ${catalog}.${sdi_schema}.planning_unit (planning_unit_sk);
ALTER TABLE ${catalog}.${sdi_schema}.order_forecast
  ADD CONSTRAINT fk_of_demand_forecast
  FOREIGN KEY (demand_forecast_sk) REFERENCES ${catalog}.${sdi_schema}.demand_forecast (demand_forecast_sk);
ALTER TABLE ${catalog}.${sdi_schema}.order_forecast
  ADD CONSTRAINT fk_of_inventory_policy
  FOREIGN KEY (inventory_policy_sk) REFERENCES ${catalog}.${sdi_schema}.inventory_policy (inventory_policy_sk);
ALTER TABLE ${catalog}.${sdi_schema}.order_forecast
  ADD CONSTRAINT fk_of_destination_store
  FOREIGN KEY (destination_store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

-- inventory optimization chain
ALTER TABLE ${catalog}.${sdi_schema}.inventory_policy
  ADD CONSTRAINT fk_ip_planning_unit
  FOREIGN KEY (planning_unit_sk) REFERENCES ${catalog}.${sdi_schema}.planning_unit (planning_unit_sk);
ALTER TABLE ${catalog}.${sdi_schema}.inventory_policy
  ADD CONSTRAINT fk_ip_service_level_target
  FOREIGN KEY (service_level_target_sk) REFERENCES ${catalog}.${sdi_schema}.service_level_target (service_level_target_sk);
ALTER TABLE ${catalog}.${sdi_schema}.inventory_policy_calculation
  ADD CONSTRAINT fk_ipc_inventory_policy
  FOREIGN KEY (inventory_policy_sk) REFERENCES ${catalog}.${sdi_schema}.inventory_policy (inventory_policy_sk);
ALTER TABLE ${catalog}.${sdi_schema}.inventory_recommendation
  ADD CONSTRAINT fk_ir_planning_unit
  FOREIGN KEY (planning_unit_sk) REFERENCES ${catalog}.${sdi_schema}.planning_unit (planning_unit_sk);
ALTER TABLE ${catalog}.${sdi_schema}.inventory_recommendation
  ADD CONSTRAINT fk_ir_inventory_policy
  FOREIGN KEY (inventory_policy_sk) REFERENCES ${catalog}.${sdi_schema}.inventory_policy (inventory_policy_sk);

-- OOS optimization chain
ALTER TABLE ${catalog}.${sdi_schema}.oos_event
  ADD CONSTRAINT fk_oe_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);
ALTER TABLE ${catalog}.${sdi_schema}.oos_event
  ADD CONSTRAINT fk_oe_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${sdi_schema}.lost_sales_estimate
  ADD CONSTRAINT fk_lse_oos_event
  FOREIGN KEY (oos_event_sk) REFERENCES ${catalog}.${sdi_schema}.oos_event (oos_event_sk);
ALTER TABLE ${catalog}.${sdi_schema}.demand_sensing_signal
  ADD CONSTRAINT fk_dss_planning_unit
  FOREIGN KEY (planning_unit_sk) REFERENCES ${catalog}.${sdi_schema}.planning_unit (planning_unit_sk);
ALTER TABLE ${catalog}.${sdi_schema}.demand_sensing_signal
  ADD CONSTRAINT fk_dss_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);
ALTER TABLE ${catalog}.${sdi_schema}.demand_sensing_signal
  ADD CONSTRAINT fk_dss_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${sdi_schema}.demand_sensing_signal
  ADD CONSTRAINT fk_dss_oos_event
  FOREIGN KEY (linked_oos_event_sk) REFERENCES ${catalog}.${sdi_schema}.oos_event (oos_event_sk);
ALTER TABLE ${catalog}.${sdi_schema}.oos_recovery_action
  ADD CONSTRAINT fk_ora_oos_event
  FOREIGN KEY (oos_event_sk) REFERENCES ${catalog}.${sdi_schema}.oos_event (oos_event_sk);
ALTER TABLE ${catalog}.${sdi_schema}.oos_recovery_action
  ADD CONSTRAINT fk_ora_inventory_recommendation
  FOREIGN KEY (inventory_recommendation_sk) REFERENCES ${catalog}.${sdi_schema}.inventory_recommendation (inventory_recommendation_sk);
ALTER TABLE ${catalog}.${sdi_schema}.oos_recovery_action
  ADD CONSTRAINT fk_ora_po_line
  FOREIGN KEY (linked_po_line_sk) REFERENCES ${catalog}.${procurement_schema}.purchase_order_line (po_line_sk);
