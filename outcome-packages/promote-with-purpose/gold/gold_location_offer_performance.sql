-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- View: gold_location_offer_performance
-- Layer: outcome package (gold / consumable, materialized)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- Weekly performance of each location-based offer, per store. Grain is
-- location_offer_sk x store_id x fiscal_week_id (the three grain columns are the
-- documented PRIMARY KEY — this package sets the grain-documentation pattern).
-- Funnel counts, delivery/open/redemption/suppression rates (bounded 0..1), and
-- redemption-attributed sales (sum of transaction net_revenue on redeemed events,
-- joined via offer_event.transaction_id). Fiscal week from the NRF 4-5-4 calendar.
-- Materialized as a TABLE (not a VIEW) so the grain PK is declared and surfaced.
--
-- Shipped as TWO statements — a CREATE TABLE carrying the column spec and the
-- grain PK, then an INSERT OVERWRITE that loads it. A CTAS cannot carry a
-- column list or a CONSTRAINT ("Constraints may not be specified in a Create
-- Table As Select"), so declaring the grain PK requires the split. The grain
-- columns are NOT NULL because a Databricks PRIMARY KEY requires it.
-- INSERT OVERWRITE (not INSERT INTO) keeps re-application idempotent.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${promo_schema}.gold_location_offer_performance (
  location_offer_sk        BIGINT NOT NULL COMMENT 'Offer surrogate (FK to location_offer.location_offer_sk); part of the grain PK.',
  store_id                 STRING NOT NULL COMMENT 'Store business key; part of the grain PK.',
  fiscal_week_id           INT    NOT NULL COMMENT 'NRF 4-5-4 fiscal week; part of the grain PK.',
  trigger_events           BIGINT COMMENT 'Count of triggered events.',
  suppressed_events        BIGINT COMMENT 'Count of suppressed events.',
  delivered_events         BIGINT COMMENT 'Count of delivered events.',
  opened_events            BIGINT COMMENT 'Count of opened events.',
  redemptions              BIGINT COMMENT 'Count of redeemed events.',
  unique_customers_reached BIGINT COMMENT 'Distinct pseudonymous customers with a delivered event.',
  delivery_rate            DECIMAL(9,4) COMMENT 'delivered / (delivered + suppressed); bounded 0..1.',
  open_rate                DECIMAL(9,4) COMMENT 'opened / delivered; bounded 0..1.',
  redemption_rate          DECIMAL(9,4) COMMENT 'redemptions / delivered; bounded 0..1.',
  suppression_rate         DECIMAL(9,4) COMMENT 'suppressed / (delivered + suppressed); bounded 0..1.',
  attributed_sales_amount  DECIMAL(18,2) COMMENT 'Sum of transaction net_revenue attributed to redeemed events (base currency).',
  CONSTRAINT pk_gold_location_offer_performance
    PRIMARY KEY (location_offer_sk, store_id, fiscal_week_id)
)
USING DELTA;

INSERT OVERWRITE ${catalog}.${promo_schema}.gold_location_offer_performance
WITH offer_week AS (
  -- Offer events tagged with their fiscal week (event date -> NRF 4-5-4 week).
  SELECT
    e.location_offer_sk,
    e.store_id,
    c.fiscal_week_id,
    e.event_type,
    e.customer_id,
    e.transaction_id
  FROM ${catalog}.${promo_schema}.offer_event e
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar c
    ON CAST(e.event_ts AS DATE) = c.date_key
),
agg AS (
  SELECT
    location_offer_sk,
    store_id,
    fiscal_week_id,
    COUNT_IF(event_type = 'triggered')  AS trigger_events,
    COUNT_IF(event_type = 'suppressed') AS suppressed_events,
    COUNT_IF(event_type = 'delivered')  AS delivered_events,
    COUNT_IF(event_type = 'opened')     AS opened_events,
    COUNT_IF(event_type = 'redeemed')   AS redemptions,
    COUNT(DISTINCT CASE WHEN event_type = 'delivered' THEN customer_id END) AS unique_customers_reached
  FROM offer_week
  GROUP BY location_offer_sk, store_id, fiscal_week_id
),
attributed AS (
  -- Redemption-attributed sales: redeemed events matched to their transaction.
  SELECT
    ow.location_offer_sk,
    ow.store_id,
    ow.fiscal_week_id,
    SUM(s.net_revenue) AS attributed_sales_amount
  FROM offer_week ow
  JOIN ${catalog}.${transaction_schema}.sales s
    ON ow.transaction_id = s.sales_id
  WHERE ow.event_type = 'redeemed'
  GROUP BY ow.location_offer_sk, ow.store_id, ow.fiscal_week_id
)
SELECT
  g.location_offer_sk,
  g.store_id,
  g.fiscal_week_id,
  g.trigger_events,
  g.suppressed_events,
  g.delivered_events,
  g.opened_events,
  g.redemptions,
  g.unique_customers_reached,
  CAST(g.delivered_events / NULLIF(g.delivered_events + g.suppressed_events, 0) AS DECIMAL(9,4)) AS delivery_rate,
  CAST(g.opened_events     / NULLIF(g.delivered_events, 0)                      AS DECIMAL(9,4)) AS open_rate,
  CAST(g.redemptions       / NULLIF(g.delivered_events, 0)                      AS DECIMAL(9,4)) AS redemption_rate,
  CAST(g.suppressed_events / NULLIF(g.delivered_events + g.suppressed_events, 0) AS DECIMAL(9,4)) AS suppression_rate,
  CAST(COALESCE(a.attributed_sales_amount, 0) AS DECIMAL(18,2)) AS attributed_sales_amount
FROM agg g
LEFT JOIN attributed a
  ON  a.location_offer_sk = g.location_offer_sk
  AND a.store_id          = g.store_id
  AND a.fiscal_week_id    = g.fiscal_week_id;
