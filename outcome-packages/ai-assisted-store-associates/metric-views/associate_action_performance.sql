-- ============================================================
-- ORDM · Outcome Package · AI-Assisted Store Associates
-- Metric View: associate_action_performance
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-29
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-29
-- ============================================================
-- Next Best Action effectiveness — acceptance, completion, responsiveness and
-- realized value — one governed semantic surface for Genie / AI-BI.
--
-- SOURCED FROM THE GOLD DAILY FUNNEL, not the raw facts: the gold view has already
-- resolved the funnel on durable ids + trading date, so every dimension here is a
-- durable key (store_id, store_zone_id, associate_id, trading_date, action_type) and
-- never a version-specific SCD2 `_sk` (§A.16 — a metric view must not expose a bare SCD2
-- surrogate as a dimension; associate_id is the durable business key, not associate_sk).
-- Carrying associate_id and store_zone_id lets the view answer the per-associate
-- effectiveness and per-zone staffing questions its name and use cases promise. Rates are
-- RATIO-OF-SUMS (SUM(numerator)/SUM(denominator)) so they re-aggregate at any grain; a
-- pre-computed per-row rate could not.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${aasa_schema}.mv_associate_action_performance
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Next Best Action effectiveness at store x zone x associate x trading date x action_type: how many actions were generated, their acceptance and completion rates, average time-to-first-response, and realized monetary outcome. Break down by associate for individual effectiveness or by zone for the staffing signal. Rates are ratio-of-sums and re-aggregate at any grain."
source: >
  SELECT *
  FROM ${catalog}.${aasa_schema}.gold_action_outcome_funnel_daily

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "location", "site", "branch"]

  - name: trading_date
    expr: trading_date
    display_name: "Trading Date"
    comment: "Business date the action was generated."
    synonyms: ["date", "business_date", "day"]

  - name: action_type
    expr: action_type
    display_name: "Action Type"
    comment: "The Next Best Action task class: customer_assist, restock_shelf, bopis_fulfill, safety_loss_prevention, maintenance_cleaning, price_check, queue_bust, clienteling."
    synonyms: ["task_type", "action", "task_class"]

  - name: associate_id
    expr: associate_id
    display_name: "Associate"
    comment: "Durable associate business key (not the version-specific surrogate). NULL for actions generated but never routed. Break down here for per-associate effectiveness."
    synonyms: ["associate", "worker", "team_member", "employee"]

  - name: store_zone_id
    expr: store_zone_id
    display_name: "Zone"
    comment: "Durable target-zone id. Break down here for the staffing signal — rejections concentrated in one zone. NULL when the action had no target zone."
    synonyms: ["zone", "area", "department", "location_zone"]

measures:
  - name: actions_generated
    expr: SUM(actions_generated)
    display_name: "Actions Generated"
    comment: "Count of Next Best Actions dispatched. Additive over time, store and action type."
    synonyms: ["tasks", "prompts", "actions", "suggestions"]

  - name: actions_accepted
    expr: SUM(actions_accepted)
    display_name: "Actions Accepted"
    comment: "Actions the associate accepted."
    synonyms: ["accepted", "taken"]

  - name: actions_completed
    expr: SUM(actions_completed)
    display_name: "Actions Completed"
    comment: "Actions that reached completed status."
    synonyms: ["completed", "done", "fulfilled"]

  - name: acceptance_rate
    expr: SUM(actions_accepted) / NULLIF(SUM(actions_generated), 0)
    display_name: "Acceptance Rate"
    comment: "Share of generated actions the associate accepted. Ratio-of-sums."
    synonyms: ["accept_rate", "take_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: completion_rate
    expr: SUM(actions_completed) / NULLIF(SUM(actions_generated), 0)
    display_name: "Completion Rate"
    comment: "Share of generated actions completed. Ratio-of-sums."
    synonyms: ["complete_rate", "fulfilment_rate"]
    format:
      type: percentage
      decimal_places:
        type: exact
        places: 1

  - name: avg_response_seconds
    expr: SUM(response_seconds_total) / NULLIF(SUM(responses_timed), 0)
    display_name: "Average Response (Seconds)"
    comment: "Mean time from action dispatch to first associate response, computed from the stored total and count so it re-aggregates correctly at any grain."
    synonyms: ["response_time", "time_to_respond", "latency"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 0

  - name: realized_outcome_value
    expr: SUM(realized_outcome_value)
    display_name: "Realized Outcome Value"
    comment: "Sum of monetary outcomes attributed to actions (e.g. closed-sale value). Single reporting currency (see outcome_currency_code on the gold view)."
    synonyms: ["outcome_value", "attributed_revenue", "roi_value"]
    format:
      type: number
      decimal_places:
        type: exact
        places: 2

  - name: sales_closed
    expr: SUM(sales_closed)
    display_name: "Sales Closed"
    comment: "Count of actions resolved as a closed sale."
    synonyms: ["closed_sales", "conversions"]
$$;
