# Smart Shelf design

**Package:** Connected Store Signals  
**Status:** Implemented; reviewed in #165. ADRs 0039–0041 Accepted (2026-10-09).  
**Design date:** 2026-08-17; repository form updated 2026-08-21

Smart Shelf answers three questions at store × shelf position × product grain: is the
product available, is the shelf executed as expected, and does the displayed price match the
price of record? It is the item-scoped perception and evidence layer. Replenishment workflow,
price setting, and price actuation remain outside this design.

## Model

| Object | Grain | Responsibility |
|---|---|---|
| `store_zone` (existing) | One SCD2 zone version | Populates site → area → aisle → bay → shelf-position hierarchy rows. |
| `sensor_device` (existing) | One SCD2 device version | Registers fixed shelf sensors, mobile CV platforms, and ESL gateways. Labels are endpoints below gateways, not devices. |
| `shelf_position_assignment` | One SCD2 version per shelf position × product | CSS-owned expected execution state: product, expected/minimum facings, and exact validity interval. |
| `shelf_state_observation` | One position × product × device × source capture | Restatable multi-measure observed shelf state with time, quality, coverage, and provenance. |
| `esl_label` | One SCD2 label version | ESL endpoint registry and gateway homing. |
| `esl_label_assignment` | One SCD2 label × product × position binding | Instant-grained pairing lifecycle and shelf-edge encoded identity snapshots. |
| `esl_price_observation` | One label × evidence source × source observation | Append-only evidence of displayed price, disclosure, and captured price of record. |

Identity-generated surrogate keys remain on the three dimensions/associations. The two
high-volume or restatable facts use deterministic `xxhash64` keys derived from durable ids and
carry collision checks. Source capture/observation ids, rather than timestamps rounded to a
second, make redelivery and CV re-inference idempotent.

## Shelf observation boundary

`shelf_state_observation` is outside `sensor_report_interval`. The interval envelope represents
one scalar report type for one auditable subject. A shelf capture contains product × position
state plus facings, unit/weight estimates, activity summaries, flags, and quality. Encoding that
as an interval would require a composite subject identity and would pre-empt the RFID/Smart
Shelf/IoT slot-series seam reserved by ADR 0036.

The dedicated fact still reuses the package contracts: UTC observation instants, store-local
date derivation, orthogonal measurement-validity and arrival-completeness axes, sensing
deployment provenance, raw-evidence pointers, and restatement metadata.

One physical misplacement capture produces two mandatory product rows with the same
`source_capture_id`: an `out_of_stock` row for the missing expected product and a `misplaced`
row for the detected wrong product. The latter captures the violated assignment. This keeps
both the absence and the misplaced product discoverable.

## Expected state and BMV

CSS owns position-level expected execution state. BMV `planogram` remains store × product
allocation intent (`allocated_facings`, `allocated_sqft`). The grains answer different
questions and neither package writes the other. Compliance gold may compare summed CSS
expected facings with BMV allocated facings and flag divergence; no cross-package FK or
corrective write is created.

Assignments and label bindings use `valid_from_ts` / `valid_to_ts` as their version grain so
same-day resets and re-pairing are unambiguous. Repository-standard SCD2 dates are retained as
derived fields. Core `product.gtin` remains authoritative; `encoded_gtin` and
`encoded_digital_link_uri` are shelf-edge snapshots whose disagreement is useful audit signal.

## Observation-only ESL

The ESL layer records what was displayed, when, and how it became known. Evidence sources are
platform acknowledgement, shelf CV, and manual audit. Multiple sources may disagree; that
disagreement is retained.

`esl_price_observation` captures a store-scoped price of record with its currency, source,
price type, and effective instant so audit evidence stands alone. Displayed and record prices
carry separate ISO 4217 columns; Delta constraints and DQ require same-currency comparison,
and gold fails closed when malformed evidence disagrees. The fact may read pricing evidence
but is never upstream of a price-producing surface. The model contains no price commands,
schedules, campaigns, or price-bearing automation actions.

ADR 0030's invariant is visible as `sensing_derived_input_flag = FALSE`. Displayed disclosure
indicator/text are observed evidence. Pricing-platform declarations such as algorithmic-pricing
or personal-data-use flags are not observations and remain deferred to a future pricing-owned
surface. This observation framing, the `esl_price_event` → `esl_price_observation` rename, and
the declaration-field deferral are the ADR 0030 amendment made by
[ADR 0041](../../../governance/decisions/0041-esl-observation-only-no-price-actuation.md) (Accepted 2026-10-09).

## Serving contracts

| View | Contract |
|---|---|
| `gold_shelf_state_current` | Latest capture per position × product wins before usability evaluation. New unknown/invalid evidence never resurrects an older good reading. |
| `gold_osa_daily_current` | OSA over known expected positions, with known, unknown, unobserved, and coverage denominators published separately. |
| `gold_planogram_compliance_current` | Presence, position, facings, and price-tag compliance at product/day grain plus read-only BMV allocation reconciliation. |
| `gold_share_of_shelf_current` | Facings-based brand share within store × category at one evaluation instant; not additive across categories, stores, or time. |
| `gold_price_accuracy_current` | End-of-day label match rate, split overcharge/undercharge, correction duration, and platform-ack latency. |
| `gold_observed_oos_episodes` | Maximal usable OOS runs with recovery/duration and an SDI-ingestible candidate shape. |
| `gold_shelf_vs_system_variance_daily` | Same-day last-usable shelf evidence versus EOD book inventory, including phantom-stock flags. |
| `gold_css_device_health` (extension) | ESL acknowledgement health aggregated under gateway devices, never under label endpoints. |

`mv_on_shelf_availability`, `mv_planogram_compliance`, and `mv_price_accuracy` expose
recomposable measures from these gold views. Distinct entity counts use durable ids, monetary
measures retain currency guards, and shares are only additive inside their declared denominator.

Every current view uses the named shelf evaluation clock. Freshness is a visible flag, not a
filter that can hide current bad evidence. Fixed sensors and mobile platforms use separate
freshness windows, and the chosen evaluation instant is returned as `fresh_as_of_ts`.

## Read-only seams

- **SDI:** consumes observed OOS episodes; CSS never writes SDI.
- **RFID:** `gold_zone_item_presence_current` can corroborate shelf product/zone presence.
- **IoT loop:** adopter automation may dispatch replenishment tasks and log them, but current
  in-model evaluation rules only watch interval report types. Shelf-condition rules await the
  shared slot-series seam. Smart Shelf adds no loop rows in v1.
- **Inventory:** same-date `inventory_position.units_on_hand_eod` supplies the book comparison.
- **Product and store:** supply conformed product identity/attributes and store/time/currency
  context.
- **DSS:** may publish supplier-safe share of shelf under its own disclosure controls.

The package is aggregate/item-scoped and carries no person-level identity, path, interaction,
or inference. There is no Smart Shelf shared-publication tier in v1.

## Deterministic validation story

Synthetic data covers normal stock, low-stock decay, a full OOS episode and recovery, the
two-row misplacement capture, good evidence followed by unknown/occluded evidence, robot partial
coverage, price mismatch and delayed correction, all three ESL evidence sources, overcharge and
undercharge, unit pricing, and cross-source disagreement. Stable source ids make repeat runs
identical. Error-severity DQ checks enforce identity, orphan, time, state-honesty, currency,
assignment/binding, gateway, and sensing-to-pricing restrictions.

The normative modeling rules remain in [ORDM data model standards](../../data-model-standards.md).
