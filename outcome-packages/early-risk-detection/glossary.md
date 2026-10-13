# Early Risk Detection — Business Glossary

> Status: 🟢 Review complete (0.5)

Business terms for the Early Risk Detection outcome package. Vendor-neutral; follows the ORDM [data model standards](../../docs/data-model-standards.md).

## Tables & views

| Object | Grain | Description |
|---|---|---|
| `supplier` (canonical-core) | One version per supplier (SCD2) | Conformed supplier/vendor master; GS1 GLN business key, ISO 3166 country. |
| `purchase_order_line` (canonical-core) | One PO line | Order + receipt/delivery + defect/return + invoice/contract price for one ordered line. |
| `inventory_position` (canonical-core) | One product x store x day | Daily inventory snapshot: on-hand, in-transit, stockout flags. |
| `shipment` (canonical-core) | One row per shipment | Shipment/ASN transactional header with ETA, carrier, lane, and destination. |
| `shipment_line` (canonical-core) | One line per shipment | Item-level shipped/received/damaged quantities. |
| `lane` (canonical-core) | One version per lane (SCD2) | Origin-to-destination route with planned transit time. |
| `disruption_event` | One disruption event (append-only) | Unifying exception log across all disruption types. |
| `disruption_alert` | One alert (lifecycle-managed) | Actionable alerts with open/acknowledged/resolved lifecycle. |
| `disruption_rule` | One rule (reference) | Detection rule configuration: metric, threshold, severity. |
| `gold_supplier_scorecard` | One supplier x fiscal period | Per-supplier KPIs and weighted composite score. |
| `gold_procurement_risk` | One supplier (current period) | Risk register: per-factor risk, blended score, tier, top factors. |
| `gold_shipment_current_state` | One shipment (current) | Real-time current state derived from the canonical-core `shipment_tracking` carrier feed. |
| `gold_inventory_risk` | One product x store (current) | Days-of-supply, stockout risk score, and risk tier. |
| `gold_control_tower` | One open/acknowledged alert | Single-pane serving view joining alerts, shipments, inventory, and supplier risk. |

## Supplier score & monitoring terms

| Term | Definition |
|---|---|
| **OTIF** (`otif_pct`) | On-Time In-Full: the share of order lines delivered **both** on time (`actual_delivery_date <= promised_date`) **and** in full (`received_qty >= ordered_qty x tolerance`, tolerance default 1.0). |
| **Fill rate** (`fill_rate`) | `SUM(received_qty) / SUM(ordered_qty)` over the period. |
| **Average lead time** (`avg_lead_time_days`) | Mean of `actual_delivery_date - order_date` (days) over delivered lines. |
| **Lead-time variance** (`lead_time_variance`) | Population variance of lead time — consistency of delivery timing. Higher = less reliable. |
| **Defect rate** (`defect_rate`) | `(defective + returned units) / received units`. |
| **Price compliance** (`price_compliance_pct`) | Share of lines invoiced at or below the contract price. |
| **Composite supplier score** (`composite_score`) | Weighted 0-100 score (OTIF 35, fill 25, lead-time 20, defect 15, price 5). |

## Procurement risk terms

| Term | Definition |
|---|---|
| **Performance risk** | `100 - composite_current`. Inverse of the current scorecard. |
| **Trend risk** | Deterioration over trailing 4 fiscal periods. Fires even with an OK current score. |
| **Concentration / HHI** | Spend-weighted average category Herfindahl index, fractional [0,1]. |
| **Single source** | Supplier is the sole source of >= 1 SKU. A supply-chain single point of failure. |
| **Geo risk** | Geographic concentration of supply within a single country. |
| **Risk tier** | LOW / MEDIUM / HIGH / CRITICAL with escalators for single-source and steep trend. |

## Real-time disruption detection terms

| Term | Definition |
|---|---|
| **Disruption event** | An append-only record of a detected exception: late shipment, stockout risk, quality issue, feed outage, etc. Event-grained; never updated. |
| **Disruption alert** | An actionable work item derived from one or more disruption events. Has a lifecycle: open -> acknowledged -> resolved / escalated. |
| **Disruption rule** | A configured detection rule: metric + threshold + severity. The configuration layer for the detection engine. |
| **ETA slip** (`eta_slip_days`) | Difference between effective arrival and original ETA, in days. Positive = late. Two lenses: the **real-time** lens (`gold_shipment_current_state`) uses the carrier's revised ETA (`carrier_eta_date`) falling back to `estimated_arrival_date`; the **KPI** lens (`mv_eta_slip`) uses `actual_arrival_date` falling back to `estimated_arrival_date`, measuring outcome against plan. |
| **Days of supply** (`days_of_supply`) | `units_on_hand / avg_daily_sales`. How many days current inventory will last at the trailing sales rate. |
| **Stockout risk score** | 0-100 score derived from days-of-supply. 100 = currently stocked out. |
| **Feed freshness** | How current the data feeds are. Measured as minutes since the last event was ingested. A stale feed is itself a disruption signal. |
| **Ingest latency** (`latency_seconds`) | Time between when an event occurred at source and when it was ingested. Lower = more real-time. |
| **Control tower** | Single-pane serving view combining open alerts, shipment state, inventory position, and supplier risk for operations triage. |

## Weighting scheme & normalization

Each supplier KPI is normalized to 0-100 (higher = better) before weighting:

| KPI | Weight | Normalization |
|---|---|---|
| OTIF | **35** | `otif_pct x 100` |
| Fill rate | **25** | `min(fill_rate, 1) x 100` |
| Lead-time reliability | **20** | `100 x max(0, 1 - lead_time_variance / 25)` |
| Defect | **15** | `100 x max(0, 1 - defect_rate / 0.10)` |
| Price compliance | **5** | `price_compliance_pct x 100` |

## Inventory risk thresholds

| Tier | Days of supply | Score |
|---|---|---|
| Stockout | 0 (currently out) | 100 |
| Critical | < 3 days | 79-99 |
| At risk | 3-14 days | 1-78 |
| Healthy | > 14 days | 0 |
