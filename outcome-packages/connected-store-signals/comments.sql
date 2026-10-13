-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals · column comments
-- Version: 0.5 · Generated: 2026-07-28 · LLM-generated: true · Reviewed: 2026-07-28
-- Column-level documentation for the gold views (Genie / AI-BI / UC metadata).
-- Run AFTER the views exist.
--
-- These comments carry MORE than a restatement of the column name, because the
-- interpretation traps in this domain are invisible from the schema: which measures are
-- additive at which level, which convention a count was captured under, and which
-- absences are structural rather than accidental. A consumer who reads only these
-- comments should still get the additivity right.
-- ============================================================

COMMENT ON TABLE ${catalog}.${css_schema}.tagged_item IS 'Serialized-item registry keyed by EPC Pure Identity URI, with product resolution, current carrier, and tag privacy state.';
COMMENT ON TABLE ${catalog}.${css_schema}.rfid_count_session IS 'Bounded RFID count-session header; coverage and census are derived from linked read events.';
COMMENT ON TABLE ${catalog}.${css_schema}.rfid_read_event IS 'Append-only RFID visibility events at EPC by reader by UTC-second grain after upstream RF-ping deduplication.';

COMMENT ON TABLE ${catalog}.${css_schema}.shelf_position_assignment IS 'Slot-level EXPECTED shelf state (SCD2): which product belongs at which shelf-position zone with how many facings. Execution contract, distinct from BMV planogram allocation intent -- the two reconcile read-only in gold and neither writes the other.';
COMMENT ON TABLE ${catalog}.${css_schema}.shelf_state_observation IS 'Restatable OBSERVED shelf state at position zone x product x device x source capture. One physical capture may yield several product rows sharing source_capture_id (expected-absent row = out_of_stock, wrong-product row = misplaced). Outside the sensor_report_interval envelope by design; state is an enum plus confidence and validity, never a boolean, and OSA/compliance ratios are computed in gold, never stored here.';
COMMENT ON TABLE ${catalog}.${css_schema}.esl_label IS 'ESL endpoint registry (SCD2): display capability, battery class, and gateway homing. A dedicated dimension below the sensor_device gateway tier; battery LEVEL is device-health telemetry, not registry data.';
COMMENT ON TABLE ${catalog}.${css_schema}.esl_label_assignment IS 'Label-product-position binding lifecycle (SCD2). A displayed price is attributable to a product only through the binding current at the observation instant; at most one current binding per label.';
COMMENT ON TABLE ${catalog}.${css_schema}.esl_price_observation IS 'Append-only price-display audit evidence: what each label displayed, when, by which of three independent evidence paths (platform ack, shelf CV, manual audit), against the price of record captured at observation time. Reads pricing, never feeds it; sensing_derived_input_flag is CHECK-constrained FALSE.';

-- ========== gold_store_traffic_daily_current ==========

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.trading_date IS 'Business date, derived from the UTC instant plus the store UTC offset -- not a calendar date in the reader timezone.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.aggregation_level IS 'Always site for this view. Present so a consumer joining it to zone data cannot mix levels by accident.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.footfall_count IS 'Store footfall for the day, measured AT site level. NOT a sum over zones -- a shopper traversing five zones would be counted five times.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.entry_count IS 'Measured entries. The denominator for per-entry productivity measures.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.exit_count IS 'Measured exits. NULL where the sensors are non-directional and therefore cannot measure them. Entries and exits are independently measured and never exactly equal.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.visitor_count_adjusted IS 'Footfall after staff exclusion. Equals visitor_count_raw - staff_count.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.staff_count IS 'Staff detections excluded from footfall.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.child_count IS 'Child detections. A SUBSET of footfall, not an exclusion from it.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.peak_occupancy IS 'Highest simultaneous occupancy in the day. Semi-additive: a MAX over intervals, never a SUM.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.avg_occupancy IS 'Mean simultaneous occupancy, DURATION-WEIGHTED by interval length rather than an average of averages.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.dwell_seconds_total IS 'Dwell numerator. Kept alongside dwell_count so the average re-aggregates correctly at any grain.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.dwell_count IS 'Dwell denominator -- the number of dwell observations.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.avg_dwell_seconds IS 'dwell_seconds_total / dwell_count.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.footfall_count_py IS 'Footfall on the equivalent NRF fiscal week and weekday last year, not the same calendar date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.footfall_growth_py IS 'Fractional growth against footfall_count_py.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.counting_unit IS 'What one count represents: person, group, device or object. A footfall number is uninterpretable without it.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.staff_exclusion_enabled IS 'TRUE if staff were excluded. Store-days differing on this are not comparable without saying so.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.group_counting_enabled IS 'TRUE if family or shopping groups were counted as one. Changes counting_unit from person to group.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.time_mode IS 'Whether the day covers operating hours only or all day. Vendors expose this per metric, so it travels with the row.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.avg_uptime_ratio IS 'Mean share of canonical interval duration the sensors were online. Read this before trusting a low count.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.avg_coverage_ratio IS 'Mean share of expected sensors that reported. A low value means the count is PARTIAL, not low.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.valid_interval_share IS 'Share of intervals whose measurement was valid. Orthogonal to completeness -- an interval can be complete but invalid.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.complete_interval_share IS 'Share of intervals whose data had fully landed. Orthogonal to validity.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.has_imputed_intervals IS 'TRUE if any interval was modelled rather than measured.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.interval_count IS 'Source intervals behind the row.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.interval_minutes_total IS 'Total duration of valid traffic intervals. This generic duration is not the denominator for measures that were reported on only some intervals.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.occupancy_interval_minutes_total IS 'Duration of valid intervals with a reported occupancy average; the re-aggregation denominator for avg_occupancy.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.uptime_interval_minutes_total IS 'Duration of intervals with a reported uptime ratio; the re-aggregation denominator for avg_uptime_ratio.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.coverage_interval_minutes_total IS 'Duration of intervals with a reported coverage ratio; the re-aggregation denominator for avg_coverage_ratio.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.fresh_as_of_ts IS 'When the view was evaluated.';

-- ========== gold_zone_traffic_current ==========

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.store_zone_id IS 'Durable zone business key -- the SCD2-safe join key. Prefer this over the surrogate.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.zone_code IS 'Zone code as emitted by the source system.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.zone_type IS 'Depth in the spatial hierarchy: entrance, area, department, aisle, bay, shelf_position, queue, fitting_room.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.parent_zone_id IS 'Durable id of the containing zone.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.hierarchy_depth IS 'Materialised depth (0 = site), so consumers avoid a recursive CTE.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.aggregation_level IS 'Always area for this view. NEVER sum footfall across rows of this view to get a store total -- use gold_store_traffic_daily_current.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.footfall_count IS 'Zone footfall for the day. Additive over TIME within the zone; NOT additive across zones.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.passersby_count IS 'Pass-by traffic. Vendors define this two OPPOSITE ways (including or excluding entrants), so it is only comparable within one convention.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.peak_occupancy IS 'Zone peak occupancy. A STORE peak is not the MAX of these -- it comes from the site row.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.avg_occupancy IS 'Duration-weighted mean occupancy for the zone.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.engaged_count IS 'Dwell observations exceeding the engagement threshold.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.passing_count IS 'Dwell observations below the engagement threshold. Distinct from passersby_count, which is storefront traffic rather than a dwell bucket.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.engagement_rate IS 'engaged_count / dwell_count.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.area_sqm_minutes IS 'Zone area multiplied by the duration of intervals where area was known; numerator for re-aggregating effective area.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.area_interval_minutes_total IS 'Duration of intervals with a recorded zone area; denominator for area_sqm.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.area_sqm IS 'Duration-weighted effective zone floor area in square metres for the zone-day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.capacity_persons IS 'Duration-weighted effective safe or design occupancy for the zone-day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.capacity_interval_minutes_total IS 'Duration of intervals with a recorded zone capacity; denominator for capacity_persons.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.footfall_per_sqm IS 'Traffic density for THIS zone-day: footfall / area_sqm. Re-aggregating over several days divides by the summed area of the grouped zone-days, which yields an AVERAGE DAILY density rather than a period total -- mv_zone_foot_traffic names the measure avg_daily_footfall_per_sqm for that reason.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.occupancy_per_sqm IS 'Occupancy density: avg_occupancy / area_sqm.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.peak_capacity_utilisation IS 'peak_occupancy / capacity_persons. Above 1 is either a safety event or a broken counter.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.interval_minutes_total IS 'Total duration of valid traffic intervals. This generic duration is not the denominator for measures reported on only some intervals.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.occupancy_interval_minutes_total IS 'Duration of valid intervals with a reported occupancy average; the re-aggregation denominator for avg_occupancy.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.uptime_interval_minutes_total IS 'Duration of intervals with a reported uptime ratio; the re-aggregation denominator for avg_uptime_ratio.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.coverage_interval_minutes_total IS 'Duration of intervals with a reported coverage ratio; the re-aggregation denominator for avg_coverage_ratio.';

-- ========== gold_store_traffic_daily_shared ==========

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.trading_date IS 'Business date whose effective disclosure policy governs this shared cell.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.fiscal_year IS 'NRF fiscal year for the trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.fiscal_period IS 'NRF fiscal period for the trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.fiscal_week IS 'NRF week number within the fiscal year.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.fiscal_week_id IS 'NRF fiscal week identifier.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.fiscal_week_index IS 'Monotonic fiscal-week index used for period comparisons.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.day_of_week IS 'ISO day of week for the trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.is_holiday IS 'TRUE when the trading date is a recognised retail holiday.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.footfall_count IS 'Disclosure-controlled site-level footfall. NULL with disclosure_suppressed_flag = TRUE means suppressed, not zero.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.entry_count IS 'Disclosure-controlled measured entries. NULL with disclosure_suppressed_flag = TRUE means suppressed, not zero.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.exit_count IS 'Disclosure-controlled measured exits. NULL with disclosure_suppressed_flag = TRUE means suppressed; otherwise NULL can mean a non-directional source.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.peak_occupancy IS 'Disclosure-controlled daily peak occupancy. NULL with disclosure_suppressed_flag = TRUE means suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.avg_occupancy IS 'Disclosure-controlled duration-weighted mean occupancy. NULL with disclosure_suppressed_flag = TRUE means suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.dwell_seconds_total IS 'Disclosure-controlled dwell numerator. NULL with disclosure_suppressed_flag = TRUE means suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.dwell_count IS 'Disclosure-controlled dwell denominator. NULL with disclosure_suppressed_flag = TRUE means suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.avg_dwell_seconds IS 'Disclosure-controlled dwell_seconds_total / dwell_count. NULL with disclosure_suppressed_flag = TRUE means suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.counting_unit IS 'What one published count represents: person, group, device or object.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.staff_exclusion_enabled IS 'TRUE when staff were excluded from the operational count behind this shared row.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.group_counting_enabled IS 'TRUE when shopping groups were counted as one.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.time_mode IS 'Whether the underlying observations cover operating hours only or all day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.sensing_disclosure_policy_id IS 'Durable policy assignment whose effective version was resolved for this trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.disclosure_suppressed_flag IS 'TRUE when every traffic-derived measure in this cell is NULL under same-cell dependent-measure suppression.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.aggregation_level IS 'Always site. Store footfall is not a sum of zone rows.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_shared.fresh_as_of_ts IS 'When the shared view was evaluated.';

-- ========== gold_zone_traffic_shared ==========

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.store_zone_id IS 'Durable zone business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.zone_code IS 'Zone code from the version effective for the measured intervals.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.zone_name IS 'Human-readable zone name.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.zone_type IS 'Depth or role of the zone in the in-store spatial hierarchy.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.parent_zone_id IS 'Durable id of the containing zone.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.hierarchy_depth IS 'Materialised zone depth, where zero is the site.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.is_sales_floor IS 'TRUE when the zone is customer-accessible selling space.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.trading_date IS 'Business date whose effective disclosure policy governs this shared cell.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.fiscal_year IS 'NRF fiscal year for the trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.fiscal_week_id IS 'NRF fiscal week identifier.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.day_of_week IS 'ISO day of week for the trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.footfall_count IS 'Disclosure-controlled zone footfall. NULL with disclosure_suppressed_flag = TRUE means suppressed, not zero.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.entry_count IS 'Disclosure-controlled zone entries. NULL with disclosure_suppressed_flag = TRUE means suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.exit_count IS 'Disclosure-controlled zone exits. NULL with disclosure_suppressed_flag = TRUE means suppressed; otherwise NULL can mean a non-directional source.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.passersby_count IS 'Disclosure-controlled pass-by traffic. NULL with disclosure_suppressed_flag = TRUE means suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.peak_occupancy IS 'Disclosure-controlled zone peak occupancy. NULL with disclosure_suppressed_flag = TRUE means suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.avg_occupancy IS 'Disclosure-controlled duration-weighted mean occupancy. NULL with disclosure_suppressed_flag = TRUE means suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.dwell_seconds_total IS 'Disclosure-controlled dwell numerator. NULL with disclosure_suppressed_flag = TRUE means suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.dwell_count IS 'Disclosure-controlled dwell denominator. NULL with disclosure_suppressed_flag = TRUE means suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.avg_dwell_seconds IS 'Disclosure-controlled dwell_seconds_total / dwell_count. NULL with disclosure_suppressed_flag = TRUE means suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.engaged_count IS 'Disclosure-controlled dwell observations at or above the engagement threshold.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.passing_count IS 'Disclosure-controlled dwell observations below the engagement threshold.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.engagement_rate IS 'Disclosure-controlled engaged_count / dwell_count.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.footfall_per_sqm IS 'Disclosure-controlled daily zone traffic density.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.occupancy_per_sqm IS 'Disclosure-controlled mean occupancy density.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.peak_capacity_utilisation IS 'Disclosure-controlled peak occupancy as a share of effective capacity.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.area_sqm IS 'Duration-weighted effective zone area. This non-traffic dimension remains visible when traffic measures are suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.capacity_persons IS 'Duration-weighted effective zone capacity. This non-traffic dimension remains visible when traffic measures are suppressed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.counting_unit IS 'What one published count represents: person, group, device or object.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.staff_exclusion_enabled IS 'TRUE when staff were excluded from the operational count behind this shared row.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.sensing_disclosure_policy_id IS 'Durable policy assignment whose effective version was resolved for this trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.disclosure_suppressed_flag IS 'TRUE when every traffic-derived measure in this cell is NULL under same-cell dependent-measure suppression.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.aggregation_level IS 'Always area. Zone footfall is not additive across zones.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_shared.fresh_as_of_ts IS 'When the shared view was evaluated.';

-- ========== gold_zone_traffic_interval_shared ==========

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.shared_zone_traffic_interval_sk IS 'Deterministic hash of the disclosure-safe shared interval id; it contains no device identity.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.shared_zone_traffic_interval_id IS 'Disclosure-safe interval id built from store, zone, UTC start epoch, and duration; it contains no device identity.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.store_sk IS 'Store surrogate carried by the canonical interval.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.store_zone_id IS 'Durable zone business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.zone_code IS 'Zone code from the exact dimension version referenced by the interval.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.interval_start_ts IS 'UTC start instant of the published canonical interval.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.interval_end_ts IS 'UTC end instant of the published canonical interval.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.trading_date IS 'Business date used to resolve the effective disclosure policy.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.interval_minutes IS 'Canonical interval duration. Rows below the policy minimum are omitted.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.footfall_count IS 'Zone footfall for an interval that cleared the effective threshold. Suppressed intervals are omitted rather than emitted with NULL.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.dwell_seconds_total IS 'Dwell numerator for a disclosure-approved interval.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.dwell_count IS 'Dwell denominator for a disclosure-approved interval.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.avg_dwell_seconds IS 'dwell_seconds_total / dwell_count for a disclosure-approved interval.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_interval_shared.sensing_disclosure_policy_id IS 'Durable policy assignment whose effective version admitted this interval.';

-- ========== gold_traffic_sales_productivity_current ==========

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.sales_per_entry IS 'Net revenue divided by measured entries. A productivity measure, not conversion.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.units_per_entry IS 'Items sold divided by measured entries. Items are not transactions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.sales_per_footfall IS 'Net revenue divided by measured footfall. Available when entry direction is not observed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.units_per_footfall IS 'Items sold divided by measured footfall. Items are not transactions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.units IS 'Units sold at the store-day. An item count, not a basket or transaction count.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.net_revenue IS 'Net revenue after discount, in the single reporting currency.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.promo_active_flag IS 'TRUE if any product at the store-day carried a real promotion; NO_PROMO is excluded.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.active_promo_count IS 'Distinct real promotions active at the store-day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.currency_code IS 'ISO 4217 reporting currency.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.occupancy_interval_minutes_total IS 'Duration of valid intervals with a reported occupancy average; denominator for re-aggregating avg_occupancy.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.coverage_interval_minutes_total IS 'Duration of intervals with a reported coverage ratio; denominator for re-aggregating avg_coverage_ratio.';

-- ========== gold_css_device_health ==========

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.device_type IS 'The dimension that lets ONE view serve the whole estate. IoT, RFID and Smart Shelf add rows here, not new views.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.sensing_technology IS 'How the device senses. Drives both the accuracy and the privacy profile.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.firmware_version IS 'Current firmware. A common cause of a STEP CHANGE in counting behaviour, so group by it when investigating a discontinuity.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.missing_observation_rate IS '1 - (observations_received / observations_expected). The primary fleet KPI. Re-aggregate it by summing the two component columns, never by averaging this ratio: an average lets a device expecting 4 observations outvote one expecting 400, which understates a fleet-wide outage.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.valid_intervals IS 'Count of intervals whose measurement was valid. Retained with invalid_intervals so valid-interval share can be re-aggregated from summed components.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.feed_age_minutes IS 'Minutes since this device last landed data.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.feed_freshness_status IS 'fresh (<= 60 min), delayed (<= 6 hr), stale (> 6 hr).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.sequence_gap_count IS 'Source messages inferred missing within source sessions, summed from interval-level summaries.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.duplicate_delivery_count IS 'Duplicate source-message deliveries, summed independently from sequence gaps.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.session_count IS 'Distinct source_session_id values in the device-day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.had_session_restart IS 'TRUE when more than one source session appears in the device-day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.historical_message_count IS 'Delivered source messages marked as buffered or historical.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.bad_quality_message_count IS 'Delivered source messages marked bad or stale by the source.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.late_arrived_intervals IS 'Intervals that landed after their window closed. These feeds are NOT append-only; vendors document data arriving hours or days late.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.observed_zero_intervals IS 'Intervals with a MEASURED zero, as distinct from an absent row. Most vendors emit no row for either a zero-traffic interval or an offline sensor, which makes the two indistinguishable without this.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.capped_intervals IS 'Intervals that hit the hardware detection ceiling. A capped peak is NOT an exact peak.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.calibration_status IS 'current, expiring_soon (<= 30 days), expired, or unknown. For vaccine storage an expiry is a compliance failure, not a maintenance backlog item.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.probe_type IS 'buffered, air, glycol, surface or none. Vaccine storage requires BUFFERED; an air probe reacts to door openings and manufactures false excursions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.accuracy_tolerance IS 'Rated accuracy in the device native unit. CDC/VFC requires +/-0.5 degC for vaccine storage.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.is_backup_device IS 'TRUE for the staggered-calibration backup unit required for vaccine storage.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.bacnet_out_of_service IS 'BACnet Out_Of_Service. When TRUE the Present_Value is SIMULATED, so every reading from this device is fabricated.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.dpia_completed_flag IS 'Whether the governing deployment has a completed impact assessment. Surfaced beside fleet health because the two are reviewed by different people who need the same row.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.ai_act_notice_status IS 'AI Act Art. 50(3) deployer notice status. Applies from 2026-08-02 and was not postponed by the Digital Omnibus.';

-- ========== gold_css_automation_response ==========
-- One row per realised automation firing, decorated with the action, rule, actuator and
-- the observation that triggered it. Every parent is resolved AS OF the firing (§A.16),
-- so a threshold, payload or actuator range here is the version that actually ran, not
-- today's tuning.
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.store_id IS 'Durable store business key of the device that fired the loop.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.sensor_device_id IS 'Durable id of the observing device whose reading breached the rule, resolved from the triggering interval version-in-effect. This is the device that CAUSED the firing.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.store_zone_id IS 'Durable id of the zone the observing device is installed in.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.device_type IS 'Kind of device that triggered the firing, e.g. temperature for the cold-chain excursion loop.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.execution_log_id IS 'Durable id of the firing. Identifies the action-that-ran-against-its-triggering-observation, not merely the observation -- one breaching interval can fire several actions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.triggered_at_timestamp IS 'When the action fired (UTC). The ledger ordering key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.trading_date IS 'Business date of the breach that fired the loop, from the triggering interval; the firing date is the fallback when the trigger was not a canonical interval. The day-grain key for rollups.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.execution_status IS 'Outcome of the firing: success, failure, pending, timeout or skipped.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.latency_ms IS 'Milliseconds from the breaching observation to the firing. Automation RESPONSE latency, NOT ingest latency -- do not compare it to sensor_report_interval.latency_seconds.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.response_latency_band IS 'fast (<= 250 ms), normal (<= 1000 ms), slow (> 1000 ms), or unknown. A responsiveness band, not a data-quality one.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.action_type IS 'What kind of action fired: system_command, notification, webhook, ticket or log_only. One breach can fan out to several action types.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.target_entity_type IS 'The kind of thing the action targeted -- actuator, role, person or external_system. Only the actuator target carries a typed actuator FK (§A.5).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.target_entity_id IS 'Durable id of the target, interpreted per target_entity_type.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.action_is_enabled IS 'TRUE if the action version that fired was live. A disabled action leaves its rule firing but takes no effect.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.evaluation_rule_id IS 'Durable id of the rule whose breach fired the action.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.rule_name IS 'Human-readable rule name, e.g. an over-temperature excursion on a named device.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.report_type IS 'GS1 CBV property the rule watches, e.g. gs1:Temperature. Shared vocabulary with sensor_report_interval.report_type.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.severity IS 'Operational severity of the breach: info, warning or critical.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.threshold_value_numeric IS 'The threshold the observed value was compared against, in the rule unit, AS OF the firing. DOUBLE, matching sensor_report_interval.value (§A.6).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.command_type IS 'What the actuator was commanded to do, e.g. toggle_power. NULL for a non-actuator action such as a notification.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.actuator_capability_id IS 'Durable id of the actuator the command hit. NULL for non-actuator actions or a retired actuator.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.equipment_id IS 'Durable business key of the asset the actuator drives, e.g. the refrigeration unit. NULL for ambient or digital-only actuation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.sensor_report_interval_sk IS 'The reading interval that breached the rule, closing the loop back to the observation. NULL if the trigger was not a single canonical interval.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.breach_value IS 'The observed value that breached the rule, in breach_uom. For the cold-chain loop this is the temperature that exceeded the limit.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.breach_margin IS 'Signed difference of breach_value from threshold_value_numeric, in the rule unit. Positive means above threshold -- how far past the limit the reading was. A cross-operator magnitude is left to the consumer.';

-- ========== RFID gold surfaces ==========

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.derived_disposition_uri IS 'Latest attributed disposition, except that a recalled disposition persists until an explicit release mechanism is modeled.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.derived_presence_state IS 'present, absent, unavailable, or stale. Stray-suspect reads never drive this state.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.freshness_window_minutes IS 'Configured freshness window selected from the latest reader platform; starter defaults are 120 minutes fixed and 1440 minutes mobile.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.zone_source IS 'How the latest read point was resolved: fixed device placement, operator declaration, or mobile-platform localization.';

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.reconciliation_basis IS 'aligned_eod only for full-store sessions closing in the declared EOD window; every other row is misaligned.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.reconciliation_date IS 'EOD inventory snapshot date used for the comparison. Sessions ending 00:00-02:59 local reconcile to the preceding local date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.inventory_accuracy_pct IS 'Observed-versus-EOD-book agreement for aligned_eod rows only; NULL for misaligned sessions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.observed_to_book_agreement_pct IS 'Agreement evidence for misaligned sessions; it must not be labeled inventory accuracy.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.eligible_tagged_units IS 'Distinct active serialized units observed for the store-product in the eligibility lookback.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.is_phantom_stock IS 'TRUE when an aligned eligible product has positive EOD book stock and zero observed units.';

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.reconciliation_date IS 'Daily EOD snapshot date at the one-row-per-store/product/date/basis metric-support grain.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.rfid_count_session_id IS 'Latest session selected within the store, product, reconciliation date, and basis.';

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.planned_zones IS 'Active non-site zones derived at session start for full_store sessions; NULL for partial scope.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.zone_coverage_rate IS 'Observed zones divided by derived planned zones for full_store sessions only.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.target_cadence_days IS 'Configured reference cadence for RFID count sessions; the starter default is seven days.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.count_lookback_days IS 'Configured wall-clock lookback used by count_sessions_in_lookback; the starter default is 30 days.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.count_sessions_in_lookback IS 'Distinct RFID count sessions observed within count_lookback_days.';

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_receiving_verification.verification_tier IS 'linked_shipment supports over/short verification; unlinked_window_evidence is evidence only and is never guessed onto a shipment.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_receiving_verification.expected_units IS 'Shipment-line quantity for linked evidence; NULL for unlinked receiving windows.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.exception_reason IS 'Item-state reason only. This view contains no person, basket, receipt, loyalty, payment, or video link.';

-- ---- Smart Shelf + RFID gold-view column documentation (coverage hardening) ----
-- ========== gold_item_current_state ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.attribution_confidence IS 'Platform confidence score for the zone attribution.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.fresh_as_of_ts IS 'When the view was evaluated.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.freshness_age_minutes IS 'Minutes since latest_event_ts at the evaluation clock.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.is_mobile_platform IS 'TRUE if the latest read came from a mobile reader.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.latest_biz_step_uri IS 'GS1 CBV business step URI of the latest event (e.g., urn:epcglobal:cbv:bizstep:receiving).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.latest_direction_code IS 'Direction code if the latest event was directional (e.g., enter, exit).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.latest_event_ts IS 'Timestamp of the most recent RFID read event.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.latest_ingest_ts IS 'Ingest timestamp of the most recent read event.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.product_sk IS 'Product surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.recalled_at_ts IS 'Timestamp when a recall disposition was applied (NULL if not recalled).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.sensing_deployment_id IS 'Durable deployment business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.sensing_deployment_sk IS 'Deployment surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.sensor_device_id IS 'Durable device business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.sensor_device_sk IS 'Device surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.store_sk IS 'Store surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.store_zone_id IS 'Durable zone business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.store_zone_sk IS 'Zone surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.tagged_item_id IS 'Durable EPC Pure Identity URI (serialized item business key).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_current_state.tagged_item_sk IS 'Serialized item surrogate key.';
-- ========== gold_item_visibility_daily ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.arrival_lag_seconds_p95 IS '95th percentile latency from read timestamp to ingest timestamp.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.avg_attribution_confidence IS 'Mean confidence score for zone attribution across all read events.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.distinct_items_read IS 'Count of distinct serialized items observed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.duplicate_delivery_count IS 'Duplicate source messages re-delivered (distinct from sequence gaps).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.fresh_as_of_ts IS 'When the view was evaluated.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.freshness_age_minutes IS 'Minutes since latest_event_ts at the evaluation clock.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.latest_event_ts IS 'Most recent read event timestamp for this product.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.raw_ping_count IS 'Source RF pings before upstream deduplication.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.read_event_count IS 'Total RFID read events for this product at the store on the trading_date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.stray_read_count IS 'Read events suspected to be RF bleed from another location.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.trading_date IS 'Business date of the RFID read events.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_item_visibility_daily.unregistered_read_count IS 'Read events for items not yet registered in tagged_item master.';
-- ========== gold_observed_oos_episodes ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.book_units_eod_at_start IS 'EOD book inventory units at the episode start date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.candidate_reason IS 'phantom_stock when EOD book units were positive at episode start, otherwise unknown.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.candidate_severity IS 'Severity band by episode duration: high (24 hours or more), medium (4 hours or more), low otherwise.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.data_quality_flag IS 'TRUE when any supporting observation was degraded: a suspected data quality issue, matching the SDI oos_event contract.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.detection_method IS 'How the episode was detected: smart_shelf, rfid, or other.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.episode_duration_minutes IS 'Duration from episode_start_ts to episode_recovery_ts or to fresh_as_of_ts if ongoing.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.episode_recovery_ts IS 'UTC timestamp when the product returned to in_stock or low_stock; NULL if is_ongoing = TRUE.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.episode_start_ts IS 'UTC timestamp when the out-of-stock state was first detected.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.episode_start_date IS 'Store-local trading date of the first out-of-stock observation. The date the book-units join uses; slice episodes by day on this, not on a cast of episode_start_ts.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.evidence_at_ts IS 'Timestamp of the most recent supporting evidence.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.fresh_as_of_ts IS 'When the view was evaluated.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.is_ongoing IS 'TRUE if the out-of-stock condition persists at the evaluation clock.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.is_phantom_stock_candidate IS 'TRUE when positive book stock existed with zero observed units.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.last_oos_observed_ts IS 'Latest timestamp an out-of-stock state was observed for this episode.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.min_confidence_score IS 'Minimum confidence score across observations supporting this episode.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.oos_episode_id IS 'Durable unique identifier for the OOS episode.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.record_source IS 'Source system of the episode record.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.store_zone_id IS 'Durable shelf-position zone business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.supporting_device_count IS 'Number of distinct devices that contributed observations.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_observed_oos_episodes.supporting_observation_count IS 'Number of observations that contributed to detecting or confirming this episode.';
-- ========== gold_osa_daily_current ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.category IS 'Product merchandising category. NULL groups positions with no category assignment.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.expected_positions IS 'Shelf positions with an active assignment for the store-date-category.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.fresh_as_of_ts IS 'When the view was evaluated.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.known_state_pct IS 'Share of observed positions in a known state: positions_known / observed_positions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.observation_coverage_pct IS 'Share of expected positions captured at least once: observed_positions / expected_positions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.observed_positions IS 'Expected positions that had at least one observation on the trading_date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.osa_pct_eod IS 'On-shelf availability at end-of-day: positions_available_eod / positions_known.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.osa_pct_intraday_floor IS 'Worst-case availability: positions never observed OOS during the day / positions_known.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.positions_available_eod IS 'Known positions in in_stock or low_stock state at the latest valid capture of the day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.positions_known IS 'Observed positions whose latest capture was a usable state (valid measurement and not unknown).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.positions_known_oos_any_time IS 'Subset of positions_known that were OOS at any point; numerator for intraday floor.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.positions_low_stock_eod IS 'Known positions in low_stock state at the latest valid capture of the day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.positions_misplaced_eod IS 'Known positions showing a misplaced product at the latest capture of the day (rare by construction).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.positions_oos_any_time IS 'Known positions that were observed in out_of_stock state at ANY point in the day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.positions_oos_eod IS 'Known positions in out_of_stock state at the latest valid capture of the day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.positions_unknown IS 'Observed positions whose latest capture was unknown or invalid — latest-capture-wins rule applies.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.positions_unobserved IS 'Expected positions with no capture that day — a coverage gap, never counted as available.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_osa_daily_current.trading_date IS 'Business date of the shelf observations.';
-- ========== gold_planogram_compliance_current ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.bmv_allocated_facings IS 'Facings allocated to this product in BMV planogram for comparison context.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.expected_facings_total IS 'Sum of expected facings from all assignments for this product.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.facing_compliance_pct IS 'Share of evaluable positions meeting facing targets.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.facing_compliant IS 'Count of positions where observed_facings >= expected_facings.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.facing_evaluable IS 'Count of positions evaluable for facing compliance.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.fresh_as_of_ts IS 'When the view was evaluated.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.fully_compliant_positions IS 'Positions compliant on all four evaluable dimensions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.fully_evaluable_positions IS 'Positions evaluable on all four dimensions (presence, position, facings, price).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.is_allocation_divergent IS 'TRUE when CSS expected_facings_total differs materially from bmv_allocated_facings.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.known_state_pct IS 'Share of observed positions in a known state: positions_known / observed_positions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.observation_coverage_pct IS 'Share of expected positions observed: observed_positions / positions_expected.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.observed_facings_total IS 'Sum of observed facings from all observations for this product.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.overall_compliance_pct IS 'Share of fully-evaluable positions that are fully compliant.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.position_compliance_pct IS 'Share of evaluable positions without misplacement.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.position_compliant IS 'Count of positions with no misplacement detected.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.position_evaluable IS 'Count of positions evaluable for misplacement.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.positions_expected IS 'Shelf positions with an assignment for this product on the trading_date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.positions_known IS 'Observed positions with a usable state (valid measurement and not unknown).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.positions_observed IS 'Positions with at least one observation on the trading_date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.positions_unknown IS 'Observed positions whose latest capture was unknown or invalid.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.positions_unobserved IS 'Expected positions with no capture — a coverage gap.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.presence_compliance_pct IS 'Share of evaluable positions with product present.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.presence_compliant IS 'Count of positions where shelf_state is in_stock or low_stock.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.presence_evaluable IS 'Count of positions evaluable for presence (usable observation).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.price_tag_compliance_pct IS 'Share of evaluable positions with correct price display.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.price_tag_compliant IS 'Count of positions with no price mismatch detected.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.price_tag_evaluable IS 'Count of positions evaluable for price-tag compliance.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_planogram_compliance_current.trading_date IS 'Business date of the shelf observations.';
-- ========== gold_price_accuracy_current ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.ack_observations IS 'Price observations from platform acknowledgement evidence.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.audit_observations IS 'Price observations from manual audits.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.avg_correction_hours IS 'Average hours from detection to price correction across corrected labels.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.avg_mismatch_abs_amount IS 'Average absolute price difference on mismatched labels.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.correction_hours_total IS 'Cumulative hours from detection to correction across all corrected labels.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.currency_code IS 'ISO 4217 reporting currency code.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.cv_observations IS 'Price observations from computer-vision shelf audits.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.fresh_as_of_ts IS 'When the view was evaluated.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.labels_corrected IS 'Count of labels that were corrected after detection.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.labels_evaluable IS 'Labels with a price of record for matching.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.labels_matched_eod IS 'Labels where displayed price matched the price of record at end-of-day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.labels_mismatched_eod IS 'Labels where displayed price did NOT match the price of record at end-of-day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.labels_observed IS 'Distinct ESL labels with at least one price observation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.labels_overcharging_eod IS 'Labels displaying a price higher than the price of record.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.labels_undercharging_eod IS 'Labels displaying a price lower than the price of record.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.max_mismatch_abs_amount IS 'Maximum absolute price difference on any mismatched label.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.max_open_mismatch_hours IS 'Hours elapsed on the longest-open (uncorrected) mismatch.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.price_match_rate_eod IS 'Share of evaluable labels matched at EOD: labels_matched_eod / labels_evaluable.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.price_observations IS 'Total price observations captured from labels.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.sync_latency_max_seconds IS 'Maximum latency from price update to label display acknowledgement.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.sync_latency_p50_seconds IS 'Median latency from price update to label display acknowledgement.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.sync_latency_p95_seconds IS '95th percentile latency from price update to label display acknowledgement.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_price_accuracy_current.trading_date IS 'Business date of the price observations.';
-- ========== gold_rfid_oos_candidates ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.absolute_unit_variance IS 'Absolute difference: |observed_units - book_units_eod|.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.book_units_eod IS 'End-of-day book inventory units at the reconciliation_date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.candidate_reason IS 'Always phantom_stock: positive EOD book stock with zero qualified physical evidence.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.candidate_severity IS 'Severity band by EOD book units with no physical evidence: high (10 or more), medium (3 or more), low otherwise. Illustrative demo bands.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.data_quality_flag IS 'Always TRUE: a phantom-stock candidate is by definition a suspected book-record data quality issue (SDI oos_event contract).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.detection_method IS 'Detection method: rfid.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.eligible_tagged_units IS 'Distinct serialized items eligible for the count.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.evidence_at_ts IS 'Timestamp of the supporting evidence.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.load_timestamp IS 'When the candidate was loaded into the warehouse.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.observed_units IS 'Distinct eligible items observed during the count session.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.product_sk IS 'Product surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.reconciliation_date IS 'EOD date of the reconciliation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.record_source IS 'Source system of the candidate record.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.rfid_count_session_id IS 'Durable RFID count session business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.rfid_count_session_sk IS 'RFID count session surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.rfid_oos_candidate_id IS 'Durable unique identifier for the candidate record.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_rfid_oos_candidates.store_sk IS 'Store surrogate key.';
-- ========== gold_share_of_shelf_current ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_share_of_shelf_current.brand IS 'Brand name.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_share_of_shelf_current.brand_facing_count IS 'Total facings for this brand within the category.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_share_of_shelf_current.category IS 'Merchandising category.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_share_of_shelf_current.category_facing_count IS 'Total facings for the entire category.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_share_of_shelf_current.fresh_as_of_ts IS 'When the view was evaluated.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_share_of_shelf_current.share_of_shelf_pct IS 'Brand facings as a percentage of category total: brand_facing_count / category_facing_count.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_share_of_shelf_current.store_id IS 'Durable store business key.';
-- ========== gold_shelf_state_current ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.assignment_source IS 'Source of the expected assignment: plano, bmv, or system.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.confidence_score IS 'Platform-specific confidence score for the observation (0-100 or equivalent).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.coverage_ratio IS 'Estimated percentage of the shelf position the device could observe.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.estimated_unit_count IS 'Estimated total units on shelf based on facings and depth observations.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.estimated_weight_grams IS 'Estimated total weight of products on shelf.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.expected_facing_count IS 'Expected number of facings from the assignment active at observation time.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.fresh_as_of_ts IS 'When the view was evaluated.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.freshness_age_minutes IS 'Minutes since observation_ts was captured at the evaluation clock.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.freshness_window_minutes IS 'Platform-dependent freshness window: typically 120 minutes for fixed devices, 1440 minutes for mobile.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.is_facing_compliant IS 'TRUE if observed_facing_count >= expected_facing_count; NULL if not usable or facing data missing.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.is_gap_detected IS 'TRUE if a gap or missing section was detected in the facing arrangement.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.is_misplaced_detected IS 'TRUE if a product other than expected was detected at this position.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.is_mobile_platform IS 'TRUE if the capture came from a mobile device (handheld or robot); FALSE for fixed shelf cameras.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.is_position_compliant IS 'TRUE if no misplacement was detected; NULL if not usable or misplacement state unknown.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.is_presence_compliant IS 'TRUE if the shelf_state is in_stock or low_stock (product present); NULL if not usable.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.is_price_tag_compliant IS 'TRUE if no price mismatch was detected; NULL if not usable or price data missing.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.is_price_tag_mismatch_detected IS 'TRUE if the displayed price did not match the expected price.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.is_stale IS 'TRUE if freshness_age_minutes exceeds the freshness_window_minutes.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.is_usable IS 'TRUE if the observation is usable for compliance evaluation: measurement_validity <> invalid AND shelf_state <> unknown.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.measurement_validity IS 'Validity of the measurement: valid, degraded, invalid, or imputed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.min_facing_count IS 'Minimum facing count from the assignment active at observation time.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.min_facing_threshold IS 'Minimum facing count threshold used for low-stock determination.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.observation_ts IS 'UTC timestamp of the shelf observation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.observed_facing_count IS 'Observed number of visible product facings.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.pick_count_since_prior IS 'Number of pick events observed since the prior observation at this position.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.product_sk IS 'Product surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.put_count_since_prior IS 'Number of put/replenishment events observed since the prior observation at this position.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.sensor_device_id IS 'Durable device business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.sensor_device_sk IS 'Sensor device surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.shelf_position_assignment_id IS 'Durable id of the expected assignment in effect at observation time.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.shelf_state IS 'Latest captured shelf state: in_stock, low_stock, out_of_stock, misplaced, or unknown.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.source_capture_id IS 'Unique identifier from the vendor capture.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.store_sk IS 'Store surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.store_zone_id IS 'Durable shelf-position zone business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.store_zone_sk IS 'Shelf-position zone surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.trading_date IS 'Business date of the observation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_state_current.zone_source IS 'How the shelf position was attributed: fixed device placement, operator declaration, or mobile-platform localization.';
-- ========== gold_shelf_vs_system_variance_daily ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.absolute_unit_variance IS 'Absolute value of unit_variance.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.book_units_eod IS 'End-of-day book inventory units from inventory systems.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.fresh_as_of_ts IS 'When the view was evaluated.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.is_over_book IS 'TRUE when observed_units_on_shelf > book_units_eod.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.is_phantom_stock IS 'TRUE when book_units_eod > 0 AND observed_units_on_shelf = 0.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.known_positions IS 'Observed positions with a usable state (not unknown or invalid).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.observed_positions IS 'Shelf positions observed for this product on the trading_date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.observed_units_on_shelf IS 'Estimated total units observed on shelf from all known positions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.positions_oos IS 'Known positions in out-of-stock state.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.trading_date IS 'Business date of the shelf observation and EOD book snapshot.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_shelf_vs_system_variance_daily.unit_variance IS 'Difference: observed_units_on_shelf - book_units_eod (positive = over book, negative = under book).';
-- ========== gold_zone_item_presence_current ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_item_presence_current.fresh_as_of_ts IS 'When the view was evaluated.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_item_presence_current.max_freshness_age_minutes IS 'Minutes since the newest supporting event at the evaluation clock.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_item_presence_current.newest_supporting_event_ts IS 'Timestamp of the newest read supporting current presence.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_item_presence_current.oldest_supporting_event_ts IS 'Timestamp of the oldest read supporting current presence.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_item_presence_current.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_item_presence_current.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_item_presence_current.store_zone_id IS 'Durable zone business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_item_presence_current.units_present IS 'Count of distinct serialized items currently attributed as present in the zone.';

-- ---- Remaining gold-view column documentation (coverage hardening) ----

-- ========== gold_count_session_summary ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.rfid_count_session_sk IS 'Surrogate key for the bounded RFID count session.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.rfid_count_session_id IS 'Durable key: store_id|source_session_id.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.source_session_id IS 'Source session identifier. For fixed windows without one: count_method|primary_sensor_device_id or _ALL|unix_timestamp(started_at_ts).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.store_sk IS 'Store surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.primary_sensor_device_sk IS 'Surrogate key of the initiating or primary sensor device. The complete device set derives from events.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.primary_sensor_device_id IS 'Durable id of the initiating or primary device.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.count_method IS 'RFID count method. Allowed values: handheld_sweep, fixed_window, robot_sweep.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.scope_type IS 'Representable scope claim. full_store has a derivable zone plan; partial makes no plan claim.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.started_at_ts IS 'Session start as a UTC instant.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.ended_at_ts IS 'Session end as a UTC instant.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.trading_date IS 'Business date of the session start.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.duration_minutes IS 'Session duration in minutes from started_at_ts to ended_at_ts.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.zones_covered IS 'Zones where read events were observed. For full_store scope, intersection of observed zones with planned zones; for partial scope, all observed zones.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.zones_missed IS 'Planned zones with no observed read events. NULL for partial_scope sessions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.units_observed IS 'Count of distinct serialized items (tagged_item_id) observed during the session, excluding stray reads.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.devices_observed IS 'Count of distinct sensor devices that reported read events in the session.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.first_event_ts IS 'Timestamp of the first non-stray read event in the session.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.last_event_ts IS 'Timestamp of the last non-stray read event in the session.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_count_session_summary.fresh_as_of_ts IS 'When the view was evaluated.';

-- ========== gold_store_traffic_daily_current - fiscal calendar ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.fiscal_year IS 'NRF fiscal year for the trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.fiscal_period IS 'NRF fiscal period for the trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.fiscal_week IS 'NRF fiscal week number (1-53 or 1-52) within the fiscal year.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.fiscal_week_id IS 'NRF fiscal week identifier, embedded with fiscal year for cross-year grouping.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.fiscal_week_index IS 'Monotonic index for fiscal weeks, used to order fiscal weeks across calendar years.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.day_of_week IS 'ISO day of week for the trading date (1 = Monday, 7 = Sunday).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.is_holiday IS 'TRUE when the trading date is a recognised retail holiday.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.footfall_delta_py IS 'Absolute difference: footfall_count - footfall_count_py. Prior-year change in count.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_store_traffic_daily_current.is_zero_observed IS 'TRUE when footfall_count = 0 AND any interval within the day carried is_zero_observed = TRUE. Distinguishes a measured zero from an offline sensor.';

-- ========== gold_zone_traffic_current ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.latest_store_zone_sk IS 'Surrogate key of the zone version effective at the latest interval of the trading_date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.zone_name IS 'Human-readable zone name from the version effective at the latest interval.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.is_sales_floor IS 'TRUE when the zone is customer-accessible selling space.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.trading_date IS 'Business date of the zone traffic observation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.fiscal_year IS 'NRF fiscal year for the trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.fiscal_week_id IS 'NRF fiscal week identifier.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.day_of_week IS 'ISO day of week for the trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.entry_count IS 'Measured entries into the zone for the day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.exit_count IS 'Measured exits from the zone for the day. NULL when the zone sensors are non-directional.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.dwell_seconds_total IS 'Sum of dwell durations in the zone. Numerator for zone-level dwell re-aggregation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.dwell_count IS 'Count of distinct dwell observations in the zone. Denominator for zone-level dwell re-aggregation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.avg_dwell_seconds IS 'dwell_seconds_total / dwell_count for the zone-day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.counting_unit IS 'What one count represents: person, group, device or object.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.staff_exclusion_enabled IS 'TRUE if staff were excluded from the operational count behind this zone-day row.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.avg_uptime_ratio IS 'Mean share of canonical interval duration the zone sensors were online.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.avg_coverage_ratio IS 'Mean share of expected sensors that reported for the zone.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.valid_interval_share IS 'Share of intervals whose measurement was valid for the zone.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.is_zero_observed IS 'TRUE when footfall_count = 0 AND any interval carried is_zero_observed = TRUE.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.interval_count IS 'Source intervals behind the zone-day aggregation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_traffic_current.fresh_as_of_ts IS 'When the view was evaluated.';

-- ========== gold_traffic_sales_productivity_current ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.trading_date IS 'Business date of the productivity observation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.fiscal_year IS 'NRF fiscal year for the trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.fiscal_week IS 'NRF fiscal week number within the fiscal year.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.fiscal_week_id IS 'NRF fiscal week identifier.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.fiscal_week_index IS 'Monotonic fiscal week index.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.day_of_week IS 'ISO day of week for the trading date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.is_holiday IS 'TRUE when the trading date is a recognised retail holiday.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.footfall_count IS 'Measured store footfall for the day. NOT a sum over zones.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.entry_count IS 'Measured entries for the day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.exit_count IS 'Measured exits for the day. NULL when entry direction is not observed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.visitor_count_adjusted IS 'Footfall after staff exclusion.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.avg_dwell_seconds IS 'Mean dwell duration in seconds.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.dwell_seconds_total IS 'Sum of all dwell durations for re-aggregation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.dwell_count IS 'Count of dwell observations for re-aggregation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.peak_occupancy IS 'Highest simultaneous occupancy for the day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.avg_occupancy IS 'Duration-weighted mean simultaneous occupancy.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.interval_minutes_total IS 'Total duration of valid traffic intervals.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.interval_count IS 'Number of intervals aggregated for the day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.footfall_count_py IS 'Footfall on the equivalent NRF fiscal week and weekday in the prior year.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.footfall_growth_py IS 'Fractional growth: (footfall_count - footfall_count_py) / footfall_count_py.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.gross_revenue IS 'Gross sales revenue before discounts at the store-day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.discount_amount IS 'Total discounts applied at the store-day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.counting_unit IS 'What one traffic count represents: person, group, device or object.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.staff_exclusion_enabled IS 'TRUE if staff were excluded from the traffic count.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.avg_coverage_ratio IS 'Mean share of expected traffic sensors that reported.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.valid_interval_share IS 'Share of intervals whose traffic measurement was valid.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.complete_interval_share IS 'Share of intervals where all data had fully landed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.is_zero_observed IS 'TRUE when footfall_count = 0 AND any interval carried is_zero_observed = TRUE.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_traffic_sales_productivity_current.fresh_as_of_ts IS 'When the view was evaluated.';

-- ========== gold_inventory_accuracy_daily ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.rfid_count_session_sk IS 'Surrogate key of the RFID count session.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.rfid_count_session_id IS 'Durable key of the count session: store_id|source_session_id.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.store_sk IS 'Store surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.product_sk IS 'Product surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.trading_date IS 'Business date of the session start.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.session_end_local_date IS 'Business date when the session ended in store local time.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.department IS 'Merchandise department classification.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.category IS 'Merchandise category classification.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.subcategory IS 'Merchandise subcategory classification.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.scope_type IS 'Count scope: full_store or partial indicates whether the session aimed to cover the entire store.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.observed_units IS 'Distinct serialized items observed for this product during the session.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.book_units_eod IS 'End-of-day book inventory units for the product at reconciliation_date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.unit_variance IS 'Difference: observed_units - book_units_eod. Positive = over book, negative = under book.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.absolute_unit_variance IS 'Absolute value of unit_variance.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.is_record_inaccuracy IS 'TRUE when observed_units <> book_units_eod (record discrepancy).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily.reconciled_at_ts IS 'Timestamp when the record was reconciled.';

-- ========== gold_inventory_accuracy_daily_latest - additional columns ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.store_sk IS 'Store surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.product_sk IS 'Product surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.reconciliation_basis IS 'Reconciliation basis: aligned_eod for full-store sessions in the declared window; misaligned for others.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.department IS 'Merchandise department classification.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.category IS 'Merchandise category classification.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.subcategory IS 'Merchandise subcategory classification.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.rfid_count_session_sk IS 'Surrogate key of the latest session selected within the store, product, reconciliation_date, and basis.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.session_trading_date IS 'Business date of the latest session selected for this store-product-reconciliation_date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.session_end_local_date IS 'Session end date in store local time.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.scope_type IS 'Count scope of the latest session: full_store or partial.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.eligible_tagged_units IS 'Distinct active serialized units eligible for the count.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.observed_units IS 'Distinct items observed in the latest session for this product.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.book_units_eod IS 'End-of-day book units at reconciliation_date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.unit_variance IS 'Difference: observed_units - book_units_eod.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.absolute_unit_variance IS 'Absolute value of unit_variance.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.inventory_accuracy_pct IS 'Observed-versus-EOD-book agreement for aligned_eod rows only; NULL for misaligned sessions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.observed_to_book_agreement_pct IS 'Agreement evidence for misaligned sessions; it must not be labeled inventory accuracy.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.is_phantom_stock IS 'TRUE when an aligned eligible product has positive EOD book stock and zero observed units.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.is_record_inaccuracy IS 'TRUE when observed_units <> book_units_eod.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_inventory_accuracy_daily_latest.reconciled_at_ts IS 'Timestamp when the latest record was reconciled.';

-- ========== gold_css_device_health - additional columns ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.trading_date IS 'Business date of the device health observation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.report_type IS 'Measurement type (e.g. gs1:Count for traffic sensors, gs1:Temperature for environmental monitoring).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.aggregation_level IS 'Reporting granularity level.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.sensor_device_id IS 'Durable device business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.sensor_device_sk IS 'Device surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.device_status IS 'Current status of the device: active, inactive, retired, or maintenance.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.store_zone_id IS 'Durable zone where the device is installed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.manufacturer IS 'Device manufacturer name.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.model IS 'Device model identifier.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.battery_powered IS 'TRUE if the device is battery-powered; FALSE if mains-powered or wired.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.intervals_reported IS 'Count of canonical intervals this device reported data in.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.observations_expected IS 'Expected observation count based on device expected reporting frequency for the day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.observations_received IS 'Actual count of observations delivered.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.avg_uptime_ratio IS 'Mean share of canonical interval duration the device was online.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.avg_coverage_ratio IS 'Mean share of expected sensors in the deployment group that reported alongside this device.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.valid_interval_share IS 'Share of reported intervals marked as measurement_validity = valid.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.invalid_intervals IS 'Count of intervals marked measurement_validity = invalid.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.imputed_intervals IS 'Count of intervals marked is_imputed = TRUE (modelled rather than measured).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.max_restatement_version IS 'Highest restatement_version encountered in the device data for the day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.last_interval_end_ts IS 'End timestamp of the most recent interval.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.last_ingest_ts IS 'Ingest timestamp of the most recent data arrival.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.avg_latency_seconds IS 'Mean latency from event timestamp to ingest timestamp.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.max_latency_seconds IS 'Maximum latency for any event.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.source_message_count IS 'Total count of source messages delivered for the device on the trading_date.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.calibration_valid_to IS 'Calibration expiration date for the device.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.calibration_certificate_id IS 'Identifier of the calibration certificate.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.sensing_deployment_id IS 'Durable id of the deployment this device belongs to.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.sensing_method_code IS 'Method code for the sensing technology (e.g. RFID, infrared, thermal).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.deployment_status IS 'Status of the deployment: active, pilot, retired.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_device_health.fresh_as_of_ts IS 'When the view was evaluated.';

-- ========== gold_css_automation_response - additional columns ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.device_status IS 'Status of the observing device at firing time: active, inactive, failed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.response_payload IS 'The actual payload delivered when the action fired (JSON or string representation).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.automation_action_id IS 'Durable id of the automation action that fired.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.payload_template IS 'Template used to generate response_payload.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.condition_operator IS 'The comparison applied by the rule (e.g. greater_than, less_than, inside_range).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.threshold_value_upper IS 'Upper bound for inside_range or outside_range operators, in the rule unit.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.time_window_seconds IS 'Rule time_window_seconds: the sustained-breach window that must hold before the rule fires.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.rule_uom_code IS 'UN/CEFACT unit code for the rule threshold (e.g. CEL for Celsius, NUM for count).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.actuator_status IS 'Status of the actuator at firing time: active, inactive, failed, or unknown.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.sensor_report_interval_id IS 'Durable id of the interval that triggered the firing (survives across SCD2 versions).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.breach_uom IS 'UN/CEFACT unit code for the breach_value (e.g. CEL for Celsius, NUM for count).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.interval_end_ts IS 'End timestamp of the triggering canonical interval.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_automation_response.fresh_as_of_ts IS 'When the view was evaluated.';

-- ========== gold_received_verification - additional columns ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_receiving_verification.window_start_ts IS 'Start of the receiving window interval (UTC).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_receiving_verification.window_end_ts IS 'End of the receiving window interval (UTC).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_receiving_verification.observed_units IS 'Distinct serialized items observed within the receiving window.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_receiving_verification.unit_variance IS 'Difference: observed_units - expected_units.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_receiving_verification.verification_status IS 'Outcome of the receiving verification: matched, over_received, short_received.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_receiving_verification.shipment_line_sk IS 'Surrogate key of the shipment line.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_receiving_verification.shipment_line_id IS 'Durable id of the shipment line.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_receiving_verification.shipment_id IS 'Durable id of the purchase order or shipment.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_receiving_verification.store_id IS 'Durable store business key where receiving was observed.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_receiving_verification.product_id IS 'Durable product business key.';

-- ========== gold_unaccounted_exits - additional columns ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.unaccounted_exit_id IS 'Durable unique identifier for the unaccounted exit event.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.tagged_item_sk IS 'Serialized item surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.tagged_item_id IS 'Durable EPC Pure Identity URI (serialized item business key).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.product_sk IS 'Product surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.store_sk IS 'Store surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.store_zone_sk IS 'Zone surrogate key where the exit was detected.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.store_zone_id IS 'Durable zone business key where the exit was detected.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.sensor_device_sk IS 'Device surrogate key that detected the exit.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.sensor_device_id IS 'Durable device business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.exit_event_ts IS 'UTC timestamp of the exit event.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.trading_date IS 'Business date of the exit event.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.direction_confidence IS 'Confidence score for the exit direction detection.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.attribution_confidence IS 'Confidence score for the store-zone attribution.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.disposition_uri IS 'GS1 CBV disposition URI (e.g. active, damaged, stolen).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_unaccounted_exits.biz_step_uri IS 'GS1 CBV business step URI describing the event context.';

-- ========== gold_zone_count_coverage - additional columns ==========
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.store_sk IS 'Store surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.store_zone_sk IS 'Zone surrogate key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.store_zone_id IS 'Durable zone business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.zone_code IS 'Zone code from the current dimension version.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.zone_name IS 'Human-readable zone name.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.zone_type IS 'Depth or role in the spatial hierarchy.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.is_sales_floor IS 'TRUE when the zone is customer-accessible selling space.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.last_counted_date IS 'Most recent trading_date on which this zone was covered by a count session.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.days_since_last_count IS 'Calendar days between last_counted_date and fresh_as_of_ts.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.is_overdue IS 'TRUE when days_since_last_count > target_cadence_days.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.lifetime_units_observed IS 'Cumulative distinct items ever observed in this zone across all sessions.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_zone_count_coverage.fresh_as_of_ts IS 'When the view was evaluated.';

-- ---- IoT environmental-monitoring gold-view column documentation ----

-- ========== gold_css_environmental_compliance_daily ==========

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.store_id IS 'Durable store business key.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.sensor_device_id IS 'Durable device business key of the environmental/temperature sensor.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.subject_type IS 'Kind of measured subject within the device (for example point for a refrigerated case). Part of the grain.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.subject_id IS 'Measured subject within the device, interpreted per subject_type (for example one case on a multi-channel logger). Part of the grain.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.equipment_id IS 'Durable equipment business key (refrigeration unit) that the sensor monitors. NULL for ambient sensors.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.report_type IS 'The environmental property measured (e.g. gs1:Temperature). Matches the report_type evaluation_rule watches.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.trading_date IS 'Business date of the compliance observation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.reading_count IS 'All intervals the device reported for the property on the day, any measurement_validity.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.valid_reading_count IS 'Intervals with measurement_validity = valid and a non-NULL value. Denominator for the value statistics.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.min_value IS 'Lowest valid reading of the day, in the measurement unit. Invalid, degraded and imputed intervals are excluded.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.max_value IS 'Highest valid reading of the day, in the measurement unit. For a cold-chain upper limit this is the peak temperature.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.avg_value IS 'Mean valid reading of the day: value_sum / valid_reading_count_for_avg.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.value_sum IS 'Sum of valid readings. Carried with valid_reading_count_for_avg so the mean re-aggregates correctly at any grain.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.valid_reading_count_for_avg IS 'Denominator of avg_value; equals valid_reading_count. Carried for transparent re-aggregation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.evaluation_rule_id IS 'Durable id of the current enabled rule this row is evaluated against. NULL when no current rule watches the device and property. Part of the grain.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.condition_operator IS 'The comparison applied by the rule (e.g. greater_than, inside_range). NULL if no rule.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.threshold_value IS 'Lower bound or single threshold from the rule, in the measurement unit. NULL if no rule.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.threshold_value_upper IS 'Upper bound for inside_range or outside_range operators. NULL otherwise.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.uom_code IS 'UN/CEFACT unit code (e.g. CEL for Celsius). From the rule when present.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.time_window_seconds IS 'Sustained-breach window from the rule, carried for context. Not applied here: a single breaching interval counts.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.evaluated_interval_count IS 'Valid intervals evaluated against a rule. Denominator of share_intervals_in_range; carried so the compliance rate re-aggregates as a ratio of sums.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.breach_interval_count IS 'Valid intervals whose value satisfies the rule firing condition. Evaluated from the readings, independent of whether automation fired.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.minutes_outside_range IS 'Sum of interval_minutes over breaching intervals: total minutes the asset was beyond the rule limit on the day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.share_intervals_in_range IS 'Share of evaluated valid intervals that did not breach: (evaluated - breaches) / evaluated. NULL when no rule applies or no valid readings exist.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.is_compliant IS 'TRUE when no valid reading breached the rule on the day, FALSE when at least one did, NULL when no rule applies or there were no valid readings. Measured against the configured rule, not a regulation.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_environmental_compliance_daily.fresh_as_of_ts IS 'When the view was evaluated.';

-- ========== gold_css_excursion_episodes ==========

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.store_id IS 'Durable store business key of the device that reported the episode.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.sensor_device_id IS 'Durable device business key of the sensor that detected the excursion.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.subject_type IS 'Kind of measured subject within the device (for example point for a refrigerated case). Part of the grain.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.subject_id IS 'Measured subject within the device, interpreted per subject_type (for example one case on a multi-channel logger). Part of the grain.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.equipment_id IS 'Durable equipment business key being monitored (the asset experiencing the excursion).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.evaluation_rule_id IS 'Durable id of the rule whose breach defined this episode.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.episode_start_ts IS 'UTC timestamp of the first breaching interval in the episode.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.episode_end_ts IS 'UTC timestamp of the last breaching interval in the episode. Episodes are maximal contiguous runs; a gap >1 interval_minutes ends the episode.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.trading_date_of_start IS 'Business date of the episode start, for time-zone-aware period grouping.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.interval_count IS 'Contiguous breaching intervals in the episode.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.duration_minutes IS 'Sum of interval_minutes across the episode intervals.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.peak_value IS 'Worst reading in the episode in the direction of the rule: the maximum for upper limits and ranges, the minimum for lower limits.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.firings IS 'Non-skipped execution_log firings of the episode rule whose triggering interval is one of the episode intervals.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.successful_firings IS 'Firings in the episode window with execution_status = success.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.failed_firings IS 'Firings in the episode window with execution_status = failure.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.first_firing_ts IS 'Timestamp of the first automation firing triggered by this episode. NULL if no firings occurred.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.minutes_to_first_successful_action IS 'Minutes from episode start to the first successful firing triggered by an episode interval. NULL when none succeeded.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.has_successful_action IS 'TRUE when at least one firing triggered by an episode interval succeeded. Evidence that the loop responded, not proof that it ended the excursion.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.is_open_at_dataset_end IS 'TRUE when the episode ends at the latest interval the device reported for this property, meaning the excursion may still be ongoing.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.fresh_as_of_ts IS 'When the view was evaluated.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.report_type IS 'The monitored property of the episode, for example gs1:Temperature.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.condition_operator IS 'Firing condition of the rule that defines the breach, for example greater_than.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_excursion_episodes.peak_exceedance IS 'How far the episode went past the rule limit, in the rule unit: peak minus threshold for upper limits, threshold minus trough for lower limits, the larger excess for outside_range. NULL for equality and inside_range rules.';

-- ========== gold_css_rule_effectiveness_daily ==========

COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.store_id IS 'Durable store business key of the interval that triggered the firings.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.evaluation_rule_id IS 'Durable id of the control-loop rule. Multiple rows per store if several rules fire.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.trading_date IS 'Business date of the interval that triggered the firings.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.firings IS 'Non-skipped execution_log firings of the rule on the day, the same definition as gold_css_excursion_episodes.firings.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.successful_firings IS 'Firings that completed with execution_status = success.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.failed_firings IS 'Firings that completed with execution_status = failure.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.other_status_firings IS 'Firings with status pending or timeout (skipped firings are excluded from this view).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.distinct_actions IS 'Distinct automation_action_id values that fired off this rule on the day. A distinct count: do not sum across days or rules.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.physical_command_firings IS 'Firings where target_entity_type = actuator (physical device commands, not notifications or webhooks).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.notification_firings IS 'Firings whose action targets a role or person (alerts, not physical actuation).';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.avg_latency_ms IS 'Mean milliseconds from the breaching observation to the firing. Automation-loop responsiveness, not ingest latency.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.latency_ms_sum IS 'Sum of latency_ms over firings with a recorded latency. Numerator of the ratio-of-sums mean latency for rollups.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.latency_measured_firings IS 'Firings with a non-NULL latency_ms. Denominator of the ratio-of-sums mean latency for rollups.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.max_latency_ms IS 'Worst-case response latency observed for this rule on the day.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.success_rate_numerator IS 'Successful firings (execution_status = success). Numerator of the ratio-of-sums success rate.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.success_rate_denominator IS 'Completed firings (success, failure or timeout). Denominator of the ratio-of-sums success rate; pending and skipped are excluded.';
COMMENT ON COLUMN ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily.fresh_as_of_ts IS 'When the view was evaluated.';
