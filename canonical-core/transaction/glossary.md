# Transaction Domain — Business Glossary

> Status: 🟢 Review complete (0.5)

| Term | Definition |
|---|---|
| **Sales** (`sales`) | Conformed POS sales fact at product × store × day grain. Shared by outcome packages. |
| **Promotion attribution** (`promo_sk`) | Each sale references a `promotion` surrogate. Non-promoted sales carry the reserved `NO_PROMO` member, so promoted and non-promoted sales are both first-class for ROI analysis. |
| **Gross / net revenue** | `gross_revenue` is before promotional discount; `net_revenue = gross_revenue − discount_amount`. |

Surrogate `sales_sk`; `sales_id` is the business key. Join `date_key` to `fiscal_calendar` for all retail-week logic.
