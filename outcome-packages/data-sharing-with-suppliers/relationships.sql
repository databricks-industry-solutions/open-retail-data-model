-- ============================================================
-- ORDM · Outcome Package · Data Sharing with Suppliers
-- File: relationships.sql
-- Version: 0.5
-- Generated: 2026-07-13
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-03 (Data Monetization FKs + enum CHECKs added)
-- ============================================================
-- Informational (NOT ENFORCED) foreign keys and enum CHECKs for every use case in this
-- package, in one file per the standard layout. Sectioned by use case below:
-- Media Measurement, Joint Demand Planning (CPFR), and Data Monetization.
--
-- Media Measurement: FKs from the supplier-media-measurement extension tables into the
-- commerce-media-networks GOLD package (advertiser, campaign). This is a deliberate,
-- layer-legal gold->gold dependency (ADR 0019, amended by ADR 0021): the retail-media
-- entities are gold, so this package deploys AFTER commerce-media-networks exists. FKs on
-- the surrogate; nullable campaign scope guarded by checks.
-- ============================================================

ALTER TABLE ${catalog}.${dss_schema}.reporting_entitlement ADD CONSTRAINT fk_re_advertiser FOREIGN KEY (advertiser_sk) REFERENCES ${catalog}.${cmn_schema}.advertiser (advertiser_sk);
ALTER TABLE ${catalog}.${dss_schema}.reporting_entitlement ADD CONSTRAINT fk_re_campaign       FOREIGN KEY (campaign_sk)       REFERENCES ${catalog}.${cmn_schema}.campaign (campaign_sk);

ALTER TABLE ${catalog}.${dss_schema}.supplier_media_report_snapshot ADD CONSTRAINT fk_smrs_advertiser FOREIGN KEY (advertiser_sk) REFERENCES ${catalog}.${cmn_schema}.advertiser (advertiser_sk);
ALTER TABLE ${catalog}.${dss_schema}.supplier_media_report_snapshot ADD CONSTRAINT fk_smrs_campaign       FOREIGN KEY (campaign_sk)       REFERENCES ${catalog}.${cmn_schema}.campaign (campaign_sk);

-- Enum / state-domain CHECK constraints (match the column-comment "Allowed values").
ALTER TABLE ${catalog}.${dss_schema}.reporting_entitlement ADD CONSTRAINT chk_re_principal_type CHECK (principal_type IS NULL OR principal_type IN ('group', 'account', 'service_principal'));
ALTER TABLE ${catalog}.${dss_schema}.reporting_entitlement ADD CONSTRAINT chk_re_status CHECK (entitlement_status IS NULL OR entitlement_status IN ('active', 'suspended', 'revoked'));
ALTER TABLE ${catalog}.${dss_schema}.supplier_media_report_snapshot ADD CONSTRAINT chk_smrs_level CHECK (report_level IS NULL OR report_level IN ('brand', 'campaign', 'product'));

-- ============================================================
-- Joint Demand Planning (CPFR)
-- ============================================================
-- Informational (NOT ENFORCED) foreign keys from the joint-demand-planning extension
-- tables into the CANONICAL CORE only (supplier, product). Unlike the media-measurement
-- tables, these carry no gold->gold dependency: the statistical-baseline enrichment in
-- gold_joint_demand_plan is a NULL-safe read of the Smarter Demand package with no FK, so
-- this use case deploys against the core alone. FKs on the surrogate; nullable product
-- scope guarded by checks.

ALTER TABLE ${catalog}.${dss_schema}.demand_collaboration ADD CONSTRAINT fk_dc_supplier FOREIGN KEY (supplier_sk) REFERENCES ${catalog}.${supplier_schema}.supplier (supplier_sk);
ALTER TABLE ${catalog}.${dss_schema}.demand_collaboration ADD CONSTRAINT fk_dc_product  FOREIGN KEY (product_sk)  REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${dss_schema}.demand_plan_submission ADD CONSTRAINT fk_dps_supplier FOREIGN KEY (supplier_sk) REFERENCES ${catalog}.${supplier_schema}.supplier (supplier_sk);
ALTER TABLE ${catalog}.${dss_schema}.demand_plan_submission ADD CONSTRAINT fk_dps_product  FOREIGN KEY (product_sk)  REFERENCES ${catalog}.${product_schema}.product (product_sk);

ALTER TABLE ${catalog}.${dss_schema}.consensus_forecast_snapshot ADD CONSTRAINT fk_cfs_supplier FOREIGN KEY (supplier_sk) REFERENCES ${catalog}.${supplier_schema}.supplier (supplier_sk);
ALTER TABLE ${catalog}.${dss_schema}.consensus_forecast_snapshot ADD CONSTRAINT fk_cfs_product  FOREIGN KEY (product_sk)  REFERENCES ${catalog}.${product_schema}.product (product_sk);

-- Enum / state-domain CHECK constraints (match the column-comment "Allowed values").
ALTER TABLE ${catalog}.${dss_schema}.demand_collaboration ADD CONSTRAINT chk_dc_principal_type CHECK (principal_type IS NULL OR principal_type IN ('group', 'account', 'service_principal'));
ALTER TABLE ${catalog}.${dss_schema}.demand_collaboration ADD CONSTRAINT chk_dc_status CHECK (collaboration_status IS NULL OR collaboration_status IN ('active', 'suspended', 'ended'));
ALTER TABLE ${catalog}.${dss_schema}.demand_plan_submission ADD CONSTRAINT chk_dps_party_role CHECK (party_role IS NULL OR party_role IN ('retailer', 'supplier'));
ALTER TABLE ${catalog}.${dss_schema}.demand_plan_submission ADD CONSTRAINT chk_dps_status CHECK (submission_status IS NULL OR submission_status IN ('draft', 'submitted', 'superseded', 'withdrawn'));

-- ============================================================
-- Data Monetization
-- ============================================================
-- Informational (NOT ENFORCED) foreign keys for the data-monetization extension tables.
-- Three reference classes here:
--   1. INTRA-package: the subscription and the consumption meter FK onto data_product
--      (this package's own catalog), and consumption FKs onto the subscription it billed
--      under — the licence chain data_product -> subscription -> consumption.
--   2. CANONICAL CORE: supplier, for the licence's supplier scope.
--   3. GOLD->GOLD into commerce-media-networks (advertiser), the same deliberate,
--      layer-legal coupling the media-measurement tables already declare (ADR 0019,
--      amended by ADR 0021) — the advertiser is the buying-side view of the supplier, so
--      an advertiser-scoped licence anchors on it.
-- The cross-package REVENUE enrichment in gold_data_product_revenue is a NULL-safe read
-- of cmn's gold layer with NO FK, so it adds no row-level deploy-order coupling beyond
-- the advertiser FK below. FKs on the surrogate; nullable scopes guarded by checks.

ALTER TABLE ${catalog}.${dss_schema}.data_product_subscription ADD CONSTRAINT fk_dpsub_data_product FOREIGN KEY (data_product_sk) REFERENCES ${catalog}.${dss_schema}.data_product (data_product_sk);
ALTER TABLE ${catalog}.${dss_schema}.data_product_subscription ADD CONSTRAINT fk_dpsub_supplier    FOREIGN KEY (supplier_sk)     REFERENCES ${catalog}.${supplier_schema}.supplier (supplier_sk);
ALTER TABLE ${catalog}.${dss_schema}.data_product_subscription ADD CONSTRAINT fk_dpsub_advertiser  FOREIGN KEY (advertiser_sk)   REFERENCES ${catalog}.${cmn_schema}.advertiser (advertiser_sk);

ALTER TABLE ${catalog}.${dss_schema}.data_share_consumption ADD CONSTRAINT fk_dsc_subscription  FOREIGN KEY (data_product_subscription_sk) REFERENCES ${catalog}.${dss_schema}.data_product_subscription (data_product_subscription_sk);
ALTER TABLE ${catalog}.${dss_schema}.data_share_consumption ADD CONSTRAINT fk_dsc_data_product  FOREIGN KEY (data_product_sk)              REFERENCES ${catalog}.${dss_schema}.data_product (data_product_sk);
ALTER TABLE ${catalog}.${dss_schema}.data_share_consumption ADD CONSTRAINT fk_dsc_supplier      FOREIGN KEY (supplier_sk)                  REFERENCES ${catalog}.${supplier_schema}.supplier (supplier_sk);

-- Enum / state-domain CHECK constraints (match the column-comment "Allowed values").
ALTER TABLE ${catalog}.${dss_schema}.data_product ADD CONSTRAINT chk_dp_category CHECK (data_product_category IS NULL OR data_product_category IN ('media_measurement', 'demand_collaboration', 'category_benchmark', 'audience_insight'));
ALTER TABLE ${catalog}.${dss_schema}.data_product ADD CONSTRAINT chk_dp_delivery_mode CHECK (delivery_mode IS NULL OR delivery_mode IN ('share', 'api', 'file_export', 'dashboard'));
ALTER TABLE ${catalog}.${dss_schema}.data_product ADD CONSTRAINT chk_dp_pricing_model CHECK (pricing_model IS NULL OR pricing_model IN ('subscription_flat', 'per_consumption_unit', 'tiered', 'revenue_share'));
ALTER TABLE ${catalog}.${dss_schema}.data_product ADD CONSTRAINT chk_dp_consumption_unit CHECK (consumption_unit IS NULL OR consumption_unit IN ('query', 'row_scanned', 'report_delivery', 'api_call'));
ALTER TABLE ${catalog}.${dss_schema}.data_product ADD CONSTRAINT chk_dp_status CHECK (data_product_status IS NULL OR data_product_status IN ('draft', 'published', 'deprecated', 'retired'));

ALTER TABLE ${catalog}.${dss_schema}.data_product_subscription ADD CONSTRAINT chk_dpsub_principal_type CHECK (principal_type IS NULL OR principal_type IN ('group', 'account', 'service_principal'));
ALTER TABLE ${catalog}.${dss_schema}.data_product_subscription ADD CONSTRAINT chk_dpsub_billing_frequency CHECK (billing_frequency IS NULL OR billing_frequency IN ('monthly', 'quarterly', 'annual'));
ALTER TABLE ${catalog}.${dss_schema}.data_product_subscription ADD CONSTRAINT chk_dpsub_status CHECK (subscription_status IS NULL OR subscription_status IN ('pending', 'active', 'suspended', 'cancelled', 'expired'));

ALTER TABLE ${catalog}.${dss_schema}.data_share_consumption ADD CONSTRAINT chk_dsc_access_channel CHECK (access_channel IS NULL OR access_channel IN ('share', 'api', 'file_export', 'dashboard'));
