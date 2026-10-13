-- ============================================================
-- ORDM · Semantic Comments · Balancing Margin and Volume
-- Pushes definitions and context directly to Unity Catalog for
-- Genie and AI-BI natural language discovery.
-- Last reviewed: 2026-06-22 by @ojasvi-goyal-03
-- ============================================================

-- ============================================================
-- TABLE: gold_affinity_features
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.gold_affinity_features IS 'Cross-elasticity features derived from product relationships (substitutes and complements).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_affinity_features.substitute_price_ratio IS 'Own price divided by average substitute price.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_affinity_features.complement_price_ratio IS 'Own price divided by average complement price.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_affinity_features.substitute_markdown_depth_pct IS 'Average markdown depth of substitute products.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_affinity_features.complement_markdown_depth_pct IS 'Average markdown depth of complement products.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_affinity_features.substitute_demand_transfer_pct IS 'Share of this SKU demand assumed to move to its mapped substitutes if it is removed or out of stock: 1 - product of (1 - affinity_coefficient) over its substitutes, reading each affinity as the share of shoppers who accept that substitute. 0 when no substitute is mapped. Heuristic assumption; adopters can replace it with a fitted demand-transfer model.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_affinity_features.product_sk IS 'Surrogate key for the product.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_affinity_features.store_sk IS 'Surrogate key for the store.';


-- ============================================================
-- TABLE: gold_assortment_optimization
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.gold_assortment_optimization IS 'Assortment optimization: features, a rule-based recommendation, and heuristic model outputs (space elasticity, projected lift, cannibalization).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.allocated_facings IS 'Number of facings on the planogram.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.allocated_sqft IS 'Square footage on the planogram.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.substitute_demand_transfer_pct IS 'Share of this SKU demand assumed to move to its mapped substitutes if it is removed (0 to 1; 0 when no substitute is mapped). Heuristic over product_relationship affinities, from gold_affinity_features; an assumption, not estimated from observed substitution.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.rolling_sales_velocity_14d IS '14-day rolling average of daily units sold.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.rolling_revenue_14d IS '14-day rolling sum of daily net revenue.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.rolling_margin_base_rev_14d IS '14-day rolling sum of net revenue on days that carry a gross-margin rate; the denominator base for margin_contribution_pct so days lacking a rate do not bias it down.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.units_on_hand_eod IS 'Units on hand at end of day.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.baseline_velocity IS '28-day non-promo observed mean units/day (heuristic baseline proxy; ratio of baseline_units_28d / baseline_nonpromo_days_28d).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.margin_contribution_pct IS '14-day realized gross-margin rate = rolling_margin_14d / rolling_margin_base_rev_14d (rate-bearing revenue only).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.recommendation IS 'Rule-based assortment action (KEEP / DROP / EXPAND) over velocity + margin buckets and days-on-hand; deterministic, not ML.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.space_elasticity IS 'Heuristic space elasticity: percent change in units per 1 percent change in facings, per space-planning category. Within-product cross-store log-log slope of non-promo velocity on facings, shrunk toward a 0.17 prior (Eisend 2014 meta-analytic average) by its standard error, clamped to 0..1. Observational, not causal. NULL when the SKU x store has no planogram allocation.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.projected_volume_lift IS 'Scenario: change in this SKU own units per selling day at the baseline rate if the recommendation is applied. EXPAND adds one facing (baseline x (((facings + 1) / facings) ^ space_elasticity - 1)); DROP removes the SKU (minus baseline_velocity); KEEP is 0. Not a forecast.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.projected_margin_lift_lc IS 'Scenario: net gross-margin change per selling day in local currency if the recommendation is applied = projected_volume_lift x own unit margin - cannibalization_drag_lc. Unit margin is the 14-day margin over units on rate-bearing days.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.cannibalization_drag_lc IS 'Scenario: gross margin per selling day in local currency that the action takes from mapped substitutes = projected_volume_lift x store-conditional demand transfer (1 - product of (1 - affinity) over the mapped substitutes sold in the store) x affinity-weighted substitute unit margin (0 when no mapped substitute sells in the store; own unit margin when substitutes sell there but their margin is unknown). Positive on EXPAND, negative (recapture) on DROP, 0 on KEEP.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.space_elasticity_se IS 'Standard error of space_elasticity after shrinkage toward the prior (0.10 when only the prior is used).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.space_elasticity_n_obs IS 'Number of product x store x planogram-allocation observations behind the category space_elasticity fit (0 = prior only).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.product_sk IS 'Surrogate key for the product.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.store_sk IS 'Surrogate key for the store.';


-- ============================================================
-- TABLE: gold_bucket_features
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.gold_bucket_features IS 'Categorical bands and buckets for simplified segmentation.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_bucket_features.margin_health_bucket IS 'Categorical indicator of gross margin performance (e.g., ''High'', ''Healthy'', ''Bleeding'').';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_bucket_features.competitive_pressure_bucket IS 'Categorical indicator of competitor price aggression (e.g., ''Severe'', ''Moderate'', ''Low'').';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_bucket_features.discount_depth_bucket IS 'Categorical depth of the current markdown (e.g., ''Clearance >50%'', ''Shallow <10%'').';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_bucket_features.demand_bucket_7d IS 'Categorical volume tier based on the last 7 days of sales.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_bucket_features.weeks_of_cover_bucket IS 'Inventory health indicator categorizing stock life (e.g., ''<1 Week'', ''Overstock'').';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_bucket_features.article_age_bucket IS 'Lifecycle stage of the product (e.g., ''New Arrival'', ''Mature'', ''End of Life'').';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_bucket_features.demand_velocity_bucket IS 'Categorical speed of sales (e.g., ''Fast Mover'', ''Slow Mover'').';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_bucket_features.promo_frequency_bucket IS 'Categorical classification of how often the item is discounted.';

-- ============================================================
-- TABLE: gold_competitor_analysis
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.gold_competitor_analysis IS 'Competitive intelligence metrics and price gaps.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_competitor_analysis.competitor_regular_price_lc IS 'The tracked shelf price of the matched competitor.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_competitor_analysis.price_gap_lc IS 'The absolute difference: effective_price_lc - competitor_regular_price_lc.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_competitor_analysis.price_index_vs_comp IS '(effective_price_lc / competitor_regular_price_lc) * 100.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_competitor_analysis.is_comp_price_below_own IS 'True if the competitor is pricing lower than our effective price.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_competitor_analysis.product_sk IS 'Surrogate key for the product.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_competitor_analysis.store_sk IS 'Surrogate key for the store.';

-- ============================================================
-- TABLE: gold_external_signals
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.gold_external_signals IS 'External macro factors, weather, and footfall confounders.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_external_signals.local_footfall_index IS 'Index representing overall traffic volume in the specific store/location.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_external_signals.temp_max_celsius IS 'Maximum recorded temperature for the day at the store location.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_external_signals.rainfall_mm IS 'Total rainfall in millimeters for the day.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_external_signals.is_heatwave IS 'Boolean flag triggered when temperatures exceed specific regional thresholds.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_external_signals.cpi_category_monthly_index IS 'The macroeconomic Consumer Price Index specific to the subcategory.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_external_signals.fuel_price_index IS 'Macroeconomic tracking of fuel prices, influencing discretionary spending.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_external_signals.is_state_election_day IS 'Boolean flag for local/state election events impacting shopping behavior.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_external_signals.is_major_sporting_event_local IS 'Boolean flag for local major sporting events driving specific traffic patterns.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_external_signals.product_sk IS 'Surrogate key for the product.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_external_signals.store_sk IS 'Surrogate key for the store.';



-- ============================================================
-- TABLE: gold_price_actuals
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.gold_price_actuals IS 'Daily price points and margin actuals.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_price_actuals.base_price_lc IS 'The regular, undiscounted shelf price in local currency.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_price_actuals.effective_price_lc IS 'The actual price paid after promotional discounts.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_price_actuals.mrp_lc IS 'Manufacturer suggested retail price in local currency.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_price_actuals.gross_margin_pct IS '(effective_price_lc - cost_price_lc) / effective_price_lc.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_price_actuals.cost_price_lc IS 'The unit cost of goods sold.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_price_actuals.price_change_direction IS 'Indicator of whether the price increased, decreased, or remained flat.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_price_actuals.price_change_magnitude_pct IS 'The percentage change in price compared to the previous period.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_price_actuals.days_since_last_price_change IS 'Tracks the decay of consumer shock as they adapt to new prices.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_price_actuals.price_barrier_proximity IS 'effective_price_lc % 1.00, measuring proximity to psychological boundaries like .99.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_price_actuals.product_sk IS 'Surrogate key for the product.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_price_actuals.store_sk IS 'Surrogate key for the store.';

-- ============================================================
-- TABLE: gold_pricing_constraints
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.gold_pricing_constraints IS 'Business constraints limiting the price optimization solver.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_pricing_constraints.mrp_lc IS 'Maximum Retail Price ceiling.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_pricing_constraints.min_margin_pct IS 'Minimum acceptable profit margin percentage.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_pricing_constraints.max_discount_pct IS 'Maximum allowed discount depth percentage.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_pricing_constraints.min_price_lc IS 'Derived minimum price bounded by cost and min margin.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_pricing_constraints.max_price_lc IS 'Derived maximum price bounded by MRP.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_pricing_constraints.max_competitor_index IS 'Maximum allowable price index against the primary competitor.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_pricing_constraints.price_rounding_rule_code IS 'Rule applied to round recommended prices.';

-- ============================================================
-- TABLE: gold_promotional_features
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.gold_promotional_features IS 'Promotional events and markdown depth features.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.is_on_promo IS 'Boolean indicating if any promotion is currently active.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.markdown_event_flag IS 'Boolean indicating if a specific markdown event is active.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.markdown_depth_pct IS 'The percentage depth of the markdown relative to base price.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.is_promo_start_day IS 'Boolean indicating if a new promotion started exactly on this date.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.days_into_promo IS 'The number of days elapsed since the current promotion started.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.days_to_promo_end IS 'The number of days remaining until the current promotion expires.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.is_promo_last_day IS 'Boolean indicating if this is the final day of the promotion.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.days_post_promo_end IS 'The number of days elapsed since the last promotion ended.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.is_post_promo_decay_window IS 'Boolean indicating if the product is in the immediate post-promo "hangover" period.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.promo_frequency_30d IS 'The number of distinct promotional days in the last 30 days.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.days_since_last_promo IS 'The number of days since the product was last on promotion.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.concurrent_promo_count IS 'The number of overlapping promotional mechanics currently active.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.promo_type IS 'Promotion mechanic type (e.g., TPR, DISPLAY).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.funding_type IS 'How the promotion is funded.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.planned_discount_pct IS 'The planned percentage depth of the markdown.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.product_sk IS 'Surrogate key for the product.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_promotional_features.store_sk IS 'Surrogate key for the store.';


-- ============================================================
-- TABLE: gold_sales_actuals
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.gold_sales_actuals IS 'Grain-level sales and volume actuals.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_sales_actuals.units_sold IS 'Raw units sold at the till.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_sales_actuals.gross_sales_lc IS 'Total sales value before discounts.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_sales_actuals.net_sales_lc IS 'Total sales value after discounts.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_sales_actuals.returns_units IS 'Units returned by customers.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_sales_actuals.net_units_sold IS 'units_sold - returns_units.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_sales_actuals.baseline_units_sold IS 'De-seasonalized and de-promoted normal demand.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_sales_actuals.incremental_lift_units IS 'Extra units sold attributable specifically to a promotion.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_sales_actuals.stockout_pct_day IS 'Percentage of the day the product was out of stock on shelf.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_sales_actuals.units_received_today IS 'Units received today for sell-through calculation.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_sales_actuals.product_sk IS 'Surrogate key for the product.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_sales_actuals.store_sk IS 'Surrogate key for the store.';

-- ============================================================
-- TABLE: gold_seasonality_features
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.gold_seasonality_features IS 'Seasonal and cyclical encodings for baseline models.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_seasonality_features.is_weekend_flag IS 'Boolean indicating if the date falls on a weekend.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_seasonality_features.is_public_holiday IS 'Boolean indicating if the date is a public holiday.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_seasonality_features.is_peak_shopping_season IS 'Boolean indicating if the date falls in a high-demand retail period.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_seasonality_features.days_to_next_holiday IS 'Days remaining until the next public holiday.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_seasonality_features.days_since_last_holiday IS 'Days elapsed since the previous public holiday.';


-- ============================================================
-- TABLE: competitor
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.competitor IS 'Competitor master dimension for price elasticity modeling.';

-- ============================================================
-- TABLE: competitor_price
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.competitor_price IS 'Scraped or sourced competitor pricing fact table.';

-- ============================================================
-- TABLE: product_relationship
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.product_relationship IS 'Product portfolio relationships (substitutes and complements) for cross-price elasticity calculations.';


-- ============================================================
-- TABLE: planogram
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.planogram IS 'Planogram and space allocation dimension capturing physical store layout.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.planogram.allocated_facings IS 'Number of physical facings allocated on the shelf.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.planogram.allocated_sqft IS 'Square footage allocated to the product on the shelf.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.planogram.space_planning_category IS 'Merchandising category for the planogram allocation.';

-- TABLE: gold_payment_actuals (payment-side revenue leakage at product x store x day)
COMMENT ON TABLE ${catalog}.${bmv_schema}.gold_payment_actuals IS 'Payment-side revenue leakage at product x store x day: order-grain payment events allocated to product lines by net-amount value-share (via order.customer_order_line). First consumer of the payment core domain.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_payment_actuals.product_sk IS 'Surrogate key for the product (from the order line the payment allocated to).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_payment_actuals.store_sk IS 'Surrogate key for the store (from the order line).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_payment_actuals.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_payment_actuals.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_payment_actuals.date_key IS 'Payment event date (when money moved), not the original sale date.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_payment_actuals.currency_code IS 'Reporting/base currency of all monetary columns (ISO 4217 alpha-3); single-currency by construction.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_payment_actuals.settled_sale_amount_lc IS 'Allocated magnitude of settled/captured sale payments; the base for payment-side leakage rates.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_payment_actuals.refund_amount_lc IS 'Allocated magnitude of merchant-initiated refunds (contra-revenue). Distinct from chargebacks.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_payment_actuals.chargeback_amount_lc IS 'Allocated magnitude of bank-initiated payment reversals (disputes); involuntary, typically irrecoverable, never touches the POS sales fact.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_payment_actuals.adjustment_amount_lc IS 'Allocated magnitude of post-sale payment adjustments (goodwill / corrections); treated as contra-revenue.';

-- gold_assortment_optimization additive numerator columns (exposed for ratio-of-sums in metric views)
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.rolling_margin_14d IS '14-day rolling sum of daily gross-margin dollars (numerator for margin_contribution_pct).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.baseline_units_28d IS '28-day non-promo unit sum (numerator for baseline_velocity).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_assortment_optimization.baseline_nonpromo_days_28d IS '28-day count of non-promo days (denominator for baseline_velocity).';

-- ============================================================
-- TABLE: gold_realized_margin
-- ============================================================
COMMENT ON TABLE ${catalog}.${bmv_schema}.gold_realized_margin IS 'Sale-cohort revenue realization at product x store x date grain: booked and realized revenue with payment reversals (refund, chargeback, adjustment) and unsettled amounts attributed to the sale date (POS) or order date (orders). Order-line allocation via net-amount revenue-share (as in gold_payment_actuals). Conservative COGS (no restock recovery from refunded goods). Identities, leakage buckets, operational estimates not an accounting close.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.product_sk IS 'Surrogate key for the product (resolved by SCD2 product version at ingest).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.store_sk IS 'Surrogate key for the store.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.date_key IS 'Sale cohort date: POS transaction date or order date (not payment event date). Recent cohorts are immature; reversals can land weeks after the sale.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.currency_code IS 'Reporting/base currency of all monetary columns (ISO 4217 alpha-3); single-currency by construction.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.pos_units IS 'SUM of net units from POS sales (sales.units), accounting for returns as negative units.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.pos_net_sales_lc IS 'SUM of net revenue from POS transactions (sales.net_revenue).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.pos_cogs_lc IS 'SUM(units * product.unit_cost) for POS sales by product version (SCD2 as-of the ingest date).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.order_units IS 'SUM of units from customer order lines (net of internal payment allocations).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.order_booked_sales_lc IS 'SUM of booked net amount from customer order lines (customer_order_line.net_amount).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.order_settled_sales_lc IS 'SUM of order-line allocated amount from settled/captured payments (net-share allocation, same predicates as gold_payment_actuals).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.order_unsettled_sales_lc IS 'order_booked_sales_lc - order_settled_sales_lc; booked revenue not yet received as payment (authorized/declined/voided attempts excluded).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.order_refund_lc IS 'SUM of order-line allocated amount from merchant-initiated refunds; contra-revenue (not recovered from COGS).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.order_chargeback_lc IS 'SUM of order-line allocated amount from bank-initiated chargebacks (payment disputes); contra-revenue.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.order_adjustment_lc IS 'SUM of order-line allocated amount from post-sale adjustments (goodwill, corrections); contra-revenue (NULL order_id adjustments excluded).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.order_cogs_lc IS 'SUM(units * product.unit_cost) for order lines by product version (SCD2 as-of); no recovery on refunded merchandise.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.booked_revenue_lc IS 'pos_net_sales_lc + order_booked_sales_lc; total booked revenue from both channels on sale cohort date.';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.realized_revenue_lc IS 'pos_net_sales_lc + order_settled_sales_lc - order_refund_lc - order_chargeback_lc - order_adjustment_lc; cash-basis revenue (payment event amounts attributed to sale date).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.leakage_lc IS 'booked_revenue_lc - realized_revenue_lc; equals order_unsettled_sales_lc + order_refund_lc + order_chargeback_lc + order_adjustment_lc (unreceived and reversed payment amounts).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.cogs_lc IS 'pos_cogs_lc + order_cogs_lc; total cost of goods sold (COGS not recovered on refunded merchandise).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.booked_margin_lc IS 'booked_revenue_lc - cogs_lc; gross margin on booked revenue (pre-payment collection).';
COMMENT ON COLUMN ${catalog}.${bmv_schema}.gold_realized_margin.realized_margin_lc IS 'realized_revenue_lc - cogs_lc; gross margin on realized (cash-basis) revenue after payment reversals.';
