# ADR 0043 — Canonical-core `labor` domain unlocks Predictive Operations: Workforce Optimization

**Status:** Accepted (2026-08-10)

## Context

[ADR 0028](0028-predictive-operations-store-risk.md) deferred the Store Operational
Risk Score's `labor_risk` sub-score and the **Workforce Optimization** use case
until a conformed `canonical-core/labor` domain landed
(`employee` / `labor_schedule` / `labor_actuals`). The same primitives are also
required by the planned `ai-assisted-store-associates` package, so they belong
in the shared core rather than as predictive-operations-only extensions.

Workforce Optimization needs more than three bare facts: skill eligibility,
availability windows, multi-store eligibility, and versioned labor standards
(workload → hours). Those are still conformed workforce primitives (reused by
multiple outcomes), so they ship in core; forecast/recommendation *outputs*
stay in the `predictive_operations` outcome schema.

ORDM trains and serves no models. Demand forecasts and schedule recommendations
are governed Delta facts an adopter pipeline writes; the package ships
transparent SQL heuristic gold views plus a deterministic greedy scheduling
reference (tests + notebook template) that can later be swapped for an exact
solver without changing the data contract.

## Decision

### 1. Canonical-core `labor` schema

Add `labor_schema` (default `labor`) and the domain tables:

| Table | Type | Grain |
|---|---|---|
| `employee` | Master (SCD2) | One current row per associate (pseudonymous IDs; no names/PII) |
| `employee_skill` | Transactional bridge | Employee × skill_code eligibility |
| `employee_availability` | Transactional | Employee × date × availability window |
| `employee_store_eligibility` | Transactional bridge | Employee × store eligibility |
| `labor_schedule` | Transactional | Planned shift (employee × store × role × interval) |
| `labor_actuals` | Transactional | Worked / timecard interval |

Employee carries role, employment status, hourly labor cost (unit-grain
`DECIMAL(18,4)`), max daily/weekly hours, and minimum rest hours between
shifts. No personal names, contact, or DOB — IDs only.

### 2. Workforce Optimization lives in `predictive_operations`

Extension tables (append-only / config) in `predops_schema`:

- `labor_standard` — versioned, data-driven workload→labor rules
- `workforce_demand_forecast`
- `workforce_labor_requirement`
- `workforce_schedule_recommendation`
- `workforce_coverage_exception`
- `workforce_optimization_run`

Gold views compute heuristic demand features, labor hours from standards,
coverage gaps, and the `labor_risk` sub-score. The Store Operational Risk Score
includes `labor_risk` in the composite denominator when present (weight 15);
`cx_risk` remains deferred/NULL.

### 3. Honesty and legal framing

- Forecast method in gold is a **seasonal same-day-of-week rolling average** with
  hierarchical fallback (store×role×slot → role×slot → global slot). Not a
  calibrated ML forecast.
- Schedule recommendations from the shipped reference are a **deterministic
  greedy heuristic** with a documented interface for an exact solver later.
- Labor-law / jurisdiction rules are **configuration**, not claimed compliance.
  Adopters must review standards and constraints for their jurisdiction.

### 4. Demand grain

Default analytical grain:

`store_id × business_date × interval_start × department_or_zone × role_code`

Default interval length: **30 minutes**, configurable via `labor_standard.interval_minutes`.
Canonical `sales` is day-grain; the heuristic gold spreads daily transaction
volume across open intervals with a fixed intra-day profile when finer signals
are absent. When `customer_order_line.event_timestamp` or Connected Store
Signals foot-traffic intervals are available, adopters should prefer those
drivers (documented; gold remains sales-backed so the package does not hard-
depend on CSS deploy order).

## Consequences

- Workforce Optimization use-case status flips to `done` once artifacts land.
- `srs_deferred_subscores_null` is narrowed to `cx_risk` only; `labor_risk` may
  be non-NULL.
- Synthetic `labor` generator must run before predictive-operations when seeding
  workforce tables / labor_risk.
- Design spec:
  [`docs/design/predictive-operations/workforce-optimization.md`](../../docs/design/predictive-operations/workforce-optimization.md).
