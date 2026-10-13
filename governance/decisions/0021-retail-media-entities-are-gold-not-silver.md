# ADR 0021 — Retail-media ad-delivery entities are GOLD (outcome-package), not a silver core domain

**Status:** Accepted (2026-07-14)

Supersedes [ADR 0017](0017-media-domain-for-retail-media-dimensions.md); amends [ADR 0020](0020-broaden-marketing-shared-dimensions.md).

> Amendment (2026-07-14) — four-axis "where an ad ran" untangle. This ADR originally introduced the ad-surface
> dimension under the name `channel` (renaming the colliding `device`). Review + a deep-research pass over IAB
> AdCOM/OpenRTB, Criteo, Amazon Marketing Cloud, and Kimball showed a bare `channel` is overloaded and that
> "where an ad ran" is really **four orthogonal axes**. The dimension is therefore renamed and the placement
> attributes are re-scoped:
> - **`delivery_channel`** (renamed from `channel`) — the coarse distribution channel / delivery environment
>   (onsite_web / offsite / dooh / in_store_screen…); IAB AdCOM/OpenRTB Site/App/DOOH × onsite/offsite/in-store.
> - **`placement.media_platform`** (renamed from `platform_name`) — the buying platform / ad network (coined
>   qualified name; IAB models publisher/exchange, not the demand-side platform).
> - **`placement.device_type`** — the device platform; **pruned** of `dooh`/`in_store_screen` (those are channels,
>   not devices, per IAB).
> - **`placement.ad_product_line`** (renamed from `placement.channel`) — the retailer go-to-market ad-product
>   packaging (sponsored_products / onsite_display / offsite_display / email / loyalty), cf. AMC `ad_product_type`.
>
> `placement.placement_type` remains the fine on-page ad surface / slot (IAB "Ad Placement"). The GOLD placement
> decision below is unchanged; read every `channel` reference below as `delivery_channel`. See the
> memory/research note for the cited sources.
>
> Amendment 2 (2026-07-14) — `audience` is also gold here. ADR 0020 had kept `audience` in silver `marketing`
> on a ≥2-outcome premise (retail media + trade promotion). On review the trade-promotion consumer was not real
> (a nullable `promotion.audience_sk` that no fact/gold read), so `audience` was moved into this gold package as a
> single-outcome retail-media dimension and `promotion.audience_sk` / `fk_promotion_audience` were dropped. ADR 0020
> is superseded; `marketing` now holds only `promotion`.

## Context
ADR 0017 created a silver `canonical-core/media` domain for the conformed retail-media
dimensions (`supplier_brand`/advertiser, `campaign`, `ad_group`, `creative`, `placement`,
`experiment`, `experiment_cell`), on the premise that they are shared by **two** outcome
packages: `commerce-media-networks` (CMN) and `data-sharing-with-suppliers` (DSS).

On review that premise does not hold. DSS is not an independent consumer of these
entities — it is the **publish/entitlement side of the same retail-media outcome**: it
freezes and row-filters the CMN `campaign_day` aggregate for supplier disclosure. So
the ad-delivery entities are consumed by exactly **one** outcome. The ORDM placement rule
(CONTRIBUTING §6) is explicit: the silver core is the set of **conformed primitives shared
by ≥2 outcomes**; single-outcome constructs are **gold** (outcome-specific). A silver
domain that serves one outcome contradicts "keep the silver core thin, push breadth into
outcome packages."

Two further problems with the silver placement:
1. **advertiser** was modeled as a new silver master (`supplier_brand`) even though it is
   just the silver `supplier` seen in an advertiser role — a second party master for one
   entity, which §6a forbids.
2. **device** (ADR 0020) collided by name and concept with Connected Store Signals'
   physical `sensor_device`. The retail-media construct is an ad **surface** (onsite/
   offsite/in-store screen/DOOH), not a device-type lookup.

## Decision
Remove the silver `canonical-core/media` domain. Relocate its dimensions into the **gold
`commerce-media-networks` package** (`outcome-packages/commerce-media-networks/tables/`),
alongside the facts that already live there:

- `campaign`, `ad_group`, `creative`, `placement`, `experiment`, `experiment_cell` — moved
  verbatim (SCD2, `dbx_data_type='master'`), now in the `cmn` schema.
- `supplier_brand` → **`advertiser`**: a **thin gold dimension** that FKs to the silver
  `supplier` (reuse supplier in an advertiser role; no new advertiser master in silver).
  It keeps only the advertiser-role attributes (brand, agency, finance account, billing
  currency, relationship type, status) plus the `supplier_sk`/`supplier_id` reuse keys.
- `device` → **`channel`**: re-conceived as the ad-**surface** reference dim (Type 1;
  `channel_category` ∈ {onsite_web, onsite_app, offsite, in_store_screen, in_store_audio,
  dooh, other}), distinct from Connected Store Signals' physical `sensor_device`.

`audience` and `promotion` **stay** in silver `marketing` — they are genuinely shared by
≥2 outcomes (trade promotion + retail media), so the ADR 0020 conformed-dimension
rationale still applies to them. CMN facts and `ad_group` conform to them via gold→silver
FKs.

### Why this is layer-legal
- A `master`-tagged dimension **is** allowed inside a gold outcome package (precedent:
  `outcome-packages/balancing-margin-and-volume/tables/competitor.sql`).
- `PK-CONTRACT` and `FK-COMPLETENESS` are canonical-core-only gates, so gold dims are not
  subject to them.
- `LAYER-INTEGRITY` forbids only **core→gold** FKs. The new FKs are gold→silver
  (`advertiser → supplier`, `ad_group → marketing.audience`, facts → `marketing.promotion`)
  and are fine.

## Consequences
- `canonical-core/media` is deleted; the `media_schema` token is removed from
  `databricks.yml`, `tools/ordm_config.py`, and the deploy bootstrap. Canonical core drops
  from 13 to 12 domains.
- The retail-media dimension DDL/relationships/checks are consolidated into the CMN
  package; the CMN facts and gold views repoint FK columns `supplier_brand_* → advertiser_*`
  and `device_* → channel_*`. DSS repoints its entitlement/snapshot FKs to `cmn.advertiser`.
- The media generator folds into the CMN generator (dims built into `cmn` before the
  facts); the `media` GenSpec is removed from the synthetic-data registry.
- No behavioral change to the conformed semantics — only the layer/home changes.

## References
- ADR 0017 (silver media domain — superseded), ADR 0020 (audience stays silver; device →
  channel gold), CONTRIBUTING §6 (core-versus-outcome placement; "keep the silver core
  thin"), §6a (one entity = one owning file; do not stand up a second party master).
