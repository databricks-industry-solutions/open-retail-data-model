-- ============================================================
-- ORDM · Outcome Package · Actionable Customer Understanding
-- Metric View: mv_competitive_position
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-24
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-24 by @saurabhshukla-db
-- ============================================================
-- Every ratio is recomputed from gold components. Distinct counts at the gold
-- grain become item-period counts when rolled across periods. Assortment rollups
-- across competitors or channels are presence-weighted averages of per-grain
-- overlaps, not a union of the own catalog; metadata states that contract.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${acu_schema}.mv_competitive_position
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Observation-native competitive price, promotion, distribution, availability, assortment, match-quality and detection-bound measures by category, durable competitor, observed channel and fiscal period. Price remains on national all-channel rows; measure_scope is price, promotion, assortment, or promotion_assortment. Assortment rollups across competitors or channels are presence-weighted per-grain averages, not own-catalog unions."
source: ${catalog}.${acu_schema}.gold_competitive_position

fields:
  - name: category
    expr: category
    display_name: "Category"
    comment: "Own merchandising category captured by the version-specific price product or source observation."
    synonyms: ["merchandising_category", "product_category"]
  - name: competitor_id
    expr: competitor_id
    display_name: "Competitor ID"
    comment: "Durable competitor business key, stable across SCD2 versions."
    synonyms: ["rival_id", "competitor"]
  - name: competitor_name
    expr: competitor_name
    display_name: "Competitor Name"
    comment: "Competitor display name effective at fiscal-period end."
    synonyms: ["rival_name", "banner_name"]
  - name: channel_code
    expr: channel_code
    display_name: "Observation Channel"
    comment: "Source-observed channel for promotion and assortment; all for national competitor-price observations."
    synonyms: ["sales_channel", "competitive_channel"]
  - name: fiscal_year
    expr: fiscal_year
    display_name: "Fiscal Year"
    comment: "NRF 4-5-4 fiscal year."
    synonyms: ["retail_year"]
  - name: fiscal_period
    expr: fiscal_period
    display_name: "Fiscal Period"
    comment: "NRF 4-5-4 fiscal period within the fiscal year."
    synonyms: ["retail_period"]
  - name: period_start_date
    expr: period_start_date
    display_name: "Period Start Date"
    comment: "First date of the fiscal period."
    synonyms: ["period_start"]
  - name: period_end_date
    expr: period_end_date
    display_name: "Period End Date"
    comment: "Last date of the fiscal period and competitor-name as-of date."
    synonyms: ["period_end"]
  - name: currency_code
    expr: currency_code
    display_name: "Currency"
    comment: "ISO 4217 reporting currency where the available monetary observation families agree."
    synonyms: ["reporting_currency", "base_currency"]
  - name: measure_scope
    expr: measure_scope
    display_name: "Measure Scope"
    comment: "Reachable observation-family scope: price, promotion, assortment, or promotion_assortment. Use with channel_code because national price cannot co-occur with source-channel promotion/assortment."
    synonyms: ["row_measure_scope", "observation_family_scope"]
  - name: price_index_basis
    expr: price_index_basis
    display_name: "Price Index Basis"
    comment: "Regular-price basis: own list price versus competitor MRP."
    synonyms: ["price_basis"]
  - name: price_coverage_basis
    expr: price_coverage_basis
    display_name: "Price Coverage Basis"
    comment: "Usable regular-price products divided by observed matched price products."
    synonyms: ["coverage_basis"]
  - name: promo_sov_basis
    expr: promo_sov_basis
    display_name: "Promotion SOV Basis"
    comment: "Promoted product-day presence over own product-days covered by any competitor observation; placement and spend bases are not blended."
    synonyms: ["promo_presence_basis", "share_of_voice_basis"]
  - name: distribution_basis
    expr: distribution_basis
    display_name: "Distribution Basis"
    comment: "Observed listing locations and unmatched listed competitor items; no fabricated ACV weighting."
    synonyms: ["points_of_availability_basis"]
  - name: availability_basis
    expr: availability_basis
    display_name: "Availability Basis"
    comment: "Listed assortment observations with an explicit stock state."
    synonyms: ["stock_basis"]
  - name: assortment_basis
    expr: assortment_basis
    display_name: "Assortment Basis"
    comment: "Observed active own products versus observed competitor items using exact/equivalent matches at confidence 0.80 or higher."
    synonyms: ["overlap_basis", "match_floor_basis"]
  - name: detection_basis
    expr: detection_basis
    display_name: "Detection Basis"
    comment: "Upper-bound lag from displayed promotion start or the prior assortment observation; not event-time certainty."
    synonyms: ["detection_bound_basis", "freshness_basis"]
  - name: channel_basis
    expr: channel_basis
    display_name: "Channel Basis"
    comment: "Distinguishes national all-channel price rows from source-observed promotion and assortment channels."
    synonyms: ["geography_channel_basis"]

measures:
  - name: price_index_vs_competitor
    expr: 100.0 * SUM(price_ratio_sum) / NULLIF(SUM(valid_price_observation_count), 0)
    display_name: "Price Index vs Competitor"
    comment: "Arithmetic mean of usable product-day own-list/competitor-MRP price relatives, unweighted across observations; 100 is regular-price parity."
    synonyms: ["competitor_price_index", "price_parity_index"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: sales_weighted_price_index_vs_competitor
    expr: 100.0 * SUM(sales_weighted_price_ratio_sum) / NULLIF(SUM(matched_units), 0)
    display_name: "Sales-Weighted Price Index"
    comment: "Own-unit-weighted arithmetic mean of usable product-day own-list/competitor-MRP price relatives; not a ratio of aggregate price totals."
    synonyms: ["weighted_competitor_price_index"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: price_observation_coverage_pct
    expr: 100.0 * SUM(valid_price_product_count) / NULLIF(SUM(observed_price_product_count), 0)
    display_name: "Usable Price-Product Coverage %"
    comment: "Usable price-product counts divided by observed matched price-product counts; no cap."
    synonyms: ["price_coverage", "matched_price_coverage"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: promo_sov_pct
    expr: 100.0 * SUM(own_promo_presence_count) / NULLIF(SUM(own_promo_presence_count) + SUM(competitor_promo_presence_count), 0)
    display_name: "Promotion Share of Voice %"
    comment: "Own promoted product-day presence divided by own plus competitor promoted presence over the same observation-coverage product-days."
    synonyms: ["promotion_sov", "promo_presence_share"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: avg_discount_depth_pct
    expr: SUM(discount_depth_pct_sum) / NULLIF(SUM(valid_discount_depth_count), 0)
    display_name: "Average Competitor Discount Depth %"
    comment: "Arithmetic mean of observed or ingest-derived competitor-promotion discount-depth percentages with known depth."
    synonyms: ["competitor_discount_depth"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: listed_share_pct
    expr: 100.0 * SUM(listed_observation_count) / NULLIF(SUM(assortment_observation_count), 0)
    display_name: "Observed Listed Share %"
    comment: "Listed observations divided by all assortment observations."
    synonyms: ["listing_rate", "listed_presence_share"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: availability_rate_pct
    expr: 100.0 * SUM(available_observation_count) / NULLIF(SUM(stock_flagged_observation_count), 0)
    display_name: "Observed Availability Rate %"
    comment: "Available listed observations divided by listed observations with known stock state."
    synonyms: ["in_stock_rate", "observed_availability"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: assortment_overlap_pct
    expr: 100.0 * SUM(matched_listed_product_count) / NULLIF(SUM(observed_own_product_count), 0)
    display_name: "Assortment Overlap %"
    comment: "Confidence-qualified active-own matched listings divided by observed active-own product-periods. Rollups across competitors or channels are presence-weighted averages, not a union over the own catalog."
    synonyms: ["range_overlap", "matched_assortment_share"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: assortment_uniqueness_pct
    expr: 100.0 * (SUM(observed_own_product_count) - SUM(matched_listed_product_count)) / NULLIF(SUM(observed_own_product_count), 0)
    display_name: "Own Assortment Uniqueness %"
    comment: "Observed active-own product-periods without a confidence-qualified competitor listing. Rollups across competitors or channels are presence-weighted averages, not a union over the own catalog."
    synonyms: ["range_uniqueness", "differentiated_assortment_share"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: assortment_jaccard_index_pct
    expr: 100.0 * SUM(matched_listed_product_count) / NULLIF(SUM(observed_own_product_count) + SUM(unmatched_listed_item_count), 0)
    display_name: "Assortment Jaccard Index %"
    comment: "Product-space intersection divided by observed active-own products plus unmatched competitor items. Rollups across competitors or channels are presence-weighted averages, not a set union."
    synonyms: ["jaccard_similarity", "symmetric_assortment_overlap"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: match_coverage_pct
    expr: 100.0 * SUM(matched_listed_competitor_item_count) / NULLIF(SUM(competitor_listed_item_count), 0)
    display_name: "Competitor Item Match Coverage %"
    comment: "Listed competitor item-periods with exact/equivalent matches at confidence 0.80 or higher."
    synonyms: ["entity_resolution_coverage", "assortment_match_coverage"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: share_of_search_avg_rank
    expr: SUM(search_rank_sum) / NULLIF(SUM(search_rank_observation_count), 0)
    display_name: "Average Search Rank"
    comment: "Ratio-of-sums average rank where digital-shelf observations provide search position."
    synonyms: ["search_visibility_rank", "digital_shelf_rank"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: avg_detection_lag_upper_bound_days
    expr: SUM(detection_lag_days_sum) / NULLIF(SUM(detection_lag_observation_count), 0)
    display_name: "Average Detection-Lag Upper Bound (Days)"
    comment: "Average upper bound across promotion starts and observed assortment state changes; cadence is published separately."
    synonyms: ["time_to_detect", "detection_bound_days"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: avg_promotion_detection_lag_days
    expr: SUM(promotion_detection_lag_days_sum) / NULLIF(SUM(promotion_detection_observation_count), 0)
    display_name: "Average Promotion Detection-Lag Bound (Days)"
    comment: "Mean upper bound from displayed promotion start to observation; exposed separately because promotion and assortment bounds are not interchangeable."
    synonyms: ["promotion_time_to_detect", "promo_detection_bound_days"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: avg_assortment_detection_lag_days
    expr: SUM(assortment_detection_lag_days_sum) / NULLIF(SUM(assortment_detection_observation_count), 0)
    display_name: "Average Assortment Detection-Lag Bound (Days)"
    comment: "Mean prior-observation interval when listing or availability changed; exposed separately from promotion detection."
    synonyms: ["assortment_time_to_detect", "listing_detection_bound_days"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: avg_observation_cadence_days
    expr: SUM(observation_interval_days_sum) / NULLIF(SUM(observation_interval_count), 0)
    display_name: "Average Assortment Observation Cadence (Days)"
    comment: "Elapsed days between consecutive assortment observations for the same durable competitor item, location and channel."
    synonyms: ["crawl_cadence_days", "observation_interval"]
    format: {type: number, decimal_places: {type: exact, places: 2}}
  - name: points_of_availability_count
    expr: SUM(points_of_availability_count)
    display_name: "Points of Availability"
    comment: "Observed listed location-points summed across selected category/competitor/channel periods; national v1 uses ALL."
    synonyms: ["distribution_points", "availability_points"]
  - name: listed_channel_count
    expr: MAX(listed_channel_count)
    display_name: "Listed Channels"
    comment: "Distinct source-observed channels with a listed item for one category, competitor and fiscal period. Group by those dimensions; this context count is repeated across channel rows and is not additive."
    synonyms: ["channel_points_of_availability", "distribution_channel_count"]
  - name: valid_price_observation_count
    expr: SUM(valid_price_observation_count)
    display_name: "Valid Price Observations"
    comment: "Positive regular-price pairs in the same reporting currency."
    synonyms: ["usable_price_pairs"]
  - name: valid_price_product_count
    expr: SUM(valid_price_product_count)
    display_name: "Valid Price Products"
    comment: "Distinct usable price products summed as product-period counts."
    synonyms: ["usable_price_products"]
  - name: observed_price_product_count
    expr: SUM(observed_price_product_count)
    display_name: "Observed Price Products"
    comment: "Distinct matched price products summed as product-period counts."
    synonyms: ["price_coverage_denominator"]
  - name: matched_units
    expr: SUM(matched_units)
    display_name: "Matched Own Units"
    comment: "Own units sold on usable regular-price-pair product-days."
    synonyms: ["price_matched_units"]
  - name: competitor_observation_count
    expr: SUM(competitor_observation_count)
    display_name: "Competitor Price Observations"
    comment: "Competitor price rows represented by the selected gold grains."
    synonyms: ["price_crawl_observations"]
  - name: own_promo_presence_count
    expr: SUM(own_promo_presence_count)
    display_name: "Own Promo Presence Count"
    comment: "Own promoted product-days on comparable competitor-promotion observations."
    synonyms: ["own_promo_product_days"]
  - name: competitor_promo_presence_count
    expr: SUM(competitor_promo_presence_count)
    display_name: "Competitor Promo Presence Count"
    comment: "Comparable matched competitor promotion product-days."
    synonyms: ["rival_promo_product_days"]
  - name: competitor_promotion_observation_count
    expr: SUM(competitor_promotion_observation_count)
    display_name: "Competitor Promotion Observations"
    comment: "All source promotion observations, including category-only placements."
    synonyms: ["promo_observations"]
  - name: assortment_observation_count
    expr: SUM(assortment_observation_count)
    display_name: "Assortment Observations"
    comment: "All listing and availability observations."
    synonyms: ["listing_observations"]
  - name: listed_observation_count
    expr: SUM(listed_observation_count)
    display_name: "Listed Observations"
    comment: "Assortment observations explicitly marked listed."
    synonyms: ["listing_presence_count"]
  - name: available_observation_count
    expr: SUM(available_observation_count)
    display_name: "Available Listed Observations"
    comment: "Listed observations explicitly marked available."
    synonyms: ["in_stock_observations"]
  - name: out_of_stock_observation_count
    expr: SUM(out_of_stock_observation_count)
    display_name: "Out-of-Stock Listed Observations"
    comment: "Listed observations explicitly marked unavailable."
    synonyms: ["oos_observations"]
  - name: stock_flagged_observation_count
    expr: SUM(stock_flagged_observation_count)
    display_name: "Stock-State-Known Listed Observations"
    comment: "Listed observations with a non-null availability state."
    synonyms: ["availability_denominator"]
  - name: competitor_listed_item_count
    expr: SUM(competitor_listed_item_count)
    display_name: "Competitor Listed Item-Periods"
    comment: "Distinct listed competitor items summed across gold periods."
    synonyms: ["competitor_assortment_items"]
  - name: matched_listed_product_count
    expr: SUM(matched_listed_product_count)
    display_name: "Matched Listed Product-Periods"
    comment: "Distinct own products with confidence-qualified competitor listings, summed across periods."
    synonyms: ["assortment_intersection_count"]
  - name: matched_listed_inactive_product_count
    expr: SUM(matched_listed_inactive_product_count)
    display_name: "Matched Listed Inactive Own Product-Periods"
    comment: "Confidence-qualified competitor listings whose matched own product is outside the active period-end catalog; excluded from overlap but published for audit."
    synonyms: ["inactive_matched_listing_count", "excluded_overlap_matches"]
  - name: observed_own_product_count
    expr: SUM(observed_own_product_count)
    display_name: "Observed Active Own Product-Periods"
    comment: "Active own products represented by at least one assortment observation; denominator for overlap and uniqueness."
    synonyms: ["matchable_own_products", "observed_own_assortment"]
  - name: unmatched_listed_item_count
    expr: SUM(unmatched_listed_item_count)
    display_name: "Unmatched Listed Item-Periods"
    comment: "Distinct listed competitor items without a confidence-qualified exact/equivalent match."
    synonyms: ["assortment_gap_count"]
  - name: own_catalog_product_count
    expr: MAX(own_catalog_product_count)
    display_name: "Own Catalog Product-Periods"
    comment: "Distinct active own products for one category and fiscal period. Group by those dimensions; this context count is repeated across competitor/channel rows and is not additive."
    synonyms: ["own_assortment_denominator"]
  - name: assortment_state_change_count
    expr: SUM(assortment_state_change_count)
    display_name: "Observed Assortment State Changes"
    comment: "Listing or availability changes versus the prior observation for the same durable competitor item."
    synonyms: ["competitor_move_count"]
  - name: detection_lag_observation_count
    expr: SUM(detection_lag_observation_count)
    display_name: "Detection-Bound Observations"
    comment: "Promotion and assortment change observations with a computable upper-bound lag."
    synonyms: ["detection_denominator"]
  - name: observation_interval_count
    expr: SUM(observation_interval_count)
    display_name: "Assortment Observation Intervals"
    comment: "Consecutive assortment-observation intervals used for cadence."
    synonyms: ["cadence_denominator"]
  - name: circular_print_promo_count
    expr: SUM(circular_print_promo_count)
    display_name: "Print Circular Promotions"
    comment: "Observed print-circular promotion placements."
    synonyms: ["print_feature_count"]
  - name: circular_digital_promo_count
    expr: SUM(circular_digital_promo_count)
    display_name: "Digital Circular Promotions"
    comment: "Observed digital-circular promotion placements."
    synonyms: ["digital_feature_count"]
  - name: onsite_promo_count
    expr: SUM(onsite_promo_count)
    display_name: "Onsite Promotions"
    comment: "Observed onsite promotion placements."
    synonyms: ["web_promo_count"]
  - name: in_store_promo_count
    expr: SUM(in_store_promo_count)
    display_name: "In-Store Promotions"
    comment: "Observed in-store promotion placements."
    synonyms: ["store_promo_count"]
  - name: email_app_promo_count
    expr: SUM(email_app_promo_count)
    display_name: "Email/App Promotions"
    comment: "Observed email or app promotion placements."
    synonyms: ["direct_digital_promo_count"]
  - name: other_promo_count
    expr: SUM(other_promo_count)
    display_name: "Other Promotions"
    comment: "Observed promotion placements in other vehicles."
    synonyms: ["other_promotion_count"]
$$;
