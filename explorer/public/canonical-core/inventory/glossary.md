# Inventory Domain Glossary

> Status: 🟢 Review complete (0.5)

Business terms and metrics used within the Inventory domain. Follows the ORDM [data model standards](../../docs/data-model-standards.md).

## Tables

| Object | Grain | Description |
|---|---|---|
| `inventory_position` | Daily snapshot per store × product | Daily inventory snapshot at store-product grain: on-hand (SOD/EOD), in-transit, on-order, received today, and stockout indicators. Scoped to `date_key`. Essential for demand elasticity modeling and distinguishing stockout from zero-demand. |

## Key terms

| Term | Definition |
|---|---|
| **Inventory Position** | A daily snapshot of the stock level for a specific product at a specific store location. |
| **Units On Hand** | The physical count of a product available at a location. Tracks start-of-day (SOD) and end-of-day (EOD) levels. |
| **Units In Transit** | Product quantities that have been shipped but not yet received by the destination location. |
| **Units On Order** | Product quantities ordered from a supplier or distribution center but not yet shipped. |
| **Stockout** | An event where the on-hand inventory for a product reaches zero, resulting in missed sales opportunities. |
| **OTIF (On-Time In-Full)** | A supply chain metric measuring the percentage of orders received both on the requested delivery date and with the exact quantities ordered. |
| **Fill Rate** | The percentage of customer or store orders that can be met from immediately available stock. |
| **Days of Supply (DOS)** | An estimate of how long the current on-hand inventory will last based on historical or forecasted demand. |
| **Weeks of Cover (WOC)** | DOS expressed in weeks. |
