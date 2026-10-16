# Examples

Deployment templates and walkthroughs for adopting ORDM in a Databricks workspace.

| Folder | Purpose |
|---|---|
| `deploy-with-dab/` | The schema-bootstrap step (`00_bootstrap_schemas.sql`). The bundle config itself is the root [`databricks.yml`](../../databricks.yml) `deploy_ordm` job. |
| `notebooks/` | `push_contracts_to_ontos.ipynb`: pushes the generated ODCS contracts to a catalog tool (optional; see [`docs/odcs-integration.md`](../../docs/odcs-integration.md)). |

## Deploying ORDM today

The repo ships as **tokenized SQL + Python generators**, deployed via the [Databricks Asset Bundle](https://docs.databricks.com/aws/en/dev-tools/bundles/) defined in the root [`databricks.yml`](../../databricks.yml). All catalog/schema names come from that bundle's `variables` — nothing is hardcoded.

The whole deploy is one bundle job. Set your catalog and a SQL warehouse in `databricks.yml` (`catalog` — separate deployments should target *different* catalogs, principle #14; `warehouse_id` — the DDL runs there, see below; the `*_schema` and `base_currency` defaults rarely need changing), then:

```bash
databricks bundle deploy -p <your-profile> --var="catalog=<cat>" --var="warehouse_id=<sql-warehouse-id>"
databricks bundle run deploy_ordm -p <your-profile>
```

The `deploy_ordm` job (root [`databricks.yml`](../../databricks.yml)) chains, in dependency order:

1. **DDL** — [`tools/apply_model_ddl.py`](../../tools/apply_model_ddl.py) applies, in order, the schema bootstrap ([`deploy-with-dab/00_bootstrap_schemas.sql`](deploy-with-dab/00_bootstrap_schemas.sql), one UC schema per domain/package + Predictive Optimization), then `canonical-core/*/tables/*.sql`, the per-domain `relationships.sql`, `outcome-packages/*/tables/*.sql` + `relationships.sql`, the `gold/*.sql` views (incl. materialized views), the `metric-views/*.sql` (UC metric views), and finally the `comments.sql` column documentation (for plain gold views those column comments are folded into the view's `CREATE OR REPLACE VIEW` column list in the gold phase; only tables, materialized views and views that cannot be rewritten keep separate `COMMENT ON COLUMN` statements). It resolves `${catalog}` / `${*_schema}` with the same resolver the tests use (`tools/ordm_config.py`) and tolerates re-runs (`CREATE ... IF NOT EXISTS`; already-added constraints skipped). **All DDL runs on the SQL warehouse** (`--warehouse ${var.warehouse_id}`): materialized views only create cleanly on a warehouse (not on serverless generic compute, where their async refresh is unreliable), and DBSQL handles the physical DDL too: one engine, portable, no workspace preview needed. Within each phase, independent files are applied **concurrently** (`--max_workers`, default 16); statements stay ordered inside a file, so a table's `CREATE` always precedes its `SET TAGS` and same-table DDL never races. The committed SQL is byte-identical; only the apply order changes.

   **Apply-time flags** (all default to the pre-parallel behaviour, so nothing changes unless you pass them):

   | Flag | Default | What it does |
   |---|---|---|
   | `--max_workers <N>` | `16` | Parallel apply within a phase. A unit is an independent group whose statements stay ordered: a file, or a per-target-table regroup for relationships and comments (so same-table DDL stays serial). |
   | `--demote-materialized` | off | Rewrites the materialized views (across all outcome packages) to plain `CREATE OR REPLACE VIEW` statements. **Demo/dev only:** the synthetic data is tiny so nothing needs materialization, and plain views avoid the empty-MV-refresh trap (MVs are created against empty tables at apply time, before data loads). For a serving/prod deploy, leave it off so the MVs stay materialized and refresh them after data loads. The `deploy_ordm` job wires this on the (single) dev/demo target. |
   | `--domains` | (all) | Comma-separated domain/package labels to scope the deploy to those domains only (plus the always-on schema bootstrap). Any outcome package auto-includes all canonical-core, plus (transitively) any sibling outcome package whose gold it reads. Useful for scoped testing; omit or leave empty for a full deploy. |
   | `--profile` | off | Emits per-statement and per-phase timing (each phase shows `elapsed`, the wall-clock span, beside `total`, the summed statement time; read `elapsed`, because `total` over-counts under parallelism), plus each statement's `statement_id` so you can join to Query History. |

   **Warehouse concurrency tip (empirically confirmed):** a SQL warehouse admits ~10 concurrent queries **per cluster**, so effective parallelism is bounded by cluster **count**, not warehouse **size** — a bigger warehouse size buys ~zero extra concurrency for these metadata-bound DDL/comment ops (a `COMMENT ON COLUMN` is a near-zero-compute metadata commit; and comments on tables and materialized views are still one statement per column, so that remaining comments phase is many tiny statements whose lever is concurrency; plain gold views take their comments on the CREATE, which cut the model's 1,213 comment statements to 223). **Set `min_num_clusters >= 3`, not just `max`**: the apply/DQ phases are short bursts and autoscale is laggy (adds clusters over minutes), so a warehouse left at `min=1` never scales up mid-burst and extra workers just deepen the queue (measured: 32 workers on a `min=1` warehouse was *slower* than 16). Pre-warm the clusters and **match** `--max_workers` / `--max_parallel` to them (~24 for 3 clusters); going above the admit ceiling is counter-productive. The bundle ships a **fail-safe `16`** (safe on any warehouse, including an un-scaled `min=1` one the bundle can't enforce); opt **up** to ~24 only after you've pre-warmed to `min_num_clusters >= 3`. Keep the size **Small** unless a compute-heavy phase (gold / metric views) proves it needs more. Auto-stop returns it to `min` afterward. Tune this on the warehouse you pass as `warehouse_id` (the bundle does not own a warehouse resource).
2. **Populate** — the [synthetic-data generators](../synthetic-data/) (on Spark) for the domains that ship one.
3. **Refresh gold** — `refresh_gold_tables` runs [`tools/apply_model_ddl.py`](../../tools/apply_model_ddl.py) once more for the physical gold snapshot tables, so they hold this run's synthetic rows rather than the empty snapshot taken during the DDL step.
4. **Validate** — [`runtime/data-quality/run_checks.py`](../data-quality/run_checks.py) (on Spark, report-only in the demo deploy).

Each `.py` reads `--catalog`/`--warehouse` (and any `${*_schema}` override) via `get_param`, so the same files run as a bundle task, a notebook, or locally. Preview the DDL without a workspace: `python3 tools/apply_model_ddl.py --catalog <cat> --dry_run true`.

> **Scope & requirements:** the DDL (tables, relationships, gold, materialized views, metric views, comments), generators, and DQ are wired. Requires a **serverless SQL warehouse** and, for metric views, **DBR 17.3+**. **PII masks** (`canonical-core/*/masks.sql`) are intentionally **excluded** (documented, not silent): `SET MASK` needs the `pii_readers` account group + ABAC grants to exist first, so masks are applied out-of-band.

## Tearing it down

To remove everything the bundle deployed, run the teardown helper (it acts on this repository's bundle wherever you run it from):

```bash
./runtime/examples/deploy-with-dab/cleanup.sh -p <your-profile>
```

It shows `databricks bundle summary`, asks for confirmation, then runs `databricks bundle destroy`. Pass the same profile you deployed with (`-p`), and the target with `-t` if you deployed a non-default one: destroy acts on whatever workspace that profile points at.
