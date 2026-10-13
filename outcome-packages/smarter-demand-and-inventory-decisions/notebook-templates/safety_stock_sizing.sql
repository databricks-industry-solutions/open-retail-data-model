-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Safety-Stock & Reorder-Point Sizing — reference template
-- MAGIC
-- MAGIC ORDM · Outcome Package · Smarter Demand and Inventory Decisions · Version 0.5
-- MAGIC
-- MAGIC Reference implementation of the safety-stock (SS) and reorder-point (ROP) sizing
-- MAGIC **method**. Per the working-group call on where ORDM's schema-vs-compute line sits
-- MAGIC (review finding M3), the shared, governed *contract* is the stored inputs —
-- MAGIC `inventory_policy_calculation` (demand/lead-time moments) and the `service_level_z`
-- MAGIC lookup (service level → z + unit-normal loss `L(z)`) — while the specific
-- MAGIC inventory-theory sizing formula is a reference **method** you adapt, exactly like
-- MAGIC `oos_detection.sql` is the reference detection method. This mirrors that placement:
-- MAGIC comparable prescriptiveness, same layer.
-- MAGIC
-- MAGIC Closes review findings **A1** (safety-stock math was a hardcoded stub) and **A2**
-- MAGIC (service level vs fill rate was conflated). Treat it as a starting point to adapt,
-- MAGIC not a managed pipeline — it is declarative and idempotent
-- MAGIC (`CREATE OR REPLACE TEMP VIEW`) and writes nothing unless you run the final MERGE.
-- MAGIC
-- MAGIC Parameters use the same `${...}` tokens as the DDL (`catalog`, `sdi_schema`). Set
-- MAGIC them via widgets or `spark.conf`.
-- MAGIC
-- MAGIC ## Method
-- MAGIC
-- MAGIC The safety factor is chosen **per `service_measure_type`** — the definitions are not
-- MAGIC interchangeable and must not be sized the same way:
-- MAGIC
-- MAGIC - `cycle_service_level` (Type I / α): `z` = smallest z whose `service_level_pct ≥
-- MAGIC   target` (round **up** = conservative); `SS = z · supplier_mult · σ_DDLT`.
-- MAGIC - `in_stock_rate` (ready rate): **approximated** by the cycle-service-level z path.
-- MAGIC   Ready rate is time-weighted and is not the same object as cycle service level, so
-- MAGIC   the CSL quantile tends to slightly over-provision — a documented approximation
-- MAGIC   until a dedicated ready-rate factor lands.
-- MAGIC - `fill_rate` (Type II / β): a z-score alone does **not** size a fill rate. Expected
-- MAGIC   shortage per cycle is `σ_DDLT · L(z)`, and `β = 1 − shortage/Q`, so the required
-- MAGIC   loss is `L(z) = (1 − β)·Q / σ_DDLT` with cycle demand `Q = D · review_cycle`; look
-- MAGIC   up the smallest adequate z via the largest seeded `L(z) ≤ target loss`.
-- MAGIC
-- MAGIC `σ_DDLT` is the combined demand-and-lead-time standard deviation
-- MAGIC `σ_DDLT = sqrt(LT·σ_d² + D²·σ_LT²)` (the `D²·σ_LT²` lead-time-variance term is
-- MAGIC retained — the stored formula string dropped it even though `lead_time_std_dev` is
-- MAGIC collected). `ROP = D·LT + SS`, surfaced next to the stored `inventory_policy` values.
-- MAGIC
-- MAGIC Out-of-range targets are **clamped**, not dropped: a target more demanding than the
-- MAGIC seeded `service_level_z` table clamps to the most conservative seeded z rather than
-- MAGIC returning NULL, with `z_clamped_to_max` flagging those rows so you can extend the
-- MAGIC seed at the tail. Zero-variance policies legitimately size to `SS = 0`.
-- MAGIC
-- MAGIC Grain: one row per current `inventory_policy` that has a calculation row.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Recommendation candidates
-- MAGIC Derive SS/ROP from the stored calculation inputs + the service-level z lookup.

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW _safety_stock_recommendation AS
WITH calc AS (
  -- most recent calculation per policy
  SELECT * FROM (
    SELECT ipc.*,
           ROW_NUMBER() OVER (PARTITION BY ipc.inventory_policy_sk
                              ORDER BY ipc.calculated_at_timestamp DESC) AS rn
    FROM ${catalog}.${sdi_schema}.inventory_policy_calculation ipc
  ) WHERE rn = 1
),
policy_inputs AS (
  SELECT
    pol.inventory_policy_sk,
    pol.inventory_policy_id,
    pol.planning_unit_sk,
    pol.planning_unit_id,
    pol.review_period_days,
    pol.service_level_target_sk,
    pol.safety_stock_quantity  AS stored_safety_stock,
    pol.reorder_point_quantity AS stored_reorder_point,
    c.avg_daily_demand,
    c.demand_std_dev,
    c.lead_time_days,
    c.lead_time_std_dev,
    COALESCE(c.supplier_reliability_multiplier, 1.0) AS supplier_reliability_multiplier,
    -- combined demand + lead-time standard deviation over the lead time
    SQRT(
      c.lead_time_days * POWER(c.demand_std_dev, 2)
      + POWER(c.avg_daily_demand, 2) * POWER(COALESCE(c.lead_time_std_dev, 0), 2)
    ) AS sigma_ddlt
  FROM ${catalog}.${sdi_schema}.inventory_policy pol
  JOIN calc c ON c.inventory_policy_sk = pol.inventory_policy_sk
  WHERE pol.is_current = TRUE
),
tgt AS (
  SELECT service_level_target_sk,
         COALESCE(service_measure_type, 'cycle_service_level') AS service_measure_type,
         COALESCE(target_service_level_pct, target_fill_rate_pct) AS service_level_pct
  FROM ${catalog}.${sdi_schema}.service_level_target
  WHERE is_current = TRUE
),
enriched AS (
  SELECT
    pi.*,
    t.service_measure_type,
    t.service_level_pct,
    -- expected cycle demand Q (review cycle, falling back to the lead time)
    pi.avg_daily_demand * COALESCE(pi.review_period_days, pi.lead_time_days) AS cycle_demand,
    -- fill-rate target loss L(z); NULL for non-fill-rate rows or zero-variance
    CASE
      WHEN t.service_measure_type = 'fill_rate' AND pi.sigma_ddlt > 0 THEN
        (1 - t.service_level_pct)
        * (pi.avg_daily_demand * COALESCE(pi.review_period_days, pi.lead_time_days))
        / pi.sigma_ddlt
    END AS target_loss_l_z
  FROM policy_inputs pi
  LEFT JOIN tgt t ON t.service_level_target_sk = pi.service_level_target_sk
),
csl_z AS (
  -- cycle_service_level / in_stock_rate: smallest z at or above the target level
  SELECT inventory_policy_sk, z_score FROM (
    SELECT e.inventory_policy_sk, slz.z_score,
           ROW_NUMBER() OVER (PARTITION BY e.inventory_policy_sk
                              ORDER BY slz.service_level_pct ASC) AS rn
    FROM enriched e
    JOIN ${catalog}.${sdi_schema}.service_level_z slz
      ON slz.service_level_pct >= e.service_level_pct
    WHERE e.service_measure_type <> 'fill_rate'
  ) WHERE rn = 1
),
fill_z AS (
  -- fill_rate: smallest adequate z = largest seeded L(z) at or below the target loss
  SELECT inventory_policy_sk, z_score FROM (
    SELECT e.inventory_policy_sk, slz.z_score,
           ROW_NUMBER() OVER (PARTITION BY e.inventory_policy_sk
                              ORDER BY slz.loss_function_l_z DESC) AS rn
    FROM enriched e
    JOIN ${catalog}.${sdi_schema}.service_level_z slz
      ON slz.loss_function_l_z <= e.target_loss_l_z
    WHERE e.service_measure_type = 'fill_rate'
  ) WHERE rn = 1
),
z_bounds AS (
  -- clamp target for out-of-range demands: the most conservative seeded safety factor
  SELECT MAX(z_score) AS max_z FROM ${catalog}.${sdi_schema}.service_level_z
),
resolved AS (
  SELECT
    e.*,
    -- matched z from the appropriate path; NULL when the target is out of the seeded range
    COALESCE(csl.z_score, fz.z_score) AS matched_z,
    zb.max_z
  FROM enriched e
  LEFT JOIN csl_z csl ON csl.inventory_policy_sk = e.inventory_policy_sk
  LEFT JOIN fill_z fz ON fz.inventory_policy_sk = e.inventory_policy_sk
  CROSS JOIN z_bounds zb
)
SELECT
  r.inventory_policy_sk,
  r.inventory_policy_id,
  r.planning_unit_sk,
  r.planning_unit_id,
  r.service_measure_type,
  r.service_level_pct,
  -- chosen safety factor: matched z, else clamp to the most conservative seeded z when a
  -- target exists but is out of the seeded range (positive variance ⇒ genuinely unmatched)
  CASE
    WHEN r.matched_z IS NOT NULL THEN r.matched_z
    WHEN r.service_level_pct IS NOT NULL AND r.sigma_ddlt > 0 THEN r.max_z
  END AS z_score,
  -- TRUE when the target was more demanding than the seeded table and z was clamped
  (r.matched_z IS NULL AND r.service_level_pct IS NOT NULL AND r.sigma_ddlt > 0) AS z_clamped_to_max,
  r.avg_daily_demand,
  r.demand_std_dev,
  r.lead_time_days,
  r.lead_time_std_dev,
  r.supplier_reliability_multiplier,
  -- safety stock: z (chosen per service measure, clamped if out of range) * supplier mult * sigma_ddlt
  ROUND(
    COALESCE(r.matched_z, CASE WHEN r.service_level_pct IS NOT NULL AND r.sigma_ddlt > 0 THEN r.max_z END)
    * r.supplier_reliability_multiplier * r.sigma_ddlt,
    3) AS recomputed_safety_stock,
  -- reorder point = lead-time demand + safety stock
  ROUND(
    r.avg_daily_demand * r.lead_time_days
    + COALESCE(r.matched_z, CASE WHEN r.service_level_pct IS NOT NULL AND r.sigma_ddlt > 0 THEN r.max_z END)
      * r.supplier_reliability_multiplier * r.sigma_ddlt,
    3) AS recomputed_reorder_point,
  r.stored_safety_stock,
  r.stored_reorder_point
FROM resolved r;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Apply (optional)
-- MAGIC Uncomment to write recommendations back onto `inventory_policy`. This overwrites the
-- MAGIC stored SS/ROP with the recomputed values — review the recommendation view first, and
-- MAGIC treat the write as a deliberate re-planning step, not an automatic one. Clamped rows
-- MAGIC (`z_clamped_to_max = TRUE`) hit the seeded-table ceiling; extend `service_level_z` if
-- MAGIC you need finer resolution at the tail before applying.

-- COMMAND ----------

-- MERGE INTO ${catalog}.${sdi_schema}.inventory_policy t
-- USING _safety_stock_recommendation s ON t.inventory_policy_sk = s.inventory_policy_sk AND t.is_current = TRUE
-- WHEN MATCHED THEN UPDATE SET
--   t.safety_stock_quantity  = s.recomputed_safety_stock,
--   t.reorder_point_quantity = s.recomputed_reorder_point;
