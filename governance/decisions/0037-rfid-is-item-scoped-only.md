# ADR 0037 — RFID is item-scoped only

**Status:** Accepted (2026-10-07; design approved 2026-08-19; domain-reviewer sign-off in #165).

## Context

ADR 0029 — *Aggregate-only sensing schema with policy-driven shared disclosure* — makes
Connected Store Signals aggregate-only with respect to people and forbids person-level or
linkable sensing identifiers. An EPC identifies an item, but it can become
person-linkable if joined to receipts, loyalty, payments, or video. RFID privacy guidance also
expects the post-sale tag state to be explicit rather than assumed.

The retail capability boundary separates serialized-inventory truth from person-directed loss
prevention. RFID is the observation source for the first; loss-prevention case management is a
different, adversarial capability and privacy tier.

## Decision

The open RFID model carries no person, basket, transaction-line, loyalty, payment, or video
linkage and no EAS case-management entities.

Item-side exceptions are published only as item-state outcomes. `gold_unaccounted_exits`
identifies an attributed outward perimeter read with no sold or shipping disposition known at or
before the exit. It contains no actor fields and is an escalation seam, not a theft conclusion.

`tagged_item.tag_privacy_state` records whether the tag is `active`, `protected`, `killed`, or
`detached`. Post-kill reads are quality telemetry. The package-wide no-person-column and
sensing-not-upstream-of-pricing checks include the RFID tables and views.

## Consequences

ORDM supports inventory accuracy, item presence, receiving verification, and item-side shrink
signals while retaining the package privacy boundary. Adopters requiring person-directed loss
prevention operate a private tier outside the open model.

`stolen` may remain a legal item disposition because it describes item state. It must never be
treated as an assertion about a person or enriched with actor-identifying joins in this package.
EAS alarms, SCO reconciliation, and organized-retail-crime case analytics remain deferred.
