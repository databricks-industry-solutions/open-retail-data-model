# Design notes — Customer identity, consent & preferences

Research and design rationale for the customer-identity slice of the ORDM canonical core. These are
**design documents, not published tables** — narrative, standards grounding, and the full research models
live here (per `CONTRIBUTING.md`: markdown is forbidden under any `tables/` directory; narrative goes to
`design/` or `docs/`). The conformed, published tables that this research distills into live in
[`canonical-core/customer/`](../../../canonical-core/customer/).

## Provenance

Distilled from retail CDP reference briefs covering Customer 360, CDP, and Identity Resolution.
The briefs are decision research — external-standards grounding, grain discipline, and privacy-by-design —
paraphrased here. References to IAB/MRC, GS1, GDPR/CCPA, and ICO guidance are cited facts and identifiers,
not reproductions of any copyrighted spec; this material is compatible with the project's Apache-2.0 license.

## What landed in the core vs. what stays here

The briefs propose rich, outcome-layer designs (identity graphs, segment/audience machinery, materialized
current-state read models, Lakebase serving tiers). ORDM's canonical core is a **thin conformed layer** —
one definition per concept, no derived metrics on masters, Delta-only. So the research is split:

| Concept | Thin core table (published) | Rich design (deferred — this folder / a future package) |
|---|---|---|
| Resolved identity | [`identity_link`](../../../canonical-core/customer/tables/identity_link.sql) — one resolved identifier→profile assertion + confidence | Full node/edge graph, merge/split event log, graph snapshots → [identity-resolution-notes](identity-resolution-notes.md) |
| Household | [`household`](../../../canonical-core/customer/tables/household.sql) — conformed household master | Householding confidence, member/device counts, anchor-store rollups → identity-resolution-notes |
| Consent | [`consent`](../../../canonical-core/customer/tables/consent.sql) (refined) — single source of truth, now jurisdiction-scoped | Purpose×channel×jurisdiction ledger, GPC/do-not-sell flags, suppression → [consent-and-preferences-notes](consent-and-preferences-notes.md) |
| Comms preference | [`channel_preference`](../../../canonical-core/customer/tables/channel_preference.sql) — soft comms preferences | Frequency/topic/format modeling → consent-and-preferences-notes |

## Contents

- [`identity-resolution-notes.md`](identity-resolution-notes.md) — the graph-first identity model (nodes,
  edges, match rules, survivorship, suppression, graph snapshots), why it is deferred out of the core, and how
  `identity_link` is the thin conformed projection of it.
- [`consent-and-preferences-notes.md`](consent-and-preferences-notes.md) — regulatory grounding
  (GDPR/CCPA/CPRA/ICO), the purpose×channel×jurisdiction consent model, and the consent-vs-preference boundary.

## Downstream

The deferred machinery is the design basis for a future **unified-customer-view** outcome package (and a
later dedicated identity-resolution package): current-state 360 marts, resolution read models, and
activation-eligibility views built **on top of** the thin core defined here.
