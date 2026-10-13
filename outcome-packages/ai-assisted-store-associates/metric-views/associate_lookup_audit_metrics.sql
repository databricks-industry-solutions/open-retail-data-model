-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- Metric View: associate_lookup_audit_metrics
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-11
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-11
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${aasa_schema}.mv_associate_lookup_audit_metrics
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Associate lookup authorization and reliability metrics from the audit trail."
source: >
  SELECT
    capability,
    access_decision,
    access_reason_code,
    response_status,
    associate_role,
    store_id,
    channel,
    latency_ms
  FROM ${catalog}.${aasa_schema}.associate_lookup_audit

fields:
  - name: capability
    expr: capability
    display_name: "Capability"
    comment: "Which lookup the associate invoked (inventory, price/promotion, order status, operational context)."
    synonyms: ["lookup_type", "intent"]

  - name: access_decision
    expr: access_decision
    display_name: "Access Decision"
    comment: "Whether the policy layer allowed or denied the lookup."
    synonyms: ["auth_decision", "allow_deny"]

  - name: access_reason_code
    expr: access_reason_code
    display_name: "Reason Code"
    comment: "Policy reason accompanying the decision — why a lookup was denied or narrowed."
    synonyms: ["deny_reason", "policy_reason"]

  - name: response_status
    expr: response_status
    display_name: "Response Status"
    comment: "Outcome of the served lookup (e.g. OK, PARTIAL_RESULT), independent of the access decision."
    synonyms: ["lookup_status"]

  - name: associate_role
    expr: associate_role
    display_name: "Associate Role"
    comment: "Role of the requesting associate, for role-scoped access review."
    synonyms: ["role"]

  - name: store_id
    expr: store_id
    display_name: "Store ID"
    comment: "Durable store business key the lookup was scoped to."
    synonyms: ["location_id"]

  - name: channel
    expr: channel
    display_name: "Channel"
    comment: "Client channel the request arrived on (handheld, kiosk, desktop)."
    synonyms: ["request_channel"]

measures:
  - name: lookup_count
    expr: COUNT(*)
    display_name: "Lookup Count"
    comment: "Total audited lookups in the selection."
    synonyms: ["request_count"]

  - name: denied_count
    expr: COUNT(*) FILTER (WHERE access_decision = 'deny')
    display_name: "Denied Lookups"
    comment: "Lookups the policy layer denied — the access-review numerator."
    synonyms: ["access_denied_count"]

  - name: avg_latency_ms
    expr: AVG(latency_ms)
    display_name: "Avg Latency (ms)"
    comment: "Mean end-to-end lookup latency in milliseconds, against the real-time serving target."
    synonyms: ["mean_latency"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 1

  - name: partial_result_count
    expr: COUNT(*) FILTER (WHERE response_status = 'PARTIAL_RESULT')
    display_name: "Partial Results"
    comment: "Lookups served with a partial result, typically store-scope narrowing."
    synonyms: ["partial_count"]
$$;
