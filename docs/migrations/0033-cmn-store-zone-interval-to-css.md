# Migration 0033 — CMN store-zone traffic to Connected Store Signals

Status: implementation ready. CMN-owner approval is recorded in ADR 0033; the ADR still lists the
CSS-owner, privacy and maintainer approvals as pending (see Required approvals below). Do not perform
the production cutover or remove the legacy table until all of them are recorded.

## Contract during the deprecation window

The published object remains
`${catalog}.${cmn_schema}.store_zone_interval`. After the manual cutover it is a view with
the same ordered columns and data types as the retired table:

`store_zone_interval_sk`, `store_zone_interval_id`, `store_sk`, `store_id`,
`store_zone_code`, `interval_start_ts`, `interval_date`, `interval_minutes`,
`footfall_count`, `avg_dwell_seconds`, `opportunity_to_see`, `aggregated_flag`,
`record_source`, `load_timestamp`.

New rows come from
`${catalog}.${css_schema}.gold_zone_traffic_interval_shared`, so disclosure suppression
is enforced at the shared boundary without changing the retired interval meaning.
`interval_start_ts` remains the canonical interval start and `interval_minutes` remains
that interval's duration. A suppressed interval is omitted completely, including its
timing metadata. `opportunity_to_see` is NULL for new rows until the CMN owner approves a
versioned placement-level derivation. The compatibility view does not reproduce the
retired placeholder formula. For new rows, the two legacy-named key columns alias the CSS
shared interval id and hash. That id is derived only from published store id, zone id, UTC
start epoch, and interval duration; it contains no operational interval or device identity.

Operational consumers that are authorized to see measured zero and below-threshold
counts must migrate to `${catalog}.${css_schema}.gold_zone_traffic_current`. External or
partner consumers must migrate to
`${catalog}.${css_schema}.gold_zone_traffic_shared` for daily data or
`${catalog}.${css_schema}.gold_zone_traffic_interval_shared` for interval data.

## Manual cutover procedure

Run this procedure in a controlled change window; it is intentionally not part of the
normal Databricks Asset Bundle deployment.

1. Backfill `sensor_report_interval` and `foot_traffic_interval_detail` from the physical
   CMN table. Build the CSS durable id from `subject_type`, `subject_id`, report type,
   aggregation level, interval length, UTC epoch start, and device id.
2. Validate source/target row counts, unique keys, trading dates, footfall totals, and
   reconstructed dwell numerator/count. Confirm there are no overlapping canonical
   intervals within a series.
3. Copy the legacy CMN keys and stored OTS values into a CMN-owned dated mapping retained
   for the full deprecation window. Do not recompute historical OTS.
4. Rename the physical table to an explicitly dated legacy name. Record that exact name
   in the change ticket and backup catalog.
5. Create the compatibility view from
   `outcome-packages/commerce-media-networks/gold/store_zone_interval.sql` at the original
   fully qualified object name.
6. Re-run the CMN and CSS data-quality suites and smoke-test representative existing
   consumer queries, including ordered-column and type-sensitive reads.
7. Keep the legacy mapping and compatibility view until the published deprecation window
   expires and the CMN owner confirms every consumer has migrated.

## Validation evidence required for approval

- Zero duplicate CSS durable keys and zero canonical-series overlaps.
- Zero duplicate disclosure-safe shared keys; their ids contain only store, zone, UTC
  start epoch, and duration, and their hashes match those ids.
- Footfall totals match by store, zone, and trading date after accounting for disclosed
  suppression at the shared boundary.
- Operational valid zeros remain present in CSS operational views.
- Shared daily zero and below-threshold measures are NULL together with no reconstructive
  columns; suppressed shared interval rows are absent in full.
- Historical OTS values match the legacy mapping exactly; new-row OTS remains NULL.
- The CMN object name, ordered column list, data types, interval starts, and
  interval-duration meanings match the retired DDL.
- New CMN key values match the CSS disclosure-safe shared keys and contain no device id.

Required approvals before production cutover: CSS owner/reviewer, CMN owner,
privacy reviewer for `external_default`, and maintainers for ADRs 0028–0033.
