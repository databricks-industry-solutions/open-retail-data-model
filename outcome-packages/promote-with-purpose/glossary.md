# Promote with Purpose — Business Glossary

> Status: ✅ Published (0.5) · Last reviewed: 2026-10-07

Business terms for the Trade Promotion and Location-Based Offers use cases. Vendor-neutral; follows the ORDM [data model principles](../../docs/data-model-standards.md).

> **Privacy invariant (Location-Based Offers).** No raw coordinates, no device
> identifiers, and no customer location trails appear anywhere in this use case.
> Location is modeled only as membership in a defined zone; customers appear only
> as pseudonymous keys; and every delivery-class event carries a consent
> verification flag. This deliberately extends the model's existing pattern of
> concentrating PII in the customer core.

## Tables & view

| Object | Grain | Description |
|---|---|---|
| `promotion` | One version per promotion (SCD2) | The conformed trade-promotion dimension — now in [`canonical-core/marketing`](../../canonical-core/marketing/glossary.md); this package consumes it. |
| `promotion_scope` | One (promotion, product, store) | The product × store coverage of each promotion. |
| `gold_trade_promotion` | One (promotion, product, store, fiscal week) | Consumable view tying promoted sales, allocated trade spend, planned lift, and a trailing-demand baseline together. |
| `gold_weekly_baseline` | One (product, store, fiscal week) | Reusable building block: actual sales + the trailing non-promoted baseline. Single home for the baseline definition. |
| `gold_promo_performance` | One per promotion | Operational "did it sell?" summary: scope, promoted units/revenue, baseline, planned vs realized lift. |
| `gold_promo_roi` | One per promotion | Financial "did it pay off?": incremental units/margin, ROI on trade spend, realized vs planned lift, cannibalization, forward buy, net incremental margin. |
| `gold_promo_roi_by_category` | One (promotion, category) | Drill grain of `gold_promo_roi`. |
| `offer_zone` | One version per zone (SCD2) | A defined location zone (membership only) an offer can attach to; centroid stored as a coarse 7-char geohash. |
| `location_offer` | One per configured offer | A location-triggered offer definition: promotion, zone, trigger, frequency/suppression rules, delivery channel. |
| `offer_event` | One per offer event | Delivery/engagement event log (triggered, suppressed, delivered, opened, redeemed); pseudonymous customer key, consent-verified deliveries. |
| `gold_location_offer_performance` | One (location offer, store, fiscal week) | Weekly offer funnel counts, delivery/open/redemption/suppression rates, and redemption-attributed sales. |
| `gold_zone_engagement_weekly` | One (zone, fiscal week) | Weekly zone-level engagement: active offers, triggers, unique customers, conversion rate. Keyed on the durable `zone_id`. |

## Terms

| Term | Definition |
|---|---|
| **Trade promotion** | A time-bound, funded offer a retailer runs on specific products in specific stores (e.g. a temporary price reduction or a feature/display) to drive incremental volume. Modeled as one structured `promotion` row with its mechanics, funding, scope, planned lift, and run dates. |
| **Promo mechanics** (`promo_type`) | *How* the promotion is presented to the shopper. Allowed values: `TPR` (temporary price reduction), `FEATURE` (advertised in a flyer/circular), `DISPLAY` (special in-store placement), `FEATURE_AND_DISPLAY`, `BOGO` (buy-one-get-one), `COUPON`, `BUNDLE`. |
| **Funding type** (`funding_type`) | *How the money flows* for the trade deal. Allowed values: `OFF_INVOICE` (deducted on the purchase invoice), `BILL_BACK` (retailer bills the supplier after the fact), `SCAN_DOWN` (per-unit allowance on scanned sales), `LUMP_SUM` (fixed payment). |
| **Funded by** (`funded_by`) | Which party bears the promotional cost: `SUPPLIER`, `RETAILER`, or `SHARED`. When not solely `RETAILER`, `supplier_share_pct` records the supplier's percentage. |
| **Baseline** (`baseline_units`) | The expected non-promoted demand used to judge incremental lift. ORDM defines it as the mean weekly units over the trailing 8 **non-promoted** fiscal weeks for the same product × store; NULL when fewer than 4 such weeks are available. |
| **Planned lift** (`planned_lift_pct`) | The incremental unit uplift, as a percent over baseline, the promotion is expected to deliver. |
| **Trade spend** (`planned_trade_spend`) | The planned promotional investment for the promotion. In `gold_trade_promotion` it is allocated evenly across the promotion's scope (products × stores) and fiscal weeks. |
| **Promotion scope** | The set of products and stores a promotion applies to (`promotion_scope`). |
| **NO_PROMO member** | The reserved `promotion` row (`promo_id = 'NO_PROMO'`) that non-promoted sales are attributed to, so the sales fact always resolves to a real promotion surrogate. |
| **Incremental volume** (`incremental_units`) | Promoted units minus baseline units over the promo window: the extra volume the promotion drove. Not clamped — a negative value means the promotion sold *below* its baseline. |
| **Lift** | The percentage uplift over baseline. **Planned lift** (`planned_lift_pct`) is the forecast; **realized lift** (`realized_lift_pct = 100 × incremental_units / baseline_units`) is what actually happened. Their gap is the lift variance. |
| **ROI** (`roi`) | Return on trade investment = `incremental_margin / trade_spend`. NULL-safe: NULL when trade spend is 0/NULL (never a divide-by-zero). |
| **Cannibalization** (`cannibalization_units` / `_margin`) | Lost volume/margin on **substitute SKUs** — same category, **not** on the promotion, in the promo's stores during the window — that dipped below their own baseline because shoppers switched to the promoted item. |
| **Forward buy / pantry loading** (`forward_buy_units` / `_margin`) | Lost volume/margin from the **promoted SKUs** selling below baseline in the N fiscal weeks *after* the promotion (default N = 2), because shoppers stocked up during the deal. |
| **Net incremental margin** (`net_incremental_margin`) | The honest bottom line: `incremental_margin − cannibalization_margin − forward_buy_margin`. Negative = the promotion destroyed value once the two value-killers are netted out. |
| **Trade spend** (ROI context) | The promotional investment ROI is measured against. ORDM uses **planned** `planned_trade_spend` (realized off-invoice / bill-back / scan-down actuals are not modelled in v1), allocated to the category drill by scope share. |
| **Zone** (`offer_zone`) | A defined geographic area an offer can be attached to, modeled as **membership only** — a `zone_type` (store radius, polygon, beacon, or mall common area) plus a coarse centroid — never a precise boundary or a customer's position within it. |
| **Trigger type** (`trigger_type`) | The device signal that fires an offer: `geofence_enter`, `geofence_exit`, `dwell` (present for at least `min_dwell_seconds`), or `beacon_proximity`. The signal is evaluated on-device; only the resulting event is recorded. |
| **Suppression window** (`suppression_window_hours`) | The minimum number of hours after an offer is delivered to a customer before the same offer may be delivered to them again — the frequency-capping control that prevents over-messaging. |
| **Consent verification** (`consent_verified`) | A per-event flag asserting that marketing consent was verified for the customer at event time. Required TRUE for every delivered / opened / redeemed event; the executable consent invariant of this use case. |
| **Geohash privacy floor** (`centroid_geohash7`) | A zone centroid is stored as a 7-character geohash (~150 m cell) — coarse **by design**. It is the deliberate privacy floor: precise coordinates and device locations are never stored. |

## Standards

Dates ISO 8601; retail weeks via the NRF 4-5-4 `fiscal_calendar` (never derived from raw dates); product GTIN and store GLN are GS1 identifiers.
