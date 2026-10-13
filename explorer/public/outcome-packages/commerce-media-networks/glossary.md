# Commerce Media Networks — Business Glossary

> Status: 🟢 Review complete (0.5)

Vendor-neutral; follows the ORDM [data model standards](../../docs/data-model-standards.md). The retail-media
FACTS + metrics built on this package's co-located retail-media dimensions (advertiser, campaign, ad_group,
creative, placement, experiment, experiment_cell, delivery_channel, keyword — gold; ADR 0021) + silver marketing
dimensions (promotion, audience per ADR 0022) and core product/store/profile and the sales facts.

## Tables & views

| Object | Grain | Person-level | Description |
|---|---|---|---|
| `advertiser` | one current version per advertiser (SCD2) | no | Thin advertiser/brand dim; FK-reuses silver `supplier` in an advertiser role; brand/agency/finance attributes. **One `brand_name` per row** — a multi-brand supplier has several `advertiser_id` rows sharing one `supplier_sk`, so a supplier-level rollup groups by `supplier_sk`, not `advertiser_id`. |
| `campaign` | one current version per campaign (SCD2) | no | Retail-media campaign: objective, flight dates, budget, buy model, attribution config. |
| `ad_group` | one current version per ad group (SCD2) | no | Targeting/bidding unit within a campaign; targeting mode, bid strategy, optimization goal. |
| `creative` | one current version per creative (SCD2) | no | Ad creative: type, format, approval status, brand-safety class. |
| `placement` | one current version per placement (SCD2) | no | Sellable ad surface / inventory slot (`media_platform`, `ad_product_line`, `device_type`, `placement_type`). Campaign-agnostic — no FK to campaign. |
| `experiment` | one current version per experiment (SCD2) | no | Incrementality test design: type, methodology, unit of assignment, objective metric. |
| `experiment_cell` | one current version per cell (SCD2) | no | Treatment/control/holdout cell of an experiment; traffic allocation. |
| `delivery_channel` | one row per delivery-channel code (Type 1) | no | Coarse distribution channel / environment (`onsite_web`/`offsite`/`in_store_screen`/`dooh`…); IAB Site/App/DOOH axis. |
| `keyword` | one current version per keyword (SCD2) | no | Search bid keyword an ad group targets (`match_type`, status, bid); enables keyword/query-level reporting. |
| `media_event` | one typed ad event | yes (restricted) | Impression/view/click/play spine (event_type discriminates); MRC/IAB viewability + IVT; nullable experiment link; parent link for click→impression. |
| `conversion_event` | one commerce event | yes (restricted) | Paid-attribution measurement projection of the conversion-relevant subset (purchase/atc/pdp/visit/signup) — the clean-room-keyed CVR denominator + `attributed_outcome` FK target. Raw touch occurrence lives in canonical-core `interaction.touchpoint` (ADR 0029); a lineage/dedup reconciliation is a deferred follow-on. |
| `attributed_outcome` | order-line × method × window × touchpoint | yes (restricted) | Conformed attribution: same-SKU/halo/new-to-brand, click-or-view basis, declared windows; gross + net. |
| `incrementality_result` | experiment × snapshot × metric × slice | no (supplier-restricted) | Paired treatment/control results: lift, iROAS, CI, p-value, significance. |
| `campaign_day` | date × brand × campaign × delivery × product × store | no (supplier-safe) | The conformed daily rollup; reconciliation + attribution measures; threshold-suppression flags. |
| `experiment_daily` | experiment × cell × date × slice | no | Intermediate feeding the incrementality readout. |
| `budget_allocation` | allocation × window × level | no | Budget plan (denominator for pacing). |
| `pacing_snapshot` | snapshot_ts × campaign × ad_group × placement | no | Operational pacing state. |
| `experiment_assignment_bridge` | assignment_unit × cell | yes (restricted) | Unit→cell assignment; folds incrementality events onto the shared spine. |
| `product_store_day` | product × store × day | no | Availability + POS; in-stock-weighted impression input. |
| `store_zone_interval` | store × zone × trading date | no (disclosure-controlled aggregate) | **Deprecated exact-name compatibility view.** Reproduces the retired ordered contract from `connected_store_signals.gold_zone_traffic_shared`. New `opportunity_to_see` is NULL pending a governed CMN derivation. |
| `gold_campaign_performance` | campaign × day | no | ROAS/CTR/CVR/iROAS/viewability KPIs. |
| `gold_incrementality_readout` | experiment × metric × slice (latest) | no | Lift/iROAS/CI readout. |
| `gold_pacing_current` | campaign (latest) | no | Current pacing state. |
| `gold_supplier_campaign_report` | brand × campaign | no | Supplier-safe campaign report. |

## Key concepts

- **One typed event, not many tables** — impression/view/click/play/exposure are `event_type` values on
  `media_event`; a click links to its served impression via `parent_media_event_sk` (CTR / IAB linkage).
- **Attribution ≠ conversion** — `conversion_event` is the paid-attribution measurement projection / un-attributed
  CVR denominator (the raw touch *occurrence* lives in canonical-core `interaction.touchpoint`, ADR 0029);
  `attributed_outcome` credits conversions to touchpoints (many-to-one, multi-touch via `attributed_fraction`).
- **Gross AND net, always separate** — never one opaque money metric.
- **Same-SKU vs halo** — `same_sku_flag` (advertised SKU/parent family) vs `halo_flag` (same brand/category, IAB).
- **Incrementality reuse** — nullable `experiment_sk`/`experiment_cell_sk` on the event/conversion/attribution
  facts + `experiment_assignment_bridge` avoid separate incrementality event tables.
- **Privacy tiering** — person-level facts carry hashed `*_key_hash` (PII-tagged + masked) + `consent_status`;
  aggregates are supplier-safe with `privacy_suppressed_flag` threshold suppression. Gold exposes no hashed keys.
- **Placement is campaign-agnostic** — `placement` is a standalone inventory catalog with **no FK to campaign**
  (by design). A campaign BUYS placements, and that link is a *fact* in the outcome layer (e.g.
  `media_event.placement_sk`), so the absent `placement → campaign` FK is intentional, not an omission.
- **Reach / frequency are non-additive** — unique-reach and frequency are deliberately NOT stored on
  `campaign_day`: a summable daily-aggregate column would double-count the same person across days. They are
  computed downstream as `COUNT(DISTINCT customer_key_hash / household_key_hash)` over the person-level
  `media_event` at the required grain (deferred, IAB/MRC-consistent).
- **The four "where an ad ran" axes — pick the right column (IAB / Criteo / AMC).** A bare "channel" is
  overloaded, so this package splits it into four orthogonal, qualified axes (plus the fine on-page slot):
  - **`delivery_channel` dim** (`delivery_channel_sk` on `media_event` / `campaign_day`) — the coarse
    **distribution channel / delivery environment** an exposure occurred in (`onsite_web`, `onsite_app`,
    `offsite`, `in_store_screen`, `in_store_audio`, `dooh`). IAB AdCOM/OpenRTB's Site/App/DOOH axis crossed with
    onsite/offsite/in-store. Single source of truth for the coarse "where the ad ran"; use it for cross-campaign
    environment reporting.
  - **`placement.media_platform`** — the **buying platform / ad network** (the RMN tech platform such as Criteo
    or CitrusAd, or an offsite DSP such as DV360 / The Trade Desk): where the media is bought and managed. No IAB
    standard name; qualified here to avoid the "platform"/"channel" overload.
  - **`placement.device_type`** — the **device platform** (OS/hardware) a placement targets (`desktop`, `mobile`,
    `tablet`, `ctv`). DOOH and in-store surfaces are NOT devices — they live on `delivery_channel`.
  - **`placement.ad_product_line`** — the retailer's **go-to-market ad-product packaging / inventory line**
    (`sponsored_products`, `onsite_display`, `offsite_display`, `email`, `loyalty`), cf. common retail-media ad-product
    taxonomies: what was sold, not where it rendered.
  - **`placement.placement_type`** — the **fine on-page ad surface / slot** (`search`, `product_listing`,
    `banner`, …), IAB's "Ad Placement": the granular surface, distinct from the coarse `delivery_channel`.
  - **Why `placement` does NOT FK to `delivery_channel` (intentional independence).** A fact carries both
    `placement_sk` and `delivery_channel_sk`, complementary and not required to agree: `delivery_channel_sk` is
    stamped independently as the **authoritative runtime channel**, while the placement's axes (media_platform /
    ad_product_line / device_type / placement_type) are planning attributes. Deriving `delivery_channel_sk` from
    the placement would be wrong because (a) they measure different things and (b) **offsite events carry a
    `delivery_channel_sk` with no `placement_sk` at all**, so the channel must live on the event, not be inferred
    from a placement that may not exist.

## Metrics (definitions)

Engine-neutral KPI definitions (materialized by the gold views; a UC Metric View overlay is a later option).
The attributed/outcome KPIs (`roas_net`, `iroas`, `cvr`, `new_to_brand_rate`, `same_sku_share`/`halo_share`) are
reported under the campaign's single configured `attribution_model` — `campaign_day` holds one model per
campaign×day (guarded by `acd_single_attribution_model`), so the gold rollups never mix models; per-touch,
multi-model comparison lives in `attributed_outcome`.

| Metric | Definition | Grain | Expression |
|---|---|---|---|
| `impressions` / `viewable_impressions` | delivered / viewable ad impressions | campaign×day | `SUM(impressions)` / `SUM(viewable_impressions)` |
| `ctr` | click-through rate | campaign×day | `clicks / impressions` |
| `viewable_rate` | viewability rate (MRC/IAB) | campaign×day | `viewable_impressions / impressions` |
| `ivt_rate` | invalid-traffic rate | campaign×day | `invalid_traffic_impressions / gross_impressions` |
| `cvr` | conversion rate | campaign×day | `conversions / clicks` |
| `roas_net` | return on ad spend | campaign×day | `attributed_net_sales / media_spend_net` |
| `iroas` | incremental ROAS | campaign×day / experiment | `incremental_sales / media_spend_net` |
| `lift_pct` | incremental lift | experiment×metric | `(treatment − control) / control × 100` |
| `new_to_brand_rate` | new-to-brand share | campaign×day | `new_to_brand_sales / attributed_net_sales` |
| `same_sku_share` / `halo_share` | attribution mix | campaign×day | `same_sku_sales / attributed_net_sales`, `halo_sales / attributed_net_sales` |
| `pacing_ratio` | budget pacing | campaign (snapshot) | `actual_spend_to_date / planned_spend_to_date` |
| `discrepancy_pct` | measurement reconciliation | campaign×day | `(platform − ad_server) / ad_server × 100` |

## Standards used

| Concept | Standard |
|---|---|
| Viewability, IVT (GIVT/SIVT), OTS | IAB/MRC retail-media & DPB measurement |
| Attribution windows, new-to-brand, same-SKU/halo | IAB retail-media measurement |
| Currency | ISO 4217 (single reporting currency per fact) |
| Dates / timestamps | ISO 8601 (UTC) |

## Deferred (documented)

Lakebase serving projection of pacing; the remaining channel-specific dims (screen_player/contract) as full dimensions — `store_zone`
is no longer deferred, it is a full SCD2 dimension in `connected-store-signals` (ADR 0033), and the supplier entitlement ledger and publish snapshots
ship in `data-sharing-with-suppliers` (`reporting_entitlement`, `supplier_media_report_snapshot`). The `keyword`
(search-targeting) dimension is now included — `media_event.keyword_sk` + the degenerate `search_term_text` carry
query-level reporting, and `attributed_outcome.keyword_sk` carries keyword-level ROAS.
