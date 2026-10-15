# ADR 0028 — Hash surrogate keys for high-volume gold event facts

**Status:** Accepted (2026-10-15; proposed 2026-07-28) by the maintainer, @Tagar (#213); implemented in `connected-store-signals`.

## Context

ADR 0004 establishes the primary-key contract: every table carries `<stem>_sk BIGINT GENERATED ALWAYS
AS IDENTITY` as its surrogate, plus a durable `<stem>_id STRING NOT NULL` and a named
`pk_<table>` constraint.

The `connected-store-signals` outcome package introduces the first tables in ORDM whose write pattern
is genuinely concurrent and streaming: `sensor_report_interval` (aggregation, restated on late
arrival), and — post-August — `rfid_read_event`, `shelf_reading`, and `esl_price_event`. An
item-level RFID feed across a store estate is the highest-volume table the model will contain.

Databricks documentation is explicit about the constraint this collides with:

> "Declaring an identity column on a Delta Lake table disables concurrent transactions. Only use
> identity columns in use cases where concurrent writes to the target table aren't required."

Identity columns are also unsupported via `CREATE TABLE AS SELECT`. So an IDENTITY surrogate on these
tables forces single-writer ingest on precisely the tables that need parallel streaming writes — and
it does so silently: nothing fails at DDL time, the constraint only shows up as serialised writes
under load.

Every existing ORDM table is a batch-loaded dimension or a batch-built fact, so the contract has never
been tested against this write pattern.

## Decision

Preserve the *shape* of the ADR 0004 key contract on high-volume gold facts, but derive the surrogate
by hash rather than IDENTITY:

| Tier | `_sk` derivation |
|---|---|
| Masters (`store_zone`, `sensor_device`, `sensing_deployment`, `electronic_shelf_label`) | `BIGINT GENERATED ALWAYS AS IDENTITY` — unchanged, ADR 0004 applies as written |
| Interval aggregates (`sensor_report_interval`) | `xxhash64(<durable _id>)` |
| Raw event facts (`rfid_read_event`, `shelf_reading`, `esl_price_event`) | `xxhash64(<durable _id>)` |

Implemented as: the master `electronic_shelf_label` shipped as `esl_label`; the event facts
`shelf_reading` and `esl_price_event` shipped as `shelf_state_observation` (ADR 0039) and
`esl_price_observation` (ADR 0041). The hash-keyed tables under this record are
`sensor_report_interval`, `rfid_read_event`, `shelf_state_observation` and
`esl_price_observation`; `tagged_item` is hash-keyed under ADR 0035. Each has a
`*_sk_collision` check in `outcome-packages/connected-store-signals/checks.sql`.

The durable `<stem>_id STRING NOT NULL` and the named `pk_<table>` constraint are unchanged. Only the
*derivation* of `_sk` differs, so joins, FK declarations, and the SCD2 join contract (ADR 0025) are
unaffected.

For interval aggregates the hash is not merely a workaround but a better fit: these rows are
**restated** when late data arrives (people-counting vendors document late arrival of hours to days),
and a recomputable key is what makes restatement idempotent. A monotonic IDENTITY value would change
on every recomputation of the same logical row.

This is legal without amending ADR 0004 because `PK-CONTRACT` is CI-enforced **canonical-core-only**
(`PK-CONTRACT` in `standards/rules.yaml`). The deviation is scoped to gold outcome-package facts and does not
weaken the core.

## Consequences

- **Collision risk is real and must be stated, not hidden.** `xxhash64` is 64-bit, so collision
  probability becomes non-trivial around ~5×10⁹ distinct values. For `rfid_read_event` at billions of
  rows the **durable `_id` STRING is the authoritative key** and `_sk` is a join convenience. A
  `<prefix>_sk_collision` DQ check at **error** severity guards every table using this pattern; it is
  not optional.
- Where an adopter needs a guaranteed-unique narrow key at that volume, use `sha2(<_id>, 256)` and
  accept the width. Documented in the table header rather than left to be rediscovered.
- The grain key feeding the hash must include every column that varies at the grain. Three collisions
  were found in review from keys that omitted `interval_minutes`, the device, and the price source
  respectively; a NULL inside a concatenated key silently collapses rows, so cross-device aggregates
  use an explicit `'_ALL'` sentinel rather than NULL.
- **A timestamp component of the grain key is epoch seconds, never a rendered timestamp.** Databricks
  `TIMESTAMP` is `TIMESTAMP_LTZ`, so `CAST(ts AS STRING)` renders in the session's
  `spark.sql.session.timeZone`. A key built that way is a property of the writing session rather than of
  the row: the same logical interval written under `UTC` and under `America/Los_Angeles` yields two
  different `_id`s and therefore two different `_sk`s, so a **restatement inserts a duplicate instead of
  updating**. Use `unix_timestamp(ts)`, which reads the underlying instant. Found by executing the check
  suite against a fixture (`tests/test_foot_traffic.py`), not by review — the two sides agreed with each
  other and were wrong together, which is exactly the failure mode a reconstruct-the-key check cannot
  catch on its own.
- Tables adopting this pattern state the deviation and cite this ADR in their header comment, so a
  reader does not conclude the PK contract was simply missed.
- Revisit if Delta lifts the IDENTITY concurrency limitation, at which point the masters/facts split
  becomes unnecessary.
