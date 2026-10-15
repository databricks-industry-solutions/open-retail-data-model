# Architecture decision records

Each file records one decision: the context, the options considered, the choice and its
consequences. Status is one of Accepted, Superseded (the record names its successor) or
Proposed; an amended decision stays Accepted and names the record that amends it.

Numbers are assigned in order but a few were reused when decisions landed in parallel
(0028 three times; 0029 and 0030 twice), and some numbers are not in this list. Cite a decision by its file
name. A new record gets a row here; its Status column is the first word of the record's
`**Status:**` line (`tests/test_adr_index.py` checks both).

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-layer-positioning.md) | ORDM covers both canonical core (silver) and outcome packages (gold) | Accepted |
| [0002](0002-money-decimal-vs-double.md) | Money is DECIMAL, DOUBLE is for derived compute and non-money values | Accepted |
| [0003](0003-is-current-scd2-flag.md) | The SCD2 current-version flag is is_current | Accepted |
| [0004](0004-primary-key-contract.md) | Primary-key contract is a BIGINT identity surrogate plus a durable business key | Accepted |
| [0005](0005-lakebase-physical-binding.md) | Lakebase as a second physical binding | Accepted |
| [0006](0006-promotion-dimension-to-marketing-core.md) | Promote the `promotion` dimension into a canonical-core `marketing` domain (Option A) | Accepted |
| [0007](0007-definition-of-done.md) | Definition of Done and the status ladder | Accepted |
| [0009](0009-uc-domains-derived-no-manifest.md) | UC Domains: derived mapping, no domains manifest | Accepted |
| [0010](0010-governed-tag-and-semantic-alignment.md) | Align governed-tag and semantic conventions with Databricks native features | Accepted |
| [0011](0011-key-naming-by-grain-role.md) | Key-stem naming by grain/role, not strict table-name match | Accepted |
| [0012](0012-model-visualization.md) | Model visualization: generated diagrams + interactive explorer | Accepted |
| [0013](0013-use-cases-planning-artifact.md) | `use-cases.yaml`: a per-package planning artifact | Accepted |
| [0016](0016-disruption-alert-lifecycle-columns.md) | Disruption Alert Lifecycle Columns | Accepted |
| [0017](0017-media-domain-for-retail-media-dimensions.md) | A canonical-core `media` domain for conformed retail-media dimensions | Superseded |
| [0018](0018-commerce-media-networks-fact-dedup.md) | Conformed fact layer for Commerce Media Networks (fact-plane dedup) | Accepted |
| [0019](0019-media-measurement-in-data-sharing.md) | Media Measurement lands in Data Sharing with Suppliers (reuse, not redefine) | Accepted |
| [0020](0020-broaden-marketing-shared-dimensions.md) | Broaden `marketing` into the shared-marketing domain (audience) | Superseded |
| [0021](0021-retail-media-entities-are-gold-not-silver.md) | Retail-media ad-delivery entities are GOLD (outcome-package), not a silver core domain | Accepted |
| [0022](0022-promote-audience-to-silver-marketing.md) | Promote the `audience` segment-definition dimension to silver `marketing` | Accepted |
| [0023](0023-cluster-key-type-mandate.md) | Clustering keys: order-independence, and a narrow enforced CLUSTER-KEY-TYPE mandate | Accepted |
| [0024](0024-gold-to-gold-coupling-acu-ucv.md) | ACU and UCV gold views may read each other (bounded gold↔gold coupling) | Accepted |
| [0025](0025-scd2-join-contract-mandate.md) | SCD2 join contract in consuming views (SCD2-JOIN-CONTRACT mandate) | Accepted |
| [0026](0026-cdp-activation-layer-in-ucv.md) | CDP activation layer (destination catalog + activation/touch facts) in Unified Customer View | Accepted |
| [0027](0027-consent-suppression-overlay.md) | Suppression as an overlay on the consent master (not a separate ledger) | Accepted |
| [0028](0028-cross-plane-do-not-target-and-multi-purpose-gate.md) | Cross-plane do-not-target view + multi-purpose activation gate | Accepted |
| [0028](0028-hash-surrogate-keys-for-high-volume-gold-facts.md) | Hash surrogate keys for high-volume gold event facts | Accepted |
| [0028](0028-predictive-operations-store-risk.md) | Store Operational Risk Score: a `predictive_operations` schema, store-grain composite, and the boundary with `early-risk-detection` | Accepted |
| [0029](0029-aggregate-only-sensing-publication-and-k10-suppression.md) | Aggregate-only sensing schema with policy-driven shared disclosure | Accepted |
| [0029](0029-conformed-interaction-touchpoint-fact.md) | Conformed omnichannel interaction fact (`interaction.touchpoint`) in the canonical core | Accepted |
| [0030](0030-a2a-logical-non-fk-references.md) | Agent representation and consent are logical (non-FK) references, not surrogate FKs | Accepted |
| [0030](0030-sensing-signals-never-upstream-of-pricing.md) | In-store sensing signals are never an upstream dependency of pricing | Accepted |
| [0031](0031-sensing-deployment-governance-dimension.md) | `sensing_deployment` is a first-class governance dimension | Accepted |
| [0032](0032-one-sensor-report-interval-fact.md) | Shared sensor-report interval envelope with keyed extensions | Accepted |
| [0033](0033-relocate-footfall-fact-from-cmn-to-css.md) | Relocate footfall ownership from CMN to Connected Store Signals | Accepted |
| [0034](0034-conversation-session-emit-once-grain.md) | `conversation_session` is emit-once per durable key; an `active` snapshot is terminal for ORDM | Accepted |
| [0035](0035-hash-keyed-type-1-tagged-item-registry.md) | Serialized-item identity is a hash-keyed Type 1 registry | Accepted |
| [0036](0036-rfid-events-remain-outside-the-interval-envelope.md) | RFID events remain outside the sensor interval envelope | Accepted |
| [0037](0037-rfid-is-item-scoped-only.md) | RFID is item-scoped only | Accepted |
| [0038](0038-rfid-current-state-evaluation-clock.md) | RFID item presence has an explicit evaluation clock | Accepted |
| [0039](0039-smart-shelf-positional-state-outside-sensor-envelope.md) | Smart Shelf positional state remains outside the sensor interval envelope | Accepted |
| [0040](0040-css-expected-shelf-state-vs-bmv-planogram.md) | CSS owns position-level expected shelf state; BMV planogram remains allocation intent | Accepted |
| [0041](0041-esl-observation-only-no-price-actuation.md) | ESL is observation-only; price actuation is rejected | Accepted |
| [0042](0042-market-analysis-reads-bmv-competitor-foundation.md) | Market Analysis reads the BMV competitor foundation | Accepted |
| [0043](0043-labor-domain-workforce-optimization.md) | Canonical-core `labor` domain unlocks Predictive Operations: Workforce Optimization | Accepted |
| [0044](0044-identity-resolution-thin-core-scope.md) | Identity Resolution is delivered by the thin identity core; the identity graph is deferred | Accepted |
| [0045](0045-cross-package-use-case-tables.md) | A use case may map to another package's gold view | Accepted |
