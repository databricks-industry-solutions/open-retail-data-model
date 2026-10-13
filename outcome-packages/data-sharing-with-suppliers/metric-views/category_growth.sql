-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- Metric View: category_growth
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-12
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-12
-- ============================================================
-- Semantic layer over gold_category_growth: category revenue, units and margin,
-- the four-way growth decomposition (distribution / volume / price / mix), and
-- period-over-period and year-over-year growth, for joint business planning by
-- category and fiscal period. Genie / AI-BI ready.
--
-- Every measure stays correct when rolled up across categories or periods: the
-- amounts and effects are additive, and both growth rates are recomputed as
-- SUM/SUM. The per-row shares in the gold view (category_share, value_share_*,
-- supplier_top_share) and the top supplier's score are NOT measures here: each is
-- a ratio or attribute of one category x period row whose numerator/denominator
-- the gold view does not expose, so any roll-up of them would be wrong. Read them
-- from gold_category_growth at its own grain.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${dss_schema}.mv_category_growth
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Category revenue, units and margin, the growth decomposition (distribution / volume / price / mix), period-over-period and year-over-year growth, and promotion contribution by category and fiscal period."
source: >
  SELECT
    category,
    fiscal_year,
    fiscal_period,
    category_revenue,
    category_units,
    category_margin,
    prior_period_revenue,
    delta_revenue,
    prior_year_revenue,
    distribution_effect,
    volume_effect,
    price_effect,
    mix_effect,
    promo_contribution
  FROM ${catalog}.${dss_schema}.gold_category_growth

fields:
  - name: category
    expr: category
    display_name: "Category"
    comment: "Product category."
    synonyms: ["product_category", "dept"]
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

measures:
  - name: category_revenue
    expr: SUM(category_revenue)
    display_name: "Category Revenue"
    comment: "Total net revenue by category for the period, reporting/base currency."
    synonyms: ["revenue", "sales"]
  - name: category_units
    expr: SUM(category_units)
    display_name: "Category Units"
    comment: "Total units sold by category for the period."
    synonyms: ["units", "qty"]
  - name: category_margin
    expr: SUM(category_margin)
    display_name: "Category Margin"
    comment: "Total line margin by category for the period (revenue less unit cost), reporting/base currency."
    synonyms: ["margin", "gross_margin"]
  - name: delta_revenue
    expr: SUM(delta_revenue)
    display_name: "Delta Revenue (PoP)"
    comment: "Period-over-period absolute change in category revenue = category_revenue - prior_period_revenue, reporting/base currency."
    synonyms: ["revenue_change", "period_delta"]
  - name: distribution_effect
    expr: SUM(distribution_effect)
    display_name: "Distribution Effect"
    comment: "Revenue change from broader or narrower availability (change in distinct product x store selling points), reporting/base currency."
    synonyms: ["availability_effect"]
  - name: volume_effect
    expr: SUM(volume_effect)
    display_name: "Volume Effect"
    comment: "Revenue change from selling more or fewer units per selling point (holding price and mix constant), reporting/base currency."
    synonyms: ["quantity_effect"]
  - name: price_effect
    expr: SUM(price_effect)
    display_name: "Price Effect"
    comment: "Revenue change from like-for-like price changes within sub-categories, reporting/base currency."
    synonyms: ["pricing_effect"]
  - name: mix_effect
    expr: SUM(mix_effect)
    display_name: "Mix Effect"
    comment: "Revenue change from shifting the sub-category mix toward higher- or lower-priced sub-categories at constant sub-category prices, reporting/base currency."
    synonyms: ["assortment_effect", "subcategory_mix"]
  - name: pop_growth_rate
    expr: SUM(delta_revenue) / NULLIF(SUM(prior_period_revenue), 0)
    display_name: "Growth % (Period-over-Period)"
    comment: "Period-over-period growth = SUM(category_revenue - prior_period_revenue) / SUM(prior_period_revenue), over rows that have a prior period (delta_revenue and prior_period_revenue are both NULL otherwise). Compares like fiscal periods (period_index - 1). Named _rate, not _pct: the gold view's pop_growth_pct is the same ratio x 100 for one category x period."
    synonyms: ["period_growth", "pop_growth"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2
  - name: yoy_growth_rate
    expr: (SUM(CASE WHEN prior_year_revenue IS NOT NULL THEN category_revenue END) - SUM(prior_year_revenue)) / NULLIF(SUM(prior_year_revenue), 0)
    display_name: "Growth % (Year-over-Year)"
    comment: "Year-over-year growth = (SUM(category_revenue) - SUM(prior_year_revenue)) / SUM(prior_year_revenue), both over rows that have a prior year, comparing like fiscal periods (period_index - 12). NULL when no row has a prior year. Named _rate, not _pct: the gold view's yoy_growth_pct is the same ratio x 100 for one category x period."
    synonyms: ["annual_growth", "yoy_growth"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 2
  - name: promo_contribution
    expr: SUM(promo_contribution)
    display_name: "Promo Contribution (Margin)"
    comment: "Incremental margin from promotions in this category for the period (from gold_promo_roi_by_category), reporting/base currency. NULL if the promo view is absent."
    synonyms: ["promotional_lift", "promo_margin"]
$$;
