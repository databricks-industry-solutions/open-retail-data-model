# Design notes — Connected Store Signals

Committed design rationale for the Connected Store Signals outcome package. These documents
explain grains, semantic boundaries, and deferred seams; the deployable model lives in
[`outcome-packages/connected-store-signals/`](../../../outcome-packages/connected-store-signals/).

## Contents

- [`rfid-tracking.md`](rfid-tracking.md) — serialized-item identity, RFID visibility events,
  count sessions, basis-aware inventory reconciliation, receiving evidence, and privacy limits.
- [`smart-shelf.md`](smart-shelf.md) — position-level expected and observed shelf state,
  observation-only ESL evidence, metric boundaries, evaluation clocks, and cross-package seams.

The package-level README and glossary remain the consumer-facing contract. Design notes are the
reviewable rationale required by `CONTRIBUTING.md` and do not create additional data objects.
