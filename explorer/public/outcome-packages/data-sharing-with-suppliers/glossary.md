# Data Sharing with Suppliers — Business Glossary

> Status: ✅ Published (0.5) · Last reviewed: 2026-10-13

Business terms for this package's four use cases — Category Growth, Media Measurement, Joint Demand Planning, and Data Monetization. Vendor-neutral; follows the ORDM [data model standards](https://github.com/databricks-industry-solutions/open-retail-data-model/blob/main/docs/data-model-standards.md).

## Domain Brief — placement decision (Phase 0)

The Category Growth use case sits in the **Data Sharing with Suppliers** column but reads like merchandising/assortment analytics. Two interpretations were considered:

- **A — collaborative** (chosen): category growth analysed **with and attributed to suppliers** (joint business planning), reusing the supplier scorecard and procurement spend. Matches the column.
- **B — merchandising**: pure internal category performance, independent of supplier.

**Decision: Interpretation A.** It matches the column, no pre-existing category/assortment asset implied B, and the supplier scorecard + procurement data exist to support supplier attribution. `gold_category_growth` therefore exposes a `supplier_contribution` (top supplier's share of category procurement spend + scorecard composite) alongside the merchandising metrics. The merchandising metrics (decomposition, share) stand on their own, so the view is still useful if the supplier signal is absent.

## Object

| Object | Grain | Description |
|---|---|---|
| `gold_category_growth` | One category × fiscal period | Category performance, growth decomposition, and the integrated promo / customer-value / supplier signals. |

## Terms

| Term | Definition |
|---|---|
| **Category growth** | Period-over-period change in category revenue (`delta_revenue = category_revenue − prior_period_revenue`), with `pop_growth_pct` and `yoy_growth_pct` comparing **like fiscal periods** (period_index = `fiscal_year*12 + fiscal_period`; PoP = index−1, YoY = index−12). |
| **Growth decomposition** | `delta_revenue` split into four effects that **reconcile exactly**. With D = distribution points (distinct product × store), q = units/point, P = avg price (subscripts 0=prior, 1=current): **distribution** `= (D1−D0)·q0·P0`, **volume** `= D1·(q1−q0)·P0`, **price** `= U1·Σ_sc w1·(p1−p0)`, **mix** `= U1·Σ_sc (w1−w0)·p0` (over sub-categories sc, w = unit share, p = sub-category avg price). distribution + volume + price + mix = `delta_revenue`. |
| **Distribution effect** | Revenue change from broader/narrower availability (more or fewer product × store selling points). |
| **Volume effect** | Revenue change from selling more/fewer units per selling point, holding price and mix. |
| **Price effect** | Like-for-like price change within sub-categories. |
| **Mix effect** | Revenue change from shifting the sub-category mix toward higher/lower-priced sub-categories at constant sub-category prices. |
| **Category share** | `category_revenue / total revenue` for the period; sums to ~1.0 across categories. |
| **Promo contribution** | Incremental margin from `gold_promo_roi` attributable to the category that period (the share of growth that was promo-driven). NULL if the promo view is absent. |
| **Value-tier mix** | `value_share_platinum/gold/silver/bronze` — the split of customer-attributed category revenue across CLV value tiers (`gold_customer_ltv`), showing whether growth comes from high- or low-value customers. NULL if the LTV view is absent. |
| **Supplier contribution** (Interpretation A) | `top_supplier_id`, `supplier_top_share` (share of category procurement spend) and `supplier_top_score` (its scorecard composite). NULL if procurement/scorecard is absent. |

## Media Measurement (supplier media reporting)

The supplier-facing publish + entitlement layer over the Commerce Media Networks fact layer — how a retail-media
network shares measured campaign performance with each supplier/advertiser under access control, with an
immutable audit trail. Routes the media-measurement brief.

| Object | Grain | Description |
|---|---|---|
| `reporting_entitlement` | one version per (principal, advertiser, campaign-scope) | Row-level access anchor: which governance principal may see which advertiser (optionally one campaign) + the minimum disclosure threshold. SCD2. |
| `supplier_media_report_snapshot` | one publish snapshot × brand × campaign × level | Immutable frozen report — what was disclosed to a supplier at a point in time (audit/dispute), sourced from `campaign_day`. |
| `gold_supplier_media_report` | principal × brand × campaign | Entitled supplier report (row-filter source): the CMN `campaign_day` rolled to brand×campaign, joined to `reporting_entitlement`. No person-level data. |

| Term | Definition |
|---|---|
| **Reporting entitlement** | A grant letting a principal (UC group / account / service principal — not a customer) see a supplier's media results, brand-wide or campaign-scoped. |
| **Disclosure threshold** | Minimum aggregation count a row must meet before it is shared with a supplier (privacy/competitive protection). |
| **Published snapshot** | An immutable, versioned freeze of the numbers shared with a supplier, so a later restatement doesn't change the historical disclosure. |

Builds on: `commerce-media-networks` (`campaign_day`) and `commerce-media-networks` (`advertiser`, `campaign`).
Deferred: Lakebase serving projections (`api_supplier_campaign_summary`, `api_user_supplier_map`).

## Joint Demand Planning (CPFR)

Collaborative Planning, Forecasting and Replenishment (CPFR): a retailer and its suppliers jointly
build, submit, reconcile and freeze a **consensus demand forecast** under row-level access control,
with an immutable agreed snapshot for accountability. Each party submits its own versioned plan; the
reconciliation view aligns them, an exception queue surfaces disagreement and gaps, and the published
consensus is frozen so a later restatement never changes what was already agreed. Builds only on the
canonical core (`supplier`, `product`; fiscal weeks as a degenerate `fiscal_week_id`, no calendar FK); NULL-safe enriches with the Smarter Demand package's
statistical baseline (no hard dependency).

| Object | Grain | Description |
|---|---|---|
| `demand_collaboration` | one version per (principal, supplier, product-scope) | Row-level access + scope anchor: which governance principal collaborates on which supplier's plan (optionally one product), the agreed horizon, and the minimum disclosure threshold. SCD2. |
| `demand_plan_submission` | (plan cycle × party × supplier × product × week × version) | Each party's versioned demand-forecast submission (retailer plan and supplier plan land as separate rows; latest version wins). |
| `consensus_forecast_snapshot` | one publish snapshot × supplier × product × week × version | Immutable frozen consensus — the agreed numbers (and each side's number at agreement) at a point in time (audit/dispute). |
| `gold_joint_demand_plan` | principal × supplier × product × week | Entitled joint plan (row-filter source): latest retailer/supplier submissions + latest consensus, NULL-safe statistical baseline. No person-level data. |
| `gold_demand_plan_exceptions` | principal × supplier × product × week | The joint-plan rows needing collaborative attention, ranked by demand value at risk. |

| Term | Definition |
|---|---|
| **Collaborative forecast (CPFR)** | A demand forecast a retailer and supplier build together, submitting their own plans and agreeing a consensus, rather than each planning in isolation. |
| **Plan cycle** | A consensus round (e.g. a monthly CPFR cadence) that groups the submissions and the consensus that reconcile within it (`plan_cycle_id`). |
| **Demand plan submission** | One party's versioned forecast for a supplier × product × fiscal week; a resubmission bumps `submission_version`, and the latest wins in reconciliation. |
| **Consensus demand** | The agreed joint forecast quantity/value for a supplier × product × week, frozen as an immutable versioned snapshot (`consensus_forecast_snapshot`). |
| **Plan variance / disagreement** | `plan_variance_pct = (retailer_qty − supplier_qty) / supplier_qty` — how far the two parties' latest plans diverge. |
| **Consensus lift over baseline** | `consensus_vs_baseline_pct = (consensus_qty − statistical_forecast_qty) / statistical_forecast_qty` — the collaboration's demand signal above the statistical forecast (NULL if the Smarter Demand package is absent). |
| **Exception** | A plan row raised for attention: a missing party plan, a party disagreement beyond tolerance, or a consensus that diverges materially from the statistical baseline. |
| **Disclosure threshold** | Minimum demand volume (units) a plan row must reach before it is shared with a partner — a low-volume/materiality floor, **not** a k-anonymity control (the shared rows are already aggregate at supplier × product × week and carry no underlying entity count). A NULL threshold means no floor. |

Builds on: canonical core `supplier`, `product` (fiscal weeks as a degenerate `fiscal_week_id`, no calendar FK). NULL-safe enrichment:
`smarter-demand-and-inventory-decisions` (`gold_demand_forecast_weekly`) — read-only, no FK.

## Data Monetization

Turning the shared data itself into a revenue line: which data products a retailer offers its
suppliers, who has **licensed** them and on what commercial terms, what they actually
**consumed**, and what revenue that yielded — with the yield expressed against both the
contract and the partner's wider retail-media spend. Closes the monetization/billing capability
deferred in [ADR 0019](https://github.com/databricks-industry-solutions/open-retail-data-model/blob/main/governance/decisions/0019-media-measurement-in-data-sharing.md).
Where Media Measurement governs *who may see what* and Joint Demand Planning governs *what we
plan together*, Data Monetization answers *what that shared data is worth*.

Builds on the canonical core (`supplier`, `calendar`) and this package's own catalog; NULL-safe
enriches with the Commerce Media Networks package's campaign performance so a supplier
relationship can be reported as total monetised value (licensed data + media).

| Object | Grain | Description |
|---|---|---|
| `data_product` | one version per data product | Catalog of monetizable data products: what exists, how it is delivered, how it is charged, and its published rate card. SCD2, so a re-pricing never rewrites the rate a historical subscription was sold at. |
| `data_product_subscription` | one version per (principal, data product, supplier-scope) | The licence: which governance principal licensed which product, for which supplier scope, on what negotiated terms (price, committed allowance, term). Row-level access anchor + contract record. SCD2. |
| `data_share_consumption` | (subscription × data product × usage date) | The meter: what a licensed partner consumed each day and what that consumption billed. Append-only; fiscal period carried as a degenerate key. |
| `gold_data_product_revenue` | principal × data product × supplier-scope × fiscal period | Entitled data-monetization P&L (row-filter source): licensed terms, metered consumption, revenue, contract utilisation, and the NULL-safe retail-media comparison. No person-level data. |
| `gold_data_monetization_exceptions` | same, filtered to exceptions | The licence × period rows needing commercial attention, ranked by revenue at risk. |

| Term | Definition |
|---|---|
| **Data product** | A named, priced, licensable data asset a retailer offers its suppliers (a measured media report, a joint demand-plan feed, a category benchmark, an audience insight). Described by what it measures, never by a person. |
| **Rate card vs contracted price** | `data_product.list_price_amount` is the **published** rate; `data_product_subscription.contracted_price_amount` is the **negotiated** rate. The gap is the discount (`contract_discount_pct`). Both are kept so revenue can be reported at either. |
| **Subscription (licence)** | A grant letting a principal (UC group / account / service principal — not a customer) consume a data product, optionally scoped to one supplier, for a contractual term. A supplier-scoped licence outranks an all-supplier one when both cover the same usage, so consumption bills once. |
| **Pricing model** | How a product is charged: `subscription_flat` (fixed per period), `per_consumption_unit` (metered), `tiered`, or `revenue_share`. Only `per_consumption_unit` makes a per-unit rate directly comparable to the rate card. |
| **Consumption unit** | The unit usage is metered in (`query`, `row_scanned`, `report_delivery`, `api_call`). `consumption_units` is always denominated in the product's own unit, so units are only comparable within a product. |
| **Billable amount** | The money a day of consumption earned, **stored** rather than derived on read: a flat or tiered licence bills the same regardless of units, so units × rate would be wrong for three of the four pricing models. |
| **Contract utilisation** | `contract_utilisation_pct = consumption_units / contracted_units pro-rated to one fiscal period`. Because `contracted_units` is stated per **billing** period, a quarterly or annual commitment is divided by 3 or 12 before comparison — otherwise a month of usage measured against an annual allowance would understate utilisation twelve-fold. > 1 = ran over the commitment; near 0 = paid for and not used. |
| **Revenue per consumption unit** | `data_revenue_amount / consumption_units` — the price the partner effectively paid per unit. Compared against the rate card to detect mispriced usage. |
| **Total monetised value** | `data_revenue_amount + media_spend_net` — the whole commercial value of a supplier relationship for the period. At **row** level this is NULL-propagating (NULL if either component is absent, rather than presenting a partial sum as a total). The **metric view** instead COALESCEs the media term to 0, because only advertiser-scoped licences carry a media signal, so a bare addition would NULL the headline KPI for every other product; read `data_revenue_share_pct` (still NULL without media) to tell whether media contributed. Both sides are assumed to be in the one reporting currency — enforced within this package, conventional across the `commerce-media-networks` boundary (that gold view does not project a currency to check). |
| **Media allocation** | The advertiser's period retail-media spend is **allocated** across the licence rows sharing that advertiser, by revenue share, so per-row values sum back to the advertiser's actual spend. Fanning the whole total onto every row would double-count `SUM(media_spend_net)`. Same allocation contract as Joint Demand Planning's statistical baseline. |
| **Revenue at risk** | The money an exception exposes, used to rank the queue: the **contracted price** for an unused licence (what a non-renewal would cost), otherwise the realised revenue. |
| **Exception** | A licence × period row raised for attention: paid-but-unused, materially under-consumed, consumption beyond the commitment, a term lapsing within 90 days, or a realised unit price diverging materially from the rate card. |
| **Disclosure threshold** | Minimum consumption volume a period's usage must reach before it is shared with a partner — a low-volume/materiality floor, **not** a k-anonymity control (rows are already aggregate at licence × fiscal period and carry no underlying entity count). Below-floor usage is withheld by **NULLing the usage measures and setting `usage_suppressed_flag`**, not by dropping the row: a licence period that exists stays visible, since a silently missing period is indistinguishable from a licence that was never sold and would under-report the P&L. A NULL threshold means no floor, and a **zero-consumption row is never suppressed** — it reveals only the principal's own inactivity and is precisely the paid-but-unused signal the exception queue exists to raise. |
| **Withheld vs unused** | `usage_suppressed_flag` distinguishes the two NULL causes: measures are NULL because they were **withheld** (usage happened, below the floor) versus **genuinely unused** (no usage at all). Only the latter is an exception; the exception queue checks the flag first so a suppressed row never raises a false churn alarm. Distinct from `data_share_consumption.threshold_suppressed_flag`, which is set **upstream** on a source usage row and excludes it *before* aggregation; `usage_suppressed_flag` marks an aggregate that was computed and then withheld. |
| **Effective disclosure floor** | Two levels, most specific wins: the **subscription's** `min_disclosure_threshold` overrides the **data product's** catalog default. A floor is absent only when neither level sets one. |

Builds on: canonical core `supplier`, `calendar` (`fiscal_calendar`, for the fiscal-period spine);
`commerce-media-networks` (`advertiser`) as the licence's advertiser scope. NULL-safe enrichment:
`commerce-media-networks` (`gold_campaign_performance`) — read-only, no FK.
Deferred (logged): invoice/settlement documents — this use case reports revenue **earned**, it
does not issue or settle invoices, so `data_share_consumption` deliberately carries no invoice
reference (a billing run groups many usage days onto one invoice line, so that reference belongs
on a separate invoice-line table keyed to the meter, not as a column on it). Also deferred:
**revenue-share settlement** — the `revenue_share` pricing model is declarable in the catalog
but has no modeled revenue path, because its earnings depend on the partner's downstream sales,
which this model does not observe.
