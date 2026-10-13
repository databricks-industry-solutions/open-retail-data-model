-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: sensor_device
-- Layer: outcome package (gold / dimensional, master-tagged)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- The physical sensing/actuating device registry. Nothing in ORDM owns this today;
-- ADR 0021 explicitly names "Connected Store Signals' physical sensor_device" as a
-- gold concept.
--
-- Built in the Foot Traffic phase rather than deferred to IoT Sensor Monitoring. The
-- deferred alternative meant shipping a source_equipment_id breadcrumb on a published
-- 0.1-beta fact and then altering it to add the real FK -- churn for a table whose
-- final shape is already known. device_type therefore already covers rfid_reader,
-- shelf_sensor and esl_gateway even though only the counting types are populated now.
--
-- Vocabulary is anchored on published standards rather than invented:
--   * brick_class_iri  -- Brick Schema 1.4.4 equipment/point class
--   * unit_iri         -- QUDT unit, the internal canonical unit reference
--   * bacnet_*         -- ANSI/ASHRAE 135-2024, for building-automation-sourced devices
--   * opc_ua_node_id   -- for industrial/refrigeration controllers
-- Verified Brick gap: there is NO refrigerated display case class (Freezer and
-- Refrigeration_System are the nearest). Local extension noted, worth upstreaming.
--
-- Distinct from canonical-core `equipment`: equipment is a maintained ASSET with a
-- maintenance history; a sensor_device is an INSTRUMENT that observes. A device may
-- monitor an asset (equipment_sk, nullable) or ambient space (NULL), and an ambient
-- zone sensor has no asset at all -- which is why it cannot be written to
-- equipment_reading (equipment_id is STRING NOT NULL there).
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.sensor_device (
  sensor_device_sk      BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version.',
  sensor_device_id      STRING NOT NULL
                          COMMENT 'Durable natural/business key for the device. Stable across SCD2 versions and across firmware upgrades.',

  store_sk              BIGINT COMMENT 'FK to store.store_sk.',
  store_id              STRING COMMENT 'Durable store business key.',
  store_zone_sk         BIGINT COMMENT 'FK to store_zone.store_zone_sk -- where the device is installed.',
  store_zone_id         STRING COMMENT 'Durable zone id. The SCD2-safe join key.',

  device_type           STRING COMMENT 'What the device is. Allowed values: people_counter, occupancy_sensor, temperature, humidity, co2, illuminance, energy_meter, door_contact, rfid_reader, shelf_sensor, camera, esl_gateway.',
  sensing_technology    STRING COMMENT 'How it senses -- drives the accuracy and privacy profile. Allowed values: ir_beam, thermal, video_cv, stereo_vision, time_of_flight, wifi_probe, ble_probe, rfid_uhf, load_cell, thermistor, thermocouple, ndir, contact.',
  device_role           STRING COMMENT 'Allowed values: sense, actuate, both. ESL gateways actuate; counters sense.',

  manufacturer          STRING COMMENT 'Device manufacturer.',
  model                 STRING COMMENT 'Device model designation.',
  serial_number         STRING COMMENT 'Manufacturer serial number.',
  firmware_version      STRING COMMENT 'Current firmware version. Changes here are a common cause of a step change in counting behaviour, so it is versioned via SCD2.',

  -- Counting capability. Recorded on the device because it constrains what the
  -- measurement can mean: a non-directional beam sensor CANNOT report exits, and the
  -- honest fact-level representation is NULL rather than 0.
  is_directional        BOOLEAN COMMENT 'TRUE if the device distinguishes entry from exit. FALSE means exit_count must be NULL, never 0.',
  supports_dwell        BOOLEAN COMMENT 'TRUE if the device measures dwell time.',
  supports_occupancy    BOOLEAN COMMENT 'TRUE if the device reports occupancy directly rather than by entry/exit balance.',
  is_mobile_platform    BOOLEAN COMMENT 'TRUE for a reader mounted on a moving handheld or robotic platform. Mobile readers resolve event zones from operator declaration or platform localization, not installed device placement.',
  detection_limit_count INT     COMMENT 'Hardware detection ceiling, where the vendor publishes one. A peak at this value is capped, not exact.',
  battery_powered       BOOLEAN COMMENT 'TRUE if battery powered -- a capability, not a level. The battery LEVEL is a fast-moving measure and belongs on gold_css_device_health, not on an SCD2 dimension.',

  -- Standards anchoring
  brick_class_iri       STRING COMMENT 'Brick Schema 1.4.4 class IRI, e.g. https://brickschema.org/schema/Brick#Occupancy_Count_Sensor.',
  unit_iri              STRING COMMENT 'QUDT unit IRI for the device native unit, e.g. http://qudt.org/vocab/unit/DEG_C. The internal canonical unit reference.',
  uom_code              STRING COMMENT 'UN/CEFACT Recommendation 20 common code for the native unit, e.g. CEL, KWH, WTT, H87, P1. The interchange form.',
  bacnet_device_id      STRING COMMENT 'BACnet device instance, for building-automation-sourced devices (ANSI/ASHRAE 135-2024).',
  bacnet_object_ref     STRING COMMENT 'BACnet object reference, e.g. the Access Zone object (Clause 12.32) backing an occupancy count.',
  bacnet_out_of_service BOOLEAN COMMENT 'BACnet Out_Of_Service. When TRUE the Present_Value is SIMULATED -- without carrying this you silently ingest fabricated readings during commissioning.',
  opc_ua_node_id        STRING COMMENT 'OPC UA NodeId, for industrial/refrigeration controllers.',
  sparkplug_edge_node_id STRING COMMENT 'Sparkplug B (ISO/IEC 20237:2023) edge node id. Session identity is (edge_node_id, bdSeq).',

  -- Calibration is regulated metrology for pharmacy cold chain, not metadata:
  -- CDC/VFC requires a NIST-traceable Certificate of Calibration Testing retained a
  -- MINIMUM OF 3 YEARS, recalibration or replacement per the certificate, and a backup
  -- device with STAGGERED calibration dates so a unit is never unmonitored. Dated
  -- first-class attributes are what make that auditable; free text is not.
  calibration_certificate_id STRING COMMENT 'NIST-traceable Certificate of Calibration Testing identifier.',
  calibration_valid_from     DATE   COMMENT 'Start of the current calibration validity window.',
  calibration_valid_to       DATE   COMMENT 'End of the current calibration validity window. Past-due active devices are flagged by sd_calibration_current.',
  accuracy_tolerance         DOUBLE COMMENT 'Rated accuracy in the device native unit, e.g. 0.5 for +/-0.5 degC. CDC/VFC requires +/-0.5 degC for vaccine storage.',
  probe_type                 STRING COMMENT 'Allowed values: buffered, air, glycol, surface, none. CDC/VFC requires a BUFFERED probe for vaccine storage; an air probe reacts to door openings and produces false excursions.',
  is_backup_device           BOOLEAN COMMENT 'TRUE if this is the staggered-calibration backup unit required for vaccine storage.',

  -- The governance record. FK is mandatory in spirit: a sensing device without a
  -- deployment record cannot be assessed for lawfulness (ADR 0031).
  sensing_deployment_sk BIGINT COMMENT 'FK to sensing_deployment.sensing_deployment_sk -- the governance record for this installation.',
  sensing_deployment_id STRING COMMENT 'Durable deployment id. The SCD2-safe join key.',

  -- Optional link to a maintained asset. NULL for ambient sensors, which is the
  -- normal case for people counters.
  equipment_sk          BIGINT COMMENT 'FK to equipment.equipment_sk when the device monitors a maintained asset. NULL for ambient/space sensing.',
  equipment_id          STRING COMMENT 'Durable equipment business key. NULL for ambient/space sensing.',

  device_status         STRING COMMENT 'Allowed values: active, inactive, faulty, maintenance, decommissioned.',
  installed_date        DATE   COMMENT 'When the device was installed.',
  decommissioned_date   DATE   COMMENT 'When the device was removed. NULL while in service.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_sensor_device PRIMARY KEY (sensor_device_sk)
)
USING DELTA
CLUSTER BY (sensor_device_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals -- physical sensing/actuating device registry (SCD2), anchored on Brick 1.4.4 + QUDT.';

ALTER TABLE ${catalog}.${css_schema}.sensor_device SET TAGS ('dbx_data_type' = 'master');
