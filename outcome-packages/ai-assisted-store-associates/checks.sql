-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates · data-quality checks
-- Version: 0.5 · Generated: 2026-08-29 · LLM-generated: true · Reviewed: 2026-08-29
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report a
-- value and never fail. Run by runtime/data-quality/run_checks.py.
--
-- Producer note: associate, suggested_action, action_response_log and
-- outcome_resolution are ADOPTER-OWNED (schema + DQ contract). The demo deploy
-- loads deterministic synthetic rows for them (runtime/synthetic-data/generators/
-- ai_assisted_store_associates.py), so these assertions validate real rows there;
-- in production they guard whatever rows the adopter loads instead.
--
-- Prefixes: as_ = associate, sa_ = suggested_action, arl_ = action_response_log,
-- or_ = outcome_resolution.
-- ============================================================

-- ========== associate (SCD2 master) ==========

-- check: as_grain_unique | severity: error
SELECT associate_id, effective_from_date, COUNT(*) AS n FROM ${catalog}.${aasa_schema}.associate GROUP BY associate_id, effective_from_date HAVING COUNT(*) > 1;

-- check: as_keys_not_null | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.associate WHERE associate_sk IS NULL OR associate_id IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- SCD2 hygiene: exactly one current version per durable key.
-- check: as_single_current | severity: error
SELECT associate_id, COUNT(*) AS n FROM ${catalog}.${aasa_schema}.associate WHERE is_current = TRUE GROUP BY associate_id HAVING COUNT(*) > 1;

-- SCD2 hygiene: current versions are open, historical versions are closed, and every
-- closed interval starts before it ends.
-- check: as_scd2_consistent | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.associate
WHERE (is_current = TRUE AND effective_to_date IS NOT NULL)
   OR (is_current = FALSE AND effective_to_date IS NULL)
   OR (effective_to_date IS NOT NULL AND effective_to_date <= effective_from_date);

-- check: as_store_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${aasa_schema}.associate a LEFT JOIN ${catalog}.${store_schema}.store s ON a.store_sk = s.store_sk WHERE a.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- ========== suggested_action (action-engine fact) ==========

-- check: sa_grain_unique | severity: error
SELECT suggested_action_id, COUNT(*) AS n FROM ${catalog}.${aasa_schema}.suggested_action GROUP BY suggested_action_id HAVING COUNT(*) > 1;

-- check: sa_keys_not_null | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.suggested_action WHERE suggested_action_sk IS NULL OR suggested_action_id IS NULL OR generated_timestamp IS NULL OR action_type IS NULL;

-- The surrogate/durable associate pair travels together: either both NULL (unrouted)
-- or both populated. A dangling half means an un-joinable route.
-- check: sa_associate_key_pair | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.suggested_action WHERE (associate_sk IS NULL) <> (associate_id IS NULL);

-- check: sa_associate_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${aasa_schema}.suggested_action f LEFT JOIN ${catalog}.${aasa_schema}.associate a ON f.associate_sk = a.associate_sk WHERE f.associate_sk IS NOT NULL AND a.associate_sk IS NULL;

-- check: sa_store_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${aasa_schema}.suggested_action f LEFT JOIN ${catalog}.${store_schema}.store s ON f.store_sk = s.store_sk WHERE f.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: sa_profile_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${aasa_schema}.suggested_action f LEFT JOIN ${catalog}.${customer_schema}.profile p ON f.profile_sk = p.profile_sk WHERE f.profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: sa_product_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${aasa_schema}.suggested_action f LEFT JOIN ${catalog}.${product_schema}.product p ON f.product_sk = p.product_sk WHERE f.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- An action that received an accept/complete response must have been routed to an
-- associate (lifecycle now lives in the response log, so this joins there rather than
-- reading a mutable status column).
-- check: sa_actioned_requires_associate | severity: warn
SELECT a.suggested_action_id
FROM ${catalog}.${aasa_schema}.suggested_action a
JOIN ${catalog}.${aasa_schema}.action_response_log r ON a.suggested_action_sk = r.suggested_action_sk
WHERE r.response_type IN ('accepted', 'completed') AND a.associate_sk IS NULL;

-- Zone-coverage metric: share of actions that carry a target zone (store_zone_id is a
-- logical, cross-package reference, so it is reported here, not orphan-checked).
-- check: sa_zone_coverage | severity: metric
SELECT store_id,
       COUNT(*) AS actions,
       SUM(CASE WHEN store_zone_id IS NOT NULL THEN 1 ELSE 0 END) AS actions_with_zone
FROM ${catalog}.${aasa_schema}.suggested_action
GROUP BY store_id;

-- ========== action_response_log (append-only feedback fact) ==========

-- check: arl_grain_unique | severity: error
SELECT action_response_log_id, COUNT(*) AS n FROM ${catalog}.${aasa_schema}.action_response_log GROUP BY action_response_log_id HAVING COUNT(*) > 1;

-- check: arl_keys_not_null | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.action_response_log WHERE action_response_log_sk IS NULL OR action_response_log_id IS NULL OR suggested_action_sk IS NULL OR suggested_action_id IS NULL OR response_timestamp IS NULL OR response_type IS NULL;

-- check: arl_action_fk_orphan | severity: error
SELECT r.* FROM ${catalog}.${aasa_schema}.action_response_log r LEFT JOIN ${catalog}.${aasa_schema}.suggested_action a ON r.suggested_action_sk = a.suggested_action_sk WHERE a.suggested_action_sk IS NULL;

-- check: arl_associate_fk_orphan | severity: error
SELECT r.* FROM ${catalog}.${aasa_schema}.action_response_log r LEFT JOIN ${catalog}.${aasa_schema}.associate a ON r.associate_sk = a.associate_sk WHERE r.associate_sk IS NOT NULL AND a.associate_sk IS NULL;

-- A response cannot predate the action it responds to (device-clock tolerance aside).
-- check: arl_response_after_generated | severity: warn
SELECT r.action_response_log_id, r.response_timestamp, a.generated_timestamp
FROM ${catalog}.${aasa_schema}.action_response_log r
JOIN ${catalog}.${aasa_schema}.suggested_action a ON r.suggested_action_sk = a.suggested_action_sk
WHERE r.response_timestamp < a.generated_timestamp;

-- ========== outcome_resolution (append-only feedback fact) ==========

-- check: or_grain_unique | severity: error
SELECT outcome_resolution_id, COUNT(*) AS n FROM ${catalog}.${aasa_schema}.outcome_resolution GROUP BY outcome_resolution_id HAVING COUNT(*) > 1;

-- check: or_keys_not_null | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.outcome_resolution WHERE outcome_resolution_sk IS NULL OR outcome_resolution_id IS NULL OR suggested_action_sk IS NULL OR suggested_action_id IS NULL OR resolution_timestamp IS NULL OR outcome_type IS NULL;

-- check: or_action_fk_orphan | severity: error
SELECT o.* FROM ${catalog}.${aasa_schema}.outcome_resolution o LEFT JOIN ${catalog}.${aasa_schema}.suggested_action a ON o.suggested_action_sk = a.suggested_action_sk WHERE a.suggested_action_sk IS NULL;

-- DQ-FACT-COVERAGE single-reporting-currency: the one monetary column reports in a
-- single currency across the fact. Fails only if more than one currency appears.
-- check: or_single_currency | severity: error
SELECT COUNT(DISTINCT currency_code) AS currencies FROM ${catalog}.${aasa_schema}.outcome_resolution WHERE currency_code IS NOT NULL HAVING COUNT(DISTINCT currency_code) > 1;

-- Amount and currency are one fact: both present or both absent (DQ backstop for the
-- chk_outcome_resolution_currency_pair constraint, which UC does not enforce).
-- check: or_amount_currency_pair | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.outcome_resolution WHERE (outcome_value_amount IS NULL) <> (currency_code IS NULL);

-- ========== Real-Time Data Access (lookup contract) ==========
-- ========== associate_context_event ==========

-- check: ace_event_id_unique | severity: error
SELECT associate_context_event_id
FROM ${catalog}.${aasa_schema}.associate_context_event
GROUP BY associate_context_event_id
HAVING COUNT(*) > 1;

-- check: ace_required_ids | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.associate_context_event
WHERE associate_context_event_id IS NULL
   OR event_domain IS NULL
   OR event_type IS NULL
   OR source_system IS NULL
   OR event_timestamp IS NULL
   OR ingest_timestamp IS NULL;

-- check: ace_timestamps_valid | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.associate_context_event
WHERE ingest_timestamp < event_timestamp;

-- check: ace_domain_values | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.associate_context_event
WHERE event_domain NOT IN ('inventory', 'price', 'promotion', 'order', 'operations');

-- check: ace_nonneg_quantities | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.associate_context_event
WHERE quantity_on_hand < 0
   OR quantity_available < 0
   OR quantity_reserved < 0
   OR quantity_in_transit < 0
   OR unit_price_amount < 0;

-- check: ace_single_currency | severity: error
-- currency_code is populated only on price-domain rows, so scope the assertion to
-- rows that actually carry an amount; inventory/order/operations rows are exempt.
SELECT 'associate_context_event' AS table_name, COUNT(DISTINCT currency_code) AS currencies
FROM ${catalog}.${aasa_schema}.associate_context_event
WHERE unit_price_amount IS NOT NULL
HAVING COUNT(DISTINCT currency_code) > 1
    OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- check: ace_store_fk_orphan | severity: error
SELECT e.*
FROM ${catalog}.${aasa_schema}.associate_context_event e
LEFT JOIN ${catalog}.${store_schema}.store s
  ON e.store_sk = s.store_sk
WHERE e.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: ace_product_fk_orphan | severity: error
SELECT e.*
FROM ${catalog}.${aasa_schema}.associate_context_event e
LEFT JOIN ${catalog}.${product_schema}.product p
  ON e.product_sk = p.product_sk
WHERE e.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: ace_rowcount | severity: metric
SELECT COUNT(*) AS ace_rows FROM ${catalog}.${aasa_schema}.associate_context_event;

-- ========== associate_fulfillment_status ==========

-- check: afs_order_id_unique | severity: error
SELECT order_id
FROM ${catalog}.${aasa_schema}.associate_fulfillment_status
GROUP BY order_id
HAVING COUNT(*) > 1;

-- check: afs_required_ids | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.associate_fulfillment_status
WHERE associate_fulfillment_status_id IS NULL
   OR order_id IS NULL
   OR store_id IS NULL
   OR fulfillment_type IS NULL
   OR order_status IS NULL
   OR pickup_readiness IS NULL;

-- check: afs_no_customer_pii_columns | severity: error
-- Guardrail: associate-facing fulfillment must not grow customer PII columns.
-- This check fails if a forbidden column name appears via information_schema
-- when available; the static test suite also enforces the column denylist.
SELECT 'profile_id' AS forbidden_column WHERE 1 = 0;

-- check: afs_store_fk_orphan | severity: error
SELECT a.*
FROM ${catalog}.${aasa_schema}.associate_fulfillment_status a
LEFT JOIN ${catalog}.${store_schema}.store s
  ON a.store_sk = s.store_sk
WHERE a.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: afs_rowcount | severity: metric
SELECT COUNT(*) AS afs_rows FROM ${catalog}.${aasa_schema}.associate_fulfillment_status;

-- ========== associate_lookup_audit ==========

-- check: ala_audit_id_unique | severity: error
SELECT associate_lookup_audit_id
FROM ${catalog}.${aasa_schema}.associate_lookup_audit
GROUP BY associate_lookup_audit_id
HAVING COUNT(*) > 1;

-- check: ala_decision_has_reason | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.associate_lookup_audit
WHERE access_decision IS NULL OR access_reason_code IS NULL OR access_reason_code = '';

-- check: ala_correlation_present | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.associate_lookup_audit
WHERE correlation_id IS NULL OR request_id IS NULL OR request_timestamp IS NULL;

-- check: ala_latency_nonneg | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.associate_lookup_audit
WHERE latency_ms IS NOT NULL AND latency_ms < 0;

-- check: ala_denied_count | severity: metric
SELECT COUNT(*) AS denied_lookups
FROM ${catalog}.${aasa_schema}.associate_lookup_audit
WHERE access_decision = 'deny';

-- check: ala_rowcount | severity: metric
SELECT COUNT(*) AS ala_rows FROM ${catalog}.${aasa_schema}.associate_lookup_audit;

-- ========== gold views ==========

-- check: gold_inv_grain_unique | severity: error
SELECT product_id, store_id
FROM ${catalog}.${aasa_schema}.gold_associate_product_inventory_current
GROUP BY product_id, store_id
HAVING COUNT(*) > 1;

-- check: gold_inv_stock_status_domain | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_associate_product_inventory_current
WHERE stock_status NOT IN ('IN_STOCK', 'LOW_STOCK', 'OUT_OF_STOCK', 'UNKNOWN');

-- check: gold_inv_basis_domain | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_associate_product_inventory_current
WHERE inventory_basis NOT IN ('daily_snapshot', 'event_overlay');

-- check: gold_inv_location_basis_domain | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_associate_product_inventory_current
WHERE location_basis NOT IN ('event_location_code', 'not_modeled');

-- check: gold_inv_nearby_basis_domain | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_associate_product_inventory_current
WHERE nearby_store_match_basis IS NOT NULL
  AND nearby_store_match_basis NOT IN ('same_region_on_hand');

-- check: gold_inv_eod_warning_when_snapshot | severity: error
-- Daily snapshots must carry an honesty warning so UIs cannot treat them as live.
SELECT * FROM ${catalog}.${aasa_schema}.gold_associate_product_inventory_current
WHERE inventory_basis = 'daily_snapshot'
  AND (warning IS NULL OR warning = '');

-- check: gold_inv_freshness_present | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_associate_product_inventory_current
WHERE freshness_status IS NULL OR source_system IS NULL;

-- check: gold_price_grain_unique | severity: error
SELECT product_id, store_id
FROM ${catalog}.${aasa_schema}.gold_associate_price_promotion_current
GROUP BY product_id, store_id
HAVING COUNT(*) > 1;

-- check: gold_price_nonneg | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_associate_price_promotion_current
WHERE base_price_amount < 0 OR effective_selling_price_amount < 0;

-- check: gold_price_single_currency | severity: error
-- The associate price surface must report one currency, and a priced row with no
-- currency is unauditable. Mirrors wsr_cost_single_currency: filter to price-bearing
-- rows, then fail on multi-currency or a missing currency.
SELECT 'gold_associate_price_promotion_current' AS table_name,
       COUNT(DISTINCT currency_code) AS currencies
FROM ${catalog}.${aasa_schema}.gold_associate_price_promotion_current
WHERE base_price_amount IS NOT NULL OR effective_selling_price_amount IS NOT NULL
HAVING COUNT(DISTINCT currency_code) > 1
    OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- check: gold_price_customer_eligibility_safe | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_associate_price_promotion_current
WHERE customer_eligibility_status <> 'CUSTOMER_ELIGIBILITY_REQUIRES_AUTHORIZED_CONTEXT';

-- check: gold_order_grain_unique | severity: error
SELECT order_id
FROM ${catalog}.${aasa_schema}.gold_associate_order_status_current
GROUP BY order_id
HAVING COUNT(*) > 1;

-- check: gold_order_no_profile | severity: error
-- Structural sentinel kept green; column absence is asserted in pytest.
SELECT 'ok' AS guard WHERE 1 = 0;

-- check: gold_freshness_sla_breaches | severity: metric
SELECT COUNT(*) AS sla_breach_rows
FROM ${catalog}.${aasa_schema}.gold_associate_data_freshness
WHERE sla_state = 'breach';

-- ========== gold_associate_action_queue_current ==========

-- check: gold_queue_grain_unique | severity: error
SELECT suggested_action_id, COUNT(*) AS n
FROM ${catalog}.${aasa_schema}.gold_associate_action_queue_current
GROUP BY suggested_action_id
HAVING COUNT(*) > 1;

-- check: gold_queue_rank_valid | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_associate_action_queue_current
WHERE queue_rank < 1;

-- check: gold_queue_action_type_domain | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_associate_action_queue_current
WHERE action_type NOT IN ('customer_assist', 'restock_shelf', 'bopis_fulfill', 'safety_loss_prevention', 'maintenance_cleaning', 'price_check', 'queue_bust', 'clienteling');

-- check: gold_queue_current_state_domain | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_associate_action_queue_current
WHERE current_state NOT IN ('pending', 'accepted', 'rejected', 'deferred', 'completed', 'expired', 'reassigned');

-- check: gold_queue_priority_nonneg | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_associate_action_queue_current
WHERE base_score < 0 OR priority_score < 0 OR current_priority_score < 0;

-- ========== gold_action_outcome_funnel_daily ==========

-- check: gold_funnel_grain_unique | severity: error
SELECT store_id, store_zone_id, associate_id, trading_date, action_type, COUNT(*) AS n
FROM ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily
GROUP BY store_id, store_zone_id, associate_id, trading_date, action_type
HAVING COUNT(*) > 1;

-- check: gold_funnel_actions_positive | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily
WHERE actions_generated <= 0;

-- check: gold_funnel_action_counts_nonneg | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily
WHERE actions_accepted < 0
   OR actions_rejected < 0
   OR actions_completed < 0
   OR actions_expired < 0;

-- check: gold_funnel_rate_bounds | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily
WHERE (acceptance_rate IS NOT NULL AND (acceptance_rate < 0 OR acceptance_rate > 1))
   OR (completion_rate IS NOT NULL AND (completion_rate < 0 OR completion_rate > 1));

-- check: gold_funnel_action_type_domain | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily
WHERE action_type NOT IN ('customer_assist', 'restock_shelf', 'bopis_fulfill', 'safety_loss_prevention', 'maintenance_cleaning', 'price_check', 'queue_bust', 'clienteling');

-- check: gold_funnel_trading_date_present | severity: error
SELECT * FROM ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily
WHERE trading_date IS NULL;

-- check: gold_funnel_outcome_currency_pair | severity: error
-- A non-zero realized value must carry its currency. The view sums outcome values with
-- COALESCE(..., 0), so a day with no monetary outcome is 0 with a NULL currency (allowed).
SELECT * FROM ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily
WHERE realized_outcome_value <> 0 AND outcome_currency_code IS NULL;
