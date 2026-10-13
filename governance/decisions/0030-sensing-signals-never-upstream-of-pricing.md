# ADR 0030 — In-store sensing signals are never an upstream dependency of pricing

**Status:** Accepted (2026-07-31) — all four scopes in the corrective-review approval record are signed off (CSS owner, CMN owner, Maintainers, Privacy). Amended 2026-10-09 by [ADR 0041](0041-esl-observation-only-no-price-actuation.md): the ESL layer is observation-only, `esl_price_event` is implemented as `esl_price_observation`, and the pricing-declaration fields in item 3 are deferred to a future pricing-owned surface. The invariant itself is unchanged. The amendment is accepted by the maintainer; this ADR's CSS-owner and Privacy scopes have not yet acknowledged it (record).

## Context

The `connected-store-signals` package produces in-store sensing signals (footfall, dwell, occupancy,
shelf state) and — in the Smart Shelf use case — an **ESL price-actuation layer** that writes displayed
prices to shelf labels. Both live in the same outcome package. Nothing in the model's structure would
prevent a future gold view or a downstream Dynamic Pricing package from joining one to the other.

Three US instruments make that join a legal exposure rather than a design preference:

| Instrument | Status | Effect |
|---|---|---|
| **CA AB 2564** | Senate third reading as of 2026-06-29 | Defines "electronic surveillance technology" to include "sensors, cameras, device tracking, or biometric monitoring … in physical … environments" and makes any customised price based even partly on PII derived from it unlawful — penalties to $12,500 per violation plus a consumer right of action |
| **MD HB 895** | Signed 2026-04-28, **effective 2026-10-01** | Prohibits using personal data to set a higher price for food at retailers ≥ 15,000 sq ft |
| **NY GBL §349-a** | **Effective 2025-11-10**, upheld in *NRF v. James* (S.D.N.Y. 2025-10-08) | Compels the disclosure "THIS PRICE WAS SET BY AN ALGORITHM USING YOUR PERSONAL DATA" wherever personalised algorithmic pricing is displayed |

Adjacent: **CA AB 325** (effective 2026-01-01) makes a shared competitor-data-fed pricing algorithm a
Cartwright Act exposure, and four states have introduced ESL bills that include a prohibition on any
linkage between sensed personal data and a displayed price.

The decisive point is the same one behind ADR 0029: in the Enschede decision the Dutch DPA penalised
the *capability* to track, absent evidence of tracking. Liability here attaches to the capability of
the linkage as much as to its use. A reference data model that makes the join easy is a reference
data model that makes the exposure easy.

## Decision

**Sensing signals are never an upstream dependency of pricing.** This is an architectural invariant of
the model, not a usage guideline:

1. **No CSS sensing table or view may appear in the lineage of any price-producing table or view.**
   Enforced by `css_no_sensing_to_pricing_lineage`, a DQ check at **error** severity that walks the
   dependency graph rather than relying on reviewer vigilance.
2. **`esl_price_event.sensing_derived_input_flag`** exists and carries a CHECK constraint that it is
   FALSE. The column is present specifically so the invariant is visible in the schema and any attempt
   to violate it has to be an explicit, reviewable act.
3. **The price-actuation layer records its own compliance context** — `algorithmic_pricing_flag`,
   `personal_data_used_flag`, `disclosure_text_shown`, and `discount_basis_code` — so a deployment that
   *does* do personalised pricing from some other lawful basis can evidence the NY §349-a disclosure.
   CSS models the disclosure; it does not enable the practice.
4. A future **Dynamic Pricing** package *consumes* the ESL actuation layer rather than re-modelling it,
   and inherits this invariant.

## Consequences

- Genuinely useful analytics are foreclosed: "raise price when the aisle is busy" is unbuildable in
  this model. That is the intent. A retailer wanting it must build it outside ORDM and own the
  compliance analysis themselves.
- The invariant needs a *mechanical* check because it is exactly the kind of rule that erodes: the join
  is one line of SQL, and the reason not to write it is not visible from the table definitions. The
  lineage check is the load-bearing part of this ADR; the flag column alone would not survive.
- `price_source` is modelled independently of this decision (NIST Handbook 44 — random-weight items are
  priced from the scale's own PLU memory, not the POS database), so "the price" is not assumed to have
  a single authoritative origin. That matters here because a check on price lineage has to know which
  lineage it is checking.
- Revisit only if the legal landscape reverses, which currently trends the other way. Note the
  ESL-specific bills (WA SB 6312, NJ S3612/S3952, MN SF 4199, NY S8616) are introduced rather than
  enacted and should be re-checked before any external claim is made about compliance posture.
