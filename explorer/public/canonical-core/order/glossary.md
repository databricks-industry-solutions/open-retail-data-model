# Order Domain — Business Glossary

> Status: ✅ Published (0.5)

| Term | Definition |
|---|---|
| **Customer order line** (`customer_order_line`) | Customer-attributed purchase fact at customer × order × product (line) grain. Unlike the anonymous POS `sales` fact, it links a purchase to a customer (`profile`) so per-customer value (CLV/RFM) can be computed. Amounts are in the reporting/base currency; margin derives from `product.unit_cost`. |

_TODO: expand as additional order tables (e.g. an order header) ship._
