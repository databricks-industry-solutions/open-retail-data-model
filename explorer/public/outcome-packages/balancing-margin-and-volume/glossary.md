# Balancing Margin and Volume - Glossary

> Status: 🟢 Review complete (0.5)

| Term | Definition |
|---|---|
| **Price Gap** | The difference in price between our product and a competitor's identical or equivalent product. |
| **Price Index** | A ratio comparing our price to a competitor's price (e.g., 1.05 means we are 5% more expensive). |
| **Substitute** | A product that can be purchased instead of another (e.g., different brand of milk). Used in cannibalization modeling. |
| **Complement** | A product that is often bought together with another (e.g., hot dogs and hot dog buns). Used in basket affinity analysis. |
| **Affinity Coefficient** | A score between 0 and 1 indicating how strongly two products are related (substitutes or complements). |
| **Weeks of Cover** | Inventory health indicator categorizing stock life (e.g., '<1 Week', 'Overstock'). |
| **Markdown Depth Pct** | The percentage depth of the markdown relative to base price. |
| **Stockout Adjusted Demand** | De-seasonalized and de-promoted normal demand adjusted for out-of-stock periods. |
| **Price Barrier Proximity** | Measures proximity to psychological boundaries like .99. |
| **Margin Health Bucket** | Categorical indicator of gross margin performance (e.g., 'High', 'Healthy', 'Bleeding'). |
| **Competitive Pressure Bucket** | Categorical indicator of competitor price aggression (e.g., 'Severe', 'Moderate', 'Low'). |
| **Discount Depth Bucket** | Categorical depth of the current markdown (e.g., 'Clearance >50%', 'Shallow <10%'). |
| **Cross Elasticity Proxy** | The substitution effect drawn from cannibalized items. |
| **Point Own Price Elasticity** | The percentage change in volume for a 1% change in price (PED). |
| **Planogram** | A visual representation of a stores products or services, used to maximize sales and space. |
| **Allocated Facings** | The number of physical items of a specific product visible at the front of a retail shelf. |
| **Allocated Sqft** | The total square footage assigned to a specific product on a retail shelf. |
| **Space Elasticity** | The sensitivity of sales volume to changes in the amount of shelf space allocated to a product: the percent change in units for a 1% change in facings. ORDM estimates it per space-planning category from cross-store differences in facings for the same product, shrunk toward a 0.17 literature average; it is observational, not a causal effect. |
| **Substitute Demand Transfer Pct** | The share of an item's demand assumed to move to its substitutes when it is unavailable or dropped. ORDM derives it from the substitute affinity coefficients (1 - product of (1 - affinity)); it is an assumption, not measured substitution. |
| **Rolling Sales Velocity 14d** | The 14-day rolling average of daily units sold. |
| **Baseline Velocity** | The expected volume sold in the absence of promotions. |
| **Margin Contribution Pct** | An item's 14-day realized gross-margin rate: rolling gross-margin dollars divided by rolling net revenue on days that carry a gross-margin rate, over the same 14-day window (ratio-of-sums). Days lacking a margin rate are excluded from the denominator so the rate is not biased downward. |
| **Assortment Recommendation** | Rule-based recommendation for an item's status in the assortment (KEEP, DROP, EXPAND), derived deterministically from sales velocity, margin health, and days-on-hand. |
| **Projected Volume Lift** | The change in an item's own units per selling day, at its baseline rate, if the recommended assortment action is applied: one more facing for EXPAND, the item's full baseline lost for DROP, none for KEEP. A scenario, not a forecast. |
| **Projected Margin Lift** | The net change in gross margin per selling day from a recommended assortment action: the item's own margin change minus cannibalization drag on its substitutes. |
| **Cannibalization Drag** | The gross margin per selling day an assortment action takes from substitute items through demand transfer. Positive when an EXPAND pulls demand from substitutes, negative when a DROP's demand is recaptured by them. |
| **Settled Sale Amount** | Allocated magnitude of sale payments in a settled or captured state, spread to product × store × day. The denominator base for payment-side leakage rates. |
| **Refund Amount** | Allocated magnitude of merchant-initiated refunds (contra-revenue), from the payment domain. Distinct from a chargeback. |
| **Chargeback Amount** | Allocated magnitude of bank-initiated payment reversals (disputes). Kept distinct from refunds: involuntary, typically irrecoverable, and never touches the POS sales fact. |
| **Adjustment Amount** | Allocated magnitude of post-sale payment adjustments (goodwill / corrections); treated as contra-revenue. |
| **Booked Revenue** | Total expected revenue at the time of sale (POS and order channels combined): sum of net POS sales and order line amounts, before any payment reversals. Formula: pos_net_sales + order_booked_sales. Operational estimate; orders may later have unsettled or reversed portions. |
| **Realized Revenue** | Revenue retained after order-channel settlement and payment reversals. Formula: pos_net_sales + order_settled_sales - refunds - chargebacks - adjustments. POS net sales count as realized on the sale day because ORDM carries no payment lifecycle for POS (POS returns are included only if loaded as negative units). Operational estimate, not an accounting close (no refund reserve or fees). |
| **Revenue Leakage** | Booked revenue that was not realized: order sales never captured or settled, plus refunds, chargebacks and adjustments. Formula: order_unsettled + refund + chargeback + adjustment (equals booked_revenue - realized_revenue). Order channel only. Operational measure; excludes forward-looking refund reserves, processing fees and shrink. |
| **Unsettled Sales** | Order-channel revenue booked but never captured or settled in the payment system. Formula: order_booked_sales - order_settled_sales. Indicates orders authorized but not completed; recent cohorts may still settle. Assumes payment sale amounts and order-line net amounts share a tax- and shipping-exclusive basis. |
| **Realized Margin** | Gross margin on realized revenue. Formula: realized_revenue - cogs, with cogs = units x product.unit_cost on both channels. Refunded merchandise is not assumed restocked, so its cost is not recovered (conservative). Compare with booked margin (booked_revenue - cogs), which includes both channels before leakage. |
| **Realized Margin Pct** | Realized margin as a share of realized revenue (ratio-of-sums). Formula: sum(realized_margin) / sum(realized_revenue), NULL when realized revenue sums to zero. Recent cohorts can still move as late reversals arrive. |
| **Leakage Rate** | Revenue leakage as a share of total booked revenue across both channels. Formula: sum(leakage) / sum(booked_revenue). Diluted by POS revenue, which carries no reversals; Order Channel Leakage Rate divides by order-channel booked sales instead. |
| **Order Channel Leakage Rate** | Revenue leakage as a share of order-channel booked sales. Formula: sum(leakage) / sum(order_booked_sales). The rate to compare leakage intensity across stores or categories, since leakage arises only on the order channel. Sale-cohort basis. |
| **Sale-Cohort Attribution** | Revenue, costs and payment reversals attributed to the original sale day (order_date for orders, the sale day for POS), regardless of when the reversal was processed. Answers how much of a day's sales was eventually retained; used by gold_realized_margin. |
| **Event-Date Attribution** | Revenue and reversals attributed to the payment event date (settlement date for refunds, chargebacks, adjustments). Cash-basis reporting; payment-side leakage rates use this attribution. |
| **Order Channel** | Customer-originated transactions managed through the orders domain (customer_order_line, order payments). Distinct sales cohort and payment processing path from POS. |
| **POS Channel** | Point-of-sale transactions recorded in transaction.sales. ORDM carries no payment lifecycle for POS, so POS net sales are treated as realized on the sale day. |
