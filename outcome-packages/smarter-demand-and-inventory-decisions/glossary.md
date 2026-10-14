# Smarter Demand and Inventory Decisions — Business Glossary

> Status: ✅ Published (0.5)

## Tables & views

| Object | Grain | Description |
|---|---|---|
| `planning_unit` | planning unit | Atomic demand-planning entity at configurable grain |
| `planning_unit_segment` | planning unit × fiscal period | ABC/XYZ segmentation and cluster assignment |
| `forecast_model_run` | model run | Model training and scoring execution registry |
| `demand_forecast` | planning unit × period | Statistical demand forecast lines |
| `forecast_component` | forecast × driver | Demand driver decomposition |
| `forecast_adjustment` | planning unit × period | Planner overrides for FVA |
| `order_forecast` | planning unit × order date | Replenishment / purchase / transfer order forecast |
| `forecast_accuracy` | planning unit × period | Lag-based accuracy and bias |
| `service_level_target` | segment version | Target service level (cycle service level / fill rate / in-stock) or days of supply by ABC/XYZ |
| `service_level_z` | service level | Service-level → z-score and unit-normal loss lookup for safety-stock sizing |
| `inventory_policy` | planning unit version | Safety stock, ROP, min/max replenishment policy |
| `inventory_policy_calculation` | policy calculation | Audit of policy derivation inputs |
| `inventory_recommendation` | recommendation | System-generated replenishment recommendation |
| `oos_event` | product × store episode | Out-of-stock episode with cause and severity |
| `lost_sales_estimate` | OOS event × day | Estimated lost demand and revenue |
| `demand_sensing_signal` | signal | Short-horizon demand anomaly |
| `oos_recovery_action` | OOS event × action | Recovery action recommendation or execution |
| `gold_effective_forecast` | planning unit × period | Statistical forecast enriched with planner adjustments |
| `gold_demand_forecast_weekly` | planning unit × fiscal week | Demand forecast aggregated to fiscal week with dimension context |
| `gold_forecast_accuracy` | planning unit × period | Accuracy/bias with `grain_type` and ABC/XYZ segment attributes |
| `gold_forecast_value_added` | planning unit × period | FVA: matched-lag naive vs model vs planner-enriched forecast |
| `gold_order_forecast` | planning unit × order date | Order forecast with open purchase-order comparison |
| `gold_demand_sensing_queue` | demand-sensing signal | Unresolved signals + forecast divergence for short-horizon triage |
| `gold_inventory_health` | product × store | Inventory health with DoS and policy compliance |
| `gold_inventory_policy_compliance` | product × store | Current inventory position vs active policy thresholds |
| `gold_replenishment_queue` | inventory recommendation | Open replenishment recommendations ranked by ABC service impact |
| `gold_inventory_capital_summary` | category × ABC class | Working capital + excess/understock exposure (cost vs margin basis) |
| `gold_inventory_productivity` | category × ABC class | Turnover, weeks-of-cover, GMROI, sell-through |
| `gold_service_level_attainment` | store × category × fiscal week | Achieved fill rate / in-stock rate vs target (gap uses the **default** segment target, not per-ABC/XYZ) |
| `gold_oos_current` | product × store | Ongoing OOS episodes with lost sales to date |
| `gold_oos_rate` | store × category × fiscal week | OOS rate KPIs from daily inventory-position snapshots |
| `gold_oos_preventability` | OOS event | Preventable / partial / not-preventable, judged as-of episode start |
| `gold_oos_recovery_priority` | OOS event | Open OOS events ranked by expected-margin recovery potential |
| `gold_lost_sales_summary` | category × cause × fiscal week | Aggregated lost sales by category, cause, and fiscal period |

## Demand planning terms

| Term | Definition |
|---|---|
| Planning unit | The atomic entity for forecasting; may be store×SKU or a rolled-up IBP grain |
| FVA (Forecast Value Added) | Improvement of the statistical forecast over a naïve baseline after planner enrichment |
| Forecast bias | Systematic over- or under-forecasting; positive bias implies excess inventory |
| DNA of demand | Decomposition of forecast into base, promo, price, weather, holiday, and residual drivers |

## Inventory terms

| Term | Definition |
|---|---|
| Days of supply (DoS) | On-hand units divided by average daily sales |
| Safety stock | Buffer inventory to absorb demand and lead-time variability; sized as `z × √(LT·σ_d² + D²·σ_LT²)` |
| Reorder point (ROP) | Inventory level that triggers a replenishment order; `lead-time demand + safety stock` |
| ABC/XYZ | Volume tier (ABC) × demand variability (XYZ) segmentation matrix |
| Cycle service level (Type I / α) | Probability of no stockout in a replenishment cycle; maps directly to the safety-stock z-score |
| Fill rate (Type II / β) | Fraction of demand met from stock; requires the unit-normal loss function to size, not just a z-score |
| GMROI | Gross Margin Return On Inventory investment = gross margin ÷ average inventory cost |
| Weeks of cover (WOC) | On-hand units divided by average weekly sell rate |
| Sell-through | Units sold ÷ (units sold + units on hand) over a period |

## Out-of-stocks terms

| Term | Definition |
|---|---|
| OOS rate | Percentage of product×store×day records with a stockout |
| Lost sales | Demand not captured in POS sales due to stockout |
| Demand sensing | Short-horizon anomaly detection bridging the forecast lag blind spot |
| Preventable OOS | Stockout that could have been avoided given policy and supply context |
| Phantom stock / record inaccuracy | System on-hand > 0 but the shelf is empty; a dominant real-world OOS driver (`oos_cause` values `phantom_stock`, `record_inaccuracy`, `shrinkage`, `misplaced`) |
| Lost margin | Estimated gross margin (not revenue) foregone during a stockout; the correct basis for recovery prioritization |
