# ADR 0013 — `use-cases.yaml`: a per-package planning artifact

**Status:** Accepted (2026-07-10). Amended by [ADR 0045](0045-cross-package-use-case-tables.md) (a use case may map to another package's gold view).

## Context

Each outcome package delivers one or more business **use cases** (e.g. "Customer 360",
"Dynamic Price Optimization"). That planning tier previously lived only in an external
planning sheet, invisible to anyone reading the repo or the model explorer. The explorer
surfaces the theme → package structure, but a package with no tables yet (a Planned
package) rendered as an empty box, giving no sense of what it is *for*.

We want the use cases discoverable in the repo and the explorer, without recreating the
drift problems ADR 0009 warns about (a central hand-maintained manifest that duplicates
and diverges from the tree), and without leaking the planning sheet's internal owner
names into a publishable artifact.

## Decision

Each outcome package **may** ship a `use-cases.yaml`:

```yaml
use_cases:
  - name: Customer 360
    status: in-progress   # one of: blocked | in-progress | planned | done
    tables: [gold_customer_ltv]   # optional: the gold tables that serve this use case
```

- **Per-package and co-located** (`outcome-packages/<package>/use-cases.yaml`), not a
  central manifest — so it cannot drift from the tree the way a `governance/*.yaml`
  enumeration would (the concern in ADR 0009).
- **Names + status only, no owners.** The planning sheet's owner names are internal and
  are intentionally excluded so the artifact is publishable.
- **Optional and NOT a scored MUST.** It does not affect Definition-of-Done
  completeness% (see `docs/definition-of-done.md`); a package is complete without it.
- **Planning intent, not derived state.** Unlike the UC-Domain mapping (ADR 0009) or the
  explorer's structural status badge, use cases are forward-looking business intent that
  cannot be inferred from the DDL, so they are authored, not generated.
- **Optional `tables:` per use case.** A use case may list the gold tables that serve it
  (`tables: [gold_...]`). It is a first-pass domain-knowledge mapping (authored, correctable
  by owners); the generator validates every listed name against the unit's real gold tables
  and fails loud on a typo. Since ADR 0045 an entry may also name another package's gold view
  as `<package>.<gold_view>`. It drives the explorer's L1 grouping (gold tables grouped by use
  case) and the use-case -> core lineage reveal (walked from each gold view's sources). A use
  case without `tables:` groups under "Not mapped to a use case".
- The model.json generator folds it into each outcome unit (`use_cases: [{name, status, tables?}]`,
  with a derived `consumes: [...]`; empty for core domains) and the explorer surfaces it under
  the package.

**Status axes are independent.** A use case's `status` (planning: is this use case
delivered) is distinct from the package's DoD maturity in `STATUS.md` and from the
explorer's structural `built | in-progress | planned` badge. A `done` use case can sit in
a package that is still 🟡 In progress; these are not the same ladder and must not be
conflated. The use-case-vs-DoD-maturity distinction is spelled out in
`docs/anatomy-of-a-model.md`; the structural badge is the explorer's own axis, derived by
its `deriveStatus` from whether the unit has tables and wired relationships.

## Consequences

- Contributors get one obvious, co-located place to record what a package is for; the
  explorer stops showing planned packages as unexplained empty boxes.
- No central manifest to maintain; the file lives and dies with its package.
- The three status vocabularies (use-case planning, package DoD maturity, explorer
  structural badge) coexist as separate axes: the first two are called out in
  `docs/anatomy-of-a-model.md` and the structural badge is defined by the explorer, so
  readers are pointed at these rather than left to conflate them.
- Because it is non-scored and optional, absence is never a Definition-of-Done gap.
- The README outcome-package table's **Use cases** column is generated from these files
  (via `model.json`) by `tools/gen_status.py`, and that surface is drift-gated by the
  standards-conformance job (`gen_status.py --check`), not auto-committed. So flipping a
  use case's `status` is now a **README docs-sync trigger**: run `make regen` and commit
  the regenerated README, exactly as when editing `STATUS.md` (CONTRIBUTING §8). This does
  not change its non-scored nature — it still never affects Done% or gates merge.
