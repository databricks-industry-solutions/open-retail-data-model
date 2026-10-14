# Customer Domain — Business Glossary

> Status: ✅ Published (0.5) · Last reviewed: 2026-07-10

Business terms for the ORDM canonical-core **Customer** domain (Unity Catalog schema). Definitions are vendor-neutral and follow the ORDM [data model principles](https://github.com/databricks-industry-solutions/open-retail-data-model/blob/main/docs/data-model-standards.md).

## Tables

| Table | Grain | SCD | Description |
|---|---|---|---|
| `profile` | One version per individual customer | SCD2 | Conformed individual-customer master — identity, locale, retail identifiers, lifecycle. Shared by every outcome package. |
| `address` | One version per customer address | SCD2 | Postal addresses (billing, shipping, home, work). |
| `contact` | One contact point | Operational (current-state) | Reachable contact points — email / phone. Type+value model. |
| `consent` | One version per consent decision | SCD2 (date) + `decision_timestamp` | **Single source of truth** for opt-ins and processing permissions. Date-grained SCD2 like every other master; `decision_timestamp` keeps the legal-grade instant. Scoped by `consent_type` × `jurisdiction_code` (GDPR vs CCPA/CPRA). `third_party_sharing` (do-not-**share**) and `data_sale` (do-not-**sell**) are distinct CCPA/CPRA opt-outs, kept as separate types. Also carries the **suppression overlay** (`suppression_indicator` + `suppression_reason_code`) — a do-not-contact signal that overrides granted consent. |
| `account` | One version per organization | SCD2 | Optional B2B organization account a customer transacts on behalf of. |
| `household` | One version per household | SCD2 | Conformed household master — a grouping of related individuals. `profile.household_sk`/`household_id` reference it. |
| `identity_link` | One version per identifier→profile assertion | SCD2 | Thin resolved-identity primitive: a pseudonymized source identifier resolved to a `profile`, with match method and confidence. |
| `channel_preference` | Type-aware: per (profile, channel, preference_type) for contact_frequency/format; + preference_value for topic_subscription; per (profile) for preferred_channel | SCD2 | Soft communication preferences. `preference_value` is in the grain only for topic_subscription (multiple concurrent topics per channel); `preferred_channel` is a single cross-channel choice (one per profile). **Not** consent — legal permissions live only in `consent`. |

## Key concepts

- **Surrogate key (`*_sk`)** — system-generated `BIGINT IDENTITY`, unique per row/version; the declared PRIMARY KEY and the FK/join target for downstream dimensional models.
- **Business / natural key (`*_id`)** — durable, externally-meaningful identifier, stable across SCD2 versions. Use with `is_current = TRUE` for "current state" joins.
- **SCD2 versioning** — `effective_from_date` / `effective_to_date` / `is_current`. A new version is appended when a tracked attribute changes; the prior version is end-dated. No destructive overwrite of master attributes (principle #8).
- **Audit block** — every mutable entity carries `created_timestamp` and `source_updated_timestamp` (source-system instants) alongside `load_timestamp` (pipeline instant). All timestamps are stored in **UTC** (principle #9b).
- **Consent is centralized** — marketing and processing permissions exist **only** in `consent`, never as flags on `profile`/`account`/`contact`/`channel_preference` (principle #5).
- **Resolve consent as-of jurisdiction** — the current-consent grain is `(profile, consent_type, jurisdiction_code)`, not `(profile, consent_type)`. A customer can hold different current consent per regime (GDPR-EU vs CCPA/CPRA-US). Consumers (activation, Unified Customer View, …) **must** filter by the applicable `jurisdiction_code` (with `is_current = TRUE`) or they may see multiple current rows and pick the wrong one.
- **Consent vs. preference** — `consent` answers "am I legally permitted to contact/process?" (lawful basis, opt-in/opt-out, jurisdiction). `channel_preference` answers "how does the customer prefer to be contacted?" (frequency, topic, format). `is_subscribed = false` is a **soft** targeting opt-out (a preference the customer expressed), **not** a legal withdrawal — that is a `consent` state. A preference neither grants what consent withheld nor legally overrides consent; a consumer combines both (contactable = consent granted AND preference allows). See [`docs/design/customer-identity/consent-and-preferences-notes.md`](https://github.com/databricks-industry-solutions/open-retail-data-model/blob/main/docs/design/customer-identity/consent-and-preferences-notes.md).
- **Identity is resolved upstream** — `identity_link` is the thin conformed projection of an identity-resolution process; the full graph (nodes/edges, merge/split, suppression) is deferred to [`docs/design/customer-identity/`](https://github.com/databricks-industry-solutions/open-retail-data-model/tree/main/docs/design/customer-identity), not the core.
- **No derived columns on masters** — lifetime value, order counts, churn/CLTV scores, last-purchase dates are computed in outcome-package metric views, not stored here (principle #4).

## Selected terms

| Term | Definition |
|---|---|
| **Profile** | A single individual customer (a person), independent of any organization. |
| **Account** | A business/organization entity (B2B). Its `primary_contact_profile_sk` is the declared FK to the primary-contact profile (resolved as-of the account version's effective date); the durable `primary_contact_profile_id` business key is retained for lineage. |
| **Household** | A grouping of related individuals, a first-class master keyed on `household_id`. A `profile` references its household via `household_sk` (as-of) + durable `household_id`. PII. |
| **Loyalty ID** | Identifier of the individual within a loyalty/membership program (`loyalty_id`). PII. |
| **Contact point** | One way to reach a customer (an email address or a phone number), typed via `contact_type`. |
| **Consent type** | The activity a consent decision governs (e.g. `marketing_email`, `data_processing`). |
| **Legal basis** | The lawful basis for processing personal data (e.g. `consent`, `contract`, `legitimate_interest`). |
| **Jurisdiction code** | Region/law scope a consent decision applies under, ISO 3166 (e.g. `EU`, `GB`, `US-CA`); lets one customer hold different consent per regime. |
| **Identity link** | A pseudonymized source identifier (hashed email/phone/device/loyalty id) resolved to a `profile`, with `match_method` and `match_confidence` in [0,1]. |
| **Match confidence** | Probability in [0,1] that an `identity_link` correctly resolves an identifier to its profile; 1.0 = deterministic/asserted. |
| **Channel preference** | A soft communication preference (preferred channel, frequency cap, topic subscription, format) — distinct from consent. |
| **Suppression (do-not-contact)** | An operational/legal do-not-contact overlay on a consent scope (`suppression_indicator` + `suppression_reason_code`). It **overrides granted consent** in the activation gate and is a distinct governed state (principle #5) — not the same as a consent withdrawal. Two scopes: **channel-level** reasons (`unsubscribe`, `hard_bounce`, `spam_complaint`, `list_hygiene`) block only the consent scope they sit on; **person-level** reasons (`deceased`, `fraud`, `do_not_contact`, `legal_objection`) block every **owned** channel the gate evaluates for the profile (the gate propagates them across scopes) and, via `gold_person_do_not_target_current`, the paid plane too. ICO treats a do-not-contact signal as a separate minimal record kept to screen future contact; ORDM's v1 overlay approximates this (an erasure-surviving hashed ledger is the deferred promote target). |
| **"Suppression" — three distinct meanings** | The word `suppression` names **three unrelated concepts** across ORDM; they are not the same thing and are not interchangeable. (1) **Do-not-contact suppression** — the consent overlay above (this domain). (2) **Threshold/statistical suppression** — `commerce-media-networks` small-cell / k-anonymity masking for supplier disclosure (`campaign_day.privacy_suppressed_flag`, `suppression_reason` ∈ `below_threshold`/`consent`/`policy`/`none`); a privacy-aggregation concern, not a marketing permission. (3) **Identity-link suppression** — `identity_link.link_status = 'suppressed'`, a link-lifecycle state marking a retired/bad identity edge. Disambiguate by domain when querying. |

## Standards used

| Concept | Standard |
|---|---|
| Dates / timestamps | ISO 8601 |
| Country codes | ISO 3166-1 alpha-2 (`nationality_country_code`, `address.country_code`) |
| Language codes | ISO 639-1 alpha-2 (`preferred_language_code`) |
| Currency codes | ISO 4217 alpha-3 (`account.currency_code`) |
| Organization location | GS1 GLN (`account.gln`) |

## PII / sensitivity classification

Tagged via `dbx_pii_*` column tags (principle #11; consumed by governance / dbxmetagen):

| Column(s) | Tag |
|---|---|
| `profile.first_name`, `middle_name`, `last_name` | `dbx_pii_name` |
| `profile.date_of_birth` | `dbx_pii_dob` |
| `profile.loyalty_id` | `dbx_pii_identifier` |
| `profile.household_id` | `dbx_pii_identifier` |
| `address.address_line_1`, `address_line_2`, `city`, `postal_code` | `dbx_pii_address` |
| `contact.contact_value` | `dbx_pii_email`, `dbx_pii_phone` |
| `account.tax_id`, `account.credit_limit_amount` | `dbx_pii_financial` |
| `household.household_id` | `dbx_pii_identifier` |
| `identity_link.identifier_value_hash` | `dbx_pii_identifier` (pseudonymized identifier) |

> Per ORDM/RSK calibration: **UPC/SKU are not PII**; **`loyalty_id` and `household_id` are PII**.
