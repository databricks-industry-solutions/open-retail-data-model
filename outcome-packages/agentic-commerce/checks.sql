-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce · data-quality checks
-- Version: 0.5 · Generated: 2026-07-27 · LLM-generated: true · Reviewed: 2026-08-02
-- Each assertion SELECTs violating rows; 0 rows = PASS. `metric` checks report
-- a value and never fail the run. Run by runtime/data-quality/run_checks.py, which
-- substitutes ${catalog} and ${ac_schema}. Covers both grains in the package:
-- conversational-shopping tables and the A2A tables.
-- ============================================================

-- ========== conversation_session ==========

-- check: cs_keys_not_null | severity: error
SELECT * FROM ${catalog}.${ac_schema}.conversation_session
WHERE conversation_session_sk IS NULL
   OR conversation_session_id IS NULL
   OR started_ts IS NULL
   OR started_date IS NULL;

-- check: cs_business_key_unique | severity: error
SELECT conversation_session_id, COUNT(*) AS n
FROM ${catalog}.${ac_schema}.conversation_session
GROUP BY conversation_session_id
HAVING COUNT(*) > 1;

-- check: cs_conversation_id_unique | severity: error
SELECT conversation_id, COUNT(*) AS n
FROM ${catalog}.${ac_schema}.conversation_session
WHERE conversation_id IS NOT NULL
GROUP BY conversation_id
HAVING COUNT(*) > 1;

-- check: cs_profile_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${ac_schema}.conversation_session s
LEFT JOIN ${catalog}.${customer_schema}.profile p ON s.profile_sk = p.profile_sk
WHERE s.profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: cs_store_fk_orphan | severity: error
SELECT s.* FROM ${catalog}.${ac_schema}.conversation_session s
LEFT JOIN ${catalog}.${store_schema}.store st ON s.store_sk = st.store_sk
WHERE s.store_sk IS NOT NULL AND st.store_sk IS NULL;

-- check: cs_entry_channel_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.conversation_session
WHERE entry_channel NOT IN ('web', 'mobile_app', 'kiosk', 'store_associate', 'voice', 'api');

-- check: cs_status_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.conversation_session
WHERE session_status NOT IN ('active', 'completed', 'abandoned', 'escalated');

-- check: cs_resolution_type_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.conversation_session
WHERE resolution_type NOT IN ('product_selected', 'add_to_cart', 'purchase', 'handoff', 'no_resolution', 'abandoned');

-- check: cs_consent_status_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.conversation_session
WHERE consent_status NOT IN ('granted', 'denied', 'unknown');

-- check: cs_timestamp_order | severity: error
SELECT * FROM ${catalog}.${ac_schema}.conversation_session
WHERE ended_ts IS NOT NULL AND ended_ts < started_ts;

-- check: cs_status_ended_ts_consistency | severity: error
-- Emit-once lifecycle invariant (ADR 0034): a session reported as 'completed' has
-- an end timestamp, and an 'active' snapshot has none. ORDM accepts one immutable
-- row per conversation_session_id (cs_business_key_unique) and never a later
-- active->completed correction, so the two states must be internally consistent
-- at the single reporting point. 'abandoned'/'escalated' may end or not.
SELECT * FROM ${catalog}.${ac_schema}.conversation_session
WHERE (session_status = 'completed' AND ended_ts IS NULL)
   OR (session_status = 'active' AND ended_ts IS NOT NULL);

-- check: cs_status_resolution_coherence | severity: warn
-- session_status and resolution_type are overlapping lifecycle signals. Flag the
-- incoherent combinations the glossary rules out: a terminal handoff mirrors
-- 'escalated', and an abandoned resolution mirrors the 'abandoned' status. warn, not
-- error: these are producer-conformance signals, not load-blocking integrity, and
-- other status/resolution pairings are legitimately independent (e.g. a session can
-- reach 'completed' with any of the non-terminal resolutions).
SELECT * FROM ${catalog}.${ac_schema}.conversation_session
WHERE (resolution_type = 'handoff'   AND session_status <> 'escalated')
   OR (resolution_type = 'abandoned' AND session_status <> 'abandoned');

-- check: cs_started_date_consistency | severity: error
SELECT * FROM ${catalog}.${ac_schema}.conversation_session
WHERE started_date <> CAST(started_ts AS DATE);

-- check: cs_rowcount | severity: metric
SELECT COUNT(*) AS conversation_session_rows
FROM ${catalog}.${ac_schema}.conversation_session;

-- ========== assistant_turn_event ==========

-- check: ate_keys_not_null | severity: error
SELECT * FROM ${catalog}.${ac_schema}.assistant_turn_event
WHERE assistant_turn_event_sk IS NULL
   OR assistant_turn_event_id IS NULL
   OR conversation_session_id IS NULL
   OR turn_sequence_number IS NULL
   OR actor_type IS NULL
   OR turn_type IS NULL
   OR event_ts IS NULL
   OR event_date IS NULL;

-- check: ate_business_key_unique | severity: error
SELECT assistant_turn_event_id, COUNT(*) AS n
FROM ${catalog}.${ac_schema}.assistant_turn_event
GROUP BY assistant_turn_event_id
HAVING COUNT(*) > 1;

-- check: ate_turn_sequence_unique | severity: error
SELECT conversation_session_id, turn_sequence_number, COUNT(*) AS n
FROM ${catalog}.${ac_schema}.assistant_turn_event
GROUP BY conversation_session_id, turn_sequence_number
HAVING COUNT(*) > 1;

-- check: ate_session_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${ac_schema}.assistant_turn_event t
LEFT JOIN ${catalog}.${ac_schema}.conversation_session s
  ON t.conversation_session_sk = s.conversation_session_sk
WHERE t.conversation_session_sk IS NOT NULL
  AND s.conversation_session_sk IS NULL;

-- check: ate_session_businesskey_orphan | severity: error
SELECT t.* FROM ${catalog}.${ac_schema}.assistant_turn_event t
LEFT JOIN ${catalog}.${ac_schema}.conversation_session s
  ON t.conversation_session_id = s.conversation_session_id
WHERE s.conversation_session_id IS NULL;

-- check: ate_intent_fk_orphan | severity: error
SELECT t.* FROM ${catalog}.${ac_schema}.assistant_turn_event t
LEFT JOIN ${catalog}.${ac_schema}.discovery_intent_event i
  ON t.discovery_intent_event_sk = i.discovery_intent_event_sk
WHERE t.discovery_intent_event_sk IS NOT NULL
  AND i.discovery_intent_event_sk IS NULL;

-- check: ate_intent_businesskey_orphan | severity: error
SELECT t.* FROM ${catalog}.${ac_schema}.assistant_turn_event t
LEFT JOIN ${catalog}.${ac_schema}.discovery_intent_event i
  ON t.discovery_intent_event_id = i.discovery_intent_event_id
WHERE t.discovery_intent_event_id IS NOT NULL
  AND i.discovery_intent_event_id IS NULL;

-- check: ate_intent_session_consistency | severity: error
-- When a turn links a discovery intent, that intent must belong to the SAME
-- conversation session as the turn (turn -> intent -> session equals turn ->
-- session). The redundant grandparent key (conversation_session_sk) is published
-- and joinable, so assert it agrees with the path through the intent.
SELECT t.* FROM ${catalog}.${ac_schema}.assistant_turn_event t
JOIN ${catalog}.${ac_schema}.discovery_intent_event i
  ON t.discovery_intent_event_sk = i.discovery_intent_event_sk
WHERE t.discovery_intent_event_sk IS NOT NULL
  AND t.conversation_session_sk <> i.conversation_session_sk;

-- check: ate_actor_type_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.assistant_turn_event
WHERE actor_type NOT IN ('shopper', 'assistant', 'associate', 'system');

-- check: ate_turn_type_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.assistant_turn_event
WHERE turn_type NOT IN ('intent_capture', 'recommendation', 'product_comparison', 'availability_check', 'cart_action', 'handoff', 'fallback', 'clarification', 'other');

-- check: ate_action_type_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.assistant_turn_event
WHERE assistant_action_type NOT IN ('none', 'search_products', 'recommend_products', 'compare_products', 'check_availability', 'add_to_cart', 'handoff_to_associate', 'answer_question', 'clarify_intent');

-- check: ate_intent_category_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.assistant_turn_event
WHERE intent_category IS NOT NULL
  AND intent_category NOT IN ('product_search', 'need_based', 'occasion', 'problem_solution', 'compatibility', 'style_fit', 'replenishment', 'comparison', 'unknown');

-- check: ate_confidence_score_range | severity: error
SELECT * FROM ${catalog}.${ac_schema}.assistant_turn_event
WHERE intent_confidence_score IS NOT NULL
  AND intent_confidence_score NOT BETWEEN 0 AND 1;

-- check: ate_event_date_consistency | severity: error
SELECT * FROM ${catalog}.${ac_schema}.assistant_turn_event
WHERE event_date <> CAST(event_ts AS DATE);

-- check: ate_rowcount | severity: metric
SELECT COUNT(*) AS assistant_turn_event_rows
FROM ${catalog}.${ac_schema}.assistant_turn_event;

-- ========== discovery_intent_event ==========

-- check: die_keys_not_null | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_intent_event
WHERE discovery_intent_event_sk IS NULL
   OR discovery_intent_event_id IS NULL
   OR event_ts IS NULL
   OR event_date IS NULL;

-- check: die_business_key_unique | severity: error
SELECT discovery_intent_event_id, COUNT(*) AS n
FROM ${catalog}.${ac_schema}.discovery_intent_event
GROUP BY discovery_intent_event_id
HAVING COUNT(*) > 1;

-- check: die_session_fk_orphan | severity: error
SELECT i.* FROM ${catalog}.${ac_schema}.discovery_intent_event i
LEFT JOIN ${catalog}.${ac_schema}.conversation_session s
  ON i.conversation_session_sk = s.conversation_session_sk
WHERE i.conversation_session_sk IS NOT NULL
  AND s.conversation_session_sk IS NULL;

-- check: die_session_businesskey_orphan | severity: error
SELECT i.* FROM ${catalog}.${ac_schema}.discovery_intent_event i
LEFT JOIN ${catalog}.${ac_schema}.conversation_session s
  ON i.conversation_session_id = s.conversation_session_id
WHERE i.conversation_session_id IS NOT NULL
  AND s.conversation_session_id IS NULL;

-- check: die_profile_fk_orphan | severity: error
SELECT i.* FROM ${catalog}.${ac_schema}.discovery_intent_event i
LEFT JOIN ${catalog}.${customer_schema}.profile p ON i.profile_sk = p.profile_sk
WHERE i.profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: die_store_fk_orphan | severity: error
SELECT i.* FROM ${catalog}.${ac_schema}.discovery_intent_event i
LEFT JOIN ${catalog}.${store_schema}.store s ON i.store_sk = s.store_sk
WHERE i.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: die_channel_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_intent_event
WHERE discovery_channel NOT IN ('web', 'mobile_app', 'kiosk', 'store_associate', 'voice', 'api');

-- check: die_intent_category_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_intent_event
WHERE intent_category NOT IN ('product_search', 'need_based', 'occasion', 'problem_solution', 'compatibility', 'style_fit', 'replenishment', 'comparison', 'unknown');

-- check: die_consent_status_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_intent_event
WHERE consent_status NOT IN ('granted', 'denied', 'unknown');

-- check: die_confidence_score_range | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_intent_event
WHERE intent_confidence_score IS NOT NULL
  AND intent_confidence_score NOT BETWEEN 0 AND 1;

-- check: die_event_date_consistency | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_intent_event
WHERE event_date <> CAST(event_ts AS DATE);

-- check: die_rowcount | severity: metric
SELECT COUNT(*) AS discovery_intent_event_rows
FROM ${catalog}.${ac_schema}.discovery_intent_event;

-- ========== discovery_result_event ==========

-- check: dre_keys_not_null | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_result_event
WHERE discovery_result_event_sk IS NULL
   OR discovery_result_event_id IS NULL
   OR discovery_intent_event_id IS NULL
   OR product_id IS NULL
   OR result_rank IS NULL
   OR event_ts IS NULL
   OR event_date IS NULL;

-- check: dre_business_key_unique | severity: error
SELECT discovery_result_event_id, COUNT(*) AS n
FROM ${catalog}.${ac_schema}.discovery_result_event
GROUP BY discovery_result_event_id
HAVING COUNT(*) > 1;

-- check: dre_rank_unique_per_intent | severity: error
SELECT discovery_intent_event_id, result_rank, COUNT(*) AS n
FROM ${catalog}.${ac_schema}.discovery_result_event
GROUP BY discovery_intent_event_id, result_rank
HAVING COUNT(*) > 1;

-- check: dre_intent_fk_orphan | severity: error
SELECT r.* FROM ${catalog}.${ac_schema}.discovery_result_event r
LEFT JOIN ${catalog}.${ac_schema}.discovery_intent_event i
  ON r.discovery_intent_event_sk = i.discovery_intent_event_sk
WHERE r.discovery_intent_event_sk IS NOT NULL
  AND i.discovery_intent_event_sk IS NULL;

-- check: dre_intent_businesskey_orphan | severity: error
SELECT r.* FROM ${catalog}.${ac_schema}.discovery_result_event r
LEFT JOIN ${catalog}.${ac_schema}.discovery_intent_event i
  ON r.discovery_intent_event_id = i.discovery_intent_event_id
WHERE i.discovery_intent_event_id IS NULL;

-- check: dre_product_fk_orphan | severity: error
SELECT r.* FROM ${catalog}.${ac_schema}.discovery_result_event r
LEFT JOIN ${catalog}.${product_schema}.product p ON r.product_sk = p.product_sk
WHERE r.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: dre_store_fk_orphan | severity: error
SELECT r.* FROM ${catalog}.${ac_schema}.discovery_result_event r
LEFT JOIN ${catalog}.${store_schema}.store s ON r.store_sk = s.store_sk
WHERE r.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: dre_scores_range | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_result_event
WHERE (retrieval_score IS NOT NULL AND retrieval_score NOT BETWEEN 0 AND 1)
   OR (ranking_score IS NOT NULL AND ranking_score NOT BETWEEN 0 AND 1)
   OR (personalization_score IS NOT NULL AND personalization_score NOT BETWEEN 0 AND 1)
   OR (availability_score IS NOT NULL AND availability_score NOT BETWEEN 0 AND 1);

-- check: dre_reason_code_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_result_event
WHERE reason_code NOT IN ('lexical_match', 'semantic_match', 'purchase_affinity', 'substitute', 'complement', 'trending', 'available_nearby', 'business_rule');

-- check: dre_event_date_consistency | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_result_event
WHERE event_date <> CAST(event_ts AS DATE);

-- check: dre_single_currency | severity: error
SELECT 'discovery_result_event' AS table_name, COUNT(DISTINCT currency_code) AS currencies
FROM ${catalog}.${ac_schema}.discovery_result_event
WHERE list_price_amount IS NOT NULL
HAVING COUNT(DISTINCT currency_code) > 1
    OR SUM(CASE WHEN currency_code IS NULL THEN 1 ELSE 0 END) > 0;

-- check: dre_rowcount | severity: metric
SELECT COUNT(*) AS discovery_result_event_rows
FROM ${catalog}.${ac_schema}.discovery_result_event;

-- ========== discovery_engagement_event ==========

-- check: dee_keys_not_null | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_engagement_event
WHERE discovery_engagement_event_sk IS NULL
   OR discovery_engagement_event_id IS NULL
   OR discovery_result_event_id IS NULL
   OR discovery_intent_event_id IS NULL
   OR product_id IS NULL
   OR engagement_type IS NULL
   OR engagement_ts IS NULL
   OR engagement_date IS NULL;

-- check: dee_business_key_unique | severity: error
SELECT discovery_engagement_event_id, COUNT(*) AS n
FROM ${catalog}.${ac_schema}.discovery_engagement_event
GROUP BY discovery_engagement_event_id
HAVING COUNT(*) > 1;

-- check: dee_result_fk_orphan | severity: error
SELECT e.* FROM ${catalog}.${ac_schema}.discovery_engagement_event e
LEFT JOIN ${catalog}.${ac_schema}.discovery_result_event r
  ON e.discovery_result_event_sk = r.discovery_result_event_sk
WHERE e.discovery_result_event_sk IS NOT NULL
  AND r.discovery_result_event_sk IS NULL;

-- check: dee_result_businesskey_orphan | severity: error
SELECT e.* FROM ${catalog}.${ac_schema}.discovery_engagement_event e
LEFT JOIN ${catalog}.${ac_schema}.discovery_result_event r
  ON e.discovery_result_event_id = r.discovery_result_event_id
WHERE r.discovery_result_event_id IS NULL;

-- check: dee_intent_fk_orphan | severity: error
SELECT e.* FROM ${catalog}.${ac_schema}.discovery_engagement_event e
LEFT JOIN ${catalog}.${ac_schema}.discovery_intent_event i
  ON e.discovery_intent_event_sk = i.discovery_intent_event_sk
WHERE e.discovery_intent_event_sk IS NOT NULL
  AND i.discovery_intent_event_sk IS NULL;

-- check: dee_result_intent_consistency | severity: error
-- The engaged result's parent intent must equal the engagement's own intent
-- (engagement -> result -> intent equals engagement -> intent). Both grandparent
-- keys are published on the row, so assert the redundant intent id agrees with
-- the path through the result rather than trusting them to be set consistently.
SELECT e.* FROM ${catalog}.${ac_schema}.discovery_engagement_event e
JOIN ${catalog}.${ac_schema}.discovery_result_event r
  ON e.discovery_result_event_id = r.discovery_result_event_id
WHERE e.discovery_intent_event_id <> r.discovery_intent_event_id;

-- check: dee_profile_fk_orphan | severity: error
SELECT e.* FROM ${catalog}.${ac_schema}.discovery_engagement_event e
LEFT JOIN ${catalog}.${customer_schema}.profile p ON e.profile_sk = p.profile_sk
WHERE e.profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: dee_product_fk_orphan | severity: error
SELECT e.* FROM ${catalog}.${ac_schema}.discovery_engagement_event e
LEFT JOIN ${catalog}.${product_schema}.product p ON e.product_sk = p.product_sk
WHERE e.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: dee_store_fk_orphan | severity: error
SELECT e.* FROM ${catalog}.${ac_schema}.discovery_engagement_event e
LEFT JOIN ${catalog}.${store_schema}.store s ON e.store_sk = s.store_sk
WHERE e.store_sk IS NOT NULL AND s.store_sk IS NULL;

-- check: dee_order_line_fk_orphan | severity: error
SELECT e.* FROM ${catalog}.${ac_schema}.discovery_engagement_event e
LEFT JOIN ${catalog}.${order_schema}.customer_order_line o ON e.order_line_sk = o.order_line_sk
WHERE e.order_line_sk IS NOT NULL AND o.order_line_sk IS NULL;

-- check: dee_type_domain | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_engagement_event
WHERE engagement_type NOT IN ('view', 'select', 'add_to_cart', 'purchase', 'dismiss');

-- check: dee_nonnegative_values | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_engagement_event
WHERE (quantity IS NOT NULL AND quantity < 0)
   OR (net_amount IS NOT NULL AND net_amount < 0)
   OR (attribution_window_minutes IS NOT NULL AND attribution_window_minutes < 0);

-- check: dee_purchase_has_amount | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_engagement_event
WHERE engagement_type = 'purchase'
  AND (net_amount IS NULL OR currency_code IS NULL);

-- check: dee_engagement_date_consistency | severity: error
SELECT * FROM ${catalog}.${ac_schema}.discovery_engagement_event
WHERE engagement_date <> CAST(engagement_ts AS DATE);

-- check: dee_single_currency | severity: error
SELECT 'discovery_engagement_event' AS table_name, COUNT(DISTINCT currency_code) AS currencies
FROM ${catalog}.${ac_schema}.discovery_engagement_event
WHERE net_amount IS NOT NULL
HAVING COUNT(DISTINCT currency_code) > 1
    OR SUM(CASE WHEN currency_code IS NULL THEN 1 ELSE 0 END) > 0;

-- check: dee_rowcount | severity: metric
SELECT COUNT(*) AS discovery_engagement_event_rows
FROM ${catalog}.${ac_schema}.discovery_engagement_event;

-- ========== gold views ==========

-- check: agentic_gold_no_raw_pii | severity: error
SELECT table_name, column_name
FROM ${catalog}.information_schema.columns
WHERE table_schema = '${ac_schema}'
  AND table_name IN ('gold_product_discovery_candidate_current',
                     'gold_intent_product_discovery_performance',
                     'gold_conversational_shopping_session',
                     'gold_conversational_shopping_performance')
  AND column_name IN ('profile_id', 'session_id', 'conversation_id', 'intent_text_hash',
                      'loyalty_id', 'household_id', 'first_name', 'middle_name',
                      'last_name', 'date_of_birth', 'contact_value');

-- check: gpd_candidate_one_row_per_product_store | severity: error
SELECT product_id, store_id, COUNT(*) AS n
FROM ${catalog}.${ac_schema}.gold_product_discovery_candidate_current
GROUP BY product_id, store_id
HAVING COUNT(*) > 1;

-- check: gpd_candidate_price_nonnegative | severity: error
SELECT * FROM ${catalog}.${ac_schema}.gold_product_discovery_candidate_current
WHERE current_list_price_amount IS NOT NULL
  AND current_list_price_amount < 0;

-- check: gipdp_rank_positive | severity: error
SELECT * FROM ${catalog}.${ac_schema}.gold_intent_product_discovery_performance
WHERE result_rank <= 0;

-- check: gipdp_scores_range | severity: error
SELECT * FROM ${catalog}.${ac_schema}.gold_intent_product_discovery_performance
WHERE (retrieval_score IS NOT NULL AND retrieval_score NOT BETWEEN 0 AND 1)
   OR (ranking_score IS NOT NULL AND ranking_score NOT BETWEEN 0 AND 1)
   OR (personalization_score IS NOT NULL AND personalization_score NOT BETWEEN 0 AND 1)
   OR (availability_score IS NOT NULL AND availability_score NOT BETWEEN 0 AND 1);

-- check: gipdp_result_count | severity: metric
SELECT COUNT(*) AS discovery_performance_rows
FROM ${catalog}.${ac_schema}.gold_intent_product_discovery_performance;

-- check: gipdp_selection_rate | severity: metric
SELECT ROUND(AVG(CASE WHEN selected_flag THEN 1.0 ELSE 0.0 END), 4) AS selected_result_rate
FROM ${catalog}.${ac_schema}.gold_intent_product_discovery_performance;

-- check: gcsa_session_one_row_per_session | severity: error
SELECT conversation_session_id, COUNT(*) AS n
FROM ${catalog}.${ac_schema}.gold_conversational_shopping_session
GROUP BY conversation_session_id
HAVING COUNT(*) > 1;

-- check: gcsa_session_nonnegative_measures | severity: error
SELECT * FROM ${catalog}.${ac_schema}.gold_conversational_shopping_session
WHERE total_turns < 0
   OR shopper_turns < 0
   OR assistant_turns < 0
   OR recommendation_turns < 0
   OR fallback_turns < 0
   OR discovery_intent_count < 0
   OR purchased_units < 0
   OR purchase_net_amount < 0;

-- check: gcsa_performance_rates_range | severity: error
SELECT * FROM ${catalog}.${ac_schema}.gold_conversational_shopping_performance
WHERE (selection_rate IS NOT NULL AND selection_rate NOT BETWEEN 0 AND 1)
   OR (add_to_cart_rate IS NOT NULL AND add_to_cart_rate NOT BETWEEN 0 AND 1)
   OR (assisted_conversion_rate IS NOT NULL AND assisted_conversion_rate NOT BETWEEN 0 AND 1)
   OR (handoff_rate IS NOT NULL AND handoff_rate NOT BETWEEN 0 AND 1)
   OR (fallback_rate IS NOT NULL AND fallback_rate NOT BETWEEN 0 AND 1);

-- check: gcsa_session_count | severity: metric
SELECT COUNT(*) AS conversational_shopping_session_rows
FROM ${catalog}.${ac_schema}.gold_conversational_shopping_session;

-- check: gcsa_assisted_conversion_rate | severity: metric
SELECT ROUND(AVG(CASE WHEN purchased_flag THEN 1.0 ELSE 0.0 END), 4) AS assisted_conversion_rate
FROM ${catalog}.${ac_schema}.gold_conversational_shopping_session;

-- ============================================================
-- Agent-to-Agent (A2A) transactions
-- ============================================================

-- ---------- a2a_session ----------

-- check: a2a_session_keys_not_null | severity: error
-- Surrogate key, business key, status, channel, initiator, and initiated timestamp are mandatory.
SELECT * FROM ${catalog}.${ac_schema}.a2a_session
WHERE a2a_session_sk IS NULL OR a2a_session_id IS NULL
   OR session_status IS NULL OR communication_channel IS NULL
   OR initiator_type IS NULL OR initiated_timestamp IS NULL;

-- check: a2a_session_business_key_unique | severity: error
-- Each session business key must be unique (no SCD2; one row per session).
SELECT a2a_session_id, COUNT(*) AS row_count
FROM ${catalog}.${ac_schema}.a2a_session
GROUP BY a2a_session_id
HAVING COUNT(*) > 1;

-- check: a2a_session_status_domain | severity: error
-- session_status must be within the declared enum.
SELECT * FROM ${catalog}.${ac_schema}.a2a_session
WHERE session_status NOT IN ('initiated', 'negotiating', 'agreed', 'completed', 'abandoned', 'failed', 'expired');

-- check: a2a_session_communication_channel_domain | severity: error
-- communication_channel must be within the declared enum.
SELECT * FROM ${catalog}.${ac_schema}.a2a_session
WHERE communication_channel NOT IN ('api', 'marketplace', 'direct', 'voice');

-- check: a2a_session_initiator_type_domain | severity: error
-- initiator_type must be within the declared enum.
SELECT * FROM ${catalog}.${ac_schema}.a2a_session
WHERE initiator_type NOT IN ('buyer_agent', 'seller_agent');

-- check: a2a_session_buyer_profile_fk_orphan | severity: error
-- Every session with a buyer must reference an existing profile (by surrogate FK).
SELECT s.* FROM ${catalog}.${ac_schema}.a2a_session s
LEFT JOIN ${catalog}.${customer_schema}.profile p ON s.buyer_profile_sk = p.profile_sk
WHERE s.buyer_profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: a2a_session_store_fk_orphan | severity: error
-- Every session with a store must reference an existing store.
SELECT s.* FROM ${catalog}.${ac_schema}.a2a_session s
LEFT JOIN ${catalog}.${store_schema}.store st ON s.store_sk = st.store_sk
WHERE s.store_sk IS NOT NULL AND st.store_sk IS NULL;

-- check: a2a_session_product_fk_orphan | severity: error
-- Every session with a product must reference an existing product.
SELECT s.* FROM ${catalog}.${ac_schema}.a2a_session s
LEFT JOIN ${catalog}.${product_schema}.product p ON s.product_sk = p.product_sk
WHERE s.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: a2a_session_completed_timestamp_consistency | severity: error
-- Completed sessions must have a completed_timestamp; active sessions must not.
SELECT * FROM ${catalog}.${ac_schema}.a2a_session
WHERE (session_status IN ('completed', 'abandoned', 'failed', 'expired') AND completed_timestamp IS NULL)
   OR (session_status IN ('initiated', 'negotiating', 'agreed') AND completed_timestamp IS NOT NULL);

-- check: a2a_session_timestamp_order | severity: error
-- completed_timestamp, when set, must be after initiated_timestamp.
SELECT * FROM ${catalog}.${ac_schema}.a2a_session
WHERE completed_timestamp IS NOT NULL
  AND completed_timestamp <= initiated_timestamp;

-- check: a2a_session_last_activity_bounds | severity: error
-- last_activity_timestamp, when set, must fall on or after initiated_timestamp
-- and (when the session has ended) on or before completed_timestamp.
SELECT * FROM ${catalog}.${ac_schema}.a2a_session
WHERE last_activity_timestamp IS NOT NULL
  AND (last_activity_timestamp < initiated_timestamp
    OR (completed_timestamp IS NOT NULL AND last_activity_timestamp > completed_timestamp));

-- check: a2a_session_audit_block_present | severity: warn
-- Audit provenance should be populated: record_source and load_timestamp
-- identify where each row came from and when it landed.
SELECT * FROM ${catalog}.${ac_schema}.a2a_session
WHERE record_source IS NULL OR load_timestamp IS NULL;

-- check: a2a_session_initiating_agent_fk_orphan | severity: error
-- Every session with an initiating agent must reference an existing agent.
SELECT s.* FROM ${catalog}.${ac_schema}.a2a_session s
LEFT JOIN ${catalog}.${ac_schema}.a2a_agent a ON s.initiating_agent_sk = a.a2a_agent_sk
WHERE s.initiating_agent_sk IS NOT NULL AND a.a2a_agent_sk IS NULL;

-- check: a2a_session_responding_agent_fk_orphan | severity: error
-- Every session with a responding agent must reference an existing agent.
SELECT s.* FROM ${catalog}.${ac_schema}.a2a_session s
LEFT JOIN ${catalog}.${ac_schema}.a2a_agent a ON s.responding_agent_sk = a.a2a_agent_sk
WHERE s.responding_agent_sk IS NOT NULL AND a.a2a_agent_sk IS NULL;

-- check: a2a_session_agents_distinct | severity: warn
-- The two agents on a session must be different rows. A self-paired session
-- (one agent as both initiator and responder) would double-count that agent in
-- gold_a2a_agent_scorecard, which UNION ALLs the two roles. warn: hardens the
-- spine without blocking on a data anomaly.
SELECT * FROM ${catalog}.${ac_schema}.a2a_session
WHERE initiating_agent_sk IS NOT NULL AND responding_agent_sk IS NOT NULL
  AND initiating_agent_sk = responding_agent_sk;

-- check: a2a_session_agents_opposite_side | severity: warn
-- The two agents must sit on opposite sides — one buyer_agent, one seller_agent
-- (the A2A model is a buying agent negotiating with a selling agent). Joins the
-- current a2a_agent version for each side's role. warn, not error: an agent's
-- role is SCD2 and could in principle change, so this is a consistency signal.
SELECT s.* FROM ${catalog}.${ac_schema}.a2a_session s
JOIN ${catalog}.${ac_schema}.a2a_agent ia
  ON s.initiating_agent_sk = ia.a2a_agent_sk AND ia.is_current = TRUE
JOIN ${catalog}.${ac_schema}.a2a_agent ra
  ON s.responding_agent_sk = ra.a2a_agent_sk AND ra.is_current = TRUE
WHERE ia.agent_role = ra.agent_role;

-- ---------- a2a_agent ----------

-- check: a2a_agent_keys_not_null | severity: error
-- Surrogate key, business key, role, trust status, and SCD2 columns are mandatory.
SELECT * FROM ${catalog}.${ac_schema}.a2a_agent
WHERE a2a_agent_sk IS NULL OR a2a_agent_id IS NULL
   OR agent_role IS NULL OR trust_status IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: a2a_agent_business_key_unique_current | severity: error
-- A business key must resolve to at most one current version.
SELECT a2a_agent_id, COUNT(*) AS current_versions
FROM ${catalog}.${ac_schema}.a2a_agent
WHERE is_current = true
GROUP BY a2a_agent_id
HAVING COUNT(*) > 1;

-- check: a2a_agent_role_domain | severity: error
-- agent_role must be within the declared enum.
SELECT * FROM ${catalog}.${ac_schema}.a2a_agent
WHERE agent_role NOT IN ('buyer_agent', 'seller_agent');

-- check: a2a_agent_trust_status_domain | severity: error
-- trust_status must be within the declared enum.
SELECT * FROM ${catalog}.${ac_schema}.a2a_agent
WHERE trust_status NOT IN ('unverified', 'verified', 'suspended', 'revoked');

-- check: a2a_agent_role_representation_consistency | severity: error
-- A buyer agent represents a profile (not a store); a seller agent represents
-- a store (not a profile). Exactly the matching representation must be set.
SELECT * FROM ${catalog}.${ac_schema}.a2a_agent
WHERE (agent_role = 'buyer_agent'  AND (represented_profile_id IS NULL OR represented_store_id IS NOT NULL))
   OR (agent_role = 'seller_agent' AND (represented_store_id  IS NULL OR represented_profile_id IS NOT NULL));

-- check: a2a_agent_scd2_current_open | severity: error
-- The current version must have an open (NULL) end date; non-current must be closed.
SELECT * FROM ${catalog}.${ac_schema}.a2a_agent
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: a2a_agent_scd2_date_order | severity: error
-- When set, the end date must be strictly after the start date.
SELECT * FROM ${catalog}.${ac_schema}.a2a_agent
WHERE effective_to_date IS NOT NULL
  AND effective_to_date <= effective_from_date;

-- check: a2a_agent_represented_profile_orphan | severity: warn
-- Soft (non-FK) registry link: a represented buyer profile should exist in the
-- customer core. warn, not error — an agent may be registered before its
-- principal is resolved in-model (see a2a_agent.sql header).
SELECT a.* FROM ${catalog}.${ac_schema}.a2a_agent a
LEFT JOIN (SELECT DISTINCT profile_id FROM ${catalog}.${customer_schema}.profile) p
  ON a.represented_profile_id = p.profile_id
WHERE a.represented_profile_id IS NOT NULL AND p.profile_id IS NULL;

-- check: a2a_agent_represented_store_orphan | severity: warn
-- Soft (non-FK) registry link: a represented store should exist in the store core.
SELECT a.* FROM ${catalog}.${ac_schema}.a2a_agent a
LEFT JOIN (SELECT DISTINCT store_id FROM ${catalog}.${store_schema}.store) s
  ON a.represented_store_id = s.store_id
WHERE a.represented_store_id IS NOT NULL AND s.store_id IS NULL;

-- ---------- a2a_negotiation_event ----------

-- check: a2a_negotiation_event_keys_not_null | severity: error
-- Surrogate key, business key, the mandatory parent-session link, event type,
-- the ordering sequence, and both timestamps are mandatory. The session link and
-- event_sequence are enforced NOT NULL in DDL too; asserted here so a parentless
-- or unordered event fails loudly rather than dropping out of / misordering the
-- gold views (all LEFT JOIN from a2a_session; event_sequence anchors first-offer
-- and acceptance de-dup in gold_a2a_session_summary).
SELECT * FROM ${catalog}.${ac_schema}.a2a_negotiation_event
WHERE a2a_negotiation_event_sk IS NULL OR a2a_negotiation_event_id IS NULL
   OR a2a_session_sk IS NULL OR a2a_session_id IS NULL
   OR event_type IS NULL OR event_sequence IS NULL
   OR event_timestamp IS NULL OR ingest_timestamp IS NULL;

-- check: a2a_negotiation_event_business_key_unique | severity: error
-- Each event business key must be unique (append-only; one row per event).
SELECT a2a_negotiation_event_id, COUNT(*) AS row_count
FROM ${catalog}.${ac_schema}.a2a_negotiation_event
GROUP BY a2a_negotiation_event_id
HAVING COUNT(*) > 1;

-- check: a2a_negotiation_event_type_domain | severity: error
-- event_type must be within the declared enum.
SELECT * FROM ${catalog}.${ac_schema}.a2a_negotiation_event
WHERE event_type NOT IN ('price_request', 'offer', 'counter_offer', 'acceptance', 'rejection', 'availability_check', 'escalation_to_human');

-- check: a2a_negotiation_event_session_fk_orphan | severity: error
-- Every event must reference an existing session (by surrogate FK).
SELECT e.* FROM ${catalog}.${ac_schema}.a2a_negotiation_event e
LEFT JOIN ${catalog}.${ac_schema}.a2a_session s ON e.a2a_session_sk = s.a2a_session_sk
WHERE e.a2a_session_sk IS NOT NULL AND s.a2a_session_sk IS NULL;

-- check: a2a_negotiation_event_agent_fk_orphan | severity: error
-- Every event with an emitting agent must reference an existing agent.
SELECT e.* FROM ${catalog}.${ac_schema}.a2a_negotiation_event e
LEFT JOIN ${catalog}.${ac_schema}.a2a_agent a ON e.a2a_agent_sk = a.a2a_agent_sk
WHERE e.a2a_agent_sk IS NOT NULL AND a.a2a_agent_sk IS NULL;

-- check: a2a_negotiation_event_product_fk_orphan | severity: error
-- Every event with a product must reference an existing product.
SELECT e.* FROM ${catalog}.${ac_schema}.a2a_negotiation_event e
LEFT JOIN ${catalog}.${product_schema}.product p ON e.product_sk = p.product_sk
WHERE e.product_sk IS NOT NULL AND p.product_sk IS NULL;

-- check: a2a_negotiation_event_single_currency | severity: error
-- Monetary fact: all priced events must carry the single reporting currency.
-- Replace 'USD' via ${base_currency} at deploy; the check asserts consistency,
-- not a specific code, by flagging any second distinct currency among priced rows.
SELECT * FROM ${catalog}.${ac_schema}.a2a_negotiation_event
WHERE proposed_price IS NOT NULL
  AND currency_code IS NOT NULL
  AND currency_code <> (
    SELECT MIN(currency_code) FROM ${catalog}.${ac_schema}.a2a_negotiation_event
    WHERE proposed_price IS NOT NULL AND currency_code IS NOT NULL
  );

-- check: a2a_negotiation_event_price_currency_paired | severity: error
-- A proposed_price requires a currency_code (and vice versa) — no orphan money.
SELECT * FROM ${catalog}.${ac_schema}.a2a_negotiation_event
WHERE (proposed_price IS NOT NULL AND currency_code IS NULL)
   OR (proposed_price IS NULL AND currency_code IS NOT NULL);

-- check: a2a_negotiation_event_nonneg | severity: error
-- Proposed price and quantity, when set, must be non-negative.
SELECT * FROM ${catalog}.${ac_schema}.a2a_negotiation_event
WHERE (proposed_price IS NOT NULL AND proposed_price < 0)
   OR (proposed_quantity IS NOT NULL AND proposed_quantity < 0);

-- check: a2a_negotiation_event_sequence_unique | severity: warn
-- event_sequence is documented as the monotonic step number within a session;
-- two events sharing a sequence within one session break replay/ordering.
SELECT a2a_session_sk, event_sequence, COUNT(*) AS rows_at_sequence
FROM ${catalog}.${ac_schema}.a2a_negotiation_event
WHERE event_sequence IS NOT NULL
GROUP BY a2a_session_sk, event_sequence
HAVING COUNT(*) > 1;

-- check: a2a_negotiation_event_single_acceptance | severity: error
-- A session concludes with at most one acceptance. More than one would fan out
-- gold_a2a_session_summary's agreed-terms join and double-count the session.
SELECT a2a_session_sk, COUNT(*) AS acceptance_count
FROM ${catalog}.${ac_schema}.a2a_negotiation_event
WHERE event_type = 'acceptance'
GROUP BY a2a_session_sk
HAVING COUNT(*) > 1;

-- check: a2a_session_completed_has_acceptance | severity: warn
-- A completed session should have an acceptance event behind it — completion is
-- the terminal lifecycle state a deal reaches after its terms are accepted. If a
-- session reads 'completed' with no acceptance in the event log, the funnel's
-- completed count (gold_a2a_negotiation_funnel, from session_status) can exceed
-- reached_agreed (from the event log). warn, not error: the session's mutable
-- status and the append-only log can legitimately lag at read time, so this is a
-- consistency signal rather than a hard invariant.
SELECT s.a2a_session_sk, s.a2a_session_id
FROM ${catalog}.${ac_schema}.a2a_session s
LEFT JOIN (
  SELECT DISTINCT a2a_session_sk
  FROM ${catalog}.${ac_schema}.a2a_negotiation_event
  WHERE event_type = 'acceptance'
) a ON s.a2a_session_sk = a.a2a_session_sk
WHERE s.session_status = 'completed' AND a.a2a_session_sk IS NULL;

-- ---------- a2a_mandate ----------

-- check: a2a_mandate_keys_not_null | severity: error
-- Surrogate key, business key, status, and SCD2 columns are mandatory.
SELECT * FROM ${catalog}.${ac_schema}.a2a_mandate
WHERE a2a_mandate_sk IS NULL OR a2a_mandate_id IS NULL
   OR mandate_status IS NULL
   OR effective_from_date IS NULL OR is_current IS NULL;

-- check: a2a_mandate_business_key_unique_current | severity: error
-- A business key must resolve to at most one current version.
SELECT a2a_mandate_id, COUNT(*) AS current_versions
FROM ${catalog}.${ac_schema}.a2a_mandate
WHERE is_current = true
GROUP BY a2a_mandate_id
HAVING COUNT(*) > 1;

-- check: a2a_mandate_status_domain | severity: error
-- mandate_status must be within the declared enum.
SELECT * FROM ${catalog}.${ac_schema}.a2a_mandate
WHERE mandate_status NOT IN ('active', 'suspended', 'revoked', 'expired');

-- check: a2a_mandate_profile_fk_orphan | severity: error
-- Every mandate with a granting customer must reference an existing profile.
SELECT m.* FROM ${catalog}.${ac_schema}.a2a_mandate m
LEFT JOIN ${catalog}.${customer_schema}.profile p ON m.buyer_profile_sk = p.profile_sk
WHERE m.buyer_profile_sk IS NOT NULL AND p.profile_sk IS NULL;

-- check: a2a_mandate_agent_fk_orphan | severity: error
-- Every mandate with a governed agent must reference an existing agent.
SELECT m.* FROM ${catalog}.${ac_schema}.a2a_mandate m
LEFT JOIN ${catalog}.${ac_schema}.a2a_agent a ON m.a2a_agent_sk = a.a2a_agent_sk
WHERE m.a2a_agent_sk IS NOT NULL AND a.a2a_agent_sk IS NULL;

-- check: a2a_mandate_consent_orphan | severity: warn
-- Soft (non-FK) authorization link: the consent authorizing a mandate should
-- exist in the customer core. warn, not error — consent is SCD2 and the link is
-- a durable business key by design (ADR 0030), so a mandate may reference a
-- consent decision not yet loaded in-model. Deduped on the durable consent_id.
SELECT m.* FROM ${catalog}.${ac_schema}.a2a_mandate m
LEFT JOIN (SELECT DISTINCT consent_id FROM ${catalog}.${customer_schema}.consent) c
  ON m.consent_id = c.consent_id
WHERE m.consent_id IS NOT NULL AND c.consent_id IS NULL;

-- check: a2a_mandate_single_currency | severity: error
-- Monetary master: all mandates with amounts must carry the single reporting currency.
SELECT * FROM ${catalog}.${ac_schema}.a2a_mandate
WHERE currency_code IS NOT NULL
  AND currency_code <> (
    SELECT MIN(currency_code) FROM ${catalog}.${ac_schema}.a2a_mandate
    WHERE currency_code IS NOT NULL
  );

-- check: a2a_mandate_amounts_nonneg | severity: error
-- Spend ceiling, per-transaction limit, and approval threshold, when set, must be non-negative.
SELECT * FROM ${catalog}.${ac_schema}.a2a_mandate
WHERE (spend_ceiling_amount IS NOT NULL AND spend_ceiling_amount < 0)
   OR (per_transaction_limit_amount IS NOT NULL AND per_transaction_limit_amount < 0)
   OR (approval_threshold_amount IS NOT NULL AND approval_threshold_amount < 0);

-- check: a2a_mandate_limit_within_ceiling | severity: warn
-- Cross-field ordering guardrail: a single transaction cannot exceed the
-- cumulative spend ceiling, so per_transaction_limit_amount must not be greater
-- than spend_ceiling_amount when both are set. warn, not error: mandates are
-- customer-authored guardrails and a source system may not enforce the ordering,
-- so this flags an incoherent mandate without blocking the load.
SELECT * FROM ${catalog}.${ac_schema}.a2a_mandate
WHERE spend_ceiling_amount IS NOT NULL
  AND per_transaction_limit_amount IS NOT NULL
  AND per_transaction_limit_amount > spend_ceiling_amount;

-- check: a2a_mandate_scd2_current_open | severity: error
-- The current version must have an open (NULL) end date; non-current must be closed.
SELECT * FROM ${catalog}.${ac_schema}.a2a_mandate
WHERE (is_current = true  AND effective_to_date IS NOT NULL)
   OR (is_current = false AND effective_to_date IS NULL);

-- check: a2a_mandate_scd2_date_order | severity: error
-- When set, the end date must be strictly after the start date.
SELECT * FROM ${catalog}.${ac_schema}.a2a_mandate
WHERE effective_to_date IS NOT NULL
  AND effective_to_date <= effective_from_date;
