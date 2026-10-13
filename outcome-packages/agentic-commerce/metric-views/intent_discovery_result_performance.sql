-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Metric View: intent_discovery_result_performance
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-12
-- LLM-generated: false (maintainer-reviewed)
-- Last reviewed: 2026-10-12
-- ============================================================
-- Result-level performance metrics for Intent Product Discovery:
-- engagement funnel (CTR, add-to-cart rate, conversion rate) and revenue
-- metrics by discovery channel, intent category, product attributes, and
-- personalization status. Every result from gold_intent_product_discovery_performance
-- is a completed discovery interaction with known engagement outcomes.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.mv_intent_discovery_result_performance
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Intent Product Discovery result-level performance: engagement funnel (CTR, add-to-cart rate, conversion rate) by channel, category, and personalization."
source: >
  SELECT
    discovery_channel,
    intent_category,
    brand,
    category,
    result_rank,
    is_available_flag,
    personalization_eligible_flag,
    known_customer_flag,
    viewed_flag,
    selected_flag,
    added_to_cart_flag,
    purchased_flag,
    purchased_units,
    purchase_net_amount
  FROM ${catalog}.${ac_schema}.gold_intent_product_discovery_performance

fields:
  - name: discovery_channel
    expr: discovery_channel
    display_name: "Discovery Channel"
    comment: "Channel through which the discovery occurred (web, mobile, kiosk, voice, associate, api)."
    synonyms: ["channel"]

  - name: intent_category
    expr: intent_category
    display_name: "Intent Category"
    comment: "Normalized product category or need category from the shopper's intent."
    synonyms: ["need_category", "search_category", "intent_type"]

  - name: brand
    expr: brand
    display_name: "Brand"
    comment: "Product brand."
    synonyms: ["product_brand", "manufacturer_brand"]

  - name: category
    expr: category
    display_name: "Category"
    comment: "Product category."
    synonyms: ["product_category", "merchandise_category"]

  - name: result_rank
    expr: result_rank
    display_name: "Result Rank"
    comment: "Position of result in ranked list for this intent (1-based)."
    synonyms: ["rank", "position"]

  - name: is_available_flag
    expr: is_available_flag
    display_name: "Available"
    comment: "Whether product was available at store/time of discovery."
    synonyms: ["available", "in_stock"]

  - name: personalization_eligible_flag
    expr: personalization_eligible_flag
    display_name: "Personalization Eligible"
    comment: "Whether personalization was eligible for this discovery."
    synonyms: ["personalization_eligible"]

  - name: known_customer_flag
    expr: known_customer_flag
    display_name: "Known Customer"
    comment: "Whether shopper was a known/logged-in customer."
    synonyms: ["logged_in", "identified"]

measures:
  - name: result_count
    expr: COUNT(*)
    display_name: "Result Count"
    comment: "Total returned results."
    synonyms: ["num_results", "results", "returned_results"]

  - name: viewed_count
    expr: SUM(CAST(viewed_flag AS INT))
    display_name: "Viewed Results"
    comment: "Results with at least one view engagement."
    synonyms: ["views", "viewed"]

  - name: result_ctr
    expr: SUM(CAST(selected_flag AS INT)) / NULLIF(COUNT(*), 0)
    display_name: "Result CTR"
    comment: "Selected results divided by returned results. A selected result has at least one select engagement event."
    synonyms: ["ctr", "click_through_rate", "selection_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: add_to_cart_rate
    expr: SUM(CAST(added_to_cart_flag AS INT)) / NULLIF(COUNT(*), 0)
    display_name: "Add-to-Cart Rate"
    comment: "Results with an add_to_cart engagement divided by returned results."
    synonyms: ["atc_rate", "cart_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: discovery_conversion_rate
    expr: SUM(CAST(purchased_flag AS INT)) / NULLIF(COUNT(*), 0)
    display_name: "Discovery Conversion Rate"
    comment: "Results with a purchase engagement divided by returned results."
    synonyms: ["discovery_purchase_rate", "result_conversion_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: purchased_units
    expr: SUM(purchased_units)
    display_name: "Purchased Units"
    comment: "Total units purchased from results, attributed once per order line."
    synonyms: ["discovery_purchased_units"]

  - name: purchase_net_amount
    expr: SUM(purchase_net_amount)
    display_name: "Purchase Net Amount"
    comment: "Total net amount from purchases attributed to results, reporting/base currency."
    synonyms: ["revenue", "sales"]

$$;
