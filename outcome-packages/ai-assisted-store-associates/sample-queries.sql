-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates · sample queries
-- Version: 0.5 · Generated: 2026-08-29 · LLM-generated: true · Reviewed: 2026-08-29
-- Illustrative read patterns against the gold views. Substitute ${catalog} and
-- ${aasa_schema} at deploy time. No raw customer or employee PII is exposed here.
-- ============================================================

-- 1. An associate's live prioritized queue (top of the list first).
SELECT queue_rank, action_type, current_priority_score, current_state, store_zone_id, minutes_to_expiry, suggested_action_id
FROM ${catalog}.${aasa_schema}.gold_associate_action_queue_current
WHERE associate_id = :associate_id
ORDER BY queue_rank;

-- 2. The single highest-value open action per associate (the "next best action").
SELECT associate_id, action_type, current_priority_score, store_zone_id, suggested_action_id
FROM ${catalog}.${aasa_schema}.gold_associate_action_queue_current
WHERE queue_rank = 1
ORDER BY current_priority_score DESC;

-- 3. Open queue depth and top priority by store — where is the floor under pressure?
SELECT store_id,
       COUNT(*)                     AS open_actions,
       COUNT(DISTINCT associate_id) AS associates_with_work,
       MAX(current_priority_score)  AS top_priority
FROM ${catalog}.${aasa_schema}.gold_associate_action_queue_current
GROUP BY store_id
ORDER BY open_actions DESC;

-- 4. Actions about to expire (transient opportunities closing) — act now.
SELECT associate_id, action_type, current_priority_score, minutes_to_expiry, suggested_action_id
FROM ${catalog}.${aasa_schema}.gold_associate_action_queue_current
WHERE minutes_to_expiry IS NOT NULL AND minutes_to_expiry <= 5
ORDER BY minutes_to_expiry;

-- 5. Acceptance and completion by action type (the effectiveness funnel).
SELECT action_type,
       SUM(actions_generated) AS generated,
       ROUND(SUM(actions_accepted)  / NULLIF(SUM(actions_generated), 0), 4) AS acceptance_rate,
       ROUND(SUM(actions_completed) / NULLIF(SUM(actions_generated), 0), 4) AS completion_rate,
       ROUND(SUM(response_seconds_total) / NULLIF(SUM(responses_timed), 0), 0) AS avg_response_seconds
FROM ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily
GROUP BY action_type
ORDER BY generated DESC;

-- 6. Per-associate effectiveness (what mv_associate_action_performance rolls up).
SELECT associate_id,
       SUM(actions_generated) AS generated,
       ROUND(SUM(actions_accepted)  / NULLIF(SUM(actions_generated), 0), 4) AS acceptance_rate,
       ROUND(SUM(actions_completed) / NULLIF(SUM(actions_generated), 0), 4) AS completion_rate,
       SUM(realized_outcome_value) AS realized_value
FROM ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily
WHERE associate_id IS NOT NULL
GROUP BY associate_id
ORDER BY realized_value DESC;

-- 7. The staffing signal: rejections concentrated by zone (rejections / generated).
SELECT store_id, store_zone_id,
       SUM(actions_generated) AS generated,
       SUM(actions_rejected)  AS rejected,
       ROUND(SUM(actions_rejected) / NULLIF(SUM(actions_generated), 0), 4) AS rejection_rate
FROM ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily
WHERE store_zone_id IS NOT NULL
GROUP BY store_id, store_zone_id
HAVING SUM(actions_generated) > 0
ORDER BY rejection_rate DESC;

-- 8. Realized ROI of the NBA program by store (attributed outcome value).
SELECT store_id,
       SUM(sales_closed)            AS sales_closed,
       SUM(realized_outcome_value)  AS realized_value,
       MIN(outcome_currency_code)   AS currency_code
FROM ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily
GROUP BY store_id
ORDER BY realized_value DESC;

-- 9. Rejection reasons (drill into the "why") — reads the response log directly.
SELECT reason_code, COUNT(*) AS rejections
FROM ${catalog}.${aasa_schema}.action_response_log
WHERE response_type = 'rejected'
GROUP BY reason_code
ORDER BY rejections DESC;

-- ---------------- Real-Time Data Access ----------------
-- 1) Product availability at a store (surface inventory_basis + warning)
SELECT product_id, product_name, stock_status,
       quantity_on_hand, quantity_available_to_sell,
       inventory_basis, location_basis, nearby_store_match_basis,
       nearby_store_with_stock_id,
       freshness_status, explanation, warning
FROM ${catalog}.${aasa_schema}.gold_associate_product_inventory_current
WHERE store_id = :store_id AND product_id = :product_id;

-- 2) Price and active promotion (no customer personalization)
SELECT product_id, base_price_amount, effective_selling_price_amount,
       active_promo_id, active_promo_name, store_channel_eligibility,
       customer_eligibility_status, freshness_status
FROM ${catalog}.${aasa_schema}.gold_associate_price_promotion_current
WHERE store_id = :store_id AND product_id = :product_id;

-- 3) Order fulfillment by exact order id (associate-safe columns only)
SELECT order_id, fulfillment_type, order_status, pickup_readiness,
       pickup_location_code, exception_state, requires_customer_verification,
       freshness_status, explanation
FROM ${catalog}.${aasa_schema}.gold_associate_order_status_current
WHERE order_id = :order_id AND store_id = :store_id;

-- 4) Open operational signals for a store
SELECT context_type, context_id, severity, signal_summary, freshness_status
FROM ${catalog}.${aasa_schema}.gold_associate_operational_context_current
WHERE store_id = :store_id
ORDER BY severity DESC, source_event_timestamp DESC;

-- 5) Freshness SLA breaches
SELECT feed_name, store_id, freshness_lag_minutes, freshness_status, sla_state
FROM ${catalog}.${aasa_schema}.gold_associate_data_freshness
WHERE sla_state = 'breach' OR freshness_status IN ('delayed', 'stale');

-- 6) Access-denied audit slice
SELECT request_id, capability, access_reason_code, response_status, latency_ms
FROM ${catalog}.${aasa_schema}.associate_lookup_audit
WHERE access_decision = 'deny'
ORDER BY request_timestamp DESC
LIMIT 100;
