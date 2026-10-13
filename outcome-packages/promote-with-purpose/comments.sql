-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose · column comments
-- Version: 0.5 · Generated: 2026-06-10 · LLM-generated: true · Reviewed: 2026-08-13
-- Column-level documentation for the consumable gold views (Genie / AI-BI / UC).
-- Run AFTER the views exist.
-- ============================================================

-- gold_promo_roi (one row per promotion)
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.promo_id IS 'Promotion business key.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.promo_name IS 'Promotion name.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.promo_type IS 'Mechanic: TPR / FEATURE / DISPLAY / FEATURE_AND_DISPLAY / BOGO / COUPON / BUNDLE.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.funding_type IS 'OFF_INVOICE / BILL_BACK / SCAN_DOWN / LUMP_SUM.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.funded_by IS 'SUPPLIER / RETAILER / SHARED.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.promoted_units IS 'Units sold on promotion.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.promoted_revenue IS 'Net revenue on promotion.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.promoted_margin IS 'Gross margin on promotion.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.baseline_units IS 'Expected non-promoted units over the promo window (trailing-8-week baseline).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.baseline_revenue IS 'Baseline units valued at normal price.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.baseline_margin IS 'Baseline units valued at normal margin.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.incremental_units IS 'promoted_units - baseline_units (NOT clamped; negative = lost volume).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.incremental_revenue IS 'promoted_revenue - baseline_revenue.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.incremental_margin IS 'promoted_margin - baseline_margin.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.trade_spend IS 'Planned trade spend (realized actuals not modelled in v1).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.roi IS 'incremental_margin / NULLIF(trade_spend, 0); NULL-safe.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.planned_lift_pct IS 'Planned incremental unit lift %.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.realized_lift_pct IS '100 x incremental_units / baseline_units.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.cannibalization_units IS 'Lost units on substitute SKUs (same category, not on promo) during the window.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.cannibalization_margin IS 'Margin lost to cannibalization.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.forward_buy_units IS 'Lost units on promoted SKUs in the N weeks after the promo (pantry loading).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.forward_buy_margin IS 'Margin lost to forward buy.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi.net_incremental_margin IS 'incremental_margin - cannibalization_margin - forward_buy_margin (negative = value destroyed).';

-- gold_promo_performance (operational per-promotion summary)
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_performance.promo_id IS 'Promotion business key.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_performance.scope_skus IS 'Distinct products in the promotion scope.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_performance.scope_stores IS 'Distinct stores in the promotion scope.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_performance.fiscal_weeks IS 'Distinct fiscal weeks the promotion ran.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_performance.promoted_units IS 'Total promoted units.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_performance.promoted_revenue IS 'Total promoted net revenue.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_performance.baseline_units IS 'Total trailing-baseline units over the promo.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_performance.planned_trade_spend IS 'Total planned trade spend.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_performance.realized_lift_pct IS '100 x (promoted_units - baseline_units) / baseline_units.';

-- gold_trade_promotion (promo x product x store x fiscal week detail)
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_trade_promotion.fiscal_week_id IS 'Fiscal week identifier (fiscal_year*100 + fiscal_week).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_trade_promotion.promoted_units IS 'Promoted units for this promo x product x store x week.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_trade_promotion.promoted_revenue IS 'Promoted net revenue for this cell.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_trade_promotion.planned_trade_spend IS 'Planned trade spend allocated to this cell (evenly across scope x weeks).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_trade_promotion.baseline_units IS 'Trailing-8-week non-promoted mean units; NULL if < 4 weeks available.';

-- gold_promo_roi_by_category (promo x category drill grain of gold_promo_roi)
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.promo_id IS 'Promotion business key.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.promo_name IS 'Promotion name.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.promo_type IS 'Mechanic: TPR / FEATURE / DISPLAY / FEATURE_AND_DISPLAY / BOGO / COUPON / BUNDLE.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.funding_type IS 'OFF_INVOICE / BILL_BACK / SCAN_DOWN / LUMP_SUM.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.funded_by IS 'SUPPLIER / RETAILER / SHARED.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.start_date IS 'Promotion start date.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.end_date IS 'Promotion end date.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.category IS 'Product category — the drill grain of this view.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.promoted_units IS 'Units sold on promotion.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.promoted_revenue IS 'Net revenue on promotion.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.promoted_margin IS 'Gross margin on promotion.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.baseline_units IS 'Expected non-promoted units over the promo window (trailing-8-week baseline).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.baseline_revenue IS 'Baseline units valued at normal price.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.baseline_margin IS 'Baseline units valued at normal margin.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.incremental_units IS 'promoted_units - baseline_units (NOT clamped; negative = lost volume).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.incremental_revenue IS 'promoted_revenue - baseline_revenue.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.incremental_margin IS 'promoted_margin - baseline_margin.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.trade_spend IS 'Planned trade spend allocated to this category by its share of the promo scope rows (realized actuals not modelled in v1).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.roi IS 'incremental_margin / NULLIF(trade_spend, 0); NULL-safe.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.planned_lift_pct IS 'Planned incremental unit lift %.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.realized_lift_pct IS '100 x incremental_units / baseline_units.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.cannibalization_units IS 'Lost units on substitute SKUs (same category, not on promo) during the window.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.cannibalization_margin IS 'Margin lost to cannibalization.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.forward_buy_units IS 'Lost units on promoted SKUs in the N weeks after the promo (pantry loading).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.forward_buy_margin IS 'Margin lost to forward buy.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_promo_roi_by_category.net_incremental_margin IS 'incremental_margin - cannibalization_margin - forward_buy_margin (negative = value destroyed).';

-- gold_location_offer_performance (location_offer_sk x store_id x fiscal_week_id; materialized TABLE)
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.location_offer_sk IS 'Offer surrogate (FK to location_offer.location_offer_sk); part of the grain PK.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.store_id IS 'Store business key; part of the grain PK.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.fiscal_week_id IS 'NRF 4-5-4 fiscal week; part of the grain PK.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.trigger_events IS 'Count of triggered events.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.suppressed_events IS 'Count of suppressed events.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.delivered_events IS 'Count of delivered events.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.opened_events IS 'Count of opened events.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.redemptions IS 'Count of redeemed events.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.unique_customers_reached IS 'Distinct pseudonymous customers with a delivered event.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.delivery_rate IS 'delivered / (delivered + suppressed); bounded 0..1.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.open_rate IS 'opened / delivered; bounded 0..1.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.redemption_rate IS 'redemptions / delivered; bounded 0..1.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.suppression_rate IS 'suppressed / (delivered + suppressed); bounded 0..1.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_location_offer_performance.attributed_sales_amount IS 'Sum of transaction net_revenue attributed to redeemed events (base currency).';

-- gold_zone_engagement_weekly (zone_id x fiscal_week_id; materialized TABLE)
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_zone_engagement_weekly.zone_id IS 'Durable zone business key; part of the grain PK.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_zone_engagement_weekly.fiscal_week_id IS 'NRF 4-5-4 fiscal week; part of the grain PK.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_zone_engagement_weekly.active_offers IS 'Distinct active location offers with events in this zone-week.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_zone_engagement_weekly.trigger_events IS 'Count of triggered events in this zone-week.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_zone_engagement_weekly.unique_customers IS 'Distinct pseudonymous customers engaged in this zone-week.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_zone_engagement_weekly.conversion_rate IS 'redemptions / triggers; NULL-safe; bounded 0..1.';

-- gold_weekly_baseline (product_sk x store_sk x fiscal_week_index; reusable building block)
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_weekly_baseline.product_sk IS 'FK to product.product_sk (version-specific); resolve to the durable product_id before aggregating (§A.16).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_weekly_baseline.store_sk IS 'FK to store.store_sk (version-specific); resolve to the durable store_id before aggregating (§A.16).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_weekly_baseline.fiscal_week_index IS 'Globally monotonic week counter across the whole calendar; use for trailing N-week windows.';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_weekly_baseline.actual_units IS 'Total units sold in the week (promoted and non-promoted).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_weekly_baseline.actual_revenue IS 'Total net revenue in the week (promoted and non-promoted).';
COMMENT ON COLUMN ${catalog}.${promo_schema}.gold_weekly_baseline.baseline_units IS 'Trailing-8-week non-promoted mean units; NULL if < 4 weeks available.';
