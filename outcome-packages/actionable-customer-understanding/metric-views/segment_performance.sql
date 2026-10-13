-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- Metric View: segment_performance
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-07-23
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-27
-- ============================================================
-- Semantic layer over behavioral-segment membership + the activation gate: per-segment
-- SIZE and ACTIVATABLE REACH. member_count is total current membership; reachable_member
-- _count is the subset that clears the consent+preference+reachability gate (from UCV's
-- gold_activatable_audience_current). activatable_penetration is a RATIO-OF-SUMS
-- (reachable / total), never an average of per-row ratios. For segment ops / audience
-- sizing via Genie and AI/BI. No person-level PII (pseudonymous profile_id only).
--
-- The source pre-aggregates to one row per (segment × profile) so member and reachable
-- counts are COUNT(DISTINCT profile_id); a profile counts once per segment even though
-- the gate view has a row per purpose×channel.
--
-- CROSS-PACKAGE DEPENDENCY (deploy ordering, m1): this ACU metric view reads UCV's
-- gold_activatable_audience_current (a legitimate gold→gold read; UCV owns the activation
-- gate). Deploy the unified-customer-view package BEFORE this metric view, or it will not
-- resolve. Also reads the shared silver marketing.audience.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${acu_schema}.mv_segment_performance
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Per behavioral-segment size and activatable reach: total members, gate-eligible members, and activatable penetration."
source: |
  WITH latest AS (
    -- NOTE (m1): same latest-minus-exited logic at four other sites — UCV's
    -- gold_activatable_audience_current `latest_membership`, ACU sample-queries.sql
    -- (#3 and #6), and UCV sample-queries.sql #11. Keep all in sync; if the
    -- membership-currency rule changes, update every site (no shared-SQL include).
    SELECT m.audience_id, m.profile_id
    FROM ${catalog}.${acu_schema}.segment_membership m
    JOIN (
      SELECT audience_id, MAX(as_of_date) AS max_as_of
      FROM ${catalog}.${acu_schema}.segment_membership
      GROUP BY audience_id
    ) mx ON m.audience_id = mx.audience_id AND m.as_of_date = mx.max_as_of
    WHERE m.membership_status IS NULL OR m.membership_status <> 'exited'
  ),
  reachable AS (
    -- Owned-channel reachability ONLY (H1). The multi-purpose gate (ADR 0028) now emits
    -- channel-agnostic rows (personalization / analytics / retail_media; channel_code NULL)
    -- where has_identifier_flag is vacuously TRUE, so a profile with NO owned contactability
    -- can carry an eligible gate row. "Reachable Members" / "Activatable Penetration" mean
    -- OWNED-channel addressability, so restrict to rows carrying an owned channel
    -- (channel_code IS NOT NULL == purpose_code = 'marketing', per
    -- ucv_eligibility_purpose_channel_pairing). Without this the metric would silently count
    -- analytics-only consenters as reachable and inflate penetration.
    SELECT DISTINCT audience_id, profile_id
    FROM ${catalog}.${ucv_schema}.gold_activatable_audience_current
    WHERE channel_code IS NOT NULL
  )
  SELECT
    l.audience_id,
    a.audience_name,
    a.segmentation_basis,
    l.profile_id,
    CASE WHEN r.profile_id IS NOT NULL THEN 1 ELSE 0 END AS is_reachable
  FROM latest l
  -- INNER JOIN the definition dim (M1): a membership row whose audience_id has no current
  -- definition must not count toward member_count under a NULL name — matches the strictness
  -- of segment_membership_audience_fk_orphan and of gold_activatable_audience_current's join.
  JOIN ${catalog}.${marketing_schema}.audience a
    ON a.audience_id = l.audience_id AND a.is_current = TRUE
  LEFT JOIN reachable r
    ON r.audience_id = l.audience_id AND r.profile_id = l.profile_id

fields:
  - name: audience_id
    expr: audience_id
    display_name: "Segment ID"
    comment: "Durable segment/audience business key."
    synonyms: ["segment_id", "audience"]
  - name: audience_name
    expr: audience_name
    display_name: "Segment Name"
    comment: "Human-readable segment name."
    synonyms: ["segment_name"]
  - name: segmentation_basis
    expr: segmentation_basis
    display_name: "Segmentation Basis"
    comment: "The axis the segment is built on (behavioral, value_rfm, lifecycle, predictive, ...)."
    synonyms: ["segment_type", "basis"]

measures:
  - name: member_count
    expr: COUNT(DISTINCT profile_id)
    display_name: "Members"
    comment: "Distinct customers currently in the segment (latest as-of snapshot)."
    synonyms: ["segment_size", "audience_size"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: reachable_member_count
    expr: COUNT(DISTINCT CASE WHEN is_reachable = 1 THEN profile_id END)
    display_name: "Reachable Members"
    comment: "Distinct members who clear the consent+preference+reachability activation gate on an OWNED channel (email/sms/phone/postal). Channel-agnostic analytics/personalization consent alone does not make a member reachable."
    synonyms: ["activatable_members", "addressable_members"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0
  - name: activatable_penetration
    expr: COUNT(DISTINCT CASE WHEN is_reachable = 1 THEN profile_id END) / nullif(COUNT(DISTINCT profile_id), 0)
    display_name: "Activatable Penetration"
    comment: "Share of segment members that are activatable (ratio-of-sums: reachable / total, not an avg of per-row ratios). A non-addressable (analytics-only) segment has no reachable members, so this reads 0 by design, not a data gap."
    synonyms: ["reach_rate", "addressable_rate"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 4
$$;
