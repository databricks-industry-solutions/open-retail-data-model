-- ============================================================
-- ORDM · Outcome Package · Early Risk Detection · data-quality checks
-- Version: 0.5 · Generated: 2026-06-30 · LLM-generated: true · Reviewed: 2026-06-30
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report
-- a value and never fail the run.
-- ============================================================

-- ========== gold_supplier_scorecard ==========

-- check: scorecard_grain_unique | severity: error
-- One row per supplier x fiscal period, keyed on the DURABLE supplier_id (never
-- the version-specific supplier_sk). A supplier versioned mid-period must not
-- split its PO lines across surrogate keys — the SCD2 fragmentation guard
-- (standard §A.16). Dormant-green under single-version synthetic data.
SELECT supplier_id, fiscal_year, fiscal_period
FROM ${catalog}.${risk_schema}.gold_supplier_scorecard
GROUP BY supplier_id, fiscal_year, fiscal_period
HAVING COUNT(*) > 1;

-- check: scorecard_otif_pct_range | severity: error
SELECT * FROM ${catalog}.${risk_schema}.gold_supplier_scorecard
WHERE otif_pct IS NOT NULL AND otif_pct NOT BETWEEN 0 AND 1;

-- check: scorecard_fill_rate_range | severity: error
SELECT * FROM ${catalog}.${risk_schema}.gold_supplier_scorecard
WHERE fill_rate IS NOT NULL AND fill_rate NOT BETWEEN 0 AND 1;

-- check: scorecard_defect_rate_range | severity: error
SELECT * FROM ${catalog}.${risk_schema}.gold_supplier_scorecard
WHERE defect_rate IS NOT NULL AND defect_rate NOT BETWEEN 0 AND 1;

-- check: scorecard_composite_range | severity: error
SELECT * FROM ${catalog}.${risk_schema}.gold_supplier_scorecard
WHERE composite_score IS NOT NULL AND composite_score NOT BETWEEN 0 AND 100;

-- check: scorecard_supplier_fk_orphan | severity: error
SELECT g.* FROM ${catalog}.${risk_schema}.gold_supplier_scorecard g
LEFT JOIN ${catalog}.${supplier_schema}.supplier s ON g.supplier_sk = s.supplier_sk
WHERE s.supplier_sk IS NULL;

-- check: scorecard_rowcount | severity: metric
SELECT COUNT(*) AS scorecard_rows FROM ${catalog}.${risk_schema}.gold_supplier_scorecard;

-- check: scorecard_composite_null_rate | severity: metric
SELECT ROUND(AVG(CASE WHEN composite_score IS NULL THEN 1.0 ELSE 0.0 END), 4) AS composite_null_rate
FROM ${catalog}.${risk_schema}.gold_supplier_scorecard;

-- check: scorecard_price_compliance_null_rate | severity: metric
SELECT ROUND(AVG(CASE WHEN price_compliance_pct IS NULL THEN 1.0 ELSE 0.0 END), 4) AS price_compliance_null_rate
FROM ${catalog}.${risk_schema}.gold_supplier_scorecard;

-- check: scorecard_composite_spread | severity: metric
SELECT ROUND(STDDEV_POP(composite_score), 4) AS composite_stddev
FROM ${catalog}.${risk_schema}.gold_supplier_scorecard;

-- ========== gold_procurement_risk ==========

-- check: risk_grain_unique | severity: error
-- One row per supplier, keyed on the DURABLE supplier_id: a re-versioned supplier
-- must not fragment into multiple rows — the SCD2 fragmentation guard (standard
-- §A.16). (This uniqueness check catches DUPLICATION only; the separate drop risk
-- — a versioned supplier vanishing from the register via an is_current INNER join —
-- is guarded by the join fix in the fix-the-views PR, not here.) Dormant-green
-- under single-version synthetic data.
SELECT supplier_id
FROM ${catalog}.${risk_schema}.gold_procurement_risk
GROUP BY supplier_id
HAVING COUNT(*) > 1;

-- check: risk_hhi_range | severity: error
SELECT * FROM ${catalog}.${risk_schema}.gold_procurement_risk
WHERE concentration_hhi IS NOT NULL AND concentration_hhi NOT BETWEEN 0 AND 1;

-- check: risk_score_range | severity: error
SELECT * FROM ${catalog}.${risk_schema}.gold_procurement_risk
WHERE risk_score IS NOT NULL AND risk_score NOT BETWEEN 0 AND 100;

-- check: risk_tier_domain | severity: error
SELECT * FROM ${catalog}.${risk_schema}.gold_procurement_risk
WHERE risk_tier NOT IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');

-- check: risk_supplier_fk_orphan | severity: error
SELECT g.* FROM ${catalog}.${risk_schema}.gold_procurement_risk g
LEFT JOIN ${catalog}.${supplier_schema}.supplier s ON g.supplier_sk = s.supplier_sk
WHERE s.supplier_sk IS NULL;

-- check: risk_rowcount | severity: metric
SELECT COUNT(*) AS risk_rows FROM ${catalog}.${risk_schema}.gold_procurement_risk;

-- check: risk_high_critical_count | severity: metric
SELECT COUNT(*) AS high_or_critical
FROM ${catalog}.${risk_schema}.gold_procurement_risk
WHERE risk_tier IN ('HIGH', 'CRITICAL');

-- check: risk_single_source_count | severity: metric
SELECT COUNT(*) AS single_source_suppliers
FROM ${catalog}.${risk_schema}.gold_procurement_risk
WHERE single_source_flag = true;

-- ========== disruption_event ==========

-- check: de_pk_unique | severity: error
SELECT disruption_event_sk
FROM ${catalog}.${risk_schema}.disruption_event
GROUP BY disruption_event_sk
HAVING COUNT(*) > 1;

-- check: de_rule_fk_orphan | severity: error
SELECT de.* FROM ${catalog}.${risk_schema}.disruption_event de
LEFT JOIN ${catalog}.${risk_schema}.disruption_rule dr ON de.disruption_rule_sk = dr.disruption_rule_sk
WHERE dr.disruption_rule_sk IS NULL AND de.disruption_rule_sk IS NOT NULL;

-- check: de_shipment_fk_orphan | severity: error
SELECT de.* FROM ${catalog}.${risk_schema}.disruption_event de
LEFT JOIN ${catalog}.${logistics_schema}.shipment s ON de.shipment_sk = s.shipment_sk
WHERE s.shipment_sk IS NULL AND de.shipment_sk IS NOT NULL;

-- check: de_supplier_fk_orphan | severity: error
SELECT de.* FROM ${catalog}.${risk_schema}.disruption_event de
LEFT JOIN ${catalog}.${supplier_schema}.supplier s ON de.supplier_sk = s.supplier_sk
WHERE s.supplier_sk IS NULL AND de.supplier_sk IS NOT NULL;

-- check: de_product_fk_orphan | severity: error
SELECT de.* FROM ${catalog}.${risk_schema}.disruption_event de
LEFT JOIN ${catalog}.${product_schema}.product p ON de.product_sk = p.product_sk
WHERE p.product_sk IS NULL AND de.product_sk IS NOT NULL;

-- check: de_store_fk_orphan | severity: error
SELECT de.* FROM ${catalog}.${risk_schema}.disruption_event de
LEFT JOIN ${catalog}.${store_schema}.store st ON de.store_sk = st.store_sk
WHERE st.store_sk IS NULL AND de.store_sk IS NOT NULL;

-- check: de_lane_fk_orphan | severity: error
SELECT de.* FROM ${catalog}.${risk_schema}.disruption_event de
LEFT JOIN ${catalog}.${logistics_schema}.lane la ON de.lane_sk = la.lane_sk
WHERE la.lane_sk IS NULL AND de.lane_sk IS NOT NULL;

-- check: de_latency_nonnegative | severity: error
SELECT * FROM ${catalog}.${risk_schema}.disruption_event
WHERE latency_seconds IS NOT NULL AND latency_seconds < 0;

-- check: de_rowcount | severity: metric
SELECT COUNT(*) AS disruption_event_rows FROM ${catalog}.${risk_schema}.disruption_event;

-- check: de_severity_distribution | severity: metric
SELECT severity, COUNT(*) AS event_count
FROM ${catalog}.${risk_schema}.disruption_event
GROUP BY severity;

-- check: de_type_distribution | severity: metric
SELECT disruption_type, COUNT(*) AS event_count
FROM ${catalog}.${risk_schema}.disruption_event
GROUP BY disruption_type;

-- ========== disruption_alert ==========

-- check: da_pk_unique | severity: error
SELECT disruption_alert_sk
FROM ${catalog}.${risk_schema}.disruption_alert
GROUP BY disruption_alert_sk
HAVING COUNT(*) > 1;

-- check: da_event_fk_orphan | severity: error
SELECT da.* FROM ${catalog}.${risk_schema}.disruption_alert da
LEFT JOIN ${catalog}.${risk_schema}.disruption_event de ON da.disruption_event_sk = de.disruption_event_sk
WHERE de.disruption_event_sk IS NULL AND da.disruption_event_sk IS NOT NULL;

-- check: da_rule_fk_orphan | severity: error
SELECT da.* FROM ${catalog}.${risk_schema}.disruption_alert da
LEFT JOIN ${catalog}.${risk_schema}.disruption_rule dr ON da.disruption_rule_sk = dr.disruption_rule_sk
WHERE dr.disruption_rule_sk IS NULL AND da.disruption_rule_sk IS NOT NULL;

-- check: da_resolved_has_timestamp | severity: error
SELECT * FROM ${catalog}.${risk_schema}.disruption_alert
WHERE alert_status = 'resolved' AND resolved_timestamp IS NULL;

-- check: da_rowcount | severity: metric
SELECT COUNT(*) AS disruption_alert_rows FROM ${catalog}.${risk_schema}.disruption_alert;

-- check: da_open_alert_count | severity: metric
SELECT COUNT(*) AS open_alerts
FROM ${catalog}.${risk_schema}.disruption_alert
WHERE alert_status IN ('open', 'acknowledged');

-- ========== disruption_rule ==========

-- check: dr_pk_unique | severity: error
SELECT disruption_rule_sk
FROM ${catalog}.${risk_schema}.disruption_rule
GROUP BY disruption_rule_sk
HAVING COUNT(*) > 1;

-- check: dr_rowcount | severity: metric
SELECT COUNT(*) AS disruption_rule_rows FROM ${catalog}.${risk_schema}.disruption_rule;

-- check: dr_enabled_count | severity: metric
SELECT COUNT(*) AS enabled_rules
FROM ${catalog}.${risk_schema}.disruption_rule
WHERE is_enabled = TRUE;

-- ========== gold_inventory_risk ==========

-- check: inv_risk_dos_nonnegative | severity: error
SELECT * FROM ${catalog}.${risk_schema}.gold_inventory_risk
WHERE days_of_supply IS NOT NULL AND days_of_supply < 0;

-- check: inv_risk_score_range | severity: error
SELECT * FROM ${catalog}.${risk_schema}.gold_inventory_risk
WHERE stockout_risk_score NOT BETWEEN 0 AND 100;

-- check: inv_risk_tier_domain | severity: error
SELECT * FROM ${catalog}.${risk_schema}.gold_inventory_risk
WHERE inventory_risk_tier NOT IN ('stockout', 'critical', 'at_risk', 'healthy');

-- check: inv_risk_product_fk_orphan | severity: error
SELECT ir.* FROM ${catalog}.${risk_schema}.gold_inventory_risk ir
LEFT JOIN ${catalog}.${product_schema}.product p ON ir.product_sk = p.product_sk
WHERE p.product_sk IS NULL;

-- check: inv_risk_store_fk_orphan | severity: error
SELECT ir.* FROM ${catalog}.${risk_schema}.gold_inventory_risk ir
LEFT JOIN ${catalog}.${store_schema}.store st ON ir.store_sk = st.store_sk
WHERE st.store_sk IS NULL;

-- check: inv_risk_rowcount | severity: metric
SELECT COUNT(*) AS inv_risk_rows FROM ${catalog}.${risk_schema}.gold_inventory_risk;

-- check: inv_risk_critical_count | severity: metric
SELECT COUNT(*) AS critical_or_stockout
FROM ${catalog}.${risk_schema}.gold_inventory_risk
WHERE inventory_risk_tier IN ('stockout', 'critical');

-- ========== feed freshness ==========
-- Query underlying tables directly; mv_feed_freshness is a UC Metric View
-- whose measures require MEASURE() syntax and cannot be SELECTed as bare columns.

-- check: freshness_all_feeds_present | severity: error
-- Each branch is PARENTHESIZED so `LIMIT 1` binds to that SELECT, not to the whole UNION ALL:
-- in Spark `SELECT ... FROM t LIMIT 1 UNION ALL SELECT ...` applies LIMIT to the entire set, so
-- the count was capped at 1 and `1 < 3` ALWAYS fired -> the check failed whenever the tables
-- existed (surfaced once serving DQ ran at --fail_on error). Per-branch LIMIT counts one row per
-- populated feed, so a present feed contributes exactly 1 and a truly-empty feed contributes 0.
SELECT 'missing_feed' AS issue
WHERE (
  SELECT COUNT(*) FROM (
    (SELECT 'shipment_tracking' AS feed_name FROM ${catalog}.${logistics_schema}.shipment_tracking LIMIT 1)
    UNION ALL
    (SELECT 'disruption_event' FROM ${catalog}.${risk_schema}.disruption_event LIMIT 1)
    UNION ALL
    (SELECT 'inventory_position' FROM ${catalog}.${inventory_schema}.inventory_position LIMIT 1)
  )
) < 3;

-- check: freshness_tracking_age | severity: metric
SELECT
  'shipment_tracking' AS feed_name,
  ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(ingest_timestamp))) / 60.0, 1) AS feed_age_minutes
FROM ${catalog}.${logistics_schema}.shipment_tracking;

-- check: freshness_de_age | severity: metric
SELECT
  'disruption_event' AS feed_name,
  ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(ingest_timestamp))) / 60.0, 1) AS feed_age_minutes
FROM ${catalog}.${risk_schema}.disruption_event;

-- check: freshness_inv_age | severity: metric
SELECT
  'inventory_position' AS feed_name,
  ROUND((UNIX_TIMESTAMP(CURRENT_TIMESTAMP()) - UNIX_TIMESTAMP(MAX(load_timestamp))) / 60.0, 1) AS feed_age_minutes
FROM ${catalog}.${inventory_schema}.inventory_position;
