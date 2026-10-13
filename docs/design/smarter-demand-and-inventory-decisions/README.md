# Design — Smarter Demand and Inventory Decisions

Design specifications for the **Smarter Demand and Inventory Decisions** outcome package in the Open Retail Data Model (ORDM). These documents define the data model for three use cases aligned to industry-standard demand planning, inventory management, and out-of-stocks practices.

## Use cases

| # | Document | Status | Description |
|---|---|---|---|
| 1 | [Demand and Order Forecasting](01-demand-and-order-forecasting.md) | Implemented | Planning units, statistical forecasts, planner overrides, order forecasts, accuracy/FVA |
| 2 | [Inventory Optimization](02-inventory-optimization.md) | Implemented | Safety stock, reorder points, ABC/XYZ policy templates, replenishment recommendations |
| 3 | [Out-of-Stocks Optimization](03-out-of-stocks-optimization.md) | Implemented | OOS events, lost sales estimation, demand sensing, recovery prioritization |

## Canonical core reuse

All three modules build on existing ORDM canonical core entities without redefining them:

- **Dimensions:** `product`, `store`, `supplier`, `promotion`, `fiscal_calendar`, `account`
- **Facts:** `sales`, `inventory_position`, `purchase_order_line`, `shipment` / `shipment_line` / `shipment_tracking`
- **Prices:** `product_price`

## Cross-package boundaries

| Package | Relationship |
|---|---|
| **Early Risk Detection** | Operational disruption triage, `gold_inventory_risk`, `mv_stockout_risk` — proactive; this package owns **planning** and **optimization** |
| **Balancing Margin and Volume** | Shares inventory health KPIs (DoH, WOC); forecast feeds elasticity models |
| **Data Sharing with Suppliers** | Joint demand planning consumes `gold_effective_forecast` |
| **Connected Store Signals** | Future smart-shelf feeds for observed OOS |

## Module dependency chain

```
Demand & Order Forecasting
        ↓
Inventory Optimization
        ↓
Out-of-Stocks Optimization
```

Each module can be implemented incrementally. Module 1 is the foundation; modules 2 and 3 consume its gold views.

## Industry patterns covered

| Pattern | ORDM module |
|---|---|
| Planning unit grain, hierarchical horizons, demand decomposition | Demand forecasting |
| ABC/XYZ segmentation and policy playbook | Inventory optimization |
| FVA, planner overrides, model registry | Demand forecasting |
| Demand sensing / incident detection | Out-of-stocks optimization |
| Forecast bias → inventory impact | Inventory optimization + OOS |

## Next steps

1. Review design docs with working group
2. Implement extension table DDL in `outcome-packages/smarter-demand-and-inventory-decisions/tables/`
3. Add gold views and metric views per module
4. Register synthetic data generators
5. Update `STATUS.md` and run `make regen`
