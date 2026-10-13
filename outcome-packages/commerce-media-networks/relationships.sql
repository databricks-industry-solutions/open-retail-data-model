-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- File: relationships.sql
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-13
-- ============================================================
-- Informational (NOT ENFORCED) foreign keys from the package facts to the media
-- domain + canonical core, plus intra-package FKs and enum CHECK constraints. Run
-- AFTER the commerce-media-networks dims and canonical core exist. FKs are declared on the
-- surrogate (_sk). FK columns are nullable (which dimension is populated depends
-- on the event/channel); orphan checks in checks.sql guard the populated ones.
-- ============================================================

-- ---------------- media_event ----------------
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_campaign        FOREIGN KEY (campaign_sk)        REFERENCES ${catalog}.${cmn_schema}.campaign (campaign_sk);
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_ad_group        FOREIGN KEY (ad_group_sk)        REFERENCES ${catalog}.${cmn_schema}.ad_group (ad_group_sk);
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_creative        FOREIGN KEY (creative_sk)        REFERENCES ${catalog}.${cmn_schema}.creative (creative_sk);
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_placement       FOREIGN KEY (placement_sk)       REFERENCES ${catalog}.${cmn_schema}.placement (placement_sk);
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_product         FOREIGN KEY (product_sk)         REFERENCES ${catalog}.${product_schema}.product (product_sk);
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_store           FOREIGN KEY (store_sk)           REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_profile         FOREIGN KEY (profile_sk)         REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_experiment      FOREIGN KEY (experiment_sk)      REFERENCES ${catalog}.${cmn_schema}.experiment (experiment_sk);
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_experiment_cell FOREIGN KEY (experiment_cell_sk) REFERENCES ${catalog}.${cmn_schema}.experiment_cell (experiment_cell_sk);
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_parent          FOREIGN KEY (parent_media_event_sk) REFERENCES ${catalog}.${cmn_schema}.media_event (media_event_sk);
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_delivery_channel FOREIGN KEY (delivery_channel_sk) REFERENCES ${catalog}.${cmn_schema}.delivery_channel (delivery_channel_sk);
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_audience        FOREIGN KEY (audience_sk)        REFERENCES ${catalog}.${marketing_schema}.audience (audience_sk);
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT fk_media_event_keyword         FOREIGN KEY (keyword_sk)         REFERENCES ${catalog}.${cmn_schema}.keyword (keyword_sk);

-- ---------------- conversion_event ----------------
ALTER TABLE ${catalog}.${cmn_schema}.conversion_event ADD CONSTRAINT fk_conversion_event_profile         FOREIGN KEY (profile_sk)         REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);
ALTER TABLE ${catalog}.${cmn_schema}.conversion_event ADD CONSTRAINT fk_conversion_event_product         FOREIGN KEY (product_sk)         REFERENCES ${catalog}.${product_schema}.product (product_sk);
ALTER TABLE ${catalog}.${cmn_schema}.conversion_event ADD CONSTRAINT fk_conversion_event_store           FOREIGN KEY (store_sk)           REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${cmn_schema}.conversion_event ADD CONSTRAINT fk_conversion_event_order_line      FOREIGN KEY (order_line_sk)      REFERENCES ${catalog}.${order_schema}.customer_order_line (order_line_sk);
ALTER TABLE ${catalog}.${cmn_schema}.conversion_event ADD CONSTRAINT fk_conversion_event_experiment      FOREIGN KEY (experiment_sk)      REFERENCES ${catalog}.${cmn_schema}.experiment (experiment_sk);
ALTER TABLE ${catalog}.${cmn_schema}.conversion_event ADD CONSTRAINT fk_conversion_event_experiment_cell FOREIGN KEY (experiment_cell_sk) REFERENCES ${catalog}.${cmn_schema}.experiment_cell (experiment_cell_sk);
ALTER TABLE ${catalog}.${cmn_schema}.conversion_event ADD CONSTRAINT fk_conversion_event_promotion       FOREIGN KEY (promo_sk)           REFERENCES ${catalog}.${marketing_schema}.promotion (promo_sk);

-- ---------------- attributed_outcome ----------------
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_campaign       FOREIGN KEY (campaign_sk)       REFERENCES ${catalog}.${cmn_schema}.campaign (campaign_sk);
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_ad_group       FOREIGN KEY (ad_group_sk)       REFERENCES ${catalog}.${cmn_schema}.ad_group (ad_group_sk);
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_creative       FOREIGN KEY (creative_sk)       REFERENCES ${catalog}.${cmn_schema}.creative (creative_sk);
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_placement      FOREIGN KEY (placement_sk)      REFERENCES ${catalog}.${cmn_schema}.placement (placement_sk);
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_advertiser FOREIGN KEY (advertiser_sk) REFERENCES ${catalog}.${cmn_schema}.advertiser (advertiser_sk);
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_product        FOREIGN KEY (product_sk)        REFERENCES ${catalog}.${product_schema}.product (product_sk);
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_store          FOREIGN KEY (store_sk)          REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_profile        FOREIGN KEY (profile_sk)        REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_touch          FOREIGN KEY (touch_media_event_sk) REFERENCES ${catalog}.${cmn_schema}.media_event (media_event_sk);
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_conversion     FOREIGN KEY (conversion_event_sk)  REFERENCES ${catalog}.${cmn_schema}.conversion_event (conversion_event_sk);
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_experiment     FOREIGN KEY (experiment_sk)     REFERENCES ${catalog}.${cmn_schema}.experiment (experiment_sk);
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_promotion      FOREIGN KEY (promo_sk)          REFERENCES ${catalog}.${marketing_schema}.promotion (promo_sk);
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT fk_attributed_outcome_keyword        FOREIGN KEY (keyword_sk)         REFERENCES ${catalog}.${cmn_schema}.keyword (keyword_sk);

-- ---------------- experiment_assignment_bridge ----------------
ALTER TABLE ${catalog}.${cmn_schema}.experiment_assignment_bridge ADD CONSTRAINT fk_experiment_assignment_bridge_experiment      FOREIGN KEY (experiment_sk)      REFERENCES ${catalog}.${cmn_schema}.experiment (experiment_sk);
ALTER TABLE ${catalog}.${cmn_schema}.experiment_assignment_bridge ADD CONSTRAINT fk_experiment_assignment_bridge_experiment_cell FOREIGN KEY (experiment_cell_sk) REFERENCES ${catalog}.${cmn_schema}.experiment_cell (experiment_cell_sk);
ALTER TABLE ${catalog}.${cmn_schema}.experiment_assignment_bridge ADD CONSTRAINT fk_experiment_assignment_bridge_profile         FOREIGN KEY (profile_sk)         REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);

-- ---------------- campaign_day ----------------
ALTER TABLE ${catalog}.${cmn_schema}.campaign_day ADD CONSTRAINT fk_campaign_day_advertiser FOREIGN KEY (advertiser_sk) REFERENCES ${catalog}.${cmn_schema}.advertiser (advertiser_sk);
ALTER TABLE ${catalog}.${cmn_schema}.campaign_day ADD CONSTRAINT fk_campaign_day_campaign       FOREIGN KEY (campaign_sk)       REFERENCES ${catalog}.${cmn_schema}.campaign (campaign_sk);
ALTER TABLE ${catalog}.${cmn_schema}.campaign_day ADD CONSTRAINT fk_campaign_day_ad_group       FOREIGN KEY (ad_group_sk)       REFERENCES ${catalog}.${cmn_schema}.ad_group (ad_group_sk);
ALTER TABLE ${catalog}.${cmn_schema}.campaign_day ADD CONSTRAINT fk_campaign_day_creative       FOREIGN KEY (creative_sk)       REFERENCES ${catalog}.${cmn_schema}.creative (creative_sk);
ALTER TABLE ${catalog}.${cmn_schema}.campaign_day ADD CONSTRAINT fk_campaign_day_placement      FOREIGN KEY (placement_sk)      REFERENCES ${catalog}.${cmn_schema}.placement (placement_sk);
ALTER TABLE ${catalog}.${cmn_schema}.campaign_day ADD CONSTRAINT fk_campaign_day_product        FOREIGN KEY (product_sk)        REFERENCES ${catalog}.${product_schema}.product (product_sk);
ALTER TABLE ${catalog}.${cmn_schema}.campaign_day ADD CONSTRAINT fk_campaign_day_store          FOREIGN KEY (store_sk)          REFERENCES ${catalog}.${store_schema}.store (store_sk);
ALTER TABLE ${catalog}.${cmn_schema}.campaign_day ADD CONSTRAINT fk_campaign_day_delivery_channel FOREIGN KEY (delivery_channel_sk) REFERENCES ${catalog}.${cmn_schema}.delivery_channel (delivery_channel_sk);
ALTER TABLE ${catalog}.${cmn_schema}.campaign_day ADD CONSTRAINT fk_campaign_day_audience       FOREIGN KEY (audience_sk)       REFERENCES ${catalog}.${marketing_schema}.audience (audience_sk);

-- ---------------- incrementality_result ----------------
ALTER TABLE ${catalog}.${cmn_schema}.incrementality_result ADD CONSTRAINT fk_incrementality_result_experiment      FOREIGN KEY (experiment_sk)      REFERENCES ${catalog}.${cmn_schema}.experiment (experiment_sk);
ALTER TABLE ${catalog}.${cmn_schema}.incrementality_result ADD CONSTRAINT fk_incrementality_result_treatment_cell  FOREIGN KEY (treatment_cell_sk)  REFERENCES ${catalog}.${cmn_schema}.experiment_cell (experiment_cell_sk);
ALTER TABLE ${catalog}.${cmn_schema}.incrementality_result ADD CONSTRAINT fk_incrementality_result_control_cell    FOREIGN KEY (control_cell_sk)    REFERENCES ${catalog}.${cmn_schema}.experiment_cell (experiment_cell_sk);
ALTER TABLE ${catalog}.${cmn_schema}.incrementality_result ADD CONSTRAINT fk_incrementality_result_campaign        FOREIGN KEY (campaign_sk)        REFERENCES ${catalog}.${cmn_schema}.campaign (campaign_sk);
ALTER TABLE ${catalog}.${cmn_schema}.incrementality_result ADD CONSTRAINT fk_incrementality_result_advertiser  FOREIGN KEY (advertiser_sk)  REFERENCES ${catalog}.${cmn_schema}.advertiser (advertiser_sk);
ALTER TABLE ${catalog}.${cmn_schema}.incrementality_result ADD CONSTRAINT fk_incrementality_result_product         FOREIGN KEY (product_sk)         REFERENCES ${catalog}.${product_schema}.product (product_sk);

-- ---------------- experiment_daily ----------------
ALTER TABLE ${catalog}.${cmn_schema}.experiment_daily ADD CONSTRAINT fk_experiment_daily_experiment      FOREIGN KEY (experiment_sk)      REFERENCES ${catalog}.${cmn_schema}.experiment (experiment_sk);
ALTER TABLE ${catalog}.${cmn_schema}.experiment_daily ADD CONSTRAINT fk_experiment_daily_experiment_cell FOREIGN KEY (experiment_cell_sk) REFERENCES ${catalog}.${cmn_schema}.experiment_cell (experiment_cell_sk);

-- ---------------- budget_allocation ----------------
ALTER TABLE ${catalog}.${cmn_schema}.budget_allocation ADD CONSTRAINT fk_budget_allocation_campaign       FOREIGN KEY (campaign_sk)       REFERENCES ${catalog}.${cmn_schema}.campaign (campaign_sk);
ALTER TABLE ${catalog}.${cmn_schema}.budget_allocation ADD CONSTRAINT fk_budget_allocation_ad_group       FOREIGN KEY (ad_group_sk)       REFERENCES ${catalog}.${cmn_schema}.ad_group (ad_group_sk);
ALTER TABLE ${catalog}.${cmn_schema}.budget_allocation ADD CONSTRAINT fk_budget_allocation_placement      FOREIGN KEY (placement_sk)      REFERENCES ${catalog}.${cmn_schema}.placement (placement_sk);
ALTER TABLE ${catalog}.${cmn_schema}.budget_allocation ADD CONSTRAINT fk_budget_allocation_advertiser FOREIGN KEY (advertiser_sk) REFERENCES ${catalog}.${cmn_schema}.advertiser (advertiser_sk);

-- ---------------- pacing_snapshot ----------------
ALTER TABLE ${catalog}.${cmn_schema}.pacing_snapshot ADD CONSTRAINT fk_pacing_snapshot_campaign  FOREIGN KEY (campaign_sk)  REFERENCES ${catalog}.${cmn_schema}.campaign (campaign_sk);
ALTER TABLE ${catalog}.${cmn_schema}.pacing_snapshot ADD CONSTRAINT fk_pacing_snapshot_ad_group  FOREIGN KEY (ad_group_sk)  REFERENCES ${catalog}.${cmn_schema}.ad_group (ad_group_sk);
ALTER TABLE ${catalog}.${cmn_schema}.pacing_snapshot ADD CONSTRAINT fk_pacing_snapshot_placement FOREIGN KEY (placement_sk) REFERENCES ${catalog}.${cmn_schema}.placement (placement_sk);

-- ---------------- product_store_day ----------------
-- The footfall fact that used to sit alongside this one has moved to
-- connected_store_signals.sensor_report_interval (ADR 0033), taking its store FK with it.
-- CMN reads its disclosure-controlled compatibility projection through
-- gold/store_zone_interval.sql at the original published object name.
ALTER TABLE ${catalog}.${cmn_schema}.product_store_day ADD CONSTRAINT fk_product_store_day_product  FOREIGN KEY (product_sk) REFERENCES ${catalog}.${product_schema}.product (product_sk);
ALTER TABLE ${catalog}.${cmn_schema}.product_store_day ADD CONSTRAINT fk_product_store_day_store    FOREIGN KEY (store_sk)   REFERENCES ${catalog}.${store_schema}.store (store_sk);

-- ============================================================
-- Enum / state-domain CHECK constraints (always-on; match the column-comment
-- "Allowed values"). Databricks does not support inline CHECK — ADD CONSTRAINT.
-- ============================================================
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT chk_fme_event_type CHECK (event_type IN ('impression','viewable_impression','click','ad_play','video_start','video_complete'));
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT chk_fme_ivt_type CHECK (ivt_type IS NULL OR ivt_type IN ('none','givt','sivt'));
ALTER TABLE ${catalog}.${cmn_schema}.media_event ADD CONSTRAINT chk_fme_consent CHECK (consent_status IS NULL OR consent_status IN ('granted','denied','unknown'));

ALTER TABLE ${catalog}.${cmn_schema}.conversion_event ADD CONSTRAINT chk_fce_conversion_type CHECK (conversion_type IN ('purchase','add_to_cart','pdp_view','store_visit','signup'));
ALTER TABLE ${catalog}.${cmn_schema}.conversion_event ADD CONSTRAINT chk_fce_consent CHECK (consent_status IS NULL OR consent_status IN ('granted','denied','unknown'));

ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT chk_fao_attr_model CHECK (attribution_model IS NULL OR attribution_model IN ('last_touch','first_touch','linear','position_based','data_driven'));
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT chk_fao_basis CHECK (click_or_view_basis IS NULL OR click_or_view_basis IN ('click','view'));
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ADD CONSTRAINT chk_fao_consent CHECK (consent_status IS NULL OR consent_status IN ('granted','denied','unknown'));

ALTER TABLE ${catalog}.${cmn_schema}.experiment_assignment_bridge ADD CONSTRAINT chk_bea_unit_type CHECK (assignment_unit_type IS NULL OR assignment_unit_type IN ('user','household','geo','store','device'));

ALTER TABLE ${catalog}.${cmn_schema}.campaign_day ADD CONSTRAINT chk_acd_attr_model CHECK (attribution_model IS NULL OR attribution_model IN ('last_touch','first_touch','linear','position_based','data_driven'));
ALTER TABLE ${catalog}.${cmn_schema}.campaign_day ADD CONSTRAINT chk_acd_suppression CHECK (suppression_reason IS NULL OR suppression_reason IN ('below_threshold','consent','policy','none'));

ALTER TABLE ${catalog}.${cmn_schema}.incrementality_result ADD CONSTRAINT chk_fir_metric CHECK (metric_name IN ('incremental_sales','incremental_units','roas','conversion_rate','reach'));
ALTER TABLE ${catalog}.${cmn_schema}.incrementality_result ADD CONSTRAINT chk_fir_level CHECK (analysis_level IS NULL OR analysis_level IN ('overall','store','geo','product','category','vendor'));
ALTER TABLE ${catalog}.${cmn_schema}.incrementality_result ADD CONSTRAINT chk_fir_methodology CHECK (methodology IS NULL OR methodology IN ('randomized_control','matched_market','synthetic_control','difference_in_differences','other'));

ALTER TABLE ${catalog}.${cmn_schema}.experiment_daily ADD CONSTRAINT chk_aed_level CHECK (analysis_level IS NULL OR analysis_level IN ('overall','store','geo','product','category','vendor'));

ALTER TABLE ${catalog}.${cmn_schema}.budget_allocation ADD CONSTRAINT chk_fba_level CHECK (allocation_level IS NULL OR allocation_level IN ('campaign','ad_group','placement'));
ALTER TABLE ${catalog}.${cmn_schema}.budget_allocation ADD CONSTRAINT chk_fba_funding CHECK (funding_source IS NULL OR funding_source IN ('supplier','retailer','shared','agency'));
ALTER TABLE ${catalog}.${cmn_schema}.budget_allocation ADD CONSTRAINT chk_fba_pacing_method CHECK (pacing_method IS NULL OR pacing_method IN ('even','asap','front_loaded','custom'));

ALTER TABLE ${catalog}.${cmn_schema}.pacing_snapshot ADD CONSTRAINT chk_fps_status CHECK (pacing_status IS NULL OR pacing_status IN ('on_track','under_pacing','over_pacing','exhausted'));

-- ============================================================
-- Relocated retail-media dimensions (gold): dim<->dim FKs + enum CHECKs.
-- advertiser reuses silver supplier (gold->silver FK); the ad_group->audience
-- FK now targets the shared silver marketing.audience dim (ADR 0022 — promoted
-- from this gold package now that behavioral segmentation is a 2nd consumer).
-- ============================================================
-- advertiser (advertiser) ──> supplier (canonical core)
ALTER TABLE ${catalog}.${cmn_schema}.advertiser
  ADD CONSTRAINT fk_advertiser_supplier
  FOREIGN KEY (supplier_sk) REFERENCES ${catalog}.${supplier_schema}.supplier (supplier_sk);

-- campaign ──> advertiser (advertiser)
ALTER TABLE ${catalog}.${cmn_schema}.campaign
  ADD CONSTRAINT fk_campaign_advertiser
  FOREIGN KEY (advertiser_sk) REFERENCES ${catalog}.${cmn_schema}.advertiser (advertiser_sk);

-- ad_group ──> campaign
ALTER TABLE ${catalog}.${cmn_schema}.ad_group
  ADD CONSTRAINT fk_ad_group_campaign
  FOREIGN KEY (campaign_sk) REFERENCES ${catalog}.${cmn_schema}.campaign (campaign_sk);

-- ad_group ──> audience (shared silver marketing.audience dim, ADR 0022)
ALTER TABLE ${catalog}.${cmn_schema}.ad_group
  ADD CONSTRAINT fk_ad_group_audience
  FOREIGN KEY (audience_sk) REFERENCES ${catalog}.${marketing_schema}.audience (audience_sk);

-- keyword ──> ad_group (a keyword is targeted within an ad group)
ALTER TABLE ${catalog}.${cmn_schema}.keyword
  ADD CONSTRAINT fk_keyword_ad_group
  FOREIGN KEY (ad_group_sk) REFERENCES ${catalog}.${cmn_schema}.ad_group (ad_group_sk);

-- creative ──> campaign
ALTER TABLE ${catalog}.${cmn_schema}.creative
  ADD CONSTRAINT fk_creative_campaign
  FOREIGN KEY (campaign_sk) REFERENCES ${catalog}.${cmn_schema}.campaign (campaign_sk);

-- placement is a standalone inventory catalog (no parent FK); a campaign buys
-- placements via a fact in the outcome packages.

-- experiment ──> campaign (optional: the campaign under test)
ALTER TABLE ${catalog}.${cmn_schema}.experiment
  ADD CONSTRAINT fk_experiment_campaign
  FOREIGN KEY (campaign_sk) REFERENCES ${catalog}.${cmn_schema}.campaign (campaign_sk);

-- experiment_cell ──> experiment
ALTER TABLE ${catalog}.${cmn_schema}.experiment_cell
  ADD CONSTRAINT fk_experiment_cell_experiment
  FOREIGN KEY (experiment_sk) REFERENCES ${catalog}.${cmn_schema}.experiment (experiment_sk);

-- ------------------------------------------------------------
-- Logical relationships on business keys (NOT declared as UC FKs).
-- Under SCD2 the business key is not unique, so it cannot be a UC FK
-- target; enforce in ETL / quality checks instead.
--
--   advertiser.supplier_id       ->  supplier.supplier_id            (durable join, is_current = TRUE)
--   campaign.advertiser_id       ->  advertiser.advertiser_id (durable join, is_current = TRUE)
--   ad_group.campaign_id             ->  campaign.campaign_id            (durable join, is_current = TRUE)
--   creative.campaign_id             ->  campaign.campaign_id            (durable join, is_current = TRUE)
--   experiment.campaign_id           ->  campaign.campaign_id            (durable join, is_current = TRUE)
--   experiment_cell.experiment_id    ->  experiment.experiment_id        (durable join, is_current = TRUE)
-- ------------------------------------------------------------

-- ============================================================
-- Enum / state-domain CHECK constraints (always-on enforcement).
-- Lists match the "Allowed values" in each table's column comments.
-- ============================================================
ALTER TABLE ${catalog}.${cmn_schema}.advertiser
  ADD CONSTRAINT chk_advertiser_relationship_type
  CHECK (relationship_type IS NULL OR relationship_type IN ('direct', 'agency', 'reseller'));
ALTER TABLE ${catalog}.${cmn_schema}.advertiser
  ADD CONSTRAINT chk_advertiser_advertiser_status
  CHECK (advertiser_status IS NULL OR advertiser_status IN ('active', 'inactive'));

ALTER TABLE ${catalog}.${cmn_schema}.campaign
  ADD CONSTRAINT chk_campaign_objective
  CHECK (objective IS NULL OR objective IN ('awareness', 'consideration', 'conversion', 'loyalty', 'other'));
ALTER TABLE ${catalog}.${cmn_schema}.campaign
  ADD CONSTRAINT chk_campaign_status
  CHECK (campaign_status IS NULL OR campaign_status IN ('draft', 'active', 'paused', 'completed', 'archived'));
ALTER TABLE ${catalog}.${cmn_schema}.campaign
  ADD CONSTRAINT chk_campaign_buy_model
  CHECK (buy_model IS NULL OR buy_model IN ('cpc', 'cpm', 'cpa', 'flat', 'other'));
ALTER TABLE ${catalog}.${cmn_schema}.campaign
  ADD CONSTRAINT chk_campaign_attribution_model
  CHECK (attribution_model IS NULL OR attribution_model IN ('last_touch', 'first_touch', 'linear', 'position_based', 'data_driven'));
ALTER TABLE ${catalog}.${cmn_schema}.campaign
  ADD CONSTRAINT chk_campaign_sales_metric_type
  CHECK (sales_metric_type IS NULL OR sales_metric_type IN ('gross', 'net'));

ALTER TABLE ${catalog}.${cmn_schema}.ad_group
  ADD CONSTRAINT chk_ad_group_status
  CHECK (ad_group_status IS NULL OR ad_group_status IN ('draft', 'active', 'paused', 'completed', 'archived'));
ALTER TABLE ${catalog}.${cmn_schema}.ad_group
  ADD CONSTRAINT chk_ad_group_targeting_mode
  CHECK (targeting_mode IS NULL OR targeting_mode IN ('keyword', 'audience', 'automatic', 'contextual', 'manual'));
ALTER TABLE ${catalog}.${cmn_schema}.ad_group
  ADD CONSTRAINT chk_ad_group_bid_strategy
  CHECK (bid_strategy IS NULL OR bid_strategy IN ('manual_cpc', 'auto', 'target_cpa', 'target_roas', 'max_conversions'));
ALTER TABLE ${catalog}.${cmn_schema}.ad_group
  ADD CONSTRAINT chk_ad_group_optimization_goal
  CHECK (optimization_goal IS NULL OR optimization_goal IN ('clicks', 'conversions', 'roas', 'impressions', 'reach'));

ALTER TABLE ${catalog}.${cmn_schema}.creative
  ADD CONSTRAINT chk_creative_type
  CHECK (creative_type IS NULL OR creative_type IN ('image', 'video', 'audio', 'html', 'native', 'text'));
ALTER TABLE ${catalog}.${cmn_schema}.creative
  ADD CONSTRAINT chk_creative_approval_status
  CHECK (approval_status IS NULL OR approval_status IN ('draft', 'submitted', 'approved', 'rejected', 'archived'));
ALTER TABLE ${catalog}.${cmn_schema}.creative
  ADD CONSTRAINT chk_creative_brand_safety_class
  CHECK (brand_safety_class IS NULL OR brand_safety_class IN ('safe', 'moderate', 'restricted'));

ALTER TABLE ${catalog}.${cmn_schema}.placement
  ADD CONSTRAINT chk_placement_ad_product_line
  CHECK (ad_product_line IS NULL OR ad_product_line IN ('sponsored_products', 'onsite_display', 'offsite_display', 'email', 'loyalty'));
ALTER TABLE ${catalog}.${cmn_schema}.placement
  ADD CONSTRAINT chk_placement_type
  CHECK (placement_type IS NULL OR placement_type IN ('search', 'banner', 'product_listing', 'video', 'audio', 'endcap', 'shelf', 'other'));
ALTER TABLE ${catalog}.${cmn_schema}.placement
  ADD CONSTRAINT chk_placement_ad_format
  CHECK (ad_format IS NULL OR ad_format IN ('display', 'video', 'audio', 'native', 'sponsored_product', 'text'));
ALTER TABLE ${catalog}.${cmn_schema}.placement
  ADD CONSTRAINT chk_placement_pricing_model
  CHECK (pricing_model IS NULL OR pricing_model IN ('cpc', 'cpm', 'cpa', 'flat', 'other'));
ALTER TABLE ${catalog}.${cmn_schema}.placement
  ADD CONSTRAINT chk_placement_device_type
  CHECK (device_type IS NULL OR device_type IN ('desktop', 'mobile', 'tablet', 'ctv', 'other'));
ALTER TABLE ${catalog}.${cmn_schema}.placement
  ADD CONSTRAINT chk_placement_store_scope
  CHECK (store_scope IS NULL OR store_scope IN ('all_stores', 'banner', 'region', 'single_store', 'online'));
ALTER TABLE ${catalog}.${cmn_schema}.placement
  ADD CONSTRAINT chk_placement_capacity_unit
  CHECK (capacity_unit IS NULL OR capacity_unit IN ('impressions', 'slots', 'seconds', 'sov_pct'));

ALTER TABLE ${catalog}.${cmn_schema}.experiment
  ADD CONSTRAINT chk_experiment_type
  CHECK (experiment_type IS NULL OR experiment_type IN ('geo_holdout', 'audience_holdout', 'ghost_ads', 'switchback', 'pre_post', 'other'));
ALTER TABLE ${catalog}.${cmn_schema}.experiment
  ADD CONSTRAINT chk_experiment_methodology
  CHECK (methodology IS NULL OR methodology IN ('randomized_control', 'matched_market', 'synthetic_control', 'difference_in_differences', 'other'));
ALTER TABLE ${catalog}.${cmn_schema}.experiment
  ADD CONSTRAINT chk_experiment_unit_of_assignment
  CHECK (unit_of_assignment IS NULL OR unit_of_assignment IN ('user', 'household', 'geo', 'store', 'device'));
ALTER TABLE ${catalog}.${cmn_schema}.experiment
  ADD CONSTRAINT chk_experiment_objective_metric
  CHECK (objective_metric IS NULL OR objective_metric IN ('incremental_sales', 'incremental_units', 'roas', 'conversion_rate', 'reach', 'other'));
ALTER TABLE ${catalog}.${cmn_schema}.experiment
  ADD CONSTRAINT chk_experiment_status
  CHECK (experiment_status IS NULL OR experiment_status IN ('draft', 'running', 'completed', 'analyzed', 'archived'));

ALTER TABLE ${catalog}.${cmn_schema}.experiment_cell
  ADD CONSTRAINT chk_experiment_cell_role
  CHECK (cell_role IS NULL OR cell_role IN ('treatment', 'control', 'holdout'));

ALTER TABLE ${catalog}.${cmn_schema}.keyword
  ADD CONSTRAINT chk_keyword_match_type
  CHECK (match_type IS NULL OR match_type IN ('exact', 'phrase', 'broad', 'negative'));
ALTER TABLE ${catalog}.${cmn_schema}.keyword
  ADD CONSTRAINT chk_keyword_status
  CHECK (keyword_status IS NULL OR keyword_status IN ('active', 'paused', 'archived'));

-- audience enum/range CHECKs moved to canonical-core/marketing/relationships.sql (ADR 0022).

-- delivery_channel (coarse distribution channel) enum domain
ALTER TABLE ${catalog}.${cmn_schema}.delivery_channel
  ADD CONSTRAINT chk_delivery_channel_category
  CHECK (delivery_channel_category IS NULL OR delivery_channel_category IN ('onsite_web', 'onsite_app', 'offsite', 'in_store_screen', 'in_store_audio', 'dooh', 'other'));
