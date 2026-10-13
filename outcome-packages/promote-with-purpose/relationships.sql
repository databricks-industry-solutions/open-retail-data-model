-- ============================================================
-- ORDM · Outcome Package · Promote with Purpose
-- File: relationships.sql
-- Version: 0.5
-- Generated: 2026-06-09
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-06-09
-- ============================================================
-- Relationships for the promotion structures. UC foreign keys are
-- informational (NOT ENFORCED) and reference the parent surrogate PK.
-- Run AFTER promotion, promotion_scope, product and store exist.
-- ============================================================

-- promotion_scope -> promotion / product / store (surrogate FKs)
ALTER TABLE ${catalog}.${promo_schema}.promotion_scope
  ADD CONSTRAINT fk_scope_promotion
  FOREIGN KEY (promo_sk) REFERENCES ${catalog}.${marketing_schema}.promotion (promo_sk);

ALTER TABLE ${catalog}.${promo_schema}.promotion_scope
  ADD CONSTRAINT fk_scope_product
  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${promo_schema}.promotion_scope
  ADD CONSTRAINT fk_scope_store
  FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

-- ------------------------------------------------------------
-- Logical relationships on non-PK keys (NOT declared as UC FKs):
--   promotion.fiscal_week_start -> fiscal_calendar.fiscal_week_id
--   promotion.fiscal_week_end   -> fiscal_calendar.fiscal_week_id
-- (fiscal_calendar PK is date_sk; fiscal_week_id is a week-level key.)
-- ------------------------------------------------------------

-- ============================================================
-- Location-Based Offers (offer_zone / location_offer / offer_event)
-- Run AFTER offer_zone, location_offer, offer_event exist.
-- ============================================================

-- Declared UC FKs (informational, NOT ENFORCED) on the parent surrogate PK.
ALTER TABLE ${catalog}.${promo_schema}.location_offer
  ADD CONSTRAINT fk_location_offer_zone
  FOREIGN KEY (zone_sk) REFERENCES ${catalog}.${promo_schema}.offer_zone (zone_sk);

ALTER TABLE ${catalog}.${promo_schema}.offer_event
  ADD CONSTRAINT fk_offer_event_location_offer
  FOREIGN KEY (location_offer_sk) REFERENCES ${catalog}.${promo_schema}.location_offer (location_offer_sk);

-- ENFORCED Delta CHECK constraints (enum domains + range rules; complement the
-- post-hoc DQ checks in checks.sql). Added via ALTER TABLE, never inline.
ALTER TABLE ${catalog}.${promo_schema}.offer_zone
  ADD CONSTRAINT chk_offer_zone_zone_type
  CHECK (zone_type IN ('store_radius', 'polygon', 'beacon', 'mall_common_area'));

ALTER TABLE ${catalog}.${promo_schema}.offer_zone
  ADD CONSTRAINT chk_offer_zone_radius
  CHECK (radius_m IS NULL OR radius_m > 0);

ALTER TABLE ${catalog}.${promo_schema}.location_offer
  ADD CONSTRAINT chk_location_offer_trigger_type
  CHECK (trigger_type IN ('geofence_enter', 'geofence_exit', 'dwell', 'beacon_proximity'));

ALTER TABLE ${catalog}.${promo_schema}.location_offer
  ADD CONSTRAINT chk_location_offer_daily_cap
  CHECK (daily_trigger_cap > 0);

ALTER TABLE ${catalog}.${promo_schema}.location_offer
  ADD CONSTRAINT chk_location_offer_suppression_window
  CHECK (suppression_window_hours >= 0);

ALTER TABLE ${catalog}.${promo_schema}.location_offer
  ADD CONSTRAINT chk_location_offer_channel
  CHECK (channel IN ('push', 'sms', 'email', 'in_app'));

ALTER TABLE ${catalog}.${promo_schema}.location_offer
  ADD CONSTRAINT chk_location_offer_window
  CHECK (offer_end_ts > offer_start_ts);

ALTER TABLE ${catalog}.${promo_schema}.location_offer
  ADD CONSTRAINT chk_location_offer_status
  CHECK (status IN ('draft', 'active', 'paused', 'ended'));

ALTER TABLE ${catalog}.${promo_schema}.offer_event
  ADD CONSTRAINT chk_offer_event_event_type
  CHECK (event_type IN ('triggered', 'suppressed', 'delivered', 'opened', 'redeemed'));

ALTER TABLE ${catalog}.${promo_schema}.offer_event
  ADD CONSTRAINT chk_offer_event_suppression_reason
  CHECK (suppression_reason IS NULL
         OR suppression_reason IN ('no_consent', 'daily_cap', 'quiet_hours', 'frequency_window'));

-- ------------------------------------------------------------
-- Logical relationships on business keys (NOT declared as UC FKs — the parent
-- key is a durable business key, not the surrogate PK, so it is documented here
-- rather than declared, per this package's convention):
--   offer_zone.store_id       -> store.store_id            (store, ${store_schema})
--   location_offer.promotion_id -> promotion.promo_id      (marketing, ${marketing_schema})
--   offer_event.customer_id   -> profile.profile_id        (customer, ${customer_schema}; pseudonymous)
--   offer_event.store_id      -> store.store_id            (store, ${store_schema})
--   offer_event.transaction_id -> sales.sales_id           (transaction, ${transaction_schema}; redemption attribution)
-- ------------------------------------------------------------
