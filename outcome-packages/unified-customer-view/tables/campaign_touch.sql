-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- Table: campaign_touch
-- Layer: outcome package (gold / transactional)
-- Version: 0.5
-- Generated: 2026-07-24
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-24
-- ============================================================
-- Append-only, one row per campaign INTERACTION with a customer: an outbound
-- delivery (email/SMS/push/direct-mail send, open, click) or an inbound response
-- (reply, unsubscribe, conversion). The touch history that lets the CDP answer "which
-- campaigns reached this customer, sourced from which audience, and what happened"
-- (ADR 0026). Immutable event history; corrections are new rows.
--
-- Distinct from CMN media_event (paid ad-delivery exposures on the retail-media
-- network): campaign_touch is OWNED/CRM outreach (the messaging plane), keyed to the
-- resolved customer profile, sourced from an activation and its audience. Its lineage
-- closes the loop: campaign_touch → activation_job → activation_destination, and
-- campaign_touch → marketing.audience (source segment) → marketing.promotion (offer).
--
-- Consent is carried per touch (consent_status) as governance evidence — a touch that
-- went out is auditable against the gate that authorized its activation_job. This is
-- the analytics/audit record of a send, NOT the gate; the gate is
-- gold_activatable_audience_current.
--
-- Grain: one row per (profile_id × promo_id × channel_code × touch_ts × touch_type) — a
-- multi-channel campaign firing on email AND push at the same instant is two distinct touches.
-- Nullable
-- _sk + durable _id FK pairs to the resolved customer (customer.profile), the source
-- audience (marketing.audience), the offer/campaign (marketing.promotion), and the
-- originating run (ucv.activation_job) when the touch came from an activation.
-- ============================================================

CREATE TABLE IF NOT EXISTS ${catalog}.${ucv_schema}.campaign_touch (
  campaign_touch_sk     BIGINT GENERATED ALWAYS AS IDENTITY
                          COMMENT 'Surrogate key. Unique per touch row.',
  campaign_touch_id     STRING NOT NULL
                          COMMENT 'Durable natural/business key for the touch — one per INTERACTION EVENT, unique at row grain (send/delivery/open/click of the same message are separate touches with distinct ids). A platform message id that repeats across event types is NOT this key; carry it in external_campaign_id.',

  -- Who was touched (canonical core, resolved)
  profile_sk            BIGINT COMMENT 'FK to customer.profile.profile_sk — the touched customer (resolved).',
  profile_id            STRING COMMENT 'Durable customer business key (pseudonymous; not raw PII).',

  -- What sourced the touch (shared silver definitions) + which run produced it (gold)
  audience_sk           BIGINT COMMENT 'FK to marketing.audience.audience_sk — the segment the touch was sourced from, if audience-driven.',
  audience_id           STRING COMMENT 'Durable audience business key.',
  promo_sk              BIGINT COMMENT 'FK to marketing.promotion.promo_sk — the offer/campaign this touch delivered, if attributable.',
  promo_id              STRING COMMENT 'Durable promotion/campaign business key.',
  activation_job_sk     BIGINT COMMENT 'FK to ucv.activation_job.activation_job_sk — the activation run that produced this touch, if outbound-activated.',
  activation_job_id     STRING COMMENT 'Durable activation-job business key.',

  external_campaign_id  STRING COMMENT 'Platform-facing campaign identifier for reconciliation (degenerate attribute; vendor-neutral, no PII).',

  touch_ts              TIMESTAMP NOT NULL COMMENT 'When the touch occurred at source (UTC, ISO 8601).',
  touch_date            DATE NOT NULL COMMENT 'Business date of the touch (cluster key).',
  touch_direction       STRING NOT NULL COMMENT 'Interaction direction. Allowed values: outbound, inbound.',
  touch_type            STRING NOT NULL COMMENT 'Interaction type. Allowed values: send, delivery, open, click, bounce, unsubscribe, reply, conversion, complaint.',
  channel_code          STRING COMMENT 'Channel the touch occurred on. Allowed values: email, sms, push, direct_mail, web, in_app, call_center, in_store.',
  delivery_status_code  STRING COMMENT 'ORDM-canonical delivery state. Allowed values: queued, sent, delivered, bounced, failed, suppressed.',
  destination_delivery_status STRING COMMENT 'Raw provider-facing delivery status, canonicalized-through (vendor label; no PII).',
  consent_status        STRING COMMENT 'Consent state AS OBSERVED AT TOUCH TIME (governance evidence / point-in-time snapshot) — deliberately a 3-value snapshot domain, the SAME as the sibling fact cmn.media_event.consent_status, and NOT the same domain as the canonical-core consent master (customer.consent.consent_status = granted/withdrawn/pending/expired, an SCD2 lifecycle). This is not a join key to that master. Allowed values: granted, denied, unknown.',
  message_ref           STRING COMMENT 'Vendor-neutral reference to the message/creative variant sent (no PII, no content body).',

  -- Audit / provenance (append-only fact block; all timestamps UTC)
  record_source         STRING    COMMENT 'Originating system of record (vendor-neutral label).',
  load_timestamp        TIMESTAMP COMMENT 'When this row was loaded (UTC, ISO 8601).',

  CONSTRAINT pk_campaign_touch PRIMARY KEY (campaign_touch_sk)
)
USING DELTA
-- Cluster by customer then touch date: the common read is "this customer's touch history".
CLUSTER BY (profile_id, touch_date)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'ORDM Unified Customer View — owned/CRM campaign interaction fact (append-only). Outbound sends and inbound responses per customer, sourced from an activation; distinct from paid CMN media_event.';

-- Table classification (machine-checkable layer/role): TAGS-DATA-TYPE
ALTER TABLE ${catalog}.${ucv_schema}.campaign_touch SET TAGS ('dbx_data_type' = 'transactional');
