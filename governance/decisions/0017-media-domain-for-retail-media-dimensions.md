# ADR 0017 — A canonical-core `media` domain for conformed retail-media dimensions

**Status:** Superseded by [ADR 0021](0021-retail-media-entities-are-gold-not-silver.md) (2026-07-14)

> Superseded: the retail-media ad-delivery entities are consumed by only ONE outcome
> (commerce-media-networks; data-sharing-with-suppliers is its publish side), so per the
> silver-core rule (a conformed primitive earns silver only when shared by ≥2 outcomes)
> they belong in the GOLD commerce-media-networks package, not a silver `media` core
> domain. The `media` domain has been removed; `advertiser` (a thin gold dim reusing
> silver `supplier`) and the `channel` ad-surface dim replace `supplier_brand` and
> `device`. See ADR 0021.

## Context
Four retail-media briefs — sponsored-products-placement, in-store-digital-ads, cross-platform-retail-mgmt,
media-measurement — each define the same advertising dimensions (campaign, ad group, creative, placement,
supplier-brand/advertiser) with divergent names and key styles (`g_rm_campaign` natural keys, `dim_campaign`
`_sk`+`_bk`, MM's fused `dim_delivery_context`, etc.). They roll up into two outcome packages
(`commerce-media-networks`, `data-sharing-with-suppliers`), neither of which can be built until one
**conformed** shared-dimension set exists.

Exploration confirmed the canonical core already provides the retail dimensions these facts join to —
`product` (SKU/GTIN/brand), `store`, `supplier`, `profile`, and the `sales` / `customer_order_line` facts —
so those must be **reused, not redefined**. But there is **no advertising/media layer** anywhere in
`canonical-core/`, and `marketing.promotion` is a trade-promotion dimension (POS mechanics + funding), not a
media construct.

## Decision
Add a new **`canonical-core/media`** domain (schema `media`) for the conformed retail-media **dimensions**.

Applying the `CONTRIBUTING.md` §6 placement decision tree:
- **Referenced by >1 outcome?** Yes — commerce-media-networks and data-sharing-with-suppliers.
  > **⚠️ This premise was wrong (see ADR 0021).** `data-sharing-with-suppliers` media-measurement is the
  > *publish side of the same retail-media outcome* (it reads `campaign_day` and the media dims), not an
  > independent second consumer. So this is **one** outcome, not two — the ≥2-outcome test **fails**, and by
  > the same §6 tree these entities belong in the **gold** package, not silver core.
- **Conformed dimension semantics (not metrics)?** Yes — campaign/advertiser identity + attributes; no rollups.
- **No outbound dependency on outcome tables?** Yes — FKs only into core (`supplier`) and within `media`.

All three were read as yes → canonical core. **ADR 0021 corrects the first bullet**, so the outcome is
reversed: the entities move to the gold commerce-media-networks package (advertiser reuses silver `supplier`;
`channel` replaces `device`). The retail-media **facts** (impression, click, conversion, attributed-sale,
incrementality) and **metrics** were always in the outcome packages and remain there. Keeping retail-media and
trade-promotion distinct still holds — that is achieved by conformed dimensions and package boundaries, not by
a silver `media` domain.

Scope (this PR): the conformed retail-media dimensions — `supplier_brand` (the advertiser: core `supplier`
conformed with brand/agency/finance), `campaign`, `ad_group`, `creative`, `placement`, and the incrementality
design dims `experiment` + `experiment_cell` (the test design; results are outcome-package facts).
Channel-specific dims (`store_zone`, `screen_player` — ISDA; `keyword_target` — SP; `contract` — CPRM) are
single-outcome and stay in their packages (§6). (Update: `keyword_target` was subsequently added as the
`keyword` dimension in the gold `commerce-media-networks` package — search/sponsored-products query-level
reporting is core enough to a retail-media network to model in v1; the other three remain deferred.)

`media_schema` is wired through `databricks.yml`, `tools/ordm_config.py`, and the deploy bootstrap.

## Consequences
*(These were the consequences of the original decision. All were unwound by ADR 0021: the `media` domain and
its `media_schema` token were removed, and the entities moved to the gold commerce-media-networks package.)*

- Establishes `media` as the **13th** canonical-core domain (README domain table + count and `docs/architecture.md`
  updated to match). `campaign → supplier_brand → supplier` is a clean core→core inbound-into-dimension FK chain,
  passing LAYER-INTEGRITY and FK-COMPLETENESS.
- The four briefs' `campaign` PK/naming divergences are normalized to the ORDM surrogate `_sk` + durable `_id`
  house style; `finance_account_code` is named `_code` (not `_id`) to stay clear of the FK-completeness scan.
- **Follow-ups (logged, not blockers):** add `ad_group` / `creative` / `placement` (next media PR); offer a
  `delivery_context` view over the normalized dims for MM-style consumers in the package; build the media facts
  in commerce-media-networks / data-sharing-with-suppliers.
