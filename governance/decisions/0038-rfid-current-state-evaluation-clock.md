# ADR 0038 — RFID item presence has an explicit evaluation clock

**Status:** Accepted (2026-10-07; design approved 2026-08-19; domain-reviewer sign-off in #165).

## Context

ADRs 0035–0037 define serialized-item identity, the RFID event fact, and the item-only
privacy boundary. The resulting `gold_item_current_state` view also derives whether an item
is present, absent, unavailable, or stale. That answer depends on an evaluation instant:
fixed-reader evidence expires after 120 minutes and mobile-sweep evidence after 24 hours.

Production data should be evaluated against wall clock. Deterministic synthetic data is
intentionally historical, however, so evaluating it against wall clock eventually makes every
item stale and empties `gold_zone_item_presence_current`. Regenerating dates near wall clock
would only postpone the failure and would make seeded datasets time-dependent.

## Decision

RFID item-presence views use the resolved `${rfid_as_of_ts}` expression.

- `wall_clock` is the default and resolves to `current_timestamp()`.
- `data_max` is an explicit demo/validation mode and resolves to the latest
  `rfid_read_event.event_ts`, falling back to wall clock when the event table is empty.
- Deployment accepts only those named modes. It does not accept arbitrary SQL expressions.
- `gold_zone_item_presence_current` propagates the evaluation timestamp from
  `gold_item_current_state`, so filtering and the reported `fresh_as_of_ts` cannot diverge.

This clock applies only to RFID item-presence semantics. Load/audit timestamps and unrelated
CSS traffic, device-health, and count-coverage calculations retain their own wall-clock
contracts.

## Consequences

Live deployments remain unchanged by default and still expose a dead RFID feed as stale.
Historical demos can be replayed repeatably without rewriting event history, while consumers
can see the exact instant at which presence was evaluated. A demo deployment must opt into
`rfid_as_of_mode=data_max`; omitting the override deliberately restores production behavior.
