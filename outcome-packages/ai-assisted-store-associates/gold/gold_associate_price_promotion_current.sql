-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- View: gold_associate_price_promotion_current
-- Layer: outcome package (gold / consumable)
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================
-- Product × store current price and active promotion context at the
-- assortment grain (product×store pairs observed in inventory_position).
-- List / promotional prices from product_price (SCD2 current) and
-- product.list_price fallback; promotion coverage via marketing.promotion
-- + promote_with_purpose.promotion_scope when scoped to the store.
--
-- Never exposes loyalty, payment, margin, or customer-specific offers.
-- Customer eligibility is explicitly unresolved:
-- CUSTOMER_ELIGIBILITY_REQUIRES_AUTHORIZED_CONTEXT.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${aasa_schema}.gold_associate_price_promotion_current AS
WITH assortment AS (
  SELECT DISTINCT product_id, store_id
  FROM ${catalog}.${inventory_schema}.inventory_position
),
current_list AS (
  SELECT
    pp.product_id,
    pp.amount AS list_amount,
    pp.currency_code,
    pp.source_updated_timestamp,
    pp.load_timestamp,
    pp.record_source,
    ROW_NUMBER() OVER (
      PARTITION BY pp.product_id
      ORDER BY pp.effective_from_date DESC, pp.product_price_sk DESC
    ) AS rn
  FROM ${catalog}.${product_schema}.product_price pp
  WHERE pp.price_type = 'list' AND pp.is_current = TRUE
),
current_promo_price AS (
  SELECT
    pp.product_id,
    pp.amount AS promo_amount,
    pp.effective_from_date,
    pp.effective_to_date,
    pp.load_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY pp.product_id
      ORDER BY pp.effective_from_date DESC, pp.product_price_sk DESC
    ) AS rn
  FROM ${catalog}.${product_schema}.product_price pp
  WHERE pp.price_type = 'promotional' AND pp.is_current = TRUE
),
active_scope AS (
  SELECT
    ps.product_id,
    ps.store_id,
    pr.promo_id,
    pr.promo_name,
    pr.promo_type,
    pr.start_date,
    pr.end_date,
    pr.planned_discount_pct,
    pr.load_timestamp AS promo_load_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY ps.product_id, ps.store_id
      ORDER BY pr.start_date DESC, pr.promo_sk DESC
    ) AS rn
  FROM ${catalog}.${promo_schema}.promotion_scope ps
  JOIN ${catalog}.${marketing_schema}.promotion pr
    ON pr.promo_id = ps.promo_id
   AND pr.is_current = TRUE
   AND pr.promo_id <> 'NO_PROMO'
  WHERE CURRENT_DATE() BETWEEN pr.start_date AND COALESCE(pr.end_date, CURRENT_DATE())
),
price_event AS (
  SELECT
    e.*,
    ROW_NUMBER() OVER (
      PARTITION BY e.product_id, e.store_id
      ORDER BY e.event_timestamp DESC, e.ingest_timestamp DESC, e.associate_context_event_sk DESC
    ) AS rn
  FROM ${catalog}.${aasa_schema}.associate_context_event e
  WHERE e.event_domain IN ('price', 'promotion')
    AND e.product_id IS NOT NULL
    AND e.store_id IS NOT NULL
)
SELECT
  p.product_sk,
  p.product_id,
  p.sku,
  p.gtin,
  p.product_name,
  s.store_sk,
  s.store_id,
  s.store_name,
  COALESCE(ev.unit_price_amount, cl.list_amount, p.list_price) AS base_price_amount,
  COALESCE(
    ev.unit_price_amount,
    cpp.promo_amount,
    CASE
      WHEN ascope.planned_discount_pct IS NOT NULL
        THEN ROUND(
          COALESCE(cl.list_amount, p.list_price) * (1 - ascope.planned_discount_pct / 100.0),
          4
        )
      ELSE COALESCE(cl.list_amount, p.list_price)
    END
  ) AS effective_selling_price_amount,
  COALESCE(ev.currency_code, cl.currency_code, p.currency_code) AS currency_code,
  ascope.promo_id AS active_promo_id,
  ascope.promo_name AS active_promo_name,
  ascope.promo_type AS active_promo_type,
  ascope.start_date AS promo_start_date,
  ascope.end_date AS promo_end_date,
  CASE
    WHEN ascope.promo_id IS NOT NULL THEN 'store_channel_time_eligible'
    WHEN cpp.promo_amount IS NOT NULL THEN 'promotional_price_active'
    ELSE 'no_active_promotion'
  END AS store_channel_eligibility,
  'CUSTOMER_ELIGIBILITY_REQUIRES_AUTHORIZED_CONTEXT' AS customer_eligibility_status,
  COALESCE(ev.event_timestamp, cl.source_updated_timestamp, p.source_updated_timestamp) AS source_event_timestamp,
  COALESCE(ev.ingest_timestamp, cl.load_timestamp, p.load_timestamp) AS source_ingest_timestamp,
  COALESCE(ev.processed_timestamp, ascope.promo_load_timestamp, cl.load_timestamp, p.load_timestamp)
    AS current_state_updated_at,
  COALESCE(ev.source_system, cl.record_source, p.record_source) AS source_system,
  CASE
    WHEN COALESCE(ev.ingest_timestamp, cl.load_timestamp, p.load_timestamp) IS NULL THEN 'UNKNOWN'
    WHEN (UNIX_TIMESTAMP(CURRENT_TIMESTAMP())
          - UNIX_TIMESTAMP(COALESCE(ev.ingest_timestamp, cl.load_timestamp, p.load_timestamp))) > 86400
      THEN 'stale'
    WHEN (UNIX_TIMESTAMP(CURRENT_TIMESTAMP())
          - UNIX_TIMESTAMP(COALESCE(ev.ingest_timestamp, cl.load_timestamp, p.load_timestamp))) > 3600
      THEN 'delayed'
    ELSE 'fresh'
  END AS freshness_status,
  ROUND(
    (UNIX_TIMESTAMP(CURRENT_TIMESTAMP())
     - UNIX_TIMESTAMP(COALESCE(ev.ingest_timestamp, cl.load_timestamp, p.load_timestamp))) / 60.0,
    1
  ) AS freshness_lag_minutes,
  CASE
    WHEN ascope.promo_id IS NOT NULL
      THEN CONCAT('Active store-scoped promotion ', ascope.promo_id, '; customer-specific eligibility not evaluated.')
    ELSE 'Base/list price shown; no active store-scoped promotion in coverage.'
  END AS explanation,
  CASE
    WHEN COALESCE(ev.ingest_timestamp, cl.load_timestamp, p.load_timestamp) IS NOT NULL
     AND (UNIX_TIMESTAMP(CURRENT_TIMESTAMP())
          - UNIX_TIMESTAMP(COALESCE(ev.ingest_timestamp, cl.load_timestamp, p.load_timestamp))) > 3600
      THEN 'Price/promotion feed exceeds freshness SLA; verify shelf label before quoting.'
    ELSE CAST(NULL AS STRING)
  END AS warning
FROM assortment a
JOIN ${catalog}.${product_schema}.product p
  ON p.product_id = a.product_id AND p.is_current = TRUE
JOIN ${catalog}.${store_schema}.store s
  ON s.store_id = a.store_id AND s.is_current = TRUE
LEFT JOIN current_list cl
  ON cl.product_id = p.product_id AND cl.rn = 1
LEFT JOIN current_promo_price cpp
  ON cpp.product_id = p.product_id AND cpp.rn = 1
LEFT JOIN active_scope ascope
  ON ascope.rn = 1
 AND ascope.product_id = p.product_id
 AND ascope.store_id = s.store_id
LEFT JOIN price_event ev
  ON ev.rn = 1
 AND ev.product_id = p.product_id
 AND ev.store_id = s.store_id;
