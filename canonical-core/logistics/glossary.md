# Logistics — Business Glossary

> Status: ✅ Published (0.5)

Business terms for the logistics domain. Vendor-neutral; follows the ORDM [data model standards](../../docs/data-model-standards.md).

## Tables

| Object | Grain | Description |
|---|---|---|
| `lane` | One version per lane (SCD2) | Directed origin-to-destination route used for shipment planning and transit-time benchmarking. |
| `shipment` | One row per shipment | Shipment / ASN transactional header linking a purchase order to a lane, carrier, and destination. |
| `shipment_line` | One line per shipment | Item-level detail within a shipment: quantities shipped, received, and damaged. |
| `shipment_tracking` | One carrier tracking message (append-only) | Raw checkpoint data from carriers: scans, GPS pings, customs events, delivery confirmations. Streaming-ready. |

## Key terms

| Term | Definition |
|---|---|
| **Lane** | A directed route between two locations (e.g. supplier site to DC, DC to store). Identified by origin, destination, and transport mode. |
| **Shipment** | A physical movement of goods from origin to destination, typically fulfilling one or more purchase-order lines. Also called an ASN (Advanced Shipping Notice) when sent by the supplier. |
| **Shipment line** | One product within a shipment. Carries shipped, received, and damaged quantities. |
| **Transport mode** | How goods move: road, rail, ocean, air, or intermodal (combination). |
| **ETA** | Estimated Time of Arrival — the current expected arrival date at destination. May be revised from the original ETA. |
| **Original ETA** | The estimated arrival date at time of dispatch, before any revisions. The baseline for ETA-slip measurement. |
| **Planned transit days** | The standard transit time for a lane in calendar days. The benchmark for on-time assessment. |
| **Tracking message** | A raw checkpoint emitted by a carrier as a shipment moves through the network. Contains checkpoint type, location (lat/long, city, country, facility), carrier message text, and timestamps. |
| **Checkpoint type** | The kind of tracking event: `pickup`, `hub_scan`, `in_transit`, `out_for_delivery`, `delivered`, `attempted_delivery`, `customs_entry`, `customs_release`, `exception`, `return_to_sender`, or `info`. |
| **Carrier code** | A standardized short identifier for the carrier (e.g. a SCAC or BIC code). |
| **Tracking number** | The carrier-assigned waybill or tracking reference for the shipment. |
| **Delivered** | Delivery is expressible both as `shipment.actual_arrival_date` (header-level) and as a `delivered` checkpoint in `shipment_tracking`. The **authoritative source** for delivery confirmation is `shipment_tracking` (the raw carrier feed); `shipment.actual_arrival_date` is set at load time and may lag. For reconciliation, prefer the tracking feed. |
| **Ingest latency** | Time in seconds between when a tracking event occurred at the carrier and when it was ingested into the lakehouse. Lower = more real-time. |
