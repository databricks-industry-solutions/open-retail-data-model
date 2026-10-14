# Marketing Domain — Business Glossary

> Status: 🟢 Review complete (0.5)

Follows the ORDM [data model standards](https://github.com/databricks-industry-solutions/open-retail-data-model/blob/main/docs/data-model-standards.md).

## Tables

| Object | Type | Description |
|---|---|---|
| `promotion` | Master (SCD2) | Conformed trade-promotion dimension — mechanics, funding, planned lift/spend, and the dates/fiscal weeks it ran. A dimension of the POS `sales` fact. Includes the reserved `NO_PROMO` member so non-promoted sales attribute to a real surrogate. Promotion **performance** (ROI, lift, baseline) is computed in outcome packages. |
| `audience` | Master (SCD2) | Conformed audience / segment-definition dimension — what a segment is, its axis, how authored/computed, and refresh latency. A definition catalog only: never member lists, PII, or live membership counts. Shared by retail-media ad delivery and customer-intelligence behavioral segmentation. |

## Key terms

| Term | Definition |
|---|---|
| **Promotion** (`promotion`) | The conformed trade-promotion dimension (SCD2) — mechanics, funding, planned lift/spend, and the dates/fiscal weeks it ran. A dimension of the POS `sales` fact (one version per promotion). Includes the reserved `NO_PROMO` member so non-promoted sales attribute to a real surrogate. Promotion **performance** (ROI, lift, baseline) is computed in the Promote with Purpose outcome package, which consumes this dimension. |
| **Audience** (`audience`) | The conformed audience / segment-**definition** dimension (SCD2) — what a segment is, the axis it is built on (`segmentation_basis`), how it is authored (`definition_origin`) and computed (`definition_method`, `criteria_expression`), its refresh latency (`evaluation_mode`), addressability, and a point-in-time `size_estimate`. A **definition catalog only**: never member lists, never PII, never live membership counts. Shared by retail-media ad delivery (commerce-media-networks) and customer-intelligence behavioral segmentation (actionable-customer-understanding); per-customer membership lives in the consuming gold packages. |
> The `device` dimension was relocated to the gold `commerce-media-networks` package as the
> ad-surface `delivery_channel` dim (single-outcome retail media; ADR 0021). `audience` was
> gold there too until behavioral segmentation became a second consumer, when it was promoted
> back here as a shared conformed dimension (ADR 0022). `marketing` now holds the conformed
> `promotion` and `audience` dimensions.

_TODO: expand as additional shared marketing tables (offer, coupon) ship._
