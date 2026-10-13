# ADR 0033 — Relocate footfall ownership from CMN to Connected Store Signals

**Status:** Accepted (2026-07-30) — CMN-owner approval recorded (Ruslan Dautkhanov, issue #105); see the corrective-review approval record.

## Context

`commerce-media-networks.store_zone_interval` was published as a store-zone interval
footfall and dwell fact because CMN was its first consumer. Footfall is store-operations
subject matter and is also the first vertical of Connected Store Signals. Moving it after
publication is a breaking schema and ownership change, so shape compatibility and a
controlled data migration are both required.

`opportunity_to_see` is different: it is a media measure that requires placement-level
exposure assumptions. It does not belong on a CSS operational fact, and the old
placeholder formula is not a governed replacement.

## Decision

- CSS owns the canonical interval envelope, `foot_traffic_interval_detail`, operational
  traffic views, and disclosure-controlled shared traffic views.
- CMN deletes the physical modeled table only through the manual migration procedure in
  `docs/migrations/0033-cmn-store-zone-interval-to-css.md`.
- During the deprecation window CMN preserves the exact published object name:
  `${catalog}.${cmn_schema}.store_zone_interval`.
- The compatibility view preserves the retired ordered column list, types, interval
  start, and interval-duration meanings and adds no helper columns. New rows come from
  `${catalog}.${css_schema}.gold_zone_traffic_interval_shared`. Suppressed rows are
  omitted completely; the shim never joins to the operational fact to recover timing
  metadata.
- New-row `opportunity_to_see` is NULL until CMN approves a versioned placement-level
  derivation. Historical OTS is preserved unchanged in a CMN-owned legacy mapping during
  migration; shape compatibility does not invent semantic equivalence.
- Existing daily operational consumers migrate to `gold_zone_traffic_current`;
  operational interval consumers use the canonical envelope/detail pair. Consumers
  receiving disclosed daily data migrate to `gold_zone_traffic_shared`; disclosed
  interval consumers migrate to `gold_zone_traffic_interval_shared`.

## Migration and release gate

The normal Asset Bundle deployment must not rename or delete the existing physical table.
The controlled cutover backfills CSS, validates totals and canonical keys, preserves
legacy OTS, renames the physical table to a dated legacy object, creates the original-name
view, and runs consumer smoke tests.

CMN-owner approval of the exact-name migration and OTS treatment is recorded (see the status
line above). CSS-owner, privacy, and maintainer approvals are still pending before production cutover.
Implementation being code-complete does not by itself record those approvals.

## Consequences

- The compatibility interface retains the original interval grain and duration semantics
  through the disclosure-controlled CSS interval surface.
- Cross-package gold reads remain intentional and governed by the layer-integrity ADR.
- Generated CMN contracts, checks, comments, diagrams, and Explorer artifacts must use
  the original `store_zone_interval` name.
- The legacy mapping and compatibility view remain until the documented deprecation
  window expires and the CMN owner confirms consumer migration.
