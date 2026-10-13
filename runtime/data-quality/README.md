# Data-quality framework

Lightweight, SQL-first data-quality assertions for the ORDM canonical core. Each new table ships a check here (ORDM contribution bar).

## How it works

- **Checks are domain-local.** Each domain owns `canonical-core/<domain>/checks.sql` (alongside its `tables/`, `glossary.md`, `relationships.sql`). Keeping checks next to the model keeps parallel work conflict-free.
- **An assertion is a query that returns the violating rows.** `0 rows = PASS`. There is no separate expectations DSL to learn — if you can write the SQL that finds bad rows, you can write a check.
- **The runner** (`run_checks.py`) discovers every `canonical-core/*/checks.sql` **and** `outcome-packages/*/checks.sql`, resolves `${catalog}` (parameter) and the `${<domain>_schema}` tokens via the shared resolver (`tools/ordm_config.py`, which reads `databricks.yml`), runs each assertion with `spark.sql`, and **fails the run if any `error`-severity check returns rows**. `warn`-severity checks are reported but non-fatal; `metric`-severity checks report a value and never fail.
- **Scale:** each error/warn check is `COUNT(*)`-wrapped so the count is computed in-engine (no rows shipped to the driver), and checks run **concurrently** against one Spark session (thread pool, `max_parallel` param, default 8) instead of ~100 strictly-sequential jobs.

## Always-on enforcement (complementary)

The runner is a post-hoc scan. For invariants that should be enforced at **write** time, the model also uses Databricks-native guardrails:

- **Delta `CHECK` constraints** — enforced bounds added in the `relationships.sql` files (e.g. `sales` non-negative measures, `purchase_order_line` `received_qty <= ordered_qty`, `promotion.supplier_share_pct` in `[0,100]`). A bad write is rejected, not just reported later.
- **UC column masks** — `canonical-core/customer/masks.sql` masks the `dbx_pii_*` columns so PII is hidden by default (`pii_readers` group only).
- For continuous monitoring of a deployed table, **Lakehouse Monitoring** / **Lakeflow Declarative Pipeline expectations** are the managed options on top of these.

## Check format

```sql
-- check: <name> | severity: error|warn
-- <one-line description>
SELECT ...        -- returns violating rows
;                 -- terminating semicolon
```

## Running it

As a Databricks notebook/job task (`notebook_path: runtime/data-quality/run_checks.py`) with parameters:

| Parameter | Required | Default | Meaning |
|---|---|---|---|
| `catalog` | yes | — | Target Unity Catalog. Never hardcoded (guardrail #1). |
| `domains` | no | all | Comma-separated domains to check (e.g. `customer`). |
| `fail_on` | no | `error` | `error`, or `warn` to also fail on warnings. |
| `max_parallel` | no | `8` | Max checks executed concurrently against the Spark session. |

Run it **after** the synthetic-data generators, as a downstream task in the same job.

## Coverage convention

Every table gets, at minimum: mandatory-key not-null, business-key uniqueness among current rows (SCD2), enum-domain membership for coded columns, referential integrity (no FK orphans), and SCD2 date-window sanity. Static structural checks (column contracts, enum/DDL parity, no hardcoded identifiers) live in `tests/` and run without a cluster.
