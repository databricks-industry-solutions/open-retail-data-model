# Lakebase serving spec — associate real-time lookups

> Adopter NICE (not ORDM DDL). Gold remains Delta-only per [ADR 0005](../../governance/decisions/0005-lakebase-physical-binding.md).

## Goal

Sub-second keyed lookups for mobile / POS companions:

| Lookup | Keys | Delta source (certified) |
|---|---|---|
| Product availability | `store_id`, `product_id` | `gold_associate_product_inventory_current` (MV) |
| Order / pickup status | `store_id`, `order_id` | `gold_associate_order_status_current` (MV) |
| Price / promo (optional) | `store_id`, `product_id` | `gold_associate_price_promotion_current` |

## Prerequisites

1. Package gold applied (inventory + order as materialized views preferred).
2. **Change Data Feed** enabled on upstream tables (shipped on `associate_context_event`, `associate_fulfillment_status`, `associate_lookup_audit`). For Triggered/Continuous Lakebase sync of an MV, also enable CDF on the MV if your sync mode requires it.
3. UC row filter from `filters.sql` applied on Delta **before** sync if you need store-scope in Postgres (FGAC does **not** propagate to synced tables — sync a store-scoped view if required).
4. Lakebase project / Postgres catalog in the adopter account (not published by ORDM).

## Recommended sync shape

```
Delta MV (UC)  --CDF / snapshot-->  Lakebase synced table  -->  App / Data API
```

- Prefer **Triggered** or **Continuous** sync once CDF is healthy; use **Snapshot** for first bring-up.
- Create Postgres indexes on `(store_id, product_id)` and `(store_id, order_id)` after sync (synced tables are read-only for DML).
- Keep the Python / DBSQL policy layer for authorization; do not treat Lakebase as a second write-back store for prices or inventory.

## CLI sketch (adopter)

```bash
# After CDF is on and gold MVs exist — names are illustrative
databricks postgres create-synced-table <lb_catalog>.public.associate_product_inventory_current \
  --source-table <uc_catalog>.ai_assisted_store_associates.gold_associate_product_inventory_current \
  --primary-key-columns store_id,product_id \
  --scheduling-policy TRIGGERED
```

Exact flags follow the workspace Lakebase / postgres CLI version — see the Databricks Lakebase synced-tables docs.

## Honesty fields that must survive sync

Apps reading Lakebase **must** still display:

- `inventory_basis` / `warning` / `explanation`
- `location_basis` (never invent shelf coords)
- `nearby_store_match_basis` (same-region, not distance)

## Out of scope for ORDM

- No Lakebase DDL under `outcome-packages/` (ADR 0005).
- No Databricks App in this repo (CONTRIBUTING §2).
- No operational write-state for price/inventory/order changes.
