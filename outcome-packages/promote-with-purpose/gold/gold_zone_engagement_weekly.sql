-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- View: gold_zone_engagement_weekly
-- Layer: outcome package (gold / consumable, materialized)
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- Weekly engagement per location zone. Grain is zone_id x fiscal_week_id (the two
-- grain columns are the documented PRIMARY KEY). NOTE: keyed on the DURABLE
-- zone_id, not the SCD2 version-specific zone_sk — the standard's SCD2-JOIN
-- contract (§A.16) forbids aggregating on a version-specific _sk, so the zone is
-- resolved by an equi-join on offer_zone's version-specific PK zone_sk and then
-- rolled up to the durable zone_id. Materialized as a TABLE so the grain PK is
-- declared and surfaced. Fiscal week from the NRF 4-5-4 calendar.
--
-- Shipped as TWO statements — a CREATE TABLE carrying the column spec and the
-- grain PK, then an INSERT OVERWRITE that loads it. A CTAS cannot carry a
-- column list or a CONSTRAINT ("Constraints may not be specified in a Create
-- Table As Select"), so declaring the grain PK requires the split. The grain
-- columns are NOT NULL because a Databricks PRIMARY KEY requires it.
-- INSERT OVERWRITE (not INSERT INTO) keeps re-application idempotent.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${promo_schema}.gold_zone_engagement_weekly (
  zone_id          STRING NOT NULL COMMENT 'Durable zone business key; part of the grain PK.',
  fiscal_week_id   INT    NOT NULL COMMENT 'NRF 4-5-4 fiscal week; part of the grain PK.',
  active_offers    BIGINT COMMENT 'Distinct active location offers with events in this zone-week.',
  trigger_events   BIGINT COMMENT 'Count of triggered events in this zone-week.',
  unique_customers BIGINT COMMENT 'Distinct pseudonymous customers engaged in this zone-week.',
  conversion_rate  DECIMAL(9,4) COMMENT 'redemptions / triggers; NULL-safe; bounded 0..1.',
  CONSTRAINT pk_gold_zone_engagement_weekly
    PRIMARY KEY (zone_id, fiscal_week_id)
)
USING DELTA;

INSERT OVERWRITE ${catalog}.${promo_schema}.gold_zone_engagement_weekly
WITH zone_week AS (
  -- Events resolved to their zone (via the offer) and fiscal week. offer_zone is
  -- joined on its version-specific PK zone_sk (the correct SCD2 as-of equi-join),
  -- then rolled up to the durable zone_id below.
  SELECT
    z.zone_id,
    c.fiscal_week_id,
    lo.location_offer_sk,
    lo.status,
    e.event_type,
    e.customer_id
  FROM ${catalog}.${promo_schema}.offer_event e
  JOIN ${catalog}.${promo_schema}.location_offer lo
    ON e.location_offer_sk = lo.location_offer_sk
  JOIN ${catalog}.${promo_schema}.offer_zone z
    ON lo.zone_sk = z.zone_sk
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar c
    ON CAST(e.event_ts AS DATE) = c.date_key
)
SELECT
  zone_id,
  fiscal_week_id,
  COUNT(DISTINCT CASE WHEN status = 'active' THEN location_offer_sk END) AS active_offers,
  COUNT_IF(event_type = 'triggered')                                     AS trigger_events,
  COUNT(DISTINCT customer_id)                                            AS unique_customers,
  CAST(COUNT_IF(event_type = 'redeemed') / NULLIF(COUNT_IF(event_type = 'triggered'), 0) AS DECIMAL(9,4)) AS conversion_rate
FROM zone_week
GROUP BY zone_id, fiscal_week_id;
