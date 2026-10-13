# Identity resolution — design notes

Design rationale for how ORDM models resolved customer identity. The canonical core publishes a **thin**
identity primitive ([`identity_link`](../../../canonical-core/customer/tables/identity_link.sql)); the full
graph-first machinery described here is deferred to a future outcome package. This note captures the
research so nothing is lost in the thinning.

## Problem framing

Identity resolution in commerce is not one algorithm — it is a combination of **deterministic matching**,
**probabilistic linkage**, **survivorship**, **householding**, **consent enforcement**, and **auditability**.
IAB Tech Lab frames identity resolution as the intersection of a consent repository, an identity/device
graph, and multiple identifier types producing a unified view at device, person, or household level.

Signal classes that a canonical model should distinguish:

- **High-confidence asserted identifiers** — loyalty IDs, verified ecommerce account IDs, documented CRM IDs,
  authenticated hashed email/phone. These drive *identity assertion* (contactable golden-profile merges).
- **Device/session signals** — IP, user agent, device details, cookies/MAIDs. These enrich edges and support
  measurement, frequency, and household inference, but should **not** by themselves drive contactable merges
  unless policy explicitly allows it and confidence is demonstrably high.

Record-linkage literature backs this split: deterministic linkage is rules-based matching on exact/near-exact
identifiers; probabilistic linkage (Fellegi–Sunter family) uses weighted evidence across fields when there is
no universal key. Probabilistic methods increase scale but reduce precision.

## The full graph-first model (deferred)

The research recommends a **relational identity graph with current-state read models**: the graph captures
durable identity structure; read models expose stable, denormalized surfaces for CDP, personalization, media,
analytics, and agents. Core objects:

| Object | Grain | Purpose |
|---|---|---|
| `ref_identifier_type` | one per identifier type | typing, privacy class, clean-room eligibility |
| `ref_match_rule` | one per matching rule | rule catalog, thresholds, activation/householding policy |
| `identity_node` | one per node version | generic node: customer, household, account, device, identifier |
| `identity_edge` | one per edge version | link between nodes with rule, method, confidence, review status |
| `identity_event` | one per merge/split/link/suppress | full auditability of graph changes |
| `identity_graph_snapshot` | one per active node-edge state per snapshot | replayable point-in-time state |
| `identifier_suppression` | one per suppression key×scope (restricted) | delete/opt-out/do-not-sell ledger |
| customer/household profile history | one per profile version | durable golden-profile history + confidence |
| customer↔household / customer↔identifier bridges | one per relationship version | householding & binding history |

### Match-rule catalog (survivorship)

Rules carry a `match_method` (deterministic / probabilistic / hybrid / manual), a tier
(assertive / strong / review / observe), a `min_confidence_threshold`, and policy flags:
`activation_allowed`, `householding_allowed`, `auto_merge_allowed`, `requires_manual_review`,
`consent_required`, and a `precedence_rank` for survivorship conflict resolution. Confidence is
`DECIMAL(5,4)` in [0,1]. This catalog is what makes merges explainable and auditable.

### Key design principles (carried into the thin core)

1. **Graph authoritative in Delta**, not in a serving store — serving tiers (if any) are read-only projections.
2. **Store only pseudonymized identifiers** in the governed layer — hashed/tokenized values, never raw
   email/phone/address. Break-glass raw PII lives in a separately governed restricted domain, linked by token.
   (ICO: pseudonymized data is still personal data in context; GDPR data-minimization.)
3. **Do not depend on warehouse PK/FK enforcement** — UC keys are informational; integrity is guaranteed by
   pipeline expectations, deterministic id generation, and reconciliation checks.
4. **Confidence and provenance are first-class** — every link carries a confidence score, a match method, and
   the rule that produced it.

## How `identity_link` projects this

The published core table is the **thin conformed projection**: one row per source-system identifier assertion
resolved to a `profile`, per SCD2 period, carrying `identifier_type`, hashed `identifier_value_hash`,
`match_method`, `match_confidence`, and `link_status`. It is the "resolved key + match confidence" surface
that downstream outcomes depend on — deliberately **excluding** the node/edge graph, the merge/split event
log, graph snapshots, and the match-rule catalog. Those stay design-only until a dedicated identity-resolution
outcome package needs them.

Mapping of the three overlapping brief designs onto the one core table:

- CDP `dim_identity_link` → `identity_link` (1:1 in spirit — identifier value per customer per period).
- Customer-360 `dim_customer_identity` → `identity_link` (source identity assertion per customer per interval).
- Identity-resolution `bridge_customer_identifier_hist` + `dim_identity_node` (identifier subset) →
  collapsed into `identity_link`; the node/edge/event graph is deferred here.

## Deferred to a future outcome package

The v1 scope (this thin core) and the deferral below are recorded in
[ADR 0044](../../../governance/decisions/0044-identity-resolution-thin-core-scope.md).

- The node/edge graph and `identity_event` audit log (merge/split/link/suppress/restore).
- `identity_graph_snapshot` replayable point-in-time state.
- The `identifier_suppression` restricted ledger (delete / opt-out / do-not-sell / GPC / global scopes) —
  see [consent-and-preferences-notes](consent-and-preferences-notes.md) for its relationship to consent.
  **Partly superseded by [ADR 0027](../../../governance/decisions/0027-consent-suppression-overlay.md):**
  v1 do-not-contact suppression now lives as an overlay on `customer.consent`; this erasure-surviving,
  identifier-hash-keyed ledger remains the deferred promote target for the fuller multi-scope signal.
- Current-state resolution read models (`mv_*_identity_current`) and any low-latency serving tier.
