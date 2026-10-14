# Equipment — Business Glossary

> Status: 🟢 Review complete (0.5) · Last reviewed: 2026-10-07

Business terms for the equipment domain. Vendor-neutral; follows the ORDM [data model standards](https://github.com/databricks-industry-solutions/open-retail-data-model/blob/main/docs/data-model-standards.md).

## Tables

| Object | Grain | Description |
|---|---|---|
| `equipment` | One version per equipment asset (SCD2) | In-store equipment master: refrigeration, HVAC, POS terminals, ovens, and other store-level assets. |
| `equipment_reading` | One sensor reading (append-only) | Telemetry data from equipment sensors: temperature, power, vibration, error codes. Streaming-ready. |

## Key terms

| Term | Definition |
|---|---|
| **Equipment** | A physical asset installed in a store that requires maintenance and monitoring. Examples: walk-in coolers, HVAC units, POS terminals, self-checkout kiosks, bakery ovens. |
| **Equipment type** | Category of the asset: `refrigeration`, `hvac`, `pos_terminal`, `self_checkout`, `oven`, `lighting`, `shelving`, `security`, or `other`. |
| **Criticality** | Impact level if the equipment fails: `critical` (immediate product loss or store closure risk), `high` (significant operational impact), `medium` (degraded service), `low` (minimal impact). |
| **Equipment status** | Current operational state: `operational` (working normally), `degraded` (working with reduced performance), `out_of_service` (not functioning), `decommissioned` (permanently retired). |
| **Installation zone** | Area within the store where the equipment is located: `sales_floor`, `backroom`, `exterior`, `loading_dock`, `office`, `kitchen`, `pharmacy`. |
| **Equipment reading** | A single telemetry data point from an equipment sensor. Append-only, streaming-ready, with event and ingest timestamps for freshness monitoring. |
| **Reading type** | The kind of sensor data: `temperature`, `humidity`, `power_kw`, `vibration`, `runtime_hours`, `error_code`, `door_open_count`, `pressure`. |
| **Anomaly** | A reading flagged by the ingestion pipeline as outside normal operating parameters. May indicate equipment degradation or imminent failure. |
| **Threshold breach** | When a reading crosses a defined boundary: `low`, `high`, `critical_low`, `critical_high`. |
| **Ingest latency** | Time in seconds between when a sensor reading occurred and when it was ingested into the lakehouse. Lower = more real-time. |
| **Asset tag** | Internal barcode or tag identifier used by the retailer's asset management system. |
