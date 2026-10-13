-- ============================================================
-- ORDM · Outcome Package · Balancing Margin and Volume · data-quality checks
-- Version: 0.5
-- Generated: 2026-06-29
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-29 by @ojasvi-goyal-03
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report
-- a value and never fail the run.
-- ============================================================

-- check: bmv_competitor_price_grain_unique | severity: error
-- Ensure competitor_price operates at the competitor x product x date grain
SELECT competitor_sk, product_sk, date_key
FROM ${catalog}.${bmv_schema}.competitor_price
GROUP BY competitor_sk, product_sk, date_key
HAVING COUNT(*) > 1;

-- check: bmv_sales_actuals_grain_unique | severity: error
-- Ensure gold_sales_actuals operates at the product x store x date grain (spine for window measures)
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_sales_actuals
GROUP BY product_sk, store_sk, date_key
HAVING COUNT(*) > 1;

-- check: bmv_sales_actuals_inventory_validity | severity: error
-- Ensure units_received_today is non-negative
SELECT * FROM ${catalog}.${bmv_schema}.gold_sales_actuals
WHERE units_received_today IS NOT NULL AND units_received_today < 0;

-- check: bmv_assortment_opt_grain_unique | severity: error
-- Ensure gold_assortment_optimization operates at the product x store grain (snapshot)
SELECT product_sk, store_sk
FROM ${catalog}.${bmv_schema}.gold_assortment_optimization
GROUP BY product_sk, store_sk
HAVING COUNT(*) > 1;

-- check: bmv_assortment_opt_metrics_validity | severity: error
-- Ensure inventory and productivity metrics are non-negative
SELECT * FROM ${catalog}.${bmv_schema}.gold_assortment_optimization
WHERE (units_on_hand_eod IS NOT NULL AND units_on_hand_eod < 0)
   OR (rolling_revenue_14d IS NOT NULL AND rolling_revenue_14d < 0);

-- check: bmv_price_actuals_grain_unique | severity: error
-- Ensure gold_price_actuals operates at the product x store x date grain
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_price_actuals
GROUP BY product_sk, store_sk, date_key
HAVING COUNT(*) > 1;

-- check: bmv_price_actuals_price_validity | severity: error
-- Ensure effective_price_lc is not negative
SELECT * FROM ${catalog}.${bmv_schema}.gold_price_actuals
WHERE effective_price_lc < 0;

-- check: bmv_affinity_features_grain_unique | severity: error
-- Ensure gold_affinity_features operates at the product x store x date grain
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_affinity_features
GROUP BY product_sk, store_sk, date_key
HAVING COUNT(*) > 1;

-- check: bmv_external_signals_grain_unique | severity: error
-- Ensure gold_external_signals operates at the product x store x date grain
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_external_signals
GROUP BY product_sk, store_sk, date_key
HAVING COUNT(*) > 1;

-- check: bmv_seasonality_features_grain_unique | severity: error
-- Ensure gold_seasonality_features operates at the date grain
SELECT date_key
FROM ${catalog}.${bmv_schema}.gold_seasonality_features
GROUP BY date_key
HAVING COUNT(*) > 1;

-- check: bmv_bucket_features_domain_margin | severity: error
-- Margin health bucket must fall within defined domain limits
SELECT * FROM ${catalog}.${bmv_schema}.gold_bucket_features
WHERE margin_health_bucket NOT IN ('High', 'Healthy', 'Low', 'Bleeding');

-- check: bmv_bucket_features_domain_discount | severity: error
-- Discount depth bucket must fall within defined domain limits
SELECT * FROM ${catalog}.${bmv_schema}.gold_bucket_features
WHERE discount_depth_bucket NOT IN ('Clearance >50%', 'Deep 20-50%', 'Shallow <20%', 'No Discount');

-- check: bmv_promotional_features_markdown_depth | severity: error
-- Ensure markdown_depth_pct is bounded between 0 and 1 (inclusive)
SELECT * FROM ${catalog}.${bmv_schema}.gold_promotional_features
WHERE markdown_depth_pct < 0.0 OR markdown_depth_pct > 1.0;


-- check: bmv_competitor_analysis_undercut_rate | severity: metric
-- Measures the percentage of instances where competitors beat our price
SELECT ROUND(AVG(CASE WHEN is_comp_price_below_own = TRUE THEN 1.0 ELSE 0.0 END), 4) AS competitor_undercut_rate
FROM ${catalog}.${bmv_schema}.gold_competitor_analysis;


-- check: bmv_pricing_constraints_logic | severity: error
-- Minimum bound price cannot be greater than the maximum bound price
SELECT * FROM ${catalog}.${bmv_schema}.gold_pricing_constraints
WHERE min_price_lc > max_price_lc;



-- check: bmv_single_currency_check | severity: error
-- A single-reporting-currency check on monetary facts.
SELECT 1 FROM ${catalog}.${bmv_schema}.competitor_price
HAVING COUNT(DISTINCT currency_code) > 1 OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- check: bmv_fk_orphan_competitor | severity: error
SELECT cp.* FROM ${catalog}.${bmv_schema}.competitor_price cp
WHERE cp.competitor_sk IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM ${catalog}.${bmv_schema}.competitor c WHERE c.competitor_sk = cp.competitor_sk
);

-- check: bmv_fk_orphan_product | severity: error
SELECT cp.* FROM ${catalog}.${bmv_schema}.competitor_price cp
WHERE cp.product_sk IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM ${catalog}.${product_schema}.product p WHERE p.product_sk = cp.product_sk
);

-- check: bmv_rel_fk_orphan_product | severity: error
SELECT pr.* FROM ${catalog}.${bmv_schema}.product_relationship pr
WHERE pr.product_sk IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM ${catalog}.${product_schema}.product p WHERE p.product_sk = pr.product_sk
);

-- check: bmv_rel_fk_orphan_related_product | severity: error
SELECT pr.* FROM ${catalog}.${bmv_schema}.product_relationship pr
WHERE pr.related_product_sk IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM ${catalog}.${product_schema}.product p WHERE p.product_sk = pr.related_product_sk
);

-- check: bmv_competitor_scd2_current_unique | severity: error
-- Ensure only one current active row per competitor_id
SELECT competitor_id
FROM ${catalog}.${bmv_schema}.competitor
WHERE is_current = TRUE
GROUP BY competitor_id
HAVING COUNT(*) > 1;

-- check: bmv_competitor_scd2_non_current_closed | severity: error
-- Ensure non-current rows have an effective_to_date
SELECT *
FROM ${catalog}.${bmv_schema}.competitor
WHERE is_current = FALSE AND effective_to_date IS NULL;

-- check: bmv_competitor_scd2_date_validity | severity: error
-- Ensure effective_from_date is strictly before effective_to_date
SELECT *
FROM ${catalog}.${bmv_schema}.competitor
WHERE effective_from_date >= effective_to_date;

-- check: bmv_product_relationship_grain_unique | severity: error
-- Ensure product relationships are unique per product, related product, and relationship type
SELECT product_id, related_product_id, relationship_type
FROM ${catalog}.${bmv_schema}.product_relationship
GROUP BY product_id, related_product_id, relationship_type
HAVING COUNT(*) > 1;


-- check: bmv_planogram_grain_unique | severity: error
-- Ensure only one current active row per store_id, product_id
SELECT store_id, product_id
FROM ${catalog}.${bmv_schema}.planogram
WHERE is_current = TRUE
GROUP BY store_id, product_id
HAVING COUNT(*) > 1;

-- check: bmv_planogram_non_current_closed | severity: error
-- Ensure non-current rows have an effective_to_date
SELECT store_id, product_id
FROM ${catalog}.${bmv_schema}.planogram
WHERE is_current = FALSE AND effective_to_date IS NULL;

-- check: bmv_planogram_scd2_date_validity | severity: error
-- Ensure effective_from_date is strictly before effective_to_date
SELECT *
FROM ${catalog}.${bmv_schema}.planogram
WHERE effective_from_date >= effective_to_date;

-- check: bmv_planogram_store_fk_orphan | severity: error
-- Ensure planogram store_sk resolves to a valid store
SELECT p.planogram_sk, p.store_sk
FROM ${catalog}.${bmv_schema}.planogram p
LEFT JOIN ${catalog}.${store_schema}.store s ON p.store_sk = s.store_sk
WHERE p.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: bmv_planogram_product_fk_orphan | severity: error
-- Ensure planogram product_sk resolves to a valid product
SELECT p.planogram_sk, p.product_sk
FROM ${catalog}.${bmv_schema}.planogram p
LEFT JOIN ${catalog}.${product_schema}.product pr ON p.product_sk = pr.product_sk
WHERE p.product_sk IS NOT NULL AND pr.product_sk IS NULL;

-- check: bmv_payment_actuals_grain_unique | severity: error
-- Ensure gold_payment_actuals operates at the product x store x date grain
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_payment_actuals
GROUP BY product_sk, store_sk, date_key
HAVING COUNT(*) > 1;

-- check: bmv_payment_actuals_single_currency | severity: error
-- All allocated payment magnitudes are in the single reporting/base currency. NULL-aware
-- (matches bmv_single_currency_check): a NULL currency_code is a leak, not silently ignored.
SELECT DISTINCT currency_code
FROM ${catalog}.${bmv_schema}.gold_payment_actuals
WHERE currency_code <> (SELECT MAX(currency_code) FROM ${catalog}.${bmv_schema}.gold_payment_actuals)
   OR currency_code IS NULL;

-- check: bmv_payment_actuals_nonneg | severity: error
-- Allocated magnitudes are non-negative (payment_type carries direction, amount is a magnitude)
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_payment_actuals
WHERE settled_sale_amount_lc < 0 OR refund_amount_lc < 0
   OR chargeback_amount_lc < 0 OR adjustment_amount_lc < 0;

-- check: bmv_payment_bridge_fk_orphan | severity: warn
-- Payment events whose order_id does not resolve to a customer_order_line. Expected to be non-zero
-- (cash/anonymous/adjustment payments legitimately lack an order); a WARN surfaces the volume that
-- cannot be allocated to a product line rather than gating the build.
SELECT p.payment_id, p.order_id
FROM ${catalog}.${payment_schema}.payment p
LEFT JOIN ${catalog}.${order_schema}.customer_order_line col ON col.order_id = p.order_id
WHERE p.order_id IS NULL OR col.order_id IS NULL;

-- check: bmv_payment_sale_terminal_status | severity: warn
-- Asserts the gold view's lifecycle invariant (M1): a `sale`-typed payment_id's LATEST row is
-- settled/captured. A sale-typed id whose terminal status is anything else (e.g. settled-then-
-- refunded on one id) matches neither the sale nor the refund branch of gold_payment_actuals, so it
-- would contribute to no measure. Expected to be zero on conformant data; a WARN surfaces the shape
-- (rather than gating the build) so it is caught, not silently dropped. If it fires, widen the gold
-- view's sale branch to catch the reversed-terminal case. Collapses to the latest row per payment_id
-- to match the view's H1 dedup.
SELECT payment_id, payment_status
FROM (
  SELECT payment_id, payment_type, payment_status,
         ROW_NUMBER() OVER (PARTITION BY payment_id
                            ORDER BY event_timestamp DESC, payment_sk DESC) AS rn
  FROM ${catalog}.${payment_schema}.payment
)
WHERE rn = 1
  AND payment_type = 'sale'
  AND payment_status NOT IN ('settled', 'captured');

-- check: bmv_payment_alloc_reconciliation | severity: metric
-- Report the share of ALLOCATABLE payment magnitude that landed on the product grain. The
-- denominator is scoped to the SAME event set the gold view aggregates (settled/captured sales +
-- REALIZED refund/chargeback/adjustment) so the gap reflects allocation/bridge loss (orphan/zero-net
-- orders) ONLY, not non-realized volume (authorized/declined/voided). The status predicate mirrors
-- the gold view's M1 guard exactly. To match the view's append-only-lifecycle dedup (H1), the
-- denominator also collapses to the latest row per payment_id, so a multi-row lifecycle counts its
-- magnitude once on both sides. Metric never fails the run.
SELECT
  (SELECT COALESCE(SUM(settled_sale_amount_lc + refund_amount_lc + chargeback_amount_lc + adjustment_amount_lc), 0)
     FROM ${catalog}.${bmv_schema}.gold_payment_actuals)
  / NULLIF((
      SELECT SUM(amount) FROM (
        SELECT amount, payment_type, payment_status,
               ROW_NUMBER() OVER (PARTITION BY payment_id
                                  ORDER BY event_timestamp DESC, payment_sk DESC) AS rn
        FROM ${catalog}.${payment_schema}.payment
      )
      WHERE rn = 1
        AND ((payment_type IN ('refund', 'chargeback', 'adjustment')
                AND payment_status NOT IN ('authorized', 'declined', 'voided'))
             OR (payment_type = 'sale' AND payment_status IN ('settled', 'captured')))), 0)
    AS pct_payment_magnitude_allocated;

-- check: bmv_assortment_recommendation_domain | severity: error
-- The rule-based recommendation is one of the three allowed actions (never NULL/other)
SELECT product_sk, store_sk, recommendation
FROM ${catalog}.${bmv_schema}.gold_assortment_optimization
WHERE recommendation NOT IN ('KEEP', 'DROP', 'EXPAND') OR recommendation IS NULL;

-- check: bmv_assortment_computed_not_all_null | severity: error
-- Guard the NULL-KPI regression: when the view has rows, the computed columns must have at least
-- one non-NULL value (a 100%-NULL governed output is the anti-pattern this view was fixed to avoid).
-- The COUNT(*) > 0 guard means a legitimately-empty deploy stage does NOT red the run (empty != all-NULL).
SELECT 1
FROM ${catalog}.${bmv_schema}.gold_assortment_optimization
HAVING COUNT(*) > 0 AND (COUNT(margin_contribution_pct) = 0 OR COUNT(baseline_velocity) = 0
                         OR COUNT(projected_volume_lift) = 0);

-- check: bmv_assortment_space_elasticity_valid | severity: error
-- The heuristic space elasticity is clamped to [0, 1], carries a positive standard error, and is only
-- set exactly on rows that have a planogram allocation with a category (no allocation or no category
-- -> NULL, while a category with no usable fit still gets the 0.17 prior).
SELECT product_sk, store_sk, allocated_facings, space_elasticity, space_elasticity_se, space_elasticity_n_obs
FROM ${catalog}.${bmv_schema}.gold_assortment_optimization
WHERE (space_elasticity IS NOT NULL AND (space_elasticity < 0 OR space_elasticity > 1
                                         OR space_elasticity_se IS NULL OR space_elasticity_se <= 0
                                         OR space_elasticity_n_obs IS NULL OR space_elasticity_n_obs < 0))
   OR (space_elasticity IS NOT NULL AND allocated_facings IS NULL)
   OR (space_elasticity IS NULL AND allocated_facings IS NOT NULL
       AND EXISTS (SELECT 1 FROM ${catalog}.${bmv_schema}.planogram pl
                   WHERE pl.product_sk = gold_assortment_optimization.product_sk
                     AND pl.store_sk = gold_assortment_optimization.store_sk
                     AND pl.space_planning_category IS NOT NULL
                     AND gold_assortment_optimization.snapshot_date >= pl.effective_from_date
                     AND (pl.effective_to_date IS NULL OR gold_assortment_optimization.snapshot_date < pl.effective_to_date)));

-- check: bmv_assortment_space_elasticity_estimated | severity: warn
-- When the view has planogram-backed rows, at least one category's elasticity should come from data
-- (n_obs > 0) rather than the prior alone; all-prior means the planogram/sales overlap is too thin to fit.
SELECT 1
FROM ${catalog}.${bmv_schema}.gold_assortment_optimization
HAVING COUNT(space_elasticity) > 0 AND MAX(space_elasticity_n_obs) = 0;

-- check: bmv_assortment_projection_sign | severity: error
-- Scenario projections follow the recommendation: KEEP projects no change; DROP removes the SKU's own
-- units (lift <= 0); EXPAND adds units (lift >= 0). The drag's sign also depends on the substitutes'
-- unit margin, which can be negative, so only KEEP pins it (to 0).
SELECT product_sk, store_sk, recommendation, projected_volume_lift, cannibalization_drag_lc
FROM ${catalog}.${bmv_schema}.gold_assortment_optimization
WHERE (recommendation = 'KEEP'   AND (projected_volume_lift <> 0 OR cannibalization_drag_lc <> 0))
   OR (recommendation = 'DROP'   AND projected_volume_lift > 0)
   OR (recommendation = 'EXPAND' AND projected_volume_lift < 0);

-- check: bmv_affinity_demand_transfer_range | severity: error
-- The demand-transfer share is a fraction: never NULL (0 when no substitute is mapped), within [0, 1].
SELECT product_sk, store_sk, date_key, substitute_demand_transfer_pct
FROM ${catalog}.${bmv_schema}.gold_affinity_features
WHERE substitute_demand_transfer_pct IS NULL
   OR substitute_demand_transfer_pct < 0 OR substitute_demand_transfer_pct > 1;

-- check: bmv_realized_margin_grain_unique | severity: error
-- Ensure gold_realized_margin operates at the product x store x date grain
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_realized_margin
GROUP BY product_sk, store_sk, date_key
HAVING COUNT(*) > 1;

-- check: bmv_realized_margin_booked_revenue_identity | severity: error
-- Verify booked_revenue_lc = pos_net_sales_lc + order_booked_sales_lc within 0.02 tolerance
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_realized_margin
WHERE ABS(booked_revenue_lc - (pos_net_sales_lc + order_booked_sales_lc)) > 0.02;

-- check: bmv_realized_margin_realized_revenue_identity | severity: error
-- Verify realized_revenue_lc = pos_net_sales_lc + order_settled_sales_lc - order_refund_lc - order_chargeback_lc - order_adjustment_lc within 0.02 tolerance
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_realized_margin
WHERE ABS(realized_revenue_lc - (pos_net_sales_lc + order_settled_sales_lc - order_refund_lc - order_chargeback_lc - order_adjustment_lc)) > 0.02;

-- check: bmv_realized_margin_leakage_identity | severity: error
-- Verify leakage_lc = booked_revenue_lc - realized_revenue_lc within 0.02 tolerance
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_realized_margin
WHERE ABS(leakage_lc - (booked_revenue_lc - realized_revenue_lc)) > 0.02;

-- check: bmv_realized_margin_cogs_identity | severity: error
-- Verify cogs_lc = pos_cogs_lc + order_cogs_lc within 0.02 tolerance
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_realized_margin
WHERE ABS(cogs_lc - (pos_cogs_lc + order_cogs_lc)) > 0.02;

-- check: bmv_realized_margin_booked_margin_identity | severity: error
-- Verify booked_margin_lc = booked_revenue_lc - cogs_lc within 0.02 tolerance
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_realized_margin
WHERE ABS(booked_margin_lc - (booked_revenue_lc - cogs_lc)) > 0.02;

-- check: bmv_realized_margin_realized_margin_identity | severity: error
-- Verify realized_margin_lc = realized_revenue_lc - cogs_lc within 0.02 tolerance
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_realized_margin
WHERE ABS(realized_margin_lc - (realized_revenue_lc - cogs_lc)) > 0.02;

-- check: bmv_realized_margin_nonneg_order_amounts | severity: error
-- Allocated payment magnitudes are non-negative: payment amounts are non-negative by contract and the
-- allocation weight is clamped at 0, so a negative value here means the view regressed.
-- (Booked order sales and COGS follow core order-line values, which carry no non-negativity CHECK;
-- they are covered by the warn-severity check below.)
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_realized_margin
WHERE order_settled_sales_lc < 0 OR order_refund_lc < 0 OR order_chargeback_lc < 0 OR order_adjustment_lc < 0;

-- check: bmv_realized_margin_nonneg_booked_and_cogs | severity: warn
-- Booked sales and COGS on either channel can legitimately be negative on otherwise-valid core data:
-- POS when an adopter loads returns as negative units, orders when a line carries a negative net
-- (deep discount or return line; customer_order_line.net_amount has no non-negativity CHECK).
-- Surfaced as a warning rather than failing the run, matching gold_payment_actuals, which clamps
-- such lines to zero allocation weight for the same reason.
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_realized_margin
WHERE pos_cogs_lc < 0 OR pos_net_sales_lc < 0 OR order_booked_sales_lc < 0 OR order_cogs_lc < 0;

-- check: bmv_realized_margin_unsettled_sanity | severity: warn
-- When order_unsettled_sales_lc is negative (settled > booked), flag for investigation. The usual cause
-- is an amount-basis mismatch: payment sale amounts that include tax or shipping while
-- customer_order_line.net_amount excludes them. Net those out upstream so both are on the same basis.
SELECT product_sk, store_sk, date_key
FROM ${catalog}.${bmv_schema}.gold_realized_margin
WHERE order_unsettled_sales_lc < -0.05;

-- check: bmv_realized_margin_reversal_exceeds_settled_sale | severity: warn
-- Refunds, chargebacks and adjustments on an order exceed what its captured/settled sale collected: either
-- there was no collected sale at all (a void recorded as a refund, or a missing capture upstream),
-- or the order was reversed twice (a partial refund followed by a full chargeback). Either way
-- gold_realized_margin reports that order below zero realized revenue. Same dedup and status
-- predicates as the views; 0.01 tolerance for rounding.
SELECT order_id, settled_sale_amount, reversal_amount
FROM (
  SELECT
    order_id,
    SUM(CASE WHEN payment_type = 'sale' AND payment_status IN ('settled', 'captured')
             THEN amount ELSE 0 END) AS settled_sale_amount,
    SUM(CASE WHEN payment_type IN ('refund', 'chargeback', 'adjustment')
              AND payment_status NOT IN ('authorized', 'declined', 'voided')
             THEN amount ELSE 0 END) AS reversal_amount
  FROM (
    SELECT order_id, payment_type, payment_status, amount,
           ROW_NUMBER() OVER (PARTITION BY payment_id
                              ORDER BY event_timestamp DESC, payment_sk DESC) AS rn
    FROM ${catalog}.${payment_schema}.payment
    WHERE order_id IS NOT NULL
  )
  WHERE rn = 1
  GROUP BY order_id
)
WHERE reversal_amount > settled_sale_amount + 0.01;

-- check: bmv_realized_margin_single_currency | severity: error
-- All rows use the single reporting/base currency; no NULL or mixed currencies allowed
SELECT DISTINCT currency_code
FROM ${catalog}.${bmv_schema}.gold_realized_margin
WHERE currency_code <> (SELECT MAX(currency_code) FROM ${catalog}.${bmv_schema}.gold_realized_margin)
   OR currency_code IS NULL;

-- check: bmv_realized_margin_computed_not_all_null | severity: error
-- Guard NULL-KPI regression: when rows exist, computed measures must have at least one non-NULL value
SELECT 1
FROM ${catalog}.${bmv_schema}.gold_realized_margin
HAVING COUNT(*) > 0 AND (COUNT(realized_revenue_lc) = 0 OR COUNT(realized_margin_lc) = 0 OR COUNT(booked_revenue_lc) = 0);

-- check: bmv_realized_margin_conservation_order_refund | severity: error
-- Lifetime SUM(order_refund_lc) in gold_realized_margin equals gold_payment_actuals refund_amount_lc sum
-- within max(1.00, 0.1%) tolerance. Both sides allocate the same events (payments whose order has
-- lines; NULL-order and zero-net events are excluded by both) with identical predicates:
-- payment_type='refund' AND payment_status NOT IN ('authorized', 'declined', 'voided').
SELECT 1 AS mismatch
WHERE ABS(
  (SELECT COALESCE(SUM(order_refund_lc), 0) FROM ${catalog}.${bmv_schema}.gold_realized_margin)
  -
  (SELECT COALESCE(SUM(refund_amount_lc), 0) FROM ${catalog}.${bmv_schema}.gold_payment_actuals)
) > GREATEST(1.00, 0.001 * ABS((SELECT COALESCE(SUM(order_refund_lc), 0) FROM ${catalog}.${bmv_schema}.gold_realized_margin)));

-- check: bmv_realized_margin_conservation_order_chargeback | severity: error
-- Lifetime SUM(order_chargeback_lc) in gold_realized_margin equals gold_payment_actuals chargeback_amount_lc sum
-- within max(1.00, 0.1%) tolerance. Both sides use identical allocation predicates:
-- payment_type='chargeback' AND payment_status NOT IN ('authorized', 'declined', 'voided').
SELECT 1 AS mismatch
WHERE ABS(
  (SELECT COALESCE(SUM(order_chargeback_lc), 0) FROM ${catalog}.${bmv_schema}.gold_realized_margin)
  -
  (SELECT COALESCE(SUM(chargeback_amount_lc), 0) FROM ${catalog}.${bmv_schema}.gold_payment_actuals)
) > GREATEST(1.00, 0.001 * ABS((SELECT COALESCE(SUM(order_chargeback_lc), 0) FROM ${catalog}.${bmv_schema}.gold_realized_margin)));

-- check: bmv_realized_margin_conservation_order_adjustment | severity: error
-- Lifetime SUM(order_adjustment_lc) in gold_realized_margin equals gold_payment_actuals adjustment_amount_lc sum
-- within max(1.00, 0.1%) tolerance. Both sides use identical allocation predicates:
-- payment_type='adjustment' AND payment_status NOT IN ('authorized', 'declined', 'voided').
-- Note: adjustments with NULL order_id cannot be allocated and are excluded from both views.
SELECT 1 AS mismatch
WHERE ABS(
  (SELECT COALESCE(SUM(order_adjustment_lc), 0) FROM ${catalog}.${bmv_schema}.gold_realized_margin)
  -
  (SELECT COALESCE(SUM(adjustment_amount_lc), 0) FROM ${catalog}.${bmv_schema}.gold_payment_actuals)
) > GREATEST(1.00, 0.001 * ABS((SELECT COALESCE(SUM(order_adjustment_lc), 0) FROM ${catalog}.${bmv_schema}.gold_realized_margin)));

-- check: bmv_realized_margin_conservation_pos_booked | severity: error
-- Booked-side conservation: lifetime POS net sales in gold_realized_margin equal the POS sales fact.
-- Catches a join that silently drops sales (e.g. a product or store key with no match).
SELECT 1 AS mismatch
WHERE ABS(
  (SELECT COALESCE(SUM(pos_net_sales_lc), 0) FROM ${catalog}.${bmv_schema}.gold_realized_margin)
  -
  (SELECT COALESCE(SUM(net_revenue), 0) FROM ${catalog}.${transaction_schema}.sales)
) > GREATEST(1.00, 0.001 * ABS((SELECT COALESCE(SUM(net_revenue), 0) FROM ${catalog}.${transaction_schema}.sales)));

-- check: bmv_realized_margin_conservation_order_booked | severity: error
-- Booked-side conservation: lifetime order booked sales equal the order-line fact.
SELECT 1 AS mismatch
WHERE ABS(
  (SELECT COALESCE(SUM(order_booked_sales_lc), 0) FROM ${catalog}.${bmv_schema}.gold_realized_margin)
  -
  (SELECT COALESCE(SUM(net_amount), 0) FROM ${catalog}.${order_schema}.customer_order_line)
) > GREATEST(1.00, 0.001 * ABS((SELECT COALESCE(SUM(net_amount), 0) FROM ${catalog}.${order_schema}.customer_order_line)));

-- check: bmv_realized_margin_unit_cost_coverage | severity: warn
-- Share of booked revenue on products with no unit_cost (missing product row or NULL
-- product.unit_cost, which the product checks tolerate). That revenue carries no COGS, so realized
-- margin is overstated by it. Fires when more than 1% of booked revenue is uncosted.
SELECT uncosted_booked_lc, booked_lc
FROM (
  SELECT
    SUM(CASE WHEN p.unit_cost IS NULL THEN g.booked_revenue_lc ELSE 0 END) AS uncosted_booked_lc,
    SUM(g.booked_revenue_lc) AS booked_lc
  FROM ${catalog}.${bmv_schema}.gold_realized_margin g
  LEFT JOIN ${catalog}.${product_schema}.product p ON g.product_sk = p.product_sk
)
WHERE booked_lc > 0 AND uncosted_booked_lc > 0.01 * booked_lc;

-- check: bmv_realized_margin_no_raw_pii | severity: error
-- The realized-margin gold view is aggregate (product x store x date);
-- it must not expose customer/order identifiers or PII per the spec: profile_id, profile_sk,
-- order_id, order_line_id, payment_id, customer_id, email. Legitimate aggregate columns like
-- product_id and store_id are not flagged.
SELECT table_name, column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${bmv_schema}'
  AND table_name IN ('gold_realized_margin')
  AND column_name IN ('profile_id', 'profile_sk', 'order_id', 'order_line_id',
                      'payment_id', 'customer_id', 'email');
