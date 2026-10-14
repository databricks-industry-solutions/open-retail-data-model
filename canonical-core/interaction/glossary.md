# Interaction Domain — Business Glossary

> Status: ✅ Published (0.5) · Last reviewed: 2026-10-07

The conformed omnichannel customer-interaction spine: one append-only fact for every observed direct customer touch, online and offline. Follows the ORDM [data model standards](../../docs/data-model-standards.md).

## Tables

| Object | Grain | Temporal | Description |
|---|---|---|---|
| `touchpoint` | One row per customer interaction | Append-only (event) | Every observed direct customer touch across the journey — digital (page/product/search/cart/checkout/app/session) and offline (store visit, call-center, kiosk, offline-marketing response, phone activation). Anonymous-first on a hashed device key; stitched to `customer.profile` via `identity_link` when resolved. Consent posture carried per touch. |

## Key concepts

| Term | Definition |
|---|---|
| **Touchpoint** | A single observed direct customer interaction (one row). The occurrence — not the attribution of credit to it (that is CMN `attributed_outcome`, whose "crediting touchpoint" is a paid media event). |
| **Interaction type** | What the touch was: digital verbs (`page_view`, `product_view`, `search`, `add_to_cart`, `checkout_start`, `app_open`, `session_start/end`, …) and offline verbs (`store_visit`, `call_center_contact`, `kiosk_session`, `offline_marketing_response`, `phone_activation`) in one enum. |
| **Channel code** | The channel the touch occurred on (`web`, `mobile_app`, `in_store`, `kiosk`, `call_center`, `direct_mail`, `other`) — the omnichannel discriminator (the coarse **medium**) that lets one fact carry online and offline touches. |
| **Source application** | The specific application / property / data stream the touch came from (`ios_app`, `android_app`, `web_desktop`, `web_mobile`, `loyalty_kiosk`, `in_store_pos`, `call_center_app`, `email_platform`, `other`) — a vendor-neutral degenerate attribute. The **source** paired with `channel_code` (the medium), mirroring how a CDP pairs channel with source/data-stream on each event. |
| **Anonymous-first** | Digital touches are keyed on a pseudonymous `device_id_hash` and carry `profile_id = NULL` until identity resolution (`identity_link`) stitches them to a known customer. Offline touches are identity-first (`profile_id` known, `device_id_hash` NULL). |
| **Session** | A visit grouping (`session_id`) for sessionization — funnels, dwell, pages-per-session. NULL for touches with no session (e.g. a single call-center contact). |
| **Consent status (per touch)** | A point-in-time `granted` / `denied` / `unknown` snapshot recorded as governance evidence at the moment of the touch — **not** the `customer.consent` SCD2 lifecycle (that is the legal source of truth; this is an observed snapshot, the same pattern as `media_event` / `campaign_touch`). |
| **Source-contract PII** | The hashed `device_id_hash` is tagged `dbx_pii_identifier` and masked (`masks.sql`). The free-text `page_url` / `referrer_url` / `search_term_text` columns are **not** identifiers, so they carry no `dbx_pii_*` tag or mask; instead their no-PII posture is a **source contract** — the producer must de-identify them at ingest (a shopper may type a name/email into search, or a URL may carry PII query params), which the model cannot structurally enforce. Adopters on untrusted input should add a `dbx_value_regex` guard or an ingest-boundary mask. |
| **Occurrence vs measurement** | `touchpoint` is the single source of truth for the raw *occurrence* of a customer touch. `commerce-media-networks.conversion_event` is a paid-attribution *measurement* projection of the conversion-relevant subset (clean-room-keyed, experiment-scoped), not a second recorder of the occurrence (ADR 0029). |

## Scope boundary

`touchpoint` holds only **person-level** (pseudonymous) direct touches. Anonymous **aggregate** physical footfall (store-zone traffic counts, zone dwell) is a different grain and lives in the connected-store package (`store_zone_interval`), not here.

## Standards used

| Concept | Standard |
|---|---|
| Dates / timestamps | ISO 8601 (UTC) |
| Currency | ISO 4217 (`currency_code`; single reporting currency) |
| Keys | surrogate `touchpoint_sk` (BIGINT IDENTITY) + durable `touchpoint_id` (STRING); `event_date` → `fiscal_calendar.date_key` |
| Classification | `dbx_data_type = 'transactional'`; `device_id_hash` tagged `dbx_pii_identifier` |
