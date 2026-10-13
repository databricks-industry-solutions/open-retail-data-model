-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- Metric View: data_product_revenue
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-03
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-03
-- ============================================================
-- Semantic layer over gold_data_product_revenue: the entitled, threshold-suppressed
-- data-monetization P&L a retailer and its supplier partners consume together (data
-- product × supplier scope × fiscal period, no person-level data). Genie / AI-BI ready.
-- Entitlement is applied by the underlying gold view's row filter; this view adds the
-- semantic measure definitions (data revenue, contract utilisation, realised unit
-- price, and data's share of total monetised value).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${dss_schema}.mv_data_product_revenue
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Entitled data-monetization KPIs (licensed data revenue, contract utilisation, realised price per consumption unit, data share of total monetised value) by data product, supplier and fiscal period."
source: >
  SELECT
    principal_id,
    data_product_id,
    data_product_name,
    data_product_category,
    pricing_model,
    supplier_scope_id,
    fiscal_year,
    fiscal_period,
    subscription_status,
    usage_suppressed_flag,
    contracted_price_amount,
    consumption_units,
    data_revenue_amount,
    -- Suppressed rows withhold their revenue but deliberately KEEP their media allocation
    -- (the allocation must stay additive to the advertiser's actual spend). Summing that
    -- media alongside a NULL revenue would understate data's share of monetised value, so
    -- for the semantic layer the media of a suppressed row is withheld too — keeping every
    -- measure below on one consistent, disclosable row population.
    CASE WHEN usage_suppressed_flag THEN NULL ELSE media_spend_net END AS media_spend_net
  FROM ${catalog}.${dss_schema}.gold_data_product_revenue

fields:
  - name: principal_id
    expr: principal_id
    display_name: "Principal ID"
    comment: "Governance principal entitled to the row. gold_data_product_revenue emits one row PER entitled principal, so a deploy-time row filter narrows this to the querying group; if two principals hold a licence covering the same product x supplier x period, aggregating WITHOUT filtering on principal_id would double-count the shared revenue. Always scope by principal (the row filter) before summing."
    synonyms: ["principal", "partner_group", "licensee"]
  - name: data_product_id
    expr: data_product_id
    display_name: "Data Product ID"
    comment: "Durable data-product business key."
    synonyms: ["data_product", "product_licensed"]
  - name: data_product_name
    expr: data_product_name
    display_name: "Data Product"
    comment: "Display name of the licensed data product."
    synonyms: ["product_name", "offering"]
  - name: data_product_category
    expr: data_product_category
    display_name: "Data Product Category"
    comment: "Kind of data product. One of: media_measurement, demand_collaboration, category_benchmark, audience_insight."
    synonyms: ["product_category", "offering_type"]
  - name: pricing_model
    expr: pricing_model
    display_name: "Pricing Model"
    comment: "How the product is charged. One of: subscription_flat, per_consumption_unit, tiered, revenue_share."
    synonyms: ["charge_model", "rate_type"]
  - name: supplier_scope_id
    expr: supplier_scope_id
    display_name: "Supplier Scope"
    comment: "Durable supplier business key the licence is scoped to; NULL for a licence spanning every supplier the product covers."
    synonyms: ["supplier", "vendor"]
  - name: fiscal_year
    expr: fiscal_year
    display_name: "Fiscal Year"
    comment: "NRF 4-5-4 fiscal year."
    synonyms: ["year", "fy"]
  - name: fiscal_period
    expr: fiscal_period
    display_name: "Fiscal Period"
    comment: "NRF fiscal period / retail month (1-12)."
    synonyms: ["period", "retail_month"]
  - name: subscription_status
    expr: subscription_status
    display_name: "Subscription Status"
    comment: "Licence lifecycle at the latest version. One of: active, suspended, expired (pending and cancelled licences are excluded upstream)."
    synonyms: ["licence_status", "contract_status"]

measures:
  - name: data_revenue_amount
    expr: SUM(data_revenue_amount)
    display_name: "Data Revenue"
    comment: "Total revenue billed from metered data-product consumption, reporting/base currency."
    synonyms: ["data_revenue", "licensing_revenue", "monetization_revenue"]
  - name: contracted_price_amount
    expr: SUM(contracted_price_amount)
    display_name: "Contracted Value"
    comment: "Total negotiated contract value for the periods in scope, reporting/base currency."
    synonyms: ["contract_value", "committed_revenue"]
  - name: consumption_units
    expr: SUM(consumption_units)
    display_name: "Consumption (Units)"
    comment: "Total metered consumption in the data product's consumption unit."
    synonyms: ["usage", "metered_units", "consumption"]
  - name: media_spend_net
    expr: SUM(media_spend_net)
    display_name: "Retail Media Spend"
    comment: "Total retail-media net spend by the same advertiser from the Commerce Media Networks package (NULL if absent). Allocated per licence row by revenue share, so it is additive rather than fanning the advertiser total onto every row. The reconciliation GUARANTEE (per-row allocations sum to the advertiser's actual spend) holds at the underlying gold view, which is what dpr_media_allocation_reconciles checks; here the media of rows whose usage was withheld by the disclosure floor is intentionally excluded, so with any suppression present this SUM is strictly LESS than the advertiser's actual spend. That keeps every measure in this view over one consistent, disclosable row population."
    synonyms: ["media_spend", "ad_spend"]
  - name: total_monetised_value
    expr: COALESCE(SUM(data_revenue_amount), 0) + COALESCE(SUM(media_spend_net), 0)
    display_name: "Total Monetised Value"
    comment: "Total value of the supplier relationship = data revenue + retail-media spend, reporting/base currency. BOTH terms are COALESCEd to 0, deliberately and symmetrically: at this aggregate layer an absent component means 'no KNOWN value of that kind', not 'unknown total'. Either can legitimately be NULL over a whole group — only advertiser-scoped licences carry media (so every other data product, and any deployment where Commerce Media Networks is unpopulated, has no media at all), and a paid-but-unused licence has media with no revenue. A bare addition NULLs this headline KPI in both cases even though real value exists. NOTE this DIFFERS from the row-level gold_data_product_revenue.total_monetised_value, which NULL-propagates: per row, 'known total or nothing' is the honest reading, whereas a KPI that vanishes whenever one component is missing is not usable. Use data_revenue_share_pct (still NULL without media) to tell whether the media term contributed, and the two component measures to see the split."
    synonyms: ["total_value", "wallet"]
  - name: realised_price_per_unit
    expr: SUM(data_revenue_amount) / NULLIF(SUM(consumption_units), 0)
    display_name: "Realised Price per Unit"
    comment: "Revenue yield per metered consumption unit = data_revenue_amount / consumption_units. Aggregated as a ratio of sums, so it is a true weighted average across whatever grain is grouped."
    synonyms: ["unit_price", "effective_rate", "yield_per_unit"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
  - name: data_revenue_share_pct
    expr: SUM(data_revenue_amount) / NULLIF(SUM(data_revenue_amount) + SUM(media_spend_net), 0)
    display_name: "Data Share of Monetised Value %"
    comment: "Data revenue as a share of total monetised value = data_revenue_amount / (data_revenue_amount + media_spend_net). NULL when the retail-media signal is absent."
    synonyms: ["data_share", "share_of_wallet"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
$$;
