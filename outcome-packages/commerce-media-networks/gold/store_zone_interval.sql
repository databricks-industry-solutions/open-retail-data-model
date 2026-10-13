-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks
-- View: store_zone_interval
-- Layer: outcome package (gold / exact-name deprecated compatibility)
-- Version: 0.5
-- Generated: 2026-07-28
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-07-28
-- ============================================================
-- DEPRECATED. REMOVAL DATE: 2026-10-31 (the 90-day floor of docs/versioning-policy.md §3,
-- counted from 2026-07-28). A date, not a pointer to the policy: §3.4 requires the header to
-- name one, and "see the policy" sends a developer to a document that names no date either.
-- Migrate shared consumers to ${css_schema}.gold_zone_traffic_shared and operational
-- consumers to ${css_schema}.gold_zone_traffic_current.
--
-- The deprecation also reaches Unity Catalog as a tag, so Genie has a reason to prefer the
-- successor: ADR 0010 makes system.certification_status the Ontology authority signal, and an
-- untagged shim keeps ranking alongside the view that replaces it. The tagging statement
-- lives in this package's comments.sql, not here -- a gold file holds exactly one view
-- definition, and tools/ordm_config.view_select_body takes the whole remainder of the file to
-- be that definition's body, so a second statement here is silently swallowed into it. This
-- comment is also deliberately free of SQL keywords, because that same regex matched them
-- when it was not.
--
-- WHY THIS EXISTS: cmn_schema.store_zone_interval was published before ADR 0033 moved
-- sensing ownership to Connected Store Signals. Existing consumers address this exact
-- object name, so changing it to gold_store_zone_interval was not compatibility.
--
-- The projection has the exact retired order, data types, and interval semantics. It adds
-- no migration-helper columns. The CSS source omits suppressed intervals completely: this
-- retired shape has no disclosure flag, so retaining a NULL-measure row would expose the
-- protected interval through interval_start_ts and interval_minutes. opportunity_to_see
-- is NULL until CMN approves a versioned placement-level derivation; the previous
-- placeholder formula is intentionally gone. Historical OTS must be retained by the
-- CMN-owned legacy mapping described in
-- docs/migrations/0033-cmn-store-zone-interval-to-css.md during the manual cutover.
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${cmn_schema}.store_zone_interval AS
SELECT
  CAST(s.shared_zone_traffic_interval_sk AS BIGINT) AS store_zone_interval_sk,
  CAST(s.shared_zone_traffic_interval_id AS STRING) AS store_zone_interval_id,
  CAST(s.store_sk AS BIGINT) AS store_sk,
  CAST(s.store_id AS STRING) AS store_id,
  CAST(s.zone_code AS STRING) AS store_zone_code,
  CAST(s.interval_start_ts AS TIMESTAMP) AS interval_start_ts,
  CAST(s.trading_date AS DATE) AS interval_date,
  CAST(s.interval_minutes AS INT) AS interval_minutes,
  CAST(s.footfall_count AS BIGINT) AS footfall_count,
  CAST(s.avg_dwell_seconds AS INT) AS avg_dwell_seconds,
  CAST(NULL AS BIGINT) AS opportunity_to_see,
  CAST(TRUE AS BOOLEAN) AS aggregated_flag,
  CAST('connected-store-signals.shared' AS STRING) AS record_source,
  CAST(current_timestamp() AS TIMESTAMP) AS load_timestamp
FROM ${catalog}.${css_schema}.gold_zone_traffic_interval_shared s;
