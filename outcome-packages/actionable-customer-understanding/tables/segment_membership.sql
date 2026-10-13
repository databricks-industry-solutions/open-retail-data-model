-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- Table: segment_membership
-- Layer: outcome package (gold / association)
-- Version: 0.5
-- Generated: 2026-07-21
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-21
-- ============================================================
-- The evaluated behavioral-segment MEMBERSHIP: which customers belong to which
-- segment, as of an evaluation date. The narrow (customer × segment) surface that
-- complements the wide trait surface (gold_customer_behavioral_attributes) — one is
-- for composing/lookalikes, this one for direct list sync.
--
-- Grain: one row per (profile_id × audience_id × as_of_date). APPEND-ONLY as-of
-- snapshots (ADR 0022 direction; user decision): each refresh appends the current
-- membership dated by as_of_date, so a campaign can freeze on a date and segment
-- size/migration is reproducible. NOT SCD2 — no version-close; the as_of_date IS the
-- temporal key. Consumers read the latest as_of_date (or a pinned one).
--
-- References the shared silver marketing.audience DEFINITION by durable audience_id
-- (segment definitions live once in the conformed core, ADR 0022). Keyed on the durable
-- pseudonymous profile_id; no raw PII. This is the TARGETING plane only — it carries NO
-- consent/preference flags; the net gate is applied in UCV's
-- gold_activatable_audience_current, never here (three planes stay separate).
--
-- ACTIVATION CONTRACT (ADR 0028): this table is a targeting surface, NOT an activation-safe
-- list. Any consumer that reverse-ETLs / syncs segment_membership DIRECTLY to a destination
-- (a paid / non-owned plane that does not resolve people through the owned gate) MUST apply
-- TWO suppressions -- anti-joining the do-not-target view ALONE is not sufficient for a
-- selling/sharing plane:
--   (a) PERSON-level do-not-target: anti-join UCV gold_person_do_not_target_current on
--       profile_id, so a deceased/fraud/do_not_contact/legal_objection customer (GDPR Art.21)
--       is never activated on ANY plane.
--   (b) PURPOSE-level do-not-sell / do-not-share (CCPA/CPRA): a selling/sharing plane must also
--       drop anyone with a current data_sale (do-not-sell) or third_party_sharing (do-not-share)
--       consent that is withdrawn or suppression-flagged. The do-not-target view does NOT cover
--       this -- it is scoped to the four person-level reasons and ignores consent.
-- OWNED-plane consumers get both legs for free by reading gold_activatable_audience_current
-- (already gated + DNT-guarded) instead of this table -- correct because an owned plane is
-- opt-IN. A PAID / selling-sharing plane governed by CCPA opt-out must NOT substitute that gate:
-- the gate is fail-closed (never-decided profile = not eligible), the opt-out leg treats a
-- never-decided profile as permitted, so they return opposite populations. A paid plane must
-- apply leg (b) directly; see UCV sample-queries.sql #11 for the worked two-leg shape.
--
-- KEYS ARE DURABLE `_id`, NOT SURROGATE `_sk` — DELIBERATE (do not "fix" to add _sk FKs).
-- profile_id / audience_id are the STABLE activation keys a warehouse-native / composable
-- CDP and reverse-ETL CDC diff on; a versioned SCD2 `_sk` would churn on every parent
-- version and break the sync contract, and this membership is not a fixed-grain fact that
-- an as-of `_sk` resolution would help. So the parent relationships are LOGICAL
-- (durable-key, NOT declared UC surrogate FKs) and integrity is enforced by the
-- segment_membership_{profile,audience}_fk_orphan DQ checks (checks.sql) rather than
-- by a `_sk` FK. This is the conscious trade-off vs sibling gold tables (e.g. CMN
-- ad_group.audience_sk) that key on `_sk` for Catalog-ERD discoverability; here
-- reverse-ETL portability wins. (Reviewer H1 — recorded here so it isn't re-raised.)
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${acu_schema}.segment_membership (
  segment_membership_sk BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per (profile, segment, as_of) row.',
  segment_membership_id STRING NOT NULL
                          COMMENT 'Durable natural/business key for the membership row (profile_id + audience_id + as_of_date).',

  profile_id            STRING NOT NULL
                          COMMENT 'Durable customer business key (pseudonymous; not raw PII). Joins customer.profile / gold_customer_behavioral_attributes and is the single stable activation/join key.',
  audience_id           STRING NOT NULL
                          COMMENT 'Durable key of the segment DEFINITION this membership is for. FK to marketing.audience.audience_id (the shared conformed definition, ADR 0022).',

  as_of_date            DATE NOT NULL
                          COMMENT 'Evaluation date of this membership snapshot (the temporal key; append-only, never version-closed).',
  membership_status     STRING COMMENT 'Membership state at as_of. Allowed values: realized, existing, exited. Standard segment-membership lifecycle semantics: realized = newly qualified this evaluation, existing = still qualifies, exited = no longer qualifies. v1 is current-state append-only: the generator emits mostly `existing` plus a deterministic ~5% `exited` slice (so the exclusion path is exercised on seed data); `realized` is RESERVED for a future entered/exited delta feed.',
  membership_score      DECIMAL(8,4) COMMENT 'Optional confidence/propensity score behind the membership (0..1); NULL for a pure deterministic rule match.',
  assignment_method     STRING COMMENT 'How membership was assigned. Allowed values: rule, ml_score, imported.',
  model_version         STRING COMMENT 'Version of the rule set / model that produced this membership (audit / reproducibility). NULL if not applicable.',

  -- Audit / provenance: append-only event-log block per section 8 -- record_source
  -- plus load_timestamp only. created_/source_updated_timestamp are the master and
  -- reference tier; here as_of_date is the row event instant, so they are omitted.
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_segment_membership PRIMARY KEY (segment_membership_sk)
)
USING DELTA
-- Cluster by segment then as_of: the common read is "current members of segment X".
CLUSTER BY (audience_id, as_of_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Actionable Customer Understanding behavioral-segment membership (append-only as-of snapshots). Targeting plane only; gated for activation in UCV.';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${acu_schema}.segment_membership SET TAGS ('dbx_data_type' = 'association');
