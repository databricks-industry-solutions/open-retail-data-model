# ADR 0018 — Conformed fact layer for Commerce Media Networks (fact-plane dedup)

**Status:** Accepted (2026-07-13)

## Context
The four retail-media briefs (sponsored-products, in-store-digital-ads, cross-platform-retail-mgmt,
incrementality-testing) each define the same fact planes 3–5× with divergent grains and names — impression/
click/play, conversion, attributed sale, incrementality result, campaign×day aggregate, budget/pacing. Built
literally, that is ~25 overlapping fact tables. The `commerce-media-networks` outcome package needs ONE
conformed fact set on the `canonical-core/media` dimensions + core product/store/profile and the sales facts.

## Decision
Adopt a **deduped, conformed fact layer** (11 tables) with these collapses:

1. **One typed `media_event`** — impression / viewable_impression / click / ad_play / video events are
   `event_type` values, not separate tables. A click links to its served impression via `parent_media_event_sk`
   (preserves CTR and IAB click-to-valid-impression). Absorbs SP g_rm_impression+g_rm_click, ISDA playout, MM
   media_event, INCR exposure_event.
2. **Experiment reuse** — nullable `experiment_sk`/`experiment_cell_sk` on `media_event`,
   `conversion_event`, `attributed_outcome` + one `experiment_assignment_bridge` eliminate INCR's
   duplicate exposure/conversion/sale facts. This is the single biggest dedup.
3. **`conversion_event` stays distinct from attribution** — attribution is many-to-one; CVR and
   new-to-brand baselines need the un-attributed denominator (MM's collapse is rejected).
4. **One `attributed_outcome`** (defined 4×) with first-class same-SKU/halo/new-to-brand,
   click-or-view basis, and declared post-click/post-view windows; gross AND net always separate.
5. **One `incrementality_result`** (defined 3×) with paired treatment/control cells and lift/iROAS/CI/
   p-value/significance.
6. **One `campaign_day`** (every brief had one) at the finest common grain with sentinel `ALL` members.
7. Budget/pacing kept as **plan (`budget_allocation`) vs state (`pacing_snapshot`)**; the in-store
   footfall (`store_zone_interval`) and availability (`product_store_day`) stay aggregate estimation
   inputs, not events.

**Engine-neutral** KPI layer: plain gold views (`gold_campaign_performance`, `gold_incrementality_readout`,
`gold_pacing_current`, `gold_supplier_campaign_report`) + glossary metric definitions (ROAS/iROAS/CTR/CVR/
viewability/IVT/lift). **Privacy-tiered**: person-level facts carry hashed `*_key_hash` (`dbx_pii_identifier`,
masked) + `consent_status`; aggregates are supplier-safe with `privacy_suppressed_flag` threshold suppression;
gold exposes no hashed keys (enforced by the `cmn_gold_no_raw_pii` check). Single reporting currency per
monetary fact (`currency_code` + a DQ check).

## Consequences
- Reconciles ~25 brief fact designs into 11 conformed facts + 4 gold views; the retail-media outcomes
  (sponsored/in-store/incrementality/cross-platform) all read one set.
- Person-level facts stay in the one package schema with tags+masks (not a separate restricted schema);
  a restricted-schema split is a documented deploy option.
- **Follow-ups (logged, not blockers):** a synthetic-data generator for the fact layer (NICE — the package
  reaches the MUST tier via sample-queries); UC Metric Views overlay; the supplier entitlement ledger +
  publish snapshots in the data-sharing-with-suppliers package; the channel-specific dims
  (store_zone/screen_player/keyword_target/contract) as full dimensions.
