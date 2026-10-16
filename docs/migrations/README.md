# Migrations

Guides for adopters moving data or queries across a published schema change. Each guide is
named after the decision record that made the change (see
[`governance/decisions/`](../../governance/decisions/)) and states what moved, the
compatibility shim (whose header carries its removal date), and the steps to migrate. The rules for when a
change needs a guide are in the [versioning policy](../versioning-policy.md).

| Guide | Change |
|---|---|
| [0033-cmn-store-zone-interval-to-css.md](0033-cmn-store-zone-interval-to-css.md) | `store_zone_interval` moves from Commerce Media Networks to Connected Store Signals (ADR 0033) |
