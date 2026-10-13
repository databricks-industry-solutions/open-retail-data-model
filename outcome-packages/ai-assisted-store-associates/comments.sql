-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates · column comments
-- Version: 0.5 · Generated: 2026-08-29 · LLM-generated: true · Reviewed: 2026-08-29
-- Column-level documentation for the gold views (Genie / AI-BI / UC metadata, and
-- the source of column descriptions in the generated ODCS contract).
-- COMMENT ON COLUMN is standard SQL. Run AFTER the views exist.
-- ============================================================

-- ========== gold_associate_action_queue_current ==========

COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.associate_id IS 'Durable associate business key the queue belongs to.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.associate_role IS 'Associate job role (from the associate version at dispatch).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.associate_skill_tags IS 'Associate capability tags (pipe-delimited) used for skill matching.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.store_zone_id IS 'Durable target-zone id (logical reference to connected-store-signals.store_zone).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.suggested_action_id IS 'Durable action business key.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.action_type IS 'Task class: customer_assist, restock_shelf, bopis_fulfill, safety_loss_prevention, maintenance_cleaning, price_check, queue_bust, clienteling.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.trigger_source IS 'What fired the action (ble_beacon_dwell, pos_inventory_decrement, order_management_system, sensor_event, digital_interaction, schedule, manual).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.base_score IS 'Hierarchy-of-needs base score in [0,100] before dynamic multipliers/decay.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.priority_score IS 'Business Value Score at generation (before time decay), in [0,100].';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.current_priority_score IS 'Time-decayed Business Value Score the queue is ranked on, derived in-view from priority_score and decay_type since generated_timestamp.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.decay_type IS 'Relevance-decay curve applied to priority_score: linear, exponential, immediate_nullification, none.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.current_state IS 'Derived lifecycle state (open states only appear here): pending, or the latest non-terminal response (accepted / deferred / reassigned). Sourced from action_response_log, not a stored status.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.profile_id IS 'Durable, pseudonymous customer key the action concerns; NULL for customer-agnostic tasks.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.product_id IS 'Durable product key the action concerns; NULL when not product-specific.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.generated_timestamp IS 'When the action was generated/dispatched (UTC).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.expiration_timestamp IS 'When the action becomes stale; NULL for persistent tasks.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.minutes_to_expiry IS 'Minutes remaining until expiration at view evaluation time; NULL for persistent tasks.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.queue_rank IS 'Rank of the action within the associate''s open queue (1 = highest priority_score).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.context_payload IS 'Schemaless JSON payload the associate app renders (location, customer/product context, suggested dialogue).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_action_queue_current.fresh_as_of_ts IS 'View evaluation timestamp (UTC).';

-- ========== gold_action_outcome_funnel_daily ==========

COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.store_zone_id IS 'Durable target-zone id (logical reference to connected-store-signals.store_zone). NULL when the actions had no target zone; the grain that exposes the per-zone staffing signal.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.associate_id IS 'Durable associate business key the actions were routed to. NULL for unrouted actions; the grain for per-associate effectiveness.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.trading_date IS 'Business date the actions were generated.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.action_type IS 'Task class of the actions in the row.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.actions_generated IS 'Count of actions generated in the cell.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.actions_accepted IS 'Actions with an accepted response (from action_response_log).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.actions_rejected IS 'Actions with a rejected response (from action_response_log).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.actions_completed IS 'Actions with a completed response (from action_response_log).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.actions_expired IS 'Actions with an expired response (from action_response_log).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.acceptance_rate IS 'actions_accepted / actions_generated for the cell (ratio-of-sums-safe components are also exposed).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.completion_rate IS 'actions_completed / actions_generated for the cell.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.avg_response_seconds IS 'Mean seconds from dispatch to first response for the cell (display convenience; re-aggregate via response_seconds_total / responses_timed).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.response_seconds_total IS 'Sum of dispatch-to-first-response seconds; the additive numerator for average response time.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.responses_timed IS 'Count of actions that received a first response; the additive denominator for average response time.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.sales_closed IS 'Count of actions resolved as a closed sale.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.realized_outcome_value IS 'Sum of monetary outcomes attributed to the actions (in outcome_currency_code).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.outcome_currency_code IS 'ISO 4217 currency of realized_outcome_value (single reporting currency; see or_single_currency).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily.fresh_as_of_ts IS 'View evaluation timestamp (UTC).';

-- ---------------- Real-Time Data Access gold columns ----------------
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_product_inventory_current.product_id IS 'Durable product business key (SKU/item).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_product_inventory_current.store_id IS 'Durable store business key for the associate store scope.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_product_inventory_current.stock_status IS 'IN_STOCK, LOW_STOCK, OUT_OF_STOCK, or UNKNOWN.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_product_inventory_current.quantity_available_to_sell IS 'Available-to-sell units after reservations.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_product_inventory_current.inventory_basis IS 'daily_snapshot (EOD inventory_position only) or event_overlay (intra-day associate_context_event).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_product_inventory_current.location_basis IS 'event_location_code when optional free-text location_code is present; not_modeled when absent. No shelf/bay geo in ORDM.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_product_inventory_current.sales_floor_or_backroom_location IS 'Optional free-text location_code from an inventory event. Not aisle/bay coordinates.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_product_inventory_current.nearby_store_match_basis IS 'same_region_on_hand when a peer store is suggested — not distance-ranked.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_product_inventory_current.nearby_store_with_stock_id IS 'Same-region active store with on-hand > 0 (qty then store_id). Not geo-nearest.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_product_inventory_current.freshness_status IS 'For event_overlay: lag bands. For daily_snapshot: calendar age of date_key (EOD semantics — not live shelf).';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_product_inventory_current.explanation IS 'Human-readable provenance for associate UI display; states EOD vs overlay and nearby-match rule.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_product_inventory_current.warning IS 'Honesty warning for EOD grain, stale overlay, or incomplete location; NULL when none.';

COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_price_promotion_current.base_price_amount IS 'Current base/list unit price in reporting currency.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_price_promotion_current.effective_selling_price_amount IS 'Effective selling unit price after known store promo mechanics.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_price_promotion_current.customer_eligibility_status IS 'Always CUSTOMER_ELIGIBILITY_REQUIRES_AUTHORIZED_CONTEXT for associate gold.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_price_promotion_current.active_promo_id IS 'Active store-scoped promotion id, if any.';

COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_order_status_current.order_id IS 'Exact order business key required for lookup.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_order_status_current.pickup_readiness IS 'not_ready, ready, overdue, completed, or not_applicable.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_order_status_current.requires_customer_verification IS 'TRUE when associate must verify customer before detail release.';

COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_operational_context_current.context_type IS 'replenishment_task, equipment_alert, or operations signal type.';
COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_operational_context_current.severity IS 'info/medium/high style severity safe for associate display.';

COMMENT ON COLUMN ${catalog}.${aasa_schema}.gold_associate_data_freshness.sla_state IS 'within_sla or breach vs 60-minute associate freshness objective.';

-- ========== Genie Ontology authority (ADR 0010) ==========
-- system.certification_status = certified ranks these surfaces as authoritative.
-- ASSIGN rights are deployment-specific (Definition of Done "Certified").
-- Lives here (not in gold/*.sql) because each gold file is one CREATE statement.
-- For demoted MVs use ALTER VIEW on inventory/order instead of ALTER TABLE.

ALTER TABLE ${catalog}.${aasa_schema}.gold_associate_product_inventory_current
  SET TAGS ('system.certification_status' = 'certified');
ALTER TABLE ${catalog}.${aasa_schema}.gold_associate_order_status_current
  SET TAGS ('system.certification_status' = 'certified');
ALTER VIEW ${catalog}.${aasa_schema}.gold_associate_price_promotion_current
  SET TAGS ('system.certification_status' = 'certified');
ALTER VIEW ${catalog}.${aasa_schema}.gold_associate_operational_context_current
  SET TAGS ('system.certification_status' = 'certified');
ALTER VIEW ${catalog}.${aasa_schema}.gold_associate_data_freshness
  SET TAGS ('system.certification_status' = 'certified');

ALTER VIEW ${catalog}.${aasa_schema}.mv_associate_inventory_availability
  SET TAGS ('system.certification_status' = 'certified');
ALTER VIEW ${catalog}.${aasa_schema}.mv_associate_lookup_freshness
  SET TAGS ('system.certification_status' = 'certified');
ALTER VIEW ${catalog}.${aasa_schema}.mv_associate_lookup_audit_metrics
  SET TAGS ('system.certification_status' = 'certified');
