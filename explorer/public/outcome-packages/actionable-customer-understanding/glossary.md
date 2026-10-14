# Actionable Customer Understanding — Business Glossary

> Status: 🟢 Review complete (0.5) · Last reviewed: 2026-10-07

Business terms for Customer Lifetime Value, Behavioral Segmentation and Market Analysis. Vendor-neutral; follows the ORDM [data model principles](https://github.com/databricks-industry-solutions/open-retail-data-model/blob/main/docs/data-model-standards.md).

## Tables & view

| Object | Grain | Description |
|---|---|---|
| `customer_order_line` (canonical-core) | One customer × order × product line | Customer-attributed purchases (the base for per-customer value + behavioral signals). |
| `gold_customer_ltv` | One customer (by surrogate) | Historical + predicted CLV, RFM segmentation, value tiers. Keys on the surrogate; **no raw PII**. |
| `gold_customer_behavioral_attributes` | One customer (by durable `profile_id`) | Wide, agent-discoverable behavioral trait surface (cadence, affinity, lifecycle stage, promo responsiveness) + value/RFM attributes surfaced from `gold_customer_ltv`. No raw PII. |
| `segment_membership` | One `profile_id` × `audience_id` × `as_of_date` (append-only) | Which customers belong to which segment, as of an evaluation date. Targeting plane only. |
| `marketing.audience` (canonical-core) | One segment definition (SCD2) | The shared segment/audience **definition** catalog membership references (ADR 0022). |
| `competitor_promotion` | One append-only source promotion observation | Competitor promotion type, vehicle, pricing, window and placement with point-in-time match snapshot. |
| `competitor_assortment` | One append-only competitor-item listing/availability observation | Sparse matched or unmatched listing state, stock state, channel, location sentinel and search rank. |
| `competitor_product_match` | One durable competitor × competitor-item Type-1 association | Current provenance match, method, type, confidence and verification dates; ID excludes mutable `product_id`. V1 serving uses observation snapshots and warns on registry drift. |
| `market_benchmark` | One delivered version of a stable licensed benchmark cell | Provider market/geography/category/subject/period measures with append-only restatement lineage. |
| `gold_competitive_position` | One category × durable `competitor_id` × `channel_code` × fiscal period | Observation-native price, promotion, distribution, availability, assortment, matching and detection-bound synthesis. |
| `mv_competitive_position` | Governed metric surface over `gold_competitive_position` | Reaggregation-safe measures computed from additive components. Count-based shares/rates divide count sums; price indices and discount depth are observation-level means. Assortment rollups across competitors/channels are presence-weighted per-grain averages, not own-catalog unions. |
| `gold_market_share` | One current stable cell at provider market definition × geography × category × non-total subject × period | Latest-wins licensed market benchmark with additive subject and total-category sales components; denominator-only total-category cells are not served. |
| `mv_market_share` | Governed metric surface over `gold_market_share` | Market share recomputed from subject-sales/market-size ratio-of-sums, separate from competitive-position grain. |
| `gold_product_affinity_pairwise` | One directed product pair × time window (`product_id_a` × `product_id_b` × `time_window`) | Market-basket association rules (support/confidence/lift) over order baskets — "frequently bought together". Derived from `customer_order_line`; no PII. |
| `gold_customer_product_affinity` | One customer × product (`profile_id` × `product_id`) | Individualized recency-weighted PURCHASE-HISTORY affinity score for each product a customer has bought. Keyed on the pseudonymous `profile_id`; no raw PII. |
| `mv_product_affinity` | Governed metric surface over `gold_customer_product_affinity` | Customer→product affinity reach and average strength by category/brand/driver/band. Means are ratio-of-sums. |

## Terms

| Term | Definition |
|---|---|
| **CLV — historical** (`historical_clv`) | Total **realized gross margin** to date: `SUM(net_amount − units × unit_cost)`. Can be negative (a real loss). |
| **CLV — predicted** (`predicted_clv`) | A transparent forward estimate, **NOT an ML model**: `avg_order_margin × frequency_per_period × expected_active_periods`, clamped to ≥ 0. `expected_active_periods = GREATEST(0, LEAST(tenure_periods, HORIZON_CAP=12) − recency_periods)` — loyalty (tenure) extends the horizon, recency shrinks it. A **heuristic starter metric**; if/when an MLflow model exists it can replace this (follow-up, not pulled into the view). |
| **Recency** (`recency_periods`) | Fiscal periods (NRF 4-5-4) since the customer's last order. |
| **Frequency** (`frequency`) | Distinct purchase occasions (`order_id`) in the observation window. |
| **Monetary** (`total_spend`, `avg_order_value`) | Total net spend and spend per order. |
| **RFM** (`r_score`, `f_score`, `m_score`, `rfm_score`) | Recency, Frequency, Monetary each scored 1–5 from **stable fixed thresholds** (not population `NTILE`), so a customer's score is **reproducible across refreshes** and changes only when their own behavior crosses a cutoff. **5 = best** (most recent / frequent / highest spend). `rfm_score = 100·R + 10·F + M` (classic 111–555 cell). Raw recency/frequency/spend stay exposed so a consumer can rebucket. |
| **Value tier** (`value_tier`) | `historical_clv` bucketed on **stable fixed thresholds** (PLATINUM ≥ 2500 / GOLD ≥ 1000 / SILVER ≥ 250 / BRONZE else), not an `NTILE(4)` quartile — reproducible across refreshes for a frozen campaign audience. Thresholds (and the monetary M cutoffs) are in the deploy's **base/reporting currency**, whole units — illustrative mid-market retail defaults adopters retune to their own currency/basket size. |
| **Churn-risk proxy** (`churn_risk_proxy`) | Heuristic flag: recency > 2.0 × the customer's own average cadence (`tenure_periods / frequency`). Clearly a proxy, not a model. |

### Behavioral Segmentation

| Term | Definition |
|---|---|
| **Behavioral segmentation** | Grouping customers by **observed actions** (purchase cadence, category/brand affinity, promo responsiveness, lifecycle stage) — distinct from value/RFM (worth) and demographic (identity). Reuses the RFM/value scores as attributes rather than recomputing them. |
| **Trait surface** (`gold_customer_behavioral_attributes`) | The wide, one-row-per-customer, agent-discoverable set of behavioral + value traits a CDP composes custom audiences from. Keyed on the durable `profile_id`; no raw PII. |
| **Lifecycle stage** (`lifecycle_stage`) | Behaviorally-derived relationship phase: `new` / `active` / `lapsing` / `churned`, from recency vs the customer's own purchase cadence. |
| **Category / brand affinity** (`top_category`, `top_brand`, `distinct_categories`, `distinct_brands`) | The category/brand a customer spends the most net revenue in, plus the breadth of categories/brands purchased. |
| **Promo purchase share** (`promo_purchase_share_ratio`) | Share of net spend on discounted lines (net < gross) — a promo-responsiveness signal, 0–1. |
| **Opt-in status** (`opt_in_status`) | Marketing consent surfaced as a **discoverable attribute** (`opted_in` / `opted_out` / `unknown`). NOT the legal source of truth (that is canonical-core `consent`) and never the activation gate. |
| **Segment definition** (`marketing.audience`) | The named, versioned rule/criteria for a segment (shared silver dimension, ADR 0022). Definition only — no member lists, no PII. |
| **Segment membership** (`segment_membership`) | Which customers belong to which segment, as of an evaluation date (append-only snapshots). `membership_status`: realized / existing / exited. Targeting plane only — carries no consent flags. |
| **Activatable audience** (`gold_activatable_audience_current`, in UCV) | Segment membership intersected with the consent+preference+reachability gate — the reverse-ETL-ready surface of who may actually be contacted per purpose × channel. The one place the three planes combine. |

### Clickstream / interaction traits (ADR 0029)

Derived from the conformed `interaction.touchpoint` fact (stitched, `profile_id`-resolved touches only). Available for purchasers who also have stitched touches (the trait surface is purchaser-grained in v1; widening to zero-order browsers is a named follow-on). **These traits are LIFETIME-grained** — every touch a profile ever made, deliberately NOT the fiscal observation window the RFM/behavioral traits use — so pair them with `last_interaction_date` for recency; bounding them to the RFM window is a deferred follow-on.

| Term | Definition |
|---|---|
| **Interaction count** (`interaction_count`) | Count of meaningful engagement touches — excludes session bookkeeping verbs (`session_start` / `session_end` / `app_open`). |
| **Session count** (`session_count`) | Distinct `session_id` values observed for the customer. |
| **Last interaction date** (`last_interaction_date`) | Most recent touch `event_date`. |
| **Average digital dwell** (`avg_digital_dwell_seconds`) | Mean page-dwell seconds over **digital** engagement touches (`web` / `mobile_app`) only. Restricted to one modality because `touchpoint.dwell_seconds` is cross-modal (page dwell vs call duration vs store-visit length are not comparable). |
| **Channel-mix shares** (`digital_interaction_share`, `in_store_interaction_share`, `call_center_interaction_share`) | Share of the customer's touches on each plane. **Non-exhaustive** — they do NOT sum to 1 (channels like `kiosk` / `direct_mail` are not counted in any of the three). |
| **Search intent** (`has_search_intent_flag`) | The customer performed at least one `search` touch. |
| **Cart activity** (`has_cart_activity_flag`) | The customer performed at least one `add_to_cart` touch. |
| **Cart-without-checkout** (`cart_without_checkout_flag`) | Added to cart but never reached `checkout_start`. **Lifetime-grained** and **checkout-reached, not purchase-confirmed** — a coarse abandonment proxy over all observed touches, not a per-session or per-order signal. |

### Product Affinity

Two complementary recommendation modalities, both derived from the canonical-core order fact (`customer_order_line`) — no ML, no stored affinity table, no synthetic producer.

> **Synthetic-data note (why the "frequently bought together" table is sparse in the demo):** raw uniform-random baskets carry no real co-purchase correlation, so almost nothing clears `min_lift = 1.05`. The shipped demo keeps `customer_order_line` a **strictly neutral uniform draw** — the co-purchase seeding (`affinity_copurchase_denom`, `seeds.yaml`) is shipped **OFF** (`= 0`) so no one package's demo need reshapes the shared fact CLV, Behavioral Segmentation and Market Analysis read. So `gold_product_affinity_pairwise` is **intentionally sparse/empty on the shipped demo data**, and its `severity: error` checks pass vacuously there — expected, not a defect. The market-basket algebra and trailing windows are proven on a correlated fixture, and end-to-end on the real generator with seeding enabled, in `tests/test_product_affinity.py`. To populate the surface (e.g. for a demo), set `affinity_copurchase_denom` > 0 — that seeds a light, deterministic co-purchase pattern (first two lines of ~1/denom multi-line baskets) but then lightly shapes the shared order fact. The customer→product affinity surface (`gold_customer_product_affinity`) needs no co-occurrence and is unaffected either way.

| Term | Definition |
|---|---|
| **Market basket analysis** | Finding products that co-occur in the same basket (order) more than chance would predict. The rules-based "frequently bought together" engine behind `gold_product_affinity_pairwise`. |
| **Basket** | One order (`order_id`) — a purchase occasion. A product counts once per basket (repeat lines of a SKU in one order collapse to a single co-occurrence unit). |
| **Support** (`support`) | `cooccurrence_baskets / total_baskets` — how common a pair is across all baskets (0..1). Symmetric in A and B. |
| **Confidence** (`confidence`) | `cooccurrence_baskets / antecedent_baskets` = P(basket contains B \| basket contains A), 0..1. **Directional** (A→B ≠ B→A), which is why both directions are emitted. |
| **Lift** (`lift`) | `support(A,B) / (support(A) × support(B))` — association strength vs. statistical independence. **> 1** = positive/meaningful co-purchase, **= 1** = independent, **< 1** = substitutes (rarely bought together). The primary ranking signal. |
| **Pruning constants** | Illustrative retail defaults keeping noise off the serving surface: `MIN_ITEM_BASKETS=5`, `MIN_PAIR_BASKETS=3`, `MIN_SUPPORT=0.0002`, `MIN_CONFIDENCE=0.02`, `MIN_LIFT=1.05`. Adopters retune (one place: the constants + final WHERE in `gold_product_affinity_pairwise`). |
| **Time window** (`time_window`) | The trailing window a rule is computed over: `30D` / `90D` / `ALL_TIME` (the source model's grain axis). Trailing cutoffs are anchored to `MAX(order_date)` (not `CURRENT_DATE`, so the surface is reproducible on historical data). `support`/`confidence`/`lift` are recomputed independently per window, so a pair can rank differently — or drop out — in a shorter window as recent behavior shifts. |
| **Customer→product affinity** (`gold_customer_product_affinity`) | Per-customer, per-product affinity score in [0,1]: `LEAST(1, purchase_intensity × recency_weight)`. Transparent heuristic, **not an ML model** (mirrors `predicted_clv`'s stance). |
| **Purchase intensity** | `LEAST(1, purchase_count / TARGET_REPEAT)`, `TARGET_REPEAT=5` — repeat-purchase depth normalized to [0,1]. |
| **Recency weight** (`recency_weight`) | `pow(0.5, days_since_last_purchase / 90)` — exponential time-decay in (0,1] with a 90-day half-life. |
| **Affinity band** (`affinity_band`) | Coarse strength bucket: `high` (≥0.6) / `medium` (≥0.2) / `low`. |
| **Primary driver** (`primary_driver`) | What an affinity is derived from. v1 is always `PURCHASE_HISTORY`; the source model's `BROWSE_BEHAVIOR` and latent/embedding (ML vector) drivers are a documented follow-on. |
| **Deferred: ML vector modality** | The source model's `dim_product_embedding` / `dim_customer_embedding` (pgvector `VECTOR(768)` + ANN/HNSW cosine search) are **out of v1 scope**. On Databricks this is Vector Search synced from Delta, not stored pgvector columns/indexes (ORDM's strict typing has no `VECTOR` type). It solves cold-start (new items) and latent discovery, and layers on top of this data model rather than living in it. |

### Market Analysis / UC-RET-0021 Competitive & Market Intelligence

| Term | Definition |
|---|---|
| **Price index vs competitor** (`price_index_vs_competitor`) | `100 × SUM(own list price ÷ competitor MRP) ÷ SUM(valid price observations)` over positive, same-currency product-day pairs. This is an unweighted arithmetic mean of price relatives, not a ratio of aggregate own and competitor price totals. 100 = parity; above 100 means own list price is higher. Metric-view rollups use the additive ratio sum and count rather than averaging already-aggregated gold-row indices. |
| **Sales-weighted price index** (`sales_weighted_price_index_vs_competitor`) | `100 × SUM(own-list/competitor-MRP ratio × matched own units) ÷ SUM(matched own units)`. This is an own-unit-weighted arithmetic mean of price relatives, not a value index or ratio of aggregate price totals. Only positive own units on usable regular-price-pair product-days enter the denominator. Use this arm when own-unit importance weighting is desired. |
| **Usable price-product coverage** (`price_observation_coverage_pct`) | Distinct observed price products with at least one usable regular-price pair divided by all matched products in competitor-price observations. No `LEAST(100, …)` mask is applied. |
| **Promotion share of voice** (`promo_sov_pct`) | Own promoted product-day presence divided by own plus competitor promoted presence over the same own product-days covered by any price, promotion or assortment competitor observation. This is one promoted-product-day observation basis; vehicle placement and syndicated spend/volume bases are not blended. |
| **Observed availability rate** (`availability_rate_pct`) | Available listed assortment observations divided by listed observations with a non-null availability state. This is not numeric distribution, %ACV or TDP. |
| **Unmatched listed-item presence** (`unmatched_listed_item_present_flag`) | Match-quality signal that a listed competitor item lacks a confidence-qualified exact/equivalent own-product match. It is not a directional distribution gap; that KPI needs own channel-ranging presence and is deferred. |
| **Points of availability** (`points_of_availability_count`) | Distinct observed listing locations within each gold grain. National v1 observations use the sentinel `ALL`, so the measure is a detection count, not an outlet-estate claim. |
| **Listed channel count** (`listed_channel_count`) | Distinct channels with a listed item per category × competitor × period, computed before the channel-row split. It is non-additive across channel rows. |
| **Listed share** (`listed_share_pct`) | Listed observations divided by all competitor assortment observations on the selected grains. Sparse observation coverage is not imputed. |
| **Assortment overlap / uniqueness** (`assortment_overlap_pct`, `assortment_uniqueness_pct`) | Confidence-qualified exact/equivalent active-own matches divided by observed active own products; uniqueness is the complement. `own_catalog_observation_coverage_pct` exposes the full-catalog gap on the gold view at base grain and is deliberately not a metric-view measure because it is only well-defined there; `matched_listed_inactive_product_count` publishes excluded matches. Across competitors/channels these ratios are presence-weighted per-grain averages, not set unions. |
| **Assortment Jaccard index** (`assortment_jaccard_index_pct`) | Product-space intersection divided by `observed active own products + unmatched listed competitor items`, at category × competitor × channel × period grain. Cross-competitor/channel rollups are weighted averages, not a global union. |
| **Match coverage** (`match_coverage_pct`) | Listed competitor items carrying an exact/equivalent product match at confidence ≥0.80 divided by all listed competitor items. Unmatched items remain in the denominator. |
| **Detection-lag upper bound** (`avg_detection_lag_upper_bound_days`) | Ratio-of-sums mean of displayed-promotion-start lag and prior-to-changed-assortment-observation intervals. `avg_promotion_detection_lag_days` and `avg_assortment_detection_lag_days` keep dimensions separate. It is a bound, not exact event-to-alert latency; median/percentile is deferred and cadence is disclosed. |
| **Current market benchmark cell** | The delivered `market_benchmark` version ranked first within `benchmark_cell_id` by provider update/observation timestamp, then load timestamp and delivered-version key. Source history is never updated away. |
| **Market share** (`mv_market_share.market_share_pct`) | `100 × SUM(subject sales) ÷ SUM(matching total-category sales)` at the declared market definition, geography, category, non-total subject and provider period. Total-category cells supply denominators internally but are not served as subjects. Provider-reported share remains a separate reconciliation field. |
| **Comparable promo day** (`comparable_promo_day_count`) | A date with at least one product observation where own and competitor promotion status are both known. Across already-aggregated competitors/periods, its sum is competitor-days, not globally distinct calendar days. |
| **Market Analysis grain** | Competitive position is category × durable competitor × channel × fiscal period; price uses national `all`, while promotion/assortment retain observed channel. `measure_scope` is one of `price`, `promotion`, `assortment`, or `promotion_assortment`; combined price scopes are unreachable by design. Market share stays separate at provider market-definition × geography × category × non-total subject × period grain. |

### Five distinct “share” senses

| Term | Definition |
|---|---|
| **Share of market** | Licensed sales or unit share for a declared provider `market_definition`, geography, category, non-total subject and provider period. Total-category cells are denominator-only inputs. It lives in separate `gold_market_share` / `mv_market_share` surfaces, not competitive-position grain. |
| **Share of shelf** | Physical share of facings. CSS can measure own-store shelf state; a competitor claim requires a separate imagery/sensing program. |
| **Share of voice** | Promotion presence share on one explicitly declared comparable matched-product-day basis; placement and syndicated spend/volume bases are not blended into it. |
| **Share of search** | Digital visibility within ranked search results. V1 publishes ratio-of-sums average observed rank; top-N search-slot share (digital share-of-shelf) is deferred, so average rank is not relabelled as a share. |
| **Visit share** | Directional share inferred from an anonymized location-intelligence panel. It is neither market sales share nor person-level data in ORDM and is not implemented. |

### Compliance and licensing

Market Analysis contains competitor and aggregate market data only—no profile, household, interaction, session or other person-level source. It may read BMV competitor observations, but its outputs are forbidden upstream dependencies of price-producing surfaces. ORDM ships synthetic rows only; licensed benchmark/promo data remains internal-use-only and excluded from sharing by default. MAP/RPM enforcement is out of scope.

## Customer-capability PII handling

The view keys on the customer **surrogate** (`profile_sk`) plus the pseudonymous business key `profile_id`. Raw PII — `loyalty_id`, `household_id`, names, date of birth — is **never** carried here; it stays in the governed `profile` dimension (tagged `dbx_pii_*`). A DQ check (`ltv_no_raw_pii`) and a test assert PII absence on the gold schema.
