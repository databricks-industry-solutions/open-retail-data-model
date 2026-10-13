-- ============================================================
-- ORDM · Canonical Core · Interaction domain · data-quality checks
-- Version: 0.5 · Generated: 2026-07-27 · LLM-generated: true · Reviewed: 2026-07-27
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report a
-- value and never fail the run. Run by runtime/data-quality/run_checks.py.
-- ============================================================

-- ========== touchpoint (conformed omnichannel interaction fact) ==========

-- check: touchpoint_keys_not_null | severity: error
SELECT * FROM ${catalog}.${interaction_schema}.touchpoint
WHERE touchpoint_sk IS NULL OR touchpoint_id IS NULL
   OR interaction_type IS NULL OR event_timestamp IS NULL OR event_date IS NULL;

-- check: touchpoint_id_unique | severity: error
SELECT touchpoint_id, COUNT(*) AS n
FROM ${catalog}.${interaction_schema}.touchpoint
GROUP BY touchpoint_id HAVING COUNT(*) > 1;

-- check: touchpoint_pk_unique | severity: error
SELECT touchpoint_sk, COUNT(*) AS n
FROM ${catalog}.${interaction_schema}.touchpoint
GROUP BY touchpoint_sk HAVING COUNT(*) > 1;

-- check: touchpoint_interaction_type_domain | severity: error
SELECT * FROM ${catalog}.${interaction_schema}.touchpoint
WHERE interaction_type NOT IN ('page_view', 'product_view', 'search', 'add_to_cart',
  'remove_from_cart', 'cart_view', 'checkout_start', 'wishlist_add', 'app_open',
  'session_start', 'session_end', 'store_visit', 'call_center_contact', 'kiosk_session',
  'offline_marketing_response', 'phone_activation');

-- check: touchpoint_channel_domain | severity: error
SELECT * FROM ${catalog}.${interaction_schema}.touchpoint
WHERE channel_code IS NOT NULL
  AND channel_code NOT IN ('web', 'mobile_app', 'in_store', 'kiosk', 'call_center',
                           'direct_mail', 'other');

-- check: touchpoint_source_application_domain | severity: error
SELECT * FROM ${catalog}.${interaction_schema}.touchpoint
WHERE source_application IS NOT NULL
  AND source_application NOT IN ('ios_app', 'android_app', 'web_desktop', 'web_mobile',
                                 'loyalty_kiosk', 'in_store_pos', 'call_center_app',
                                 'email_platform', 'other');

-- check: touchpoint_consent_domain | severity: error
SELECT * FROM ${catalog}.${interaction_schema}.touchpoint
WHERE consent_status IS NOT NULL
  AND consent_status NOT IN ('granted', 'denied', 'unknown');

-- check: touchpoint_modality_coherence | severity: error
-- The omnichannel design rests on interaction_type + channel_code agreeing; the per-column
-- domain checks validate each independently but never assert they are CONSISTENT. This guards
-- the discriminator (M2): (a) an OFFLINE interaction_type must carry an offline channel_code, a
-- NULL device_id_hash, AND a non-NULL profile_id (offline is identity-first — profile known, no
-- anonymous device key, so a person-level offline touch with no actor at all is invalid); (b) a
-- DIGITAL interaction_type must carry a digital channel_code; (c) an in-store verb (store_visit /
-- kiosk_session) must populate store_sk. NULLs are otherwise tolerated (channel_code is nullable);
-- this fires only on an explicit contradiction CI cannot catch (cross-column semantics).
SELECT * FROM ${catalog}.${interaction_schema}.touchpoint
WHERE
  -- (a) offline verb on a digital channel, carrying an anonymous device key, or with no actor
  ( interaction_type IN ('store_visit', 'call_center_contact', 'kiosk_session',
                         'offline_marketing_response', 'phone_activation')
    AND ( channel_code IN ('web', 'mobile_app')
          OR device_id_hash IS NOT NULL
          OR profile_id IS NULL ) )
  -- (b) digital verb on an offline channel
  OR ( interaction_type IN ('page_view', 'product_view', 'search', 'add_to_cart',
                            'remove_from_cart', 'cart_view', 'checkout_start', 'wishlist_add',
                            'app_open', 'session_start', 'session_end')
       AND channel_code IN ('in_store', 'kiosk', 'call_center', 'direct_mail') )
  -- (c) in-store verb with no store context
  OR ( interaction_type IN ('store_visit', 'kiosk_session') AND store_sk IS NULL );

-- check: touchpoint_profile_fk_orphan | severity: error
-- When resolved, the profile surrogate FK must reference an existing profile.
SELECT t.* FROM ${catalog}.${interaction_schema}.touchpoint t
LEFT JOIN ${catalog}.${customer_schema}.profile p ON t.profile_sk = p.profile_sk
WHERE t.profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: touchpoint_identity_link_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${interaction_schema}.touchpoint t
LEFT JOIN ${catalog}.${customer_schema}.identity_link il ON t.identity_link_sk = il.identity_link_sk
WHERE t.identity_link_sk IS NOT NULL AND il.identity_link_sk IS NULL;

-- check: touchpoint_product_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${interaction_schema}.touchpoint t
LEFT JOIN ${catalog}.${product_schema}.product pr ON t.product_sk = pr.product_sk
WHERE t.product_sk IS NOT NULL AND pr.product_sk IS NULL;

-- check: touchpoint_store_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${interaction_schema}.touchpoint t
LEFT JOIN ${catalog}.${store_schema}.store s ON t.store_sk = s.store_sk
WHERE t.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: touchpoint_calendar_coverage | severity: error
-- Natural date key: every touch date must exist in the fiscal calendar (event_date is an
-- un-minted natural key to fiscal_calendar.date_key, the sales.date_key convention, so a DQ
-- check is the guard rather than a UC FK).
SELECT t.event_date FROM ${catalog}.${interaction_schema}.touchpoint t
LEFT JOIN ${catalog}.${calendar_schema}.fiscal_calendar c ON t.event_date = c.date_key
WHERE c.date_key IS NULL
GROUP BY t.event_date;

-- check: touchpoint_profile_pairing | severity: error
-- Anonymous-first contract: profile_sk and profile_id are populated together (a stitched
-- touch carries its durable customer key; an unresolved touch has both NULL). Neither the
-- surrogate nor the durable key may be set without the other.
SELECT * FROM ${catalog}.${interaction_schema}.touchpoint
WHERE (profile_sk IS NULL) <> (profile_id IS NULL);

-- check: touchpoint_single_reporting_currency | severity: error
-- Monetary values are normalized to the base currency; currency_code must be constant.
SELECT COUNT(DISTINCT currency_code) AS distinct_currencies
FROM ${catalog}.${interaction_schema}.touchpoint
HAVING COUNT(DISTINCT currency_code) > 1;

-- check: touchpoint_resolved_needs_profile | severity: error
-- If an identity link is attached, the resolved profile_id must be populated (a stitched
-- touch carries its durable customer key).
SELECT * FROM ${catalog}.${interaction_schema}.touchpoint
WHERE identity_link_sk IS NOT NULL AND profile_id IS NULL;

-- check: touchpoint_latency_nonneg | severity: error
SELECT * FROM ${catalog}.${interaction_schema}.touchpoint
WHERE latency_seconds IS NOT NULL AND latency_seconds < 0;

-- check: touchpoint_dwell_nonneg | severity: error
-- Engagement depth is a duration, never negative (mirrors touchpoint_latency_nonneg).
SELECT * FROM ${catalog}.${interaction_schema}.touchpoint
WHERE dwell_seconds IS NOT NULL AND dwell_seconds < 0;

-- check: touchpoint_event_date_matches_timestamp | severity: error
-- event_date is the date_key-role natural key and MUST be the calendar date of
-- event_timestamp; the two columns are independent in the DDL, so this hardens the grain
-- (a drift would silently mis-bucket a touch onto the wrong fiscal day).
-- SESSION-TZ ROBUST (M1): event_timestamp is a plain TIMESTAMP (UTC by construction; the repo
-- uses no TIMESTAMP_NTZ), and CAST(ts AS DATE) resolves in the runner's session timezone, which
-- the DQ runner does not pin. A tolerance of one day absorbs the legitimate UTC-vs-session
-- boundary difference for a near-midnight touch, while still catching a real grain drift (a
-- generator/pipeline bug mis-dates by weeks/months, never by a single boundary day), so the
-- check no longer goes red on correct data in a west-of-UTC deploy.
SELECT * FROM ${catalog}.${interaction_schema}.touchpoint
WHERE event_timestamp IS NOT NULL AND ABS(DATEDIFF(CAST(event_timestamp AS DATE), event_date)) > 1;

-- check: touchpoint_rowcount | severity: metric
SELECT COUNT(*) AS touchpoint_rows FROM ${catalog}.${interaction_schema}.touchpoint;

-- check: touchpoint_resolved_rate | severity: metric
-- Share of touches stitched to a known profile (anonymous-first: many rows are unresolved).
SELECT ROUND(AVG(CASE WHEN profile_id IS NOT NULL THEN 1.0 ELSE 0.0 END), 4) AS resolved_rate
FROM ${catalog}.${interaction_schema}.touchpoint;
