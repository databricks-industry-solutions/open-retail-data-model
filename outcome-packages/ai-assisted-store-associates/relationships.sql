-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates · relationships
-- Version: 0.5
-- Generated: 2026-08-29
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-29
-- ============================================================
-- Foreign keys and CHECK constraints. Run AFTER the table DDL.
--
-- FKs are single-column on the parent _sk and are informational in Unity Catalog
-- (RELY NOT ENFORCED semantics) — the orphan checks in checks.sql are what actually
-- catch violations, so every FK here has a matching *_fk_orphan check.
--
-- All CHECKs are declared here via ALTER TABLE ADD CONSTRAINT, never inline in
-- CREATE TABLE: Databricks supports only PRIMARY/FOREIGN KEY inline, so an inline
-- CHECK fails to parse at deploy time (NO-INLINE-CHECK). Nullable enum columns carry
-- the explicit `IS NULL OR` guard (house convention; makes nullability visible at
-- the constraint even though Delta already treats a NULL CHECK result as a pass).
-- ============================================================

-- ---------------- associate (into canonical core) ----------------
ALTER TABLE ${catalog}.${aasa_schema}.associate ADD CONSTRAINT fk_associate_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

ALTER TABLE ${catalog}.${aasa_schema}.associate ADD CONSTRAINT chk_associate_role CHECK (role IS NULL OR role IN ('sales_associate', 'cashier', 'department_specialist', 'stock_associate', 'customer_service', 'team_lead', 'store_manager', 'visual_merchandiser', 'loss_prevention'));
ALTER TABLE ${catalog}.${aasa_schema}.associate ADD CONSTRAINT chk_associate_employment_type CHECK (employment_type IS NULL OR employment_type IN ('full_time', 'part_time', 'seasonal', 'contractor'));

-- ---------------- suggested_action ----------------
-- The associate FK is on the surrogate (version at dispatch); customer/product/store
-- FKs point into the canonical core. There is NO FK on store_zone_id: the target zone
-- lives in another outcome package (connected-store-signals), so it is a LOGICAL
-- reference resolved by convention (mirroring the CSS -> fiscal_calendar logical join),
-- validated in review rather than by a constraint or a cross-package orphan check —
-- a hard reference would make this package's deploy/DQ depend on CSS being present.
ALTER TABLE ${catalog}.${aasa_schema}.suggested_action ADD CONSTRAINT fk_suggested_action_associate FOREIGN KEY (associate_sk) REFERENCES ${catalog}.${aasa_schema}.associate (associate_sk);
ALTER TABLE ${catalog}.${aasa_schema}.suggested_action ADD CONSTRAINT fk_suggested_action_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${aasa_schema}.suggested_action ADD CONSTRAINT fk_suggested_action_profile FOREIGN KEY (profile_sk) REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);
ALTER TABLE ${catalog}.${aasa_schema}.suggested_action ADD CONSTRAINT fk_suggested_action_product FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${aasa_schema}.suggested_action ADD CONSTRAINT chk_suggested_action_type CHECK (action_type IN ('customer_assist', 'restock_shelf', 'bopis_fulfill', 'safety_loss_prevention', 'maintenance_cleaning', 'price_check', 'queue_bust', 'clienteling'));
ALTER TABLE ${catalog}.${aasa_schema}.suggested_action ADD CONSTRAINT chk_suggested_action_trigger CHECK (trigger_source IS NULL OR trigger_source IN ('ble_beacon_dwell', 'pos_inventory_decrement', 'order_management_system', 'sensor_event', 'digital_interaction', 'schedule', 'manual'));
-- No status CHECK: suggested_action is append-only (one row per action GENERATED); the
-- lifecycle lives in action_response_log (chk_action_response_log_type), not a mutable
-- status column here.
ALTER TABLE ${catalog}.${aasa_schema}.suggested_action ADD CONSTRAINT chk_suggested_action_decay CHECK (decay_type IS NULL OR decay_type IN ('linear', 'exponential', 'immediate_nullification', 'none'));
ALTER TABLE ${catalog}.${aasa_schema}.suggested_action ADD CONSTRAINT chk_suggested_action_base_score CHECK (base_score IS NULL OR base_score BETWEEN 0 AND 100);
ALTER TABLE ${catalog}.${aasa_schema}.suggested_action ADD CONSTRAINT chk_suggested_action_priority CHECK (priority_score IS NULL OR priority_score >= 0);
ALTER TABLE ${catalog}.${aasa_schema}.suggested_action ADD CONSTRAINT chk_suggested_action_expiry CHECK (expiration_timestamp IS NULL OR expiration_timestamp >= generated_timestamp);

-- ---------------- action_response_log ----------------
ALTER TABLE ${catalog}.${aasa_schema}.action_response_log ADD CONSTRAINT fk_action_response_log_action FOREIGN KEY (suggested_action_sk) REFERENCES ${catalog}.${aasa_schema}.suggested_action (suggested_action_sk);
ALTER TABLE ${catalog}.${aasa_schema}.action_response_log ADD CONSTRAINT fk_action_response_log_associate FOREIGN KEY (associate_sk) REFERENCES ${catalog}.${aasa_schema}.associate (associate_sk);

ALTER TABLE ${catalog}.${aasa_schema}.action_response_log ADD CONSTRAINT chk_action_response_log_type CHECK (response_type IN ('accepted', 'rejected', 'deferred', 'completed', 'expired', 'reassigned'));

-- ---------------- outcome_resolution ----------------
ALTER TABLE ${catalog}.${aasa_schema}.outcome_resolution ADD CONSTRAINT fk_outcome_resolution_action FOREIGN KEY (suggested_action_sk) REFERENCES ${catalog}.${aasa_schema}.suggested_action (suggested_action_sk);

ALTER TABLE ${catalog}.${aasa_schema}.outcome_resolution ADD CONSTRAINT chk_outcome_resolution_type CHECK (outcome_type IN ('sale_closed', 'item_restocked', 'customer_assisted', 'issue_resolved', 'task_abandoned', 'no_outcome'));
ALTER TABLE ${catalog}.${aasa_schema}.outcome_resolution ADD CONSTRAINT chk_outcome_resolution_amount CHECK (outcome_value_amount IS NULL OR outcome_value_amount >= 0);
ALTER TABLE ${catalog}.${aasa_schema}.outcome_resolution ADD CONSTRAINT chk_outcome_resolution_units CHECK (units_affected IS NULL OR units_affected >= 0);
-- A monetary amount is auditable only when its currency travels with it.
ALTER TABLE ${catalog}.${aasa_schema}.outcome_resolution ADD CONSTRAINT chk_outcome_resolution_currency_pair CHECK ((outcome_value_amount IS NULL AND currency_code IS NULL) OR (outcome_value_amount IS NOT NULL AND currency_code IS NOT NULL));

-- ---------------- Real-Time Data Access extension tables ----------------
-- The lookup-contract tables (associate_context_event, associate_fulfillment_status)
-- reference the canonical core only; they carry no FK into the action-queue tables
-- above, so either use case deploys without the other.
ALTER TABLE ${catalog}.${aasa_schema}.associate_context_event
  ADD CONSTRAINT fk_ace_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

ALTER TABLE ${catalog}.${aasa_schema}.associate_context_event
  ADD CONSTRAINT fk_ace_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${aasa_schema}.associate_fulfillment_status
  ADD CONSTRAINT fk_afs_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
