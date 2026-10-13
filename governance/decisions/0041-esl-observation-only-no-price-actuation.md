# ADR 0041 — ESL is observation-only; price actuation is rejected

**Status:** Accepted (2026-10-09; proposed 2026-08-21) by the maintainer, @Tagar, with the Connected Store Signals sign-off in #165 (acceptance record). Its amendment of ADR 0030 still awaits acknowledgement from ADR 0030's CSS-owner and Privacy scopes.

## Context

ADR 0030 established the invariant that in-store sensing is never upstream of pricing. Its
context predicted that Smart Shelf would publish an ESL price-actuation layer, and its decision
referred to an `esl_price_event` carrying the invariant plus pricing-compliance context.

The implemented Smart Shelf boundary is narrower. `esl_label` registers display endpoints,
`esl_label_assignment` records label × product × shelf-position bindings, and the append-only
`esl_price_observation` records what a label displayed, how that state was observed, and the
store-scoped price evidence used for comparison. The generic IoT automation loop exists, but
Smart Shelf has no need to publish price commands to deliver price-accuracy or sync-latency
analytics.

## Decision

Smart Shelf remains inside Connected Store Signals and models ESL display state only. The open
model contains no ESL price command, schedule, campaign, or other price-actuation entity. No
price-bearing automation action may originate from or be triggered by a CSS object.

`esl_price_observation` may read and capture pricing evidence, including an adopter's pricing
platform or core `product_price` where its scope is valid. It is never an ancestor or input of a
pricing decision. The `sensing_derived_input_flag = FALSE` constraint and the
`css_no_sensing_to_pricing_lineage` error check preserve ADR 0030's invariant. Displayed
disclosure indicator and text remain observation evidence rather than pricing declarations.

### Amendment to ADR 0030

The amendment is in force from this ADR's acceptance (2026-10-09) for the open model in staging. Because item 3 defers
ADR 0030's privacy-relevant compliance fields, ADR 0030's CSS-owner and Privacy scopes must acknowledge it, and the
formal DPO review that ADR 0030's Privacy approval requires on a scope change must happen, before Connected Store
Signals is ✅ Published. Until then it is recorded as an open ✅ gate in `STATUS.md`. Accepting this ADR amends ADR 0030 to:

1. amend ADR 0030's predicted ESL actuation-layer wording to an observation-only evidence layer;
2. rename the proposed `esl_price_event` concept to the implemented
   `esl_price_observation`;
3. defer pricing-platform declaration fields—`algorithmic_pricing_flag`,
   `personal_data_used_flag`, and `discount_basis_code`—to a future pricing-owned surface while
   retaining observed disclosure evidence on the ESL observation; and
4. preserve the rule that ESL observations may read pricing evidence but never feed pricing
   decisions.

### Rejected alternative

Representing ESL price pushes as IoT-loop firings or adding Smart Shelf commands, schedules, or
campaign entities is rejected. ORDM has no consumer that requires price-command state, the
observation fact already supports the named compliance and operations measures, and a price
payload on the sensing-adjacent automation ledger would make the prohibited lineage easier to
create and harder to inspect. A future pricing-owned ADR could add an actuation surface without
changing the ESL observation objects.

## Consequences

- Dynamic-pricing consumers use `esl_price_observation` as displayed-state evidence, not as an
  actuation ledger.
- Pricing-platform declarations remain outside CSS; the package carries no person-level data and
  preserves its aggregate-only boundary.
- Existing latest-capture-wins behavior, known/unknown/unobserved splits, single-currency guards,
  and shelf evaluation-clock behavior remain unchanged.
- No existing table schema changes as a result of this decision.
