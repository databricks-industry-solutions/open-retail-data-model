# ADR 0042 — Market Analysis reads the BMV competitor foundation

**Status:** Accepted (2026-10-09; proposed 2026-08-24) by the maintainer, @Tagar. Market Analysis is `done`, confirmed by its use-case owner (@saurabhshukla-db) on 2026-10-09, with the KPI validation and this ratification recorded on #165. The maintainer ratifies as Balancing Margin and Volume's interim owner and reviewer.

## Context

Balancing Margin and Volume owns the current `competitor` SCD2 identity and
`competitor_price` observation fact. Market Analysis belongs to Actionable Customer
Understanding and needs every competitor observation to produce category-level price,
promotion-presence, and availability context. Re-declaring competitor identity in ACU
would create two sources of truth; reading BMV's cheapest-competitor gold view would
discard competitors and use the wrong grain.

The core-versus-outcome promotion test in CONTRIBUTING §6 treats reuse, conformed
dimension semantics, and independence from outcome state as promotion signals. This is
the second outcome consumer of competitor identity, so the dependency must be explicit
even though it is not a layer-inversion foreign key.

## Decision

Market Analysis may read BMV's `competitor` and `competitor_price` objects directly as
a sanctioned read-only cross-package dependency. BMV remains their sole owner for now;
ACU adds neither a duplicate competitor dimension nor a foreign key into BMV. The ACU
gold view reads the observation fact rather than BMV gold, aggregates on durable
`competitor_id` and `product_id`, and resolves the competitor SCD2 display name only
after aggregation.

Market Analysis may also read canonical marketing `promotion` plus Promote with
Purpose's `promotion_scope` bridge as a sanctioned read-only cross-package dependency
for own promoted product-days. This does not change ADR 0006's placement: promotion
identity stays canonical while the outcome-specific scope bridge stays with Promote
with Purpose. ACU declares that dependency and deploys after the bridge is available.

`benchmark_cell_id` deliberately includes adopter-owned `category_ref` because no
portable provider-category identity ships in this interface and category is part of
the delivered analytical grain. A category remap therefore creates a new logical cell
instead of silently rewriting prior evidence. Adopters must govern a remap as an
effective-dated migration/backfill and suppress the superseded mapping before serving;
a future provider-native category key requires a versioned contract change.

Promotion to canonical core is deferred until a third independent outcome needs the
competitor foundation or maintainers decide the two-package deploy-order coupling has
become material. That change follows CONTRIBUTING §6: open a change proposal, move the
shared objects into a canonical-core domain, and re-point both packages in one
coordinated change. The future decision must separately assess identity and price
observations; one need not move merely because the other does.

Market Analysis remains decision support only. It may consume public or licensed
aggregate competitor observations, but its gold or metric surfaces may never become an
upstream dependency of a price-producing surface.

The deployed wall uses two registry dimensions together. `price_producing_scopes`
enumerates schemas that own retail price, promotion, offer, margin, elasticity or price-
accuracy decision outputs: BMV, canonical product, SDI, Promote with Purpose and
Connected Store Signals. `price_producing_name_pattern` then limits the runtime scan in
those schemas to views whose names match `price|margin|offer|elasticity|cost|promo`.
Keeping the name filter is required for the lean single-schema deploy, where unrelated
packages intentionally collapse into one schema.

The name pattern is intentionally broader than any one scope's current files, but it is
not a declaration that every lexical match is price-producing. The canonical marketing
`promotion` table is an input dimension, not a price-producing view. Predictive
Operations' `maintenance_cost` metric is equipment operating expense, not retail price,
margin, promotion or offer output. ACU's own protected Market Analysis objects are
excluded by object name so the wall does not reject their definitions. A future package
that adds a matching retail decision view must either join `price_producing_scopes` or
record an ADR-grounded non-pricing exception; the static test inventories current
matching view owners so registry coverage cannot silently narrow again.

## Consequences

- ACU declares BMV in its dependency closure and therefore deploys after the BMV
  competitor foundation.
- ACU also declares Promote with Purpose and deploys after `promotion_scope`; the
  dependency is read-only and leaves ADR 0006's canonical/outcome placement intact.
- BMV remains the single source of truth; no duplicate competitor master is created.
- Durable business keys preserve cross-deployment portability while version-specific
  surrogates retain correct fact-to-dimension history joins.
- Adopter category remaps intentionally fork benchmark cell identity and require a
  governed migration/backfill so old and new mappings are not served together.
- The deployed guard resolves price-producing schemas from the policy registry in
  `standards/rules.yaml`; the static guard globs every other outcome gold/metric SQL
  file plus all canonical SQL, covering future packages and committed MV definitions.
- Promote with Purpose and Connected Store Signals are included in the deployed scan
  because their promo/offer and price-accuracy surfaces can feed retail decisions even
  though they are not the BMV competitor foundation read sanctioned by this ADR.
- A second registry blocks `market_benchmark`, `gold_market_share` and
  `mv_market_share` from Data Sharing with Suppliers, the repository owner of
  supplier-sharing, clean-room and Delta-Sharing publication surfaces.
- The current generator registry permits one provider per schema key, so Market
  Analysis remains inside the `customer_ltv` ACU provider. Its BMV dependency moves
  `customer_ltv` to generator wave 4 and `agentic_commerce` to wave 5. Splitting an
  ACU writer is deferred until the registry supports multiple coordinated providers.
- V1 recomputes market share from subject and total-category sales while retaining
  provider share for reconciliation. `fair_share_gap_pct` stays deferred because the
  licensed pass-through distribution fields are non-additive and no additive
  footprint denominator ships. Detection publishes dimension-specific means, not
  medians; top-N digital share-of-shelf and dbldatagen-scale fact generation are also
  explicit follow-ons.
- A third consuming outcome triggers a fresh promotion review rather than silently
  expanding the sanctioned exception.
