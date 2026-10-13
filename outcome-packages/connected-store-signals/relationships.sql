-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals · relationships
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- Foreign keys and CHECK constraints. Run AFTER the table DDL.
--
-- All CHECKs are declared here via ALTER TABLE ADD CONSTRAINT, never inline:
-- Databricks does not support inline CHECK in CREATE TABLE (NO-INLINE-CHECK), and
-- ADD CONSTRAINT is the idempotent form.
--
-- FKs are single-column on the parent _sk. They are informational in Unity Catalog
-- (RELY NOT ENFORCED semantics) -- the orphan checks in checks.sql are what actually
-- catch violations, which is why every FK here has a matching *_fk_orphan check.
-- ============================================================

-- ---------------- store_zone ----------------
ALTER TABLE ${catalog}.${css_schema}.store_zone ADD CONSTRAINT fk_store_zone_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);

-- Self-reference for the recursive hierarchy. Note the DURABLE id (parent_zone_id) is
-- the join key consumers should use -- this FK is on the _sk and therefore points at a
-- specific SCD2 VERSION of the parent, which is why sz_parent_resolves_current exists.
ALTER TABLE ${catalog}.${css_schema}.store_zone ADD CONSTRAINT fk_store_zone_parent FOREIGN KEY (parent_zone_sk) REFERENCES ${catalog}.${css_schema}.store_zone (store_zone_sk);

-- Nullable enum columns carry the explicit `IS NULL OR` guard. Delta treats a NULL
-- CHECK result as a pass, so the guard is not strictly required — it is the house
-- convention (see commerce-media-networks/relationships.sql:104) and it makes the
-- nullability visible at the constraint rather than only in the DDL.
ALTER TABLE ${catalog}.${css_schema}.store_zone ADD CONSTRAINT chk_store_zone_type CHECK (zone_type IS NULL OR zone_type IN ('site', 'entrance', 'area', 'department', 'aisle', 'bay', 'shelf_position', 'queue', 'fitting_room', 'perimeter', 'back_of_house'));
ALTER TABLE ${catalog}.${css_schema}.store_zone ADD CONSTRAINT chk_store_zone_depth CHECK (hierarchy_depth IS NULL OR hierarchy_depth >= 0);
ALTER TABLE ${catalog}.${css_schema}.store_zone ADD CONSTRAINT chk_store_zone_area CHECK (area_sqm IS NULL OR area_sqm > 0);
ALTER TABLE ${catalog}.${css_schema}.store_zone ADD CONSTRAINT chk_store_zone_capacity CHECK (capacity_persons IS NULL OR capacity_persons > 0);

-- ---------------- sensing_deployment ----------------
ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT fk_sensing_deployment_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT fk_sensing_deployment_disclosure_policy FOREIGN KEY (external_disclosure_policy_sk) REFERENCES ${catalog}.${css_schema}.sensing_disclosure_policy (sensing_disclosure_policy_sk);

ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT chk_sensing_deployment_method CHECK (sensing_method_code IS NULL OR sensing_method_code IN ('ir_beam', 'thermal', 'video_cv', 'stereo_vision', 'time_of_flight', 'wifi_probe', 'ble_probe', 'rfid', 'weight', 'door_contact', 'environmental'));
ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT chk_sensing_deployment_purpose CHECK (sensing_purpose_code IS NULL OR sensing_purpose_code IN ('people_counting', 'occupancy_safety', 'queue_management', 'layout_optimisation', 'cold_chain_compliance', 'shelf_availability', 'asset_tracking', 'energy_management'));
ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT chk_sensing_deployment_basis CHECK (lawful_basis_code IS NULL OR lawful_basis_code IN ('legitimate_interest', 'consent', 'legal_obligation', 'vital_interest', 'not_personal_data'));
ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT chk_sensing_deployment_ai_notice CHECK (ai_act_notice_status IS NULL OR ai_act_notice_status IN ('not_applicable', 'required_posted', 'required_not_posted'));
ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT chk_sensing_deployment_consent CHECK (consent_required_flag IS NULL OR consent_required_flag IN ('required', 'not_required', 'under_review'));
ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT chk_sensing_deployment_optout CHECK (optout_mechanism_code IS NULL OR optout_mechanism_code IN ('none', 'signage_contact', 'in_store_kiosk', 'web_portal', 'not_applicable'));
ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT chk_sensing_deployment_excl_method CHECK (staff_exclusion_method IS NULL OR staff_exclusion_method IN ('none', 'exclusion_line', 'zone_button', 'patterned_tag', 'fabric_tag', 'uniform_ml', 'reidentification', 'fixed_count_subtraction', 'scaling_factor'));
ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT chk_sensing_deployment_excl_stage CHECK (staff_exclusion_stage IS NULL OR staff_exclusion_stage IN ('none', 'at_sensor', 'at_aggregation'));
ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT chk_sensing_deployment_status CHECK (deployment_status IS NULL OR deployment_status IN ('planned', 'active', 'suspended', 'decommissioned'));
ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT chk_sensing_deployment_retention CHECK (retention_days_max IS NULL OR retention_days_max > 0);

-- Wi-Fi and BLE probe deployments are consent-gated by construction, not by policy.
-- Hashed MACs remain personal data (Art. 29 WP Opinion 05/2014; EDPB Guidelines
-- 01/2025), and the Dutch DPA fined a municipality EUR 600,000 for the CAPABILITY to track
-- absent evidence of tracking. Making this a constraint means a non-consented Wi-Fi
-- deployment cannot be recorded as compliant.
ALTER TABLE ${catalog}.${css_schema}.sensing_deployment ADD CONSTRAINT chk_sensing_deployment_wifi_consent CHECK (sensing_method_code NOT IN ('wifi_probe', 'ble_probe') OR consent_required_flag = 'required');

-- ---------------- sensing_disclosure_policy ----------------
ALTER TABLE ${catalog}.${css_schema}.sensing_disclosure_policy ADD CONSTRAINT chk_sdp_threshold CHECK (k_threshold >= 0);
ALTER TABLE ${catalog}.${css_schema}.sensing_disclosure_policy ADD CONSTRAINT chk_sdp_minimum_interval CHECK (minimum_interval_minutes > 0);
ALTER TABLE ${catalog}.${css_schema}.sensing_disclosure_policy ADD CONSTRAINT chk_sdp_effective_window CHECK (effective_to_date IS NULL OR effective_to_date > effective_from_date);

-- ---------------- sensor_device ----------------
ALTER TABLE ${catalog}.${css_schema}.sensor_device ADD CONSTRAINT fk_sensor_device_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${css_schema}.sensor_device ADD CONSTRAINT fk_sensor_device_zone FOREIGN KEY (store_zone_sk) REFERENCES ${catalog}.${css_schema}.store_zone (store_zone_sk);
ALTER TABLE ${catalog}.${css_schema}.sensor_device ADD CONSTRAINT fk_sensor_device_deployment FOREIGN KEY (sensing_deployment_sk) REFERENCES ${catalog}.${css_schema}.sensing_deployment (sensing_deployment_sk);
ALTER TABLE ${catalog}.${css_schema}.sensor_device ADD CONSTRAINT fk_sensor_device_equipment FOREIGN KEY (equipment_sk) REFERENCES ${catalog}.${equipment_schema}.equipment (equipment_sk);

ALTER TABLE ${catalog}.${css_schema}.sensor_device ADD CONSTRAINT chk_sensor_device_type CHECK (device_type IS NULL OR device_type IN ('people_counter', 'occupancy_sensor', 'temperature', 'humidity', 'co2', 'illuminance', 'energy_meter', 'door_contact', 'rfid_reader', 'shelf_sensor', 'camera', 'esl_gateway'));
ALTER TABLE ${catalog}.${css_schema}.sensor_device ADD CONSTRAINT chk_sensor_device_technology CHECK (sensing_technology IS NULL OR sensing_technology IN ('ir_beam', 'thermal', 'video_cv', 'stereo_vision', 'time_of_flight', 'wifi_probe', 'ble_probe', 'rfid_uhf', 'load_cell', 'thermistor', 'thermocouple', 'ndir', 'contact'));
ALTER TABLE ${catalog}.${css_schema}.sensor_device ADD CONSTRAINT chk_sensor_device_role CHECK (device_role IS NULL OR device_role IN ('sense', 'actuate', 'both'));
ALTER TABLE ${catalog}.${css_schema}.sensor_device ADD CONSTRAINT chk_sensor_device_status CHECK (device_status IS NULL OR device_status IN ('active', 'inactive', 'faulty', 'maintenance', 'decommissioned'));
ALTER TABLE ${catalog}.${css_schema}.sensor_device ADD CONSTRAINT chk_sensor_device_probe CHECK (probe_type IS NULL OR probe_type IN ('buffered', 'air', 'glycol', 'surface', 'none'));
ALTER TABLE ${catalog}.${css_schema}.sensor_device ADD CONSTRAINT chk_sensor_device_calibration_window CHECK (calibration_valid_to IS NULL OR calibration_valid_from IS NULL OR calibration_valid_to >= calibration_valid_from);
ALTER TABLE ${catalog}.${css_schema}.sensor_device ADD CONSTRAINT chk_sensor_device_tolerance CHECK (accuracy_tolerance IS NULL OR accuracy_tolerance >= 0);

-- ---------------- tagged_item ----------------
ALTER TABLE ${catalog}.${css_schema}.tagged_item ADD CONSTRAINT fk_tagged_item_product FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${css_schema}.tagged_item ADD CONSTRAINT chk_tagged_item_epc_scheme CHECK (epc_scheme IN ('sgtin', 'grai'));
ALTER TABLE ${catalog}.${css_schema}.tagged_item ADD CONSTRAINT chk_tagged_item_privacy_state CHECK (tag_privacy_state IN ('active', 'protected', 'killed', 'detached'));
ALTER TABLE ${catalog}.${css_schema}.tagged_item ADD CONSTRAINT chk_tagged_item_lifecycle CHECK (decommissioned_at_ts IS NULL OR decommissioned_at_ts >= commissioned_at_ts);

-- ---------------- rfid_count_session ----------------
ALTER TABLE ${catalog}.${css_schema}.rfid_count_session ADD CONSTRAINT fk_rfid_count_session_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${css_schema}.rfid_count_session ADD CONSTRAINT fk_rfid_count_session_primary_device FOREIGN KEY (primary_sensor_device_sk) REFERENCES ${catalog}.${css_schema}.sensor_device (sensor_device_sk);

ALTER TABLE ${catalog}.${css_schema}.rfid_count_session ADD CONSTRAINT chk_rfid_count_session_method CHECK (count_method IN ('handheld_sweep', 'fixed_window', 'robot_sweep'));
ALTER TABLE ${catalog}.${css_schema}.rfid_count_session ADD CONSTRAINT chk_rfid_count_session_scope CHECK (scope_type IN ('full_store', 'partial'));
ALTER TABLE ${catalog}.${css_schema}.rfid_count_session ADD CONSTRAINT chk_rfid_count_session_window CHECK (ended_at_ts >= started_at_ts);
ALTER TABLE ${catalog}.${css_schema}.rfid_count_session ADD CONSTRAINT chk_rfid_count_session_hour CHECK (hour_of_day IS NULL OR hour_of_day BETWEEN 0 AND 23);

-- ---------------- rfid_read_event ----------------
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT fk_rfid_read_event_tagged_item FOREIGN KEY (tagged_item_sk) REFERENCES ${catalog}.${css_schema}.tagged_item (tagged_item_sk);
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT fk_rfid_read_event_product FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT fk_rfid_read_event_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT fk_rfid_read_event_zone FOREIGN KEY (store_zone_sk) REFERENCES ${catalog}.${css_schema}.store_zone (store_zone_sk);
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT fk_rfid_read_event_device FOREIGN KEY (sensor_device_sk) REFERENCES ${catalog}.${css_schema}.sensor_device (sensor_device_sk);
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT fk_rfid_read_event_deployment FOREIGN KEY (sensing_deployment_sk) REFERENCES ${catalog}.${css_schema}.sensing_deployment (sensing_deployment_sk);
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT fk_rfid_read_event_session FOREIGN KEY (rfid_count_session_sk) REFERENCES ${catalog}.${css_schema}.rfid_count_session (rfid_count_session_sk);
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT fk_rfid_read_event_shipment_line FOREIGN KEY (shipment_line_sk) REFERENCES ${catalog}.${logistics_schema}.shipment_line (shipment_line_sk);

ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT chk_rfid_read_event_biz_step CHECK (biz_step_uri IS NULL OR biz_step_uri IN (
  'https://ref.gs1.org/cbv/BizStep-commissioning',
  'https://ref.gs1.org/cbv/BizStep-receiving',
  'https://ref.gs1.org/cbv/BizStep-stocking',
  'https://ref.gs1.org/cbv/BizStep-storing',
  'https://ref.gs1.org/cbv/BizStep-retail_selling',
  'https://ref.gs1.org/cbv/BizStep-cycle_counting',
  'https://ref.gs1.org/cbv/BizStep-stock_taking',
  'https://ref.gs1.org/cbv/BizStep-shipping',
  'https://ref.gs1.org/cbv/BizStep-staging_outbound',
  'https://ref.gs1.org/cbv/BizStep-inspecting',
  'https://ref.gs1.org/cbv/BizStep-killing',
  'https://ref.gs1.org/cbv/BizStep-decommissioning'
));
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT chk_rfid_read_event_disposition CHECK (disposition_uri IS NULL OR disposition_uri IN (
  'https://ref.gs1.org/cbv/Disp-sellable_accessible',
  'https://ref.gs1.org/cbv/Disp-sellable_not_accessible',
  'https://ref.gs1.org/cbv/Disp-in_transit',
  'https://ref.gs1.org/cbv/Disp-retail_sold',
  'https://ref.gs1.org/cbv/Disp-damaged',
  'https://ref.gs1.org/cbv/Disp-expired',
  'https://ref.gs1.org/cbv/Disp-recalled',
  'https://ref.gs1.org/cbv/Disp-stolen',
  'https://ref.gs1.org/cbv/Disp-unavailable',
  'https://ref.gs1.org/cbv/Disp-unknown'
));
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT chk_rfid_read_event_zone_source CHECK (zone_source IN ('device_placement', 'operator_declared', 'platform_localization'));
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT chk_rfid_read_event_direction CHECK (direction_code IN ('in', 'out', 'unknown', 'not_applicable'));
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT chk_rfid_read_event_confidence CHECK ((direction_confidence IS NULL OR direction_confidence BETWEEN 0 AND 1) AND attribution_confidence BETWEEN 0 AND 1);
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT chk_rfid_read_event_counts CHECK (read_count > 0 AND (duplicate_delivery_count IS NULL OR duplicate_delivery_count >= 0));
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT chk_rfid_read_event_window CHECK (first_seen_ts <= event_ts AND event_ts <= last_seen_ts);
ALTER TABLE ${catalog}.${css_schema}.rfid_read_event ADD CONSTRAINT chk_rfid_read_event_hour CHECK (hour_of_day IS NULL OR hour_of_day BETWEEN 0 AND 23);

-- ---------------- sensor_report_interval ----------------
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT fk_sensor_report_interval_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT fk_sensor_report_interval_zone FOREIGN KEY (store_zone_sk) REFERENCES ${catalog}.${css_schema}.store_zone (store_zone_sk);
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT fk_sensor_report_interval_device FOREIGN KEY (sensor_device_sk) REFERENCES ${catalog}.${css_schema}.sensor_device (sensor_device_sk);
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT fk_sensor_report_interval_deployment FOREIGN KEY (sensing_deployment_sk) REFERENCES ${catalog}.${css_schema}.sensing_deployment (sensing_deployment_sk);
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT fk_sensor_report_interval_product FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);
-- The asset FK belongs on the FACT as well as on sensor_device. A cold-chain reading is
-- about the refrigeration case, not about the probe attached to it this month: reaching the
-- asset only through the device registry means re-pointing one sensor silently rewrites the
-- temperature history of two assets, which is the opposite of what FSMA-style traceability
-- needs. FK-COMPLETENESS (A.15) is enforced canonical-core-only, so this is house
-- convention rather than a gate, which is precisely why it is easy to leave out.
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT fk_sensor_report_interval_equipment FOREIGN KEY (equipment_sk) REFERENCES ${catalog}.${equipment_schema}.equipment (equipment_sk);

-- ---------------- foot_traffic_interval_detail ----------------
-- The shared key is both PK and FK, which makes this a strict one-to-one extension
-- rather than a second fact with an independently drifting grain.
ALTER TABLE ${catalog}.${css_schema}.foot_traffic_interval_detail
  ADD CONSTRAINT fk_foot_traffic_interval_detail_report
  FOREIGN KEY (sensor_report_interval_sk)
  REFERENCES ${catalog}.${css_schema}.sensor_report_interval (sensor_report_interval_sk);

-- NOTE: trading_date -> fiscal_calendar is a LOGICAL join, deliberately NOT an FK.
-- Unity Catalog requires that "foreign keys must reference a primary key or unique
-- constraint in another table". fiscal_calendar's PK is date_sk; date_key carries no
-- UNIQUE constraint (UNIQUE is itself Public Preview), so a FK to date_key WOULD BE
-- REJECTED at deploy time. This follows the house convention already set at
-- canonical-core/calendar/relationships.sql:11-12.
--   Logical join: ${catalog}.${css_schema}.sensor_report_interval.trading_date
--   Logical join: ${catalog}.${css_schema}.rfid_count_session.trading_date
--   Logical join: ${catalog}.${css_schema}.rfid_read_event.trading_date
--              -> ${catalog}.${calendar_schema}.fiscal_calendar.date_key
-- Enforced by the sri_calendar_orphan, rcs_calendar_orphan, and rre_calendar_orphan
-- checks in checks.sql rather than by constraints.

-- Enum domains. These are declared on the published aggregate tier, which is the only
-- tier CSS owns -- raw sub-interval pulses live in bronze outside ORDM, where enum
-- enforcement belongs in pipeline expectations rather than table constraints so a
-- single bad vendor value cannot stall ingest.
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT chk_sri_subject_type CHECK (subject_type IN ('epc', 'gln', 'grai', 'point', 'space'));
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT chk_sri_report_type CHECK (report_type IN ('gs1:Count', 'gs1:Temperature', 'gs1:RelativeHumidity', 'gs1:Power', 'gs1:Energy', 'gs1:Mass', 'gs1:Illuminance', 'gs1:VolumeFraction'));
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT chk_sri_aggregation_level CHECK (aggregation_level IN ('site', 'entrance', 'area', 'device', 'subject'));
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT chk_sri_day_part CHECK (day_part IS NULL OR day_part IN ('pre_open', 'morning', 'midday', 'afternoon', 'evening', 'late'));
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT chk_sri_time_mode CHECK (time_mode IS NULL OR time_mode IN ('within_operating_hours', 'all_day'));
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT chk_sri_validity CHECK (measurement_validity IS NULL OR measurement_validity IN ('valid', 'degraded', 'invalid', 'imputed'));
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT chk_sri_completeness CHECK (arrival_completeness IS NULL OR arrival_completeness IN ('complete', 'incomplete', 'late_arrived', 'precheck'));

-- Structural invariants Delta CAN express. Cross-row interval and extension integrity
-- remain in checks.sql.
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT chk_sri_interval_minutes CHECK (interval_minutes > 0);
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT chk_sri_ratios CHECK ((uptime_ratio IS NULL OR (uptime_ratio BETWEEN 0 AND 1)) AND (coverage_ratio IS NULL OR (coverage_ratio BETWEEN 0 AND 1)) AND (confidence_score IS NULL OR (confidence_score BETWEEN 0 AND 1)));
ALTER TABLE ${catalog}.${css_schema}.sensor_report_interval ADD CONSTRAINT chk_sri_observations_nonneg CHECK ((source_observation_count IS NULL OR source_observation_count >= 0) AND (expected_observation_count IS NULL OR expected_observation_count >= 0));

ALTER TABLE ${catalog}.${css_schema}.foot_traffic_interval_detail ADD CONSTRAINT chk_ftid_counting_unit CHECK (counting_unit IS NULL OR counting_unit IN ('person', 'group', 'device', 'object'));
ALTER TABLE ${catalog}.${css_schema}.foot_traffic_interval_detail ADD CONSTRAINT chk_ftid_directionality CHECK (directionality IS NULL OR directionality IN ('bidirectional', 'unidirectional', 'none'));
ALTER TABLE ${catalog}.${css_schema}.foot_traffic_interval_detail ADD CONSTRAINT chk_ftid_passby_convention CHECK (passby_convention IS NULL OR passby_convention IN ('includes_entrants', 'excludes_entrants'));
ALTER TABLE ${catalog}.${css_schema}.foot_traffic_interval_detail ADD CONSTRAINT chk_ftid_excl_method CHECK (staff_exclusion_method IS NULL OR staff_exclusion_method IN ('none', 'exclusion_line', 'zone_button', 'patterned_tag', 'fabric_tag', 'uniform_ml', 'reidentification', 'fixed_count_subtraction', 'scaling_factor'));
ALTER TABLE ${catalog}.${css_schema}.foot_traffic_interval_detail ADD CONSTRAINT chk_ftid_excl_stage CHECK (staff_exclusion_stage IS NULL OR staff_exclusion_stage IN ('none', 'at_sensor', 'at_aggregation'));
ALTER TABLE ${catalog}.${css_schema}.foot_traffic_interval_detail ADD CONSTRAINT chk_ftid_excl_grade CHECK (staff_exclusion_grade IS NULL OR staff_exclusion_grade IN ('high', 'medium', 'low'));
ALTER TABLE ${catalog}.${css_schema}.foot_traffic_interval_detail ADD CONSTRAINT chk_ftid_adjustment_source CHECK (adjustment_source IS NULL OR adjustment_source IN ('manual', 'reset', 'reconciliation', 'vendor_correction'));
ALTER TABLE ${catalog}.${css_schema}.foot_traffic_interval_detail ADD CONSTRAINT chk_ftid_counts_nonneg CHECK ((footfall_count IS NULL OR footfall_count >= 0) AND (entry_count IS NULL OR entry_count >= 0) AND (exit_count IS NULL OR exit_count >= 0) AND (dwell_seconds_total IS NULL OR dwell_seconds_total >= 0) AND (dwell_count IS NULL OR dwell_count >= 0));

-- Negative occupancy is a drift signal and therefore remains a warn-severity DQ
-- condition rather than a rejecting table constraint.

-- ========== Automation loop (IoT Sensor Monitoring): sense -> evaluate -> act -> log ==========
-- actuator_capability, evaluation_rule and automation_action reuse the existing
-- sensor_device / sensor_report_interval / equipment entities rather than redeclaring a
-- device registry (ADR 0032, standards §A.2). All FKs are single-column on the parent _sk.

-- ---------------- actuator_capability ----------------
ALTER TABLE ${catalog}.${css_schema}.actuator_capability ADD CONSTRAINT fk_actuator_capability_device FOREIGN KEY (sensor_device_sk) REFERENCES ${catalog}.${css_schema}.sensor_device (sensor_device_sk);
ALTER TABLE ${catalog}.${css_schema}.actuator_capability ADD CONSTRAINT fk_actuator_capability_equipment FOREIGN KEY (equipment_sk) REFERENCES ${catalog}.${equipment_schema}.equipment (equipment_sk);

ALTER TABLE ${catalog}.${css_schema}.actuator_capability ADD CONSTRAINT chk_actuator_capability_command CHECK (command_type IS NULL OR command_type IN ('toggle_power', 'set_level', 'set_setpoint', 'open_close', 'dispense', 'display_message', 'reset'));
ALTER TABLE ${catalog}.${css_schema}.actuator_capability ADD CONSTRAINT chk_actuator_capability_status CHECK (actuator_status IS NULL OR actuator_status IN ('active', 'inactive', 'faulty', 'maintenance', 'decommissioned'));

-- ---------------- evaluation_rule ----------------
ALTER TABLE ${catalog}.${css_schema}.evaluation_rule ADD CONSTRAINT fk_evaluation_rule_device FOREIGN KEY (sensor_device_sk) REFERENCES ${catalog}.${css_schema}.sensor_device (sensor_device_sk);

-- report_type shares sensor_report_interval's GS1 CBV vocabulary so a rule and the
-- readings it evaluates are discriminated identically (see chk_sri_report_type).
ALTER TABLE ${catalog}.${css_schema}.evaluation_rule ADD CONSTRAINT chk_evaluation_rule_report_type CHECK (report_type IS NULL OR report_type IN ('gs1:Count', 'gs1:Temperature', 'gs1:RelativeHumidity', 'gs1:Power', 'gs1:Energy', 'gs1:Mass', 'gs1:Illuminance', 'gs1:VolumeFraction'));
ALTER TABLE ${catalog}.${css_schema}.evaluation_rule ADD CONSTRAINT chk_evaluation_rule_operator CHECK (condition_operator IS NULL OR condition_operator IN ('greater_than', 'greater_than_or_equal', 'less_than', 'less_than_or_equal', 'equal', 'not_equal', 'outside_range', 'inside_range'));
ALTER TABLE ${catalog}.${css_schema}.evaluation_rule ADD CONSTRAINT chk_evaluation_rule_severity CHECK (severity IS NULL OR severity IN ('info', 'warning', 'critical'));
ALTER TABLE ${catalog}.${css_schema}.evaluation_rule ADD CONSTRAINT chk_evaluation_rule_window CHECK (time_window_seconds IS NULL OR time_window_seconds >= 0);
-- A range operator needs both bounds; a scalar operator needs only the lower one.
ALTER TABLE ${catalog}.${css_schema}.evaluation_rule ADD CONSTRAINT chk_evaluation_rule_range_bounds CHECK (condition_operator IS NULL OR condition_operator NOT IN ('inside_range', 'outside_range') OR (threshold_value_numeric IS NOT NULL AND threshold_value_upper IS NOT NULL));

-- ---------------- automation_action ----------------
ALTER TABLE ${catalog}.${css_schema}.automation_action ADD CONSTRAINT fk_automation_action_rule FOREIGN KEY (evaluation_rule_sk) REFERENCES ${catalog}.${css_schema}.evaluation_rule (evaluation_rule_sk);
ALTER TABLE ${catalog}.${css_schema}.automation_action ADD CONSTRAINT fk_automation_action_actuator FOREIGN KEY (actuator_capability_sk) REFERENCES ${catalog}.${css_schema}.actuator_capability (actuator_capability_sk);

ALTER TABLE ${catalog}.${css_schema}.automation_action ADD CONSTRAINT chk_automation_action_type CHECK (action_type IS NULL OR action_type IN ('system_command', 'notification', 'webhook', 'ticket', 'log_only'));
ALTER TABLE ${catalog}.${css_schema}.automation_action ADD CONSTRAINT chk_automation_action_target CHECK (target_entity_type IS NULL OR target_entity_type IN ('actuator', 'role', 'person', 'external_system', 'none'));
-- The typed actuator FK is present exactly when the polymorphic target is an actuator,
-- so the physical-command path is a declared FK and the other target kinds are not.
ALTER TABLE ${catalog}.${css_schema}.automation_action ADD CONSTRAINT chk_automation_action_actuator_target CHECK ((target_entity_type = 'actuator' AND actuator_capability_sk IS NOT NULL) OR (COALESCE(target_entity_type, 'none') <> 'actuator' AND actuator_capability_sk IS NULL));

-- ---------------- execution_log ----------------
ALTER TABLE ${catalog}.${css_schema}.execution_log ADD CONSTRAINT fk_execution_log_action FOREIGN KEY (automation_action_sk) REFERENCES ${catalog}.${css_schema}.automation_action (automation_action_sk);
ALTER TABLE ${catalog}.${css_schema}.execution_log ADD CONSTRAINT fk_execution_log_actuator FOREIGN KEY (actuator_capability_sk) REFERENCES ${catalog}.${css_schema}.actuator_capability (actuator_capability_sk);
ALTER TABLE ${catalog}.${css_schema}.execution_log ADD CONSTRAINT fk_execution_log_rule FOREIGN KEY (evaluation_rule_sk) REFERENCES ${catalog}.${css_schema}.evaluation_rule (evaluation_rule_sk);
ALTER TABLE ${catalog}.${css_schema}.execution_log ADD CONSTRAINT fk_execution_log_interval FOREIGN KEY (sensor_report_interval_sk) REFERENCES ${catalog}.${css_schema}.sensor_report_interval (sensor_report_interval_sk);

ALTER TABLE ${catalog}.${css_schema}.execution_log ADD CONSTRAINT chk_execution_log_status CHECK (execution_status IN ('success', 'failure', 'pending', 'timeout', 'skipped'));
ALTER TABLE ${catalog}.${css_schema}.execution_log ADD CONSTRAINT chk_execution_log_latency CHECK (latency_ms IS NULL OR latency_ms >= 0);

-- ========== Smart Shelf: expected state, observed state, ESL observation layer ==========
-- shelf_state_observation and esl_price_observation reuse the existing store_zone /
-- sensor_device / sensing_deployment entities (standards §A.2); shelf_position_assignment's
-- planogram_id is a LOGICAL reference to BMV planogram, deliberately not a FK (ADR 0040,
-- ADR 0024 read-only gold-to-gold reconciliation). No Smart Shelf FK touches pricing
-- surfaces; esl_price_observation reads product_price by capture, not by key (ADR 0030).

-- ---------------- shelf_position_assignment ----------------
ALTER TABLE ${catalog}.${css_schema}.shelf_position_assignment ADD CONSTRAINT fk_shelf_position_assignment_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${css_schema}.shelf_position_assignment ADD CONSTRAINT fk_shelf_position_assignment_zone FOREIGN KEY (store_zone_sk) REFERENCES ${catalog}.${css_schema}.store_zone (store_zone_sk);
ALTER TABLE ${catalog}.${css_schema}.shelf_position_assignment ADD CONSTRAINT fk_shelf_position_assignment_product FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${css_schema}.shelf_position_assignment ADD CONSTRAINT chk_shelf_position_assignment_source CHECK (assignment_source IS NULL OR assignment_source IN ('planogram', 'manual', 'vendor'));
ALTER TABLE ${catalog}.${css_schema}.shelf_position_assignment ADD CONSTRAINT chk_shelf_position_assignment_status CHECK (assignment_status IS NULL OR assignment_status IN ('active', 'suspended', 'retired'));
ALTER TABLE ${catalog}.${css_schema}.shelf_position_assignment ADD CONSTRAINT chk_shelf_position_assignment_facings CHECK ((expected_facing_count IS NULL OR expected_facing_count >= 0) AND (min_facing_count IS NULL OR min_facing_count >= 0) AND (min_facing_count IS NULL OR expected_facing_count IS NULL OR min_facing_count <= expected_facing_count));

-- ---------------- shelf_state_observation ----------------
ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation ADD CONSTRAINT fk_shelf_state_observation_assignment FOREIGN KEY (shelf_position_assignment_sk) REFERENCES ${catalog}.${css_schema}.shelf_position_assignment (shelf_position_assignment_sk);
ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation ADD CONSTRAINT fk_shelf_state_observation_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation ADD CONSTRAINT fk_shelf_state_observation_zone FOREIGN KEY (store_zone_sk) REFERENCES ${catalog}.${css_schema}.store_zone (store_zone_sk);
ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation ADD CONSTRAINT fk_shelf_state_observation_product FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);
ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation ADD CONSTRAINT fk_shelf_state_observation_device FOREIGN KEY (sensor_device_sk) REFERENCES ${catalog}.${css_schema}.sensor_device (sensor_device_sk);
ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation ADD CONSTRAINT fk_shelf_state_observation_deployment FOREIGN KEY (sensing_deployment_sk) REFERENCES ${catalog}.${css_schema}.sensing_deployment (sensing_deployment_sk);

ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation ADD CONSTRAINT chk_shelf_state_observation_state CHECK (shelf_state IN ('in_stock', 'low_stock', 'out_of_stock', 'misplaced', 'unknown'));
ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation ADD CONSTRAINT chk_shelf_state_observation_zone_source CHECK (zone_source IN ('device_placement', 'operator_declared', 'platform_localization'));
ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation ADD CONSTRAINT chk_shelf_state_observation_validity CHECK (measurement_validity IS NULL OR measurement_validity IN ('valid', 'degraded', 'invalid', 'imputed'));
ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation ADD CONSTRAINT chk_shelf_state_observation_arrival CHECK (arrival_completeness IS NULL OR arrival_completeness IN ('complete', 'incomplete', 'late_arrived', 'precheck'));
ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation ADD CONSTRAINT chk_shelf_state_observation_counts_nonneg CHECK ((observed_facing_count IS NULL OR observed_facing_count >= 0) AND (min_facing_threshold IS NULL OR min_facing_threshold >= 0) AND (estimated_unit_count IS NULL OR estimated_unit_count >= 0) AND (estimated_weight_grams IS NULL OR estimated_weight_grams >= 0) AND (pick_count_since_prior IS NULL OR pick_count_since_prior >= 0) AND (put_count_since_prior IS NULL OR put_count_since_prior >= 0));
ALTER TABLE ${catalog}.${css_schema}.shelf_state_observation ADD CONSTRAINT chk_shelf_state_observation_ratios CHECK ((attribution_confidence BETWEEN 0 AND 1) AND (confidence_score IS NULL OR (confidence_score BETWEEN 0 AND 1)) AND (coverage_ratio IS NULL OR (coverage_ratio BETWEEN 0 AND 1)));

-- ---------------- esl_label ----------------
ALTER TABLE ${catalog}.${css_schema}.esl_label ADD CONSTRAINT fk_esl_label_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${css_schema}.esl_label ADD CONSTRAINT fk_esl_label_gateway FOREIGN KEY (sensor_device_sk) REFERENCES ${catalog}.${css_schema}.sensor_device (sensor_device_sk);

ALTER TABLE ${catalog}.${css_schema}.esl_label ADD CONSTRAINT chk_esl_label_display_technology CHECK (display_technology IS NULL OR display_technology IN ('eink_mono', 'eink_multicolor', 'lcd', 'segment'));
ALTER TABLE ${catalog}.${css_schema}.esl_label ADD CONSTRAINT chk_esl_label_battery_class CHECK (battery_life_class IS NULL OR battery_life_class IN ('under_3y', 'y3_to_5', 'y5_to_10', 'over_10y'));
ALTER TABLE ${catalog}.${css_schema}.esl_label ADD CONSTRAINT chk_esl_label_status CHECK (label_status IS NULL OR label_status IN ('active', 'inactive', 'faulty', 'retired'));

-- ---------------- esl_label_assignment ----------------
ALTER TABLE ${catalog}.${css_schema}.esl_label_assignment ADD CONSTRAINT fk_esl_label_assignment_label FOREIGN KEY (esl_label_sk) REFERENCES ${catalog}.${css_schema}.esl_label (esl_label_sk);
ALTER TABLE ${catalog}.${css_schema}.esl_label_assignment ADD CONSTRAINT fk_esl_label_assignment_product FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);
ALTER TABLE ${catalog}.${css_schema}.esl_label_assignment ADD CONSTRAINT fk_esl_label_assignment_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${css_schema}.esl_label_assignment ADD CONSTRAINT fk_esl_label_assignment_zone FOREIGN KEY (store_zone_sk) REFERENCES ${catalog}.${css_schema}.store_zone (store_zone_sk);

ALTER TABLE ${catalog}.${css_schema}.esl_label_assignment ADD CONSTRAINT chk_esl_label_assignment_source CHECK (binding_source IS NULL OR binding_source IN ('platform', 'manual'));
ALTER TABLE ${catalog}.${css_schema}.esl_label_assignment ADD CONSTRAINT chk_esl_label_assignment_status CHECK (binding_status IS NULL OR binding_status IN ('active', 'suspended', 'retired'));

-- ---------------- esl_price_observation ----------------
ALTER TABLE ${catalog}.${css_schema}.esl_price_observation ADD CONSTRAINT fk_esl_price_observation_label FOREIGN KEY (esl_label_sk) REFERENCES ${catalog}.${css_schema}.esl_label (esl_label_sk);
ALTER TABLE ${catalog}.${css_schema}.esl_price_observation ADD CONSTRAINT fk_esl_price_observation_assignment FOREIGN KEY (esl_label_assignment_sk) REFERENCES ${catalog}.${css_schema}.esl_label_assignment (esl_label_assignment_sk);
ALTER TABLE ${catalog}.${css_schema}.esl_price_observation ADD CONSTRAINT fk_esl_price_observation_product FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);
ALTER TABLE ${catalog}.${css_schema}.esl_price_observation ADD CONSTRAINT fk_esl_price_observation_store FOREIGN KEY (store_sk) REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${css_schema}.esl_price_observation ADD CONSTRAINT fk_esl_price_observation_zone FOREIGN KEY (store_zone_sk) REFERENCES ${catalog}.${css_schema}.store_zone (store_zone_sk);

ALTER TABLE ${catalog}.${css_schema}.esl_price_observation ADD CONSTRAINT chk_esl_price_observation_source CHECK (observation_source IN ('platform_ack', 'shelf_cv', 'manual_audit'));
ALTER TABLE ${catalog}.${css_schema}.esl_price_observation ADD CONSTRAINT chk_esl_price_observation_record_source CHECK (price_of_record_source IS NULL OR price_of_record_source IN ('pricing_platform', 'product_price', 'pos_system', 'scale_plu', 'manual'));
-- ADR 0030 §Decision.2 verbatim: the invariant is schema-visible and violating it must
-- be an explicit, reviewable act. The DQ assertion eslp_sensing_flag_false backs it.
ALTER TABLE ${catalog}.${css_schema}.esl_price_observation ADD CONSTRAINT chk_esl_price_observation_sensing_flag CHECK (sensing_derived_input_flag = FALSE);
ALTER TABLE ${catalog}.${css_schema}.esl_price_observation ADD CONSTRAINT chk_esl_price_observation_amounts_nonneg CHECK ((displayed_price IS NULL OR displayed_price >= 0) AND (displayed_unit_price IS NULL OR displayed_unit_price >= 0) AND (price_of_record IS NULL OR price_of_record >= 0) AND (display_sync_latency_seconds IS NULL OR display_sync_latency_seconds >= 0));
-- A captured price is auditable only when its currency travels with it. The second
-- constraint fails closed at write time for the regulator-facing scalar comparison;
-- eslp_price_of_record_currency mirrors both rules in post-hoc DQ.
ALTER TABLE ${catalog}.${css_schema}.esl_price_observation ADD CONSTRAINT chk_esl_price_observation_record_currency_pair CHECK ((price_of_record IS NULL AND price_of_record_currency_code IS NULL) OR (price_of_record IS NOT NULL AND price_of_record_currency_code IS NOT NULL));
ALTER TABLE ${catalog}.${css_schema}.esl_price_observation ADD CONSTRAINT chk_esl_price_observation_comparison_currency CHECK (displayed_price IS NULL OR price_of_record IS NULL OR (displayed_currency_code IS NOT NULL AND price_of_record_currency_code IS NOT NULL AND displayed_currency_code = price_of_record_currency_code));
