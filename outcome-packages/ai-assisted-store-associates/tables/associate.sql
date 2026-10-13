-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- Table: associate
-- Layer: outcome package (gold / dimensional, master-tagged)
-- Version: 0.5
-- Generated: 2026-08-29
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-29
-- ============================================================
-- The store-workforce dimension: the qualified, rostered associates a Next Best
-- Action can be routed to. Its upstream is the canonical-core labor domain:
-- associate_id is labor.employee.employee_id, and the demo generator projects one
-- associate per current labor.employee row (skills from labor.employee_skill).
-- It stays a master-tagged construct inside the gold package for the
-- NBA-specific attributes (precedent connected-store-signals/tables/store_zone.sql);
-- whether it should carry an employee_sk FK or become an extension of
-- labor.employee is open (CONTRIBUTING section 6 promotion path).
--
-- SCD2 carries only STABLE/slowly-changing workforce attributes (role, skills,
-- home store, employment type). The source model's fast-changing Current_Status /
-- Current_Zone are DELIBERATELY NOT here: live floor availability is operational
-- write-state the application owns (standards §0), and putting it on an SCD2 master
-- would churn a new version on every shift move. The routing target zone is instead
-- captured on suggested_action at dispatch time.
--
-- PII scope: an associate is a worker, but this table stores NO raw employee PII
-- (no name, contact, or government id). associate_id is a pseudonymous workforce
-- code. Raw employee identity is out of scope for the published model, the same way
-- cardholder data is out of scope for the customer/transaction schemas.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${aasa_schema}.associate (
  associate_sk          BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per SCD2 version; the join/FK target.',
  associate_id          STRING NOT NULL
                          COMMENT 'Durable business key for the associate — a pseudonymous workforce/employee code. Stable across SCD2 versions. Not a name (raw employee PII is out of scope; see header).',

  store_sk              BIGINT COMMENT 'FK to store.store_sk — the associate''s home store (SCD2 version current at load).',
  store_id              STRING COMMENT 'Durable home-store business key. Prefer this for SCD2-safe joins.',

  role                  STRING COMMENT 'Job role on the floor. Allowed values: sales_associate, cashier, department_specialist, stock_associate, customer_service, team_lead, store_manager, visual_merchandiser, loss_prevention.',
  skill_tags            STRING COMMENT 'Pipe-delimited capability tags used to route skill-matched tasks, e.g. "electronics|appliances|installations". Free STRING (brand-specific taxonomy); a normalized associate_skill association is a documented future option.',
  employment_type       STRING COMMENT 'Allowed values: full_time, part_time, seasonal, contractor.',
  primary_department    STRING COMMENT 'Home merchandising department the associate is normally assigned to. Free STRING (brand-specific department taxonomy).',
  is_active             BOOLEAN COMMENT 'TRUE if currently employed and rostered. NOT a live floor-availability signal — that is operational state the application owns.',
  hire_date             DATE   COMMENT 'Date the associate was hired.',

  -- SCD2 versioning (principle #8)
  effective_from_date   DATE    NOT NULL COMMENT 'SCD2: inclusive start date this version became effective.',
  effective_to_date     DATE             COMMENT 'SCD2: exclusive end date; NULL for the current version.',
  is_current            BOOLEAN NOT NULL COMMENT 'SCD2: TRUE for the currently active version.',

  -- Audit / provenance (master block; all timestamps UTC, ISO 8601)
  created_timestamp        TIMESTAMP COMMENT 'When the record was created in the source system (UTC, ISO 8601).',
  source_updated_timestamp TIMESTAMP COMMENT 'When the record was last modified in the source system (UTC, ISO 8601).',
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_associate PRIMARY KEY (associate_sk)
)
USING DELTA
CLUSTER BY (associate_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM AI-Assisted Store Associates — the store-workforce dimension (SCD2): qualified, rostered associates a Next Best Action is routed to. No raw employee PII.';

ALTER TABLE ${catalog}.${aasa_schema}.associate SET TAGS ('dbx_data_type' = 'master');
