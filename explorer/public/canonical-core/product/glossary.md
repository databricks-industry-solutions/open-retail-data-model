# Product Domain — Business Glossary

> Status: 🟢 Review complete (0.5)

| Term | Definition |
|---|---|
| **Product** (`product`) | Conformed product master (SCD2). One **sellable SKU/GTIN**, versioned over time. |
| **GTIN** | GS1 Global Trade Item Number (UPC/EAN). A product business key. **Not PII.** |
| **SKU** | Stock keeping unit code. A product business key. **Not PII.** |
| **Variant hierarchy** (`style_id` / `color` / `size`) | A SKU is a *variant* of a style: `style_id` groups the SKUs of one style/model (product → style → SKU); `color` / `size` are the variant-defining attributes. `style_id` is NULL for non-variant products. |
| **Category / subcategory / department** | Merchandising hierarchy attributes used to roll up and scope analytics. |
| **List price** | Standard shelf price in the reporting/base currency; not a derived metric. The **current** snapshot mirrors `product_price` (`price_type = list`, `is_current`). |
| **Unit cost** | Standard unit cost (COGS) in the reporting/base currency. Basis for margin (`revenue − units × unit_cost`); a master cost attribute. Current snapshot of `product_price` (`price_type = cost`). |
| **Price history** (`product_price`) | System of record for prices over time: one date-grained SCD2 version per (`product_id`, `price_type` ∈ list/cost/promotional/contract). Read price **as of** a date here; the product dim keeps the current list/cost snapshot for cheap joins. Amount is unit-grain `DECIMAL(18,4)` (principle #9d). |

Surrogate `product_sk` is the join/FK target; `product_id` is the durable business key. No sales/margin aggregates live here (principle #4).
