-- ============================================================
-- ORDM · Outcome Package · Smarter Demand and Inventory Decisions
-- File: comments.sql
-- Version: 0.5
-- Generated: 2026-07-21
-- ============================================================
-- Column comments for gold and metric views. Run AFTER views exist.
-- Extension tables carry inline COMMENT in their CREATE TABLE DDL.
-- ============================================================

-- ========== gold_effective_forecast ==========
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_effective_forecast.planning_unit_id IS 'Durable planning unit business key.';
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_effective_forecast.forecast_date_key IS 'Forecast period (day or week start).';
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_effective_forecast.statistical_forecast_quantity IS 'Model-generated forecast before adjustments.';
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_effective_forecast.effective_forecast_quantity IS 'Forecast after latest approved planner adjustment.';

-- ========== gold_inventory_health ==========
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_inventory_health.days_of_supply IS 'Units on hand divided by trailing average daily sales.';
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_inventory_health.inventory_position_status IS 'Health status: overstock, healthy, at_risk, stockout.';

-- ========== gold_oos_current ==========
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_oos_current.lost_revenue_to_date IS 'Cumulative estimated lost revenue for the active OOS episode.';

-- ========== gold_service_level_attainment ==========
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_service_level_attainment.attained_in_stock_rate IS 'Time-based availability: 1 - stockout SKU-days / total SKU-days.';
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_service_level_attainment.attained_fill_rate IS 'Demand-weighted (Type II) fill rate: units sold / (units sold + censoring-aware lost units).';
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_service_level_attainment.target_service_level_pct IS 'Target from the DEFAULT segment only (abc_class/xyz_class NULL); NOT the per-ABC/XYZ segment target. Segment-specific attainment is a documented follow-up.';
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_service_level_attainment.service_level_gap_to_target IS 'Attained minus target on the target measure type. Exact for fill_rate/in_stock_rate; for a cycle_service_level target it is an approximation (per-cycle probability vs the time-based in-stock rate) — see gap_is_approximate. Uses the default segment target, so read as an enterprise-default gap, not a segment-accurate one.';
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_service_level_attainment.gap_is_approximate IS 'TRUE when service_level_gap_to_target differences a cycle_service_level target (per-cycle probability) against the time-based attained_in_stock_rate proxy; FALSE when the target and attained measure are the same unit.';

-- ========== gold_inventory_productivity ==========
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_inventory_productivity.inventory_turnover IS 'Annualized: trailing COGS scaled to a year / AVERAGE inventory value over the trailing window.';
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_inventory_productivity.gmroi IS 'Annualized gross margin (realized net_revenue - COGS) / AVERAGE inventory cost over the trailing window.';
COMMENT ON COLUMN ${catalog}.${sdi_schema}.gold_inventory_productivity.avg_inventory_value IS 'Mean of daily on-hand inventory value over the trailing window (not the period-end snapshot).';

-- ========== mv_forecast_accuracy ==========
COMMENT ON COLUMN ${catalog}.${sdi_schema}.mv_forecast_accuracy.accuracy_pct IS 'Forecast accuracy percentage at planning-unit grain.';
