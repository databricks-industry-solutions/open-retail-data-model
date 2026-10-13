-- ============================================================
-- ORDM · Outcome Package · Agentic Commerce · comments
-- Version: 0.5
-- Generated: 2026-07-27
-- LLM-generated: true
-- Last reviewed: 2026-08-02
-- ============================================================
-- Column comments, display metadata, and Genie / AI-BI synonyms. Applied after
-- tables and views exist by tools/apply_model_ddl.py. Covers both grains in the
-- package: conversational-shopping gold surfaces and the A2A tables.
-- ============================================================

COMMENT ON TABLE ${catalog}.${ac_schema}.gold_product_discovery_candidate_current IS 'Current product-store candidate surface for organic intent product discovery.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_product_discovery_candidate_current.product_id IS 'Durable product business key.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_product_discovery_candidate_current.product_name IS 'Display name of the discoverable product.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_product_discovery_candidate_current.current_list_price_amount IS 'Current list price amount in the reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_product_discovery_candidate_current.is_available_flag IS 'TRUE when latest inventory indicates the product is buyable for the store context; FALSE when inventory is missing or unavailable.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_product_discovery_candidate_current.latest_inventory_date IS 'Latest inventory snapshot date used to determine availability.';

COMMENT ON TABLE ${catalog}.${ac_schema}.gold_intent_product_discovery_performance IS 'Result-level performance surface for organic intent product discovery, excluding raw prompt text and customer identifiers.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_intent_product_discovery_performance.intent_category IS 'Normalized shopper intent category.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_intent_product_discovery_performance.known_customer_flag IS 'TRUE when the source intent was tied to a resolved customer profile.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_intent_product_discovery_performance.personalization_eligible_flag IS 'TRUE when personalized ranking was allowed at event time.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_intent_product_discovery_performance.result_rank IS 'One-based product rank within the returned result set.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_intent_product_discovery_performance.reason_code IS 'Primary explainability reason for why the product was returned.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_intent_product_discovery_performance.selected_flag IS 'TRUE when the returned product received a select engagement.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_intent_product_discovery_performance.added_to_cart_flag IS 'TRUE when the returned product received an add-to-cart engagement.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_intent_product_discovery_performance.purchased_flag IS 'TRUE when this returned product had any purchase engagement (per-result). Uses a different attribution rule than purchase_net_amount/purchased_units, so a row may be purchased_flag=TRUE yet carry 0 attributed units/amount when the order line was attributed to a sibling result.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_intent_product_discovery_performance.purchase_net_amount IS 'Net purchase amount in the reporting/base currency, with each order line attributed to a SINGLE result (deduped to avoid double-counting across sibling results). 0 on a result whose order line was attributed elsewhere even if purchased_flag is TRUE.';

COMMENT ON TABLE ${catalog}.${ac_schema}.gold_conversational_shopping_session IS 'Session-level performance surface for the consolidated Conversational Shopping Assistant use case.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_session.conversation_session_id IS 'Durable session business key; raw session and conversation identifiers are not exposed.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_session.entry_channel IS 'Surface where the guided shopping conversation started.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_session.primary_intent_category IS 'Representative intent category for the session based on linked discovery intent events.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_session.total_turns IS 'Total structured turns observed in the conversation session.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_session.handoff_flag IS 'TRUE when the session included an associate or support handoff.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_session.fallback_turns IS 'Number of turns where fallback behavior was used.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_session.purchase_net_amount IS 'Net purchase amount attributed to the conversation session, in the reporting/base currency.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_session.currency_code IS 'Reporting/base currency (ISO 4217 alpha-3) for purchase_net_amount; NULL when the session had no purchase.';

COMMENT ON TABLE ${catalog}.${ac_schema}.gold_conversational_shopping_performance IS 'KPI-ready aggregate surface for Conversational Shopping Assistant sessions.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_performance.conversation_sessions IS 'Count of conversational shopping sessions in the reporting grain.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_performance.sessions_reaching_discovery IS 'Count of conversational shopping sessions that reached at least one linked discovery intent.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_performance.assisted_conversion_rate IS 'Share of conversational shopping sessions that reached a purchase.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_performance.handoff_rate IS 'Share of conversational shopping sessions with an associate or support handoff.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_performance.fallback_rate IS 'Share of conversational shopping sessions with at least one fallback turn.';
COMMENT ON COLUMN ${catalog}.${ac_schema}.gold_conversational_shopping_performance.currency_code IS 'Reporting/base currency (ISO 4217 alpha-3) for purchase_net_amount; NULL when the grain had no purchases.';

-- ============================================================
-- Agent-to-Agent (A2A) transactions — Genie / AI-BI synonyms
-- ============================================================

-- ---------- a2a_session ----------
COMMENT ON TABLE ${catalog}.${ac_schema}.a2a_session IS
  'Agent-to-agent (A2A) commerce session tracking. One row per negotiation lifecycle between a buying agent (customer) and a selling agent (retailer). Distinct from human-to-assistant conversational shopping (conversation_session). Synonyms: agent-to-agent session, A2A negotiation, automated negotiation, bot-to-bot session.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_session.session_status IS
  'Lifecycle status of the session. Synonyms: state, phase, session state. Display name: Session Status. Allowed values: initiated, negotiating, agreed, completed, abandoned, failed, expired.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_session.communication_channel IS
  'Communication channel between agents. Synonyms: medium, interface, connection type, agent channel. Display name: Communication Channel. Allowed values: api, marketplace, direct, voice.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_session.initiator_type IS
  'Which side started the session. Synonyms: starter, originator. Display name: Initiator. Allowed values: buyer_agent, seller_agent.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_session.initiated_timestamp IS
  'When the session started. Synonyms: start time, created at, session start. Display name: Started At. Format: UTC timestamp.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_session.completed_timestamp IS
  'When the session concluded. Synonyms: end time, finished at, closed at. Display name: Completed At. Format: UTC timestamp. NULL if still active.';

-- ---------- a2a_agent ----------
COMMENT ON TABLE ${catalog}.${ac_schema}.a2a_agent IS
  'Autonomous agents (buyer-side and seller-side) participating in agent-to-agent commerce. SCD2 dimensional master. Synonyms: AI agent, trading agent, autonomous agent, bot.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_agent.agent_role IS
  'Which side the agent acts for. Synonyms: side, agent side, party. Display name: Agent Role. Allowed values: buyer_agent, seller_agent.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_agent.trust_status IS
  'Verification/trust state of the agent. Synonyms: verification status, trust level. Display name: Trust Status. Allowed values: unverified, verified, suspended, revoked.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_agent.protocol_version IS
  'A2A protocol version the agent speaks. Synonyms: protocol, version, spec version. Display name: Protocol Version.';

-- ---------- a2a_negotiation_event ----------
COMMENT ON TABLE ${catalog}.${ac_schema}.a2a_negotiation_event IS
  'Append-only log of every negotiation step (offer, counter-offer, acceptance, escalation) within an agent-to-agent session. Synonyms: negotiation log, offer history, bid event, negotiation step.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_negotiation_event.event_type IS
  'The negotiation step. Synonyms: step, action, move. Display name: Event Type. Allowed values: price_request, offer, counter_offer, acceptance, rejection, availability_check, escalation_to_human.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_negotiation_event.proposed_price IS
  'Proposed unit price for this step, normalized to the reporting currency. Synonyms: offer price, bid, quote, proposed amount. Display name: Proposed Price. Format: currency.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_negotiation_event.event_timestamp IS
  'When the negotiation step occurred at source. Synonyms: event time, step time, occurred at. Display name: Event Time. Format: UTC timestamp.';

-- ---------- a2a_mandate ----------
COMMENT ON TABLE ${catalog}.${ac_schema}.a2a_mandate IS
  'Delegated purchasing authority a customer grants to a buying agent — spend ceiling, per-transaction limit, approval threshold, allowed categories. SCD2. Synonyms: delegation, authority, purchasing mandate, spend policy, agent budget.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_mandate.spend_ceiling_amount IS
  'Maximum cumulative spend the agent may commit under this mandate. Synonyms: budget, spend cap, total limit. Display name: Spend Ceiling. Format: currency.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_mandate.approval_threshold_amount IS
  'Transaction value at or above which a human must approve. Synonyms: approval limit, human-in-the-loop threshold. Display name: Approval Threshold. Format: currency.';

COMMENT ON COLUMN ${catalog}.${ac_schema}.a2a_mandate.mandate_status IS
  'Lifecycle status of the mandate. Synonyms: state, status. Display name: Mandate Status. Allowed values: active, suspended, revoked, expired.';
