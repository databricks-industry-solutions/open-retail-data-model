-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · column comments (all use cases)
-- Version: 0.5 · Generated: 2026-07-15 · LLM-generated: true · Reviewed: 2026-07-29
-- Column-level documentation for the gold views (Genie / AI-BI / UC metadata).
-- Run AFTER the views exist.
-- ============================================================

-- ========== gold_equipment_health ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_equipment_health.equipment_sk IS 'Equipment surrogate key.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_equipment_health.equipment_id IS 'Durable equipment business key.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_equipment_health.equipment_name IS 'Display name of the equipment.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_equipment_health.equipment_type IS 'Category: refrigeration, hvac, pos_terminal, self_checkout, oven, etc.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_equipment_health.health_score IS '0-100 health score. 100 = fully healthy, 0 = out of service.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_equipment_health.health_tier IS 'Health tier: healthy, at_risk, degraded, or failed.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_equipment_health.anomaly_count_7d IS 'Number of anomalous sensor readings in the last 7 days.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_equipment_health.anomaly_rate_7d IS 'Fraction of readings flagged as anomalous in the last 7 days.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_equipment_health.corrective_wo_count_90d IS 'Number of corrective work orders in the last 90 days.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_equipment_health.total_downtime_hours_90d IS 'Total equipment downtime hours in the last 90 days.';

-- ========== gold_maintenance_effectiveness ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_maintenance_effectiveness.equipment_sk IS 'Equipment surrogate key.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_maintenance_effectiveness.equipment_id IS 'Durable equipment business key.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_maintenance_effectiveness.preventive_to_corrective_ratio IS 'Ratio of preventive to corrective work orders. Higher = more proactive.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_maintenance_effectiveness.total_maintenance_cost IS 'Total maintenance spend in base currency.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_maintenance_effectiveness.mtbf_days IS 'Mean Time Between Failures in calendar days.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_maintenance_effectiveness.schedule_compliance_rate IS 'Fraction of active schedules that are on-schedule (0-1).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_maintenance_effectiveness.overdue_schedules IS 'Number of active maintenance schedules that are past due.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_maintenance_effectiveness.currency_code IS 'ISO currency code for cost amounts.';

-- ========== gold_downtime_impact ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_downtime_impact.downtime_hours IS 'Equipment downtime in hours caused by this maintenance event.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_downtime_impact.spoilage_risk_flag IS 'TRUE if this is a refrigeration outage with critical/high criticality.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_downtime_impact.spoilage_risk_tier IS 'Spoilage risk level for refrigeration: high (>4h), medium (2-4h), low (<2h), none.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_downtime_impact.perishable_units_at_risk IS 'Perishable inventory units at risk in the affected store on the event date (refrigeration only).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_downtime_impact.perishable_products_at_risk IS 'Number of perishable products at risk in the affected store (refrigeration only).';

-- ========== metric views ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.mv_equipment_downtime.total_downtime_hours IS 'Total equipment downtime hours across work orders.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.mv_equipment_downtime.equipment_count IS 'Number of distinct equipment assets.';

COMMENT ON COLUMN ${catalog}.${predops_schema}.mv_maintenance_cost.total_cost IS 'Total maintenance cost in base currency.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.mv_maintenance_cost.work_order_count IS 'Number of completed work orders.';

-- ========== gold_store_operational_risk (Store Performance use case) ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.store_name IS 'Display name of the store.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.as_of_date IS 'Snapshot date the score is computed for (conforms to fiscal_calendar.date_key).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.horizon_days IS 'Declared forward assessment horizon in days (7 in v1) — a comparability label, not a claim every input is windowed to 7 days; per-domain observation windows differ (see design spec §4.7).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.operational_risk_score IS 'Store Operational Risk Score, 0-100, higher = riskier. A transparent expert-weighted HEURISTIC INDEX, not a calibrated probability.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.operational_risk_tier IS 'Risk tier: UNKNOWN (no domain scored, domains_scored = 0), LOW, MEDIUM, HIGH, CRITICAL. Any single present domain going critical, or a steep sales/margin decline, forces at least HIGH.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.top_risk_domains IS 'Up-to-3 domains with the largest weighted contribution to the score (the Diagnose step).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.domains_scored IS 'How many domains had a present (non-NULL) sub-score feeding the composite. Max is 5 (cx deferred); 0 means unscored (tier UNKNOWN).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.inventory_risk IS 'Inventory domain sub-score (0-100): sales-velocity-weighted mean of gold_inventory_risk.stockout_risk_score across the store''s SKUs (weight = trailing_units_sold; plain mean when the store has no velocity).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.supply_chain_risk IS 'Supply-chain domain sub-score (0-100), spend-weighted supplier risk from gold_procurement_risk for suppliers shipping to the store.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.sales_margin_risk IS 'Sales/margin domain sub-score (0-100): recent-vs-prior net-sales decline + discount-depth compression from BMV gold. The discount half is normalized against a cross-store p95, so it is a relative (fleet-comparative) signal — see design spec §4.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.equipment_risk IS 'Equipment domain sub-score (0-100), criticality-weighted 100 - health_score from gold_equipment_health.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.labor_risk IS 'Labor/workforce domain sub-score from gold_labor_risk (0-100). Present when Workforce Optimization / labor domain is deployed (ADR 0043).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_store_operational_risk.cx_risk IS 'Customer-experience domain sub-score. DEFERRED — always NULL in v1 (no CX source yet).';

-- ========== store_risk_score (scored-output fact) ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.store_risk_score.operational_risk_score IS 'Store Operational Risk Score, 0-100. Heuristic index, not a probability.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.store_risk_score.score_method IS 'How the score was produced: heuristic (shipped) or model (an adopter/pipeline may write these later).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.store_risk_score.predicted_impact_amount IS 'Estimated business impact in currency_code. Reserved for a model-backed pipeline; NULL in the shipped heuristic.';

-- ========== metric view ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.mv_store_risk.avg_operational_risk_score IS 'Average Store Operational Risk Score across the selected stores/dates.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.mv_store_risk.high_risk_store_count IS 'Number of distinct stores at HIGH or CRITICAL risk tier.';

-- ========== gold_workforce_demand_forecast (Workforce Optimization use case) ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.store_sk IS 'Surrogate key for the store.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.business_date IS 'Local business date the forecast interval belongs to.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.interval_start_ts IS 'Inclusive start of the planning interval (UTC).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.interval_end_ts IS 'Exclusive end of the planning interval (UTC).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.interval_minutes IS 'Planning interval length in minutes, taken from the current labor_standard (30 when none is configured).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.department_or_zone IS 'Department or zone within the store the forecast applies to.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.role_code IS 'Workforce role the forecast is produced for: cashier, sales_associate, fulfillment, inventory, supervisor.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.demand_driver IS 'Workload driver the forecast is expressed in, derived from role_code (transaction_count, foot_traffic, pickup_orders, receiving_units, store_open_coverage).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.forecast_driver_units IS 'Point forecast of driver units in the interval. A transparent seasonal-average HEURISTIC, not a calibrated model output.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.forecast_lower_bound IS 'Lower uncertainty proxy: 80% of the point forecast. A fixed band, not a fitted prediction interval.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.forecast_upper_bound IS 'Upper uncertainty proxy: 120% of the point forecast. A fixed band, not a fitted prediction interval.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.forecast_method IS 'How the row was produced: seasonal_rolling_avg when store-level history was available, hierarchical_fallback when the estimate came from a coarser level.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.model_version IS 'Reserved for a model-backed pipeline (forecast_method = model); NULL in the shipped heuristic (ADR 0028 §4).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.forecast_horizon_days IS 'Forward horizon the forecast covers, in days (7 by default).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_demand_forecast.forecast_origin_ts IS 'When the forecast was computed (UTC) — the view evaluates at query time.';

-- ========== gold_workforce_labor_requirement (Workforce Optimization use case) ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.store_sk IS 'Surrogate key for the store.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.business_date IS 'Local business date the requirement interval belongs to.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.interval_start_ts IS 'Inclusive start of the planning interval (UTC).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.interval_end_ts IS 'Exclusive end of the planning interval (UTC).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.interval_minutes IS 'Planning interval length in minutes.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.department_or_zone IS 'Department or zone within the store.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.role_code IS 'Workforce role the requirement applies to.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.demand_driver IS 'Workload driver the requirement was converted from.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.forecast_driver_units IS 'Forecast driver units carried through from gold_workforce_demand_forecast.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.labor_standard_id IS 'Durable key of the labor_standard row applied to this interval.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.labor_standard_version IS 'Version label of the applied labor_standard, so a requirement stays reproducible after the standard changes.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.applied_labor_standard IS 'Labor hours per driver unit taken from the applied standard.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.required_labor_hours IS 'Labor hours required in the interval: driver units x standard, floored at the minimum-headcount coverage.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.required_headcount IS 'Required headcount for the interval: required hours over interval length, floored at minimum_headcount.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.minimum_headcount IS 'Minimum headcount the standard mandates regardless of forecast demand.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_labor_requirement.coverage_rationale IS 'Why the standard sets this coverage (service, safety, or statutory rationale recorded on labor_standard).';

-- ========== gold_workforce_coverage_gap (Workforce Optimization use case) ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.store_sk IS 'Surrogate key for the store.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.business_date IS 'Local business date the interval belongs to.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.interval_start_ts IS 'Inclusive start of the planning interval (UTC).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.interval_end_ts IS 'Exclusive end of the planning interval (UTC).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.department_or_zone IS 'Department or zone within the store.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.role_code IS 'Workforce role the gap is measured for.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.required_labor_hours IS 'Labor hours required in the interval, from gold_workforce_labor_requirement.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.required_headcount IS 'Required headcount in the interval.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.scheduled_hours IS 'Published labor_schedule hours overlapping the interval, clipped to the interval boundaries.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.recommended_hours IS 'Proposed workforce_schedule_recommendation hours overlapping the interval, clipped to the interval boundaries. Status = proposed ONLY: an accepted recommendation is published into labor_schedule and is already counted in scheduled_hours, so including it here would double-count the same shift.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.covered_hours IS 'Scheduled plus recommended hours overlapping the interval.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.shortfall_hours IS 'Unmet required hours (required minus covered, floored at 0). Overstaffing is not reported as a negative shortfall.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.coverage_pct IS 'Covered hours over required hours, capped at 2.0; 1.0 when nothing is required.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_coverage_gap.shortfall_severity IS 'Coverage band: none (no shortfall), low (>=85% covered), medium (>=60%), high (>=35%), critical (below 35%).';

-- ========== gold_labor_risk (labor sub-score for the Store Operational Risk Score) ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.store_sk IS 'Surrogate key for the store.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.store_name IS 'Display name of the store.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.region IS 'Store region for roll-up.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.district IS 'Store district for roll-up.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.as_of_date IS 'Date the sub-score is computed for (the view evaluates at query time).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.required_hours_7d IS 'Required labor hours summed over the 7-day observation window.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.shortfall_hours_7d IS 'Unmet required hours summed over the 7-day observation window.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.avg_coverage_pct IS 'Mean interval coverage ratio over the window (1.0 = fully covered).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.critical_intervals IS 'Count of intervals in the window at critical coverage (below 35% covered).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.high_or_critical_intervals IS 'Count of intervals in the window at high or critical coverage (below 60% covered).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.intervals_scored IS 'How many intervals contributed to the sub-score; a small count makes the score noisy.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_labor_risk.labor_risk IS 'Labor/workforce sub-score, 0-100, higher = riskier. A transparent HEURISTIC INDEX built from coverage shortfall plus critical-interval escalators, not a calibrated probability. Feeds gold_store_operational_risk.labor_risk (ADR 0043).';

-- ========== gold_workforce_forecast_accuracy (Workforce Optimization use case) ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.business_date IS 'Local business date the interval belongs to.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.interval_start_ts IS 'Inclusive start of the planning interval (UTC).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.interval_end_ts IS 'Exclusive end of the planning interval (UTC).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.interval_minutes IS 'Planning interval length in minutes.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.department_or_zone IS 'Department or zone within the store.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.role_code IS 'Workforce role the forecast was produced for.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.demand_driver IS 'Workload driver the forecast is expressed in.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.forecast_driver_units IS 'Forecast driver units for the interval.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.actual_driver_units IS 'Observed driver units for the interval; NULL when no actuals source is available for the driver. STORE-TOTAL grain: actuals are joined on store/date/interval only, NOT on role or zone, so every per-role row on one interval repeats the SAME store total. Use it as a per-row diagnostic; summing it across roles multiply-counts the interval.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.forecast_error IS 'Forecast minus actual driver units. Positive = over-forecast.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.ape IS 'Absolute percentage error for the interval; NULL when actuals are absent or zero. Aggregate as a weighted ratio of sums, not a mean of these row values.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.forecast_method IS 'How the forecast row was produced.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.model_version IS 'Reserved for a model-backed pipeline (forecast_method = model); NULL for heuristic rows (ADR 0028 §4).';
COMMENT ON COLUMN ${catalog}.${predops_schema}.gold_workforce_forecast_accuracy.optimization_run_id IS 'workforce_optimization_run.run_id that produced the forecast being scored.';

-- ========== metric view ==========

COMMENT ON COLUMN ${catalog}.${predops_schema}.mv_workforce_coverage.required_labor_hours IS 'Sum of required labor hours across the selection.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.mv_workforce_coverage.covered_hours IS 'Sum of scheduled plus recommended hours overlapping demand.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.mv_workforce_coverage.shortfall_hours IS 'Sum of unmet required hours.';
COMMENT ON COLUMN ${catalog}.${predops_schema}.mv_workforce_coverage.coverage_ratio IS 'Covered hours over required hours — a ratio of sums, not a mean of per-interval ratios.';
