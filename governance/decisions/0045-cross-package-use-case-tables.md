# ADR 0045 — A use case may map to another package's gold view

**Status:** Accepted (2026-10-12) by the maintainer, @Tagar. Amends [ADR 0013](0013-use-cases-planning-artifact.md).

## Context

ADR 0013 gives each use case an optional `tables:` list: the gold views that serve it. The generator
validated every name against the package's OWN gold views, so a use case could only point at views in its
own package.

The outcome map ([docs/outcome-map.md](../../docs/outcome-map.md)) assigns Customer Lifetime Value to the
Unified Customer View package, but its view, `gold_customer_ltv`, has always lived in Actionable Customer
Understanding: it is built on the same order and margin history as Behavioral Segmentation and Product
Affinity, and other ACU views read it. With same-package-only mapping, the Model Explorer showed UCV's
Customer Lifetime Value with no views, and showed `gold_customer_ltv` in ACU's "Not mapped to a use case"
band. Moving the view would break its ACU consumers and the Data Sharing with Suppliers Category Growth view
that reads it; a thin UCV copy would duplicate it.

## Decision

1. A `tables:` entry may name another outcome package's gold view as `<package>.<gold_view>`, for example
   `actionable-customer-understanding.gold_customer_ltv`. Package and view names contain no dots, so the
   form is unambiguous. A bare name still means a gold view of the package itself.
2. The generator validates a qualified entry like a bare one and fails loud on an unknown package or an
   unknown gold view. A qualified reference to the package's own views is rejected (use the bare name).
3. model.json carries the entry as `foreign_tables: [{unit, table}]` on the use case, resolves the use
   case's consumed core domains through the OWNING package's lineage, and adds the reverse entry to the
   owning package as `external_use_cases`.
4. The Explorer bands the view in its home package under "<use case> (<package>)" and lists it under "Also
   serves"; the declaring package's panel links the use case to the view in its home package.
5. Ownership does not move: the view, its DDL, contract, checks and metric view stay with the package that
   owns them. The mapping is planning metadata only and adds no deploy dependency.

## Consequences

- No gold view needs to sit in "Not mapped to a use case" just because the use case that consumes it lives
  in another package.
- `mv_customer_lifetime_value` ships in Actionable Customer Understanding, next to `gold_customer_ltv`, and
  carries the KPIs of UCV's Customer Lifetime Value use case.
- Use cases should keep mapping their own package's views first; a cross-package entry is for a view another
  package owns for good reason, as here.
