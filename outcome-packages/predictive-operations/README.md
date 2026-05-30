# Outcome Package — Predictive Operations

> Status: ⚪ Planned · Marketplace listing: planned

## Business outcome

_What this package helps a retailer achieve. (TODO)_

## Contents

The layout is the same in every outcome package. One file per table / per metric view keeps parallel work conflict-free.

| Path | Purpose |
|---|---|
| `tables/<table>.sql` | Outcome-specific extension tables (one file each) |
| `metric-views/<metric>.yml` | One UC Metric View per file (measures, dimensions, joins) |
| `agent-metadata.yml` | Synonyms, display names, glossary terms for Genie / AI-BI |
| `sample-queries.sql` | Example queries |
| `notebook-templates/` | Reusable notebooks |

## Builds on (canonical core)

_List the canonical-core entities this package depends on. (TODO)_

## Design notes

Follows the ORDM [data model principles](../../docs/data-model-principles.md).
