-- ============================================================
-- ORDM · Outcome Package · Connected Store Signals
-- Metric View: planogram_compliance
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-20
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-20
-- ============================================================
-- Reads gold, never the fact (§13). Ratios recompute from summed evaluable/compliant
-- counts over the gold's unique store × date × product grain (fan-out-proof, M1
-- lesson). Per-dimension denominators are EVALUABLE positions - a dimension the
-- platform could not judge is neither compliant nor violating. Expected, observed,
-- known, unknown, and unobserved positions stay separate so missing sensing cannot
-- masquerade as compliant execution.
-- Share-of-shelf is served by gold_share_of_shelf_current directly (different grain
-- and additivity boundary - shares are additive only within store × category at one
-- instant, which a time-dimensioned metric view would invite users to violate).
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${css_schema}.mv_planogram_compliance
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Planogram execution compliance from shelf sensing, split across the four dimensions: right product present, right position, right facing count, right price tag - plus the overall rate and BMV allocation divergence."
source: ${catalog}.${css_schema}.gold_planogram_compliance_current

fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ["store", "site", "location"]

  - name: trading_date
    expr: trading_date
    display_name: "Trading Date"
    comment: "Business date of the shelf observations."
    synonyms: ["date", "day", "business_date"]

  - name: product_id
    expr: product_id
    display_name: "Product"
    comment: "Durable product business key."
    synonyms: ["product", "sku", "item"]

measures:
  - name: products_measured
    expr: COUNT(DISTINCT CASE WHEN positions_observed > 0 THEN product_id END)
    display_name: "Products Measured"
    comment: "Distinct products with at least one observed position that day. Counted on the durable id so no grouping fans it out."
    synonyms: ["skus_measured", "products_observed"]

  - name: positions_expected
    expr: SUM(positions_expected)
    display_name: "Positions Expected"
    comment: "Assigned position-days in the compliance denominator universe."
    synonyms: ["assigned_positions", "planned_positions"]

  - name: positions_observed
    expr: SUM(positions_observed)
    display_name: "Positions Observed"
    comment: "Position-days observed across the grouping."
    synonyms: ["slots_observed"]

  - name: positions_unobserved
    expr: SUM(positions_unobserved)
    display_name: "Unobserved Positions"
    comment: "Expected position-days with no capture. They are coverage gaps, never compliant or violating."
    synonyms: ["uncovered_positions", "coverage_gaps"]

  - name: positions_known
    expr: SUM(positions_known)
    display_name: "Known-State Positions"
    comment: "Observed position-days whose last capture was usable."
    synonyms: ["evaluable_positions", "usable_positions"]

  - name: overall_compliance_pct
    expr: SUM(fully_compliant_positions) / NULLIF(SUM(fully_evaluable_positions), 0)
    display_name: "Overall Compliance %"
    comment: "Positions compliant on ALL FOUR dimensions, over positions where all four were evaluable."
    synonyms: ["planogram_compliance", "compliance_rate", "execution_compliance"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: presence_compliance_pct
    expr: SUM(presence_compliant) / NULLIF(SUM(presence_evaluable), 0)
    display_name: "Presence Compliance %"
    comment: "Right product present (in stock or low stock) at its assigned position."
    synonyms: ["product_presence_rate", "right_product_rate"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: position_compliance_pct
    expr: SUM(position_compliant) / NULLIF(SUM(position_evaluable), 0)
    display_name: "Position Compliance %"
    comment: "No misplaced product detected at the position (the right-position dimension)."
    synonyms: ["placement_compliance", "right_position_rate"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: facing_compliance_pct
    expr: SUM(facing_compliant) / NULLIF(SUM(facing_evaluable), 0)
    display_name: "Facing Compliance %"
    comment: "Observed facings meet the expected facing count from the slot assignment."
    synonyms: ["facings_rate", "right_facings_rate"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: price_tag_compliance_pct
    expr: SUM(price_tag_compliant) / NULLIF(SUM(price_tag_evaluable), 0)
    display_name: "Price Tag Compliance %"
    comment: "No price-tag mismatch flagged by shelf vision. The authoritative displayed-price comparison lives in the price-accuracy metric view."
    synonyms: ["tag_compliance", "right_tag_rate"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: positions_unknown
    expr: SUM(positions_unknown)
    display_name: "Unknown-State Positions"
    comment: "Position-days whose last capture was unknown or invalid - excluded from every compliance denominator, published so partial sensing is visible."
    synonyms: ["unevaluable_positions"]

  - name: observation_coverage_pct
    expr: SUM(positions_observed) / NULLIF(SUM(positions_expected), 0)
    display_name: "Observation Coverage %"
    comment: "Share of expected position-days captured at least once."
    synonyms: ["compliance_audit_coverage", "sensing_coverage"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: known_state_pct
    expr: SUM(positions_known) / NULLIF(SUM(positions_observed), 0)
    display_name: "Known-State %"
    comment: "Share of observed position-days whose last capture was usable."
    synonyms: ["evaluable_rate", "usable_reading_rate"]
    format:
      type: percentage
      decimal_places: {type: exact, places: 1}

  - name: products_allocation_divergent
    expr: SUM(CASE WHEN is_allocation_divergent THEN 1 ELSE 0 END)
    display_name: "Products Diverging From Allocation"
    comment: "Product-days whose summed expected facings differ from BMV planogram allocated facings. A flagged conversation between space planning and execution, never a correction (ADR 0040)."
    synonyms: ["allocation_mismatches", "bmv_divergence"]
$$;
