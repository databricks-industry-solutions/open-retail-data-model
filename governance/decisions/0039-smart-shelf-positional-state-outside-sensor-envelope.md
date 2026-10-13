# ADR 0039 — Smart Shelf positional state remains outside the sensor interval envelope

**Status:** Accepted (2026-10-09; proposed 2026-08-21) by the maintainer, @Tagar, with the Connected Store Signals sign-off in #165 (acceptance record).

## Context

ADR 0032 established `sensor_report_interval` as the shared envelope for scalar interval
reports. Smart Shelf instead observes a multi-measure state at shelf-position × product ×
device × source-capture grain: facings, unit and weight estimates, since-prior pick/put
summaries, state, compliance flags, and independent quality axes. The envelope's one-subject
durable identity cannot represent several products from one physical shelf capture without
inventing composite subject identifiers or weakening its EPCIS-shaped audit trail.

ADR 0036 records the same boundary for RFID item events and reserves a future coordination
seam among RFID, Smart Shelf, and IoT for true item- or position-slot interval series. Smart
Shelf must not pre-empt that seam.

## Decision

Smart Shelf remains a use case inside the Connected Store Signals outcome package.
`shelf_state_observation` is its dedicated restatable positional-state fact and remains
outside `sensor_report_interval`; Smart Shelf v1 publishes no envelope rows.

The fact reuses the envelope's contracts without extending its schema: UTC capture time with
store-local derivations, device and sensing-deployment provenance, measurement validity and
arrival completeness, hash-keyed durable identity, restatement metadata, and Bronze evidence
pointers. Nullable pick/put and weight summaries remain on the observation row until the
reserved slot-series seam is jointly resolved.

The implementation remains aggregate- and item-level only. It carries no person-level or
person-linkable sensing data and does not weaken ADR 0029's package-wide privacy boundary.

## Consequences

- The scalar interval envelope keeps one coherent subject and measurement contract.
- Smart Shelf gets one auditable source fact instead of an envelope/detail duplication.
- A future slot-series design is additive and must not change the positional observation
  identity by inventing a composite envelope subject.
- The tri-party slot-series seam (RFID / Smart Shelf / IoT) that would carry shelf-condition
  interval series into the envelope — and unblock UC-RET-0204's replenishment-task-lead-time
  and all of UC-RET-0217 — is convened by **@saurabhshukla-db** (Smart Shelf is the newest
  consumer), review-by **2026-12-31 (end of Q4 2026)**. Until it lands, those task-loop KPIs
  are explicitly out of Smart Shelf v1's measurable scope.
- Serving semantics remain unchanged: latest capture wins before usability is evaluated;
  known, unknown, and unobserved states remain separate; and current-state freshness continues
  to use the named shelf evaluation clock.
- This decision introduces no change to any existing table schema.
