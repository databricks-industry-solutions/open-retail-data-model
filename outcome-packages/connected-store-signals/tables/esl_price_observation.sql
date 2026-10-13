-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Table: esl_price_observation
-- Layer: outcome package (gold / append-only audit fact)
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- License: see repository LICENSE.md
-- ============================================================
-- What a shelf label ACTUALLY DISPLAYED, when, and how we know. Append-only audit
-- evidence: corrections are new observations, never restatements. Three independent
-- observation paths (platform ack, shelf CV, manual audit) land in one fact —
-- disagreement between them is the point, not a defect.
--
-- ADR 0030 / ADR 0041: this fact OBSERVES pricing outputs; nothing in CSS feeds
-- price-setting. It is a permitted READER of product.product_price (price of record is
-- captured onto the row at observation time so the audit evidence stands alone) and
-- must never be an ancestor of any price-producing surface
-- (css_no_sensing_to_pricing_lineage, error severity).
--
-- ADR 0030 carried thin (ADR 0041 amendment): sensing_derived_input_flag is present with
-- a Delta CHECK that it is FALSE — the invariant stays schema-visible exactly as
-- 0030 §Decision.2 demands. Displayed disclosure (indicator + text) is observed
-- display state: NY GBL §349-a compelled the wording, Connecticut's 2026 law mandates
-- it. The remaining 0030 §Decision.3 columns (algorithmic_pricing_flag,
-- personal_data_used_flag, discount_basis_code) are pricing-platform DECLARATIONS,
-- not observations, and are deliberately deferred to the pricing side (ADR 0041).
--
-- ADR 0028 (hash surrogate keys) named this table esl_price_event; _observation is the ADR 0041 boundary made
-- visible: an observation of display state, not a pricing event.
--
-- KEY (ADR 0028): xxhash64(esl_price_observation_id), durable id authoritative,
-- eslp_sk_collision at error severity.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${css_schema}.esl_price_observation (
  esl_price_observation_sk BIGINT NOT NULL
                       COMMENT 'Surrogate join key: xxhash64(esl_price_observation_id). The durable id is authoritative and collision-guarded.',
  esl_price_observation_id STRING NOT NULL
                       COMMENT 'Durable grain key: esl_label_id|observation_source|source_observation_id. Source-event identity, not timestamp-to-the-second: a re-delivered source event deduplicates instead of duplicating, and ack/CV/audit observing the same label in the same second cannot collide.',
  source_observation_id STRING NOT NULL
                       COMMENT 'Source-system event identity: platform ack/event id, CV frame/inference id, or audit record id. Part of the durable grain key.',

  esl_label_sk        BIGINT NOT NULL COMMENT 'FK to the label endpoint version in effect at observation time.',
  esl_label_id        STRING NOT NULL COMMENT 'Durable label endpoint identifier.',
  esl_label_assignment_sk BIGINT COMMENT 'FK to the binding version current at observation time. NULL when the label was observed unbound.',
  esl_label_assignment_id STRING COMMENT 'Durable binding key captured at observation time (SCD2-safe attribution, ADR 0025). NULL when observed unbound.',
  product_sk          BIGINT COMMENT 'Product version resolved through the binding at write. NULL when observed unbound.',
  product_id          STRING COMMENT 'Durable product business key via the binding. NULL when observed unbound.',
  store_sk            BIGINT NOT NULL COMMENT 'FK to the store version in effect at observation time.',
  store_id            STRING NOT NULL COMMENT 'Durable store business key.',
  store_zone_sk       BIGINT COMMENT 'FK to the shelf-position zone version of the label placement at observation time.',
  store_zone_id       STRING COMMENT 'Durable shelf-position zone id via the binding. NULL when observed unbound.',

  observed_at_ts      TIMESTAMP NOT NULL COMMENT 'Observation instant as UTC: ack receipt, CV capture, or audit scan time.',
  store_timezone      STRING COMMENT 'IANA store timezone used to derive local business fields.',
  utc_offset_minutes  SMALLINT NOT NULL COMMENT 'Store UTC offset in minutes at observed_at_ts.',
  trading_date        DATE NOT NULL COMMENT 'Business date of observed_at_ts, persisted on the ledger itself so no join loss can strip store-local date context. Logical join to fiscal_calendar.date_key.',
  hour_of_day         TINYINT COMMENT 'Store-local observation hour, 0 through 23.',

  observation_source  STRING NOT NULL COMMENT 'How the displayed state became known: platform_ack, shelf_cv, manual_audit. The three paths are independent evidence; disagreement between them is signal.',

  displayed_price     DECIMAL(18,4) COMMENT 'Unit-grain price shown on the label at observation, in the store reporting currency. NULL only when the source could observe the label but not read a price (e.g. occluded CV).',
  displayed_currency_code STRING COMMENT 'ISO 4217 currency of the displayed price; must match the store reporting currency (single-currency check).',
  displayed_unit_price DECIMAL(18,4) COMMENT 'Unit price shown (per uom), where the label displays one. NIST HB44 random-weight awareness: unit-priced items are priced from scale PLU memory, not the POS database.',
  unit_price_uom      STRING COMMENT 'UN/CEFACT unit code for the displayed unit price (e.g. KGM, LBR).',
  displayed_promo_indicator BOOLEAN COMMENT 'TRUE when the label showed a promotional presentation AS DISPLAYED. Records the display, not the promotion validity.',
  displayed_disclosure_indicator BOOLEAN COMMENT 'TRUE when the label showed a pricing-disclosure notice AS DISPLAYED (NY GBL §349-a wording; CT 2026 mandated label text). Observed display state, not a compliance conclusion.',
  displayed_disclosure_text STRING COMMENT 'The disclosure wording as displayed, where the source captures text. Nullable; an indicator plus Bronze evidence may stand in.',

  price_of_record     DECIMAL(18,4) COMMENT 'The STORE-SCOPED unit-grain authoritative price in effect at observation time, captured onto the row (degenerate copy — audit evidence must stand alone). Core product_price is product × price_type × DATE with no store/channel scope, so it is a legal source only where the adopter prices chain-wide by day; store/zone-priced or intraday-priced estates capture from their pricing platform of record. This fact READS pricing; it never feeds it (ADR 0030).',
  price_of_record_currency_code STRING COMMENT 'ISO 4217 currency of the captured price of record. MUST equal displayed_currency_code and the store reporting currency: price_of_record_source may name a non-store-reporting authority (pricing_platform, pos_system) whose price arrives in another currency, so without this column is_price_match and the over/undercharge magnitudes would silently compare across currencies. Enforced row-wise by eslp_price_of_record_currency and folded into the single-reporting-currency contract (eslp_single_currency).',
  price_of_record_source STRING COMMENT 'Which authority the captured price of record came from: pricing_platform, product_price, pos_system, scale_plu, manual. NIST HB44: random-weight items price from scale PLU memory, not the POS database — "the price" has no single origin (ADR 0030 consequence), so the source is part of the evidence.',
  price_of_record_price_type STRING COMMENT 'Price type of the captured record where the source distinguishes one (e.g. list, promotional). Vocabulary follows the source system; core product_price uses list/cost/promotional/contract.',
  price_of_record_effective_ts TIMESTAMP COMMENT 'UTC instant the captured price of record became effective IN THE SOURCE AUTHORITY. Date-grained sources (core product_price) yield a midnight instant; intraday-capable platforms yield the real one — display_sync_latency_seconds is only as good as this timestamp.',
  is_price_match      BOOLEAN COMMENT 'TRUE when displayed_price equals the captured price of record. NULL when either side is unobserved. Comparison is same-currency by contract: price_of_record_currency_code = displayed_currency_code (eslp_price_of_record_currency).',
  display_sync_latency_seconds BIGINT COMMENT 'Seconds from price-of-record effectiveness to this ack observation. platform_ack rows only; NULL otherwise.',

  sensing_derived_input_flag BOOLEAN NOT NULL COMMENT 'ADR 0030 §Decision.2 invariant, schema-visible: always FALSE (Delta CHECK). No displayed price may claim a sensing-derived input; any attempt to violate is an explicit, reviewable act.',

  raw_data_uri        STRING COMMENT 'Pointer to source evidence in Bronze (ack payload, CV crop, audit record), outside ORDM.',
  ingest_timestamp    TIMESTAMP COMMENT 'When the observation arrived in the lakehouse (UTC).',
  record_source       STRING COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp      TIMESTAMP COMMENT 'When this row was loaded (UTC).',

  CONSTRAINT pk_esl_price_observation PRIMARY KEY (esl_price_observation_sk)
)
USING DELTA
CLUSTER BY (trading_date, store_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'Connected Store Signals append-only price-display audit fact: what each ESL displayed, when, by which evidence path, against the captured price of record. Observation-only ESL layer (ADR 0041, extending ADR 0030).';

ALTER TABLE ${catalog}.${css_schema}.esl_price_observation SET TAGS ('dbx_data_type' = 'transactional');
