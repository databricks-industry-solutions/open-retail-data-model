-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: sensing_deployment
-- Layer: outcome package (gold / dimensional, master-tagged)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- The governance record for a sensing installation: sensor-in-a-place-for-a-purpose.
-- ADR 0031.
--
-- Why this is a dimension and not documentation: whether a given footfall row is
-- lawful to hold depends almost entirely on facts that are NOT in the measurement --
-- which technology produced it, in which jurisdiction, under which lawful basis,
-- whether a DPIA was completed and whether it covered employees, whether signage was
-- posted, whether a works council was consulted, and how long it may be retained.
-- The same footfall_count = 47 is unremarkable from a thermal counter in one
-- jurisdiction and unlawful from a Wi-Fi probe in another. Modelling it as a joinable
-- dimension turns "may we hold this?" into a query.
--
-- SCD2 because deployments change -- a DPIA is revised, signage is added, a lawful
-- basis changes -- and an audit asks for the governance record that applied AT THE
-- TIME OF MEASUREMENT, not the current one.
--
-- Distinct from ADR 0027's consent/suppression overlay, which addresses consented
-- INDIVIDUALS in the customer domain. In-store sensing usually has no identified
-- individual; the obligations attach to the deployment.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.sensing_deployment (
  sensing_deployment_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  sensing_deployment_id STRING NOT NULL
                          COMMENT 'Durable natural/business key for the deployment.',

  store_sk              BIGINT COMMENT 'FK to store.store_sk.',
  store_id              STRING COMMENT 'Durable store business key.',

  deployment_name       STRING COMMENT 'Human-readable deployment name, e.g. "Front-of-store thermal counters, UK estate".',
  sensing_method_code   STRING COMMENT 'Sensing technology -- the legal analysis differs per method. Allowed values: ir_beam, thermal, video_cv, stereo_vision, time_of_flight, wifi_probe, ble_probe, rfid, weight, door_contact, environmental.',
  sensing_purpose_code  STRING COMMENT 'Declared purpose. Allowed values: people_counting, occupancy_safety, queue_management, layout_optimisation, cold_chain_compliance, shelf_availability, asset_tracking, energy_management.',

  -- Lawful basis and jurisdiction
  lawful_basis_code     STRING COMMENT 'GDPR Art. 6 basis or equivalent. Allowed values: legitimate_interest, consent, legal_obligation, vital_interest, not_personal_data.',
  jurisdiction_code     STRING COMMENT 'ISO 3166-1 alpha-2 country, or country-subdivision for state-level regimes (e.g. US-IL for BIPA, US-TX for CUBI).',

  -- DPIA. A EUR 2.52M Spanish DPA decision (2021) is why the employee-risk question is
  -- tracked separately, because that deployment was penalised partly for a DPIA that
  -- did not account for risks to the store staff themselves.
  dpia_completed_flag   BOOLEAN COMMENT 'TRUE if a data protection impact assessment has been completed for this deployment.',
  dpia_reference        STRING  COMMENT 'Pointer to the DPIA artefact (document id or URI).',
  dpia_covers_employees_flag BOOLEAN COMMENT 'TRUE if the DPIA explicitly assessed risks to employees, not only customers.',
  dpia_review_due_date  DATE    COMMENT 'When the DPIA must be reassessed. EDPB 02/2026: anonymity is not a one-time determination.',

  -- Transparency. AI Act Art. 50(3) -- the deployer duty to inform persons exposed to
  -- emotion recognition or biometric categorisation -- applies from 2026-08-02 and was
  -- NOT postponed by the Digital Omnibus (Reg. (EU) 2026/1744), which deferred only
  -- Annex III high-risk obligations to 2027-12-02.
  signage_posted_flag   BOOLEAN COMMENT 'TRUE if on-premises notice is posted at every point of entry to the sensed area.',
  ai_act_notice_status  STRING  COMMENT 'AI Act Art. 50(3) deployer notice status. Allowed values: not_applicable, required_posted, required_not_posted.',

  -- Employment regime. Art. 88 GDPR lets Member States add rules with real teeth:
  -- German BetrVG 87(1) co-determination BEFORE introducing monitoring devices, French
  -- works-council consultation, Italian Statuto dei Lavoratori Art. 4, Polish Labour
  -- Code Art. 22-2. The consultation evidence is therefore a governed artefact.
  works_council_consulted_flag BOOLEAN COMMENT 'TRUE if employee representatives were consulted before deployment, where the jurisdiction requires it.',
  consultation_reference       STRING  COMMENT 'Pointer to the consultation record (document id or URI).',

  -- Consent gating. Hashed MACs remain personal data: Art. 29 WP Opinion 05/2014
  -- (hashing is pseudonymisation), EDPB Guidelines 01/2025 (pseudonymised data is
  -- still personal data), CNIL Oct 2018 (an operable opt-out, before AND after
  -- collection; "turn off your Wi-Fi" does not qualify).
  consent_required_flag STRING  COMMENT 'Whether the method requires consent. Allowed values: required, not_required, under_review. TRUE-equivalent (required) for wifi_probe and ble_probe.',
  optout_mechanism_code STRING  COMMENT 'How a data subject objects. Allowed values: none, signage_contact, in_store_kiosk, web_portal, not_applicable.',

  -- Retention is per-deployment, not global: the EDPB expects erasure of
  -- video-derived personal data "after a few days" and France caps vidéoprotection at
  -- one month (CSI Art. L.252-3), while FSMA 204 (2y), 21 CFR 117.315 (2y) and
  -- CDC/VFC calibration certificates (3y) attach to data that is NOT personal.
  retention_days_max    INT     COMMENT 'Maximum retention for personal data from this deployment, in days. A ceiling, not an entitlement.',
  retention_basis       STRING  COMMENT 'Why this retention -- the statutory or policy source.',

  -- Staff exclusion links the analytic requirement (a staff member at the door
  -- inflates footfall) to its governance consequence (to exclude staff you must
  -- identify them). See the staff columns on sensor_report_interval.
  staff_exclusion_method STRING COMMENT 'How staff are excluded. Allowed values: none, exclusion_line, zone_button, patterned_tag, fabric_tag, uniform_ml, reidentification, fixed_count_subtraction, scaling_factor.',
  staff_exclusion_stage  STRING COMMENT 'WHERE exclusion is applied -- without this you cannot tell whether a received number was already corrected, so double-correction is inevitable. Allowed values: none, at_sensor, at_aggregation.',

  external_disclosure_policy_sk BIGINT
      COMMENT 'FK lineage to the policy version current when this deployment version was written; shared views resolve controls through the durable id and fact date.',
  external_disclosure_policy_id STRING
      COMMENT 'Durable disclosure-policy id for SCD2-safe resolution.',

  deployment_status     STRING COMMENT 'Allowed values: planned, active, suspended, decommissioned.',
  deployed_date         DATE   COMMENT 'When sensing began at this deployment.',
  decommissioned_date   DATE   COMMENT 'When sensing ceased. NULL while active.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_sensing_deployment PRIMARY KEY (sensing_deployment_sk)
)
USING DELTA
CLUSTER BY (sensing_deployment_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals -- governance dimension for in-store sensing deployments (SCD2). ADR 0031.';

ALTER TABLE ${catalog}.${css_schema}.sensing_deployment SET TAGS ('dbx_data_type' = 'master');
