# Changelog

All notable changes to ORDM are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). ORDM is pre-1.0. Each
release is dated in this file (0.1 and 0.2 were betas; from 0.5 on releases carry no
`-beta` label); new changes accumulate under **[Unreleased]** until the next one. The
authoritative per-domain and per-package state lives in [`STATUS.md`](STATUS.md); this
file is the chronological, project-level story — and a thank-you to everyone who has
shaped it. 🎉

Each entry links its pull request, and every PR credits its author (see the
[contributor graph](https://github.com/databricks-industry-solutions/open-retail-data-model/graphs/contributors)).

**Where things stand:** see [`STATUS.md`](STATUS.md), the single source of truth for
where each canonical-core domain and outcome package stands. README tables and the
per-folder status lines are generated from it; ladder definitions are in
[`definition-of-done.md`](docs/definition-of-done.md).

## [Unreleased]

<!-- Add new entries here, under the matching change-area heading (### Canonical core &
     data model, ### Outcome packages, ### Standards, governance & ADRs, ### CI &
     automation, ### Data contracts & synthetic data). -->

### Repository layout

- Follow-ups to the layout change: the package READMEs and `governance/README.md` no longer list
  the deleted `notebook-templates/` and `meeting-notes/` folders, `runtime/examples/README.md`
  lists `notebooks/`, and the per-PR workspace sync uploads only what the job reads
  (`runtime/synthetic-data`, `runtime/data-quality` and the deploy bootstrap SQL) instead of
  all of `runtime/` (#179)
- Model Explorer: the glossary copies under `explorer/public/` carry absolute source-repo URLs
  instead of repo-relative paths for files the site does not serve (the data-model standard, design
  notes, ADRs), so a reader can follow them from the raw glossary the site shows
  (`tools/gen_model_json.py`) (#179)

### Standards, governance & ADRs

- The initial-release self-review exception is off now that 0.5 is public. The self-reviewed
  deliverables 0.5 published stay ✅ while 0.5 is the current release; before the next release,
  each needs a second, independent sign-off or goes back to 🟢, and `gen_status.py --check`
  enforces it once `VERSION` moves past 0.5. `STATUS.md` records that `transaction`, `order` and
  `inventory` were published without the Lakebase binding the Definition of Done expects of the
  transactional spine; it is deferred until its generator exists. The `connected-store-signals` ✅
  gate is closed: ADR 0030's CSS-owner and Privacy scopes acknowledged ADR 0041's amendment and the
  DPO review is done, as the maintainer recorded on 2026-10-13 (ADRs 0030 and 0041 updated)
  (#181)

### CI & automation

- `tools/gen_status.py` also keeps the Status column of `canonical-core/README.md` and
  `outcome-packages/README.md` in step with `STATUS.md`: `--write` refreshes it and `--check`
  fails on a stale cell (#181)
- Dependency upgrades, folded from the first batch of Dependabot PRs: GitHub Actions
  `actions/setup-node` v7, `actions/upload-artifact` v7, `actions/download-artifact` v8,
  `actions/deploy-pages` v5 and `databricks/setup-cli` v1.20.0 (`checkout`, `setup-python`,
  `setup-java` and `upload-pages-artifact` follow in a later batch); explorer
  `@playwright/test` 1.64.0 and `cytoscape` 3.34.3. TypeScript 7 and jsdom 30 are left for a
  follow-up: TypeScript 7 rejects the side-effect CSS import, and jsdom 30 makes
  `window.document` read-only, which one explorer test relies on. The Python requirements stay
  lower bounds: Dependabot raises one only when a release falls outside its range
  (`versioning-strategy: increase-if-necessary`), and Python vulnerabilities are handled from
  Dependabot alerts (#204).
- Dependency updates are automated in the working repository: weekly grouped updates for the
  explorer's npm packages, the Python requirements (except the exactly pinned `sqlglot`) and the
  GitHub Actions. They reach this repository with each publication
  (#182).
- Explorer dev dependencies: vite 5 to 8.3.4 and vitest 2 to 5.0.4, which also brings
  `@vitest/mocker` 5.0.4, drops `tinypool`, and moves postcss to 8.5.30, nanoid to 3.3.20 and
  source-map-js to 1.2.2 (folded into one change). The explorer now needs Node 22.12 or later
  (`explorer/.nvmrc`)
  (#182).

## [0.5] — 2026-10-13

Use cases catch up with the model. All 41 declared use cases are done, and every use case
has governed KPIs as UC Metric Views. Seven became done in this release: Identity Resolution,
CDP, Market Analysis, Assortment Optimization, Realized Margin & Revenue Leakage, Associates
Best Next Actions and Digital Assistant Selling Tools, with populated gold views and metric
views on the demo deploy. Ten more deliverables are 🟢 Review complete, so all 15
canonical-core domains are. The Model Explorer follows lineage across packages, and a use case
can map to another package's gold view. The model version now has one source, `VERSION`, and
`make release` cuts a release. All file headers move to **0.5**, the first release without a
`-beta` label.

Published to the public repository as v0.5 on 2026-10-13: every canonical-core domain and
outcome package is ✅ Published, each as its own commit authored by the people who built it.

### Repository layout

- Fewer top-level folders (18 to 11). What runs on a workspace moves under `runtime/`
  (`runtime/synthetic-data/`, `runtime/data-quality/`, `runtime/examples/`, with the contracts
  notebook in `runtime/examples/notebooks/` and the bundle cleanup script in
  `runtime/examples/deploy-with-dab/`). The design notes move to `docs/design/`, and the
  overview diagram to `docs/diagrams/`. The bundle, CI, the per-PR deploy, the tests and every
  link follow the new paths.
  The bundle cleanup script and the contracts notebook, staging-only before, now publish with
  `runtime/examples/` (maintainer decision, 2026-10-13).
- Placeholder-only folders are gone: `dashboards/`, `scripts/`, `tools/validators/`,
  `governance/meeting-notes/`, `synthetic-data/samples/`, the empty `samples/` folders in nine
  core domains and six empty `notebook-templates/` folders, plus every `.gitkeep` and the two
  working notes under `docs/superpowers/`. Sample rows
  come from the generators; the docs no longer list a `samples/` folder.
- The review skill is marked staging-only in `docs/claude-skills.md`.

### Outcome packages

- **Every outcome package reached 🟢 Review complete** (and is ✅ Published in this release). `data-sharing-with-suppliers` is signed off
  (#177), a self-review disclosed in
  `REVIEWERS.md`; #165 had left it out until the Media Measurement fix (#163) merged. No `TODO(owner)`
  is left in any `use-cases.yaml`: the maintainer confirmed Realized Margin & Revenue Leakage done (it
  has no card owner), accepted the CDP status call in place of the card owner's confirmation,
  confirmed the `commerce-media-networks` and `balancing-margin-and-volume` `tables:` mappings, and
  recorded who confirmed the `smarter-demand-and-inventory-decisions` and `connected-store-signals`
  use cases (#178).
- **Governed KPIs for every use case.** The use cases that had none now have UC Metric Views, each
  checked against the deployed synthetic data:
  - **agentic-commerce:** `mv_intent_discovery_result_performance` (Result CTR, Add-to-Cart Rate,
    Discovery Conversion Rate) and `mv_intent_discovery_intents` (Zero-Result Rate) for Intent Product
    Discovery; `mv_conversational_shopping_session` (Assisted Conversion, Handoff and Fallback Rate) for
    Conversational Shopping Assistant.
  - **unified-customer-view:** the glossary metrics also ship as UC Metric Views: `mv_customer_360`
    (Customer 360 and Identity Resolution) and `mv_cdp_activation_eligibility`,
    `mv_cdp_activation_jobs` and `mv_cdp_campaign_touch` (CDP). The glossary stays the engine-neutral
    definition.
  - **actionable-customer-understanding:** `mv_customer_lifetime_value` over `gold_customer_ltv`
    (historical and predicted CLV, spend per order, frequency, recency, churn-risk share by value tier
    and RFM cell). It serves unified-customer-view's Customer Lifetime Value use case, which now maps
    to `gold_customer_ltv` across packages.
  - **data-sharing-with-suppliers:** `mv_category_growth` for Category Growth (revenue, units, margin,
    the four growth effects, period-over-period and year-over-year growth as SUM/SUM ratios, promo
    contribution). The gold view's per-row shares stay on `gold_category_growth`. (#172)
- **data-sharing-with-suppliers:** `gold_category_growth` no longer reports a price effect for a
  category's first period. With no prior period the price component fell back to the full average
  price, so `price_effect` equalled that period's whole revenue and inflated any roll-up of the
  effects; now `price_effect` and `mix_effect` are `NULL` there, like `delta_revenue` and the other two
  effects (#172)
- **unified-customer-view:** CDP is done. This is a maintainer status call (2026-10-12); the tracker
  card owner's confirmation is not recorded. Synthetic
  activation destinations, publish runs and campaign touches (`activation_destination`,
  `activation_job`, `campaign_touch`) now load in the demo deploy, so the activation metric views
  return rows (#172)
- **ai-assisted-store-associates:** `checks.sql` adds data-quality checks for the Best Next Actions
  and Digital Assistant Selling Tools gold views (`gold_associate_action_queue_current`,
  `gold_action_outcome_funnel_daily`): grain, allowed values, ranges and currency pairing (#172)
- **ai-assisted-store-associates:** Associates Best Next Actions and Digital Assistant Selling Tools now
  have demo data. The generator writes `associate` (projected from `labor.employee`), `suggested_action`,
  `action_response_log` and `outcome_resolution`, anchored to the run date: a 14-day history that feeds
  the outcome funnel and an open slice that keeps the action queue populated, so both gold views and
  `mv_associate_action_performance` return rows. The tables stay adopter-owned
  (#170)
- **ai-assisted-store-associates:** Associates Best Next Actions and Digital Assistant Selling Tools are
  done, so all three AASA use cases are done. Both gold views and `mv_associate_action_performance` are
  populated on the serving deploy. This was a maintainer status call; both tracker cards have since been
  set to Done
  (#171)
- **balancing-margin-and-volume:** Assortment Optimization is done. The four model outputs
  of `gold_assortment_optimization` that were `NULL` placeholders are now computed by
  heuristic estimators in SQL: `space_elasticity` (per category, cross-store and
  within-product, shrunk toward a 0.17 literature prior, with new `space_elasticity_se`
  and `space_elasticity_n_obs` columns), `projected_volume_lift`, `projected_margin_lift_lc`
  and `cannibalization_drag_lc` (scenario projections for each KEEP/DROP/EXPAND
  recommendation). `gold_affinity_features.substitute_demand_transfer_pct` is derived from
  substitute affinities. `avg_space_elasticity`, `total_projected_volume_lift`,
  `total_projected_margin_lift_lc` and `total_cannibalization_drag_lc` return to the
  assortment metric views. New DQ checks cover the elasticity range, projection signs and
  the transfer share (#167)
- **balancing-margin-and-volume:** Realized Margin & Revenue Leakage is done.
  `gold_realized_margin` (product x store x sale day, sale-cohort basis) computes booked
  revenue, realized revenue (settled sales minus refunds/chargebacks/adjustments), and revenue
  leakage from order unsettled sales and reversals, allocating by order-line net-amount share.
  `mv_realized_margin` exposes realized-margin KPIs (margin %, leakage and reversal rates,
  channel contribution) as ratio-of-sums measures. `mv_payment_actuals` surfaces
  payment-event-date (cash basis) leakage rates. New grain, identity, currency and
  conservation DQ checks (#168)
- **unified-customer-view:** Identity Resolution is done, on the scope recorded in
  [ADR 0044](governance/decisions/0044-identity-resolution-thin-core-scope.md) (Accepted):
  ORDM models the output of identity resolution (`customer.identity_link`, householding
  through `customer.household`, and the per-profile `active_identifier_count` and
  `resolved_identity_confidence` in `gold_unified_customer_360_current`), not the matching
  engine. The identity graph, merge/split log and match-rule catalog are deferred to a future
  package (#164)
- **data-sharing-with-suppliers:** `gold_supplier_media_report` (and
  `mv_supplier_media_report` on top of it) is readable on Databricks again: the
  most-specific-entitlement rule is an anti-join instead of a correlated subquery in the
  join condition. DSWS sample query 1 and Predictive Operations sample query 8 fixed
  (#163)

### Model Explorer

- The README's Explorer screenshot (`docs/images/explorer.png`) is re-captured from the current model:
  every use case of the 12 packages shows done (#172)
- A use case can map to another package's gold view with a qualified `<package>.<gold_view>` entry in
  `tables:` (validated like a local name). unified-customer-view's Customer Lifetime Value now maps to
  actionable-customer-understanding's `gold_customer_ltv`: its panel row links to that view, its
  consumed domains come from that view's lineage, and actionable-customer-understanding bands the view
  under "Customer Lifetime Value (unified-customer-view)" and lists it under "Also serves", so no gold
  view is left in "Not mapped to a use case" (#172)
- The unified-customer-view CDP use case maps all three of its gold views
  (`gold_person_do_not_target_current`, `gold_customer_activation_eligibility_current`,
  `gold_activatable_audience_current`, the Govern and Gate pieces of
  [`docs/cdp-composition.md`](docs/cdp-composition.md)), so the do-not-target set and the
  eligibility gate no longer sit in the "Not mapped to a use case" band. commerce-media-networks,
  whose four use cases had no `tables:` mapping at all, gets a provisional one, pending its
  owner's confirmation: each use case lists the gold views whose source facts conform that use
  case's brief (#169)
- The package and table side panels add a **GitHub** link to the unit's source folder, next to
  Glossary and Contract (`source_url` in `model.json`)
  (#169)
- Gold-view lineage follows references into other outcome packages and through chains of
  ingredient tables. A gold view reading another package's gold view or ingredient table (e.g.
  data-sharing-with-suppliers `gold_supplier_media_report` over commerce-media-networks
  `campaign_day`), or an ingredient whose core link is more than one FK away (e.g. `campaign` ->
  `advertiser` -> `supplier`), used to lose the core tables behind it, so its L1 lineage, its use
  cases' domain chips and its package's L0 edges were incomplete
  (#169)
- The explorer README lists all 15 core domains, and an e2e test that pointed at a renamed table
  (so it passed without checking anything) uses a real one and fails if the card is missing
  (#169)

### Standards, governance & ADRs

- **Interim self-review rule, initial release.** The 19 reviewer rows with no named owner now
  name the maintainer as interim owner, so the self-review check can see them, and REVIEWERS.md
  discloses every Owner = Reviewer row as a self-review. For the initial public release only, a
  self-reviewed deliverable may be Published on the maintainer's disclosed sign-off; from the next release a second, independent sign-off is required again
  (`INITIAL_PUBLICATION_SELF_REVIEW` in `tools/gen_status.py`)
  (#166)
- **Batch sign-off.** Ten deliverables move to 🟢 Review complete, signed off in
  #165: the labor,
  equipment and interaction core domains (the core badge reaches 15/15) and seven outcome
  packages. ADRs 0035–0041 are Accepted (0041 amends ADR 0030's ESL wording); Market Analysis is done, so
  ADR 0042 is Accepted; GOVERNANCE.md records the self-review rule (a disclosed
  self-review reaches 🟢; ✅ needs a second reviewer, except in the initial public release);
  the stale Calendar status in the canonical-core README is fixed
  (#166)

### Data contracts & synthetic data

- Synthetic sales respond to shelf space: the sales generator and the planogram generator
  derive a product x store's facings from one shared function, and units scale with a known
  per-category space elasticity, so the assortment estimator can be checked against a true
  value. Planogram coverage rises from 10% to 50% of product x store pairs (the configured
  density was previously ignored). Inventory positions now span the sales calendar instead
  of a fixed 2024, with a dense trailing window so the latest sales day has a position. A
  long-tail slow-mover tier and a thin-margin tail of SKUs give the assortment DROP and
  EXPAND rules real candidates; previously every synthetic row was KEEP
  (#167)
- Payment synthetic data (customer_ltv generator): refund probability now depends on store
  refund tier (deterministic by store_id hash: HIGH 2.0x, NORMAL 1.0x, LOW 0.5x of base rate;
  20%/60%/20% store distribution). Adjustments carry order_id on 80% of rows
  (ADJUSTMENT_ORPHAN_SHARE = 0.2), keeping the NULL-order rejection path exercised.
  Refunds, chargebacks and adjustments are now drawn only from orders whose sale was captured
  or settled; previously about 10% of reversals landed on authorization-only orders and drove
  realized revenue below zero. A full chargeback is no longer drawn on an order that was
  already partially refunded (#168)

### CI & automation

- `tests/test_metric_view_sources.py` checks every metric view's `source:` against the tables and
  views it reads, and its fields and measures against what the source exposes, so a missing column
  fails in CI instead of at CREATE time on the workspace (#172)
- The `unit + spark tests` job runs as 4 parallel shards (whole test files per shard, balanced on
  measured CI time per file, `tests/ci_test_durations.json`, refreshed with
  `tools/ci_test_durations.py`), each on every runner core via `pytest-xdist`, with the
  pip cache on. `tests/test_gen_model_json.py` builds the model once per process instead of once
  per test. The conformance gate, the drift guard and the repo-writing `writes_repo` tests run in
  shard 1, and a `test-summary` job keeps one "unit + spark tests" check
  (#174).
- A cluster-free guard rejects subquery predicates inside `JOIN ... ON` across all SQL,
  including metric-view source queries (#163)
- **Release tooling.** The model version has one source, the new `VERSION` file.
  `tools/release.py` (`make release NEW_VERSION=...`) rewrites it and every version stamp
  (file headers, notebook titles, `> Status:` lines) in one pass, cuts `[Unreleased]` to the
  dated release, and refuses a version that is not newer, an empty `[Unreleased]`, or merged
  PRs with no entry. `make check-version` (also a CI step) fails when any stamp disagrees
  with `VERSION`. The release steps, including the post-merge tag and GitHub Release, are in
  [`docs/releasing.md`](docs/releasing.md) (#173)

## [0.2-beta] — 2026-10-07

The status, review and contract plumbing catches up with the model. Status labels now
come from one source and 🟢 Review complete needs a recorded sign-off; Connected Store
Signals reaches 4/4 use cases done with a validated IoT serving layer; UC metric views
join the ODCS contracts; the per-PR deploy gate gets several times faster; and every
Markdown file was re-checked against the code. All file headers move to **0.2-beta**.

### Canonical core & data model

- `supplier.supplier_type` gets its enum CHECK (`chk_supplier_type`); "ADR 0034"
  citations that meant the labor ADR now cite ADR 0043; stale `audience` text in Commerce
  Media Networks now says it is a silver marketing dimension (ADR 0022)
  (#141)

### Outcome packages

- **connected-store-signals:** IoT Sensor Monitoring gets a serving layer (daily
  environmental compliance, excursion episodes, rule effectiveness, two metric views, a
  notebook template) evaluated from readings against the configured rule; synthetic
  excursions so the views populate; every gold column documented and typed;
  `mv_phantom_stock_candidates` and `mv_oos_episodes`; Foot Traffic Analysis and IoT Sensor
  Monitoring move to done, so 4/4 use cases are done (#144)
- **predictive-operations:** workforce forecast-accuracy column reference fixed, which
  unblocked the daily deploy (#139)

### Standards, governance & ADRs

- **One source of truth for status.** `STATUS.md` (package/domain ladder) and each
  package's `use-cases.yaml` (cards) are the only hand-edited status sources; the README
  badge and tables plus every per-folder "> Status:" line are generated and drift-gated.
  🟢 Review complete now needs an assigned Reviewer **and** a linked Sign-off issue in
  `REVIEWERS.md`, which `tools/gen_status.py --check` enforces (#143)
- Docs and the AI-review skill match what CI actually enforces: enforced vs planned
  rules, the hard gate, workflow list, ODCS drift check, domain counts (#142)
- Documentation refresh across the repository's Markdown files (stale counts, table
  lists, links, deferred-vs-shipped claims), a current Model Explorer screenshot, and the
  0.2-beta version bump (#162)

### CI & automation

- **Faster lean per-PR deploy gate**: one Python dependency install, a parallel sync of only the files the workspace job runs (`tools/sync_workspace_bundle.sh`), per-table constraint units, and a 40-minute cap. **Deploy behavior change (daily deploy too):** plain gold views now get their column comments inline on `CREATE OR REPLACE VIEW` (falling back to separate `COMMENT ON COLUMN` statements if the warehouse rejects the column list), so 37 columns with no comment of their own now inherit the upstream view's comment instead of the base table's. Deploy logs count each inlined view as one applied statement, so applied counts drop by roughly the number of inlined comments; nothing is missing (#145)

### Data contracts & synthetic data

- ODCS contracts now include **UC metric views**: fields and measures from the
  `WITH METRICS` YAML, typed by inferring from each `source:`, with `businessName` and
  synonyms (#140)

## [0.1-beta] — 2026-09-03

In a few short months ORDM grew from an empty repository into a genuinely useful,
Databricks-native retail data model: canonical-core domains, 12 **outcome packages**
across 4 retail themes, an interactive browser-based **Model Explorer**, generated **ODCS
data contracts**, and an agentic, self-grounding **CI and governance** stack. Huge thanks
to the contributors below — this is a team effort. 🙌

### Highlights

- **A 13-domain canonical core under one contract.** The initial baseline
  (#2, [@a0x8o](https://github.com/a0x8o))
  established the conformed core, first gold views, data-quality checks, synthetic data,
  and tests. The promotion dimension was promoted into a first-class marketing domain
  (#9), and customer-identity
  (#60, [@chloecheau-k](https://github.com/chloecheau-k)),
  inventory (#15, [@ojasvi-goyal-03](https://github.com/ojasvi-goyal-03)),
  equipment (#76, [@sreekanthmunigati](https://github.com/sreekanthmunigati)),
  and calendar (#46) domains
  followed — all conforming to a single primary-key contract, key-naming standard, and
  governed-tag convention.
- **12 outcome packages across 4 retail themes.** Real, consumable gold layers landed
  for early-risk-detection (#29, [@sreekanthmunigati](https://github.com/sreekanthmunigati)),
  balancing-margin-and-volume (#31, #80, [@ojasvi-goyal-03](https://github.com/ojasvi-goyal-03)),
  commerce-media-networks / retail media (#66, [@chloecheau-k](https://github.com/chloecheau-k)),
  unified-customer-view (#67, [@chloecheau-k](https://github.com/chloecheau-k)),
  and smarter-demand-and-inventory-decisions (#85, [@vibewisely](https://github.com/vibewisely)).
  In-Store Equipment Maintenance was consolidated into predictive-operations as a use
  case rather than a standalone package, settling the catalog at 12
  (#83).
- **An interactive Model Explorer.** A browser-based explorer, generated from the DDL,
  lets you navigate the core and outcome packages, drill into columns / keys / PII, and
  follow use-case-to-core lineage — including a layered value-chain view
  (#57) and an L1
  consumes-silver lineage overlay (#61).
- **Agentic, drift-proof CI.** An advisory Claude Code PR reviewer runs in CI
  (#19), now grounded,
  bidirectional, and self-pacing (#71,
  #72), with a durable review
  log (#32).
  Standards-conformance gates, a PR base-guard, doc/status anti-drift locks, and
  branch-freshness checks keep generated artifacts and docs from ever drifting.
- **Governed data contracts and generators that scale.** An optional ODCS v3.1.0
  contract generator emits data contracts from the DDL
  (#41), and a uniform
  generators-v2 layer (#43)
  with dbldatagen as the default engine scales synthetic data to 1 TB+
  (#81).

### Contributors

With gratitude to everyone who has shaped ORDM so far —
[@a0x8o](https://github.com/a0x8o) (the founding baseline),
[@chloecheau-k](https://github.com/chloecheau-k) (retail media, customer 360 / CDP, the identity core),
[@ojasvi-goyal-03](https://github.com/ojasvi-goyal-03) (balancing margin & volume, inventory),
[@sreekanthmunigati](https://github.com/sreekanthmunigati) (early risk detection, equipment, predictive operations),
[@vibewisely](https://github.com/vibewisely) (smarter demand & inventory decisions), and
[@adityajain03-png](https://github.com/adityajain03-png) — plus everyone who reviewed,
tested, and refined along the way. The auto-generated grid in the
[README](README.md#contributors) stays current with every merge.

### Canonical core & data model

- Initial baseline — domains, outcome gold views, DQ, synthetic data, and tests (#2, [@a0x8o](https://github.com/a0x8o))
- Promote the promotion dimension into a canonical-core **marketing** domain (#9)
- Canonical entities schema + **inventory** domain and use-case specifics (#15, [@ojasvi-goyal-03](https://github.com/ojasvi-goyal-03))
- **Calendar** MUST-tier parity + date-stemmed keys (`date_sk` / `date_id` / `date_key`) (#46)
- **FK-completeness** standard + `product_price` → product surrogate FK (#58)
- Thin **customer-identity** core slice + design harvest (#60, [@chloecheau-k](https://github.com/chloecheau-k))
- **Equipment** domain (#76, [@sreekanthmunigati](https://github.com/sreekanthmunigati)) — remains a canonical-core domain; only its In-Store Equipment Maintenance outcome package was later folded into predictive-operations (#83)
- **Interaction** domain ([ADR 0029](governance/decisions/0029-conformed-interaction-touchpoint-fact.md)): the conformed **omnichannel customer-interaction fact** `interaction.touchpoint` (14th canonical-core domain) — one append-only, streaming-ready fact for every observed customer touch, online (page/product/search/cart/checkout/app/session) and offline (store visit, call-center, kiosk, offline-marketing, phone), anonymous-first on a hashed device key and stitched to `profile` via `identity_link`. The time-series event class of the two-class CDP shape and the single source of truth for the raw touch *occurrence*; `commerce-media-networks.conversion_event` is re-chartered as the paid-attribution *measurement* projection. Ships a seeded generator and one demonstrating consumer (ACU `gold_customer_behavioral_attributes` gains channel-mix + engagement/intent traits from it, filling the gap that view documented).

### Outcome packages

- **connected-store-signals — Smart Shelf:** introduces five new CSS-owned table
  objects (`shelf_position_assignment`, `shelf_state_observation`, `esl_label`,
  `esl_label_assignment`, and `esl_price_observation`), new shelf-state, availability,
  compliance, share-of-shelf, price-accuracy, OOS-episode, and inventory-variance gold
  surfaces, and three metric views. Price observations carry explicit displayed and
  price-of-record currencies, with engine, DQ, and fail-closed gold comparison guards.
  ADRs [0039](governance/decisions/0039-smart-shelf-positional-state-outside-sensor-envelope.md),
  [0040](governance/decisions/0040-css-expected-shelf-state-vs-bmv-planogram.md), and
  [0041](governance/decisions/0041-esl-observation-only-no-price-actuation.md) record the
  dedicated positional fact, CSS/BMV expected-state boundary, and observation-only ESL
  stance; all remain Proposed pending maintainer review
  (#132, [@saurabhshukla-db](https://github.com/saurabhshukla-db)).

- **connected-store-signals — RFID Tracking:** adds the hash-keyed serialized-item registry,
  append-only read events, bounded count sessions, item presence, basis-aware inventory
  reconciliation, count coverage, receiving evidence, OOS/exit seams, RFID fleet health,
  three metric views, deterministic synthetic journeys, and `sensor_device.is_mobile_platform`
  (#130, [@saurabhshukla-db](https://github.com/saurabhshukla-db)).
- **connected-store-signals — IoT Sensor Monitoring:** the sense → evaluate → act → log
  automation loop (`actuator_capability`, `evaluation_rule`, `automation_action`,
  `execution_log`), its response gold view and metric view (#131, [@jam-dbx](https://github.com/jam-dbx)).
- **labor** canonical-core domain with **predictive-operations — Workforce Optimization**,
  plus **promote-with-purpose — Location-Based Offers** and **data-sharing-with-suppliers —
  Data Monetization** use cases (#133, [@a0x8o](https://github.com/a0x8o)).
- **ai-assisted-store-associates — Real-Time Data Access:** the associate lookup contract
  (inventory, price/promotion, order status, operational context, freshness) on the labor
  core (#134, [@a0x8o](https://github.com/a0x8o)).
- **ai-assisted-store-associates — Associates Best Next Actions:** next-best-action engine
  schema, action queue and outcome funnel (#136, #137,
  [@jam-dbx](https://github.com/jam-dbx)).
- **promote-with-purpose — Location-Based Offers:** synthetic data for the location-offer
  tables and a use-case test module (#121), UC metric views and gold-view column
  comments (#122), and PK/audit-standard conformance for the offer tables
  (#123) ([@a0x8o](https://github.com/a0x8o)).
- **actionable-customer-understanding — Product Affinity:** market-basket association rules
  and per-customer product affinity (#138, [@jam-dbx](https://github.com/jam-dbx)).

- **early-risk-detection**: real-time disruption-detection spine (#29, [@sreekanthmunigati](https://github.com/sreekanthmunigati); review fixes #69)
- **balancing-margin-and-volume**: package + assortment optimization and metric views (#31, #80, [@ojasvi-goyal-03](https://github.com/ojasvi-goyal-03))
- **commerce-media-networks** (retail media): gold layer + shared marketing audience (#66, [@chloecheau-k](https://github.com/chloecheau-k))
- **unified-customer-view**: customer 360 + activation-eligibility on the identity core (#67, [@chloecheau-k](https://github.com/chloecheau-k))
- **smarter-demand-and-inventory-decisions**: demand forecasting, inventory optimization, and out-of-stocks across 16 tables + 15 gold views (#85, [@vibewisely](https://github.com/vibewisely))
- **actionable-customer-understanding**: Behavioral Segmentation — a wide, agent-discoverable customer trait surface (`gold_customer_behavioral_attributes`) + append-only `segment_membership` over the shared `marketing.audience` definition catalog (ADR 0022), unblocking CDP marketing activation. Consent / preference / targeting stay three separate planes; the net gate is applied only in UCV's `gold_activatable_audience_current`. Also fixed `gold_customer_ltv` RFM/value-tier bucketing from population `NTILE` to stable fixed thresholds (reproducible across refreshes). Note for downstream consumers: `data-sharing-with-suppliers` `gold_category_growth` reads `ltv.value_tier` for its `value_share_platinum/gold/silver/bronze` splits, so those shares shift from the prior population-relative quartiles to absolute-CLV bands — retune the cutoffs (documented in `gold_customer_ltv.sql`) per deployment.
- **actionable-customer-understanding — Market Analysis PR 1** (#135): adds durable-competitor, fiscal-period `gold_competitive_position` and reaggregation-safe `mv_competitive_position`; publishes additive components for metric rollups, valid price pairs/products, matched units, comparable promo populations, stock-flag populations, observation counts, currency and explicit proxy bases. The price indices remain observation-level means of price relatives rather than ratios of aggregate price totals. Compliance tests enforce no person-level sources and no Market Analysis → pricing lineage. The use case remains `in-progress` until PR 2 completes the observation-native assortment/distribution, market-share/share-of-shelf and detection-lag surfaces ([@saurabhshukla-db](https://github.com/saurabhshukla-db)).
- **actionable-customer-understanding — Market Analysis PR 2** (#135): adds append-only competitor promotion/assortment observations, a Type-1 competitor-item match registry, restatement-aware market benchmarks, deterministic synthetic scenarios, observation-native competitive-position KPIs, and separate ratio-of-sums market-share gold/metric surfaces. Review hardening moves promotion SOV to shared observation coverage, constrains overlap to observed active products, publishes excluded inactive matches/listed channels and dimension-specific detection means, labels match failure separately from distribution gaps, and adds a registry-driven licensed-data no-redistribution wall. CI follow-up removes a period-vs-channel count false positive, narrows the email PII detector to exempt only the `email_app` promotion counter, keeps retired durable competitors valid for historical observations, and makes total-category benchmark cells denominator-only rather than served subjects. The antitrust wall scans price, margin, offer, elasticity, cost and promotion surface names. The use case remains `in-progress` pending six-KPI Databricks validation and @Tagar/BMV-owner review; deferred KPI arms are recorded in the package README/use-case/ADR ([@saurabhshukla-db](https://github.com/saurabhshukla-db)).
- Fold In-Store Equipment Maintenance into **predictive-operations** — settles the catalog at 12 packages (#83)
- **CDP activation compliance follow-ups** (#95, [@Tagar](https://github.com/Tagar); [ADR 0028](governance/decisions/0028-cross-plane-do-not-target-and-multi-purpose-gate.md)): closed the GDPR Art.21 cross-plane do-not-target gap with a shared `gold_person_do_not_target_current` view consulted by the owned gate (CI-enforced on the gate + UCV activation surface) and, on any paid/non-owned reverse-ETL plane, by an adopter-obligation activation contract on `segment_membership`; generalized the activation gate to derive purpose from the full consent-type set (marketing / personalization / analytics / retail_media / data_sale) instead of marketing-only; added a distinct `data_sale` consent type + gate purpose for the CCPA/CPRA do-not-sell opt-out (kept separate from `third_party_sharing`/do-not-share, per the two-signal "Do Not Sell or Share" requirement); added the missing `consent` SCD2 integrity DQ checks; added `activation_job` delete-propagation + run-lifecycle + gate-provenance telemetry columns; reconciled the customer-identity design notes with ADR 0027; disambiguated the three meanings of "suppression"; and added [`docs/cdp-composition.md`](docs/cdp-composition.md). Vendor-neutralized the ADR prose.

### Model Explorer

- ER-diagram visualizer — generated dual-theme diagrams from the DDL (#53)
- Comment tooltips + column/key/PII drill-in (#55)
- **Layered value-chain redesign** + filters/search/back/theme fixes and integration tests (#57)
- **L1 consumes-silver lineage overlay** + gold-view type/column hardening (#61)

### Standards, governance & ADRs

Governance decisions are recorded as ADRs (`governance/decisions/`, currently 0001–0033; 0008 intentionally unused).

- Single data-model standard, expanded CONTRIBUTING, and the initial decision ADRs (#3)
- `dbx_data_type` tag on every table, enforced in CI (#10)
- **Definition of Done** + status-ladder definitions (ADR 0007) (#18)
- Clustering-key selection guidance (§B) + a review-rubric check (#35)
- UC Domains as an optional, derived governance overlay (ADR 0009) (#40)
- Governed-tag & semantic conventions aligned with Databricks native features (ADR 0010) (#47)
- Key-stem naming by grain/role + documented intentional deviations (ADR 0011) (#49)
- Two-axis status — package build status **and** use-case delivery — plus the 🔵 Nearing-complete tier (#77, #82)
- **Schema versioning & deprecation policy** — breaking-change classification, semver bump mechanics, the 90-day deprecation window, and the Lakebase dual-binding rule; wired into CONTRIBUTING §6a, the publication process, and ADR 0005 (#106)

### CI & automation

- Tooling to push the generated ODCS contracts to an external data-contract catalog (CLI +
  notebook) (#128, [@mjsturwold](https://github.com/mjsturwold))
- ORDM Claude Code **modeling and review skills** (#4)
- Standards-conformance gates + docs/CI anti-drift lock (#5)
- PR **base-guard** + doc-sync enforcement (#17)
- **Agentic advisory AI PR review** + DoD status, via Claude Code on the Databricks gateway (#19)
- Durable AI-review capture to a log branch (Delta-queryable) (#32)
- Advisory PR-branch-freshness check (sticky "behind main" comment) (#48)
- **Grounded, bidirectional model-coverage reviewer** (#71, #72)
- Generated, drift-proof surfaces: README status tables from `STATUS.md` (`gen_status.py`, #62) and the auto-generated Contributors grid (`gen_contributors.py`, #64)

### Data contracts & synthetic data

- Optional **ODCS v3.1.0** data-contract generator (#41)
- **generators-v2**: uniform `run(ctx)` + `generate_all` on one serverless task + shared layer (#43)
- Make **dbldatagen** the default generator engine — scales to 1 TB+ (#81)
- Payment synthetic data (customer_ltv generator): full enum-domain coverage —
  authorized/settled/declined/voided lifecycle on sales, post-sale adjustments
  (NULL order_id, the documented warn-path), and card-only chargebacks; rates
  seed-stable and configurable with unchanged defaults. New static test asserts
  emitted literals both stay within and fully cover the CHECK domains.

<!-- Releases: run `make release NEW_VERSION=X` (tools/release.py). It cuts [Unreleased]
     to "## [X] — YYYY-MM-DD", opens a fresh [Unreleased] above it, and bumps VERSION and
     every version stamp. The full process is in docs/releasing.md. -->
