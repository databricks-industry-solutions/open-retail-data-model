-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- View: gold_joint_demand_plan
-- Layer: outcome package (gold / consumable)
-- Materialization: plain view (engine-neutral). Apply a deploy-time row filter on
--   principal_id (= the querying group) so each partner sees only entitled rows.
-- Version: 0.5
-- Generated: 2026-08-01
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-01
-- ============================================================
-- The ENTITLED joint demand plan (CPFR reconciliation): per supplier × product ×
-- fiscal week, the latest retailer submission, the latest supplier submission, and
-- the latest published consensus, joined to demand_collaboration so every row
-- carries the principal_id permitted to see it (supplier-wide or product-scoped).
-- This is the row-filter source for partner sharing; pairs with
-- consensus_forecast_snapshot (the immutable published freeze).
--
-- Cross-package enrichment (NULL-safe, no FK): LEFT JOIN the Smarter Demand and
-- Inventory Decisions package's gold_demand_forecast_weekly to add the statistical
-- baseline. Degrades gracefully by DATA, not by object existence: if that view exists
-- but is EMPTY (SDI schema deployed, not yet populated), the LEFT JOIN NULLs the
-- baseline column and every plan row is still returned — the same pattern as
-- gold_category_growth. The referenced view must still EXIST for this view to compile
-- (a genuinely absent object fails at analysis time, like any SQL view dependency), so
-- deploy the sdi schema's gold layer alongside this package; no FK / no row-level
-- deploy-order coupling is introduced (gold→gold coupling is avoided by design).
--
-- Low-volume suppression and below-threshold rows are excluded. No person-level data.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${dss_schema}.gold_joint_demand_plan AS
WITH ranked_submission AS (
  -- Rank ALL versions first (across every status) so the newest submission wins even
  -- when it is a withdrawal/draft; the status filter is applied AFTER ranking so a
  -- withdrawn/draft latest VACATES the scope (raising missing_*_plan downstream)
  -- rather than silently resurfacing a stale prior version.
  --
  -- Order primarily by EVENT TIME (submitted_ts), NOT submission_version: version is
  -- documented as monotonic only WITHIN a plan cycle (see demand_plan_submission), so
  -- across a rolling CPFR cadence the same target fiscal_week_id is re-planned fresh in
  -- a later cycle at a LOW version — ordering by version first would let an older
  -- cycle's high version shadow the newer cycle's plan. Event time is cycle-agnostic,
  -- so the most recently submitted plan for a target week always wins; version only
  -- breaks ties within the same instant.
  SELECT
    party_role, supplier_id, product_id, fiscal_week_id,
    forecast_qty, forecast_value_net, currency_code, submission_status,
    ROW_NUMBER() OVER (
      PARTITION BY party_role, supplier_id, product_id, fiscal_week_id
      ORDER BY submitted_ts DESC, submission_version DESC
    ) AS rn
  FROM ${catalog}.${dss_schema}.demand_plan_submission
),
retailer_plan AS (
  SELECT supplier_id, product_id, fiscal_week_id,
         forecast_qty AS retailer_qty, forecast_value_net AS retailer_value_net,
         currency_code AS retailer_currency_code
  FROM ranked_submission
  WHERE rn = 1 AND party_role = 'retailer' AND submission_status IN ('submitted', 'superseded')
),
supplier_plan AS (
  SELECT supplier_id, product_id, fiscal_week_id,
         forecast_qty AS supplier_qty, forecast_value_net AS supplier_value_net,
         currency_code AS supplier_currency_code
  FROM ranked_submission
  WHERE rn = 1 AND party_role = 'supplier' AND submission_status IN ('submitted', 'superseded')
),
latest_consensus AS (
  -- Latest published consensus per (supplier, product, week). Rank by SNAPSHOT TIME
  -- (event time) first, NOT plan_version — matching the submission ranking above: a
  -- later cycle re-publishing the same target week must win even if its plan_version
  -- numbering differs, so the most recently frozen consensus is always served.
  -- threshold_suppressed_flag is applied AFTER ranking (below) so a suppressed latest
  -- vacates the scope rather than resurfacing an older, disclosable version.
  SELECT
    supplier_id, product_id, fiscal_week_id, plan_cycle_id,
    consensus_qty, consensus_value_net, variance_pct, currency_code, threshold_suppressed_flag,
    ROW_NUMBER() OVER (
      PARTITION BY supplier_id, product_id, fiscal_week_id
      ORDER BY snapshot_ts DESC, plan_version DESC
    ) AS rn
  FROM ${catalog}.${dss_schema}.consensus_forecast_snapshot
),
consensus AS (
  SELECT supplier_id, product_id, fiscal_week_id, plan_cycle_id,
         consensus_qty, consensus_value_net, variance_pct, currency_code
  FROM latest_consensus
  WHERE rn = 1 AND COALESCE(threshold_suppressed_flag, FALSE) = FALSE
),
-- Cross-package statistical baseline (NULL-safe). gold_demand_forecast_weekly still
-- carries a finer grain than product × week — it breaks out grain_type, store_id,
-- forecast_horizon_type and forecast_origin_date_key — so a naive SUM by product ×
-- week would MULTIPLE-COUNT across planning grains, horizons and re-forecasts. We
-- therefore collapse to ONE forecast per (product, store, week) first: a single
-- planning grain (store_sku), the highest-priority available horizon, and the latest
-- forecast origin, then SUM across stores to the PRODUCT × week baseline.
sdi_weekly_ranked AS (
  SELECT
    product_id, store_id, fiscal_week_id, forecast_quantity,
    ROW_NUMBER() OVER (
      PARTITION BY product_id, store_id, fiscal_week_id
      ORDER BY
        CASE forecast_horizon_type
          WHEN 'short_term' THEN 1 WHEN 'mid_term' THEN 2 WHEN 'long_term' THEN 3 ELSE 4 END,
        forecast_origin_date_key DESC
    ) AS rn
  FROM ${catalog}.${sdi_schema}.gold_demand_forecast_weekly
  WHERE forecast_horizon_type != 'backtest'
    AND grain_type = 'store_sku'
),
stat_baseline_product AS (
  SELECT product_id, fiscal_week_id, SUM(forecast_quantity) AS product_forecast_qty
  FROM sdi_weekly_ranked
  WHERE rn = 1
  GROUP BY product_id, fiscal_week_id
),
-- The scope grid: every (supplier, product, week) that any party or the consensus
-- touched, so the reconciliation returns a row even when only one side submitted.
scope AS (
  SELECT supplier_id, product_id, fiscal_week_id FROM retailer_plan
  UNION
  SELECT supplier_id, product_id, fiscal_week_id FROM supplier_plan
  UNION
  SELECT supplier_id, product_id, fiscal_week_id FROM consensus
),
-- One reconciled row per supplier × product × week (pre-entitlement).
recon AS (
  SELECT
    g.supplier_id, g.product_id, g.fiscal_week_id,
    c.plan_cycle_id,
    rp.retailer_qty, rp.retailer_value_net,
    sp.supplier_qty, sp.supplier_value_net,
    c.consensus_qty, c.consensus_value_net,
    -- Label every monetary row: prefer the consensus currency, else whichever party
    -- submitted (so a party-only row still carries a currency for its *_value_net).
    COALESCE(c.currency_code, rp.retailer_currency_code, sp.supplier_currency_code) AS currency_code,
    -- Demand weight used both for low-volume suppression and to ALLOCATE the
    -- product-level statistical baseline across the suppliers that share a product.
    COALESCE(c.consensus_qty, GREATEST(COALESCE(rp.retailer_qty, 0), COALESCE(sp.supplier_qty, 0))) AS demand_weight
  FROM scope g
  LEFT JOIN retailer_plan rp ON rp.supplier_id = g.supplier_id AND rp.product_id = g.product_id AND rp.fiscal_week_id = g.fiscal_week_id
  LEFT JOIN supplier_plan sp ON sp.supplier_id = g.supplier_id AND sp.product_id = g.product_id AND sp.fiscal_week_id = g.fiscal_week_id
  LEFT JOIN consensus     c  ON c.supplier_id  = g.supplier_id AND c.product_id  = g.product_id AND c.fiscal_week_id  = g.fiscal_week_id
),
-- Allocate the PRODUCT baseline to each supplier by its demand share of the product ×
-- week, so a product shared by multiple suppliers does NOT fan the whole-product
-- baseline onto every supplier row (which would understate per-row lift and
-- double-count SUM(statistical_forecast_qty)). Single-supplier products get the full
-- baseline (share = 1). When no supplier has demand weight the baseline is NULL for
-- those rows rather than divided by zero.
allocated AS (
  SELECT
    r.*,
    b.product_forecast_qty,
    SUM(r.demand_weight) OVER (PARTITION BY r.product_id, r.fiscal_week_id) AS product_demand_weight,
    CASE
      WHEN b.product_forecast_qty IS NULL THEN NULL
      WHEN SUM(r.demand_weight) OVER (PARTITION BY r.product_id, r.fiscal_week_id) > 0
        THEN b.product_forecast_qty * r.demand_weight
             / SUM(r.demand_weight) OVER (PARTITION BY r.product_id, r.fiscal_week_id)
      ELSE NULL
    END AS statistical_forecast_qty
  FROM recon r
  LEFT JOIN stat_baseline_product b
    ON b.product_id = r.product_id AND b.fiscal_week_id = r.fiscal_week_id
),
ent AS (
  SELECT principal_id, supplier_id, product_id, min_disclosure_threshold
  FROM ${catalog}.${dss_schema}.demand_collaboration
  WHERE is_current = TRUE AND collaboration_status = 'active'
),
-- Match each reconciled row to its entitlements, then keep the MOST-SPECIFIC grant per
-- (principal, supplier, product, week): a product-scoped grant (product_id NOT NULL)
-- outranks a supplier-wide one (product_id NULL), so a principal holding BOTH emits the
-- row once, with the product-scoped threshold. Done by ranking rather than a correlated
-- EXISTS in the join predicate (which Spark rejects when it references both join inputs).
entitled AS (
  SELECT
    a.*,
    e.principal_id,
    e.min_disclosure_threshold,
    ROW_NUMBER() OVER (
      PARTITION BY e.principal_id, a.supplier_id, a.product_id, a.fiscal_week_id
      ORDER BY CASE WHEN e.product_id IS NOT NULL THEN 0 ELSE 1 END
    ) AS ent_rn
  FROM allocated a
  JOIN ent e
    ON e.supplier_id = a.supplier_id
   AND (e.product_id IS NULL OR e.product_id = a.product_id)
)
SELECT
  en.principal_id,
  en.supplier_id,
  s.supplier_name,
  en.product_id,
  p.product_name,
  en.fiscal_week_id,
  en.plan_cycle_id,
  en.retailer_qty,
  en.supplier_qty,
  en.consensus_qty,
  en.retailer_value_net,
  en.supplier_value_net,
  en.consensus_value_net,
  en.currency_code,
  en.statistical_forecast_qty,
  -- Retailer-vs-supplier disagreement on the live latest submissions.
  ROUND((en.retailer_qty - en.supplier_qty) / NULLIF(en.supplier_qty, 0), 4) AS plan_variance_pct,
  -- Consensus lift over the (supplier-allocated) statistical baseline.
  ROUND((en.consensus_qty - en.statistical_forecast_qty) / NULLIF(en.statistical_forecast_qty, 0), 4) AS consensus_vs_baseline_pct,
  current_timestamp() AS fresh_as_of_ts
FROM entitled en
LEFT JOIN ${catalog}.${supplier_schema}.supplier s ON s.supplier_id = en.supplier_id AND s.is_current = TRUE
LEFT JOIN ${catalog}.${product_schema}.product p ON p.product_id = en.product_id AND p.is_current = TRUE
-- Keep only the most-specific entitlement per (principal, supplier, product, week).
WHERE en.ent_rn = 1
-- Low-volume suppression: gate on the row's demand weight (agreed consensus demand,
-- or the larger submitted party quantity before a consensus exists) against the
-- entitled minimum. This is a small-volume/materiality filter, NOT a k-anonymity
-- control (the row is already aggregate at supplier × product × week and carries no
-- underlying entity count). CONTRACT: a NULL min_disclosure_threshold means NO floor
-- (COALESCE(..., 0)) — the principal sees every entitled row regardless of volume.
  AND en.demand_weight >= COALESCE(en.min_disclosure_threshold, 0);
