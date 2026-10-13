# ADR 0029 — Conformed omnichannel interaction fact (`interaction.touchpoint`) in the canonical core

**Status:** Accepted (2026-07-27)

Relates to the CDP work ([ADR 0026](0026-cdp-activation-layer-in-ucv.md), [0027](0027-consent-suppression-overlay.md), [0028](0028-cross-plane-do-not-target-and-multi-purpose-gate.md)) and the behavioral-segmentation package (ACU). Adds the one behavioral entity class the CDP audit (design memo `design/54`) found absent repo-wide.

## Context

ORDM modeled customer interactions only in fragments, each single-outcome and none conformed:
- `commerce-media-networks.media_event` — **paid** ad-delivery exposures (hashed clean-room keys).
- `unified-customer-view.campaign_touch` — **owned/CRM** sends (resolved `profile_id`).
- `commerce-media-networks.conversion_event` — the **paid-attribution** conversion denominator.

None is the shared, person-level, un-scoped record of the raw behavioral *occurrence* — the clickstream/interaction time-series that every major CDP models as a first-class class (Adobe XDM `ExperienceEvent`, Salesforce engagement DMOs, mParticle/Segment event streams), separate from the stateful profile. ACU's behavioral traits are consequently **purchase-only** (an inner join to `customer_order_line`); the ACU trait view itself documents the gap in three places (channel-mix "awaits an interaction fact"; `reactivated` lifecycle "deferred to the interaction-fact follow-on"; the purchaser-grain caveat where non-purchasers get no row).

The user also asked that the fact cover **offline** interactions (store visit, call-center, kiosk, offline-marketing/phone activation), not only web/app clickstream, and that there be **one source of truth** for behavioral/conversion events.

## Decision

### 1. One conformed omnichannel fact in the canonical core: `interaction.touchpoint`

Add a new canonical-core domain `interaction` with a single append-only fact `touchpoint`: one row per observed direct customer touch, **online and offline**, unioned by an `interaction_type` + `channel_code` discriminator with nullable role columns (the established ORDM pattern — `media_event` unions impression/click/video, `campaign_touch` unions web/call_center/in_store). Anonymous-first on `device_id_hash`, stitched to `customer.profile` via `identity_link`; offline touches are identity-first. Consent posture per touch is the `granted/denied/unknown` snapshot domain (governance evidence), not the `customer.consent` SCD2 domain. Streaming-ready (`event_timestamp`/`ingest_timestamp`/`latency_seconds`).

**Why the canonical core, not a package or a UCV/ACU-local table** (CONTRIBUTING §6 tree): (a) referenced by more than one outcome — ACU behavioral traits ship a consumer in this PR and UCV segmentation is a documented consumer-in-waiting, with CMN attribution and agentic-commerce as further consumers; note the placement does not rest on the consumer count alone — (b) it is conformed raw data (a fact), and ORDM already homes conformed multi-consumer facts in the core (`transaction.sales`, `order.customer_order_line`); (c) it FKs only outward/upward to `profile`/`identity_link`/`product`/`store`/`fiscal_calendar`, so LAYER-INTEGRITY holds and the core still stands alone. A standalone `cdp`/behavior package would re-create the one-outcome-one-package anti-pattern (ADR 0026); folding into `media_event`/`campaign_touch` was rejected for conflating planes.

**Why one fact, not online + offline split:** the god-table objection is rebutted by ORDM's own precedent (the discriminator + nullable-role pattern above) and the external two-class model (Adobe XDM's single `ExperienceEvent` spans all event types). Digital rows populate `device_id_hash`/`session_id`/`page_url`; offline rows leave those NULL and populate `store_sk`/`channel_code`.

**Channel + source pairing.** `channel_code` is the coarse **medium** (web / mobile_app / in_store / …); `source_application` is the paired **source** — the specific application / property / data stream the touch came from (vendor-neutral degenerate attribute: `ios_app`, `web_desktop`, `loyalty_kiosk`, …), with an enum/domain check. This mirrors how a CDP pairs channel-medium with a source/data-stream on each event (Adobe XDM / Segment), and keeps cross-property reporting (per-app engagement) expressible without overloading `channel_code`.

**Why a new `interaction` domain, not the `customer` domain:** `customer` is a thin master/dim root with zero facts (facts FK into dims, never the reverse); a high-volume append-only touch fact there breaks no-god-tables and the two-class CDP model. `interaction` also leaves room for a future session/device-context sibling. (`interaction.touchpoint`, never `interaction.interaction_event` — ORDM never repeats the domain noun.)

### 2. Single source of truth: re-charter `conversion_event` (doc-only here)

`touchpoint` owns the raw *occurrence* of a customer touch. `commerce-media-networks.conversion_event` is re-chartered from "the raw un-attributed conversion" to the **paid-attribution measurement projection** — the clean-room-keyed, experiment-cell-scoped, money/order-line-enriched subset that serves as `attributed_outcome`'s FK target and the CVR denominator. It keeps its genuinely distinct value (hashed keys, experiment scope, conversion money, hard purchase/signup conversions whose occurrence originates in `order`/registration). Safe to assert now with only documentation: **no gold or metric view reads `conversion_event`** (verified) — its only dependents are `attributed_outcome`'s FK and two DQ checks, all untouched. Physical dedup (a `touchpoint_id` lineage column + generating `conversion_event`'s browse rows from `touchpoint`) is a **deferred CMN follow-on**; today the CMN generator emits only `purchase` conversions, so there is no browse-row duplication to eliminate yet.

## Consequences

- New domain count 13 → 14; new `interaction_schema` token (`databricks.yml` + `tools/ordm_config.py`).
- ACU's `gold_customer_behavioral_attributes` gains a clickstream-derived trait CTE (this PR ships one demonstrating consumer to prove consumability and exercise the anonymous→known stitch); the remaining consumers land in their own package PRs.
- A seeded synthetic generator ships (matching every other core event fact — `equipment_reading`, `media_event`, `conversion_event` all have generators), emitting sessionized anonymous-first sequences with a resolvable fraction, offline touches, and per-touch consent snapshots.
- `conversion_event`'s header/glossary are re-worded to the measurement-projection charter; its enum is left intact (narrowing is part of the deferred follow-on).
- Regenerated artifacts (model.json, ODCS, ER) show the new domain + fact.

## Alternatives considered

- **Digital-only `clickstream_event` now, offline as a later sibling.** Rejected: the user wants one omnichannel source of truth, offline touch is a real gap ORDM only fragmentarily covers, and the discriminator pattern makes one fact clean.
- **Home it in UCV or ACU, or a new customer-behavior package.** Rejected: the fact-in-core precedent (sales / customer_order_line) + FKs-outward-only is sufficient on its own (CONTRIBUTING §6), and more than one outcome consumes it (ACU shipped, UCV documented); a package would trap the shared substrate in one outcome.
- **Physically re-source `conversion_event` from `touchpoint` in this PR.** Deferred: no gold/metric view reads `conversion_event`, the CMN generator emits only purchases today, and coupling PR-B to a CMN generator rewrite adds risk for no v1 benefit.
