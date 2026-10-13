# ADR 0006 — Promote the `promotion` dimension into a canonical-core `marketing` domain (Option A)

**Status:** Accepted (2026-06-28)

## Context
The canonical-core `sales` fact (transaction domain) was attributed to a promotion via a foreign key (`fk_sales_promotion`) and a referential-integrity DQ check that resolved the `promotion` dimension in `${promo_schema}` — the **Promote with Purpose outcome package** (gold). A silver fact depending on a gold table **inverts** ADR 0001's layering (the canonical core could not deploy or pass DQ standalone) and was the single hard `LAYER-INTEGRITY` blocker, waved through only by a temporary `known_exceptions` entry.

Two options were on the table:
- **Option A** — promote the `promotion` master into the canonical core as a shared conformed dimension.
- **Option B** — keep `promotion` in the outcome package, drop the FK, and make the link a non-enforced logical reference.

## Decision (Option A)
`promotion` is a **conformed dimension of the POS `sales` fact** (Kimball's Date · Product · Store · Promotion), referenced by a core fact and reusable across outcomes — so it belongs in the canonical core. It moves to a new **`canonical-core/marketing`** domain (schema `marketing`):

- The SCD2 `promotion` master (incl. the reserved `NO_PROMO` member) lives at `canonical-core/marketing/tables/promotion.sql`.
- `sales`→`promotion` is now **core→core** (`${marketing_schema}.promotion`); the `LAYER-INTEGRITY` `known_exceptions` entry is removed (matrix: "Tracked exceptions: none").
- The trade-promotion-specific assets stay in **Promote with Purpose**: the `promotion_scope` bridge and the `gold_*` ROI/baseline views, which consume the core dimension.
- `marketing_schema` is wired through `databricks.yml`, `tools/ordm_config.py`, and the deploy bootstrap.

## Consequences
- Removes the inverted silver→gold dependency; the canonical core deploys and validates standalone. `pytest tests/standards` passes layer-integrity without the exception.
- Establishes `marketing` as the 11th canonical-core domain.
- **Known tension (follow-up):** the moved table still carries trade-promotion-OUTCOME planning/funding columns (`planned_trade_spend`, `planned_lift_pct`, `planned_discount_pct`, `funding_type`, `funded_by`, `supplier_share_pct`). A stricter conformed dimension would keep identity/mechanics/dates in core and push those plan/funding attributes into a Promote-with-Purpose extension table keyed to `promo_sk`. This passes every enforced mandate today (the columns are plan inputs, not derived metrics), so it is logged here as a reviewer/altitude note, not a blocker. Revisit if a second, non-promotion outcome needs `promotion`.
