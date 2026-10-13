# ORDM Reviewers

Sign-off numbers (#NNN) refer to review records kept in the working repository ORDM is published from.

Named reviewers per area. A domain needs a reviewer before it can enter the publication queue (see [GOVERNANCE.md](GOVERNANCE.md)).

Columns: **Owner** is who maintains the area (— if none). Where no other owner is named, the maintainer (@Tagar) is the interim owner; ownership may be reassigned after publication. **Reviewer** is the assigned reviewer. **Sign-off** links the review-signoff issue where that reviewer records the verdict (— if none yet); a self-reviewed row (Owner = Reviewer) lists its second, independent sign-off in the same cell as `#A, #B` before it can be ✅, except in the initial public release, where the disclosed self-review is enough (see [GOVERNANCE.md](GOVERNANCE.md)). Being listed as Reviewer is not a sign-off: a 🟢 or ✅ row in [STATUS.md](STATUS.md) needs both an assigned Reviewer and a linked Sign-off, and `tools/gen_status.py --check` fails otherwise. The check validates the form of the reference (an issue or PR in this repo), not the verdict recorded in it (see [docs/definition-of-done.md](docs/definition-of-done.md)).

## Canonical core

| Entity | Owner | Reviewer | Sign-off |
|---|---|---|---|
| Customer | @Tagar | @Tagar | #147 |
| Product | @Tagar | @Tagar | #148 |
| Order | @Tagar | @Tagar | #149 |
| Transaction | @Tagar | @Tagar | #150 |
| Marketing | @Tagar | @Tagar | #151 |
| Store | @Tagar | @Tagar | #152 |
| Calendar | @Tagar | @Tagar | #153 |
| Payment | @Tagar | @Tagar | #154 |
| Supplier | @Tagar | @Tagar | #155 |
| Procurement | @Tagar | @Tagar | #156 |
| Inventory | @Tagar | @Tagar | #157 |
| Logistics | @sreekanthmunigati | @Tagar | #158 |
| Equipment | @sreekanthmunigati | @Tagar | #165 |
| Interaction | @Tagar | @Tagar | #165 |
| Labor | @Tagar | @Tagar | #165 |

## Outcome packages

| Outcome package | Owner | Reviewer | Sign-off |
|---|---|---|---|
| Unified Customer View | @Tagar | @Tagar | #165 |
| Actionable Customer Understanding | @Tagar | @Tagar | #165 |
| Agentic Commerce | @shubhamp051991 | @Tagar | #165 |
| Commerce Media Networks | @Tagar | @Tagar | #159 |
| Balancing Margin and Volume | @Tagar | @Tagar | #160 |
| Promote with Purpose | @Tagar | @Tagar | #165 |
| Early Risk Detection | @sreekanthmunigati | @Tagar | #146 |
| Smarter Demand and Inventory Decisions | @Tagar | @Tagar | #161 |
| Data Sharing with Suppliers | @Tagar | @Tagar | #177 |
| Connected Store Signals | @saurabhshukla-db | @Tagar | #165 |
| Predictive Operations | @sreekanthmunigati | @Tagar | #165 |
| AI-Assisted Store Associates | @Tagar | @Tagar | #165 |

## Self-reviews

Disclosure (2026-10-11): every row above whose Owner is also its Reviewer is a self-review, signed off by the maintainer (@Tagar) as both owner and reviewer. That covers: Customer, Product, Order, Transaction, Marketing, Store, Calendar, Payment, Supplier, Procurement, Inventory, Interaction, Labor, Unified Customer View, Actionable Customer Understanding, Commerce Media Networks, Balancing Margin and Volume, Promote with Purpose, Smarter Demand and Inventory Decisions, AI-Assisted Store Associates, and Data Sharing with Suppliers (added 2026-10-13, #177). This note is the self-review disclosure the [GOVERNANCE.md](GOVERNANCE.md) interim rule requires, alongside each row's linked sign-off issue. A self-reviewed row can be 🟢 Review complete, and ✅ Published in the initial public release only; after that it needs a second, independent sign-off.
