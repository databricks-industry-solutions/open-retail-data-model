-- ============================================================
-- ORDM · Outcome Package · Unified Customer View
-- Metric View: cdp_activation_jobs
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-10-12
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-10-12
-- ============================================================
-- The CDP activation KPIs of the UCV glossary as a UC Metric View over the
-- activation_job audit table (ADR 0026), one row per audience x destination x
-- jurisdiction x run. Answers "of the members we asked to publish, how many passed
-- the gate, how many reached the destination, and how well did they match".
--
-- All three rates are ratio-of-sums over member counts, never averages of per-job
-- rates. activation_block_rate is ALL-CAUSE (consent, preference, reachability or
-- suppression), not suppression-specific. activation_match_rate is member-weighted
-- and counts only exports with a known match_rate in its denominator.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${ucv_schema}.mv_cdp_activation_jobs
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "CDP activation KPIs over audience-to-destination publish runs: requested, eligible, blocked and exported members, export rate, all-cause block rate and member-weighted match rate."
source: >
  SELECT
    job.activation_destination_id,
    job.audience_id,
    job.purpose_code,
    job.channel_code,
    job.jurisdiction_code,
    job.job_status,
    job.job_run_date,
    job.requested_member_count,
    job.eligible_member_count,
    job.blocked_member_count,
    job.exported_member_count,
    job.match_rate
  FROM ${catalog}.${ucv_schema}.activation_job job

fields:
  - name: activation_destination_id
    expr: activation_destination_id
    display_name: "Destination"
    comment: "Activation destination the audience was published to."
    synonyms: ["destination", "endpoint"]
  - name: audience_id
    expr: audience_id
    display_name: "Audience"
    comment: "Audience that was published."
    synonyms: ["segment", "audience"]
  - name: purpose_code
    expr: purpose_code
    display_name: "Activation Purpose"
    comment: "Consent purpose the publish run was gated on."
    synonyms: ["purpose"]
  - name: channel_code
    expr: channel_code
    display_name: "Channel"
    comment: "Contact channel of the publish run."
    synonyms: ["channel", "medium"]
  - name: jurisdiction_code
    expr: jurisdiction_code
    display_name: "Jurisdiction"
    comment: "ISO 3166 jurisdiction the run was scoped to; NULL when the adopter reports regime-agnostic runs."
    synonyms: ["jurisdiction", "privacy_region"]
  - name: job_status
    expr: job_status
    display_name: "Job Status"
    comment: "Outcome status of the publish run."
    synonyms: ["status", "run_status"]
  - name: job_run_date
    expr: job_run_date
    display_name: "Run Date"
    comment: "Date of the publish run."
    synonyms: ["date", "run_date"]

measures:
  - name: activation_run_count
    expr: COUNT(*)
    display_name: "Publish Runs"
    comment: "Count of audience-to-destination publish runs."
    synonyms: ["job_count", "runs"]
  - name: requested_members
    expr: SUM(requested_member_count)
    display_name: "Requested Members"
    comment: "Members requested for activation, before the eligibility gate."
    synonyms: ["requested"]
  - name: eligible_members
    expr: SUM(eligible_member_count)
    display_name: "Eligible Members"
    comment: "Members that passed the net eligibility gate."
    synonyms: ["eligible"]
  - name: blocked_members
    expr: SUM(blocked_member_count)
    display_name: "Blocked Members"
    comment: "Members the gate removed for any reason (requested minus eligible)."
    synonyms: ["blocked"]
  - name: exported_members
    expr: SUM(exported_member_count)
    display_name: "Exported Members"
    comment: "Members synced to the destination."
    synonyms: ["exported", "synced_members"]
  - name: activation_export_rate
    expr: SUM(exported_member_count) / NULLIF(SUM(eligible_member_count), 0)
    display_name: "Activation Export Rate"
    comment: "Share of gate-eligible members actually exported, ratio-of-sums (glossary activation_export_rate)."
    synonyms: ["export_rate", "activation_efficiency"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: activation_block_rate
    expr: SUM(blocked_member_count) / NULLIF(SUM(requested_member_count), 0)
    display_name: "Activation Block Rate"
    comment: "Share of requested members the eligibility gate removed for ANY reason (consent, preference, reachability or suppression); an all-cause block rate, not suppression-specific (glossary activation_block_rate)."
    synonyms: ["block_rate", "gate_block_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
  - name: activation_match_rate
    expr: SUM(exported_member_count * match_rate) / NULLIF(SUM(CASE WHEN match_rate IS NOT NULL THEN exported_member_count END), 0)
    display_name: "Activation Match Rate"
    comment: "Member-weighted provider match rate across exports; the denominator counts only exports with a known match_rate (glossary activation_match_rate)."
    synonyms: ["match_rate", "provider_match_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1
$$;
