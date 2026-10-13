# Design — RFID Tracking

Design contract for the RFID Tracking use case in Connected Store Signals.

> Status: v1 implemented. ADRs 0035–0038 Accepted; sign-off in #165.

## 1. Outcome and scope

The use case answers five operational questions:

1. Where was each serialized item last observed, and how fresh is that evidence?
2. How does a qualified physical census compare with EOD book inventory?
3. Are count sessions covering the intended store and happening often enough?
4. Do explicitly linked dock reads agree with shipment-line quantities?
5. Which item-side presence or exit exceptions should downstream inventory or LP tooling review?

V1 includes a serialized-item registry, append-only RFID visibility events, bounded count
sessions, current presence, inventory reconciliation, count coverage, receiving evidence,
device health, and read-only OOS/exit seams.

V1 deliberately excludes person, basket, receipt, loyalty, payment, or video linkage; EAS case
management; SSCC case/pallet genealogy; a conformed lot master; and DPP publication. Raw RF pings
remain in Bronze. The modeled event is the upstream-deduplicated business observation.
Serialized-item census-disappearance episode inference is also deferred: the OOS seam remains at
aggregate store × product × reconciliation-date grain and exposes candidates, not episodes.

## 2. Placement and promotion triggers

All three physical objects are CSS-owned because their first use is store-sensing operations:

- `tagged_item` — serialized EPC identity registry.
- `rfid_read_event` — append-only observation fact.
- `rfid_count_session` — bounded census header.

Two triggers prevent these objects becoming accidental shared masters:

- **Registry: first non-CSS consumer of serialized identity.** This triggers a canonical-core
  placement ADR for `tagged_item`, most naturally product-adjacent.
- **Session: second counting consumer.** This triggers review of a shared count-session contract.

Until a trigger occurs, CSS remains the single owner and other packages consume gold seams.

## 3. Physical grains and keys

### `tagged_item`

- Grain: one EPC Pure Identity URI.
- Durable id: `tagged_item_id`, whose value is the EPC Pure Identity URI.
- Surrogate: `xxhash64(tagged_item_id)`, guarded by `ti_sk_collision`.
- History: Type 1. EPC identity attributes are immutable; the current carrier and privacy state
  can change in place. Event history provides the recoverable operational timeline.
- Identity versus carrier: `current_tid_hex` identifies the physical chip. Re-encoding the same
  serialized identity onto a replacement chip changes the TID, not the row identity.
- Product: SGTIN rows resolve `product_sk` and `product_id`; unresolved or non-product schemes may
  leave them NULL. Optional lot/expiry fields do not create a conformed lot entity.

`xxhash64` follows ADR 0028 — *Hash surrogate keys for high-volume gold event facts*. The
durable id is authoritative. At
deployments approaching one billion distinct keys, use the documented SHA-256 escape rather than
accepting 64-bit birthday-collision risk.

### `rfid_read_event`

- Grain: one EPC × reader × UTC second after upstream RF-ping collapse.
- Durable id: `tagged_item_id|unix_timestamp(event_ts)|sensor_device_id`.
- Surrogate: `xxhash64(rfid_read_event_id)`, guarded by `rre_sk_collision`.
- Mutability: append-only; event rows are never restated.
- Dedup evidence: `first_seen_ts`, `last_seen_ts`, `read_count`,
  `duplicate_delivery_count`, peak RSSI, and `raw_data_uri`.
- Time: UTC event instant plus stored timezone/offset, trading date, and local hour.
- Business context: supported GS1 CBV business-step and disposition URIs.

Sanctioned nullable relationships are explicit:

- unregistered EPC → `tagged_item_sk` and resolved product keys may be NULL;
- free read → count-session keys are NULL;
- non-receiving or unlinked receiving read → shipment-line keys are NULL.

Every other entity reference carries both the version-specific surrogate FK and the durable id:
store, zone, device, deployment, item, product, session, and shipment line.

### `rfid_count_session`

- Grain: one bounded source session.
- Durable id: `store_id|source_session_id`.
- Surrogate: Delta IDENTITY; volume and write concurrency do not justify a hash exception.
- Methods: `fixed_window`, `handheld_sweep`, `robot_sweep`.
- Scope: `full_store` or `partial` only.
- Write order: the header is written before, or atomically with, linked events.

`full_store` permits a plan derived from the active non-site zone hierarchy at session start.
`partial` makes no plan-completion claim. Observed zones, units, and devices derive from events;
they are not mutable counters stored on the header.

## 4. Read-point attribution

Fixed readers inherit their installed zone. Mobile readers require event-level location. The
`zone_source` enum keeps those claims distinguishable:

- `device_placement` — fixed installed reader;
- `operator_declared` — handheld sweep location;
- `platform_localization` — robot/platform location.

`attribution_confidence` measures the assignment, and `is_stray_suspect` retains RF-bleed
evidence. Stray reads remain queryable for quality analysis but never drive current presence.
Direction is populated only for capable readers; non-directional readers use
`not_applicable` with NULL direction confidence.

## 5. Serving semantics

### Current item state and presence

`gold_item_current_state` selects the latest non-stray event per durable item. A recalled
disposition persists until a future explicit release mechanism exists. Fixed-reader evidence has
a 120-minute reference freshness window; mobile sweeps have 24 hours. Adopters may tighten these
reference values without changing the event contract.

`gold_zone_item_presence_current` aggregates only fresh items whose derived state is `present`.
It is evidence-backed presence, not guaranteed physical truth.

### Inventory reconciliation

`gold_inventory_accuracy_daily` has grain session × store × product × session trading date. Its
eligibility denominator contains products with active commissioned items observed at the store
during the preceding 90 days. This documented heuristic prevents an untagged product with book
stock from being mislabeled phantom stock.

The explicit `reconciliation_date` selects the EOD snapshot. A session ending 00:00–02:59
local reconciles to the preceding local calendar date; later sessions use their local end date.
`gold_inventory_accuracy_daily_latest` then selects one latest row per store, product,
reconciliation date, and basis for metric rollups, while the base view preserves every session.

The basis is structural:

- `aligned_eod` — `full_store` session whose **closing local hour** is 20:00–02:59, compared with
  `inventory_position.units_on_hand_eod`. Only these rows expose `inventory_accuracy_pct` and
  phantom/record-inaccuracy flags.
- `misaligned` — every other session. These rows expose
  `observed_to_book_agreement_pct`, never the inventory-accuracy label.

The agreement formula is `max(0, 1 - absolute_variance / max(abs(book), observed))`, with the
zero/zero case equal to 1. Numerators and denominators remain in gold so metric views recompute
weighted rates rather than averaging row percentages.

### Count execution and cadence

`gold_count_session_summary` reports duration, observed units/devices/zones, and full-store plan
coverage. The coverage numerator intersects observed zones with the active non-site plan, so
site and out-of-plan reads cannot inflate it above 100 percent. Partial sessions have NULL
planned/missed/rate columns.

`gold_zone_count_coverage` derives last-counted date and count frequency from actual session
events. Its seven-day target is a starter policy value, not a claim stored on session headers.
`is_overdue` is the single cadence signal; the DQ suite deliberately does not duplicate it as a
second "never covered in N days" check.

### Reader health

`gold_css_device_health` keeps every current registered RFID reader visible, including readers
with zero events, and exposes read volume, freshness, and ingest latency. RFID events do not
populate interval-observation, uptime, or coverage KPIs. Read-volume anomaly detection and
portal-direction health are deferred; direction capability remains an event-level DQ contract.

### Receiving

`gold_receiving_verification` has two honest tiers:

- `linked_shipment` — events carry an explicit shipment-line association; compare distinct EPCs
  with shipped quantity and label verified/short/over.
- `unlinked_window_evidence` — store × product × day/window evidence only; expected units and
  variance stay NULL. Overlapping shipments are never resolved by guesswork.

### Downstream seams

- Inventory: EOD book snapshot is read by the reconciliation view.
- Logistics: shipment lines are read only for explicitly linked receiving events.
- SDI: `gold_rfid_oos_candidates` exposes aligned phantom-stock investigation candidates but writes nothing. The
  seam remains dormant until SDI separately admits `rfid` as a detection method.
- Smart Shelf: product/zone presence can be corroborated in a future gold view without physical
  schema coupling.
- LP: `gold_unaccounted_exits` exposes item-state exceptions only.
- DSS/DPP: publication remains a downstream responsibility.

## 6. Envelope decision

RFID v1 publishes no `sensor_report_interval` rows. A read is an instant, per-item observation
with business context, not a scalar interval report. Zone counts and presence are derived states.
Publishing them as `space` + `gs1:Count` would collide with Foot Traffic's keyed-detail contract.

Future per-item interval series may adopt the IoT solution for subject identity. That is an
additive follow-up and does not require duplicating every RFID event into the envelope.

## 7. Quality controls

Error-severity checks cover durable grain, hash collision, key pairing, FK orphans, product/GTIN
agreement, CBV subsets, mobile read-point honesty, direction capability, session integrity,
event time, and schema append-only posture. Warning/metric checks expose header ordering,
post-kill reads, unregistered EPC rate, late delivery, and duplicate delivery.

The package-wide no-person-column and sensing-not-upstream-of-pricing checks explicitly include
all RFID objects. No monetary column exists, so the single-currency invariant is not applicable.

## 8. Synthetic scenarios and verification

The deterministic generator creates fixed entrance/backroom readers, handheld and robot readers,
serialized SGTIN/GRAI items, all count methods, full and partial sessions, all zone-source values,
linked and unlinked receiving, late handheld delivery, stray reads, unregistered EPCs, killed-tag
post-read telemetry, and item journeys through receiving, storage, floor, sale, and exit.

Focused executable tests cover five high-risk decisions only:

1. current state excludes stray reads and recall persists;
2. closing-hour basis, eligibility, and phantom stock;
3. full versus partial count coverage;
4. linked versus unlinked receiving;
5. registered/unregistered key pairing and fixed/mobile zone-source honesty.

## 9. Privacy boundary

RFID is item-scoped only. No model object links an EPC to a person, basket, transaction line,
loyalty profile, payment, image, or video track. `tag_privacy_state` records governance evidence
about the physical tag. An outward read with no prior sold/shipping disposition is an item-state
exception, not proof of theft or a statement about an actor.

Person-directed loss prevention belongs in an adopter-controlled private tier outside this open
model. This boundary is recorded in ADR 0037 and enforced structurally, not by masking.
