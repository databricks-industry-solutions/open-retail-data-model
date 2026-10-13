-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- Sample Queries
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-13 by @a0x8o
-- ============================================================

-- 1. Which promotions paid off? Top promotions by return on trade spend,
-- with realized against planned lift. Reads gold_promo_roi alone (already one row per promo).
SELECT
    promo_id,
    promo_name,
    promo_type,
    funding_type,
    funded_by,
    start_date,
    end_date,
    trade_spend,
    incremental_margin,
    net_incremental_margin,
    roi,
    planned_lift_pct,
    realized_lift_pct,
    (realized_lift_pct - planned_lift_pct) AS lift_variance_pct
FROM ${catalog}.${promo_schema}.gold_promo_roi
WHERE trade_spend > 0
ORDER BY roi DESC
LIMIT 25;

-- 2. Where does incremental margin leak away? ROI at promo x category grain with the
-- cannibalization and forward-buy drag. Reads gold_promo_roi_by_category, where the drag is decomposed.
SELECT
    promo_id,
    promo_name,
    category,
    incremental_units,
    incremental_margin,
    cannibalization_units,
    cannibalization_margin,
    forward_buy_units,
    forward_buy_margin,
    net_incremental_margin,
    trade_spend,
    roi,
    (cannibalization_margin + forward_buy_margin)
        / NULLIF(incremental_margin, 0) AS drag_share_of_incremental_margin
FROM ${catalog}.${promo_schema}.gold_promo_roi_by_category
WHERE trade_spend > 0
ORDER BY (cannibalization_margin + forward_buy_margin) DESC
LIMIT 30;

-- 3. Did the promoted week beat its own trailing baseline, at the finest grain?
-- Joins gold_trade_promotion to gold_weekly_baseline on the DURABLE product_id/store_id.
-- The baseline is keyed on version-specific SCD2 surrogates, so it is resolved through
-- product/store on their PK _sk (no is_current predicate — §A.16) and rolled up to the
-- durable keys; filtering to the current version here would drop re-versioned rows.
SELECT
    tp.promo_id,
    tp.product_id,
    tp.product_name,
    tp.category,
    tp.store_id,
    tp.store_name,
    tp.fiscal_week_id,
    tp.promoted_units,
    tp.baseline_units,
    (tp.promoted_units - tp.baseline_units) AS incremental_units,
    (100.0 * (tp.promoted_units - tp.baseline_units)
        / NULLIF(tp.baseline_units, 0))     AS realized_lift_pct,
    tp.planned_lift_pct,
    wb.actual_units                         AS total_units_all_promos,
    tp.planned_trade_spend
FROM ${catalog}.${promo_schema}.gold_trade_promotion tp
JOIN (
    SELECT DISTINCT fiscal_week_id, fiscal_week_index
    FROM ${catalog}.${calendar_schema}.fiscal_calendar
) fw
  ON fw.fiscal_week_id = tp.fiscal_week_id
JOIN (
    SELECT
        pr.product_id,
        st.store_id,
        wb.fiscal_week_index,
        SUM(wb.actual_units) AS actual_units
    FROM ${catalog}.${promo_schema}.gold_weekly_baseline wb
    JOIN ${catalog}.${product_schema}.product pr ON pr.product_sk = wb.product_sk
    JOIN ${catalog}.${store_schema}.store   st ON st.store_sk   = wb.store_sk
    GROUP BY pr.product_id, st.store_id, wb.fiscal_week_index
) wb
  ON  wb.product_id        = tp.product_id
  AND wb.store_id          = tp.store_id
  AND wb.fiscal_week_index = fw.fiscal_week_index
WHERE tp.baseline_units IS NOT NULL
ORDER BY (tp.promoted_units - tp.baseline_units) DESC
LIMIT 50;

-- 4. How does a location offer convert end to end? The trigger -> suppressed -> delivered ->
-- opened -> redeemed funnel by offer x fiscal week. Joins gold_location_offer_performance
-- (store grain) to location_offer; rates are recomputed from the summed counts, never averaged.
SELECT
    lo.location_offer_id,
    lo.promotion_id,
    lo.trigger_type,
    lo.channel,
    perf.fiscal_week_id,
    SUM(perf.trigger_events)     AS trigger_events,
    SUM(perf.suppressed_events)  AS suppressed_events,
    SUM(perf.delivered_events)   AS delivered_events,
    SUM(perf.opened_events)      AS opened_events,
    SUM(perf.redemptions)        AS redemptions,
    -- Reach is summed across stores, so a customer reached in two stores counts twice.
    SUM(perf.unique_customers_reached) AS customers_reached_store_sum,
    SUM(perf.delivered_events)
        / NULLIF(SUM(perf.delivered_events) + SUM(perf.suppressed_events), 0) AS delivery_rate,
    SUM(perf.opened_events)     / NULLIF(SUM(perf.delivered_events), 0)       AS open_rate,
    SUM(perf.redemptions)       / NULLIF(SUM(perf.delivered_events), 0)       AS redemption_rate,
    SUM(perf.suppressed_events)
        / NULLIF(SUM(perf.delivered_events) + SUM(perf.suppressed_events), 0) AS suppression_rate,
    SUM(perf.attributed_sales_amount) AS attributed_sales_amount
FROM ${catalog}.${promo_schema}.gold_location_offer_performance perf
JOIN ${catalog}.${promo_schema}.location_offer lo
  ON lo.location_offer_sk = perf.location_offer_sk
GROUP BY lo.location_offer_id, lo.promotion_id, lo.trigger_type, lo.channel, perf.fiscal_week_id
ORDER BY perf.fiscal_week_id DESC, redemptions DESC
LIMIT 100;

-- 5. Which frequency caps are throttling delivery? The worst suppression rates next to the
-- offer's own cap configuration. Joins gold_location_offer_performance to location_offer's
-- daily_trigger_cap and suppression_window_hours.
SELECT
    lo.location_offer_id,
    lo.promotion_id,
    lo.trigger_type,
    lo.channel,
    lo.status,
    lo.daily_trigger_cap,
    lo.suppression_window_hours,
    SUM(perf.suppressed_events) AS suppressed_events,
    SUM(perf.delivered_events)  AS delivered_events,
    SUM(perf.suppressed_events)
        / NULLIF(SUM(perf.delivered_events) + SUM(perf.suppressed_events), 0) AS suppression_rate,
    SUM(perf.redemptions) / NULLIF(SUM(perf.delivered_events), 0)             AS redemption_rate
FROM ${catalog}.${promo_schema}.gold_location_offer_performance perf
JOIN ${catalog}.${promo_schema}.location_offer lo
  ON lo.location_offer_sk = perf.location_offer_sk
GROUP BY lo.location_offer_id, lo.promotion_id, lo.trigger_type, lo.channel, lo.status,
         lo.daily_trigger_cap, lo.suppression_window_hours
HAVING SUM(perf.delivered_events) + SUM(perf.suppressed_events) > 0
ORDER BY suppression_rate DESC
LIMIT 25;

-- 6. Is a zone gaining or losing engagement? Weekly active offers, triggers, reach and
-- conversion per zone. Joins gold_zone_engagement_weekly (durable zone_id grain) to the
-- current offer_zone version for the zone's type and anchor store.
SELECT
    ze.zone_id,
    z.zone_type,
    z.store_id AS anchor_store_id,
    z.radius_m,
    ze.fiscal_week_id,
    ze.active_offers,
    ze.trigger_events,
    ze.unique_customers,
    ze.conversion_rate
FROM ${catalog}.${promo_schema}.gold_zone_engagement_weekly ze
JOIN ${catalog}.${promo_schema}.offer_zone z
  ON z.zone_id = ze.zone_id AND z.is_current = TRUE
ORDER BY ze.zone_id, ze.fiscal_week_id
LIMIT 200;
