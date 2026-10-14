# Agentic Commerce — Business Glossary

> Status: ✅ Published (0.5) · Last reviewed: 2026-10-07

Business terms for the ORDM outcome package **Agentic Commerce** (Unity Catalog schema `agentic_commerce`). Definitions are vendor-neutral and follow the ORDM [data model standards](../../docs/data-model-standards.md).

## Scope

The package spans two independent grains that share the `agentic_commerce` schema but never share a spine table:

- **Human-to-assistant conversational shopping** (**Intent Product Discovery** and **Conversational Shopping Assistant**) — a person interacting with a shopping assistant across web, mobile, kiosk, voice, associate, or API surfaces. Modeled by the `conversation_session` / `assistant_turn_event` / `discovery_*` tables.
- **Autonomous agent-to-agent (A2A) commerce** — a buyer's AI agent negotiating and transacting with a seller's AI agent. Modeled by the `a2a_` prefixed tables.

The grain boundary is deliberate: `conversation_session` is **human↔assistant** and `a2a_session` is **agent↔agent**. They are never joined on a shared spine key; each has its own session grain, lifecycle, and gold surfaces.

## Conversational Shopping + Intent Product Discovery

| Term | Definition |
|---|---|
| **Intent Product Discovery** | Organic product discovery flow that interprets a shopper's need or query and returns ranked products. |
| **Conversational Shopping Assistant** | Consolidated use case for guided multi-turn shopping experiences. `Shopping Assistant` describes the persona and `Conversational Shopping` describes the interaction mode; ORDM models them as one analytical use case. |
| **Guided Selling** | Retail journey where a digital assistant, associate, kiosk, or voice surface helps a shopper narrow needs, compare products, and move toward selection or purchase. Synonym for the journey served by Conversational Shopping Assistant. |
| **Digital Shopping Assistant** | Shopper-facing assistant surface that uses conversation, product discovery, and availability context to guide product selection. Former planning label: Shopping Assistant. |
| **Product Finder** | Discovery experience that turns a need, occasion, compatibility question, or replenishment request into ranked product candidates. |
| **Clienteling / Associate-Assisted Shopping** | Store-associate guided selling journey that uses the same session, turn, discovery, and engagement grain as a digital assistant. |
| **Save-the-Sale Discovery** | Journey where the assistant or associate recommends an available substitute, complement, or nearby product when the original need cannot be fulfilled directly. |
| **Conversation Session** | Append-only, privacy-safe summary of one guided shopping conversation emitted once when the session is reportable. `conversation_session_id` is the durable ORDM session key; `session_id` and `conversation_id` are pseudonymous source identifiers retained as degenerate attributes, not runtime state. |
| **Assistant Turn Event** | One structured shopper, assistant, associate, or system turn within a conversation session. Stores action metadata only, not utterance or generated response text. |
| **Discovery Intent Event** | One privacy-safe shopper intent/query turn captured by a search, agent, voice, kiosk, or associate-assisted surface. |
| **Discovery Result Event** | One product returned for a discovery intent, including rank, score, explainability reason, and availability context. |
| **Discovery Engagement Event** | A shopper interaction with a returned result, such as view, select, add to cart, dismiss, or purchase. Purchase `net_amount` / `quantity` are a point-of-engagement attribution snapshot, not reconciled against `customer_order_line` (the authoritative financial record) even when `order_line_sk` resolves. |
| **Product Discovery Candidate** | A current product-store candidate available for retrieval/ranking, combining product attributes, current price, and inventory availability. |
| **Intent Category** | Normalized classification of the shopper need, such as product search, need-based, occasion, compatibility, style/fit, replenishment, comparison, or unknown. |
| **Reason Code** | Primary explainability reason for why a product was returned, such as semantic match, purchase affinity, substitute, complement, trending, nearby availability, or business rule. |
| **Result Rank** | One-based position of a product within the returned result set for an intent. |
| **Result CTR** | Selected results divided by returned results. A selected result has at least one `select` engagement event. |
| **Add-to-Cart Rate** | Results with an `add_to_cart` engagement divided by returned results. |
| **Discovery Conversion Rate** | Results with a purchase engagement divided by returned results. |
| **Zero-Result Rate** | Intent events that return no result events divided by total intent events. |
| **Low-Result Intent** | Discovery intent with fewer returned products than the retailer expects for the journey, often signaling catalog, availability, or ranking coverage gaps. |
| **Assisted Conversion Rate** | Conversation sessions with a **discovery-attributed** purchase (a `purchase` engagement on a discovery result linked to the session) divided by total conversation sessions. Intentionally narrower than `resolution_type='purchase'`: a session that resolved to a purchase with no tracked discovery-result purchase engagement is not counted, so this KPI can read lower than a raw resolution-based purchase rate. |
| **Resolution Type** | How a conversational shopping session resolved, such as product selected, add to cart, purchase, handoff, no resolution, or abandoned. |
| **Handoff (occurrence vs resolution)** | Two distinct, intentionally non-equal signals. **Occurrence** — a handoff happened at some point in the session (gold `handoff_flag`, from a turn's `turn_type='handoff'` / `is_handoff_flag`); this is the authoritative "did a handoff occur" measure. **Resolution** — the session *ended* in a handoff (`resolution_type='handoff'`, mirrored by `session_status='escalated'`). A session can hand off mid-flow yet still resolve to a purchase, so the two diverge by design. |
| **Handoff Rate** | Conversation sessions where a handoff *occurred* (turn-derived `handoff_flag`) divided by total conversation sessions. Distinct from the `resolution_type='handoff'` terminal outcome — see **Handoff (occurrence vs resolution)**. |
| **Fallback Rate** | Conversation sessions with at least one fallback turn divided by total conversation sessions. |
| **Turns to First Discovery** | Number of turns before a conversational shopping session reaches a linked discovery intent, useful for measuring friction in guided selling. |
| **Former Planning Labels** | `Shopping Assistant` and `Conversational Shopping` are retained as business synonyms, but the implemented ORDM use case is `Conversational Shopping Assistant`. |
| **Agent Runtime** | The shopper or associate-facing application and model endpoint, commonly implemented with Databricks Apps plus Agent Serving or Model Serving. The runtime consumes ORDM but is not itself an ORDM artifact. |
| **Lakebase Backend State** | Low-latency operational state for active conversations, agent decisions, tool/action state, and workflow checkpoints. It can produce ORDM events through change data feed, CDC, or event streaming, but the backend schema is application-owned. |
| **ORDM Event Contract** | The durable analytical event shape emitted from an agentic backend or event stream into Delta, such as `discovery_intent_event`, `discovery_result_event`, `conversation_session`, and `assistant_turn_event`. |
| **Vector Search Index** | Databricks Vector Search index built from embeddings over the curated product candidate surface, typically sourced from `gold_product_discovery_candidate_current`, for semantic retrieval by the agent runtime. |
| **Zerobus Event Stream** | Event streaming path that can land agent, search, conversation, and engagement events into the ORDM Delta contracts when direct Lakebase change feed / CDC is not the preferred integration. |

## Agent-to-Agent (A2A) transactions

### Tables

| Table | Grain | SCD | Description |
|---|---|---|---|
| `a2a_session` | One agent-to-agent session | None (mutable lifecycle) | Tracks the full negotiation lifecycle between a buying agent (customer) and a selling agent (retailer). |
| `a2a_agent` | One agent version | SCD2 | The autonomous agents themselves as first-class actors — buyer-side or seller-side, with operator, trust status, and protocol version. |
| `a2a_negotiation_event` | One negotiation step | None (append-only) | Immutable log of every offer / counter-offer / acceptance / escalation within a session. |
| `a2a_mandate` | One mandate version | SCD2 | The delegated authority a customer grants a buying agent — spend ceiling, per-transaction limit, approval threshold, allowed categories. |

### Gold views

| View | Grain | Description |
|---|---|---|
| `gold_a2a_session_summary` | One session | Session + rolled-up negotiation outcome (event count, first offer, agreed price/quantity, concession, escalation flag). |
| `gold_a2a_negotiation_funnel` | Day × channel × product | Funnel counts (initiated → negotiating → agreed → completed) and loss, with completion rate. |
| `gold_a2a_agent_scorecard` | One agent | Per-agent participation, completion, success rate, and average time to agreement. |

### Key concepts

- **A2A session** — A single negotiation between two AI agents: one acting on behalf of a buyer (customer) and one acting on behalf of a seller (retailer/store). The session has a lifecycle from initiation through negotiation to completion, abandonment, or failure.
- **Buying agent** — An AI agent that acts on behalf of a customer (linked via `buyer_profile_sk`). It discovers products, requests quotes, negotiates terms, and places orders within delegated authority.
- **Selling agent** — An AI agent that acts on behalf of a retailer or store (linked via `store_sk`). It responds to inquiries, offers pricing, checks inventory, and accepts or counters proposals.
- **Session lifecycle** — The progression of a session through states: `initiated` (first contact), `negotiating` (active exchange), `agreed` (terms accepted), `completed` (order placed), `abandoned` (party withdrew), `failed` (technical/policy failure), `expired` (timed out).
- **Initiator** — The agent that started the session, either `buyer_agent` or `seller_agent`.
- **Agent** (`a2a_agent`) — An autonomous software actor that participates in A2A sessions. A **buyer agent** represents a customer profile; a **seller agent** represents a store. Agents are SCD2-versioned because their trust status, protocol version, and capabilities change over time.
- **Trust status** — The verification state of an agent: `unverified`, `verified`, `suspended`, `revoked`. A counterparty may refuse to transact with an unverified or suspended agent.
- **Negotiation event** (`a2a_negotiation_event`) — One immutable step in a negotiation: `price_request`, `offer`, `counter_offer`, `acceptance`, `rejection`, `availability_check`, or `escalation_to_human`. The append-only history behind a session's current state.
- **Escalation to human** — A negotiation step where the agent hands control to a person (e.g. a proposal exceeds its mandate). Tracked as an `event_type` so the human-escalation rate is measurable.
- **Mandate** (`a2a_mandate`) — The delegated authority a customer grants a buying agent: the spend ceiling, per-transaction limit, the value above which a human must approve (`approval_threshold_amount`), and the product categories the agent may buy. SCD2 — a customer revises the mandate over time. Authorized by a `consent` decision in the customer core (referenced by durable `consent_id`).
- **Price concession** — The reduction from a session's first offer to its agreed price, expressed as a fraction in `gold_a2a_session_summary` — `(first_offer_price − agreed_price) / first_offer_price`. The first offer is the seller agent's opening quote (its ask), so a positive value measures how much ground the seller gave from that quote; a negative value means the settled price rose above the opening.

### Selected terms

| Term | Definition |
|---|---|
| **Agent-to-Agent Transaction** | A purchase completed entirely through automated negotiation between AI agents, without direct human interaction during the transaction itself. |
| **Communication channel** | The communication medium between agents: `api` (programmatic), `marketplace` (platform-mediated), `direct` (peer-to-peer), `voice` (spoken-language interface). Named `communication_channel` to avoid collision with the canonical retail channel concept. |
| **Delegation / mandate** | The authority a human grants to their buying agent to act on their behalf within defined constraints (scope, spend limits, product categories). Modeled in the `a2a_mandate` SCD2 table (see the entities table above). |
| **Session summary** | Free-text description of the session outcome. Treated as PII because agents may relay customer details. |

## Standards used

| Concept | Standard |
|---|---|
| Timestamps | ISO 8601, UTC |
| Session identifiers | UUID v4 (recommended, not enforced) |
| Occurrence-column naming | The conversational-shopping facts name the occurrence timestamp `event_ts` with a two-field audit block (`record_source` + `load_timestamp`); the A2A event fact uses `event_timestamp` + `ingest_timestamp` (+ `latency_seconds`) and `a2a_session` adds `source_updated_timestamp`. Both are grain-appropriate; the naming difference between the two slices is intentional, not a typo. |

## PII / sensitivity classification

Tagged via `dbx_pii` column tags (standard §11):

| Column(s) | Tag |
|---|---|
| `a2a_session.session_summary` | `dbx_pii` |

## Deferred

| Term | Deferred reason |
|---|---|
| **Conversation Transcript** | Application/agent operational state; not part of the ORDM published data model. |
| **Agent Memory** | Application-owned state that may consume ORDM but should not be modeled as shared retail data. |
| **Lakebase / pgvector Retrieval Index** | Optional backend-specific cache or alternate implementation. The recommended semantic retrieval path is Databricks Vector Search sourced from the candidate gold view. |
