# ADR 0036 — RFID events remain outside the sensor interval envelope

**Status:** Accepted (2026-10-07; design approved 2026-08-19; domain-reviewer sign-off in #165).

## Context

ADR 0032 established `sensor_report_interval` as the reusable envelope for scalar interval
reports, with keyed details when vertical-specific measures do not fit. ADR 0028 — *Hash
surrogate keys for high-volume gold event facts* — already named `rfid_read_event` as a
standalone high-volume fact.

An RFID read is an instant per-item observation carrying EPC identity, business step,
disposition, direction, and read-point attribution. It is not an interval aggregate of a scalar
property. Squeezing reads into the envelope would either create an envelope row per item instant
or overload subject identifiers. Publishing derived zone item counts as `space` + `gs1:Count`
would conflict with Foot Traffic's one-to-one detail contract.

## Decision

`rfid_read_event` is a dedicated append-only fact at EPC × reader × UTC-second grain. It reuses
the envelope's contracts—UTC time, store-local derivations, device/deployment lineage, quality,
and Bronze evidence pointers—without inserting envelope rows.

Current location, presence, disposition, census, inventory reconciliation, and zone counts are
derived in RFID gold views. RFID v1 publishes no `sensor_report_interval` rows.

Future item-subject interval series may adopt the IoT Sensor Monitoring solution for subject
identity. That addition is deferred and does not change the event fact.

## Consequences

V1 has one source fact instead of an event/envelope duplicate. The shared envelope remains a
coherent scalar-series contract, and Foot Traffic's `space` count semantics remain intact.

The cost is a named future coordination seam between RFID, Smart Shelf, and IoT for true
per-item or position-slot interval series. That seam is additive and must not be pre-empted by
inventing composite subject identifiers in this build.
