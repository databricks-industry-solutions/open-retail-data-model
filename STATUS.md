# ORDM Status

Single place to see what's in progress and who's on it. Update your row when you pick something up.

Legend: ✅ Published · 🟢 Review complete · 🔵 Nearing complete · 🟡 In progress · ⚪ Planned — defined in [docs/definition-of-done.md](docs/definition-of-done.md)

## Canonical core (domains)

| Domain | Status | Working on it | Branch |
|---|---|---|---|
| customer | ✅ Published | — | — |
| product | ✅ Published | — | — |
| order | ✅ Published | — | — |
| transaction | ✅ Published | — | — |
| marketing | ✅ Published | — | — |
| store | ✅ Published | — | — |
| calendar | ✅ Published | — | — |
| payment | ✅ Published | — | — |
| supplier | ✅ Published | — | — |
| procurement | ✅ Published | — | — |
| inventory | ✅ Published | — | — |
| logistics | ✅ Published | @sreekanthmunigati | — |
| labor | ✅ Published | — | — |  <!-- MUST tier complete; signed off in #165 (2026-10-07) -->
| equipment | ✅ Published | @sreekanthmunigati | — |  <!-- MUST tier complete; signed off in #165 (2026-10-07) -->
| interaction | ✅ Published | @Tagar | — |  <!-- MUST tier complete; signed off in #165 (2026-10-07). Self-review (owner = reviewer, disclosed in #165 and REVIEWERS.md); see GOVERNANCE.md for when ✅ Published needs a second reviewer. -->

> Every domain and package whose Owner is also its Reviewer in [REVIEWERS.md](REVIEWERS.md) reached 🟢 on a self-review by the maintainer (@Tagar), disclosed in the Self-reviews note there (and, for `interaction`, in #165). Under the [self-review rule](GOVERNANCE.md) they were ✅ Published in the initial public release (0.5) on that sign-off; each needs a second, independent reviewer before the next release.

> `transaction`, `order` and `inventory` are the transactional spine. They were ✅ Published in 0.5 without the Lakebase binding the [Definition of Done](docs/definition-of-done.md) expects of spine entities, because the generator that derives it from the logical model ([ADR 0005](governance/decisions/0005-lakebase-physical-binding.md)) does not exist yet. The binding is deferred to a later release.

## Outcome packages

| Package | Status | Working on it | Branch |
|---|---|---|---|
| promote-with-purpose | ✅ Published | @a0x8o | — |  <!-- MUST tier complete; signed off in #165 (2026-10-07) -->
| actionable-customer-understanding | ✅ Published | @saurabhshukla-db | — |  <!-- MUST tier complete; signed off in #165 (2026-10-07) -->
| early-risk-detection | ✅ Published | — | — |
| data-sharing-with-suppliers | ✅ Published | @bryanmoo92 | — |  <!-- MUST and SHOULD tiers complete for all 4 use cases; signed off in #177 (2026-10-13), a self-review disclosed in REVIEWERS.md. -->
| unified-customer-view | ✅ Published | — | — |  <!-- MUST tier complete; signed off in #165 (2026-10-07). SHOULD (UC Metric Views) now ships as a Databricks-native materialization of the glossary metric definitions: mv_customer_360 (Customer 360 and Identity Resolution) and mv_cdp_activation_eligibility, mv_cdp_activation_jobs and mv_cdp_campaign_touch (CDP); Customer Lifetime Value maps to ACU's gold_customer_ltv and its mv_customer_lifetime_value. CDP marked done by the maintainer, 2026-10-12, and that call accepted in place of the card owner's confirmation, 2026-10-13; the other three were already done. SHOULD gates ✅ Published, not 🟢. -->
| agentic-commerce | ✅ Published | @shubhamp051991 | — |  <!-- both grains merged: conversational shopping / intent product discovery + agent-to-agent transactions. MUST tier complete for all 3 use cases; signed off in #165 (2026-10-07). SHOULD (UC Metric Views) is now COMPLETE: the 3 A2A metric views, plus mv_intent_discovery_result_performance and mv_intent_discovery_intents (Intent Product Discovery) and mv_conversational_shopping_session (Conversational Shopping Assistant), added 2026-10-12. SHOULD gates ✅ Published, not 🟢. -->
| commerce-media-networks | ✅ Published | — | — |
| balancing-margin-and-volume | ✅ Published | @ojasvi-goyal-03 | — |
| smarter-demand-and-inventory-decisions | ✅ Published | @vibewisely | — |
| connected-store-signals | ✅ Published | @saurabhshukla-db | — |  <!-- artifact tier is complete: the full outcome-package MUST set plus the metric-view SHOULD ship for RFID Tracking and Smart Shelf; signed off in #165 (2026-10-07). Per ADR 0013 the use-case axis is separate and does NOT gate this ladder: 4/4 done (Foot Traffic Analysis, IoT Sensor Monitoring, RFID Tracking, Smart Shelf). -->
| predictive-operations | ✅ Published | @sreekanthmunigati, @a0x8o | — |  <!-- MUST tier complete; signed off in #165 (2026-10-07) -->
| ai-assisted-store-associates | ✅ Published | @a0x8o | — |  <!-- MUST tier complete; signed off in #165 (2026-10-07). Associates Best Next Actions and Digital Assistant Selling Tools marked done by the maintainer in #171, 2026-10-12; both cards show Done on the ownership tracker (checked 2026-10-13). Their two gold views have data-quality checks in checks.sql. -->

> `actionable-customer-understanding` reached 🟢 Review complete (signed off in #165, which covered the Market Analysis surfaces) and was ✅ Published in 0.5. All three use cases are `done`: Market Analysis was confirmed done by its owner on 2026-10-09 (record). The four source interfaces and both serving surfaces are implemented, including non-total-subject market-share serving with denominator-only category totals; the ACU → BMV competitor read is recorded in the Accepted [ADR 0042](governance/decisions/0042-market-analysis-reads-bmv-competitor-foundation.md). Behavioral Segmentation and Product Affinity are `done` (Product Affinity ships two gold views + `mv_product_affinity`, with the demo's opt-in co-purchase seeding shipped off / core neutral).

> `connected-store-signals` ✅ gate (closed): ADR 0041 amends ADR 0030 (observation-only ESL; the pricing-declaration fields are deferred). The amendment is in force in staging (record). ADR 0030's CSS-owner and Privacy scopes have acknowledged it, and the formal DPO review that ADR 0030's Privacy approval requires on a scope change is done; the maintainer recorded both as closed on 2026-10-13, so CSS is ✅ Published in 0.5 with no open gate.

> `data-sharing-with-suppliers` reached 🟢 Review complete (signed off in #177, 2026-10-13; #165 had left it out until the Media Measurement fix in #163 merged) and was ✅ Published in 0.5. All **four** of its use cases (Category Growth, Media Measurement, Joint Demand Planning, and Data Monetization, which closes the monetization/billing capability deferred in [ADR 0019](governance/decisions/0019-media-measurement-in-data-sharing.md)) are done with the full MUST tier, and each has a UC Metric View (the SHOULD tier). One documented assumption remains: `gold_data_product_revenue` assumes one reporting currency across this package and commerce-media-networks, which a check can only assert once the CMN gold views carry a currency column (#114).
