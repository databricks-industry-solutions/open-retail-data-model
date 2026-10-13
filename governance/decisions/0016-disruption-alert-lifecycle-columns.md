# ADR-0016: Disruption Alert Lifecycle Columns

- **Status:** Accepted
- **Date:** 2026-07-14
- **Context:** PR #29 review (H1)

## Context

Standards §0 excludes "operational or application write-state tables (preference
overrides, agent feedback, workflow state, and the like)" from what ORDM publishes.
`disruption_alert` includes lifecycle/workflow columns (`alert_status`,
`assigned_to`, `acknowledged_timestamp`, `resolved_timestamp`, `resolution_notes`)
that represent mutable triage state.

## Decision

ORDM publishes the `disruption_alert` table **including** the lifecycle columns as
an adopter-extensible column contract. The rationale:

1. **Column contract, not state ownership.** ORDM defines the schema (column names,
   types, allowed values) so that the `gold_control_tower` view and downstream
   consumers have a stable interface. The adopter's operational tooling owns the
   state transitions (open -> acknowledged -> resolved).

2. **Detection output is the core value.** The detection-output columns
   (`alert_type`, `severity`, `alert_title`, affected entity keys,
   `created_timestamp`) are the ORDM-managed payload. The lifecycle columns are
   extension points that adopters populate via their own triage workflows.

3. **Removing the columns fragments the contract.** If ORDM publishes only the
   detection columns, every adopter independently re-invents the lifecycle schema,
   breaking interoperability across implementations and making the control-tower
   view non-portable.

## Consequences

- The lifecycle columns are clearly marked as "adopter-managed" in DDL comments.
- The synthetic-data generator seeds a realistic mix of statuses for demo purposes.
- `gold_control_tower` filters on `alert_status IN ('open', 'acknowledged')`;
  adopters should default `alert_status` to `'open'` when inserting detection
  outputs so that unmanaged alerts are visible in the control tower.
- This does not set a precedent for general workflow tables in ORDM; it applies
  narrowly to alert lifecycle within outcome packages where the serving view
  depends on the lifecycle schema.
