# ADR 0002: Money is DECIMAL, DOUBLE is for derived compute and non-money values

**Status:** Accepted (2026-06-15)

## Context
DECIMAL arithmetic is slower than DOUBLE in baseline Spark, which raised the question of whether monetary columns could be FLOAT or DOUBLE. The concern is real for compute-heavy work, but FLOAT and DOUBLE cannot represent most decimal fractions exactly, so sums drift by fractions of a unit and equality and reconciliation become unreliable across the volumes a shared retail spec aggregates.

A relevant detail tempers the performance concern. At precision 18 or less, Spark stores DECIMAL as a 64-bit long rather than an arbitrary-precision type, so monetary columns at DECIMAL(18,x) are already on the fast path. The slow path is reached mainly at higher precision or when intermediate arithmetic widens precision past 18, which is a compute-step concern in the gold layer, not a storage-type concern.

## Decision
The float-versus-decimal choice is split by purpose.

- Stored money (amounts, prices, costs, fx_rate) is DECIMAL with grain-aware scale: unit-grain DECIMAL(18,4), extended and aggregate DECIMAL(18,2), fx_rate DECIMAL(18,8). Not FLOAT or DOUBLE.
- Derived ratios and intermediate computation in the gold and metric layers use DOUBLE, cast inside the view.
- Non-monetary continuous values (latitude and longitude, rates, fractions, scores, percentages where exact reconciliation is not the point) may be DOUBLE or FLOAT. DECIMAL stays acceptable for them too.

CI flags STRING numerics and FLOAT or DOUBLE on monetary column names (amount, price, cost, revenue, fee, balance, and the like) and does not flag DOUBLE on non-monetary columns.

## Consequences
- Financial aggregations stay exact and reconcilable across partners, which is the value of a shared core.
- Compute-heavy non-money math is free to use DOUBLE, and existing DECIMAL choices for coordinates or percentages need not change.
- The standard, docs/data-model-standards.md section 6, is the authoritative wording.
