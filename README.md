# Open Retail Data Model (ORDM)

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE.md)
[![Databricks](https://img.shields.io/badge/Databricks-Unity_Catalog-FF3621?logo=databricks)](https://www.databricks.com)

The **Open Retail Data Model (ORDM)** is an open, Apache-2.0-licensed foundation of reusable retail data assets — canonical entities, semantic models, business glossary, and synthetic data — built together with retail partners, Databricks, and the broader retail community.

It gives retailers, partners, and solution builders a **shared, ready-to-use starting point** so analytics and AI solutions compose instead of being rebuilt from scratch for every project. Adopt it as-is, extend it, or adapt it to your own data landscape.

ORDM is the retail instance of the **Industry Data Model — Open Program (DIDM-OP)**.

## What's inside

| Layer | Folder | What it is |
|---|---|---|
| **Canonical core** | [`canonical-core/`](canonical-core/) | Conformed business entities — Customer, Product, Order, Inventory, Store, Transaction. The shared primitives every outcome builds on. |
| **Outcome packages** | [`outcome-packages/`](outcome-packages/) | One package per retail business outcome (12 in the first wave). Each bundles metric views, semantic metadata, and analytical views on top of the canonical core. |
| **Synthetic data** | [`synthetic-data/`](synthetic-data/) | Generators (Python + dbldatagen) and sample data so you can deploy and explore without your own data. |
| **Examples** | [`examples/`](examples/) | Deployment templates (Databricks Asset Bundle). |

## Architecture at a glance

```
                         ┌──────────────────────────────────┐
                         │  Canonical core                   │  conformed entities
                         │  Customer · Product · Order ·     │  (shared primitives)
                         │  Inventory · Store · Transaction  │
                         └──────────────────────────────────┘
                                          │
                                          ▼
                         ┌──────────────────────────────────┐
                         │  Outcome packages                 │  metric views + semantics
                         │  12 retail outcomes               │  (consumption-ready)
                         └──────────────────────────────────┘
                                          │
                                          ▼
                              Your data & extensions
```

You bring your own source data and ingestion; ORDM provides the conformed model and the outcome-aligned semantics on top. See [`docs/architecture.md`](docs/architecture.md).

## The 12 retail outcomes (first wave)

**Respond & Predict to Customer Behavior**
- [Unified Customer View](outcome-packages/unified-customer-view/)
- [Actionable Customer Understanding](outcome-packages/actionable-customer-understanding/)
- [Agentic Commerce](outcome-packages/agentic-commerce/)
- [Commerce Media Networks](outcome-packages/commerce-media-networks/)

**Profitable Volume Growth**
- [Balancing Margin and Volume](outcome-packages/balancing-margin-and-volume/)
- [Promote with Purpose](outcome-packages/promote-with-purpose/)

**Collaborative Supply Chain**
- [Early Risk Detection](outcome-packages/early-risk-detection/)
- [Smarter Demand and Inventory Decisions](outcome-packages/smarter-demand-and-inventory-decisions/)
- [Data Sharing with Suppliers](outcome-packages/data-sharing-with-suppliers/)

**Intelligent In-Store Experience**
- [Connected Store Signals](outcome-packages/connected-store-signals/)
- [Predictive Operations](outcome-packages/predictive-operations/)
- [AI-Assisted Store Associates](outcome-packages/ai-assisted-store-associates/)

## Getting started

1. **Explore the model** — browse [`canonical-core/`](canonical-core/) for the core entities and [`outcome-packages/`](outcome-packages/) for outcome-aligned metrics.
2. **Try it with synthetic data** — use [`synthetic-data/`](synthetic-data/) to populate the model in your own Databricks workspace, no source data required.
3. **Deploy** — the [`examples/deploy-with-dab/`](examples/) Databricks Asset Bundle deploys the canonical core and an outcome package to Unity Catalog.
4. **Adapt to your data** — map your existing sources to the canonical core, then build on the outcome packages.

## Adapting ORDM to your data

Most retailers don't start from a clean slate. The **Vibe Modeling Agent** is a companion open-source tool that helps adapt ORDM to your existing data landscape — your naming, your source systems, your custom entities — keeping what fits and customizing what doesn't. See [`docs/vibe-modeling-integration.md`](docs/vibe-modeling-integration.md).

## Documentation

- [Architecture](docs/architecture.md) — the layered model in detail
- [Data model principles](docs/data-model-principles.md) — the design conventions ORDM follows
- [Retail outcome map](docs/outcome-map.md) — the 12 outcomes
- [Adapting ORDM with the Vibe Modeling Agent](docs/vibe-modeling-integration.md)
- [FAQ](docs/faq.md)

## Contributing

ORDM is built collaboratively and we welcome input from the retail community. Open an **issue** to report a problem or suggest an improvement, or open a **pull request** to propose changes. Accepted code/content contributions may require signing a Contributor License Agreement (CLA) — we'll guide you through it on your first PR.

## License

ORDM is released under the **Apache License 2.0** — chosen so partners and customers can freely adopt, extend, and build on the model. See [LICENSE.md](LICENSE.md).

## Acknowledgments

ORDM is built **partners first** — our retail solution partners and domain experts lead the way, with Databricks and the broader retail community building alongside them. Independently authored; not a redistribution of any third-party proprietary data model. See [NOTICE.md](NOTICE.md).
