# Connected Store Signals — Business Glossary

> Status: ✅ Published (0.5) · Last reviewed: 2026-10-07

Business terms for the Connected Store Signals outcome package. Vendor-neutral; follows the
ORDM [data model standards](../../docs/data-model-standards.md).

Two things about this domain that the term list alone will not convey. First, **footfall
vendors do not agree on what footfall means** — the same field name carries at least four
meanings depending on device configuration, and there is no standard to appeal to (unlike
RFID, which has GS1 EPCIS, or building telemetry, which has Brick and BACnet). Every
convention column below exists because of that absence. Second, **no measure here is safe to
sum without checking `aggregation_level`**.

## Tables & views

| Object | Grain | Description |
|---|---|---|
| `store` (canonical-core) | One version per store (SCD2) | Conformed store master. |
| `fiscal_calendar` (canonical-core) | One row per date | NRF 4-5-4 fiscal calendar. Joined logically on `trading_date = date_key`, not by FK. |
| `equipment` (canonical-core) | One version per asset (SCD2) | The maintained asset a temperature probe monitors. |
| `store_zone` | One version per zone (SCD2) | Recursive spatial hierarchy: site → area → aisle → bay → shelf position. Carries area, capacity and countability. |
| `sensing_deployment` | One version per deployment (SCD2) | The governance record for a sensing installation: method, purpose, lawful basis, DPIA, signage, retention, staff-exclusion policy. |
| `sensing_disclosure_policy` | One effective version per disclosure policy | Audience-specific k-threshold, zero suppression, same-cell dependent-measure suppression, and minimum publishable window. |
| `sensor_device` | One version per device (SCD2) | Physical device registry, anchored on Brick Schema 1.4.4 + QUDT, with BACnet / OPC UA / Sparkplug identity and calibration metrology. |
| `sensor_report_interval` | One report type × subject namespace × canonical interval × level × device | Narrow EPCIS-shaped interval envelope. Every modeled series is non-overlapping; alternate vendor rollups stay outside the additive fact. |
| `foot_traffic_interval_detail` | One row per `gs1:Count` envelope | One-to-one traffic, counting-convention, staff, occupancy, and dwell extension. |
| `actuator_capability` | One version per actuator (SCD2) | The active-control command surface of a `sensor_device` (role `actuate`/`both`). What a device can be commanded to do. |
| `evaluation_rule` | One version per rule (SCD2) | Standing threshold on a sensor observed property (shares the GS1 CBV `report_type` vocabulary) that fires actions when breached for `time_window_seconds`. |
| `automation_action` | One version per action (SCD2) | The intent: what happens when a rule fires. Polymorphic target (`actuator`/`role`/`person`/`external_system`), with a typed FK on the actuator case. |
| `execution_log` | One row per realised firing (append-only) | Audit ledger of automation runs: status, response, latency, and the interval that triggered it. |
| `tagged_item` | One serialized EPC identity | Type 1 registry of EPC identity, resolved product, current carrier, and tag privacy state. |
| `rfid_count_session` | One bounded count session | Header for a fixed, handheld, or robot count with an honest `full_store` or `partial` scope claim. |
| `rfid_read_event` | One EPC × reader × UTC second | Append-only, upstream-deduplicated visibility event; raw RF pings stay in Bronze. |
| `shelf_position_assignment` | One version per shelf position × product | Position-level expected product and facings, with instant-grained validity. CSS execution state, distinct from BMV allocation intent. |
| `shelf_state_observation` | One position × product × device × source capture | Restatable shelf-state evidence outside the scalar interval envelope. A misplacement capture has separate missing-expected and detected-wrong-product rows. |
| `esl_label` | One version per label endpoint | Electronic shelf-label registry below an ESL gateway device. |
| `esl_label_assignment` | One version per label × product × position binding | Instant-grained pairing lifecycle that makes a displayed-price observation attributable. |
| `esl_price_observation` | One label × evidence source × source observation | Append-only evidence of displayed price/disclosure versus a captured price of record; never a price command. |
| `gold_item_current_state` | One serialized item | Latest attributed state, persistent recall, disposition, presence, and method-specific freshness. |
| `gold_zone_item_presence_current` | One store × zone × product | Fresh serialized units currently attributed as present. |
| `gold_item_visibility_daily` | One store × product × trading date | Additive read-quality counts plus non-additive daily confidence, lag, and freshness diagnostics. |
| `gold_inventory_accuracy_daily` | One session × store × product × session trading date | Basis-aware observed-versus-EOD-book reconciliation over RFID-eligible products, with an explicit EOD `reconciliation_date`. |
| `gold_inventory_accuracy_daily_latest` | One store × product × reconciliation date × basis | Latest daily reconciliation per basis for metric rollups without repeated-session double counting. |
| `gold_count_session_summary` | One RFID count session | Duration, observed units/devices/zones, and full-store plan coverage. |
| `gold_zone_count_coverage` | One current store zone | Last-counted date and reference cadence, derived from actual session reads. |
| `gold_receiving_verification` | Linked shipment line or unlinked store × product × window | Expected-versus-observed verification only when the event carries a shipment-line association. |
| `gold_rfid_oos_candidates` | One store × product × reconciliation date | Latest aligned phantom-stock evidence for investigation; candidates are not stockout episodes and carry no inferred duration or cause beyond the observed evidence. |
| `gold_unaccounted_exits` | One item exit event | Item-side exit exceptions with no prior sold or shipping disposition; no person linkage. |
| `gold_shelf_state_current` | One shelf position × product | Latest-capture shelf truth with usability, freshness, and four compliance dimensions. |
| `gold_osa_daily_current` | One store × date × category | OSA with known, unknown, unobserved, and coverage denominators kept explicit. |
| `gold_planogram_compliance_current` | One store × date × product | Presence, position, facings, and price-tag compliance plus read-only BMV allocation comparison. |
| `gold_share_of_shelf_current` | One store × category × brand | Facings-based share of shelf at one evaluation instant. |
| `gold_price_accuracy_current` | One store × date × currency | Display match, split over/undercharge, correction, and acknowledgement latency evidence. |
| `gold_observed_oos_episodes` | One observed OOS episode | Shelf-gap episode start, recovery, duration, and SDI candidate evidence. |
| `gold_shelf_vs_system_variance_daily` | One store × product × date | Same-date last-usable shelf evidence versus EOD book inventory. |
| `gold_store_traffic_daily_current` | One store × trading date | Store-level daily traffic, dwell and occupancy with NRF prior-year comparison. |
| `gold_zone_traffic_current` | One store × zone × trading date | Zone-level traffic with density and engagement. |
| `gold_store_traffic_daily_shared` | One store × trading date | Disclosure-controlled shared store traffic. |
| `gold_zone_traffic_shared` | One store × zone × trading date | Disclosure-controlled shared zone traffic. |
| `gold_zone_traffic_interval_shared` | One disclosure-approved canonical area interval | Disclosure-controlled zone traffic at interval grain. Unlike the daily shared views, suppressed, invalid and sub-policy-duration intervals are omitted entirely rather than emitted with NULL measures, because the interval start and duration would otherwise disclose the protected cell. |
| `gold_traffic_sales_productivity_current` | One store × trading date | Sales and units per entry and per footfall. It exposes no conversion surface. |
| `gold_css_device_health` | One device version × report type × aggregation level × trading date | Whole-estate fleet health: uptime, coverage, freshness, session integrity, calibration, governance gaps. Report type and level are in the grain because one device can report more than one thing at more than one level. |
| `gold_css_automation_response` | One realised firing (`execution_log` grain) | The sense → evaluate → act → log loop as one row: the firing decorated with the action, rule, actuator and the observation that breached the threshold. Every parent is resolved AS OF the firing, so the threshold and payload shown are the versions that actually ran. |
| `gold_css_environmental_compliance_daily` | One store × device × measured subject × equipment × report type × current rule × trading date (one canonical series per device and property: device level, else subject level, finest cadence) | Daily compliance of a monitored asset against the current control rule: reading counts, min/max/avg, breach intervals, minutes outside range, share in range, and an `is_compliant` flag (NULL when no rule applies). |
| `gold_css_excursion_episodes` | One excursion episode (maximal contiguous breach run per device × measured subject × rule) | Excursions as coherent events: start, end, duration, worst reading and how far past the limit it went, firings triggered by the episode intervals (a late firing still counts), and time to the first successful action. |
| `gold_css_rule_effectiveness_daily` | One store × rule × trading date | Control-loop performance per rule: firings, successful firings, physical-command firings, latency, and ratio-of-sums success components. |
| `mv_store_foot_traffic` | store × date | Store totals. Separate from the zone view because a metric view cannot require a filter, so one combined view let `SELECT footfall` return the store total plus every zone total. |
| `mv_zone_foot_traffic` | store × zone × date | Zone detail, for comparing and ranking zones and for density. Zone footfall does NOT sum to a store total. |
| `mv_traffic_sales_productivity` | store × date | Metric view over traffic-sales productivity. |
| `mv_device_health` | store × device type × date | Metric view over the fleet-health gold view. |
| `mv_automation_response` | device × rule × action target × date | Metric view over the automation loop: firings, success rate, response latency and breach magnitude. |
| `mv_inventory_accuracy` | store × product × reconciliation date × basis | Metric view over RFID observed-versus-book reconciliation. |
| `mv_item_visibility` | store × product × trading date | Metric view over RFID item-visibility quality. |
| `mv_count_operations` | store × method × scope × trading date | Metric view over RFID count execution and full-store zone coverage. |
| `mv_on_shelf_availability` | store × category × date | Metric view over additive OSA counters and denominator-honesty measures. |
| `mv_planogram_compliance` | store × product × date | Metric view over recomposable compliance measures and share-of-shelf context. |
| `mv_price_accuracy` | store × currency × date | Metric view over label accuracy, over/undercharge, correction, and sync-latency measures. |
| `mv_environmental_compliance` | store × device × measured subject × report type × current rule × date | Metric view over daily environmental compliance: device-rule-days in and out of range, breach counts, compliance share. |
| `mv_excursion_episodes` | device × measured subject × rule × episode start date | Metric view over excursion episodes: frequency, duration, successful-action share (a firing credited to the episode succeeded; not proof it ended the excursion), and response latency. |
| `mv_phantom_stock_candidates` | store × product × reconciliation date × reason | Metric view over RFID phantom-stock investigation candidates. Candidates are investigation signals, never autonomous inventory adjustments. |
| `mv_oos_episodes` | store × zone × product × episode | Metric view over observed shelf out-of-stock episodes: duration, detection method, and investigation flags, sliceable by episode_start_date (store-local trading date) and candidate_severity. |

## Telemetry integrity terms

| Term | Meaning |
|---|---|
| Sequence gap | Source messages inferred missing within a source session. Raw sequence values stay in Bronze; the interval envelope carries only the interval-level count. |
| Duplicate delivery | Source messages delivered more than once. A different fault from a gap and counted separately as an interval summary. |
| Session restart | More than one `source_session_id` in a device-day. |

## RFID terms

| Term | Definition |
|---|---|
| **EPC** | GS1 Electronic Product Code. ORDM stores the EPC Pure Identity URI as `tagged_item_id`; it is serialized-item identity, not a person identifier. |
| **SGTIN** | Serialized Global Trade Item Number: a GTIN plus serial component represented as an EPC identity. |
| **TID / carrier** | Physical tag-chip identifier. `current_tid_hex` may change when the same serialized identity is re-encoded onto a replacement carrier. |
| **Tag privacy state** | Current evidence that a tag is `active`, `protected`, `killed`, or `detached`. Post-kill reads are surfaced as quality telemetry. |
| **Visibility event** | One upstream-deduplicated observation at EPC × reader × UTC second. It is not a raw RF ping and not an interval report. |
| **Read point vs business location** | The device or mobile platform supplies a read point; `zone_source` records whether the zone came from fixed placement, operator declaration, or platform localization. It is evidence, not certainty. |
| **Stray read** | A read suspected to be RF bleed from another location. Stray reads stay in the fact for quality analysis but do not drive current presence. |
| **Count session** | A bounded fixed, handheld, or robot census. `full_store` permits a derived active-zone plan; `partial` makes no plan-completion claim. |
| **Coverage vs cadence** | Coverage asks which zones a session actually observed. Cadence asks how recently and how often a zone was counted. A session plan is not required for cadence. |
| **Reconciliation basis** | `aligned_eod` supports the inventory-accuracy label; `misaligned` supports observed-to-book agreement only. |
| **Phantom stock** | Positive EOD book stock with zero qualified physical evidence. RFID requires an aligned, eligible reconciliation; Smart Shelf requires same-date usable shelf evidence. It is an investigation signal, not proof that no units exist elsewhere in the store. |
| **Unaccounted exit** | Attributed outward perimeter read with no sold or shipping disposition at or before the exit. It is an item-state exception, not proof about a person. |
| **Read rate vs accuracy** | Read volume and attribution health describe sensing quality. Inventory accuracy compares a qualified physical census with book inventory; high read volume alone does not establish accuracy. |

## Smart Shelf terms

| Term | Definition |
|---|---|
| **On-shelf availability (OSA)** | Expected shelf positions whose latest evaluable state is `in_stock` or `low_stock`, divided by expected positions with a known state. Unknown and unobserved positions are reported separately and never counted as available. |
| **Planogram compliance** | Execution compliance across four independently evaluable dimensions: expected product present, correct position, sufficient facings, and correct price tag. CSS expected state is position-level; BMV planogram remains allocation intent. |
| **Share of shelf** | Brand facings divided by total category facings within one store, category, and evaluation instant. Shares are not additive across categories, stores, or time. |
| **Facing** | One visible front presentation of a product on the shelf. `expected_facing_count` is the execution target; `observed_facing_count` is sensed evidence. A facing is not a complete unit count. |
| **Pick / put** | Since-prior activity summaries: picks remove units and puts return or replenish units. They are NULL for platforms that cannot observe events; NULL never means zero. |
| **Price of record** | Store-scoped authoritative price captured with its source, type, and effective instant on the price observation. It is pricing evidence read by CSS, never an output of shelf sensing. |
| **Displayed price** | Price actually visible on the label according to platform acknowledgement, shelf CV, or manual audit. It may disagree with the price of record. |
| **Label assignment** | Instant-grained binding of one ESL endpoint to a product and shelf position. It determines which product a displayed-price observation can be attributed to. |
| **Acknowledgement** | Platform evidence that a label update or displayed state was accepted/reported. It measures delivery evidence, not independent proof that pixels on the shelf match; shelf CV and manual audit remain separate sources. |
| **Displayed disclosure** | Indicator and optional text observed on the label alongside price. It records display evidence and does not by itself declare legal compliance. |
| **Latest-capture-wins** | Current-state rule that selects the newest capture before evaluating usability. A newer unknown, invalid, or occluded reading remains current and never revives an older good reading. |
| **Confidence score** | Platform-specific reliability score for a shelf capture. Used to rank captures when several are available; it is not comparable across platforms. |
| **Is stale** | The observation age exceeds the method-specific freshness window (for example 120 minutes for fixed devices, 1440 for mobile). Stale readings should not drive operational action without verification. |
| **Fully compliant position** | A position that is evaluable and compliant on all four dimensions: presence, position, facings and price tag. The strictest compliance gate. |

## Counting terms

| Term | Definition |
|---|---|
| **Footfall** (`footfall_count`) | Shopper count for the interval, measured **at** `aggregation_level`. Uninterpretable without the four convention columns below. |
| **Entries / exits** (`entry_count`, `exit_count`) | Independently measured crossings. They are **never exactly equal** — a divergence of a percent or so is physics, not a fault. `exit_count` is NULL, never 0, for a non-directional sensor. |
| **Counting unit** (`counting_unit`) | What one count represents: `person`, `group`, `device` or `object`. With group counting enabled, a count is of visitor **groups**. |
| **Group counting** (`group_counting_enabled`) | Whether a family or shopping party is counted as one. Changes `counting_unit` from person to group. |
| **Child counting** (`child_counting_enabled`, `child_height_threshold_cm`) | Whether shoppers below a height threshold are counted. Children are a **subset** of footfall, not an exclusion. The threshold is vendor-specific (130 cm and 120 cm are both in the field), so it travels with the count. |
| **Pass-by** (`passersby_count`, `passby_convention`) | Storefront traffic that did not enter. Vendors define this **two opposite ways** — one includes entrants, one excludes them — so the bare number is ambiguous by a factor of the capture rate. |
| **Capture rate** | `footfall / passersby`. Only meaningful where the pass-by convention is uniform across the rows compared. |
| **Count divisor** (`count_divisor`) | Divisor applied by a beam sensor counting both directions on one door. A device setting, **not** the constant 2. |
| **Unique visitors** (`unique_visitor_count`) | De-duplicated visitors within a window. Not additive across intervals. |

## Staff exclusion terms

| Term | Definition |
|---|---|
| **Staff exclusion method** (`staff_exclusion_method`) | How staff are separated: exclusion line, zone button, patterned or fabric tag, uniform ML, re-identification, fixed subtraction, scaling factor, or none. |
| **Staff exclusion stage** (`staff_exclusion_stage`) | **Where** the exclusion was applied: `at_sensor`, `at_aggregation` or `none`. Without this you cannot tell whether a received number was already corrected, so **double-correction is inevitable**. |
| **Staff exclusion grade** (`staff_exclusion_grade`) | Published accuracy band for the method: high (>90%), medium (70–90%), low (<70%). |
| **Raw vs adjusted** (`visitor_count_raw`, `visitor_count_adjusted`) | Before and after staff adjustment. The identity `adjusted = raw - staff_count` is enforced at error severity. |

## Occupancy terms

| Term | Definition |
|---|---|
| **Occupancy** (`occupancy_snapshot_end`) | People present at interval end. **Semi-additive**: take the last value across intervals, never the sum. |
| **Peak occupancy** (`occupancy_max`) | Highest simultaneous occupancy in the interval. A **store** peak comes from the site row, not `MAX()` over zone rows. |
| **Average occupancy** (`occupancy_avg`) | Mean occupancy, rolled up **duration-weighted** — never an average of averages, which over-weights sparse periods. |
| **Occupancy adjustment** (`occupancy_adjustment`) | A **signed** manual correction. Two unrelated standards independently put this in the schema: a retail vendor exposes it as a queryable metric, and BACnet Access Zone carries `Adjust_Value` as an integer. |
| **Counter reset** (`last_reset_local_ts`) | When cumulative counters were last zeroed. Per ONVIF this is interpreted as **local** time and is unbounded — multiple resets per day are legal, so a model assuming one daily reset is wrong. |
| **Negative occupancy** | Entry/exit drift. It is surfaced as a warning, never clamped: clamping would destroy the only evidence the balance has broken. |

## Dwell terms

| Term | Definition |
|---|---|
| **Dwell total / count** (`dwell_seconds_total`, `dwell_count`) | Numerator and denominator, stored separately so the average re-aggregates at any grain. A pre-computed average cannot. |
| **Average dwell** | `dwell_seconds_total / dwell_count`. |
| **Engaged vs passing** (`engaged_count`, `passing_count`, `engagement_threshold_seconds`) | Dwell observations above and below a configurable threshold. `passing_count` is a dwell bucket and is **not** the same as `passersby_count`. |
| **Engagement rate** | `engaged_count / dwell_count`. |

## Quality and completeness terms

| Term | Definition |
|---|---|
| **Measurement validity** (`measurement_validity`) | Was the sensor telling the truth: valid, degraded, invalid, imputed. |
| **Arrival completeness** (`arrival_completeness`) | Has the data landed: complete, incomplete, late_arrived, precheck. |
| **Why they are separate** | They are **orthogonal**. A sensor with its batteries pulled for 15 minutes yields an interval that is invalid but complete; a still-open current interval is valid but incomplete. One quality score cannot express both. |
| **Observed zero** (`is_zero_observed`) | A **measured** zero, distinct from an absent row. Most vendors emit no row for either a zero-traffic interval or an offline sensor, which makes the two indistinguishable without this flag. |
| **Uptime / coverage** (`uptime_ratio`, `coverage_ratio`) | Share of the interval the device was online, and share of expected sensors that reported. A low coverage means the count is **partial**, not low. |
| **Capped** (`is_capped`, `capped_count_limit`) | The reading hit the hardware detection ceiling. A capped peak is not an exact peak. |
| **Restatement** (`restatement_version`) | These feeds are **not** append-only. Vendors publish a late-data status that later resolves, and sensors check in with data hours or days old, so a row can be rewritten. |
| **Source observations** (`source_observation_count`, `expected_observation_count`) | Received and expected observations derived from source cadence and delivery completeness, never from shopper count or measured value. |
| **Source message summary** | Interval-level message, gap, duplicate, historical, and bad-quality counts. Per-message sequence and quality fields remain in Bronze. |
| **Session identity** (`source_session_id`) | Source-session identifier effective for the interval. |

## Additivity rules

| Measure | Rule |
|---|---|
| `footfall_count`, `entry_count`, `exit_count` | Additive over **time** within one `aggregation_level`. **Not** additive across zones. |
| `occupancy_snapshot_end` | Semi-additive — last value, never a sum. |
| `occupancy_max` | Max over time at one level. A store peak comes from the site row. |
| `occupancy_avg` | Duration-weighted mean. |
| `avg_dwell_seconds` | Re-derive from `SUM(total) / SUM(count)`. |
| `unique_visitor_count` | Not additive at all. |
| Ratios (`uptime_ratio`, `coverage_ratio`, `confidence_score`) | Averaged, never summed. |

## Automation loop terms (IoT Sensor Monitoring)

The closed loop that turns a sensed breach into an auditable action: **sense**
(`sensor_report_interval`) → **evaluate** (`evaluation_rule`) → **act**
(`automation_action` against an `actuator_capability`) → **log** (`execution_log`). It
reuses the existing device registry rather than redefining one.

| Term | Definition |
|---|---|
| **Actuator capability** (`actuator_capability`) | What a device can be *commanded* to do, as opposed to what it observes. An actuator is a capability of a `sensor_device` whose `device_role` is `actuate` or `both` — not a separate device registry. |
| **Command type** (`command_type`) | The kind of command: `toggle_power`, `set_level`, `set_setpoint`, `open_close`, `dispense`, `display_message`, `reset`. |
| **Acceptable value range** (`acceptable_value_range`) | Documented bound on a valid command payload, e.g. `0,1` for a toggle or `2.0,8.0` for a setpoint. Free text because the shape varies by `command_type`. |
| **Evaluation rule** (`evaluation_rule`) | A standing condition on a sensor's `report_type`: `condition_operator` compared against `threshold_value_numeric` (and `threshold_value_upper` for range operators). Shares the GS1 CBV vocabulary with `sensor_report_interval`. |
| **Sustained-breach window** (`time_window_seconds`) | How long the condition must hold before the rule fires — the debounce against a single transient reading. `0` fires on the first breaching observation. |
| **Automation action** (`automation_action`) | The intent triggered by a rule: `system_command`, `notification`, `webhook`, `ticket`, or `log_only`. |
| **Action target** (`target_entity_type`, `target_entity_id`) | A **polymorphic** reference — the target can be an `actuator`, `role`, `person` or `external_system`. The `actuator` case additionally carries a typed `actuator_capability_sk` FK; the others carry only the id pair (standards §A.5 adjudicated exception). |
| **Payload template vs response** (`payload_template`, `response_payload`) | The template is the command/message to send (on `automation_action`); the response is what the target actually returned (on `execution_log`). |
| **Execution log** (`execution_log`) | **Append-only** audit ledger: one row per realised firing, with `execution_status` (`success`/`failure`/`pending`/`timeout`/`skipped`), rendered `response_payload`, and `latency_ms`. Parent FKs are nullable so a log row survives the retirement of the action or actuator it references. |

## Environmental monitoring terms

| Term | Definition |
|---|---|
| **Excursion episode** | A maximal contiguous run of breaching intervals for one device × measured subject × rule. A breaching interval joins the episode only when it starts exactly where the previous one ended, so one in-range or missing interval ends the episode. Breaches are evaluated from the readings against the rule, so an excursion appears even if automation never fired. |
| **Compliance share** (`share_intervals_in_range`) | `(evaluated_interval_count - breach_interval_count) / evaluated_interval_count` for one device-day and rule. Roll up as a ratio of sums, never an average of daily shares. 1.0 means the asset never left the configured range. NULL when there are no valid readings. |
| **Compliant day** (`is_compliant`) | TRUE when no valid reading breached the current rule on the day, FALSE otherwise, NULL when no rule applies or no valid reading was evaluated (for example a unit mismatch). Compliance is measured against the adopter-configured rule, not against any specific regulation; regulatory cold-chain evidence (for example vaccine-storage logging) remains the adopter's responsibility. |
| **Time to first successful action** (`minutes_to_first_successful_action`) | Minutes from episode start to the first automation firing with `execution_status = 'success'`. NULL when no firing credited to the episode succeeded. Firings are credited by their triggering interval, so a firing that lands after the last breaching interval still counts. |
| **Has successful action** (`has_successful_action`) | TRUE when a firing triggered by one of the episode intervals succeeded. It shows the loop responded, not that the response ended the excursion. |
| **Physical command vs notification** | Firings are classified by the action target: an `actuator` target is a physical command (for example a compressor relay); a `role` or `person` target is a notification. One rule can own both, so the counts need not sum to firings. |

## Privacy and governance terms

| Term | Definition |
|---|---|
| **Aggregate-only schema** | There is no person-level tier in the published model, and the never-publish column list is asserted absent by a schema-level check. |
| **`external_default` k=10 policy** | Reference configuration for explicitly external/shared views, not a universal legal threshold or a base-fact invariant. Operational rows remain complete. |
| **Zero suppression** | A measured zero is suppressed on the same terms as a small count. |
| **Dependent-measure suppression** | Every traffic-derived measure in the same cell is NULL when its primary shared count is suppressed. This is not statistical complementary/secondary-cell suppression. |
| **Disclosure outcome** (`disclosure_suppressed_flag`) | Present only on shared views together with the policy id. Operational facts carry no suppression state. |
| **Sensing deployment** | The first-class governance record for an installation: method, declared purpose, lawful basis, jurisdiction, DPIA (including whether it assessed **employees**), signage, works-council consultation, consent requirement, opt-out mechanism, and retention ceiling. |
| **Sensing is never upstream of pricing** | An architectural invariant, not a usage guideline: no sensing table or view may appear in the lineage of a price-producing object. Enforced by a lineage-walking check, because the offending join is one line of SQL. |

## Traffic-sales productivity terms

| Term | Definition |
|---|---|
| **Conversion rate** | **Not published.** ORDM carries no transaction, basket or receipt count at any grain, so the industry numerator (transactions / visitors) does not exist, and no vendor publishes an accepted proxy. Computing it from `units` would count items rather than baskets and overstate conversion by roughly the average basket size. Recorded as decision D3; closing it needs a canonical-core change. |
| **Sales per entry** | `net_revenue / entry_count`. A productivity measure, not conversion. |
| **Units per entry** | `units / entry_count`. Items per entry, not transactions per visitor. |
| **Sales per footfall** | `net_revenue / footfall_count`. Preserves productivity for non-directional counters; not conversion. |
| **Units per footfall** | `units / footfall_count`. Items per observed footfall, not transactions per visitor. |
