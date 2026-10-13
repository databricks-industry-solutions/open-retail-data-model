# ADR 0040 — CSS owns position-level expected shelf state; BMV planogram remains allocation intent

**Status:** Accepted (2026-10-09; proposed 2026-08-21) by the maintainer, @Tagar, with the Connected Store Signals sign-off in #165 (acceptance record).

## Context

Smart Shelf planogram compliance needs expected state at shelf-position × product grain: the
product assigned to a slot, expected and minimum facings, and the exact validity interval.
Balancing Margin and Volume's `planogram` is store × product allocation intent expressed through
measures such as `allocated_facings` and `allocated_sqft`. Expanding that object to position
grain would change its published meaning and place store-execution state in the wrong outcome
package.

## Decision

Connected Store Signals owns `shelf_position_assignment` as the position-level expected-state
contract for the Smart Shelf use case. It is an instant-valid SCD2 association at shelf-position
zone × product grain and records expected facings, minimum facings, and an assignment source of
`planogram`, `manual`, or `vendor`.

Balancing Margin and Volume continues to own `planogram` as store × product allocation intent.
It remains unchanged. CSS compliance serving may compare the sum of position-level expected
facings with BMV allocated facings through a read-only gold-to-gold reconciliation under ADR
0024. Neither package writes the other's state, and no foreign key crosses the boundary; durable
business keys and an optional logical `planogram_id` carry traceability.

Smart Shelf remains inside Connected Store Signals. Promotion of a shared space-planning concept
to canonical core is deferred until multiple independent outcome consumers establish that need.

## Consequences

- Adopters with slot-level planogram systems can trace expected execution to allocation intent;
  adopters without one can operate with manual or vendor assignments.
- Two objects use planogram-related language at different grains, so their comments and glossary
  must state the allocation-intent versus execution-state distinction.
- Reconciliation reports divergence but never corrects either source.
- Latest-capture-wins serving, known/unknown/unobserved splits, currency guards, and the shelf
  evaluation clock are unaffected.
- The package remains aggregate-only with no person-level data, and no existing table schema is
  changed by this decision.
