# Runtime

What runs on a Databricks workspace. The model itself (DDL, gold views, metric views) lives in
[`canonical-core/`](../canonical-core/) and [`outcome-packages/`](../outcome-packages/); this folder
holds what deploys and exercises it.

| Folder | What it is |
|---|---|
| [`synthetic-data/`](synthetic-data/) | Generators and seeds that populate every table with synthetic data, so you can deploy and explore without your own data |
| [`data-quality/`](data-quality/) | `run_checks.py`, which runs every domain's and package's `checks.sql` against a deployed catalog |
| [`examples/`](examples/) | The Databricks Asset Bundle walkthrough (`deploy-with-dab/`) and a notebook that pushes the ODCS contracts to a catalog tool (`notebooks/`) |

The bundle in [`databricks.yml`](../databricks.yml) runs them in order: DDL, synthetic data, then the
data-quality checks. See [`examples/README.md`](examples/README.md) for the walkthrough.
