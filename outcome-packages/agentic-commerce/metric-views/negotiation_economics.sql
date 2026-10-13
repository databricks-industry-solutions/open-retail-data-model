-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce
-- Metric View: negotiation_economics
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-02 by @shubhamp051991
-- ============================================================
-- Negotiation economics per completed A2A session: agreed value, price
-- concession from first offer to accepted price, and agreed quantity.
-- Grained at session level via gold_a2a_session_summary (completed sessions
-- with an accepted price). Aggregatable by channel, product, and date.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ac_schema}.mv_negotiation_economics
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Agent-to-agent negotiation economics: agreed value, price concession, and quantity for sessions that reached an accepted price."
source: >
  SELECT
    s.a2a_session_id,
    s.communication_channel,
    s.product_id,
    CAST(s.initiated_timestamp AS DATE) AS session_date,
    s.first_offer_price,
    s.agreed_price,
    s.agreed_quantity,
    s.agreed_currency_code,
    s.price_concession_pct,
    -- Quantity defaults to 1 when the acceptance carried a price but no
    -- proposed_quantity (both nullable at source): a priced deal is at least one
    -- unit, so total_agreed_value must not silently drop it via NULL arithmetic.
    s.agreed_price * COALESCE(s.agreed_quantity, 1) AS agreed_value
  FROM ${catalog}.${ac_schema}.gold_a2a_session_summary s
  WHERE s.agreed_price IS NOT NULL

fields:
  - name: a2a_session_id
    expr: a2a_session_id
    display_name: "Session ID"
    comment: "Durable business key for the agent-to-agent session."
    synonyms: ["session", "negotiation_id"]

  - name: communication_channel
    expr: communication_channel
    display_name: "Channel"
    comment: "Communication channel between the agents: api, marketplace, direct, voice."
    synonyms: ["channel", "medium"]

  - name: product_id
    expr: product_id
    display_name: "Product ID"
    comment: "Durable business key for the agreed product."
    synonyms: ["SKU", "item_id", "product"]

  - name: agreed_currency_code
    expr: agreed_currency_code
    display_name: "Currency"
    comment: "ISO 4217 reporting currency of the agreed price."
    synonyms: ["currency", "ccy"]

  - name: session_date
    expr: session_date
    display_name: "Session Date"
    comment: "Calendar date the session started."
    synonyms: ["date", "day"]
    format:
      type: date
      date_format: year_month_day

measures:
  - name: agreed_session_count
    expr: COUNT(*)
    display_name: "Agreed Sessions"
    comment: "Number of sessions that reached an accepted price."
    synonyms: ["deals", "closed_negotiations"]

  - name: total_agreed_value
    expr: SUM(agreed_value)
    display_name: "Total Agreed Value"
    comment: "Sum of agreed price times agreed quantity, in the reporting currency."
    synonyms: ["gmv", "total_value", "negotiated_value"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: avg_agreed_price
    expr: AVG(agreed_price)
    display_name: "Avg Agreed Price"
    comment: "Average accepted unit price across sessions."
    synonyms: ["mean_price", "average_deal_price"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: avg_price_concession
    expr: AVG(price_concession_pct)
    display_name: "Avg Price Concession"
    comment: "Average reduction from the seller's opening offer to the accepted price, as a fraction. Higher = the seller gave more ground from its opening quote."
    synonyms: ["avg_discount", "concession_rate", "negotiation_savings"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: total_agreed_quantity
    expr: SUM(agreed_quantity)
    display_name: "Total Agreed Quantity"
    comment: "Sum of agreed quantity across sessions."
    synonyms: ["units", "total_units", "quantity"]
$$;
