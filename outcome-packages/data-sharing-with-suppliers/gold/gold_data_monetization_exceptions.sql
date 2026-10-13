-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- View: gold_data_monetization_exceptions
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Inherits the entitlement carried by
--   gold_data_product_revenue (principal_id); apply the same deploy-time row filter.
-- Version: 0.5
-- Generated: 2026-08-03
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-03
-- ============================================================
-- Data-monetization attention queue over gold_data_product_revenue: the licence ×
-- period rows a commercial owner should act on, ranked by revenue at risk. An exception
-- is raised when a licence was paid for and not used (the churn signal), when
-- consumption ran materially beyond the contracted allowance (an upsell or an
-- over-run to true up), when a term is about to lapse without renewal, or when the
-- effective price per unit diverges materially from the published rate card. Reads only
-- the entitled revenue view, so it exposes no row a partner could not already see.
--
-- Grain: one row per exception (principal × data product × supplier scope × fiscal year ×
-- fiscal period), same as the underlying entitled revenue view — the row carries
-- principal_id and priority_rank is ranked within each principal, so aggregate only
-- within a principal (or after the row filter) to avoid double-counting across entitled
-- principals.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${dss_schema}.gold_data_monetization_exceptions AS
WITH flagged AS (
  SELECT
    principal_id,
    data_product_id,
    data_product_name,
    data_product_category,
    pricing_model,
    supplier_scope_id,
    supplier_name,
    fiscal_year,
    fiscal_period,
    subscription_status,
    term_end_date,
    contracted_price_amount,
    contracted_units,
    consumption_units,
    data_revenue_amount,
    currency_code,
    contract_utilisation_pct,
    revenue_per_consumption_unit,
    contract_discount_pct,
    last_usage_date,
    -- Exception taxonomy (first matching reason wins, so a row is raised once under its
    -- most material reason). The 0.10 / 1.20 / 0.25 tolerances and the 90-day lapse
    -- window are LITERAL reference defaults baked into this view; "tuning" them means
    -- editing this SQL (there is no deploy-time parameter). A deployment that needs them
    -- configurable should lift them to a small threshold table or a bundle variable.
    CASE
      -- A row whose usage was WITHHELD by the disclosure floor is not an exception: its
      -- measures are NULL because they were suppressed, not because nothing happened.
      -- Checked FIRST so a suppressed row can never be misread as paid-but-unused (which
      -- would raise a false churn alarm on a licence that was, in fact, being used).
      WHEN COALESCE(usage_suppressed_flag, FALSE) THEN NULL
      -- Paid for and never touched in the period: the clearest churn signal, and the
      -- reason the revenue view deliberately keeps zero-consumption rows.
      WHEN COALESCE(consumption_units, 0) = 0 AND COALESCE(contracted_price_amount, 0) > 0
        THEN 'paid_unused_subscription'
      -- Consumed well below the commitment (but not zero) — a downgrade/renewal risk.
      WHEN contract_utilisation_pct IS NOT NULL AND contract_utilisation_pct < 0.10
        THEN 'under_consumed_subscription'
      -- Ran beyond the commitment — an upsell opportunity or an over-run to true up.
      WHEN contract_utilisation_pct IS NOT NULL AND contract_utilisation_pct > 1.20
        THEN 'over_contracted_consumption'
      -- Term ends within 90 days of the period it is being reported in, and the licence
      -- has not already been cancelled/expired — a renewal that needs working.
      WHEN term_end_date IS NOT NULL
       AND subscription_status = 'active'
       AND DATEDIFF(term_end_date, period_end_date) BETWEEN 0 AND 90
        THEN 'lapsing_term'
      -- Effective price per unit drifted materially from the published rate card,
      -- which usually means mispriced usage rather than an agreed discount.
      WHEN ABS(COALESCE(rate_card_divergence_pct, 0)) > 0.25
        THEN 'rate_card_divergence'
      ELSE NULL
    END AS exception_reason,
    -- Revenue at risk ranks the queue. For an UNUSED licence the money at risk is the
    -- contracted price (that is what a non-renewal would cost); once there is usage, the
    -- realised revenue is the exposure. Falls back through both so an exception is never
    -- pinned to 0 and cannot be out-ranked purely for lack of one figure.
    COALESCE(
      CASE WHEN COALESCE(consumption_units, 0) = 0 THEN contracted_price_amount END,
      data_revenue_amount,
      contracted_price_amount,
      0
    ) AS revenue_at_risk
  FROM (
    SELECT
      r.*,
      -- Period end date, needed to judge a lapsing term against the period being
      -- reported rather than against today (which would re-flag historical periods
      -- forever). Collapsed from the DAY-grain calendar to period grain.
      sp.period_end_date,
      -- Effective unit price vs the published rate card, only meaningful where the
      -- product is actually priced per consumption unit.
      CASE
        WHEN r.pricing_model = 'per_consumption_unit'
          THEN (r.revenue_per_consumption_unit - r.list_price_amount) / NULLIF(r.list_price_amount, 0)
        ELSE NULL
      END AS rate_card_divergence_pct
    FROM ${catalog}.${dss_schema}.gold_data_product_revenue r
    LEFT JOIN (
      SELECT fiscal_year, fiscal_period, MAX(date_key) AS period_end_date
      FROM ${catalog}.${calendar_schema}.fiscal_calendar
      WHERE fiscal_year IS NOT NULL AND fiscal_period IS NOT NULL
      GROUP BY fiscal_year, fiscal_period
    ) sp
      ON sp.fiscal_year = r.fiscal_year AND sp.fiscal_period = r.fiscal_period
  )
)
SELECT
  principal_id,
  data_product_id,
  data_product_name,
  data_product_category,
  supplier_scope_id,
  supplier_name,
  fiscal_year,
  fiscal_period,
  exception_reason,
  subscription_status,
  term_end_date,
  contracted_units,
  consumption_units,
  contract_utilisation_pct,
  contracted_price_amount,
  data_revenue_amount,
  revenue_per_consumption_unit,
  contract_discount_pct,
  last_usage_date,
  revenue_at_risk,
  currency_code,
  -- Explicit CAST: ROW_NUMBER() is BIGINT in Databricks SQL, but sqlglot's
  -- annotate_types() only resolves it from 30.9.0 up. The cast makes the
  -- generated contract type independent of the sqlglot version.
  CAST(ROW_NUMBER() OVER (PARTITION BY principal_id
                          ORDER BY revenue_at_risk DESC, data_product_id, supplier_scope_id, fiscal_year, fiscal_period) AS BIGINT) AS priority_rank,
  current_timestamp() AS fresh_as_of_ts
FROM flagged
WHERE exception_reason IS NOT NULL;
