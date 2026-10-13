# ADR 0019 — Media Measurement lands in Data Sharing with Suppliers (reuse, not redefine)

**Status:** Accepted (2026-07-13); amended by [ADR 0021](0021-retail-media-entities-are-gold-not-silver.md)

> Amendment (ADR 0021): this ADR predates the relocation of the retail-media entities out of a silver
> `canonical-core/media` domain. That domain was **deleted** — the conformed dims/facts (`advertiser`,
> `campaign`, `campaign_day`, …) now live in the **gold `commerce-media-networks`** package, not silver.
> The decision below is unchanged: media measurement reuses those objects rather than redefining them. Read
> every "`canonical-core/media`" / "the `media` dimensions" reference below as "the `commerce-media-networks`
> gold dimensions". The FKs from this package's extension tables into those dims are therefore a deliberate,
> layer-legal **gold→gold** dependency: `data-sharing-with-suppliers` deploys *after* `commerce-media-networks`.

## Context
The media-measurement brief defines a supplier-facing publish layer: a supplier×campaign report, an immutable
published snapshot (`mart_supplier_report_snapshot`), and a reporting-entitlement bridge for row-level access.
Its dimensions (supplier_brand, campaign, product) and its measurement facts (media events, attributed
outcomes, incrementality results, campaign×day aggregate) are the SAME conformed objects now in
`canonical-core/media` and the `commerce-media-networks` package (ADR 0017, 0018).

The question: where do the media-measurement supplier-reporting pieces live?

## Decision
Media measurement is the **supplier data-sharing side** of retail media, so its publish + entitlement layer
lands in the existing **`data-sharing-with-suppliers`** outcome package (alongside collaborative category
growth) — **reusing** the `media` dimensions and the `commerce-media-networks` facts rather than redefining any
of them. Three additions:

- `reporting_entitlement` (extension table, SCD2 association) — the row-level access anchor: which governance
  principal may see which advertiser (optionally one campaign) + a minimum disclosure threshold.
- `supplier_media_report_snapshot` (extension table, append-only) — the immutable, versioned freeze of what was
  disclosed to a supplier at a point in time (audit / dispute / reconciliation), sourced from
  `commerce-media-networks.campaign_day`.
- `gold_supplier_media_report` (view) — the entitled live report: `campaign_day` rolled to advertiser ×
  campaign, joined to `reporting_entitlement` so every row carries the `principal_id` allowed to see it (a
  deploy-time row filter narrows it to the querying group). No person-level data; below-threshold rows excluded.

This mirrors the package's existing cross-package pattern (`gold_category_growth` reads promote-with-purpose,
actionable-customer-understanding, and early-risk-detection golds). The media-measurement dims/facts are NOT
re-created here — placement follows §6 (supplier-facing serving/entitlement is single-outcome package content;
the conformed dims/facts are shared and live in media / commerce-media-networks).

## Consequences
- Closes the media-measurement capability by composition — the 7th retail-media brief is modeled with zero new
  dimensions and zero fact redefinition.
- Establishes the entitlement + immutable-publish pattern for supplier data sharing.
- **Deferred (logged):** Lakebase serving projections (`api_supplier_campaign_summary`, `api_user_supplier_map`);
  a UC row-filter function bound to `reporting_entitlement` at deploy; monetization/billing on top of the shared
  reports.
