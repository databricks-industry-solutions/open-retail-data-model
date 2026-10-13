-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- View: gold_intent_product_discovery_performance
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- Result-level performance surface for Intent Product Discovery. The view joins
-- the intent, ranked product result, product context, and engagement outcomes
-- while excluding raw prompt text, hashes, session identifiers, and customer IDs.
--
-- purchased_flag and purchased_units/purchase_net_amount use DIFFERENT attribution
-- rules ON PURPOSE, so they can disagree on a row:
--   * purchased_flag (from engagement_rollup) is per-result — TRUE if THIS result had
--     any purchase engagement.
--   * purchased_units / purchase_net_amount (from purchase_attribution) attribute each
--     order line's revenue to a SINGLE result (ROW_NUMBER over the order-line key), to
--     avoid double-counting one purchase across sibling results of the same intent.
-- So when one order line spans two sibling results, both get purchased_flag=TRUE but
-- only the first (by engagement_ts) carries the units/amount; the other reads 0. Read
-- purchased_flag as "this result led to a purchase" and the amounts as "revenue
-- attributed once per order line," never as "flag implies this result's revenue > 0."
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.gold_intent_product_discovery_performance AS
WITH engagement_rollup AS (
  SELECT
    discovery_result_event_id,
    MAX(CASE WHEN engagement_type = 'view' THEN 1 ELSE 0 END) AS viewed_flag_int,
    MAX(CASE WHEN engagement_type = 'select' THEN 1 ELSE 0 END) AS selected_flag_int,
    MAX(CASE WHEN engagement_type = 'add_to_cart' THEN 1 ELSE 0 END) AS added_to_cart_flag_int,
    MAX(CASE WHEN engagement_type = 'purchase' THEN 1 ELSE 0 END) AS purchased_flag_int,
    COUNT(*) AS engagement_count,
    MIN(engagement_ts) AS first_engagement_ts
  FROM ${catalog}.${ac_schema}.discovery_engagement_event
  GROUP BY discovery_result_event_id
),
purchase_attribution AS (
  SELECT
    discovery_result_event_id,
    quantity,
    net_amount,
    engagement_ts,
    ROW_NUMBER() OVER (
      PARTITION BY COALESCE(
        CAST(order_line_sk AS STRING),
        order_line_id,
        discovery_engagement_event_id
      )
      ORDER BY engagement_ts, discovery_engagement_event_sk
    ) AS attribution_rn
  FROM ${catalog}.${ac_schema}.discovery_engagement_event
  WHERE engagement_type = 'purchase'
),
purchase_rollup AS (
  SELECT
    discovery_result_event_id,
    SUM(COALESCE(quantity, 0)) AS purchased_units,
    SUM(COALESCE(net_amount, 0)) AS purchase_net_amount,
    MIN(engagement_ts) AS purchase_ts
  FROM purchase_attribution
  WHERE attribution_rn = 1
  GROUP BY discovery_result_event_id
)
SELECT
  r.discovery_result_event_id,
  r.discovery_intent_event_id,
  i.event_date AS intent_date,
  i.event_ts AS intent_ts,
  i.discovery_channel,
  i.locale_code,
  i.jurisdiction_code,
  i.intent_category,
  i.intent_confidence_score,
  i.profile_sk IS NOT NULL AS known_customer_flag,
  i.personalization_eligible_flag,
  i.consent_status,
  r.product_id,
  p.product_name,
  p.brand,
  p.category,
  p.subcategory,
  p.department,
  r.store_id,
  r.result_rank,
  r.retrieval_score,
  r.ranking_score,
  r.personalization_score,
  r.availability_score,
  r.reason_code,
  r.is_available_flag,
  r.units_available,
  r.list_price_amount,
  r.currency_code,
  COALESCE(e.viewed_flag_int, 0) = 1 AS viewed_flag,
  COALESCE(e.selected_flag_int, 0) = 1 AS selected_flag,
  COALESCE(e.added_to_cart_flag_int, 0) = 1 AS added_to_cart_flag,
  COALESCE(e.purchased_flag_int, 0) = 1 AS purchased_flag,
  COALESCE(e.engagement_count, 0) AS engagement_count,
  COALESCE(pr.purchased_units, 0) AS purchased_units,
  COALESCE(pr.purchase_net_amount, 0) AS purchase_net_amount,
  e.first_engagement_ts,
  pr.purchase_ts
FROM ${catalog}.${ac_schema}.discovery_result_event r
JOIN ${catalog}.${ac_schema}.discovery_intent_event i
  ON r.discovery_intent_event_id = i.discovery_intent_event_id
LEFT JOIN ${catalog}.${product_schema}.product p
  ON r.product_sk = p.product_sk
LEFT JOIN engagement_rollup e
  ON r.discovery_result_event_id = e.discovery_result_event_id
LEFT JOIN purchase_rollup pr
  ON r.discovery_result_event_id = pr.discovery_result_event_id;
