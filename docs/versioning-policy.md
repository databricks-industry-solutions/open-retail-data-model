# Schema versioning and deprecation policy

**Status:** Proposed (2026-07-28) · Required by [ADR 0033](../governance/decisions/0033-relocate-footfall-fact-from-cmn-to-css.md)

`docs/data-model-standards.md` §A.15 mandates that "a backward-incompatible change to a published canonical
table (rename, type change, drop column) requires a schema-version bump and a deprecation window, or
downstream ABAC, Genie, and metric-view consumers break silently." That is a one-line mandate with no
mechanism behind it. This document is the mechanism.

It exists because ADR 0033 is the first backward-incompatible change ORDM has made to a published package,
and the precedent should be set explicitly rather than by accident. The relocation of `store_zone_interval`
is the policy's first worked example, recorded in §5.

**Scope.** This policy attaches to a domain or outcome package at the moment it is published and governs it from then on. Pre-publication objects are
under open refinement per [CONTRIBUTING.md](../CONTRIBUTING.md): improve in place, breaking changes are
normal and reconciled toward publish, and none of the obligations below apply until publication.

## 1. What counts as breaking

The test is whether a consumer's existing query stops returning the same answer — not whether it stops
running. A query that silently starts returning different numbers is worse than one that errors.

**Breaking:**

- Dropping or renaming a table, view, metric view, or column
- Narrowing a type (`BIGINT` → `INT`), or changing its semantics at the same type (`TIMESTAMP` →
  `TIMESTAMP_NTZ`, a UTC instant reinterpreted as local wall-clock)
- Moving a table between schemas, including package relocation
- Removing an allowed value from an enum domain, or adding a `CHECK`/`NOT NULL` that existing rows fail
- Changing the grain of a fact, or the additivity of a measure
- Changing a metric view measure's expression such that the same query returns a different number
- Removing a measure or dimension from a metric view

**Non-breaking:**

- Adding a nullable column, a new table, a new view, or a new metric view measure
- Widening a type (`INT` → `BIGINT`)
- Adding an allowed value to an enum domain
- Comment, synonym, display-name, and tag changes
- Adding a DQ check, unless it is at `error` severity and existing synthetic data fails it

**Ambiguous, and resolved as breaking:** adding a `NOT NULL` to a column that is nullable in practice; and
tightening a `CHECK` on a column a consumer filters on.

**The Lakebase dual-binding rule.** For canonical-core transactional-spine entities that carry (or will
carry) a Lakebase/Postgres binding generated from the shared logical model
([ADR 0005](../governance/decisions/0005-lakebase-physical-binding.md)), a change is **breaking if it is
breaking on either binding.** Lakebase generally raises the bar: under enforced constraints, column drops,
`NOT NULL` additions, and type narrowing are hard failures where Delta would silently allow them, so the
classification above is applied against the stricter binding. A spine entity's version tag describes the
logical model, and both physical bindings move with it; versioning and CI gate the two together.

## 2. Version numbering

Packages carry a semantic version in their file headers (`-- Version: <version>`). The repo-wide value lives in the [`VERSION`](../VERSION) file, and a release rewrites every header from it ([releasing.md](releasing.md)).

| Change | Bump |
|---|---|
| Breaking | Minor while pre-1.0 (`0.1` → `0.2`); major at and after 1.0 |
| Non-breaking additive | Patch pre-1.0; minor at and after 1.0 |
| Comment/tag/doc only | No bump |

**Pre-1.0 is not a licence to break freely.** A published `0.1-beta` package has adopters, and the
deprecation window in §3 applies at every version. What pre-1.0 buys is a minor bump instead of a major one,
not a shorter window.

## 3. The deprecation window

**One minor release, and a minimum of 90 days.** Whichever is longer. The 90-day floor exists because
release cadence is not yet regular enough for "one release" to mean a predictable amount of calendar time to
an adopter planning migration work.

During the window, all four of these hold:

1. **A compatibility shim preserves the retired shape.** A view reproducing the old column set at the old
   name, which is what makes an existing query keep working unchanged. It lives in the package that owned the
   old name — not the new owner — so that a derivation belonging to the old consumer stays with that
   consumer. Where the shim cannot fully reproduce the old shape, the header says so explicitly.
2. **`system.certification_status = 'deprecated'`** is set on the shim via `SET TAG`, per ADR 0010, which is
   how the deprecation reaches Unity Catalog rather than only the docs.
3. **The ODCS contract carries the deprecation notice**, including the replacement object and the removal
   date. This is the machine-readable path, and it is what a consumer's own tooling can act on.
4. **The shim's header names the replacement and the removal date**, so a developer who arrives via the SQL
   file rather than the contract gets the same information.

At the end of the window the shim is deleted in a release whose notes name it.

## 4. Obligations on the contributor making the change

- **The owning maintainer of every affected package signs off before merge.** A breaking change to someone
  else's review-complete package is their decision to accept, not the changer's to announce.
- **An ADR records the change**, with the rejected alternative and why. A breaking change with no recorded
  alternative reads as though none was considered.
- **The change is wired through in the same PR** — relationships, checks, generators, tests, `use-cases.yaml`,
  glossary, README, and regenerated artifacts (ODCS contracts, diagrams, `explorer/public/model.json`, the
  conformance matrix). A diff confined to the new package means the change was not wired through.
- **Migration guidance is written for the consumer**, not for the model: which object to read instead, and
  what to do about any column that has no replacement.

## 5. Worked example — ADR 0033

`commerce-media-networks.store_zone_interval` → `connected-store-signals.sensor_report_interval`.

| Policy element | How it was satisfied | Status |
|---|---|---|
| Breaking? | Yes, on three counts: schema move, rename, and three dropped columns | — |
| Shim | `commerce-media-networks/gold/store_zone_interval.sql` at the exact original fully qualified object name and ordered contract | Implemented; cutover pending |
| Dropped with no like-for-like replacement | New `opportunity_to_see` is NULL until CMN approves a versioned placement-level derivation. Historical values are retained unchanged in the CMN legacy mapping. Shape compatibility does not invent semantic equivalence. | Implemented; owner approval pending |
| ODCS deprecation notice | Carried in `contracts/odcs/commerce-media-networks.odcs.yaml`, regenerated from the shim header | Done |
| Certification tag | `ALTER VIEW … SET TAGS ('system.certification_status' = 'deprecated')` in `commerce-media-networks/comments.sql`, per ADR 0010 | Done |
| Removal date named in the header | `2026-10-31`, the §3 90-day floor counted from the relocation | Done |
| Version bump | CMN `0.1-beta` → `0.2-beta`, with the whole repo, in the 0.2-beta release (2026-10-07) | Done |
| Sign-off | CMN owner for exact-name cutover and OTS treatment: recorded in ADR 0033 (issue #105). CSS owner, privacy and maintainers | CMN: recorded; others **Pending review** |

The first version of this table claimed every row was done when two were not. That is the failure
mode a worked example is most prone to: it is written from the policy rather than from the tree, so it
documents intent as fact. The version bump was a release-time action — every package in the repo read
`0.1-beta` in its file headers and there is no single package-version file to bump, so bumping CMN
alone mid-PR would have created an inconsistency without conveying anything a reader can act on. It
landed with the repo-wide 0.2-beta release. The sign-off row stays partly open: the CMN-owner approval
is recorded in ADR 0033, while the CSS-owner, privacy and maintainer approvals are still pending, and a
document cannot assert its own approval.

One thing this example does **not** settle is the future OTS derivation. The retired value was
stored and its replacement needs placement-level inputs and CMN ownership. Returning NULL for new
rows is more compatible with the meaning of the field than publishing an unapproved estimate. The
legacy mapping preserves historical values while the exact-name view preserves query shape.

## 6. What this policy does not yet cover

- **Metric view versioning.** UC metric views are versioned by their own `version:` key in the YAML body
  (`1.1` today), which is the *spec* version and not the package's. How a breaking measure change interacts
  with that is unresolved.
- **Data migration.** This policy governs schema contracts, not the backfill of existing rows into a
  relocated table. For ADR 0033 the synthetic generator is simply repointed; a real adopter's backfill is
  their concern and ORDM offers no tooling for it.
- **Release cadence.** "One minor release" is only meaningful with a predictable cadence, and there is not
  one yet — hence the 90-day floor doing the real work.
