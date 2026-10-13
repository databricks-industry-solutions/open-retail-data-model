# ADR 0020 — Broaden `marketing` into the shared-marketing domain (audience)

**Status:** SUPERSEDED (2026-07-14) by [ADR 0021](0021-retail-media-entities-are-gold-not-silver.md) — `marketing` is NOT broadened; it keeps only `promotion`.

> Amendment 2 (2026-07-14) — REVERSED. On review, `audience` turned out to be consumed by
> only ONE outcome: the trade-promotion side was a nullable `promotion.audience_sk` column
> that no trade-promotion fact/gold actually read. Rather than manufacture a second consumer,
> `audience` was moved to the gold `commerce-media-networks` package as a single-outcome
> retail-media dimension (like `delivery_channel`), and `promotion.audience_sk` +
> `fk_promotion_audience` were dropped (a silver `promotion` cannot FK a gold `audience`).
> Net: this ADR's "broaden marketing" decision is fully reversed — `marketing` holds only
> `promotion`; `audience` and the former `device`→`delivery_channel` both live in gold CMN
> (ADR 0021). The analysis below is retained for history.
>
> Amendment 1 (ADR 0021): `device` was re-conceived as the ad-surface dimension (later
> `delivery_channel`) and relocated to gold `commerce-media-networks`.
>
> **Note on `audience` (HISTORICAL — reversed).** This ADR argued `audience` was shared by a second
> outcome (trade promotion, via a `promotion.audience_sk` link and a `gold_promotion_performance_by_audience`
> view). On review that second consumer was **not real** — no trade-promotion fact or gold view ever read
> the column — so `audience` moved to gold `commerce-media-networks` and the promotion link was removed
> (see ADR 0021 amendment 2). The `promotion.audience_sk` column and the named view **no longer exist** in
> the tree; treat the argument below as superseded history.

## Context
ADR 0017 established a separate `canonical-core/media` domain for the retail-media *ad-delivery* dimensions (campaign, ad group, creative, placement, experiment) and kept trade promotion in `marketing` (ADR 0006). External research (Kimball Group primary sources; IAB/MRC Retail Media Measurement Guidelines, Jan 2024) confirmed that decision: retail-media advertising and trade/price-promotion are **distinct business processes** (different grain, facts, ownership) and should stay in separate subject areas, integrated through **conformed dimensions**, not merged.

That same research surfaced two dimensions the model was missing. IAB/MRC list **audience** and **device** as core retail-media reporting dimensions — but they are not *unique* to retail media: an audience/segment can be planned against in trade promotion too, and device/surface (incl. in-store screens) spans channels. Under Kimball's conformed-dimension rule, a dimension shared by ≥2 processes should be **defined once** and reused, not duplicated per process.

The question: where do `audience` and `device` live — in `media`, or in `marketing`?

## Decision
Broaden `marketing` from "the trade-promotion domain" into the **shared-marketing domain**: the home of the conformed dimensions shared across trade promotion *and* retail media. It now owns:

- `promotion` (existing, ADR 0006) — trade-promotion dimension.
- **`audience`** (new) — SCD2 conformed audience/targeting-segment dimension.

(This ADR originally also placed a Type-1 `device` reference dimension here; ADR 0021 moved it to the gold `commerce-media-networks` package as the ad-surface `channel` dim.)

The retail-media ad-delivery dimensions (campaign/ad_group/creative/placement/experiment/advertiser — gold, ADR 0021) **conform to** the shared silver dimensions via FKs rather than redefining them:

- `ad_group` → `marketing.audience` (targeting is set at the ad-group level).
- Commerce Media Networks facts reference `marketing.audience` (an IAB reporting dim) and `marketing.promotion` (so retail-media measurement can control for concurrent price promotions — IAB notes ad-attribution often does not account for promotion); the ad surface is the gold `channel` dim (ADR 0021).

This keeps the two *processes* separate (per ADR 0017 and the research) while placing the genuinely *shared* dimensions in one conformed home — Kimball integration-by-conformance, not integration-by-merge.

## Alternatives considered
- **Put audience/device in `media`.** Rejected: they are not media-specific; trade promotion also targets audiences and spans devices. Housing them in `media` would force trade promotion to reach into a media schema or duplicate them.
- **A separate `audience`/`targeting` domain.** Rejected as premature (minimum-viable): two dimensions do not yet justify a new domain; `marketing` is the natural conformed home and already exists.
- **Merge `media` into `marketing`.** Rejected (ADR 0017 + research): retail-media and trade promotion are distinct business processes; merging creates a "god" subject area.

## Consequences
- `marketing` README/glossary re-scoped to "shared marketing"; `audience`/`device` added with enum CHECKs and DQ checks. No new schema (reuses `marketing`).
- New core→core inbound FKs: `media.ad_group.audience_sk → marketing.audience`, and CMN facts → `marketing.{audience,device,promotion}`. All are inbound-into-dimension, passing `LAYER-INTEGRITY` and `FK-COMPLETENESS`.
- `campaign` naming collision is resolved structurally: `media.campaign` (ad campaign) and `marketing.promotion` (trade-promotion campaign) are distinct entities in distinct domains.
- **Follow-ups (logged, not blockers):** audience/device generation in the trade_promotion generator; potential `audience_sk` on CMN person-level facts for audience-level attribution; revisit whether a dedicated targeting domain is warranted if the shared-dimension set grows.

## References
- ADR 0006 (promotion → marketing core), ADR 0017 (media domain), CONTRIBUTING §6 (placement decision tree).
- Kimball Group: Enterprise Data Warehouse Bus Matrix; "The Matrix: Revisited" (business processes, not org functions); Conformed Dimensions.
- IAB/MRC Retail Media Measurement Guidelines (Jan 2024): device + audience as core reporting dimensions; attribution vs price/promotion.
