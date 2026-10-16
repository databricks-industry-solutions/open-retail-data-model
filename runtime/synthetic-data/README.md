# Synthetic Data

Generators and sample data so adopters can deploy ORDM **without their own data**. All data here is synthetic — no real customer data ever.

| Folder          | Purpose                                                                                                                                       |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `generators/` | Python + dbldatagen scripts that produce synthetic rows for canonical-core entities and outcome packages                                      |
| `seeds.yaml`  | Deterministic seeds and per-domain volumes/fanout for reproducible generation                                                                 |

## Usage

Each generator under `generators/` is a plain `.py` that writes synthetic rows for one domain. **Convention: `dbldatagen` is the default engine for every generator.** ORDM sample data is meant to be regenerated at multiple scale factors, up to 1&nbsp;TB and beyond, so build on `dbldatagen` for scale, partition control, and repeatable seeding, as `customer`/`trade_promotion`/`inventory` do. Plain PySpark (`spark.range` + `withColumn`) is acceptable only for a small derived child table where dbldatagen would add no value; when a generator hand-rolls a high-volume entity, expect a reviewer nudge to move it to dbldatagen. Generators only **insert** — the tables must already exist, so the DDL step runs first (see the deploy walkthrough in [`../examples/README.md`](../examples/README.md)).

### 1. Run the whole model (the primary path)

Populate the model as part of the one-shot bundle deploy. The root [`databricks.yml`](../../databricks.yml) `deploy_ordm` job runs the generators in a single serverless `generate_all` task (which topologically sorts them from the registry), in dependency order, after the DDL step and before the data-quality checks:

```bash
databricks bundle deploy -p <your-profile> --var="catalog=<cat>" --var="warehouse_id=<sql-warehouse-id>"
databricks bundle run deploy_ordm -p <your-profile>
```

`dbldatagen` and `pyyaml` are declared as the job's serverless environment dependencies, so there is nothing to install by hand. The `generate_all` task passes only `--catalog ${var.catalog}`; each generator resolves its schema names from the `databricks.yml` `variables` (via the shared `tools/ordm_config` resolver — never hardcoded) and reads its volumes from `seeds.yaml`. Pass a `--<domain>_schema` flag to override a schema name.

### 2. Run a single generator standalone

Because parameters are read via `get_param` in [`generators/_common.py`](generators/_common.py) — **notebook widget → environment variable (uppercased name) → `--flag` / `--flag=value` argv → default** — the same file runs unchanged as a bundle `spark_python_task`, a notebook task, or a local Databricks Connect script. For example, to (re)populate just the customer domain:

```bash
# as a spark_python_task / local run
python3 runtime/synthetic-data/generators/customer.py --catalog <cat> --customer_schema customer --num_profiles 50000 --mode overwrite
```

The same flags become notebook widgets (`catalog`, `customer_schema`, `num_profiles`, `mode`, …) when the file is attached as a notebook task, or env vars (`CATALOG`, `CUSTOMER_SCHEMA`, …).

What each generator writes and reads (all parameters are optional except `catalog`):

<!-- GENERATORS:START (mirrors generators/_registry.py; tests/test_generators_context.py keeps them in sync) -->
| Generator | Writes (schema keys) | Reads (schema keys, written by an earlier generator) |
| --- | --- | --- |
| `customer.py` | `customer` | - |
| `trade_promotion.py` | `calendar`, `marketing`, `product`, `promo`, `store`, `transaction` | - |
| `balancing_margin_and_volume.py` | `bmv` | `calendar`, `inventory`, `product`, `store`, `transaction` |
| `supplier_monitoring.py` | `procurement`, `supplier` | `calendar`, `product`, `store` |
| `inventory.py` | `inventory` | `calendar`, `product`, `store` |
| `customer_ltv.py` | `acu`, `order`, `payment` | `bmv`, `calendar`, `customer`, `marketing`, `product`, `promo`, `store` |
| `logistics.py` | `logistics` | `procurement`, `product`, `store`, `supplier` |
| `early_risk_detection.py` | `risk` | `logistics`, `product` |
| `equipment.py` | `equipment` | `store` |
| `labor.py` | `labor` | `store` |
| `predictive_operations.py` | `predops` | `equipment`, `labor`, `store` |
| `connected_store_signals.py` | `css` | `calendar`, `equipment`, `inventory`, `logistics`, `product`, `store` |
| `commerce_media_networks.py` | `cmn` | `css`, `customer`, `order`, `product`, `store`, `supplier` |
| `data_sharing_with_suppliers.py` | `dss` | `cmn`, `product`, `supplier` |
| `smarter_demand_and_inventory_decisions.py` | `sdi` | `inventory`, `product`, `store`, `transaction` |
| `interaction.py` | `interaction` | `calendar`, `customer`, `product`, `store` |
| `agentic_commerce.py` | `ac` | `customer`, `inventory`, `order`, `product`, `store` |
| `ai_assisted_store_associates.py` | `aasa` | `customer`, `inventory`, `labor`, `product`, `store` |
| `unified_customer_view.py` | `ucv` | `customer`, `marketing` |
<!-- GENERATORS:END -->

Every generator requires `--catalog` and accepts a `--<key>_schema` override for each schema key it writes or reads (for example `--customer_schema`), `--base_currency` where it writes money, and `--mode` (below). Some money columns are labelled `USD` whatever `--base_currency` says: all of them in `labor.py`, `interaction.py`, `balancing_margin_and_volume.py` and `connected_store_signals.py`; the mandate limits and negotiation prices in `agentic_commerce.py`; and the context-event prices in `ai_assisted_store_associates.py`. Two exceptions to `--mode`: `unified_customer_view.py` always overwrites, and `ai_assisted_store_associates.py` always overwrites its associate and action tables while its context-event, fulfillment-status and lookup-audit tables follow `--mode`. The table lists the generators that take volume or other flags, plus `customer_ltv.py`, whose volumes come only from [`seeds.yaml`](seeds.yaml) but which needs a note; every generator not listed takes its volumes only from `seeds.yaml`.

| Generator | Volume overrides (else `seeds.yaml`) | Generator-specific flags |
| --- | --- | --- |
| `customer.py` | `num_profiles`, `num_accounts` | `seed` |
| `trade_promotion.py` | `products`, `stores`, `promotions`, `calendar_weeks` | - |
| `supplier_monitoring.py` | `suppliers`, `lines_per_supplier` | - |
| `inventory.py` | `num_records`, `trailing_days` | `seed` |
| `customer_ltv.py` | (from `seeds.yaml`); invokes `_market_analysis.py` for sparse observations, unmatched items and benchmark restatements | - |
| `ai_assisted_store_associates.py` | (from `seeds.yaml`, including `seed`) | `aasa_anchor_date` |
| `smarter_demand_and_inventory_decisions.py` | (from `seeds.yaml`) | `seed` |


`mode` (default `overwrite`) controls the write into each target table: `overwrite` (idempotent full reload) or `append`. (The shared `_write` helper also supports `merge`, but the shipped generators do not set merge keys, so running a generator with `--mode merge` raises `ValueError` — use `overwrite` or `append`.) Schema-override flags default to the matching `${*_schema}` variable in `databricks.yml`, resolved at run time by the shared `tools/ordm_config` resolver (a hardcoded fallback is used only if `databricks.yml` cannot be read); volume flags that a generator does not expose come from `seeds.yaml`.

### 3. Volumes and seeds

Row counts and fanout live in [`seeds.yaml`](seeds.yaml), one block per domain under the top-level `domains:` key (e.g. `domains.customer.volumes.profiles`, `domains.trade_promotion.volumes.promotions`, `domains.supplier_monitoring.volumes.suppliers`). Each domain also has a fixed `seed`. Generators load these via `load_domain_config` (customer.py uses a `load_seed_config` variant of it); **any param passed at run time overrides `seeds.yaml`**, which is how you scale up for a volume test without editing the file. Generation is deterministic — the **same seed + same row counts produce identical data**, so committed samples and re-runs are reproducible.

### 4. Generator order matters

Several generators read masters written by an earlier one, so order is not arbitrary — a reader that runs before its master lands writes into empty tables and silently produces nothing. An `overwrite` that lands 0 rows prints a loud `[ordm] WARNING … likely an upstream master is unpopulated; check generator ordering`. The `deploy_ordm` job wires the tasks to respect these dependencies, and standalone runs must too — any valid topological order works (see below):

This is a dependency DAG, not a strict chain: the Reads column of the table above is each generator's dependencies, taken from the registry.

A valid run order is any topological sort. The current registry places `balancing_margin_and_volume` before `customer_ltv` because the latter invokes the Market Analysis helper and reads BMV competitor identity; `agentic_commerce` then follows `customer_ltv` because it reads the order schema. The exact order remains derived from `_registry.py`, not hand-maintained here.

This order is **not** hand-maintained — `generate_all` derives it by topologically sorting the declarative registry (`generators/_registry.py`), where each generator declares the schema keys it `provides` and `depends_on`. **Adding a generator:** expose a `run(ctx: DeployContext)` entrypoint (with `main()` as a thin standalone shim) and add a `GenSpec` to `_registry.py` declaring its `provides`/`depends_on`. A generator that is not registered will not run under `generate_all`, even if it exists and imports cleanly.

**Running a subset:** `generate_all` accepts `--include <keys>` (a comma-separated list of schema keys or generator names) to run just those generators plus their transitive upstreams — handy for re-populating one domain locally. The default `deploy_ordm` task passes no `--include`, so it runs the full set; the flag is available for standalone/manual runs.

A domain or outcome package with no generator still gets its schema and tables from the DDL step; it just has no synthetic rows.

## Principles

- Synthetic only — never derived from a real customer dataset
- Deterministic via seeds so samples are reproducible
- Volume-scalable from thousands to millions of rows
