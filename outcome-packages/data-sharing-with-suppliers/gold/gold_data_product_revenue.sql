-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- View: gold_data_product_revenue
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Apply a deploy-time row filter on
--   principal_id (= the querying group) so each partner sees only entitled rows.
-- Version: 0.5
-- Generated: 2026-08-03
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-03
-- ============================================================
-- The ENTITLED data-monetization P&L: per principal × data product × supplier scope ×
-- fiscal period, the licensed commercial terms, the metered consumption, the revenue it
-- billed, and the yield of that revenue against both the contract and the partner's
-- retail-media spend. This is the row-filter source for partner-facing revenue
-- reporting; pairs with gold_data_monetization_exceptions (the ranked attention queue).
--
-- Cross-package enrichment (NULL-safe, no FK): LEFT JOIN the Commerce Media Networks
-- package's gold_campaign_performance to add the same advertiser's retail-media spend
-- for the period, so a supplier relationship can be reported as TOTAL monetised value
-- (licensed data + media) and as data's share of it. Degrades gracefully by DATA, not by
-- object existence: if that view exists but is EMPTY (cmn schema deployed, not yet
-- populated), the LEFT JOIN NULLs the media columns and every revenue row is still
-- returned — the same pattern as gold_joint_demand_plan and gold_category_growth. The
-- referenced view must still EXIST for this view to compile (a genuinely absent object
-- fails at analysis time, like any SQL view dependency), so deploy the cmn schema's gold
-- layer alongside this package. This introduces no new coupling CLASS: the package
-- already declares informational FKs into commerce-media-networks (ADR 0019, amended by
-- ADR 0021), and no FK / no row-level deploy-order coupling is added here.
--
-- CURRENCY ASSUMPTION on that fusion. total_monetised_value and data_revenue_share_pct add
-- this package's data revenue to CMN's media_spend_net, so they assume BOTH sides are
-- denominated in the one model-wide reporting currency. Within this package that is
-- ENFORCED (dm_cross_table_single_currency spans all three monetization tables); across the
-- dss<->cmn boundary it currently rests on the convention alone, because
-- gold_campaign_performance does not surface a currency_code to compare against — its
-- source campaign_day carries one (guarded by acd_single_currency) but the gold view does
-- not project it. A symmetric cross-package check is therefore not writable today; closing
-- it needs CMN's gold layer to expose currency first, which is that package's call to make,
-- not a change to bury in this use case. Under a genuinely multi-currency deployment these
-- two derived columns would be meaningless — the same defect class
-- dm_cross_table_single_currency exists to catch, one boundary over.
--
-- Low-volume usage is suppressed by NULLing the usage MEASURES and setting
-- usage_suppressed_flag, NOT by dropping the row: a licence period that exists must remain
-- visible (a silently missing period is indistinguishable from a licence that was never
-- sold, and would under-report the P&L). Consumption already flagged
-- threshold_suppressed_flag upstream is excluded before aggregation. No person-level data —
-- the consuming party is always a governance principal, never a person.
--
-- Grain: one row per (principal × data product × supplier scope × fiscal year × fiscal
-- period). supplier_scope_id is the LICENCE's scope (NULL = a licence spanning every
-- supplier the product covers), not the supplier of an individual usage row.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${dss_schema}.gold_data_product_revenue AS
WITH ranked_subscription AS (
  -- Rank ALL versions first (across every status) so the newest licence version wins
  -- even when it is a cancellation; the status filter is applied AFTER ranking so a
  -- cancelled latest VACATES the scope rather than silently resurfacing the stale
  -- active terms it replaced (which would keep invoicing a cancelled contract).
  --
  -- Order primarily by EVENT TIME (subscribed_ts), NOT the SCD2 window: a renewal and a
  -- mid-term re-price can share an effective_from_date, and event time is the only key
  -- that is monotonic across both; effective_from_date breaks ties within an instant.
  SELECT
    principal_id, data_product_id, supplier_id, advertiser_id,
    contracted_price_amount, contracted_units, billing_frequency, currency_code,
    term_start_date, term_end_date, min_disclosure_threshold, subscription_status,
    ROW_NUMBER() OVER (
      PARTITION BY principal_id, data_product_id, COALESCE(supplier_id, '__all_suppliers__')
      ORDER BY subscribed_ts DESC, effective_from_date DESC
    ) AS rn
  FROM ${catalog}.${dss_schema}.data_product_subscription
),
-- The revenue-bearing licences: a contract that was genuinely in force at some point.
-- 'expired' and 'suspended' are KEPT deliberately — this view reports history by fiscal
-- period, so dropping them would erase the periods those contracts legitimately earned
-- in. 'pending' (never started) and 'cancelled' (revoked) are excluded.
licence AS (
  SELECT
    principal_id, data_product_id,
    supplier_id AS supplier_scope_id,
    advertiser_id,
    contracted_price_amount, contracted_units, billing_frequency, currency_code,
    term_start_date, term_end_date, subscription_status,
    -- Effective disclosure floor: the per-grant threshold OVERRIDES the data product's
    -- catalog default, and the default applies when the grant states none. Both levels are
    -- documented as participating (data_product.min_disclosure_threshold is "overridden per
    -- grant"), so both must be read here — reading only the grant would make the product
    -- default dead metadata. A floor is absent only when NEITHER level sets one, which is
    -- the documented "NULL means no floor" case.
    min_disclosure_threshold AS grant_disclosure_threshold
  FROM ranked_subscription
  WHERE rn = 1 AND subscription_status IN ('active', 'suspended', 'expired')
),
-- Fiscal-period spine with its date bounds, so a licence term can be expanded into the
-- periods it covers. Derived from the canonical calendar rather than hard-coded, and
-- collapsed to period grain first (fiscal_calendar is DAY grain).
fiscal_period_spine AS (
  SELECT
    fiscal_year, fiscal_period,
    MIN(date_key) AS period_start_date,
    MAX(date_key) AS period_end_date
  FROM ${catalog}.${calendar_schema}.fiscal_calendar
  WHERE fiscal_year IS NOT NULL AND fiscal_period IS NOT NULL
  GROUP BY fiscal_year, fiscal_period
),
-- Every (licence × in-term fiscal period). This is what lets a PAID-BUT-UNUSED licence
-- surface at all: the row exists because the contract covers the period, not because
-- someone consumed something. An open-ended term (term_end_date NULL) runs to the end
-- of the spine.
licence_period AS (
  SELECT
    l.principal_id, l.data_product_id, l.supplier_scope_id,
    sp.fiscal_year, sp.fiscal_period
  FROM licence l
  JOIN fiscal_period_spine sp
    ON sp.period_end_date >= l.term_start_date
   AND sp.period_start_date <= COALESCE(l.term_end_date, DATE'9999-12-31')
  WHERE l.term_start_date IS NOT NULL
),
-- Metered consumption rolled to (principal × product × supplier × fiscal period).
-- Suppressed usage rows are dropped before aggregation so a suppressed measure never
-- contributes to a disclosed total. currency_code is taken with MAX over a set the
-- dsc_single_currency check constrains to ONE value, so this picks that value rather
-- than mixing denominations.
consumption_period AS (
  SELECT
    principal_id,
    data_product_id,
    supplier_id,
    fiscal_year,
    fiscal_period,
    SUM(consumption_units)  AS consumption_units,
    SUM(billed_query_count) AS billed_query_count,
    SUM(billable_amount)    AS data_revenue_amount,
    MAX(currency_code)      AS currency_code,
    MAX(usage_date)         AS last_usage_date
  FROM ${catalog}.${dss_schema}.data_share_consumption
  WHERE COALESCE(threshold_suppressed_flag, FALSE) = FALSE
  GROUP BY principal_id, data_product_id, supplier_id, fiscal_year, fiscal_period
),
-- Attach each usage row to the MOST-SPECIFIC licence that covers it: a supplier-scoped
-- licence (supplier_scope_id NOT NULL) outranks an all-supplier one, so a principal
-- holding BOTH bills that supplier's usage once, against the specific contract. Done by
-- ranking rather than a correlated EXISTS in the join predicate (which Spark rejects
-- when it references both join inputs). Without this, overlapping grants would
-- double-count the same consumption.
entitled_usage AS (
  SELECT
    cp.principal_id, cp.data_product_id, l.supplier_scope_id,
    cp.fiscal_year, cp.fiscal_period,
    cp.consumption_units, cp.billed_query_count, cp.data_revenue_amount,
    cp.currency_code, cp.last_usage_date,
    ROW_NUMBER() OVER (
      PARTITION BY cp.principal_id, cp.data_product_id, cp.supplier_id, cp.fiscal_year, cp.fiscal_period
      ORDER BY CASE WHEN l.supplier_scope_id IS NOT NULL THEN 0 ELSE 1 END
    ) AS ent_rn
  FROM consumption_period cp
  JOIN licence l
    ON l.principal_id = cp.principal_id
   AND l.data_product_id = cp.data_product_id
   AND (l.supplier_scope_id IS NULL OR l.supplier_scope_id = cp.supplier_id)
),
-- Roll the deduplicated usage up to the licence's own grain (its supplier SCOPE), so an
-- all-supplier licence reports one row per period covering every supplier it billed.
usage_by_licence AS (
  SELECT
    principal_id, data_product_id, supplier_scope_id, fiscal_year, fiscal_period,
    SUM(consumption_units)  AS consumption_units,
    SUM(billed_query_count) AS billed_query_count,
    SUM(data_revenue_amount) AS data_revenue_amount,
    MAX(currency_code)      AS currency_code,
    MAX(last_usage_date)    AS last_usage_date
  FROM entitled_usage
  WHERE ent_rn = 1
  GROUP BY principal_id, data_product_id, supplier_scope_id, fiscal_year, fiscal_period
),
-- The scope grid: every (licence × period) the contract covers, UNION every period that
-- actually billed. The union keeps out-of-term usage visible instead of silently
-- dropping it (an anomaly worth seeing), and keeps in-term no-usage periods present.
scope AS (
  SELECT principal_id, data_product_id, supplier_scope_id, fiscal_year, fiscal_period FROM licence_period
  UNION
  SELECT principal_id, data_product_id, supplier_scope_id, fiscal_year, fiscal_period FROM usage_by_licence
),
-- Cross-package retail-media spend (NULL-safe). gold_campaign_performance is campaign ×
-- day, so it is collapsed to advertiser × fiscal period first; summing media_spend_net
-- across campaigns and days is additive (spend is spend, and campaign_day carries one
-- attribution model per grain, so no measure is mixed here).
media_spend_period AS (
  SELECT
    cp.advertiser_id,
    c.fiscal_year,
    c.fiscal_period,
    SUM(cp.media_spend_net) AS media_spend_net
  FROM ${catalog}.${cmn_schema}.gold_campaign_performance cp
  JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON c.date_key = cp.metric_date
  GROUP BY cp.advertiser_id, c.fiscal_year, c.fiscal_period
),
-- One reconciled row per licence × period, with terms, usage and the media signal.
recon AS (
  SELECT
    g.principal_id,
    g.data_product_id,
    g.supplier_scope_id,
    g.fiscal_year,
    g.fiscal_period,
    l.advertiser_id,
    l.subscription_status,
    l.billing_frequency,
    l.term_start_date,
    l.term_end_date,
    l.contracted_price_amount,
    l.contracted_units,
    -- Effective floor: the grant's threshold wins; the data product's catalog default
    -- applies when the grant states none (see the `licence` CTE).
    COALESCE(l.grant_disclosure_threshold, cat.min_disclosure_threshold) AS min_disclosure_threshold,
    u.consumption_units,
    u.billed_query_count,
    u.data_revenue_amount,
    u.last_usage_date,
    -- Label every monetary row: prefer the currency the revenue was billed in, else the
    -- licence's contracted currency (so a no-usage row still carries a currency for its
    -- contracted_price_amount).
    COALESCE(u.currency_code, l.currency_code) AS currency_code,
    -- Contracted allowance NORMALIZED to one fiscal period. contracted_units is stated
    -- per BILLING period, and a fiscal period is a retail month, so a quarterly or
    -- annual commitment must be pro-rated before it can be compared to a period's usage
    -- — comparing an annual allowance to one month of usage would understate
    -- utilisation twelve-fold. An unrecognised frequency yields NULL rather than a
    -- wrong denominator.
    CASE l.billing_frequency
      WHEN 'monthly'   THEN l.contracted_units
      WHEN 'quarterly' THEN l.contracted_units / 3.0
      WHEN 'annual'    THEN l.contracted_units / 12.0
      ELSE NULL
    END AS period_contracted_units
  FROM scope g
  LEFT JOIN licence l
    ON l.principal_id = g.principal_id
   AND l.data_product_id = g.data_product_id
   AND COALESCE(l.supplier_scope_id, '__all_suppliers__') = COALESCE(g.supplier_scope_id, '__all_suppliers__')
  LEFT JOIN usage_by_licence u
    ON u.principal_id = g.principal_id
   AND u.data_product_id = g.data_product_id
   AND COALESCE(u.supplier_scope_id, '__all_suppliers__') = COALESCE(g.supplier_scope_id, '__all_suppliers__')
   AND u.fiscal_year = g.fiscal_year
   AND u.fiscal_period = g.fiscal_period
  -- The data product's catalog row, for its DEFAULT disclosure floor. Joined on the
  -- business key + is_current (never on a version-specific _sk with is_current, which
  -- would drop history — SCD2-JOIN-CONTRACT).
  LEFT JOIN ${catalog}.${dss_schema}.data_product cat
    ON cat.data_product_id = g.data_product_id AND cat.is_current = TRUE
),
-- ALLOCATE the advertiser's period media spend across the licence rows that share that
-- advertiser, by each row's revenue weight — so a principal holding several licences
-- against one advertiser (e.g. an all-supplier licence AND a supplier-scoped one) does
-- NOT fan the whole advertiser spend onto every row. Fanning would double-count
-- SUM(media_spend_net) and total_monetised_value (both exposed as metric-view measures)
-- and understate each row's data share. A single-licence advertiser gets the full spend
-- (share = 1), and the per-row allocations sum back to the advertiser's actual spend.
--
-- Same allocation contract as gold_joint_demand_plan's statistical baseline. Weight is
-- realised revenue, falling back to the contracted price so a paid-but-unused licence
-- still draws a share rather than silently discarding that slice of spend. When no row
-- in the group carries any weight the allocation is NULL rather than divided by zero.
allocated AS (
  SELECT
    r.*,
    m.media_spend_net AS advertiser_media_spend_net,
    COALESCE(r.data_revenue_amount, r.contracted_price_amount, 0) AS media_alloc_weight,
    SUM(COALESCE(r.data_revenue_amount, r.contracted_price_amount, 0))
      OVER (PARTITION BY r.advertiser_id, r.fiscal_year, r.fiscal_period) AS advertiser_alloc_weight
  FROM recon r
  LEFT JOIN media_spend_period m
    ON m.advertiser_id = r.advertiser_id
   AND m.fiscal_year = r.fiscal_year
   AND m.fiscal_period = r.fiscal_period
),
-- Low-volume suppression decision, made ONCE here so every measure and derived metric
-- below reads the same flag. This is a small-volume/materiality filter, NOT a k-anonymity
-- control (the row is already aggregate at licence × fiscal period and carries no
-- underlying entity count).
--
-- CONTRACT, two parts:
--   1. A NULL effective threshold means NO floor — every entitled row discloses. "Effective"
--      = the grant's threshold, else the data product's catalog default (resolved in `recon`),
--      so a floor is absent only when NEITHER level sets one.
--   2. A ZERO-consumption (or no-usage) row is NEVER suppressed. The floor exists to avoid
--      disclosing a thin aggregate volume; a row with no usage discloses no volume at all,
--      only the principal's OWN inactivity, which they are entitled to see. Suppressing it
--      would also hide the paid-but-unused licence that gold_data_monetization_exceptions
--      exists to raise — the most commercially material exception in this use case.
suppression AS (
  SELECT
    a.*,
    (a.consumption_units IS NOT NULL
     AND a.consumption_units > 0
     AND a.consumption_units < COALESCE(a.min_disclosure_threshold, 0)) AS usage_suppressed
  FROM allocated a
),
allocated_spend AS (
  SELECT
    a.*,
    CASE
      WHEN a.advertiser_media_spend_net IS NULL THEN NULL
      WHEN a.advertiser_alloc_weight > 0
        THEN a.advertiser_media_spend_net * a.media_alloc_weight / a.advertiser_alloc_weight
      ELSE NULL
    END AS media_spend_net
  FROM suppression a
)
SELECT
  r.principal_id,
  r.data_product_id,
  dp.data_product_name,
  dp.data_product_category,
  dp.pricing_model,
  dp.consumption_unit,
  r.supplier_scope_id,
  s.supplier_name,
  -- The advertiser (brand role of the supplier) the licence is tied to, if any. Exposed
  -- because it is the grain the media allocation below is computed over: without it a
  -- consumer cannot verify that SUM(media_spend_net) reconciles to an advertiser's actual
  -- spend (see the dpr_media_allocation_reconciles check).
  r.advertiser_id,
  r.fiscal_year,
  r.fiscal_period,
  r.subscription_status,
  r.billing_frequency,
  r.term_start_date,
  r.term_end_date,
  r.contracted_price_amount,
  dp.list_price_amount,
  r.contracted_units,
  -- Low-volume suppression, applied to the MEASURES rather than by dropping the row (see
  -- the contract note at the foot of this view). Below-floor usage is withheld but the
  -- licence row survives, flagged, so a suppressed period is visibly suppressed rather
  -- than silently missing.
  CASE WHEN r.usage_suppressed THEN NULL ELSE r.consumption_units END  AS consumption_units,
  CASE WHEN r.usage_suppressed THEN NULL ELSE r.billed_query_count END AS billed_query_count,
  CASE WHEN r.usage_suppressed THEN NULL ELSE r.data_revenue_amount END AS data_revenue_amount,
  r.currency_code,
  CASE WHEN r.usage_suppressed THEN NULL ELSE r.last_usage_date END    AS last_usage_date,
  r.usage_suppressed AS usage_suppressed_flag,
  -- Discount actually granted off the published rate card.
  ROUND((dp.list_price_amount - r.contracted_price_amount) / NULLIF(dp.list_price_amount, 0), 4) AS contract_discount_pct,
  -- Share of the period's contracted allowance consumed. > 1 means the licence ran over
  -- its commitment; near 0 means it was paid for and not used. NULL when usage is
  -- suppressed — deriving it from withheld volume would leak that volume back out.
  CASE WHEN r.usage_suppressed THEN NULL
       ELSE ROUND(r.consumption_units / NULLIF(r.period_contracted_units, 0), 4) END AS contract_utilisation_pct,
  -- Revenue yield per metered unit — the price the partner effectively paid per unit.
  CASE WHEN r.usage_suppressed THEN NULL
       ELSE ROUND(r.data_revenue_amount / NULLIF(r.consumption_units, 0), 4) END AS revenue_per_consumption_unit,
  -- The advertiser's period spend ALLOCATED to this licence row by revenue share (see
  -- the `allocated` CTE) — additive across rows, unlike the raw advertiser total.
  r.media_spend_net,
  -- Total monetised value of the relationship for the period (licensed data + media).
  -- NULL-propagating on purpose: if EITHER component is absent (no media signal, or a
  -- period with no billed usage) the total is NULL rather than a partial sum presented as
  -- a total, which would overstate data's share below. Read it as "known total, or
  -- nothing" and use the two components directly when a partial view is wanted.
  --
  -- DELIBERATELY DIFFERENT from mv_data_product_revenue's total_monetised_value measure,
  -- which COALESCEs both terms to 0. The layers want different things: per ROW, "known
  -- total or nothing" is the honest reading; as an AGGREGATE KPI, a measure that vanishes
  -- whenever one component is missing for the whole group is unusable, and absent there
  -- means "no known value of that kind" rather than "unknown total". Both sides carry this
  -- note so the divergence reads as intentional rather than as drift.
  CASE WHEN r.usage_suppressed THEN NULL
       ELSE r.data_revenue_amount + r.media_spend_net END AS total_monetised_value,
  -- NOTE: because the media allocation above is revenue-PROPORTIONAL, this share is by
  -- construction identical across every licence row of the same advertiser × period —
  -- it is the ADVERTISER-level data share, correctly carried on each row so it survives
  -- the row filter and any aggregation. That invariance is a property of the allocation,
  -- not a bug; do not "fix" it by allocating on a different weight without re-checking
  -- that SUM(media_spend_net) still reconciles to the advertiser's actual spend.
  CASE WHEN r.usage_suppressed THEN NULL
       ELSE ROUND(r.data_revenue_amount / NULLIF(r.data_revenue_amount + r.media_spend_net, 0), 4) END AS data_revenue_share_pct,
  current_timestamp() AS fresh_as_of_ts
FROM allocated_spend r
LEFT JOIN ${catalog}.${dss_schema}.data_product dp
  ON dp.data_product_id = r.data_product_id AND dp.is_current = TRUE
LEFT JOIN ${catalog}.${supplier_schema}.supplier s
  ON s.supplier_id = r.supplier_scope_id AND s.is_current = TRUE;
