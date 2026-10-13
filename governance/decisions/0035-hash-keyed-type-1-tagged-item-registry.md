# ADR 0035 — Serialized-item identity is a hash-keyed Type 1 registry

**Status:** Accepted (2026-10-07; design approved 2026-08-19; domain-reviewer sign-off in #165).

## Context

RFID introduces an estate-scale grain not otherwise carried by ORDM: the individual serialized
unit. Commissioning feeds can write hundreds of millions or billions of EPCs concurrently.
Delta IDENTITY columns serialize writers, the constraint that motivated ADR 0028 — *Hash
surrogate keys for high-volume gold event facts*.

SCD2 would add little value. For SGTIN, the GTIN and serial are encoded in the EPC and cannot
change without creating a different identity. Versions would mainly record privacy-state flips
that operational event history already explains. The current physical carrier can change while
the EPC identity remains stable.

## Decision

`tagged_item` is a CSS Type 1 registry at one row per EPC Pure Identity URI.

- `tagged_item_id` is the authoritative durable identity and contains the EPC URI.
- `tagged_item_sk = xxhash64(tagged_item_id)` supports concurrent commissioning.
- `ti_sk_collision` is an error-severity guard.
- Immutable identity attributes and the commission-time product reference remain on the row.
- `current_tid_hex` is replaceable physical-carrier evidence, not item identity.
- `tag_privacy_state`, commission/decommission timestamps, and the carrier are maintained in
  place. Kill/decommission history is recoverable from read events; protected/detached are
  asserted current-state governance attributes.

The `_sk`/`_id` pair and primary-key shape stay consistent with ADR 0004; key derivation and
history strategy are the intentional deviations. At deployments approaching one billion
distinct keys, use ADR 0028 — *Hash surrogate keys for high-volume gold event facts* — and
its SHA-256 escape rather than accepting 64-bit birthday risk.

The registry remains CSS-owned until the **first non-CSS consumer of serialized identity**.
That event triggers a follow-up placement ADR, most naturally product-adjacent canonical core.

## Consequences

Streaming commissioning remains parallel and the registry stays one row per serialized unit.
Historical state questions use the event fact. Consumers must treat the durable EPC URI as
authoritative and collision checks as operational controls.

This is the first master-tagged ORDM object that is neither IDENTITY-keyed nor SCD2, so its table
header and design documentation cite this decision explicitly. If Delta removes the IDENTITY
concurrency constraint and a genuine version-history use case appears, revisit the choice.
