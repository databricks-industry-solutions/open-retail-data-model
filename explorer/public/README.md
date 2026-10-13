# ORDM Model Explorer

**Live site → https://open-retail-data-model.github.io/model-explorer/**

An interactive, browser-based explorer for the **Open Retail Data Model (ORDM)** — the retail
instance of the Industry Data Model. It lets you navigate the model visually:

- **Canonical core** (silver) — the conformed foundational domains (customer, product, store,
  order, transaction, payment, inventory, supplier, procurement, marketing, logistics, calendar,
  interaction, labor, equipment).
- **Outcome packages** (gold) — business-outcome data products built on top of the core, grouped
  by retail theme.
- **Per-table detail** — columns with types, primary/foreign keys, PII flags, and enum values,
  plus which outcome packages consume which core domains.
- **Links** — each package and domain panel links its glossary and ODCS data contract (served with
  this site) and its source folder on GitHub (which needs access to the ORDM source repository).

## About this repository

This repo hosts **only the built, deployed site** (the `gh-pages` branch). It is **generated and
published automatically** from the ORDM model and its shared DDL parser — **do not edit files here
directly**, they are overwritten on every deploy. The model itself (DDL, contracts, generators) is
maintained in the ORDM project repository.

> This page is the deployed-site view. In the source repo this file lives at `explorer/public/README.md`
> and IS hand-edited there; "do not edit files here" refers to the published `gh-pages` root, not the source.

Everything you see is generated from the model's source of truth (the committed DDL), so the diagram
can never drift from the data model.
