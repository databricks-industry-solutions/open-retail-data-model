# Payment Domain — Business Glossary

> Status: ✅ Published (0.5)

| Term | Definition |
|---|---|
| **Payment** (`payment`) | Transaction-grain payment-event fact — the tender/settlement side of a customer order. Append-only event log (no SCD2). |
| **Payment type** | The kind/direction of the event: `sale` (inflow), `refund`, `adjustment`, `chargeback` (outflows). One fact covers all four. |
| **Payment method** | Tender used: `card`, `cash`, `wallet`, `bank_transfer`, `gift_card`, `voucher`. |
| **Payment status** | Settlement state: `authorized`, `captured`, `settled`, `declined`, `refunded`, `voided`. |
| **Amount** | Event magnitude (`>= 0`) in the reporting/base currency; direction is carried by `payment_type`, not the sign. |
| **Event-time vs processing-time** | `event_timestamp` is when the payment occurred (UTC); `load_timestamp` is when it landed in the canonical core. Keep the two distinct for late-arriving data. |

Surrogate `payment_sk` is the join/FK target; `payment_id` is the durable business key. Keyed to the order (`order_id`) and the customer (`profile`). No aggregates live here (principle #4).

---

## Realized Margin & Leakage Terms

For comprehensive glossary of realized-margin and revenue-leakage KPI definitions (booked revenue, realized revenue, revenue leakage, unsettled sales, realized margin, sale-cohort vs event-date attribution), see the [Balancing Margin & Volume glossary](../../outcome-packages/balancing-margin-and-volume/glossary.md). Those terms are outcome-package concepts; payment-domain terms live above.
