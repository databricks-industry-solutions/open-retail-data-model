-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: price_accuracy
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- ============================================================
-- Reads gold, never the fact (§13). Match ratios recompute from summed label counts
-- over the gold's unique store × date × currency grain. Overcharge and undercharge are never
-- netted (regulators treat them asymmetrically); mismatch magnitudes are absolute
-- values, never signed averages (IoT-review M2 lesson). Currency-bearing measures return
-- NULL when a grouping spans currencies; exposing currency as a field is not treated as
-- an enforceable guard because metric-view callers may omit it. Latency percentiles cannot be
-- re-derived from percentiles: the p50/p95 measures report the WORST grouped
-- store-day, stated in their comments so Genie inherits the caveat.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_price_accuracy
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "ESL price-display accuracy from the observation audit trail: end-of-day match rate, overcharge/undercharge split, mismatch magnitudes, correction times, and ack sync latency."
source: ${catalog}.${css_schema}.gold_price_accuracy_current

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "site", "location"]

  - name: trading_date
    expr: trading_date
    display_name: "Trading Date"
    comment: "Business date of the price-display observations."
    synonyms: ["date", "day", "business_date"]

  - name: currency_code
    expr: currency_code
    display_name: "Currency"
    comment: "ISO 4217 currency of the label's last daily price observation."
    synonyms: ["currency", "iso_currency", "reporting_currency"]

measures:
  - name: labels_observed
    expr: SUM(labels_observed)
    display_name: "Labels Observed"
    comment: "Label-days with at least one price observation from any evidence path (ack, shelf CV, manual audit)."
    synonyms: ["esl_labels_seen", "labels_checked"]

  - name: labels_evaluable
    expr: SUM(labels_evaluable)
    display_name: "Labels Evaluable"
    comment: "Observed label-days whose last observation carried an evaluable displayed-versus-record comparison."
    synonyms: ["labels_compared", "price_checks_evaluable"]

  - name: price_match_rate
    expr: SUM(labels_matched_eod) / NULLIF(SUM(labels_evaluable), 0)
    display_name: "Price Match Rate"
    comment: "Labels whose day's LAST observation matched the captured price of record, over labels where the comparison was evaluable. The HB130-style price accuracy figure."
    synonyms: ["price_accuracy", "match_rate", "display_accuracy"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: labels_mismatched
    expr: SUM(labels_mismatched_eod)
    display_name: "Labels Mismatched (EOD)"
    comment: "Labels ending the day displaying a price different from the captured price of record."
    synonyms: ["mismatched_labels", "wrong_price_labels"]

  - name: labels_overcharging
    expr: SUM(labels_overcharging_eod)
    display_name: "Labels Overcharging"
    comment: "End-of-day mismatches where the displayed price EXCEEDS the price of record. Never netted against undercharges - regulators treat the directions asymmetrically."
    synonyms: ["overcharges", "price_too_high"]

  - name: labels_undercharging
    expr: SUM(labels_undercharging_eod)
    display_name: "Labels Undercharging"
    comment: "End-of-day mismatches where the displayed price is BELOW the price of record."
    synonyms: ["undercharges", "price_too_low"]

  - name: max_mismatch_amount
    expr: CASE WHEN COUNT(DISTINCT currency_code) = 1 THEN MAX(max_mismatch_abs_amount) END
    display_name: "Largest Mismatch Amount"
    comment: "Largest absolute displayed-vs-record gap at end of day. Returns NULL when the grouping spans currencies; group by Currency for monetary analysis."
    synonyms: ["worst_mismatch", "biggest_price_error"]

  - name: avg_correction_hours
    expr: SUM(correction_hours_total) / NULLIF(SUM(labels_corrected), 0)
    display_name: "Average Correction Hours"
    comment: "Label-weighted mean correction time: first mismatch to first subsequent match on the same day."
    synonyms: ["time_to_correct", "mismatch_fix_time"]

  - name: max_open_mismatch_hours
    expr: MAX(max_open_mismatch_hours)
    display_name: "Longest Open Mismatch (Hours)"
    comment: "Longest still-uncorrected mismatch age across the grouping, aged to the day's last evidence, not to the reader's wall clock."
    synonyms: ["oldest_mismatch", "mismatch_aging"]

  - name: sync_latency_p95_seconds
    expr: MAX(sync_latency_p95_seconds)
    display_name: "Sync Latency p95 (Seconds)"
    comment: "WORST grouped store-day p95 of price-of-record-effective to label ack. Percentiles cannot be re-aggregated, so grouping reports the worst constituent, not a recomputed percentile. Latency evidence is only as granular as the captured price authority's effective timestamp."
    synonyms: ["ack_latency_p95", "price_update_latency"]

  - name: ack_observation_count
    expr: SUM(ack_observations)
    display_name: "Ack Observations"
    comment: "Platform-acknowledged display confirmations - the only evidence path that measures sync latency."
    synonyms: ["acks", "platform_acks"]

  - name: audit_observation_count
    expr: SUM(audit_observations)
    display_name: "Manual Audit Observations"
    comment: "Human price checks. Disagreement between evidence paths is signal, not noise."
    synonyms: ["manual_checks", "price_audits"]
$$;
