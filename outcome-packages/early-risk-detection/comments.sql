-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection · column comments
-- Version: 0.5 · Generated: 2026-06-30 · LLM-generated: true · Reviewed: 2026-06-30
-- Column-level documentation for the gold views (Genie / AI-BI / UC metadata).
-- Run AFTER the views exist.
-- ============================================================

-- ========== gold_supplier_scorecard ==========

COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.supplier_sk IS 'Supplier surrogate key.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.supplier_id IS 'Durable supplier business key.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.supplier_name IS 'Supplier name.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.country_code IS 'Supplier country, ISO 3166-1 alpha-2.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.fiscal_year IS 'NRF fiscal year.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.fiscal_period IS 'NRF 4-5-4 fiscal period (1-12).';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.order_lines IS 'Order lines in the period (OTIF / price-compliance denominator).';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.otif_pct IS 'On-Time In-Full rate: lines on time AND in full / total lines.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.fill_rate IS 'SUM(received_qty) / SUM(ordered_qty).';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.avg_lead_time_days IS 'Mean (actual_delivery_date - order_date) over delivered lines.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.lead_time_variance IS 'Population variance (var_pop) of lead time; higher = less reliable.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.defect_rate IS '(defective + returned units) / received units.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.price_compliance_pct IS 'Share of lines invoiced at or below contract price.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_supplier_scorecard.composite_score IS 'Weighted 0-100 score: OTIF 35, fill 25, lead-time reliability 20, defect 15, price 5.';

-- ========== gold_procurement_risk ==========

COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.supplier_sk IS 'Supplier surrogate key.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.supplier_id IS 'Durable supplier business key.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.supplier_name IS 'Supplier name.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.country_code IS 'Supplier country, ISO 3166-1 alpha-2.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.composite_current IS 'Current-period scorecard composite (0-100).';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.performance_risk IS 'Risk from current performance = 100 - composite_current (0-100).';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.trend_risk IS 'Risk from deterioration over the trailing 4 periods (0-100); fires even with an OK current score.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.concentration_risk IS '100 x concentration_hhi.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.concentration_hhi IS 'Spend-weighted avg category Herfindahl index, fractional [0,1].';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.single_source_flag IS 'TRUE if the supplier is the sole source of >= 1 SKU.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.single_sourced_sku_count IS 'Number of SKUs sole-sourced by this supplier.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.geo_risk IS '100 x the largest single-country spend share among the supplier categories (own country).';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.geo_concentration_flag IS 'TRUE if that country share exceeds 0.60.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.risk_score IS 'Weighted blend: performance 25, trend 30, concentration 20, single_source 15, geo 10.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.risk_tier IS 'LOW / MEDIUM / HIGH / CRITICAL; single-source or steep trend escalate to at least HIGH.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_procurement_risk.top_risk_factors IS 'Up to 3 factors with the largest weighted contribution.';

-- ========== gold_shipment_current_state ==========

COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.shipment_id IS 'Durable shipment business key.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.current_status IS 'Latest carrier checkpoint type (e.g. in_transit, delivered, exception).';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.current_status_reason IS 'Carrier message text for the latest checkpoint.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.current_eta_date IS 'Most recent ETA: carrier_eta from the latest tracking event, or the shipment estimated_arrival_date.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.eta_slip_days IS 'Days between current ETA and original ETA. Positive = late.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.transit_elapsed_days IS 'Calendar days since ship_date.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.last_event_timestamp IS 'Timestamp of the most recent carrier tracking event.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.last_known_location IS 'Facility name from the most recent tracking event.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.last_known_city IS 'City from the most recent tracking event.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.last_known_country IS 'Country code (ISO 3166-1 alpha-2) from the most recent tracking event.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.carrier_code IS 'Standardized carrier identifier (SCAC or BIC code).';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.tracking_number IS 'Carrier-assigned tracking or waybill number.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_shipment_current_state.last_event_latency_seconds IS 'Ingest latency of the most recent tracking event, in seconds.';

-- ========== gold_control_tower ==========

COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_control_tower.alert_type IS 'Category of disruption: shipment_delay, stockout_risk, quality_issue, feed_outage, etc.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_control_tower.severity IS 'Alert severity: info, warning, or critical.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_control_tower.alert_status IS 'Lifecycle status: open or acknowledged (resolved/suppressed filtered out).';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_control_tower.supplier_risk_tier IS 'Procurement risk tier of the affected supplier (from gold_procurement_risk).';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_control_tower.inventory_on_hand IS 'Current units on hand for the affected product x store.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_control_tower.inventory_is_stockout IS 'Whether the affected product x store is currently stocked out.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_control_tower.shipment_eta_slip_days IS 'ETA slip in days for the affected shipment. Positive = late.';

-- ========== gold_inventory_risk ==========

COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_inventory_risk.days_of_supply IS 'units_on_hand_eod / avg_daily_sales. NULL if no sales velocity.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_inventory_risk.days_of_supply_with_transit IS '(on_hand + in_transit) / avg_daily_sales. Includes replenishment en route.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_inventory_risk.stockout_risk_score IS '0-100 score: higher = more risk. 100 = currently stocked out.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_inventory_risk.inventory_risk_tier IS 'stockout / critical / at_risk / healthy based on days-of-supply.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.gold_inventory_risk.avg_daily_sales IS 'Trailing 14-day average daily unit sales.';

-- ========== metric views ==========

COMMENT ON COLUMN ${catalog}.${risk_schema}.mv_eta_slip.eta_slip_days IS 'Days between effective arrival and original ETA. Positive = late, negative = early.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.mv_eta_slip.eta_slip_tier IS 'Severity tier: on_time_or_early, minor (1d), moderate (1-3d), severe (>3d).';
COMMENT ON COLUMN ${catalog}.${risk_schema}.mv_eta_slip.avg_actual_transit_days IS 'Average actual or elapsed transit days (ship_date to arrival or today).';

COMMENT ON COLUMN ${catalog}.${risk_schema}.mv_feed_freshness.feed_name IS 'Name of the data feed being monitored.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.mv_feed_freshness.feed_age_minutes IS 'Minutes since the last event was ingested. Lower = fresher.';
COMMENT ON COLUMN ${catalog}.${risk_schema}.mv_feed_freshness.freshness_status IS 'fresh (<60m), delayed (60m-24h), or stale (>24h).';
COMMENT ON COLUMN ${catalog}.${risk_schema}.mv_feed_freshness.avg_latency_seconds IS 'Average ingest latency (event_timestamp to ingest_timestamp) in seconds.';
