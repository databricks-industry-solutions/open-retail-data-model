# ADR 0032 — Shared sensor-report interval envelope with keyed extensions

**Status:** Accepted (2026-07-31) — all four scopes in the corrective-review approval record are signed off (CSS owner, CMN owner, Maintainers, Privacy).

## Context

Foot Traffic, IoT Sensor Monitoring, RFID Tracking, and Smart Shelf all produce an
aggregated measurement of a property over a subject and interval. Their reusable
measurement, time, quality, provenance, and restatement fields align with the GS1 EPCIS
2.0 `sensorReport` field set. Their type-specific measures do not: Foot Traffic alone
needs counting conventions, staff adjustment, occupancy, and dwell numerators.

A single wide sparse table obscures ownership and lets unrelated report types carry
traffic fields. Fully separate facts duplicate the interval, quality, lineage, and
restatement contracts and invite drift.

## Decision

Use a narrow shared envelope, `sensor_report_interval`, plus keyed one-to-one type-specific
extensions.

- The envelope contains only fields reusable across the four solutions: subject,
  `report_type`, EPCIS-shaped values and units, aggregation level, canonical time window,
  source-observation completeness, quality, device/deployment lineage, interval-level
  source-message summaries, restatement, and audit.
- `foot_traffic_interval_detail` uses `sensor_report_interval_sk` as both primary key and
  foreign key and owns all traffic, convention, staff, occupancy, and dwell fields.
- Every space-subject `gs1:Count` envelope row has exactly one traffic-detail row. Item,
  EPC, and other non-space counts remain valid without traffic detail; every other
  report/subject combination cannot have one. DQ checks enforce both directions.
- The durable id is
  `subject_type|subject_id|report_type|aggregation_level|interval_minutes|`
  `unix_timestamp(interval_start_ts)|sensor_device_id`; the surrogate remains
  `xxhash64(durable_id)`.
- Every modeled interval row is canonical. An additive series is identified by
  `subject_type`, `subject_id`, `report_type`, and `aggregation_level`; device identity
  is provenance, not additive-series identity. A series contains one non-overlapping
  cadence, so cross-device `_ALL` rollups cannot coexist with their per-device
  constituents. Vendor-native rollups and alternate resolutions remain in Bronze or a
  reconciliation tier and are never co-stored in the additive fact.
- Raw message sequence and quality fields remain in Bronze. The envelope stores only
  interval-grain summaries such as message count, sequence gaps, duplicates, historical
  messages, and bad-quality messages.

## Rejected alternatives

**One wide sparse fact.** It avoids extension joins but mixes unrelated contracts, grows
with every vertical, and requires null-group exclusivity rules to remain interpretable.

**Fully separate interval facts.** They read cleanly but copy the same time, quality,
source, and restatement machinery into every solution and leave no stable shared
substrate.

## Consequences

- New solutions reuse the envelope and add a keyed extension only when they have
  non-scalar measures.
- Gold views explicitly join the relevant extension and filter `report_type`,
  `subject_type`, and `aggregation_level`.
- Source completeness can never be inferred from shopper volume.
- Canonical overlap, duration agreement, observation bounds, and extension integrity are
  release-blocking checks.
- EPCIS conformance remains a projection capability, not a certification claim.
