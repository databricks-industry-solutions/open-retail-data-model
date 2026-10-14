# Predictive Operations — Business Glossary

> Status: 🟢 Review complete (0.5) · Last reviewed: 2026-10-07

Business terms for the Predictive Operations outcome package (In-Store Equipment Maintenance, Store Performance, and Workforce Optimization). Vendor-neutral; follows the ORDM [data model standards](https://github.com/databricks-industry-solutions/open-retail-data-model/blob/main/docs/data-model-standards.md).

## Tables & views

| Object | Grain | Description |
|---|---|---|
| `equipment` (canonical-core) | One version per equipment asset (SCD2) | In-store equipment master: refrigeration, HVAC, POS, ovens. |
| `equipment_reading` (canonical-core) | One sensor reading (append-only) | Telemetry data: temperature, power, vibration, error codes. |
| `employee` (canonical-core/labor) | One version per associate (SCD2) | Pseudonymous workforce master (no personal names). |
| `labor_schedule` / `labor_actuals` (canonical-core/labor) | One planned / worked interval | Shift plan and timecards. |
| `work_order` | One work order | Maintenance task header with lifecycle: open to completed. |
| `work_order_line` | One line per work order | Parts, labor, and service charges for a work order. |
| `maintenance_schedule` | One version per schedule entry (SCD2) | Recurring preventive maintenance plan for an equipment asset. |
| `labor_standard` | One version per standard (SCD2) | Versioned workload to labor-hour rules. |
| `workforce_demand_forecast` | Store x date x interval x zone x role | Durable demand forecast lines. |
| `workforce_labor_requirement` | Same grain | Required hours/headcount with coverage rationale. |
| `workforce_schedule_recommendation` | One recommended shift | Scheduler output with constraint-check flags. |
| `workforce_coverage_exception` | One understaffed interval | Unfilled demand with severity and suggested action. |
| `workforce_optimization_run` | One run | Run-level metrics and diagnostics. |
| `gold_equipment_health` | One equipment asset (current) | Health dashboard: latest readings, anomaly stats, health score. |
| `gold_maintenance_effectiveness` | One equipment asset (all time) | Maintenance program effectiveness: PM ratio, MTBF, cost, compliance. |
| `gold_downtime_impact` | One downtime event | Downtime impact analysis: links outages to inventory/spoilage risk. |
| `gold_store_operational_risk` | One store (current as_of_date) | Store Operational Risk Score: composite of domain sub-scores + diagnosis. |
| `store_risk_score` | One store x as_of_date x score_method (append-only) | Durable snapshot history of the risk score a scoring pipeline writes. |
| `gold_workforce_demand_forecast` | Store x date x interval x zone x role | Live heuristic demand forecast (order-interval preferred, sales-profile fallback). |
| `gold_workforce_forecast_accuracy` | Forecast x actual interval | Backtest MAPE/bias when actuals exist. |
| `gold_workforce_labor_requirement` | Same grain | Live labor hours from standards. |
| `gold_workforce_coverage_gap` | Same grain | Required vs scheduled/recommended coverage. |
| `gold_labor_risk` | One store (current) | Labor domain sub-score for the store risk composite. |

## Key terms — Workforce Optimization

| Term | Definition |
|---|---|
| **Labor standard** | Versioned, data-driven rule converting a demand driver into required labor hours and minimum headcount. |
| **Demand driver** | Activity signal used for staffing (transactions, foot traffic, pickups, receiving, open-store coverage). |
| **Required headcount** | Staff needed in an interval after applying labor standards and minimum coverage. |
| **Schedule recommendation** | A proposed shift assignment that passed availability, skill, store, hours-cap, and rest checks in the optimizer run. |
| **Coverage exception** | Explicit record of unfilled demand (never silently dropped), with severity and suggested action. |
| **Labor risk** | Store-grain 0-100 index of near-term understaffing risk from coverage shortfalls (heuristic, not a probability). |
| **Optimization run id** | `optimization_run_id` on the workforce facts references `workforce_optimization_run.run_id`, the run's durable business key. The differing stems are intentional and stable. |

## Key terms — Store Performance

| Term | Definition |
|---|---|
| **Store Operational Risk Score** | A store-grain index (0-100, higher = riskier) estimating near-term operational/financial deterioration over a declared forward horizon. A transparent, expert-weighted heuristic index, not a calibrated probability. |
| **Domain sub-score** | A 0-100 risk score for one signal domain. A missing sub-score is NULL and excluded from the composite denominator (missing = unknown, not safe). CX remains deferred. |
| **Non-compensatory scoring** | Worst-domain floor and steep-sales-decline force prevent a strong domain from averaging away a critical one. |
| **Risk tier** | Categorical triage: UNKNOWN, LOW, MEDIUM, HIGH, CRITICAL. |
| **Top risk domains** | The up-to-3 domains contributing most to the score (the Diagnose step). |
| **Horizon** | The declared forward assessment horizon (horizon_days, 7 in v1). |
| **Score method** | heuristic (shipped deterministic index) or model (adopter pipeline). |

## Key terms — In-Store Equipment Maintenance

| Term | Definition |
|---|---|
| **Work order** | A maintenance task for a specific equipment asset. |
| **Work order line** | An individual cost item within a work order. |
| **Maintenance schedule** | A recurring preventive maintenance plan. |
| **Health score** | 0-100 composite of recent anomalies, errors, and corrective work-order frequency. |
| **MTBF** | Mean time between failures. |
| **Schedule compliance** | Share of active preventive schedules that are not overdue. |
