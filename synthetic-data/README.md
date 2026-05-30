# Synthetic Data

Generators and sample data so adopters can deploy ORDM **without their own data**. All data here is synthetic — no real customer data ever.

| Folder | Purpose |
|---|---|
| `generators/` | Python + dbldatagen scripts that produce synthetic rows for canonical-core entities and outcome packages |
| `samples/` | Small pre-generated samples (Delta / CSV) committed for quick start |
| `seeds.yaml` | Deterministic seeds for reproducible generation |

## Usage

_TODO: generation instructions (dbldatagen on serverless / Databricks Connect)._

## Principles

- Synthetic only — never derived from a real customer dataset
- Deterministic via seeds so samples are reproducible
- Volume-scalable from thousands to millions of rows
