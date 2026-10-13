-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals · data-quality checks
-- Version: 0.5 · Generated: 2026-07-28 · LLM-generated: true · Reviewed: 2026-07-28
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report a
-- value and never fail. Run by runtime/data-quality/run_checks.py.
--
-- Grain integrity: the `*_grain_unique` checks assert the DURABLE business key
-- (`<table>_id`). For sensor_report_interval the surrogate is a HASH, not an identity
-- (ADR 0028 — Hash surrogate keys for high-volume gold event facts), so a `_sk`
-- uniqueness test is NOT a tautology here -- it is a real
-- collision test, and sri_sk_collision is that test.
--
-- Prefixes: sri_ = sensor_report_interval, ftid_ = foot_traffic_interval_detail,
-- sd_ = sensor_device, sz_ = store_zone, sdep_ = sensing_deployment,
-- sdp_ = sensing_disclosure_policy, css_ = cross-cutting,
-- ssa_ = shelf_position_assignment, sso_ = shelf_state_observation,
-- esll_ = esl_label, esla_ = esl_label_assignment, eslp_ = esl_price_observation.
--
-- Honest note on enforcement: DQ-FACT-COVERAGE is a PLANNED rule in
-- standards/rules.yaml with no CI test, and PK-CONTRACT / TYPING-MONEY /
-- FK-COMPLETENESS are enforced canonical-core-only. So for a gold package these checks
-- are hand-maintained and reviewer attention is the real gate -- which argues for
-- fewer, higher-value checks over exhaustive per-table boilerplate.
-- ============================================================

-- ========== sensor_report_interval: the invariants this design depends on ==========

-- A space-scoped count is Foot Traffic and therefore has exactly one traffic-detail
-- row. Non-space gs1:Count envelopes remain valid for RFID item counts and Smart Shelf
-- unit counts without inheriting traffic semantics.
-- check: ftid_space_count_requires_detail | severity: error
SELECT f.sensor_report_interval_id
FROM ${catalog}.${css_schema}.sensor_report_interval f
LEFT JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
  ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
WHERE f.report_type = 'gs1:Count'
  AND f.subject_type = 'space'
GROUP BY f.sensor_report_interval_id
HAVING COUNT(t.sensor_report_interval_sk) <> 1;

-- Other report types cannot acquire traffic semantics through the extension.
-- check: ftid_noncount_report_forbids_detail | severity: error
SELECT f.sensor_report_interval_id
FROM ${catalog}.${css_schema}.sensor_report_interval f
JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
  ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
WHERE f.report_type <> 'gs1:Count' OR f.subject_type <> 'space';

-- check: sri_grain_unique | severity: error
SELECT sensor_report_interval_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.sensor_report_interval GROUP BY sensor_report_interval_id HAVING COUNT(*) > 1;

-- Hash-surrogate collision guard. Mandated by ADR 0028 — Hash surrogate keys for
-- high-volume gold event facts: xxhash64 is 64-bit, so
-- collision probability becomes non-trivial around ~5e9 distinct values.
-- check: sri_sk_collision | severity: error
SELECT sensor_report_interval_sk, COUNT(DISTINCT sensor_report_interval_id) AS n FROM ${catalog}.${css_schema}.sensor_report_interval GROUP BY sensor_report_interval_sk HAVING COUNT(DISTINCT sensor_report_interval_id) > 1;

-- check: sri_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensor_report_interval WHERE sensor_report_interval_sk IS NULL OR sensor_report_interval_id IS NULL OR subject_type IS NULL OR subject_id IS NULL OR report_type IS NULL OR aggregation_level IS NULL OR interval_start_ts IS NULL OR interval_minutes IS NULL OR trading_date IS NULL;

-- A NULL inside a concatenated grain key silently collapses rows. Cross-device
-- aggregates must use the explicit '_ALL' sentinel.
-- check: sri_device_id_sentinel | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensor_report_interval WHERE sensor_device_id IS NULL;

-- The grain key must actually contain every varying component, or two legitimately
-- different rows collide. Reconstructing it is the only way to catch a generator or
-- pipeline that builds the key differently from the contract.
--
-- The interval component is EPOCH SECONDS, not CAST(interval_start_ts AS STRING). That
-- looks like a readability regression and is in fact the only correct option: Databricks
-- TIMESTAMP is TIMESTAMP_LTZ, so casting one to STRING renders it in the READER's
-- spark.sql.session.timeZone. A key built that way is not a property of the row -- the
-- same logical interval written under UTC and under America/Los_Angeles gets two different
-- durable ids and therefore two different surrogates, so a restatement INSERTS instead of
-- updating. unix_timestamp() reads the underlying instant and is session-independent.
-- check: sri_grain_key_wellformed | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensor_report_interval
WHERE sensor_report_interval_id <> concat_ws('|', subject_type, subject_id, report_type, aggregation_level, CAST(interval_minutes AS STRING), CAST(unix_timestamp(interval_start_ts) AS STRING), sensor_device_id);

-- check: sri_sk_matches_id | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensor_report_interval WHERE sensor_report_interval_sk <> xxhash64(sensor_report_interval_id);

-- ---------- Additivity: one canonical non-overlapping interval series ----------

-- A vendor-native hourly interval cannot coexist with four canonical 15-minute rows in
-- the same series. Device identity is provenance, not additive-series identity: a
-- cross-device `_ALL` rollup, or a second device-native total, cannot coexist with
-- another row for the same subject/report/level window. Vendor rollups and unreconciled
-- device constituents remain in Bronze or a reconciliation tier.
-- check: sri_canonical_interval_overlap | severity: error
SELECT
  a.sensor_report_interval_id AS left_id,
  b.sensor_report_interval_id AS right_id
FROM ${catalog}.${css_schema}.sensor_report_interval a
JOIN ${catalog}.${css_schema}.sensor_report_interval b
 ON a.subject_type = b.subject_type
 AND a.subject_id = b.subject_id
 AND a.report_type = b.report_type
 AND a.aggregation_level = b.aggregation_level
 AND a.sensor_report_interval_id < b.sensor_report_interval_id
 AND a.interval_start_ts < b.interval_end_ts
 AND b.interval_start_ts < a.interval_end_ts;

-- Rows summed together must share the same counting convention, or the sum is
-- meaningless: one vendor headline count means visitor GROUPS with group counting enabled and
-- individual PEOPLE without it.
--
-- The grouping is the rows that ACTUALLY get summed, which is a per-zone question at area
-- level. An earlier version grouped by store, date and level only, so every zone in a store
-- landed in one bucket and a heterogeneous estate -- an entrance beam counter with group
-- counting off, an overhead sensor in grocery with it on -- failed at error severity even
-- though zone rows are never summed across zones. store_zone_sk is NULL on site rows, so one
-- GROUP BY covers both levels: site rows still collapse into a single per-store bucket.
--
-- time_mode and staff_exclusion_stage are in the distinct-count set because the gold views
-- collapse them with MIN()/MAX() and cite THIS check as the reason that is safe. time_mode
-- was missing, so an operating-hours row and an all-day row for the same store-day silently
-- resolved to whichever sorted first.
-- check: ftid_counting_convention_uniform | severity: error
SELECT f.store_id, f.trading_date, f.aggregation_level, f.store_zone_sk,
       COUNT(DISTINCT counting_unit) AS units,
       COUNT(DISTINCT group_counting_enabled) AS grp,
       COUNT(DISTINCT staff_exclusion_enabled) AS staff,
       COUNT(DISTINCT staff_exclusion_stage) AS stage,
       COUNT(DISTINCT time_mode) AS modes
FROM ${catalog}.${css_schema}.sensor_report_interval f
JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
  ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
WHERE f.report_type = 'gs1:Count'
GROUP BY f.store_id, f.trading_date, f.aggregation_level, f.store_zone_sk
HAVING COUNT(DISTINCT counting_unit) > 1 OR COUNT(DISTINCT group_counting_enabled) > 1
    OR COUNT(DISTINCT staff_exclusion_enabled) > 1 OR COUNT(DISTINCT staff_exclusion_stage) > 1
    OR COUNT(DISTINCT time_mode) > 1;

-- A non-directional sensor cannot report exits. The honest value is NULL; 0 is a lie
-- that silently balances the occupancy equation.
-- check: ftid_nondirectional_exits_null | severity: error
SELECT t.* FROM ${catalog}.${css_schema}.foot_traffic_interval_detail t
JOIN ${catalog}.${css_schema}.sensor_report_interval f
  ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
WHERE f.report_type = 'gs1:Count' AND t.directionality = 'none' AND t.exit_count IS NOT NULL;

-- ---------- Time ----------

-- trading_date must agree with the local date implied by the UTC instant plus the
-- offset, allowing for stores that trade past midnight.
--
-- Computed entirely in EPOCH SPACE, for exactly the reason ADR 0028 — Hash surrogate
-- keys for high-volume gold event facts — gives for the grain key.
-- The obvious form -- CAST(interval_start_ts + make_interval(...) AS DATE) -- resolves the
-- cast in spark.sql.session.timeZone, because Databricks TIMESTAMP is TIMESTAMP_LTZ. That
-- made an ERROR-severity check's verdict a property of whoever ran the build: the repo's own
-- fixture passes under a UTC session and flags 6 rows under America/Los_Angeles. Every other
-- part of this package warns about this trap; the check that polices time had inherited it.
-- date_from_unix_date takes a day number, and FLOOR gives the right answer for pre-epoch
-- dates where integer division truncates toward zero.
-- check: sri_time_agreement | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensor_report_interval
WHERE utc_offset_minutes IS NOT NULL
  AND trading_date <> date_add(
        date_from_unix_date(
          CAST(FLOOR((unix_timestamp(interval_start_ts) + utc_offset_minutes * 60) / 86400) AS INT)),
        -COALESCE(trading_day_offset, 0));

-- The DST guard. Without the offset the autumn fold produces two rows that cannot be
-- distinguished, so one silently overwrites the other once a year.
-- check: sri_utc_offset_present | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensor_report_interval WHERE utc_offset_minutes IS NULL;

-- check: sri_interval_end_after_start | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensor_report_interval WHERE interval_end_ts IS NOT NULL AND interval_end_ts <= interval_start_ts;

-- Declared cadence and physical interval boundaries must agree.
-- check: sri_interval_duration_agreement | severity: error
SELECT *
FROM ${catalog}.${css_schema}.sensor_report_interval
WHERE interval_end_ts IS NULL
   OR unix_timestamp(interval_end_ts) - unix_timestamp(interval_start_ts)
      <> interval_minutes * 60;

-- Report uncovered time between consecutive canonical rows. Gaps are operational
-- telemetry, not necessarily invalid data, so this is a metric rather than a failure.
-- check: sri_series_gap_metric | severity: metric
WITH sequenced AS (
  SELECT
    subject_type,
    subject_id,
    report_type,
    aggregation_level,
    sensor_device_id,
    interval_start_ts,
    LAG(interval_end_ts) OVER (
      PARTITION BY subject_type, subject_id, report_type, aggregation_level, sensor_device_id
      ORDER BY interval_start_ts
    ) AS previous_interval_end_ts
  FROM ${catalog}.${css_schema}.sensor_report_interval
)
SELECT
  subject_type,
  subject_id,
  report_type,
  aggregation_level,
  sensor_device_id,
  SUM(
    GREATEST(
      unix_timestamp(interval_start_ts) - unix_timestamp(previous_interval_end_ts),
      0
    )
  ) AS uncovered_seconds
FROM sequenced
WHERE previous_interval_end_ts IS NOT NULL
GROUP BY subject_type, subject_id, report_type, aggregation_level, sensor_device_id;

-- check: sri_source_observation_bounds | severity: error
SELECT *
FROM ${catalog}.${css_schema}.sensor_report_interval
WHERE source_observation_count IS NOT NULL
  AND expected_observation_count IS NOT NULL
  AND (
    source_observation_count < 0
    OR expected_observation_count < 0
    OR source_observation_count > expected_observation_count
  );

-- check: sri_source_message_summary_bounds | severity: error
SELECT *
FROM ${catalog}.${css_schema}.sensor_report_interval
WHERE COALESCE(source_message_count, 0) < 0
   OR COALESCE(sequence_gap_count, 0) < 0
   OR COALESCE(duplicate_delivery_count, 0) < 0
   OR COALESCE(historical_message_count, 0) < 0
   OR COALESCE(bad_quality_message_count, 0) < 0;

-- The comment-only calendar join (see relationships.sql) still needs orphan coverage --
-- it just cannot be a constraint.
-- check: sri_calendar_orphan | severity: error
SELECT f.* FROM ${catalog}.${css_schema}.sensor_report_interval f
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON f.trading_date = c.date_key
WHERE c.date_key IS NULL;

-- ---------- Staff, occupancy, dwell ----------

-- check: ftid_staff_adjustment_balances | severity: error
SELECT * FROM ${catalog}.${css_schema}.foot_traffic_interval_detail
WHERE staff_adjustment_applied = TRUE
  AND visitor_count_raw IS NOT NULL
  AND staff_count IS NOT NULL
  AND visitor_count_adjusted IS NOT NULL
  AND visitor_count_adjusted <> visitor_count_raw - staff_count;

-- Children are a subset of footfall, not an exclusion from it.
-- check: ftid_child_subset | severity: error
SELECT * FROM ${catalog}.${css_schema}.foot_traffic_interval_detail WHERE child_count IS NOT NULL AND footfall_count IS NOT NULL AND child_count > footfall_count;

-- Negative occupancy is drift, and drift must be visible. This is a check rather than
-- a CHECK constraint precisely so the offending row SURVIVES to be investigated.
-- check: ftid_occupancy_nonnegative | severity: warn
SELECT * FROM ${catalog}.${css_schema}.foot_traffic_interval_detail WHERE occupancy_snapshot_end IS NOT NULL AND occupancy_snapshot_end < 0;

-- check: ftid_occupancy_balance | severity: warn
SELECT * FROM ${catalog}.${css_schema}.foot_traffic_interval_detail
WHERE occupancy_snapshot_end IS NOT NULL AND cumulative_entries IS NOT NULL AND cumulative_exits IS NOT NULL
  AND occupancy_snapshot_end <> cumulative_entries - cumulative_exits + COALESCE(occupancy_adjustment, 0);

-- Entries and exits are independently measured and never exactly equal (a vendor
-- own worked example returns 173 in / 174 out for the same day, both flagged complete).
-- A large divergence is a real fault; a small one is physics.
-- check: ftid_entry_exit_reconciliation | severity: warn
SELECT f.store_id, f.trading_date, SUM(t.entry_count) AS entries, SUM(t.exit_count) AS exits
FROM ${catalog}.${css_schema}.sensor_report_interval f
JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
  ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
WHERE f.report_type = 'gs1:Count' AND f.aggregation_level = 'site' AND t.directionality <> 'none'
GROUP BY f.store_id, f.trading_date
HAVING SUM(entry_count) > 0 AND ABS(SUM(entry_count) - SUM(exit_count)) > 0.05 * SUM(entry_count);

-- Occupancy above a known safe capacity is either a real safety event or a broken
-- counter. Either way somebody should look.
-- check: ftid_occupancy_within_capacity | severity: warn
SELECT f.sensor_report_interval_id, t.occupancy_max, z.capacity_persons
FROM ${catalog}.${css_schema}.sensor_report_interval f
JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
  ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
JOIN ${catalog}.${css_schema}.store_zone z ON f.store_zone_id = z.store_zone_id AND z.is_current = TRUE
WHERE t.occupancy_max IS NOT NULL AND z.capacity_persons IS NOT NULL AND t.occupancy_max > z.capacity_persons;

-- Dwell is stored as SUM + COUNT so it can be re-aggregated. A numerator without a
-- denominator cannot be.
-- check: ftid_dwell_denominator_present | severity: error
SELECT * FROM ${catalog}.${css_schema}.foot_traffic_interval_detail WHERE dwell_seconds_total IS NOT NULL AND dwell_seconds_total > 0 AND (dwell_count IS NULL OR dwell_count = 0);

-- ---------- EPCIS conformance ----------

-- Per the EPCIS 2.0 spec: sDev is meaningful only with meanValue, and percValue only
-- with percRank. A dangling deviation or percentile is not a partial measurement, it is
-- an uninterpretable one.
--
-- NOTE what is deliberately NOT asserted here. EPCIS states a SensorReport carries
-- either a type or an exception, but in this model report_type is NOT NULL because it is
-- the grain discriminator (ADR 0032) -- so an exception row still carries the type of
-- the thing that alarmed, and forbidding the combination would make exception_code
-- unreachable. That is a conscious divergence from the spec's cardinality, made because
-- the discriminator has to be total for the one-table decision to work.
-- check: sri_epcis_field_pairing | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensor_report_interval
WHERE (s_dev IS NOT NULL AND mean_value IS NULL)
   OR (perc_value IS NOT NULL AND perc_rank IS NULL);

-- A value without a unit is not a measurement. Counts are the exception: a person count
-- is dimensionless.
-- check: sri_uom_present | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensor_report_interval WHERE value IS NOT NULL AND report_type <> 'gs1:Count' AND uom IS NULL AND unit_iri IS NULL;

-- ---------- Quality and completeness ----------

-- Expected vs actual interval coverage, using is_zero_observed to separate a measured
-- zero from an absent row. Reported, never failed -- coverage is a fact about the
-- estate, not a defect in the data.
-- check: sri_zero_vs_missing | severity: metric
SELECT trading_date, store_id,
       COUNT(*) AS rows_present,
       SUM(CASE WHEN t.is_zero_observed THEN 1 ELSE 0 END) AS observed_zeros,
       SUM(CASE WHEN arrival_completeness = 'incomplete' THEN 1 ELSE 0 END) AS incomplete_rows,
       AVG(COALESCE(coverage_ratio, 0)) AS avg_coverage
FROM ${catalog}.${css_schema}.sensor_report_interval f
JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
  ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
WHERE f.report_type = 'gs1:Count'
GROUP BY f.trading_date, f.store_id;

-- A capped reading must say what ceiling it hit, or the cap is uninterpretable.
-- check: sri_capped_limit_present | severity: warn
SELECT * FROM ${catalog}.${css_schema}.sensor_report_interval WHERE is_capped = TRUE AND capped_count_limit IS NULL;

-- ---------- FK orphans ----------

-- check: sri_store_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${css_schema}.sensor_report_interval f LEFT JOIN ${catalog}.${store_schema}.store s ON f.store_sk = s.store_sk WHERE f.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: sri_zone_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${css_schema}.sensor_report_interval f LEFT JOIN ${catalog}.${css_schema}.store_zone z ON f.store_zone_sk = z.store_zone_sk WHERE f.store_zone_sk IS NOT NULL AND z.store_zone_sk IS NULL;

-- check: sri_device_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${css_schema}.sensor_report_interval f LEFT JOIN ${catalog}.${css_schema}.sensor_device d ON f.sensor_device_sk = d.sensor_device_sk WHERE f.sensor_device_sk IS NOT NULL AND d.sensor_device_sk IS NULL;

-- check: sri_deployment_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${css_schema}.sensor_report_interval f LEFT JOIN ${catalog}.${css_schema}.sensing_deployment p ON f.sensing_deployment_sk = p.sensing_deployment_sk WHERE f.sensing_deployment_sk IS NOT NULL AND p.sensing_deployment_sk IS NULL;

-- check: sri_product_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${css_schema}.sensor_report_interval f LEFT JOIN ${catalog}.${product_schema}.product p ON f.product_sk = p.product_sk WHERE f.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: sri_equipment_fk_orphan | severity: error
SELECT f.* FROM ${catalog}.${css_schema}.sensor_report_interval f LEFT JOIN ${catalog}.${equipment_schema}.equipment e ON f.equipment_sk = e.equipment_sk WHERE f.equipment_sk IS NOT NULL AND e.equipment_sk IS NULL;

-- The traffic extension points BACK at the envelope, so the orphan can face the other way:
-- a foot_traffic_interval_detail row whose sensor_report_interval_sk has no parent interval.
-- The two 1:1 checks above (ftid_space_count_requires_detail / ftid_noncount_report_forbids_detail)
-- INNER-join from the fact, so a detail row with no matching envelope row is invisible to
-- them -- it simply never enters the join. UC does not enforce the declared FK, so this
-- anti-join is the only thing that catches a detail row orphaned by a mis-hashed key or a
-- deleted parent, which would otherwise double- or mis-count in the gold joins.
-- check: ftid_interval_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${css_schema}.foot_traffic_interval_detail t LEFT JOIN ${catalog}.${css_schema}.sensor_report_interval f ON t.sensor_report_interval_sk = f.sensor_report_interval_sk WHERE f.sensor_report_interval_sk IS NULL;

-- The asset key pair must agree with the device registry where both are present. They are
-- allowed to differ from NULL (an ambient sensor reporting a space has no asset) but never
-- to disagree, which would mean two answers to "which case was this reading about".
-- check: sri_equipment_agrees_with_device | severity: error
SELECT f.sensor_report_interval_id, f.equipment_sk AS fact_equipment_sk, d.equipment_sk AS device_equipment_sk
FROM ${catalog}.${css_schema}.sensor_report_interval f
JOIN ${catalog}.${css_schema}.sensor_device d ON f.sensor_device_sk = d.sensor_device_sk
WHERE f.equipment_sk IS NOT NULL AND d.equipment_sk IS NOT NULL AND f.equipment_sk <> d.equipment_sk;

-- ========== Shared-view disclosure invariants ==========
-- ADR 0029 — Aggregate-only sensing schema with policy-driven shared disclosure
-- ADR 0030 — In-store sensing signals are never an upstream dependency of pricing

-- Operational facts and views remain complete. These checks apply only to explicit
-- shared projections and their effective disclosure policy.
-- check: shared_suppression_threshold | severity: error
SELECT 'zone' AS shared_view, s.store_id, s.trading_date, s.footfall_count
FROM ${catalog}.${css_schema}.gold_zone_traffic_shared s
JOIN ${catalog}.${css_schema}.sensing_disclosure_policy p
  ON s.sensing_disclosure_policy_id = p.sensing_disclosure_policy_id
 AND s.trading_date >= p.effective_from_date
 AND (p.effective_to_date IS NULL OR s.trading_date < p.effective_to_date)
WHERE s.footfall_count IS NOT NULL
  AND s.footfall_count < p.k_threshold
UNION ALL
SELECT 'store' AS shared_view, s.store_id, s.trading_date, s.footfall_count
FROM ${catalog}.${css_schema}.gold_store_traffic_daily_shared s
JOIN ${catalog}.${css_schema}.sensing_disclosure_policy p
  ON s.sensing_disclosure_policy_id = p.sensing_disclosure_policy_id
 AND s.trading_date >= p.effective_from_date
 AND (p.effective_to_date IS NULL OR s.trading_date < p.effective_to_date)
WHERE s.footfall_count IS NOT NULL
  AND s.footfall_count < p.k_threshold;

-- check: shared_zero_suppression | severity: error
SELECT 'zone' AS shared_view, s.store_id, s.trading_date, s.footfall_count
FROM ${catalog}.${css_schema}.gold_zone_traffic_shared s
JOIN ${catalog}.${css_schema}.sensing_disclosure_policy p
  ON s.sensing_disclosure_policy_id = p.sensing_disclosure_policy_id
 AND s.trading_date >= p.effective_from_date
 AND (p.effective_to_date IS NULL OR s.trading_date < p.effective_to_date)
WHERE p.suppress_zero_flag = TRUE
  AND s.footfall_count = 0
UNION ALL
SELECT 'store' AS shared_view, s.store_id, s.trading_date, s.footfall_count
FROM ${catalog}.${css_schema}.gold_store_traffic_daily_shared s
JOIN ${catalog}.${css_schema}.sensing_disclosure_policy p
  ON s.sensing_disclosure_policy_id = p.sensing_disclosure_policy_id
 AND s.trading_date >= p.effective_from_date
 AND (p.effective_to_date IS NULL OR s.trading_date < p.effective_to_date)
WHERE p.suppress_zero_flag = TRUE
  AND s.footfall_count = 0;

-- The interval-grain compatibility surface cannot retain a suppressed row with
-- NULL measures because its required timestamp and duration would disclose the
-- protected interval. Every published row must therefore clear the policy version
-- resolved from its deployment's durable assignment for the interval date; protected
-- rows are absent.
-- check: shared_interval_policy_enforced | severity: error
SELECT s.shared_zone_traffic_interval_id
FROM ${catalog}.${css_schema}.gold_zone_traffic_interval_shared s
JOIN ${catalog}.${css_schema}.sensor_report_interval f
  ON s.shared_zone_traffic_interval_id = CONCAT_WS(
    '|',
    f.store_id,
    f.store_zone_id,
    CAST(UNIX_TIMESTAMP(f.interval_start_ts) AS STRING),
    CAST(f.interval_minutes AS STRING)
  )
JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
  ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
JOIN ${catalog}.${css_schema}.sensing_deployment d
  ON f.sensing_deployment_sk = d.sensing_deployment_sk
JOIN ${catalog}.${css_schema}.sensing_disclosure_policy p
  ON d.external_disclosure_policy_id = p.sensing_disclosure_policy_id
 AND f.trading_date >= p.effective_from_date
 AND (p.effective_to_date IS NULL OR f.trading_date < p.effective_to_date)
WHERE COALESCE(f.measurement_validity, 'valid') = 'invalid'
   OR f.interval_minutes < p.minimum_interval_minutes
   OR t.footfall_count IS NULL
   OR (t.footfall_count = 0 AND p.suppress_zero_flag)
   OR t.footfall_count < p.k_threshold;

-- Every traffic-derived output is NULL when a cell is suppressed. This is
-- dependent-measure suppression within one cell, not statistical complementary
-- suppression of additional cells in an arithmetic hierarchy.
-- check: shared_dependent_measure_suppression | severity: error
SELECT 'zone' AS shared_view, store_id, trading_date
FROM ${catalog}.${css_schema}.gold_zone_traffic_shared
WHERE disclosure_suppressed_flag = TRUE
  AND (
    footfall_count IS NOT NULL
    OR entry_count IS NOT NULL
    OR exit_count IS NOT NULL
    OR passersby_count IS NOT NULL
    OR peak_occupancy IS NOT NULL
    OR avg_occupancy IS NOT NULL
    OR dwell_seconds_total IS NOT NULL
    OR dwell_count IS NOT NULL
    OR avg_dwell_seconds IS NOT NULL
    OR engaged_count IS NOT NULL
    OR passing_count IS NOT NULL
    OR engagement_rate IS NOT NULL
    OR footfall_per_sqm IS NOT NULL
    OR occupancy_per_sqm IS NOT NULL
    OR peak_capacity_utilisation IS NOT NULL
  )
UNION ALL
SELECT 'store' AS shared_view, store_id, trading_date
FROM ${catalog}.${css_schema}.gold_store_traffic_daily_shared
WHERE disclosure_suppressed_flag = TRUE
  AND (
    footfall_count IS NOT NULL
    OR entry_count IS NOT NULL
    OR exit_count IS NOT NULL
    OR peak_occupancy IS NOT NULL
    OR avg_occupancy IS NOT NULL
    OR dwell_seconds_total IS NOT NULL
    OR dwell_count IS NOT NULL
    OR avg_dwell_seconds IS NOT NULL
  );

-- Reconstructive operational fields must not exist on either shared schema.
-- check: shared_no_suppression_side_channels | severity: error
SELECT table_name, column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${css_schema}'
  AND table_name IN (
    'gold_store_traffic_daily_shared',
    'gold_zone_traffic_shared',
    'gold_zone_traffic_interval_shared'
  )
  AND lower(column_name) IN (
    'is_zero_observed',
    'source_observation_count',
    'expected_observation_count',
    'observations_received',
    'observations_expected',
    'visitor_count_raw',
    'visitor_count_adjusted',
    'staff_count',
    'child_count',
    'sensor_report_interval_sk',
    'sensor_report_interval_id',
    'sensor_device_sk',
    'sensor_device_id'
  );

-- The current shared surfaces are daily, so a policy requesting more than one day
-- cannot be satisfied without changing the published grain.
-- check: shared_minimum_interval_granularity | severity: error
SELECT *
FROM ${catalog}.${css_schema}.sensing_disclosure_policy
WHERE is_current = TRUE
  AND minimum_interval_minutes > 1440;

-- Schema-level assertion that the never-publish list is absent, including tagged_item,
-- rfid_count_session and rfid_read_event. This is the structural
-- half of ADR 0029 — Aggregate-only sensing schema with policy-driven shared disclosure -- a
-- Dutch DPA decision penalised the CAPABILITY to track absent
-- evidence of tracking, so the defence has to be that the column cannot exist.
-- Scoped to THIS package's own objects by name, not to the schema alone: the lean
-- per-PR gate deploys every domain into ONE schema (--single_schema pr_<N>), so
-- `table_schema = '${css_schema}'` there also resolves to canonical-core tables, whose
-- person-level columns are legitimate in their own domain (customer.profile.gender is
-- consented first-party profile data, not sensing output). A schema-only filter reported
-- those as ADR 0029 violations. Same table_name-scoping the other metadata guardrails use
-- (shared_no_suppression_side_channels, rfid_append_only_schema). The list is held to the
-- package's full object surface by test_person_level_guard_covers_every_package_object.
-- check: sri_no_person_level_columns | severity: error
SELECT column_name, table_name FROM ${catalog}.information_schema.columns
WHERE table_schema = '${css_schema}'
  AND table_name IN (
    -- tables
    'actuator_capability', 'automation_action', 'evaluation_rule', 'execution_log',
    'esl_label', 'esl_label_assignment', 'esl_price_observation',
    'foot_traffic_interval_detail', 'rfid_count_session', 'rfid_read_event',
    'sensing_deployment', 'sensing_disclosure_policy', 'sensor_device',
    'sensor_report_interval', 'shelf_position_assignment', 'shelf_state_observation',
    'store_zone', 'tagged_item',
    -- gold views
    'gold_count_session_summary', 'gold_css_automation_response',
    'gold_css_device_health', 'gold_css_environmental_compliance_daily',
    'gold_css_excursion_episodes', 'gold_css_rule_effectiveness_daily',
    'gold_inventory_accuracy_daily', 'gold_inventory_accuracy_daily_latest',
    'gold_item_current_state', 'gold_item_visibility_daily',
    'gold_observed_oos_episodes', 'gold_osa_daily_current',
    'gold_planogram_compliance_current', 'gold_price_accuracy_current',
    'gold_receiving_verification', 'gold_rfid_oos_candidates',
    'gold_share_of_shelf_current', 'gold_shelf_state_current',
    'gold_shelf_vs_system_variance_daily',
    'gold_store_traffic_daily_current', 'gold_store_traffic_daily_shared',
    'gold_traffic_sales_productivity_current', 'gold_unaccounted_exits',
    'gold_zone_count_coverage', 'gold_zone_item_presence_current',
    'gold_zone_traffic_current', 'gold_zone_traffic_interval_shared',
    'gold_zone_traffic_shared',
    -- metric views
    'mv_automation_response', 'mv_count_operations', 'mv_device_health',
    'mv_inventory_accuracy', 'mv_item_visibility', 'mv_store_foot_traffic',
    'mv_on_shelf_availability', 'mv_planogram_compliance', 'mv_price_accuracy',
    'mv_environmental_compliance', 'mv_excursion_episodes', 'mv_oos_episodes',
    'mv_phantom_stock_candidates',
    'mv_traffic_sales_productivity', 'mv_zone_foot_traffic'
  )
  AND (lower(column_name) LIKE '%mac_address%'
    OR lower(column_name) LIKE '%face_%'
    OR lower(column_name) LIKE '%person_id%'
    OR lower(column_name) LIKE '%track_id%'
    OR lower(column_name) LIKE '%journey_path%'
    OR lower(column_name) LIKE '%emotion%'
    OR lower(column_name) LIKE '%sentiment%'
    OR lower(column_name) LIKE '%gender%'
    OR lower(column_name) LIKE '%ethnicity%'
    OR lower(column_name) LIKE '%age_bracket%'
    OR lower(column_name) LIKE '%reidentification_key%');

-- THE ADR 0030 — In-store sensing signals are never an upstream dependency of pricing —
-- architectural invariant. Databricks exposes view SQL through INFORMATION_SCHEMA.VIEWS
-- (not the SQL-standard VIEW_TABLE_USAGE relation), so inspect each candidate view's
-- normalized definition and retain explicit object ownership. Lean PR CI resolves every
-- schema token to one pr_<N> schema; schema-only matching would mistake CSS's own
-- price-accuracy analytics for price-producing views. The object list is held to the
-- package's complete deployed surface by
-- test_pricing_lineage_guard_covers_every_package_object.
--
-- esl_price_observation is a permitted READER of product_price (captured at observation
-- time); the reverse direction is what this guards. Known limitation: the view-definition
-- match sees direct references only, not lineage laundered through an intermediate table --
-- reviewer vigilance still owns that case (eslp_sensing_flag_false is the row-level
-- backstop). Backticks are removed before matching because UC may normalize qualified
-- identifiers as `catalog`.`schema`.`object`; the trailing boundary prevents one CSS
-- object name from matching a longer, unrelated table name.
-- check: css_no_sensing_to_pricing_lineage | severity: error
WITH css_objects(object_name) AS (
  VALUES
    -- tables
    ('actuator_capability'), ('automation_action'), ('evaluation_rule'), ('execution_log'),
    ('esl_label'), ('esl_label_assignment'), ('esl_price_observation'),
    ('foot_traffic_interval_detail'), ('rfid_count_session'), ('rfid_read_event'),
    ('sensing_deployment'), ('sensing_disclosure_policy'), ('sensor_device'),
    ('sensor_report_interval'), ('shelf_position_assignment'), ('shelf_state_observation'),
    ('store_zone'), ('tagged_item'),
    -- gold views
    ('gold_count_session_summary'), ('gold_css_automation_response'),
    ('gold_css_device_health'), ('gold_css_environmental_compliance_daily'),
    ('gold_css_excursion_episodes'), ('gold_css_rule_effectiveness_daily'),
    ('gold_inventory_accuracy_daily'), ('gold_inventory_accuracy_daily_latest'),
    ('gold_item_current_state'), ('gold_item_visibility_daily'),
    ('gold_observed_oos_episodes'), ('gold_osa_daily_current'),
    ('gold_planogram_compliance_current'), ('gold_price_accuracy_current'),
    ('gold_receiving_verification'), ('gold_rfid_oos_candidates'),
    ('gold_share_of_shelf_current'), ('gold_shelf_state_current'),
    ('gold_shelf_vs_system_variance_daily'),
    ('gold_store_traffic_daily_current'), ('gold_store_traffic_daily_shared'),
    ('gold_traffic_sales_productivity_current'), ('gold_unaccounted_exits'),
    ('gold_zone_count_coverage'), ('gold_zone_item_presence_current'),
    ('gold_zone_traffic_current'), ('gold_zone_traffic_interval_shared'),
    ('gold_zone_traffic_shared'),
    -- metric views
    ('mv_automation_response'), ('mv_count_operations'), ('mv_device_health'),
    ('mv_inventory_accuracy'), ('mv_item_visibility'), ('mv_store_foot_traffic'),
    ('mv_on_shelf_availability'), ('mv_planogram_compliance'), ('mv_price_accuracy'),
    ('mv_environmental_compliance'), ('mv_excursion_episodes'), ('mv_oos_episodes'),
    ('mv_phantom_stock_candidates'),
    ('mv_traffic_sales_productivity'), ('mv_zone_foot_traffic')
)
SELECT DISTINCT v.table_schema, v.table_name
FROM ${catalog}.information_schema.views v
JOIN css_objects source_object
  ON regexp_like(
    replace(lower(v.view_definition), '`', ''),
    concat('[.]', source_object.object_name, '([^a-z0-9_]|$)')
  )
WHERE lower(v.table_schema) IN (
    lower('${cmn_schema}'), lower('${bmv_schema}'),
    lower('${sdi_schema}'), lower('${product_schema}')
  )
  AND lower(v.table_name) LIKE '%price%'
  AND NOT EXISTS (
    SELECT 1 FROM css_objects own_object
    WHERE own_object.object_name = lower(v.table_name)
  );

-- ========== store_zone ==========

-- check: sz_grain_unique | severity: error
SELECT store_zone_id, effective_from_date, COUNT(*) AS n FROM ${catalog}.${css_schema}.store_zone GROUP BY store_zone_id, effective_from_date HAVING COUNT(*) > 1;

-- check: sz_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.store_zone WHERE store_zone_sk IS NULL OR store_zone_id IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- SCD2 hygiene: exactly one current version per durable key.
-- check: sz_single_current | severity: error
SELECT store_zone_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.store_zone WHERE is_current = TRUE GROUP BY store_zone_id HAVING COUNT(*) > 1;

-- The recursive self-reference must resolve to a CURRENT parent version. Resolving on
-- the _sk alone would silently orphan children every time a parent re-versions.
-- check: sz_parent_resolves_current | severity: error
SELECT z.store_zone_id, z.parent_zone_id
FROM ${catalog}.${css_schema}.store_zone z
LEFT JOIN ${catalog}.${css_schema}.store_zone p ON z.parent_zone_id = p.store_zone_id AND p.is_current = TRUE
WHERE z.parent_zone_id IS NOT NULL AND p.store_zone_id IS NULL;

-- A zone cannot contain itself.
-- check: sz_no_self_parent | severity: error
SELECT * FROM ${catalog}.${css_schema}.store_zone WHERE parent_zone_id = store_zone_id;

-- Only the site row may have no parent.
-- check: sz_root_is_site | severity: error
SELECT * FROM ${catalog}.${css_schema}.store_zone WHERE parent_zone_id IS NULL AND zone_type <> 'site';

-- check: sz_store_fk_orphan | severity: error
SELECT z.* FROM ${catalog}.${css_schema}.store_zone z LEFT JOIN ${catalog}.${store_schema}.store s ON z.store_sk = s.store_sk WHERE z.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- ========== sensor_device ==========

-- check: sd_grain_unique | severity: error
SELECT sensor_device_id, effective_from_date, COUNT(*) AS n FROM ${catalog}.${css_schema}.sensor_device GROUP BY sensor_device_id, effective_from_date HAVING COUNT(*) > 1;

-- check: sd_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensor_device WHERE sensor_device_sk IS NULL OR sensor_device_id IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- check: sd_single_current | severity: error
SELECT sensor_device_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.sensor_device WHERE is_current = TRUE GROUP BY sensor_device_id HAVING COUNT(*) > 1;

-- Every sensing device needs a governance record, or its lawfulness cannot be assessed
-- (ADR 0031).
-- check: sd_deployment_present | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensor_device WHERE is_current = TRUE AND device_status = 'active' AND sensing_deployment_id IS NULL;

-- Calibration is regulated metrology for vaccine storage, not metadata: CDC/VFC
-- requires recalibration or replacement per the certificate.
-- check: sd_calibration_current | severity: warn
SELECT * FROM ${catalog}.${css_schema}.sensor_device WHERE is_current = TRUE AND device_status = 'active' AND calibration_valid_to IS NOT NULL AND calibration_valid_to < current_date();

-- A buffered probe is mandatory for vaccine storage; an air probe reacts to door
-- openings and generates false excursions.
-- check: sd_vaccine_probe_buffered | severity: warn
SELECT * FROM ${catalog}.${css_schema}.sensor_device WHERE device_type = 'temperature' AND accuracy_tolerance IS NOT NULL AND accuracy_tolerance <= 0.5 AND probe_type = 'air';

-- Interval-level message summaries preserve source continuity without putting one raw
-- per-message sequence value on an aggregate interval.
-- check: sd_session_continuity | severity: metric
SELECT sensor_device_id, trading_date, COUNT(*) AS rows_present,
       COUNT(DISTINCT source_session_id) AS sessions,
       SUM(sequence_gap_count) AS sequence_gap_count,
       SUM(duplicate_delivery_count) AS duplicate_delivery_count
FROM ${catalog}.${css_schema}.sensor_report_interval
WHERE source_session_id IS NOT NULL
GROUP BY sensor_device_id, trading_date;

-- A BACnet device with Out_Of_Service TRUE emits a SIMULATED Present_Value. Ingesting
-- it as real is the failure mode this catches.
-- check: sd_out_of_service_not_reporting | severity: warn
SELECT d.sensor_device_id, COUNT(*) AS reporting_rows
FROM ${catalog}.${css_schema}.sensor_device d
JOIN ${catalog}.${css_schema}.sensor_report_interval f ON f.sensor_device_id = d.sensor_device_id
WHERE d.is_current = TRUE AND d.bacnet_out_of_service = TRUE AND f.measurement_validity = 'valid'
GROUP BY d.sensor_device_id;

-- A non-directional device must not be the source of directional measures.
-- check: sd_directionality_consistent | severity: error
SELECT f.sensor_report_interval_id, d.sensor_device_id
FROM ${catalog}.${css_schema}.sensor_report_interval f
JOIN ${catalog}.${css_schema}.sensor_device d ON f.sensor_device_id = d.sensor_device_id AND d.is_current = TRUE
JOIN ${catalog}.${css_schema}.foot_traffic_interval_detail t
  ON f.sensor_report_interval_sk = t.sensor_report_interval_sk
WHERE d.is_directional = FALSE AND t.exit_count IS NOT NULL;

-- check: sd_zone_fk_orphan | severity: error
SELECT d.* FROM ${catalog}.${css_schema}.sensor_device d LEFT JOIN ${catalog}.${css_schema}.store_zone z ON d.store_zone_sk = z.store_zone_sk WHERE d.store_zone_sk IS NOT NULL AND z.store_zone_sk IS NULL;

-- check: sd_store_fk_orphan | severity: error
SELECT d.* FROM ${catalog}.${css_schema}.sensor_device d LEFT JOIN ${catalog}.${store_schema}.store s ON d.store_sk = s.store_sk WHERE d.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: sd_deployment_fk_orphan | severity: error
SELECT d.* FROM ${catalog}.${css_schema}.sensor_device d LEFT JOIN ${catalog}.${css_schema}.sensing_deployment sd ON d.sensing_deployment_sk = sd.sensing_deployment_sk WHERE d.sensing_deployment_sk IS NOT NULL AND sd.sensing_deployment_sk IS NULL;

-- check: sd_equipment_fk_orphan | severity: error
SELECT d.* FROM ${catalog}.${css_schema}.sensor_device d LEFT JOIN ${catalog}.${equipment_schema}.equipment e ON d.equipment_sk = e.equipment_sk WHERE d.equipment_sk IS NOT NULL AND e.equipment_sk IS NULL;

-- ========== tagged_item ==========

-- check: ti_grain_unique | severity: error
SELECT tagged_item_id, COUNT(*) AS n
FROM ${catalog}.${css_schema}.tagged_item
GROUP BY tagged_item_id
HAVING COUNT(*) > 1;

-- xxhash64 is a join convenience, never the authoritative identity. Any one hash
-- mapping to multiple EPC values is unsafe for every downstream FK join.
-- check: ti_sk_collision | severity: error
SELECT tagged_item_sk, COUNT(DISTINCT tagged_item_id) AS durable_id_count
FROM ${catalog}.${css_schema}.tagged_item
GROUP BY tagged_item_sk
HAVING COUNT(DISTINCT tagged_item_id) > 1;

-- check: ti_keys_not_null | severity: error
SELECT *
FROM ${catalog}.${css_schema}.tagged_item
WHERE tagged_item_sk IS NULL OR tagged_item_id IS NULL;

-- The URI prefix is identity-bearing, and SGTIN always has a serial and a product.
-- check: ti_identity_contract | severity: error
SELECT *
FROM ${catalog}.${css_schema}.tagged_item
WHERE (epc_scheme = 'sgtin' AND (
         tagged_item_id NOT LIKE 'urn:epc:id:sgtin:%'
         OR serial_number IS NULL
         OR gtin IS NULL
         OR product_sk IS NULL
         OR product_id IS NULL
       ))
   OR (epc_scheme = 'grai' AND tagged_item_id NOT LIKE 'urn:epc:id:grai:%');

-- check: ti_product_fk_orphan | severity: error
SELECT i.*
FROM ${catalog}.${css_schema}.tagged_item i
LEFT JOIN ${catalog}.${product_schema}.product p ON i.product_sk = p.product_sk
WHERE i.product_sk IS NOT NULL
  AND p.product_sk IS NULL;

-- check: ti_product_gtin_agreement | severity: error
SELECT i.tagged_item_id, i.gtin AS item_gtin, p.gtin AS product_gtin
FROM ${catalog}.${css_schema}.tagged_item i
JOIN ${catalog}.${product_schema}.product p ON i.product_sk = p.product_sk
WHERE i.gtin IS NOT NULL
  AND p.gtin IS NOT NULL
  AND i.gtin <> p.gtin;

-- ========== rfid_count_session ==========

-- check: rcs_grain_unique | severity: error
SELECT rfid_count_session_id, COUNT(*) AS n
FROM ${catalog}.${css_schema}.rfid_count_session
GROUP BY rfid_count_session_id
HAVING COUNT(*) > 1;

-- check: rcs_keys_not_null | severity: error
SELECT *
FROM ${catalog}.${css_schema}.rfid_count_session
WHERE rfid_count_session_sk IS NULL OR rfid_count_session_id IS NULL;

-- check: rcs_durable_id_wellformed | severity: error
SELECT *
FROM ${catalog}.${css_schema}.rfid_count_session
WHERE rfid_count_session_id <> concat(store_id, '|', source_session_id);

-- One query covers both declared session FKs and their durable-id twins.
-- check: rcs_fk_orphan | severity: error
SELECT s.*
FROM ${catalog}.${css_schema}.rfid_count_session s
LEFT JOIN ${catalog}.${store_schema}.store st ON s.store_sk = st.store_sk
LEFT JOIN ${catalog}.${css_schema}.sensor_device d
  ON s.primary_sensor_device_sk = d.sensor_device_sk
WHERE st.store_sk IS NULL
   OR st.store_id <> s.store_id
   OR (s.primary_sensor_device_sk IS NULL) <> (s.primary_sensor_device_id IS NULL)
   OR (s.primary_sensor_device_sk IS NOT NULL AND (
         d.sensor_device_sk IS NULL OR d.sensor_device_id <> s.primary_sensor_device_id
       ));

-- A closed session without events is operationally suspicious but remains loadable.
-- check: rcs_zero_events | severity: warn
SELECT s.rfid_count_session_id, s.store_id, s.ended_at_ts
FROM ${catalog}.${css_schema}.rfid_count_session s
LEFT JOIN ${catalog}.${css_schema}.rfid_read_event e
  ON s.rfid_count_session_sk = e.rfid_count_session_sk
GROUP BY s.rfid_count_session_id, s.store_id, s.ended_at_ts
HAVING COUNT(e.rfid_read_event_sk) = 0;

-- Session trading_date is a logical calendar reference, just like event trading_date.
-- check: rcs_calendar_orphan | severity: error
SELECT s.rfid_count_session_id, s.trading_date
FROM ${catalog}.${css_schema}.rfid_count_session s
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar c
  ON s.trading_date = c.date_key
WHERE c.date_key IS NULL;

-- ========== rfid_read_event ==========

-- check: rre_grain_unique | severity: error
SELECT rfid_read_event_id, COUNT(*) AS n
FROM ${catalog}.${css_schema}.rfid_read_event
GROUP BY rfid_read_event_id
HAVING COUNT(*) > 1;

-- check: rre_sk_collision | severity: error
SELECT rfid_read_event_sk, COUNT(DISTINCT rfid_read_event_id) AS durable_id_count
FROM ${catalog}.${css_schema}.rfid_read_event
GROUP BY rfid_read_event_sk
HAVING COUNT(DISTINCT rfid_read_event_id) > 1;

-- check: rre_durable_id_wellformed | severity: error
SELECT *
FROM ${catalog}.${css_schema}.rfid_read_event
WHERE rfid_read_event_id <>
      concat(tagged_item_id, '|', unix_timestamp(event_ts), '|', sensor_device_id);

-- Unregistered reads resolve neither registry nor product. Registered EPCs must
-- resolve the registry row. A registered SGTIN must also resolve product keys;
-- a registered GRAI asset may remain product-less. Product key pairs travel together.
-- check: rre_registration_pairing | severity: error
SELECT e.*
FROM ${catalog}.${css_schema}.rfid_read_event e
LEFT JOIN ${catalog}.${css_schema}.tagged_item i
  ON e.tagged_item_sk = i.tagged_item_sk
WHERE (e.is_unregistered_epc = TRUE AND (
         e.tagged_item_sk IS NOT NULL OR e.product_sk IS NOT NULL OR e.product_id IS NOT NULL
       ))
   OR (e.is_unregistered_epc = FALSE AND (
         e.tagged_item_sk IS NULL
         OR i.tagged_item_sk IS NULL
         OR (e.product_sk IS NULL) <> (e.product_id IS NULL)
         OR (i.epc_scheme = 'sgtin' AND (
              e.product_sk IS NULL
              OR e.product_sk <> i.product_sk
              OR e.product_id <> i.product_id
            ))
       ));

-- Consolidated declared-FK and durable-twin resolution check. Optional session and
-- shipment references pass only when both members of the pair are NULL.
-- check: rre_fk_orphan | severity: error
SELECT e.*
FROM ${catalog}.${css_schema}.rfid_read_event e
LEFT JOIN ${catalog}.${css_schema}.tagged_item i ON e.tagged_item_sk = i.tagged_item_sk
LEFT JOIN ${catalog}.${product_schema}.product p ON e.product_sk = p.product_sk
LEFT JOIN ${catalog}.${store_schema}.store st ON e.store_sk = st.store_sk
LEFT JOIN ${catalog}.${css_schema}.store_zone z ON e.store_zone_sk = z.store_zone_sk
LEFT JOIN ${catalog}.${css_schema}.sensor_device d ON e.sensor_device_sk = d.sensor_device_sk
LEFT JOIN ${catalog}.${css_schema}.sensing_deployment dep
  ON e.sensing_deployment_sk = dep.sensing_deployment_sk
LEFT JOIN ${catalog}.${css_schema}.rfid_count_session s
  ON e.rfid_count_session_sk = s.rfid_count_session_sk
LEFT JOIN ${catalog}.${logistics_schema}.shipment_line sl
  ON e.shipment_line_sk = sl.shipment_line_sk
WHERE (e.tagged_item_sk IS NOT NULL AND (
         i.tagged_item_sk IS NULL OR i.tagged_item_id <> e.tagged_item_id
       ))
   OR (e.product_sk IS NOT NULL AND (
         p.product_sk IS NULL OR p.product_id <> e.product_id
       ))
   OR st.store_sk IS NULL OR st.store_id <> e.store_id
   OR z.store_zone_sk IS NULL OR z.store_zone_id <> e.store_zone_id
   OR d.sensor_device_sk IS NULL OR d.sensor_device_id <> e.sensor_device_id
   OR dep.sensing_deployment_sk IS NULL
   OR dep.sensing_deployment_id <> e.sensing_deployment_id
   OR (e.rfid_count_session_sk IS NULL) <> (e.rfid_count_session_id IS NULL)
   OR (e.rfid_count_session_sk IS NOT NULL AND (
         s.rfid_count_session_sk IS NULL
         OR s.rfid_count_session_id <> e.rfid_count_session_id
         OR s.store_id <> e.store_id
       ))
   OR (e.shipment_line_sk IS NULL) <> (e.shipment_line_id IS NULL)
   OR (e.shipment_line_sk IS NOT NULL AND (
         sl.shipment_line_sk IS NULL
         OR sl.shipment_line_id <> e.shipment_line_id
         OR sl.product_id <> e.product_id
       ));

-- check: rre_calendar_orphan | severity: error
SELECT e.rfid_read_event_id, e.trading_date
FROM ${catalog}.${css_schema}.rfid_read_event e
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar c
  ON e.trading_date = c.date_key
WHERE c.date_key IS NULL;

-- The session header must already exist, must share the store, and the event must
-- fall inside the bounded sweep (five-minute edge tolerance for device clocks).
-- check: rre_session_integrity | severity: error
SELECT e.rfid_read_event_id, e.rfid_count_session_id
FROM ${catalog}.${css_schema}.rfid_read_event e
JOIN ${catalog}.${css_schema}.rfid_count_session s
  ON e.rfid_count_session_sk = s.rfid_count_session_sk
WHERE e.store_id <> s.store_id
   OR e.event_ts < s.started_at_ts - INTERVAL 5 MINUTES
   OR e.event_ts > s.ended_at_ts + INTERVAL 5 MINUTES;

-- check: rre_header_before_event | severity: warn
SELECT e.rfid_read_event_id, e.ingest_timestamp, s.ingest_timestamp AS session_ingest_timestamp
FROM ${catalog}.${css_schema}.rfid_read_event e
JOIN ${catalog}.${css_schema}.rfid_count_session s
  ON e.rfid_count_session_sk = s.rfid_count_session_sk
WHERE s.ingest_timestamp IS NOT NULL
  AND e.ingest_timestamp < s.ingest_timestamp;

-- Fixed readers use installed placement; mobile readers must report their event-level
-- operator or platform location instead.
-- check: rre_zone_source_honesty | severity: error
SELECT e.rfid_read_event_id, e.zone_source, d.is_mobile_platform
FROM ${catalog}.${css_schema}.rfid_read_event e
JOIN ${catalog}.${css_schema}.sensor_device d ON e.sensor_device_sk = d.sensor_device_sk
WHERE (d.is_mobile_platform = TRUE
       AND e.zone_source NOT IN ('operator_declared', 'platform_localization'))
   OR (COALESCE(d.is_mobile_platform, FALSE) = FALSE
       AND e.zone_source <> 'device_placement');

-- Mirrors the Foot Traffic directionality rule at item-event grain.
-- check: rre_directionality_consistent | severity: error
SELECT e.rfid_read_event_id, e.direction_code, e.direction_confidence
FROM ${catalog}.${css_schema}.rfid_read_event e
JOIN ${catalog}.${css_schema}.sensor_device d ON e.sensor_device_sk = d.sensor_device_sk
WHERE COALESCE(d.is_directional, FALSE) = FALSE
  AND (e.direction_code <> 'not_applicable' OR e.direction_confidence IS NOT NULL);

-- A retail_sold disposition outside checkout or a store portal is suspicious context,
-- not proof of a bad read. Keep it warn-level and preserve the event for investigation.
-- check: rre_retail_sold_context | severity: warn
SELECT e.rfid_read_event_id, e.store_zone_id, z.zone_code, z.zone_type
FROM ${catalog}.${css_schema}.rfid_read_event e
LEFT JOIN ${catalog}.${css_schema}.store_zone z
  ON e.store_zone_sk = z.store_zone_sk
WHERE e.disposition_uri = 'https://ref.gs1.org/cbv/Disp-retail_sold'
  AND NOT (
    lower(COALESCE(z.zone_code, '')) = 'checkout'
    OR z.zone_type IN ('entrance', 'perimeter')
  );

-- check: rre_event_not_future | severity: error
SELECT *
FROM ${catalog}.${css_schema}.rfid_read_event
WHERE event_ts > current_timestamp() + INTERVAL 5 MINUTES;

-- check: rre_before_commission | severity: warn
SELECT e.rfid_read_event_id, e.event_ts, i.commissioned_at_ts
FROM ${catalog}.${css_schema}.rfid_read_event e
JOIN ${catalog}.${css_schema}.tagged_item i ON e.tagged_item_sk = i.tagged_item_sk
WHERE e.event_ts < i.commissioned_at_ts;

-- A read after the first kill event is a process-health metric, not rejected history.
-- check: rre_post_kill_reads | severity: metric
WITH killed AS (
  SELECT tagged_item_id, MIN(event_ts) AS killed_at_ts
  FROM ${catalog}.${css_schema}.rfid_read_event
  WHERE biz_step_uri = 'https://ref.gs1.org/cbv/BizStep-killing'
  GROUP BY tagged_item_id
)
SELECT e.store_id, e.tagged_item_id, COUNT(*) AS post_kill_read_count
FROM ${catalog}.${css_schema}.rfid_read_event e
JOIN killed k ON e.tagged_item_id = k.tagged_item_id
WHERE e.event_ts > k.killed_at_ts
GROUP BY e.store_id, e.tagged_item_id;

-- check: rre_unregistered_epc_rate | severity: warn
SELECT store_id, trading_date,
       SUM(CASE WHEN is_unregistered_epc THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS unregistered_epc_rate
FROM ${catalog}.${css_schema}.rfid_read_event
GROUP BY store_id, trading_date
HAVING SUM(CASE WHEN is_unregistered_epc THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) > 0.05;

-- check: rre_delivery_quality | severity: metric
SELECT store_id, trading_date,
       SUM(COALESCE(duplicate_delivery_count, 0)) AS duplicate_deliveries,
       percentile_approx(timestampdiff(SECOND, event_ts, ingest_timestamp), 0.95) AS arrival_lag_seconds_p95
FROM ${catalog}.${css_schema}.rfid_read_event
GROUP BY store_id, trading_date;

-- Append-only posture is structural: RFID tables must not grow restatement fields.
-- check: rfid_append_only_schema | severity: error
SELECT table_name, column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${css_schema}'
  AND table_name IN ('tagged_item', 'rfid_count_session', 'rfid_read_event')
  AND lower(column_name) IN (
    'restatement_version', 'restated_at_ts', 'restated_by', 'update_reason'
  );

-- DQ-FACT-COVERAGE single-currency check: not applicable. RFID introduces no
-- monetary columns; accuracy, read rate, confidence and variance are unit metrics.

-- ========== sensing_deployment ==========

-- check: sdep_grain_unique | severity: error
SELECT sensing_deployment_id, effective_from_date, COUNT(*) AS n FROM ${catalog}.${css_schema}.sensing_deployment GROUP BY sensing_deployment_id, effective_from_date HAVING COUNT(*) > 1;

-- check: sdep_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensing_deployment WHERE sensing_deployment_sk IS NULL OR sensing_deployment_id IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- check: sdep_single_current | severity: error
SELECT sensing_deployment_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.sensing_deployment WHERE is_current = TRUE GROUP BY sensing_deployment_id HAVING COUNT(*) > 1;

-- Any deployment processing personal data needs a completed DPIA before it goes active.
-- check: sdep_dpia_before_active | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensing_deployment
WHERE is_current = TRUE AND deployment_status = 'active' AND lawful_basis_code <> 'not_personal_data' AND COALESCE(dpia_completed_flag, FALSE) = FALSE;

-- A EUR 2.52M Spanish DPA decision: the DPIA was penalised partly for not assessing risks to
-- the supermarket's own employees. Any deployment applying staff exclusion is by
-- definition processing employee data.
-- check: sdep_dpia_covers_employees | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensing_deployment
WHERE is_current = TRUE AND deployment_status = 'active' AND staff_exclusion_method NOT IN ('none') AND COALESCE(dpia_covers_employees_flag, FALSE) = FALSE;

-- Where the jurisdiction requires it, works-council consultation must precede
-- deployment (German BetrVG 87(1) is co-determination BEFORE introduction).
-- check: sdep_consultation_recorded | severity: warn
SELECT * FROM ${catalog}.${css_schema}.sensing_deployment
WHERE is_current = TRUE AND deployment_status = 'active' AND staff_exclusion_method NOT IN ('none')
  AND jurisdiction_code IN ('DE', 'FR', 'IT', 'PL', 'NL', 'ES', 'AT', 'BE')
  AND COALESCE(works_council_consulted_flag, FALSE) = FALSE;

-- AI Act Art. 50(3) applies from 2026-08-02 and was NOT postponed by the Digital
-- Omnibus. An active deployment that owes a notice and has not posted one is a live
-- exposure.
-- check: sdep_ai_act_notice_posted | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensing_deployment
WHERE is_current = TRUE AND deployment_status = 'active' AND ai_act_notice_status = 'required_not_posted' AND current_date() >= DATE'2026-08-02';

-- Signage is the baseline transparency measure for any people-sensing deployment
-- (EDPB Guidelines 3/2019).
-- check: sdep_signage_posted | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensing_deployment
WHERE is_current = TRUE AND deployment_status = 'active' AND lawful_basis_code <> 'not_personal_data' AND COALESCE(signage_posted_flag, FALSE) = FALSE;

-- Consent-required deployments need an operable opt-out. Per CNIL, "turn off your
-- Wi-Fi" does not qualify.
-- check: sdep_optout_operable | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensing_deployment
WHERE is_current = TRUE AND deployment_status = 'active' AND consent_required_flag = 'required' AND optout_mechanism_code IN ('none');

-- A retention ceiling must exist wherever personal data is processed, and the EDPB
-- expects heavier justification beyond 72 hours for video-derived data.
-- check: sdep_retention_ceiling_present | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensing_deployment
WHERE is_current = TRUE AND deployment_status = 'active' AND lawful_basis_code <> 'not_personal_data' AND retention_days_max IS NULL;

-- check: sdep_dpia_review_due | severity: warn
SELECT * FROM ${catalog}.${css_schema}.sensing_deployment WHERE is_current = TRUE AND deployment_status = 'active' AND dpia_review_due_date IS NOT NULL AND dpia_review_due_date < current_date();

-- check: sdep_store_fk_orphan | severity: error
SELECT p.* FROM ${catalog}.${css_schema}.sensing_deployment p LEFT JOIN ${catalog}.${store_schema}.store s ON p.store_sk = s.store_sk WHERE p.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- Active people-counting deployments must fail closed rather than silently disappear
-- from a shared projection because no external policy was assigned.
-- check: sdep_external_policy_present | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensing_deployment
WHERE is_current = TRUE
  AND deployment_status = 'active'
  AND sensing_purpose_code IN ('people_counting', 'occupancy_safety', 'queue_management', 'layout_optimisation')
  AND (
    external_disclosure_policy_sk IS NULL
    OR external_disclosure_policy_id IS NULL
  );

-- Both reference forms travel together: the surrogate declares the UC FK and lineage
-- version, while the durable id resolves the effective policy for a fact date.
-- check: sdep_disclosure_policy_key_pair | severity: error
SELECT d.sensing_deployment_id
FROM ${catalog}.${css_schema}.sensing_deployment d
JOIN ${catalog}.${css_schema}.sensing_disclosure_policy p
  ON d.external_disclosure_policy_sk = p.sensing_disclosure_policy_sk
WHERE d.external_disclosure_policy_id IS NULL
   OR d.external_disclosure_policy_id <> p.sensing_disclosure_policy_id;

-- ========== sensing_disclosure_policy ==========

-- check: sdp_grain_unique | severity: error
SELECT sensing_disclosure_policy_id, effective_from_date, COUNT(*) AS n FROM ${catalog}.${css_schema}.sensing_disclosure_policy GROUP BY sensing_disclosure_policy_id, effective_from_date HAVING COUNT(*) > 1;

-- check: sdp_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensing_disclosure_policy WHERE sensing_disclosure_policy_sk IS NULL OR sensing_disclosure_policy_id IS NULL OR audience_code IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- check: sdp_single_current | severity: error
SELECT sensing_disclosure_policy_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.sensing_disclosure_policy WHERE is_current = TRUE GROUP BY sensing_disclosure_policy_id HAVING COUNT(*) > 1;

-- check: sdp_valid_controls | severity: error
SELECT * FROM ${catalog}.${css_schema}.sensing_disclosure_policy
WHERE k_threshold < 0
   OR minimum_interval_minutes <= 0;

-- Effective-dated versions for the same policy cannot overlap.
-- check: sdp_effective_window_overlap | severity: error
SELECT a.sensing_disclosure_policy_id, a.sensing_disclosure_policy_sk AS left_sk,
       b.sensing_disclosure_policy_sk AS right_sk
FROM ${catalog}.${css_schema}.sensing_disclosure_policy a
JOIN ${catalog}.${css_schema}.sensing_disclosure_policy b
  ON a.sensing_disclosure_policy_id = b.sensing_disclosure_policy_id
 AND a.sensing_disclosure_policy_sk < b.sensing_disclosure_policy_sk
 AND a.effective_from_date < COALESCE(b.effective_to_date, DATE'9999-12-31')
 AND b.effective_from_date < COALESCE(a.effective_to_date, DATE'9999-12-31');

-- The durable policy assigned to a measured count must have exactly one version covering
-- its trading date. Otherwise the shared view fails closed by omitting the row, which is
-- safe but operationally invisible and therefore still a data-quality error.
-- check: sdep_disclosure_policy_effective | severity: error
SELECT f.sensor_report_interval_id, d.external_disclosure_policy_id
FROM ${catalog}.${css_schema}.sensor_report_interval f
JOIN ${catalog}.${css_schema}.sensing_deployment d
  ON f.sensing_deployment_sk = d.sensing_deployment_sk
LEFT JOIN ${catalog}.${css_schema}.sensing_disclosure_policy p
  ON d.external_disclosure_policy_id = p.sensing_disclosure_policy_id
 AND f.trading_date >= p.effective_from_date
 AND (p.effective_to_date IS NULL OR f.trading_date < p.effective_to_date)
WHERE f.report_type = 'gs1:Count'
  AND p.sensing_disclosure_policy_sk IS NULL;

-- check: sdep_disclosure_policy_orphan | severity: error
SELECT d.sensing_deployment_id
FROM ${catalog}.${css_schema}.sensing_deployment d
LEFT JOIN ${catalog}.${css_schema}.sensing_disclosure_policy p
  ON d.external_disclosure_policy_sk = p.sensing_disclosure_policy_sk
WHERE d.external_disclosure_policy_sk IS NOT NULL
  AND p.sensing_disclosure_policy_sk IS NULL;

-- ========== Sales-productivity currency gating ==========

-- gold_traffic_sales_productivity_current collapses currency with MIN(). That is only
-- safe if a store-day is single-currency. CMN carries the
-- equivalent check on its monetary facts; this is the same assertion at the same severity.
-- Scoped to the store-days this package actually PUBLISHES, rather than to all of sales:
-- a mixed-currency store-day that never reaches a CSS view is canonical-core's problem, and
-- a gold package should not fail its build over one.
-- check: productivity_single_currency | severity: error
SELECT g.store_id, g.trading_date, COUNT(DISTINCT s.currency_code) AS currencies
FROM ${catalog}.${css_schema}.gold_traffic_sales_productivity_current g
JOIN ${catalog}.${transaction_schema}.sales s
  ON g.store_id = s.store_id AND g.trading_date = s.date_key
GROUP BY g.store_id, g.trading_date
HAVING COUNT(DISTINCT s.currency_code) > 1;

-- ========== Gold-view grain (the ratios above are only as good as their denominators) ==========

-- Device health is one row per device VERSION x report_type x aggregation_level x date, and
-- every ratio in it divides by a count taken at that grain. The check exists because the
-- first version of the view grouped by device and date alone, which silently double-counted
-- every entrance counter: the fact holds both an `area` row and the store's `site` row for
-- the same device and interval, so intervals_reported, observations_expected/received and
-- the headline missing_observation_rate were all inflated on exactly the devices that matter
-- most. The failure is invisible in the output -- the numbers look plausible -- so only a
-- duplicate-key assertion catches it.
--
-- Asserted on sensor_device_sk, the actual version key. An earlier version used
-- firmware_version as a proxy for it, which is unsound in BOTH directions: a device
-- re-versioned for a calibration renewal legitimately produces two rows for one device-day
-- and failed the build, while a genuine duplicate that happened to share a firmware string
-- passed. The view now projects the surrogate for this reason and for §A.16 joins.
-- check: css_device_health_grain | severity: error
SELECT sensor_device_sk, trading_date, report_type, aggregation_level, COUNT(*) AS n
FROM ${catalog}.${css_schema}.gold_css_device_health
GROUP BY sensor_device_sk, trading_date, report_type, aggregation_level
HAVING COUNT(*) > 1;

-- Store traffic is one row per store-day at site level, and zone traffic one row per
-- durable zone-day at area level. Both feed metric views whose measures re-weight by
-- interval_minutes_total, so a duplicated row would double a weight rather than produce a
-- visibly wrong count.
-- check: css_store_traffic_grain | severity: error
SELECT store_id, trading_date, COUNT(*) AS n
FROM ${catalog}.${css_schema}.gold_store_traffic_daily_current
GROUP BY store_id, trading_date
HAVING COUNT(*) > 1;

-- The serving grain is the durable zone id. A mid-day SCD2 refit must not create two
-- rows for the same logical zone-day.
-- check: css_zone_traffic_grain | severity: error
SELECT store_zone_id, trading_date, COUNT(*) AS n
FROM ${catalog}.${css_schema}.gold_zone_traffic_current
GROUP BY store_zone_id, trading_date
HAVING COUNT(*) > 1;

-- ========== Automation loop: actuator_capability ==========
-- Prefixes: ac_ = actuator_capability, er_ = evaluation_rule, aa_ = automation_action,
-- el_ = execution_log.

-- check: ac_grain_unique | severity: error
SELECT actuator_capability_id, effective_from_date, COUNT(*) AS n FROM ${catalog}.${css_schema}.actuator_capability GROUP BY actuator_capability_id, effective_from_date HAVING COUNT(*) > 1;

-- check: ac_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.actuator_capability WHERE actuator_capability_sk IS NULL OR actuator_capability_id IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- check: ac_single_current | severity: error
SELECT actuator_capability_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.actuator_capability WHERE is_current = TRUE GROUP BY actuator_capability_id HAVING COUNT(*) > 1;

-- check: ac_device_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${css_schema}.actuator_capability a LEFT JOIN ${catalog}.${css_schema}.sensor_device d ON a.sensor_device_sk = d.sensor_device_sk WHERE a.sensor_device_sk IS NOT NULL AND d.sensor_device_sk IS NULL;

-- check: ac_equipment_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${css_schema}.actuator_capability a LEFT JOIN ${catalog}.${equipment_schema}.equipment e ON a.equipment_sk = e.equipment_sk WHERE a.equipment_sk IS NOT NULL AND e.equipment_sk IS NULL;

-- ========== Automation loop: evaluation_rule ==========

-- check: er_grain_unique | severity: error
SELECT evaluation_rule_id, effective_from_date, COUNT(*) AS n FROM ${catalog}.${css_schema}.evaluation_rule GROUP BY evaluation_rule_id, effective_from_date HAVING COUNT(*) > 1;

-- check: er_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.evaluation_rule WHERE evaluation_rule_sk IS NULL OR evaluation_rule_id IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- check: er_single_current | severity: error
SELECT evaluation_rule_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.evaluation_rule WHERE is_current = TRUE GROUP BY evaluation_rule_id HAVING COUNT(*) > 1;

-- check: er_device_fk_orphan | severity: error
SELECT r.* FROM ${catalog}.${css_schema}.evaluation_rule r LEFT JOIN ${catalog}.${css_schema}.sensor_device d ON r.sensor_device_sk = d.sensor_device_sk WHERE r.sensor_device_sk IS NOT NULL AND d.sensor_device_sk IS NULL;

-- ========== Automation loop: automation_action ==========

-- check: aa_grain_unique | severity: error
SELECT automation_action_id, effective_from_date, COUNT(*) AS n FROM ${catalog}.${css_schema}.automation_action GROUP BY automation_action_id, effective_from_date HAVING COUNT(*) > 1;

-- check: aa_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.automation_action WHERE automation_action_sk IS NULL OR automation_action_id IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- check: aa_single_current | severity: error
SELECT automation_action_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.automation_action WHERE is_current = TRUE GROUP BY automation_action_id HAVING COUNT(*) > 1;

-- check: aa_rule_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${css_schema}.automation_action a LEFT JOIN ${catalog}.${css_schema}.evaluation_rule r ON a.evaluation_rule_sk = r.evaluation_rule_sk WHERE a.evaluation_rule_sk IS NOT NULL AND r.evaluation_rule_sk IS NULL;

-- check: aa_actuator_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${css_schema}.automation_action a LEFT JOIN ${catalog}.${css_schema}.actuator_capability c ON a.actuator_capability_sk = c.actuator_capability_sk WHERE a.actuator_capability_sk IS NOT NULL AND c.actuator_capability_sk IS NULL;

-- An actuator-targeted action must carry the typed FK, and a non-actuator action must
-- not: the polymorphic target and the typed key cannot disagree about whether this
-- action drives a physical device. Mirrors chk_automation_action_actuator_target as a
-- DQ backstop, since UC does not enforce the CHECK.
-- check: aa_actuator_target_consistent | severity: error
SELECT * FROM ${catalog}.${css_schema}.automation_action
WHERE (target_entity_type = 'actuator' AND actuator_capability_sk IS NULL)
   OR (COALESCE(target_entity_type, 'none') <> 'actuator' AND actuator_capability_sk IS NOT NULL);

-- ========== Automation loop: execution_log (append-only fact) ==========

-- check: el_grain_unique | severity: error
SELECT execution_log_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.execution_log GROUP BY execution_log_id HAVING COUNT(*) > 1;

-- check: el_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.execution_log WHERE execution_log_sk IS NULL OR execution_log_id IS NULL OR triggered_at_timestamp IS NULL OR execution_status IS NULL;

-- check: el_action_fk_orphan | severity: error
SELECT l.* FROM ${catalog}.${css_schema}.execution_log l LEFT JOIN ${catalog}.${css_schema}.automation_action a ON l.automation_action_sk = a.automation_action_sk WHERE l.automation_action_sk IS NOT NULL AND a.automation_action_sk IS NULL;

-- check: el_actuator_fk_orphan | severity: error
SELECT l.* FROM ${catalog}.${css_schema}.execution_log l LEFT JOIN ${catalog}.${css_schema}.actuator_capability c ON l.actuator_capability_sk = c.actuator_capability_sk WHERE l.actuator_capability_sk IS NOT NULL AND c.actuator_capability_sk IS NULL;

-- check: el_rule_fk_orphan | severity: error
SELECT l.* FROM ${catalog}.${css_schema}.execution_log l LEFT JOIN ${catalog}.${css_schema}.evaluation_rule r ON l.evaluation_rule_sk = r.evaluation_rule_sk WHERE l.evaluation_rule_sk IS NOT NULL AND r.evaluation_rule_sk IS NULL;

-- check: el_interval_fk_orphan | severity: error
SELECT l.* FROM ${catalog}.${css_schema}.execution_log l LEFT JOIN ${catalog}.${css_schema}.sensor_report_interval f ON l.sensor_report_interval_sk = f.sensor_report_interval_sk WHERE l.sensor_report_interval_sk IS NOT NULL AND f.sensor_report_interval_sk IS NULL;

-- ========== Smart Shelf: shelf_position_assignment (SCD2 expected state) ==========
-- Prefixes: ssa_ = shelf_position_assignment, sso_ = shelf_state_observation,
-- esll_ = esl_label, esla_ = esl_label_assignment, eslp_ = esl_price_observation.

-- Version grain is the INSTANT (valid_from_ts), not the date: same-day re-slotting
-- during a reset produces two legal versions on one effective_from_date (design B2).
-- check: ssa_grain_unique | severity: error
SELECT shelf_position_assignment_id, valid_from_ts, COUNT(*) AS n FROM ${catalog}.${css_schema}.shelf_position_assignment GROUP BY shelf_position_assignment_id, valid_from_ts HAVING COUNT(*) > 1;

-- check: ssa_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.shelf_position_assignment WHERE shelf_position_assignment_sk IS NULL OR shelf_position_assignment_id IS NULL OR store_id IS NULL OR store_zone_id IS NULL OR product_id IS NULL OR valid_from_ts IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- Expected-state windows for one position-product never overlap: an observation must
-- resolve to at most one expected state at its instant.
-- check: ssa_nonoverlapping_validity | severity: error
SELECT a.shelf_position_assignment_id, a.shelf_position_assignment_sk, b.shelf_position_assignment_sk AS overlapping_sk
FROM ${catalog}.${css_schema}.shelf_position_assignment a
JOIN ${catalog}.${css_schema}.shelf_position_assignment b
  ON a.shelf_position_assignment_id = b.shelf_position_assignment_id
 AND a.shelf_position_assignment_sk < b.shelf_position_assignment_sk
 AND a.valid_from_ts < COALESCE(b.valid_to_ts, TIMESTAMP'9999-12-31 00:00:00')
 AND b.valid_from_ts < COALESCE(a.valid_to_ts, TIMESTAMP'9999-12-31 00:00:00');

-- The repo-standard SCD2 dates are DERIVED from the instant validity; drift between the
-- two would make date-grained tooling disagree with instant-grained resolution.
-- check: ssa_dates_derive_from_ts | severity: warn
SELECT * FROM ${catalog}.${css_schema}.shelf_position_assignment
WHERE effective_from_date <> CAST(valid_from_ts AS DATE)
   OR (valid_to_ts IS NULL AND effective_to_date IS NOT NULL)
   OR (valid_to_ts IS NOT NULL AND
       (effective_to_date IS NULL OR effective_to_date <> CAST(valid_to_ts AS DATE)));

-- SCD2 hygiene at the authoritative instant grain: current versions are open,
-- historical versions are closed, and every closed interval has positive duration.
-- check: ssa_scd2_consistent | severity: error
SELECT * FROM ${catalog}.${css_schema}.shelf_position_assignment
WHERE (is_current = TRUE AND (valid_to_ts IS NOT NULL OR effective_to_date IS NOT NULL))
   OR (is_current = FALSE AND (valid_to_ts IS NULL OR effective_to_date IS NULL))
   OR (valid_to_ts IS NOT NULL AND valid_to_ts <= valid_from_ts);

-- check: ssa_single_current | severity: error
SELECT shelf_position_assignment_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.shelf_position_assignment WHERE is_current = TRUE GROUP BY shelf_position_assignment_id HAVING COUNT(*) > 1;

-- check: ssa_store_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${css_schema}.shelf_position_assignment a LEFT JOIN ${catalog}.${store_schema}.store s ON a.store_sk = s.store_sk WHERE a.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: ssa_zone_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${css_schema}.shelf_position_assignment a LEFT JOIN ${catalog}.${css_schema}.store_zone z ON a.store_zone_sk = z.store_zone_sk WHERE a.store_zone_sk IS NOT NULL AND z.store_zone_sk IS NULL;

-- check: ssa_product_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${css_schema}.shelf_position_assignment a LEFT JOIN ${catalog}.${product_schema}.product p ON a.product_sk = p.product_sk WHERE a.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- A surrogate and its carried durable id are one reference. Independent orphan
-- checks prove the _sk exists; this proves that it identifies the SAME store, zone,
-- and product named by the denormalized ids.
-- check: ssa_reference_key_agreement | severity: error
SELECT a.shelf_position_assignment_id
FROM ${catalog}.${css_schema}.shelf_position_assignment a
JOIN ${catalog}.${store_schema}.store s ON a.store_sk = s.store_sk
JOIN ${catalog}.${css_schema}.store_zone z ON a.store_zone_sk = z.store_zone_sk
JOIN ${catalog}.${product_schema}.product p ON a.product_sk = p.product_sk
WHERE a.store_id <> s.store_id
   OR a.store_zone_id <> z.store_zone_id
   OR a.product_id <> p.product_id;

-- Expected state binds to SHELF-POSITION zones only. Guard against foot-traffic zone
-- contamination in the other direction lives on the observation (sso_zone_is_shelf_position);
-- this is the assignment-side pairing, resolved on the durable id so re-versioned zones
-- do not false-positive.
-- check: ssa_zone_is_shelf_position | severity: error
SELECT a.shelf_position_assignment_id, z.store_zone_id, z.zone_type
FROM ${catalog}.${css_schema}.shelf_position_assignment a
JOIN ${catalog}.${css_schema}.store_zone z
  ON a.store_zone_sk = z.store_zone_sk
WHERE z.zone_type <> 'shelf_position';

-- Smart Shelf's spatial contract is position -> bay -> aisle. Checking the current
-- durable parents prevents a structurally valid shelf_position label from being hung
-- directly under an area or another position.
-- check: ssa_zone_has_bay_aisle_ancestry | severity: error
SELECT a.shelf_position_assignment_id, z.store_zone_id,
       b.store_zone_id AS parent_zone_id, ai.store_zone_id AS grandparent_zone_id
FROM ${catalog}.${css_schema}.shelf_position_assignment a
JOIN ${catalog}.${css_schema}.store_zone z
  ON a.store_zone_sk = z.store_zone_sk
LEFT JOIN ${catalog}.${css_schema}.store_zone b
  ON z.parent_zone_id = b.store_zone_id AND b.is_current = TRUE
LEFT JOIN ${catalog}.${css_schema}.store_zone ai
  ON b.parent_zone_id = ai.store_zone_id AND ai.is_current = TRUE
WHERE a.is_current = TRUE
  AND (b.store_zone_id IS NULL OR b.zone_type <> 'bay'
       OR ai.store_zone_id IS NULL OR ai.zone_type <> 'aisle');

-- The compliance-audit-coverage KPI's model-side half: how many current shelf-position
-- zones carry a current assignment. Reports a value; never fails.
-- check: ssa_position_coverage | severity: metric
SELECT COUNT(DISTINCT a.store_zone_id) AS assigned_positions,
       COUNT(DISTINCT z.store_zone_id) AS shelf_position_zones
FROM ${catalog}.${css_schema}.store_zone z
LEFT JOIN ${catalog}.${css_schema}.shelf_position_assignment a
  ON a.store_zone_id = z.store_zone_id AND a.is_current = TRUE
WHERE z.zone_type = 'shelf_position' AND z.is_current = TRUE;

-- ========== Smart Shelf: shelf_state_observation (restatable positional fact) ==========

-- check: sso_grain_unique | severity: error
SELECT shelf_state_observation_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.shelf_state_observation GROUP BY shelf_state_observation_id HAVING COUNT(*) > 1;

-- xxhash64 is a join convenience, never the authoritative identity (ADR 0028).
-- check: sso_sk_collision | severity: error
SELECT shelf_state_observation_sk, COUNT(DISTINCT shelf_state_observation_id) AS durable_id_count
FROM ${catalog}.${css_schema}.shelf_state_observation
GROUP BY shelf_state_observation_sk
HAVING COUNT(DISTINCT shelf_state_observation_id) > 1;

-- check: sso_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.shelf_state_observation WHERE shelf_state_observation_sk IS NULL OR shelf_state_observation_id IS NULL OR source_capture_id IS NULL OR store_id IS NULL OR store_zone_id IS NULL OR product_id IS NULL OR sensor_device_id IS NULL OR sensing_deployment_id IS NULL OR observation_ts IS NULL OR utc_offset_minutes IS NULL OR trading_date IS NULL OR shelf_state IS NULL OR zone_source IS NULL OR attribution_confidence IS NULL;

-- check: sso_assignment_fk_orphan | severity: error
SELECT o.* FROM ${catalog}.${css_schema}.shelf_state_observation o LEFT JOIN ${catalog}.${css_schema}.shelf_position_assignment a ON o.shelf_position_assignment_sk = a.shelf_position_assignment_sk WHERE o.shelf_position_assignment_sk IS NOT NULL AND a.shelf_position_assignment_sk IS NULL;

-- The surrogate and durable assignment references are one captured relationship, not
-- independently nullable breadcrumbs.
-- check: sso_assignment_key_pair | severity: error
SELECT * FROM ${catalog}.${css_schema}.shelf_state_observation
WHERE (shelf_position_assignment_sk IS NULL AND shelf_position_assignment_id IS NOT NULL)
   OR (shelf_position_assignment_sk IS NOT NULL AND shelf_position_assignment_id IS NULL);

-- The captured assignment must cover the observation instant and agree with the
-- denormalized store/position. Product equality is required except on the detected-
-- product row of the two-row misplacement model, where inequality is intentional.
-- check: sso_assignment_context_consistent | severity: error
SELECT o.shelf_state_observation_id, o.observation_ts,
       o.store_id AS observed_store, a.store_id AS assignment_store,
       o.store_zone_id AS observed_zone, a.store_zone_id AS assignment_zone,
       o.product_id AS observed_product, a.product_id AS assignment_product
FROM ${catalog}.${css_schema}.shelf_state_observation o
JOIN ${catalog}.${css_schema}.shelf_position_assignment a
  ON o.shelf_position_assignment_sk = a.shelf_position_assignment_sk
WHERE o.store_id <> a.store_id
   OR o.store_zone_id <> a.store_zone_id
   OR (o.shelf_state <> 'misplaced' AND o.product_id <> a.product_id)
   OR o.observation_ts < a.valid_from_ts
   OR (a.valid_to_ts IS NOT NULL AND o.observation_ts >= a.valid_to_ts);

-- check: sso_store_fk_orphan | severity: error
SELECT o.* FROM ${catalog}.${css_schema}.shelf_state_observation o LEFT JOIN ${catalog}.${store_schema}.store s ON o.store_sk = s.store_sk WHERE o.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: sso_zone_fk_orphan | severity: error
SELECT o.* FROM ${catalog}.${css_schema}.shelf_state_observation o LEFT JOIN ${catalog}.${css_schema}.store_zone z ON o.store_zone_sk = z.store_zone_sk WHERE o.store_zone_sk IS NOT NULL AND z.store_zone_sk IS NULL;

-- check: sso_product_fk_orphan | severity: error
SELECT o.* FROM ${catalog}.${css_schema}.shelf_state_observation o LEFT JOIN ${catalog}.${product_schema}.product p ON o.product_sk = p.product_sk WHERE o.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: sso_device_fk_orphan | severity: error
SELECT o.* FROM ${catalog}.${css_schema}.shelf_state_observation o LEFT JOIN ${catalog}.${css_schema}.sensor_device d ON o.sensor_device_sk = d.sensor_device_sk WHERE o.sensor_device_sk IS NOT NULL AND d.sensor_device_sk IS NULL;

-- check: sso_deployment_fk_orphan | severity: error
SELECT o.* FROM ${catalog}.${css_schema}.shelf_state_observation o LEFT JOIN ${catalog}.${css_schema}.sensing_deployment dep ON o.sensing_deployment_sk = dep.sensing_deployment_sk WHERE o.sensing_deployment_sk IS NOT NULL AND dep.sensing_deployment_sk IS NULL;

-- Every populated surrogate/durable pair must resolve to one entity. product_sk may
-- be NULL only for the documented _ALL unresolved-product sentinel; assignment is
-- likewise optional when no expected state applied at capture time.
-- check: sso_reference_key_agreement | severity: error
SELECT o.shelf_state_observation_id
FROM ${catalog}.${css_schema}.shelf_state_observation o
JOIN ${catalog}.${store_schema}.store s ON o.store_sk = s.store_sk
JOIN ${catalog}.${css_schema}.store_zone z ON o.store_zone_sk = z.store_zone_sk
JOIN ${catalog}.${css_schema}.sensor_device d ON o.sensor_device_sk = d.sensor_device_sk
JOIN ${catalog}.${css_schema}.sensing_deployment dep
  ON o.sensing_deployment_sk = dep.sensing_deployment_sk
LEFT JOIN ${catalog}.${css_schema}.shelf_position_assignment a
  ON o.shelf_position_assignment_sk = a.shelf_position_assignment_sk
LEFT JOIN ${catalog}.${product_schema}.product p ON o.product_sk = p.product_sk
WHERE o.store_id <> s.store_id
   OR o.store_zone_id <> z.store_zone_id
   OR o.sensor_device_id <> d.sensor_device_id
   OR o.sensing_deployment_id <> dep.sensing_deployment_id
   OR (o.shelf_position_assignment_sk IS NOT NULL
       AND o.shelf_position_assignment_id <> a.shelf_position_assignment_id)
   OR (o.product_sk IS NOT NULL AND o.product_id <> p.product_id);

-- Observations attach to shelf-position zones only; no space-count semantics may leak
-- onto sub-area zones (ftid_space_count_requires_detail binds space-subject counts, and
-- this binds positional observations -- the two vocabularies never mix).
-- check: sso_zone_is_shelf_position | severity: error
SELECT o.shelf_state_observation_id, z.store_zone_id, z.zone_type
FROM ${catalog}.${css_schema}.shelf_state_observation o
JOIN ${catalog}.${css_schema}.store_zone z ON o.store_zone_sk = z.store_zone_sk
WHERE z.zone_type <> 'shelf_position';

-- State honesty, one rule per failure class so a violation names its class:
-- out_of_stock means the position was OBSERVED empty.
-- check: sso_state_oos_zero_facings | severity: error
SELECT * FROM ${catalog}.${css_schema}.shelf_state_observation
WHERE shelf_state = 'out_of_stock' AND (observed_facing_count IS NULL OR observed_facing_count <> 0);

-- low_stock means observed facings are strictly between zero and the threshold
-- recorded on the row, so the classification stays explainable after the assignment
-- re-versions.
-- check: sso_state_low_stock_band | severity: error
SELECT * FROM ${catalog}.${css_schema}.shelf_state_observation
WHERE shelf_state = 'low_stock'
  AND (observed_facing_count IS NULL OR min_facing_threshold IS NULL
       OR observed_facing_count <= 0 OR observed_facing_count >= min_facing_threshold);

-- in_stock with a recorded threshold means facings meet it.
-- check: sso_state_in_stock_meets_threshold | severity: error
SELECT * FROM ${catalog}.${css_schema}.shelf_state_observation
WHERE shelf_state = 'in_stock' AND min_facing_threshold IS NOT NULL
  AND (observed_facing_count IS NULL OR observed_facing_count < min_facing_threshold);

-- unknown means the platform could not evaluate: measures are NULL, never zero
-- (mirrors ftid_nondirectional_exits_null honesty).
-- check: sso_state_unknown_measures_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.shelf_state_observation
WHERE shelf_state = 'unknown'
  AND (observed_facing_count IS NOT NULL OR estimated_unit_count IS NOT NULL
       OR estimated_weight_grams IS NOT NULL OR pick_count_since_prior IS NOT NULL
       OR put_count_since_prior IS NOT NULL);

-- Two-row misplacement semantics (design §3.1): a misplaced row is the DETECTED product
-- sitting at a position assigned to a DIFFERENT product, so it must carry the violated
-- assignment and its product must differ from the assignment's. Resolved on the
-- version-pinned _sk the row captured (§A.16).
-- check: sso_state_misplaced_semantics | severity: error
SELECT o.shelf_state_observation_id, o.product_id AS detected_product, a.product_id AS expected_product
FROM ${catalog}.${css_schema}.shelf_state_observation o
LEFT JOIN ${catalog}.${css_schema}.shelf_position_assignment a
  ON o.shelf_position_assignment_sk = a.shelf_position_assignment_sk
WHERE o.shelf_state = 'misplaced'
  AND (o.shelf_position_assignment_sk IS NULL
       OR o.product_sk IS NULL OR o.product_id = '_ALL'
       OR a.product_id = o.product_id);

-- A misplaced row MUST have its expected-product out_of_stock sibling, with the
-- expected row's is_misplaced_detected flag set, in the same capture. The misplaced row carries
-- the violated assignment, so the PUBLISHING pipeline knows the expected product and
-- synthesizes its row even when the source platform reports detections only. Without
-- the sibling, the missing product is undiscoverable — the exact failure the two-row
-- model exists to prevent.
-- check: sso_misplaced_sibling_present | severity: error
SELECT m.shelf_state_observation_id, m.source_capture_id, a.product_id AS expected_product
FROM ${catalog}.${css_schema}.shelf_state_observation m
JOIN ${catalog}.${css_schema}.shelf_position_assignment a
  ON m.shelf_position_assignment_sk = a.shelf_position_assignment_sk
LEFT JOIN ${catalog}.${css_schema}.shelf_state_observation s
  ON s.source_capture_id = m.source_capture_id
 AND s.sensor_device_id = m.sensor_device_id
 AND s.store_id = m.store_id
 AND s.store_zone_id = m.store_zone_id
 AND s.product_id = a.product_id
 AND s.shelf_state = 'out_of_stock'
 AND COALESCE(s.is_misplaced_detected, FALSE) = TRUE
WHERE m.shelf_state = 'misplaced'
  AND s.shelf_state_observation_id IS NULL;

-- Weight and unit estimates only come from platforms that can produce them: the
-- observing device version must carry load_cell sensing technology. Resolved on the
-- version-specific _sk the fact captured (ADR 0025).
-- check: sso_unit_estimate_capability | severity: error
SELECT o.shelf_state_observation_id, d.sensor_device_id, d.sensing_technology
FROM ${catalog}.${css_schema}.shelf_state_observation o
JOIN ${catalog}.${css_schema}.sensor_device d ON o.sensor_device_sk = d.sensor_device_sk
WHERE (o.estimated_unit_count IS NOT NULL OR o.estimated_weight_grams IS NOT NULL)
  AND (d.sensing_technology IS NULL OR d.sensing_technology <> 'load_cell');

-- Since-prior pick/put counts require a load-cell or CV event-capable technology.
-- Other device families must publish NULL rather than a fabricated zero.
-- check: sso_event_count_capability | severity: error
SELECT o.shelf_state_observation_id, d.sensor_device_id, d.sensing_technology
FROM ${catalog}.${css_schema}.shelf_state_observation o
JOIN ${catalog}.${css_schema}.sensor_device d ON o.sensor_device_sk = d.sensor_device_sk
WHERE (o.pick_count_since_prior IS NOT NULL OR o.put_count_since_prior IS NOT NULL)
  AND (d.sensing_technology IS NULL OR
       d.sensing_technology NOT IN ('load_cell', 'video_cv', 'stereo_vision'));

-- An occluded capture is never a valid measurement.
-- check: sso_occluded_not_valid | severity: error
SELECT * FROM ${catalog}.${css_schema}.shelf_state_observation
WHERE COALESCE(is_occluded, FALSE) = TRUE AND measurement_validity = 'valid';

-- Epoch-space time agreement: UTC instant + store offset must land on trading_date
-- regardless of session timezone (same contract as sri_time_agreement).
-- check: sso_time_agreement | severity: error
SELECT * FROM ${catalog}.${css_schema}.shelf_state_observation
WHERE utc_offset_minutes IS NOT NULL
  AND trading_date <> date_from_unix_date(
        CAST(FLOOR((unix_timestamp(observation_ts) + utc_offset_minutes * 60) / 86400) AS INT));

-- A source timestamp beyond the wall clock is invalid evidence. Gold separately
-- applies its named evaluation clock so replay/data-max consumers keep point-in-time
-- semantics without weakening this ingestion-quality guard.
-- check: sso_observation_not_future | severity: error
SELECT * FROM ${catalog}.${css_schema}.shelf_state_observation
WHERE observation_ts > current_timestamp();

-- Observations without a captured expected-state reference cannot enter compliance
-- ratios; the rate is telemetry, not a defect (positions legitimately lack assignments
-- during resets).
-- check: sso_unassigned_observation_rate | severity: metric
SELECT COUNT(CASE WHEN shelf_position_assignment_id IS NULL THEN 1 END) AS unassigned_observations,
       COUNT(*) AS total_observations
FROM ${catalog}.${css_schema}.shelf_state_observation;

-- Cadence-gap telemetry: positions whose latest capture trails the freshest capture in
-- the estate by more than 24 hours. A staleness distribution signal, not a defect.
-- check: sso_position_cadence_gap | severity: metric
SELECT COUNT(*) AS stale_positions
FROM (
  SELECT store_zone_id, MAX(observation_ts) AS latest_ts
  FROM ${catalog}.${css_schema}.shelf_state_observation
  GROUP BY store_zone_id
) p
CROSS JOIN (SELECT MAX(observation_ts) AS estate_latest FROM ${catalog}.${css_schema}.shelf_state_observation) e
WHERE p.latest_ts < e.estate_latest - INTERVAL 24 HOURS;

-- ========== Smart Shelf: esl_label (SCD2 endpoint registry) ==========

-- check: esll_grain_unique | severity: error
SELECT esl_label_id, effective_from_date, COUNT(*) AS n FROM ${catalog}.${css_schema}.esl_label GROUP BY esl_label_id, effective_from_date HAVING COUNT(*) > 1;

-- check: esll_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_label WHERE esl_label_sk IS NULL OR esl_label_id IS NULL OR store_id IS NULL OR sensor_device_id IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- check: esll_single_current | severity: error
SELECT esl_label_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.esl_label WHERE is_current = TRUE GROUP BY esl_label_id HAVING COUNT(*) > 1;

-- check: esll_scd2_consistent | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_label
WHERE (is_current = TRUE AND effective_to_date IS NOT NULL)
   OR (is_current = FALSE AND effective_to_date IS NULL)
   OR (effective_to_date IS NOT NULL AND effective_to_date <= effective_from_date);

-- check: esll_store_fk_orphan | severity: error
SELECT l.* FROM ${catalog}.${css_schema}.esl_label l LEFT JOIN ${catalog}.${store_schema}.store s ON l.store_sk = s.store_sk WHERE l.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: esll_gateway_fk_orphan | severity: error
SELECT l.* FROM ${catalog}.${css_schema}.esl_label l LEFT JOIN ${catalog}.${css_schema}.sensor_device d ON l.sensor_device_sk = d.sensor_device_sk WHERE l.sensor_device_sk IS NOT NULL AND d.sensor_device_sk IS NULL;

-- check: esll_reference_key_agreement | severity: error
SELECT l.esl_label_id
FROM ${catalog}.${css_schema}.esl_label l
JOIN ${catalog}.${store_schema}.store s ON l.store_sk = s.store_sk
JOIN ${catalog}.${css_schema}.sensor_device d ON l.sensor_device_sk = d.sensor_device_sk
WHERE l.store_id <> s.store_id
   OR l.sensor_device_id <> d.sensor_device_id;

-- The homing device must BE a gateway: labels below anything else in the registry are
-- a modeling error, not a data accident (IoT-review M3 lesson -- assert the declared
-- invariant, not just the join).
-- check: esll_gateway_is_esl_gateway | severity: error
SELECT l.esl_label_id, d.sensor_device_id, d.device_type
FROM ${catalog}.${css_schema}.esl_label l
JOIN ${catalog}.${css_schema}.sensor_device d ON l.sensor_device_sk = d.sensor_device_sk
WHERE d.device_type <> 'esl_gateway';

-- ========== Smart Shelf: esl_label_assignment (binding lifecycle) ==========

-- Version grain is the INSTANT (valid_from_ts): labels are re-paired during the trading
-- day, so two same-day binding versions are legal and must not collide (design B2).
-- check: esla_grain_unique | severity: error
SELECT esl_label_assignment_id, valid_from_ts, COUNT(*) AS n FROM ${catalog}.${css_schema}.esl_label_assignment GROUP BY esl_label_assignment_id, valid_from_ts HAVING COUNT(*) > 1;

-- check: esla_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_label_assignment WHERE esl_label_assignment_sk IS NULL OR esl_label_assignment_id IS NULL OR esl_label_id IS NULL OR product_id IS NULL OR store_id IS NULL OR store_zone_id IS NULL OR valid_from_ts IS NULL OR effective_from_date IS NULL OR is_current IS NULL;

-- check: esla_dates_derive_from_ts | severity: warn
SELECT * FROM ${catalog}.${css_schema}.esl_label_assignment
WHERE effective_from_date <> CAST(valid_from_ts AS DATE)
   OR (valid_to_ts IS NULL AND effective_to_date IS NOT NULL)
   OR (valid_to_ts IS NOT NULL AND
       (effective_to_date IS NULL OR effective_to_date <> CAST(valid_to_ts AS DATE)));

-- check: esla_scd2_consistent | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_label_assignment
WHERE (is_current = TRUE AND (valid_to_ts IS NOT NULL OR effective_to_date IS NOT NULL))
   OR (is_current = FALSE AND (valid_to_ts IS NULL OR effective_to_date IS NULL))
   OR (valid_to_ts IS NOT NULL AND valid_to_ts <= valid_from_ts);

-- check: esla_single_current | severity: error
SELECT esl_label_assignment_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.esl_label_assignment WHERE is_current = TRUE GROUP BY esl_label_assignment_id HAVING COUNT(*) > 1;

-- THE binding-lifecycle invariant: one label displays one product at a time, so at
-- most one current binding per label ENDPOINT (across all durable binding triples).
-- check: esla_one_current_per_label | severity: error
SELECT esl_label_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.esl_label_assignment WHERE is_current = TRUE GROUP BY esl_label_id HAVING COUNT(*) > 1;

-- An active current binding must resolve through the current label endpoint and an
-- active current expected-state assignment at the same store/position/product.
-- check: esla_current_chain_resolves | severity: error
SELECT a.esl_label_assignment_id, a.esl_label_id, a.store_zone_id, a.product_id
FROM ${catalog}.${css_schema}.esl_label_assignment a
LEFT JOIN ${catalog}.${css_schema}.esl_label l
  ON a.esl_label_id = l.esl_label_id AND l.is_current = TRUE
LEFT JOIN ${catalog}.${css_schema}.shelf_position_assignment s
  ON a.store_id = s.store_id
 AND a.store_zone_id = s.store_zone_id
 AND a.product_id = s.product_id
 AND s.is_current = TRUE
 AND s.assignment_status = 'active'
WHERE a.is_current = TRUE
  AND a.binding_status = 'active'
  AND (l.esl_label_id IS NULL OR l.store_id <> a.store_id
       OR s.shelf_position_assignment_id IS NULL);

-- Binding validity windows for one label never overlap AT THE INSTANT GRAIN: a
-- displayed price must be attributable to exactly one product at any instant,
-- historically as well as now — date-grained windows would false-flag legal same-day
-- rebinds and miss true sub-day overlaps.
-- check: esla_nonoverlapping_validity | severity: error
SELECT a.esl_label_id, a.esl_label_assignment_sk, b.esl_label_assignment_sk AS overlapping_sk
FROM ${catalog}.${css_schema}.esl_label_assignment a
JOIN ${catalog}.${css_schema}.esl_label_assignment b
  ON a.esl_label_id = b.esl_label_id
 AND a.esl_label_assignment_sk < b.esl_label_assignment_sk
 AND a.valid_from_ts < COALESCE(b.valid_to_ts, TIMESTAMP'9999-12-31 00:00:00')
 AND b.valid_from_ts < COALESCE(a.valid_to_ts, TIMESTAMP'9999-12-31 00:00:00');

-- check: esla_label_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${css_schema}.esl_label_assignment a LEFT JOIN ${catalog}.${css_schema}.esl_label l ON a.esl_label_sk = l.esl_label_sk WHERE a.esl_label_sk IS NOT NULL AND l.esl_label_sk IS NULL;

-- check: esla_product_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${css_schema}.esl_label_assignment a LEFT JOIN ${catalog}.${product_schema}.product p ON a.product_sk = p.product_sk WHERE a.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: esla_store_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${css_schema}.esl_label_assignment a LEFT JOIN ${catalog}.${store_schema}.store s ON a.store_sk = s.store_sk WHERE a.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: esla_zone_fk_orphan | severity: error
SELECT a.* FROM ${catalog}.${css_schema}.esl_label_assignment a LEFT JOIN ${catalog}.${css_schema}.store_zone z ON a.store_zone_sk = z.store_zone_sk WHERE a.store_zone_sk IS NOT NULL AND z.store_zone_sk IS NULL;

-- check: esla_reference_key_agreement | severity: error
SELECT a.esl_label_assignment_id
FROM ${catalog}.${css_schema}.esl_label_assignment a
JOIN ${catalog}.${css_schema}.esl_label l ON a.esl_label_sk = l.esl_label_sk
JOIN ${catalog}.${product_schema}.product p ON a.product_sk = p.product_sk
JOIN ${catalog}.${store_schema}.store s ON a.store_sk = s.store_sk
JOIN ${catalog}.${css_schema}.store_zone z ON a.store_zone_sk = z.store_zone_sk
WHERE a.esl_label_id <> l.esl_label_id
   OR a.product_id <> p.product_id
   OR a.store_id <> s.store_id
   OR a.store_zone_id <> z.store_zone_id;

-- check: esla_zone_is_shelf_position | severity: error
SELECT a.esl_label_assignment_id, z.store_zone_id, z.zone_type
FROM ${catalog}.${css_schema}.esl_label_assignment a
JOIN ${catalog}.${css_schema}.store_zone z
  ON a.store_zone_sk = z.store_zone_sk
WHERE z.zone_type <> 'shelf_position';

-- M3: encoded_gtin is a shelf-edge SNAPSHOT; core product.gtin is the authority. A
-- disagreement is exactly the shelf-edge defect this layer surfaces — flagged, never
-- silently overwritten. Resolved on the version-pinned product _sk the binding captured.
-- check: esla_encoded_gtin_agrees | severity: warn
SELECT a.esl_label_assignment_id, a.encoded_gtin, p.gtin AS product_gtin
FROM ${catalog}.${css_schema}.esl_label_assignment a
JOIN ${catalog}.${product_schema}.product p
  ON a.product_sk = p.product_sk
WHERE a.encoded_gtin IS NOT NULL
  AND p.gtin IS NOT NULL
  AND a.encoded_gtin <> p.gtin;

-- ========== Smart Shelf: esl_price_observation (append-only audit fact) ==========
-- Append-only is STRUCTURAL here: the table carries no restatement columns at all;
-- corrections are new observations under a new grain key. Source-event identity is
-- checked independently of the derived durable id so a malformed publisher cannot
-- bypass re-delivery deduplication by changing esl_price_observation_id.

-- check: eslp_grain_unique | severity: error
SELECT esl_price_observation_id, COUNT(*) AS n FROM ${catalog}.${css_schema}.esl_price_observation GROUP BY esl_price_observation_id HAVING COUNT(*) > 1;

-- check: eslp_source_identity_unique | severity: error
SELECT esl_label_id, observation_source, source_observation_id, COUNT(*) AS n
FROM ${catalog}.${css_schema}.esl_price_observation
GROUP BY esl_label_id, observation_source, source_observation_id
HAVING COUNT(*) > 1;

-- check: eslp_sk_collision | severity: error
SELECT esl_price_observation_sk, COUNT(DISTINCT esl_price_observation_id) AS durable_id_count
FROM ${catalog}.${css_schema}.esl_price_observation
GROUP BY esl_price_observation_sk
HAVING COUNT(DISTINCT esl_price_observation_id) > 1;

-- check: eslp_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_price_observation WHERE esl_price_observation_sk IS NULL OR esl_price_observation_id IS NULL OR source_observation_id IS NULL OR esl_label_id IS NULL OR store_id IS NULL OR observed_at_ts IS NULL OR utc_offset_minutes IS NULL OR trading_date IS NULL OR observation_source IS NULL OR sensing_derived_input_flag IS NULL;

-- A bound observation carries the complete binding/product/position reference; an
-- unbound observation carries none of those denormalized keys.
-- check: eslp_binding_reference_consistent | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_price_observation
WHERE (esl_label_assignment_sk IS NULL AND esl_label_assignment_id IS NOT NULL)
   OR (esl_label_assignment_sk IS NOT NULL AND esl_label_assignment_id IS NULL)
   OR (esl_label_assignment_sk IS NULL AND
       (product_sk IS NOT NULL OR product_id IS NOT NULL
        OR store_zone_sk IS NOT NULL OR store_zone_id IS NOT NULL))
   OR (esl_label_assignment_sk IS NOT NULL AND
       (product_sk IS NULL OR product_id IS NULL
        OR store_zone_sk IS NULL OR store_zone_id IS NULL));

-- B1: a captured price of record without its source attribution is weaker audit
-- evidence than the design contract allows.
-- check: eslp_record_source_present | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_price_observation
WHERE price_of_record IS NOT NULL AND price_of_record_source IS NULL;

-- The Delta enum constraint protects deployed tables; this DQ guard also catches
-- pre-constraint and externally loaded data during validation.
-- check: eslp_record_source_domain | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_price_observation
WHERE price_of_record_source IS NOT NULL
  AND price_of_record_source NOT IN ('pricing_platform', 'product_price', 'pos_system', 'scale_plu', 'manual');

-- ADR 0030 §Decision.2 as a DQ backstop to the engine-enforced Delta CHECK, so the
-- invariant is also tested explicitly during DQ validation.
-- check: eslp_sensing_flag_false | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_price_observation WHERE sensing_derived_input_flag <> FALSE;

-- check: eslp_label_fk_orphan | severity: error
SELECT o.* FROM ${catalog}.${css_schema}.esl_price_observation o LEFT JOIN ${catalog}.${css_schema}.esl_label l ON o.esl_label_sk = l.esl_label_sk WHERE o.esl_label_sk IS NOT NULL AND l.esl_label_sk IS NULL;

-- check: eslp_assignment_fk_orphan | severity: error
SELECT o.* FROM ${catalog}.${css_schema}.esl_price_observation o LEFT JOIN ${catalog}.${css_schema}.esl_label_assignment a ON o.esl_label_assignment_sk = a.esl_label_assignment_sk WHERE o.esl_label_assignment_sk IS NOT NULL AND a.esl_label_assignment_sk IS NULL;

-- check: eslp_product_fk_orphan | severity: error
SELECT o.* FROM ${catalog}.${css_schema}.esl_price_observation o LEFT JOIN ${catalog}.${product_schema}.product p ON o.product_sk = p.product_sk WHERE o.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: eslp_store_fk_orphan | severity: error
SELECT o.* FROM ${catalog}.${css_schema}.esl_price_observation o LEFT JOIN ${catalog}.${store_schema}.store s ON o.store_sk = s.store_sk WHERE o.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: eslp_zone_fk_orphan | severity: error
SELECT o.* FROM ${catalog}.${css_schema}.esl_price_observation o LEFT JOIN ${catalog}.${css_schema}.store_zone z ON o.store_zone_sk = z.store_zone_sk WHERE o.store_zone_sk IS NOT NULL AND z.store_zone_sk IS NULL;

-- Bound references are optional as one complete group, but every populated _sk/_id
-- pair must name the same entity. Orphan checks remain separate so each failure class
-- has a precise result.
-- check: eslp_reference_key_agreement | severity: error
SELECT o.esl_price_observation_id
FROM ${catalog}.${css_schema}.esl_price_observation o
JOIN ${catalog}.${css_schema}.esl_label l ON o.esl_label_sk = l.esl_label_sk
JOIN ${catalog}.${store_schema}.store s ON o.store_sk = s.store_sk
LEFT JOIN ${catalog}.${css_schema}.esl_label_assignment a
  ON o.esl_label_assignment_sk = a.esl_label_assignment_sk
LEFT JOIN ${catalog}.${product_schema}.product p ON o.product_sk = p.product_sk
LEFT JOIN ${catalog}.${css_schema}.store_zone z ON o.store_zone_sk = z.store_zone_sk
WHERE o.esl_label_id <> l.esl_label_id
   OR o.store_id <> s.store_id
   OR (o.esl_label_assignment_sk IS NOT NULL
       AND o.esl_label_assignment_id <> a.esl_label_assignment_id)
   OR (o.product_sk IS NOT NULL AND o.product_id <> p.product_id)
   OR (o.store_zone_sk IS NOT NULL AND o.store_zone_id <> z.store_zone_id);

-- The match flag asserts a comparison that must actually hold, and may only be
-- asserted when both sides were captured.
-- check: eslp_match_consistency | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_price_observation
WHERE (is_price_match IS NOT NULL
       AND (displayed_price IS NULL
            OR price_of_record IS NULL
            OR displayed_currency_code IS NULL
            OR price_of_record_currency_code IS NULL
            OR displayed_currency_code <> price_of_record_currency_code))
   OR (is_price_match = TRUE  AND displayed_price <> price_of_record)
   OR (is_price_match = FALSE AND displayed_price = price_of_record);

-- H1: is_price_match / eslp_match_consistency compare displayed_price against
-- price_of_record as bare scalars. price_of_record_source may name a non-store-reporting
-- authority (pricing_platform, pos_system), so the record side needs its own currency and
-- it must equal the displayed (store reporting) currency, or the flagship over/undercharge
-- magnitudes silently compare across currencies. A captured price must carry its currency;
-- when both currencies are present they must agree.
-- check: eslp_price_of_record_currency | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_price_observation
WHERE (price_of_record IS NULL AND price_of_record_currency_code IS NOT NULL)
   OR (price_of_record IS NOT NULL AND price_of_record_currency_code IS NULL)
   OR (displayed_price IS NOT NULL AND price_of_record IS NOT NULL
       AND (displayed_currency_code IS NULL
            OR price_of_record_currency_code IS NULL
            OR displayed_currency_code <> price_of_record_currency_code));

-- Monetary fact: one reporting currency across BOTH the displayed price and the captured
-- price of record (MUST-tier single-currency contract). Folding price_of_record_currency_code
-- in closes the residual gap the row-wise tie leaves when displayed_price is NULL (occluded
-- read, no displayed currency to compare against): a price-of-record-only estate still
-- cannot report in a second currency the displayed-only count would never see.
-- check: eslp_single_currency | severity: error
SELECT 'esl_price_observation' AS table_name, COUNT(DISTINCT currency_code) AS currencies
FROM (
  SELECT displayed_currency_code AS currency_code
  FROM ${catalog}.${css_schema}.esl_price_observation WHERE displayed_price IS NOT NULL
  UNION ALL
  SELECT price_of_record_currency_code AS currency_code
  FROM ${catalog}.${css_schema}.esl_price_observation WHERE price_of_record IS NOT NULL
)
HAVING COUNT(DISTINCT currency_code) > 1
    OR COUNT(CASE WHEN currency_code IS NULL THEN 1 END) > 0;

-- Sync latency is defined as of-record-effective -> ack; only the ack path can carry it.
-- check: eslp_sync_latency_ack_only | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_price_observation
WHERE display_sync_latency_seconds IS NOT NULL AND observation_source <> 'platform_ack';

-- A populated latency must have its source timestamp and equal the elapsed epoch
-- seconds from the captured price becoming effective to the acknowledgement.
-- check: eslp_sync_latency_agreement | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_price_observation
WHERE display_sync_latency_seconds IS NOT NULL
  AND (price_of_record_effective_ts IS NULL
       OR display_sync_latency_seconds <>
          unix_timestamp(observed_at_ts) - unix_timestamp(price_of_record_effective_ts));

-- Captured disclosure text without the indicator is an inconsistent capture.
-- check: eslp_disclosure_text_implies_indicator | severity: warn
SELECT * FROM ${catalog}.${css_schema}.esl_price_observation
WHERE displayed_disclosure_text IS NOT NULL AND COALESCE(displayed_disclosure_indicator, FALSE) = FALSE;

-- Epoch-space time agreement (same contract as sri_time_agreement).
-- check: eslp_time_agreement | severity: error
SELECT * FROM ${catalog}.${css_schema}.esl_price_observation
WHERE utc_offset_minutes IS NOT NULL
  AND trading_date <> date_from_unix_date(
        CAST(FLOOR((unix_timestamp(observed_at_ts) + utc_offset_minutes * 60) / 86400) AS INT));

-- Denormalization honesty (IoT-review M3 lesson): the product and position carried on
-- the observation must agree with the binding version it references. Warn severity --
-- real feeds may lag a re-binding by one capture.
-- check: eslp_binding_denorm_consistent | severity: warn
SELECT o.esl_price_observation_id, o.product_id AS observed_product, a.product_id AS binding_product,
       o.store_zone_id AS observed_zone, a.store_zone_id AS binding_zone
FROM ${catalog}.${css_schema}.esl_price_observation o
JOIN ${catalog}.${css_schema}.esl_label_assignment a
  ON o.esl_label_assignment_sk = a.esl_label_assignment_sk
WHERE o.esl_label_id <> a.esl_label_id
   OR o.store_id <> a.store_id
   OR o.product_id <> a.product_id
   OR o.store_zone_id <> a.store_zone_id
   OR o.observed_at_ts < a.valid_from_ts
   OR (a.valid_to_ts IS NOT NULL AND o.observed_at_ts >= a.valid_to_ts);

-- Ack-vs-CV disagreement telemetry: same label, same trading date, different displayed
-- prices from the two independent paths. Disagreement is the SIGNAL this fact exists
-- to surface; the rate is telemetry, not a defect.
-- check: eslp_ack_cv_disagreement | severity: metric
SELECT COUNT(*) AS disagreeing_label_days
FROM (
  SELECT esl_label_id, trading_date
  FROM ${catalog}.${css_schema}.esl_price_observation
  WHERE observation_source IN ('platform_ack', 'shelf_cv') AND displayed_price IS NOT NULL
  GROUP BY esl_label_id, trading_date
  HAVING COUNT(DISTINCT observation_source) = 2 AND COUNT(DISTINCT displayed_price) > 1
);

-- ============================================================
-- IoT environmental monitoring: environmental_compliance_daily, excursion_episodes,
-- rule_effectiveness_daily
-- ============================================================

-- ========== gold_css_environmental_compliance_daily ==========

-- Grain: store x device x subject x equipment x report_type x current rule x trading_date.
-- check: ecd_grain_unique | severity: error
SELECT store_id, sensor_device_id, subject_type, subject_id, equipment_id, report_type, evaluation_rule_id, trading_date, COUNT(*) AS n
FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
GROUP BY store_id, sensor_device_id, subject_type, subject_id, equipment_id, report_type, evaluation_rule_id, trading_date
HAVING COUNT(*) > 1;

-- Durable keys are non-null (evaluation_rule_id is NULL by design when no rule applies).
-- check: ecd_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
WHERE store_id IS NULL OR sensor_device_id IS NULL OR report_type IS NULL OR trading_date IS NULL;

-- Count hierarchy: breaches <= evaluated <= valid <= all readings.
-- check: ecd_count_hierarchy | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
WHERE breach_interval_count < 0
   OR breach_interval_count > evaluated_interval_count
   OR evaluated_interval_count > valid_reading_count
   OR valid_reading_count > reading_count;

-- Compliance share is in [0, 1] and recomputes from its counts.
-- check: ecd_share_recomputes | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
WHERE share_intervals_in_range IS NOT NULL
  AND ABS(share_intervals_in_range
          - (evaluated_interval_count - breach_interval_count) / CAST(evaluated_interval_count AS DOUBLE)) > 1e-9;

-- Minutes outside range: zero without breaches, and never more than a full day
-- (sum of interval_minutes over at most one day of non-overlapping intervals). The cap is
-- 1500, not 1440: a 25-hour DST fall-back trading day legitimately holds 1500 minutes.
-- check: ecd_minutes_outside_bounded | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
WHERE minutes_outside_range < 0
   OR minutes_outside_range > 1500
   OR (breach_interval_count = 0 AND minutes_outside_range <> 0)
   OR (breach_interval_count > 0 AND minutes_outside_range = 0);

-- is_compliant agrees with the breach count, and is NULL exactly when nothing was evaluated.
-- check: ecd_compliance_flag_consistency | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
WHERE (is_compliant IS NULL) <> (evaluation_rule_id IS NULL OR evaluated_interval_count = 0)
   OR (is_compliant = TRUE AND breach_interval_count > 0)
   OR (is_compliant = FALSE AND breach_interval_count = 0);

-- Value statistics are ordered.
-- check: ecd_value_stats_ordered | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
WHERE min_value > max_value OR avg_value < min_value OR avg_value > max_value;

-- An enabled rule whose unit differs from the readings it watches cannot be evaluated.
-- Deliberately broader than the views: any series of the watched device and property in
-- another unit is reported, so warn rather than error.
-- check: ecd_rule_reading_uom_mismatch | severity: warn
SELECT r.evaluation_rule_id, r.uom_code AS rule_uom, s.uom AS reading_uom
FROM ${catalog}.${css_schema}.evaluation_rule r
JOIN (SELECT DISTINCT sensor_device_id, report_type, uom
      FROM ${catalog}.${css_schema}.sensor_report_interval) s
  ON s.sensor_device_id = r.sensor_device_id AND s.report_type = r.report_type
WHERE r.is_current = TRUE AND COALESCE(r.is_enabled, TRUE) = TRUE
  AND r.uom_code IS NOT NULL AND s.uom IS NOT NULL AND r.uom_code <> s.uom;

-- Share of monitored device-days with no applicable rule: coverage telemetry.
-- check: ecd_unruled_share | severity: metric
SELECT AVG(CASE WHEN evaluation_rule_id IS NULL THEN 1.0 ELSE 0.0 END) AS unruled_share
FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily;

-- check: ecd_row_count | severity: metric
SELECT COUNT(*) AS ecd_row_count FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily;

-- ========== gold_css_excursion_episodes ==========

-- Grain: one row per episode (device x subject x rule x start).
-- check: exe_grain_unique | severity: error
SELECT sensor_device_id, subject_type, subject_id, evaluation_rule_id, episode_start_ts, COUNT(*) AS n
FROM ${catalog}.${css_schema}.gold_css_excursion_episodes
GROUP BY sensor_device_id, subject_type, subject_id, evaluation_rule_id, episode_start_ts
HAVING COUNT(*) > 1;

-- check: exe_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_excursion_episodes
WHERE sensor_device_id IS NULL OR evaluation_rule_id IS NULL OR episode_start_ts IS NULL OR episode_end_ts IS NULL;

-- Episodes of one device x subject x rule never overlap (islands are maximal and disjoint).
-- check: exe_no_overlap | severity: error
SELECT a.sensor_device_id, a.subject_type, a.subject_id, a.evaluation_rule_id, a.episode_start_ts
FROM ${catalog}.${css_schema}.gold_css_excursion_episodes a
JOIN ${catalog}.${css_schema}.gold_css_excursion_episodes b
  ON a.sensor_device_id = b.sensor_device_id
  AND a.subject_type = b.subject_type
  AND a.subject_id = b.subject_id
  AND a.evaluation_rule_id = b.evaluation_rule_id
  AND a.episode_start_ts < b.episode_start_ts
  AND b.episode_start_ts < a.episode_end_ts;

-- Shape: end after start, at least one interval, duration matches the span.
-- check: exe_shape | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_excursion_episodes
WHERE episode_end_ts <= episode_start_ts
   OR interval_count < 1
   OR duration_minutes <> TIMESTAMPDIFF(MINUTE, episode_start_ts, episode_end_ts);

-- Firing counts: success + failure never exceed firings.
-- check: exe_firings_bounded | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_excursion_episodes
WHERE firings < 0 OR successful_firings < 0 OR failed_firings < 0
   OR successful_firings + failed_firings > firings;

-- has_successful_action and the first-success latency agree with the successful-firing count.
-- check: exe_resolution_consistency | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_excursion_episodes
WHERE has_successful_action <> (successful_firings > 0)
   OR (minutes_to_first_successful_action IS NULL) <> (successful_firings = 0);

-- A peak exceedance, when defined, is never negative: strict operators exceed the limit,
-- inclusive ones (greater_than_or_equal, less_than_or_equal) may sit exactly on it.
-- check: exe_peak_exceedance_non_negative | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_excursion_episodes
WHERE peak_exceedance IS NOT NULL
  AND (peak_exceedance < 0
       OR (peak_exceedance = 0 AND condition_operator NOT IN ('greater_than_or_equal', 'less_than_or_equal')));

-- The two views share the breach predicate and series choice: every breaching interval
-- the daily view counts belongs to exactly one episode, per rule over the whole history.
-- check: iot_breach_episode_reconciliation | severity: error
SELECT COALESCE(d.evaluation_rule_id, e.evaluation_rule_id) AS evaluation_rule_id, d.breaches, e.episode_intervals
FROM (SELECT evaluation_rule_id, SUM(breach_interval_count) AS breaches
      FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
      WHERE evaluation_rule_id IS NOT NULL GROUP BY evaluation_rule_id) d
FULL OUTER JOIN (SELECT evaluation_rule_id, SUM(interval_count) AS episode_intervals
      FROM ${catalog}.${css_schema}.gold_css_excursion_episodes GROUP BY evaluation_rule_id) e
  ON d.evaluation_rule_id = e.evaluation_rule_id
WHERE COALESCE(d.breaches, 0) <> COALESCE(e.episode_intervals, 0);

-- Enabled current rules over a cross-device aggregate (NULL device): neither IoT view
-- evaluates them (both join readings on sensor_device_id), so they never breach or open
-- an episode. Coverage telemetry; non-zero means some rules are silently unevaluated.
-- check: iot_cross_device_rules_unevaluated | severity: metric
SELECT COUNT(*) AS cross_device_rules_unevaluated
FROM ${catalog}.${css_schema}.evaluation_rule
WHERE is_current = TRUE AND COALESCE(is_enabled, TRUE) = TRUE AND sensor_device_id IS NULL;

-- Device x property series with more than one measured subject under at least one current
-- rule. Rules have no subject scope, so each such rule applies to every subject on the
-- device. Informational, not an error: it is non-zero on any multi-subject logger, including
-- one whose subjects correctly share limits, so read a non-zero value as "verify these rules
-- apply to every subject".
-- check: iot_multi_subject_ruled_series | severity: metric
SELECT COUNT(*) AS multi_subject_ruled_series
FROM (SELECT sensor_device_id, report_type
      FROM ${catalog}.${css_schema}.gold_css_environmental_compliance_daily
      WHERE evaluation_rule_id IS NOT NULL
      GROUP BY sensor_device_id, report_type
      HAVING COUNT(DISTINCT subject_type || '|' || subject_id) > 1) m;

-- Valid intervals of a rule-watched property that fall outside the canonical series both IoT
-- views read (same series key as the views), for any reason: a subject's own cadence or
-- level change over time (see iot_series_history_loss_intervals), another subject on the
-- device at a coarser cadence or a lower-priority aggregation level, or a subject id that is
-- absent from the chosen series. Coverage telemetry: non-zero on any device whose subjects
-- report at mixed cadences or levels.
-- check: iot_series_excluded_valid_intervals | severity: metric
SELECT COUNT(*) AS series_excluded_valid_intervals
FROM (SELECT measurement_validity, value, report_type,
             CASE aggregation_level WHEN 'device' THEN 0 WHEN 'subject' THEN 1 ELSE 2 END * 100000 + interval_minutes AS series_key,
             MIN(CASE aggregation_level WHEN 'device' THEN 0 WHEN 'subject' THEN 1 ELSE 2 END * 100000 + interval_minutes) OVER (PARTITION BY sensor_device_id, report_type) AS chosen_series_key
      FROM ${catalog}.${css_schema}.sensor_report_interval) s
WHERE s.series_key <> s.chosen_series_key
  AND s.measurement_validity = 'valid' AND s.value IS NOT NULL
  AND s.report_type IN (SELECT DISTINCT report_type FROM ${catalog}.${css_schema}.evaluation_rule
                        WHERE is_current = TRUE AND COALESCE(is_enabled, TRUE) = TRUE);

-- The actionable part of iot_series_excluded_valid_intervals: excluded valid intervals of a
-- subject that ALSO has rows on the chosen series. That subject changed cadence or level over
-- time, so its own earlier (or later) readings are lost to both IoT views. Non-zero means
-- history loss to investigate, not a coarser sibling channel. Caveat: a subject with NO rows on
-- the chosen series is counted only in iot_series_excluded_valid_intervals, as an off-series
-- subject, whatever its own history (for example a single-subject device whose only subject moved
-- to device-level reporting under a different subject id).
-- check: iot_series_history_loss_intervals | severity: metric
SELECT COUNT(*) AS series_history_loss_intervals
FROM (SELECT sensor_device_id, report_type, subject_type, subject_id, measurement_validity, value,
             CASE aggregation_level WHEN 'device' THEN 0 WHEN 'subject' THEN 1 ELSE 2 END * 100000 + interval_minutes AS series_key,
             MIN(CASE aggregation_level WHEN 'device' THEN 0 WHEN 'subject' THEN 1 ELSE 2 END * 100000 + interval_minutes) OVER (PARTITION BY sensor_device_id, report_type) AS chosen_series_key
      FROM ${catalog}.${css_schema}.sensor_report_interval) s
JOIN (SELECT DISTINCT sensor_device_id, report_type, subject_type, subject_id
      FROM (SELECT sensor_device_id, report_type, subject_type, subject_id, measurement_validity, value,
             CASE aggregation_level WHEN 'device' THEN 0 WHEN 'subject' THEN 1 ELSE 2 END * 100000 + interval_minutes AS series_key,
             MIN(CASE aggregation_level WHEN 'device' THEN 0 WHEN 'subject' THEN 1 ELSE 2 END * 100000 + interval_minutes) OVER (PARTITION BY sensor_device_id, report_type) AS chosen_series_key
      FROM ${catalog}.${css_schema}.sensor_report_interval) c
      WHERE c.series_key = c.chosen_series_key) cs
  ON cs.sensor_device_id = s.sensor_device_id AND cs.report_type = s.report_type
  AND cs.subject_type = s.subject_type AND cs.subject_id = s.subject_id
WHERE s.series_key <> s.chosen_series_key
  AND s.measurement_validity = 'valid' AND s.value IS NOT NULL
  AND s.report_type IN (SELECT DISTINCT report_type FROM ${catalog}.${css_schema}.evaluation_rule
                        WHERE is_current = TRUE AND COALESCE(is_enabled, TRUE) = TRUE);

-- Share of episodes the automation never reacted to: control-loop coverage telemetry.
-- check: exe_unanswered_share | severity: metric
SELECT AVG(CASE WHEN firings = 0 THEN 1.0 ELSE 0.0 END) AS unanswered_episode_share
FROM ${catalog}.${css_schema}.gold_css_excursion_episodes;

-- check: exe_row_count | severity: metric
SELECT COUNT(*) AS exe_row_count FROM ${catalog}.${css_schema}.gold_css_excursion_episodes;

-- ========== gold_css_rule_effectiveness_daily ==========

-- Grain: one row per store x rule x trading_date.
-- check: red_grain_unique | severity: error
SELECT store_id, evaluation_rule_id, trading_date, COUNT(*) AS n
FROM ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily
GROUP BY store_id, evaluation_rule_id, trading_date
HAVING COUNT(*) > 1;

-- All key columns must be non-null.
-- check: red_keys_not_null | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily
WHERE store_id IS NULL OR evaluation_rule_id IS NULL OR trading_date IS NULL;

-- Firing counts must be non-negative.
-- check: red_firing_counts_non_negative | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily
WHERE firings < 0 OR successful_firings < 0 OR failed_firings < 0 OR other_status_firings < 0
   OR distinct_actions < 0 OR physical_command_firings < 0 OR notification_firings < 0;

-- Status counts must sum to firings.
-- check: red_status_counts_sum | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily
WHERE (successful_firings + failed_firings + other_status_firings) <> firings;

-- Latencies must be non-negative and avg <= max.
-- check: red_latency_reasonable | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily
WHERE (avg_latency_ms IS NOT NULL AND avg_latency_ms < 0)
   OR (max_latency_ms IS NOT NULL AND max_latency_ms < 0)
   OR (avg_latency_ms IS NOT NULL AND max_latency_ms IS NOT NULL AND avg_latency_ms > max_latency_ms);

-- Latency rollup inputs agree with the per-row mean: the measured count never exceeds the
-- firings, and sum / count reproduces avg_latency_ms.
-- check: red_latency_rollup_inputs_consistent | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily
WHERE latency_measured_firings < 0
   OR latency_measured_firings > firings
   OR (latency_measured_firings = 0) <> (avg_latency_ms IS NULL)
   OR (latency_measured_firings > 0
       AND ABS(latency_ms_sum / CAST(latency_measured_firings AS DOUBLE) - avg_latency_ms) > 1e-6);

-- Success rate inputs must be consistent.
-- check: red_success_rate_inputs_bounded | severity: error
SELECT * FROM ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily
WHERE success_rate_numerator < 0 OR success_rate_denominator < 0 OR success_rate_numerator > success_rate_denominator;

-- Metric check: count rows in rule_effectiveness_daily daily
-- check: red_row_count | severity: metric
SELECT COUNT(*) AS red_row_count FROM ${catalog}.${css_schema}.gold_css_rule_effectiveness_daily;
