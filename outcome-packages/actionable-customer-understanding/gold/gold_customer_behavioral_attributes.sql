-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- View: gold_customer_behavioral_attributes   (MATERIALIZED VIEW)
-- Layer: outcome package (gold / consumable)
-- Materialization: Lakeflow Declarative Pipeline materialized view, refreshed on
--   the fiscal-period cadence (same cadence as gold_customer_ltv, which it reads).
-- Version: 0.5
-- Generated: 2026-07-23
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-23
-- ============================================================
-- The wide, agent-discoverable customer TRAIT surface for behavioral segmentation
-- (the "parent model" a warehouse-native / composable CDP activation platform reads
-- to compose custom audiences). ONE CURRENT ROW PER CUSTOMER, keyed on the durable
-- `profile_id` — a single stable join key so a downstream activation platform (and
-- reverse-ETL CDC) diffs on one column, never a multi-column predicate.
--
-- GRAIN CAVEAT (M1): the row set is PURCHASER-grained, not all-customers. Traits are
-- derived from customer_order_line via an inner join, so a segment member with zero
-- order lines has NO row here. This is intentional for v1 (every behavioral trait is an
-- observed-purchase signal, undefined without orders) and is safe because activation
-- never reads this surface to decide membership — the activatable audience is built in
-- UCV's gold_activatable_audience_current, which keys on the full customer/consent set,
-- not on this trait table. If a future use case needs a trait row for non-purchasers,
-- switch the base join to a LEFT join from the customer/profile set (NULL traits).
--
-- This is the BEHAVIORAL axis, distinct from (and building on) value/RFM: it surfaces
-- gold_customer_ltv's RFM scores + value tier as ATTRIBUTES (does not recompute them),
-- and adds observed-behavior signals derived from customer_order_line: purchase cadence,
-- category/brand affinity, promo responsiveness, and a derived lifecycle stage.
-- Predictive/heuristic scores (churn_risk_proxy) are surfaced as attributes too.
-- Channel mix + engagement/intent traits are now surfaced from the conformed
-- interaction.touchpoint fact (ADR 0029): digital/in-store/call-center interaction shares,
-- session/dwell cadence, search-intent and cart-abandonment flags. (These are NULL for a
-- purchaser with no stitched touches; a follow-on can widen the profile universe to include
-- browsers with zero orders so non-purchasers also get a row.)
--
-- Every trait is an individually-named, typed, commented column (see comments.sql) so a
-- Genie/AI-BI agent can enumerate and compose them — never an opaque map/JSON blob.
--
-- CONSENT PLANE: opt_in_status is surfaced here as a discoverable ATTRIBUTE only (the
-- downstream platform expects consent as an attribute). It is NOT the legal source of
-- truth (that is canonical-core consent) and NEVER gates membership here — the net
-- consent+preference+reachability gate is applied only in UCV's
-- gold_activatable_audience_current (three planes stay separate; targeting never
-- overrides consent). Behavioral membership is computed over ALL customers regardless
-- of consent (no profiling-consent exclusion in v1 — a deliberate simplification).
--
-- B2B: the customer grain is the durable `profile_id`. account_id / account_type /
-- parent_account_id are surfaced as first-class attributes so B2B segments (and account
-- roll-ups) are expressible without a separate rollup table. CAVEAT (m1): the account is
-- resolved via account.primary_contact_profile_id, so only the account's PRIMARY CONTACT
-- carries account_* today; non-primary member profiles get NULL. A full account-membership
-- roll-up (all contacts of an account) needs a contact→account membership resolution and is
-- a follow-up.
--
-- No raw PII (names, loyalty_id, household_id, contact strings) — keyed on the
-- pseudonymous profile_id, mirroring gold_customer_ltv.
-- ============================================================

CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${acu_schema}.gold_customer_behavioral_attributes AS
WITH ord AS (
  SELECT
    col.profile_id,
    col.order_id,
    col.product_sk,
    col.order_date,
    col.units,
    col.net_amount,
    col.gross_amount,
    -- discounted line proxy: net below gross = bought on a discount/promotion. ORDM has
    -- no direct order->promotion link yet, so the gross/net gap is the available signal.
    CASE WHEN col.net_amount < col.gross_amount THEN 1 ELSE 0 END AS is_discounted_line,
    p.category,
    p.brand,
    (c.fiscal_year * 12 + c.fiscal_period) AS period_index
  FROM ${catalog}.${order_schema}.customer_order_line col
  JOIN ${catalog}.${product_schema}.product p ON p.product_sk = col.product_sk
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON col.order_date = c.date_key
),
obs AS (
  SELECT MAX(period_index) AS cur_period FROM ord
),
per_cust AS (
  SELECT
    o.profile_id,
    COUNT(DISTINCT o.order_id)                                   AS frequency,
    SUM(o.net_amount)                                            AS total_spend,
    SUM(o.units)                                                 AS total_units,
    MAX(o.period_index)                                          AS last_period,
    MIN(o.period_index)                                          AS first_period,
    MAX(o.order_date)                                            AS last_order_date,
    COUNT(DISTINCT o.category)                                   AS distinct_categories,
    COUNT(DISTINCT o.brand)                                      AS distinct_brands,
    -- promo responsiveness: share of spend on discounted lines (0..1).
    SUM(CASE WHEN o.is_discounted_line = 1 THEN o.net_amount ELSE 0 END)
      / NULLIF(SUM(o.net_amount), 0)                             AS promo_purchase_share_ratio
  FROM ord o
  GROUP BY o.profile_id
),
-- top category / brand by net spend (the customer's dominant affinity), one each.
cat_rank AS (
  SELECT profile_id, category,
         ROW_NUMBER() OVER (PARTITION BY profile_id ORDER BY SUM(net_amount) DESC, category) AS rn
  FROM ord GROUP BY profile_id, category
),
brand_rank AS (
  SELECT profile_id, brand,
         ROW_NUMBER() OVER (PARTITION BY profile_id ORDER BY SUM(net_amount) DESC, brand) AS rn
  FROM ord GROUP BY profile_id, brand
),
behavioral AS (
  SELECT
    pc.profile_id,
    pc.frequency,
    pc.total_units,
    pc.total_spend,
    pc.last_order_date,
    pc.distinct_categories,
    pc.distinct_brands,
    CAST(pc.promo_purchase_share_ratio AS DECIMAL(6,4))    AS promo_purchase_share_ratio,
    cr.category                                          AS top_category,
    br.brand                                             AS top_brand,
    (ob.cur_period - pc.last_period)                     AS recency_periods,
    (ob.cur_period - pc.first_period + 1)                AS tenure_periods,
    pc.frequency / NULLIF(ob.cur_period - pc.first_period + 1, 0) AS frequency_per_period,
    -- average cadence = periods of tenure per order (a customer's own normal gap).
    (ob.cur_period - pc.first_period + 1) / NULLIF(pc.frequency, 0) AS avg_cadence_periods,
    -- lifecycle stage: derived from recency vs the customer's own cadence + tenure.
    -- new: only one period of history; churned: recency > 2x cadence AND > 3 periods;
    -- lapsing: recency > 1x cadence; else active. (Reactivated needs prior-stage history
    -- — a stateful transition deferred to the interaction-fact follow-on.)
    CASE
      WHEN (ob.cur_period - pc.first_period) = 0 THEN 'new'
      WHEN (ob.cur_period - pc.last_period) > 2 * ((ob.cur_period - pc.first_period + 1) / NULLIF(pc.frequency, 0))
           AND (ob.cur_period - pc.last_period) > 3 THEN 'churned'
      WHEN (ob.cur_period - pc.last_period) > ((ob.cur_period - pc.first_period + 1) / NULLIF(pc.frequency, 0)) THEN 'lapsing'
      ELSE 'active'
    END AS lifecycle_stage
  FROM per_cust pc
  CROSS JOIN obs ob
  LEFT JOIN cat_rank   cr ON cr.profile_id = pc.profile_id AND cr.rn = 1
  LEFT JOIN brand_rank br ON br.profile_id = pc.profile_id AND br.rn = 1
),
-- consent opt-in as a discoverable ATTRIBUTE (net over the four marketing_* consents:
-- opted_in only if at least one marketing consent is granted; opted_out if any explicit
-- withdrawal and none granted; unknown otherwise). NOT the legal gate.
consent_attr AS (
  -- Deliberately collapses multi-jurisdiction consent to ONE value per profile
  -- (MAX across jurisdictions = opted_in if granted anywhere). This is only the
  -- discoverable ATTRIBUTE; the legal gate (UCV gold_activatable_audience_current)
  -- keeps jurisdiction in its grain and is where per-jurisdiction consent is honored.
  SELECT profile_id,
         CASE
           WHEN MAX(CASE WHEN consent_status = 'granted'   THEN 1 ELSE 0 END) = 1 THEN 'opted_in'
           WHEN MAX(CASE WHEN consent_status = 'withdrawn' THEN 1 ELSE 0 END) = 1 THEN 'opted_out'
           ELSE 'unknown'
         END AS opt_in_status
  FROM ${catalog}.${customer_schema}.consent
  WHERE is_current = TRUE
    AND consent_type IN ('marketing_email', 'marketing_sms', 'marketing_phone', 'marketing_postal')
  GROUP BY profile_id
),
-- B2B: resolve the current account this profile is the primary contact for (first-class
-- account attributes so account segments / roll-ups need no separate table).
acct AS (
  SELECT primary_contact_profile_id AS profile_id, account_id, account_type, parent_account_id,
         ROW_NUMBER() OVER (PARTITION BY primary_contact_profile_id ORDER BY effective_from_date DESC) AS rn
  FROM ${catalog}.${customer_schema}.account
  WHERE is_current = TRUE AND primary_contact_profile_id IS NOT NULL
),
-- Clickstream / interaction traits from the conformed interaction.touchpoint fact (ADR 0029).
-- This unblocks the channel-mix + engagement signals the header notes were awaiting "an
-- interaction fact". These traits are AVAILABLE FOR purchasers who also have stitched touches
-- (this CTE LEFT-joins onto the purchaser-grained base below, so a stitched NON-purchaser still
-- gets no row — widening the base to browsers with zero orders is the named header follow-on).
-- Only stitched (profile_id NOT NULL) touches contribute — anonymous pre-stitch touches carry
-- no durable customer key.
-- GRAIN CAVEAT (M1): these clickstream traits are LIFETIME-grained (ALL of a profile's stitched
-- touches, unbounded) — deliberately NOT the fiscal observation window the RFM/behavioral traits
-- in the same row use. So a customer whose last touch was years ago reads the same channel mix as
-- a currently-active one; consumers wanting recency must read last_interaction_date alongside.
-- Labeled "LIFETIME grain" in comments.sql/glossary. Bounding these to the RFM window is a
-- deferred follow-on (a deliberate semantic change, not made here).
clickstream AS (
  SELECT
    profile_id,
    -- Engagement touches only: exclude session bookkeeping (session_start/session_end, app_open)
    -- so interaction_count reflects meaningful engagement, not lifecycle markers.
    COUNT(CASE WHEN interaction_type NOT IN ('session_start', 'session_end', 'app_open')
               THEN 1 END)                                          AS interaction_count,
    COUNT(DISTINCT session_id)                                        AS session_count,
    MAX(event_date)                                                   AS last_interaction_date,
    -- dwell over DIGITAL engagement touches only. touchpoint.dwell_seconds is cross-modal
    -- (page dwell vs call duration vs store-visit length are not comparable units — see the
    -- column comment), so this trait restricts to the digital plane (web/mobile_app) and
    -- excludes session bookkeeping, giving one comparable page-dwell measure rather than a
    -- meaningless blend. (A per-modality dwell breakout is a future trait if needed.)
    AVG(CASE WHEN channel_code IN ('web', 'mobile_app')
              AND interaction_type NOT IN ('session_start', 'session_end', 'app_open')
             THEN dwell_seconds END)                                  AS avg_digital_dwell_seconds,
    -- channel mix: the share of interactions per plane (the trait the header says is missing).
    AVG(CASE WHEN channel_code IN ('web', 'mobile_app') THEN 1.0 ELSE 0.0 END) AS digital_interaction_share,
    AVG(CASE WHEN channel_code IN ('in_store', 'kiosk') THEN 1.0 ELSE 0.0 END) AS in_store_interaction_share,
    AVG(CASE WHEN channel_code = 'call_center' THEN 1.0 ELSE 0.0 END)          AS call_center_interaction_share,
    -- intent / funnel signals
    MAX(CASE WHEN interaction_type = 'search' THEN 1 ELSE 0 END)      AS has_search_intent_flag,
    MAX(CASE WHEN interaction_type = 'add_to_cart' THEN 1 ELSE 0 END) AS has_cart_activity_flag,
    -- cart-abandonment: added to cart but never reached checkout_start.
    (MAX(CASE WHEN interaction_type = 'add_to_cart' THEN 1 ELSE 0 END) = 1
       AND MAX(CASE WHEN interaction_type = 'checkout_start' THEN 1 ELSE 0 END) = 0) AS cart_without_checkout_flag
  FROM ${catalog}.${interaction_schema}.touchpoint
  WHERE profile_id IS NOT NULL
  GROUP BY profile_id
)
SELECT
  b.profile_id,
  -- observed behavioral traits
  b.recency_periods,
  b.frequency,
  b.frequency_per_period,
  b.total_units,
  b.total_spend,
  b.last_order_date,
  b.tenure_periods,
  b.avg_cadence_periods,
  b.distinct_categories,
  b.distinct_brands,
  b.top_category,
  b.top_brand,
  b.promo_purchase_share_ratio,
  b.lifecycle_stage,
  -- value/RFM axis, surfaced from gold_customer_ltv as ATTRIBUTES (not recomputed here)
  ltv.r_score,
  ltv.f_score,
  ltv.m_score,
  ltv.rfm_score,
  ltv.value_tier,
  ltv.historical_clv,
  ltv.predicted_clv,
  ltv.churn_risk_proxy,
  -- consent attribute (discoverable; NOT the gate)
  COALESCE(ca.opt_in_status, 'unknown') AS opt_in_status,
  -- clickstream / interaction traits (ADR 0029) — channel mix + engagement + intent, from
  -- the conformed interaction.touchpoint fact. NULL for a purchaser with no stitched touches.
  cs.interaction_count,
  cs.session_count,
  cs.last_interaction_date,
  cs.avg_digital_dwell_seconds,
  cs.digital_interaction_share,
  cs.in_store_interaction_share,
  cs.call_center_interaction_share,
  COALESCE(cs.has_search_intent_flag, 0)  AS has_search_intent_flag,
  COALESCE(cs.has_cart_activity_flag, 0)  AS has_cart_activity_flag,
  COALESCE(cs.cart_without_checkout_flag, FALSE) AS cart_without_checkout_flag,
  -- B2B account attributes (first-class)
  a.account_id,
  a.account_type,
  a.parent_account_id,
  current_timestamp() AS computed_ts
FROM behavioral b
-- M2 fix: gold_customer_ltv groups by (profile_sk, profile_id), and profile_sk is the
-- SCD2 version-specific surrogate — so a customer versioned mid-history with orders under
-- more than one profile_sk yields >1 ltv row per durable profile_id. Joining that directly
-- would fan out this one-row-per-customer surface. Collapse ltv to ONE row per profile_id
-- first (latest version by profile_sk) so the join is strictly 1:1, robust under real SCD2
-- (invisible in synthetic data, which sources profiles_current — a latent deploy bug).
LEFT JOIN (
  SELECT * EXCEPT (rn) FROM (
    SELECT l.*, ROW_NUMBER() OVER (PARTITION BY l.profile_id ORDER BY l.profile_sk DESC) AS rn
    FROM ${catalog}.${acu_schema}.gold_customer_ltv l
  ) WHERE rn = 1
) ltv ON ltv.profile_id = b.profile_id
LEFT JOIN consent_attr ca ON ca.profile_id = b.profile_id
LEFT JOIN acct a ON a.profile_id = b.profile_id AND a.rn = 1
-- clickstream is grouped one-row-per-profile_id, so this join is strictly 1:1 (no fan-out).
LEFT JOIN clickstream cs ON cs.profile_id = b.profile_id;
