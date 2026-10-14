# How ORDM is maintained

We're keeping governance light while the working group is small.

- **Maintainers** (Databricks FE / RCT) curate the model, review PRs, and decide what gets promoted to the public repo.
- **Contributors** (Databricks + invited partners / SMEs) build and propose changes via PRs.

Two things are firm regardless of team size:
- The [open vs private boundary](docs/architecture.md#open-vs-private-boundary) — nothing customer-confidential or partner-proprietary enters this repo.
- Publishing to the public repo is a deliberate maintainer step, never automatic.

Publication from the working repository is scripted and curated by the maintainers; we'll formalize roles and review gates further as contribution volume grows. Design decisions are noted in [`governance/decisions/`](governance/decisions/).

## Interim rules

**Self-review** (until review gates are formalized). While the group is small, a deliverable's owner may also be its assigned reviewer
and record the sign-off, provided the self-review is disclosed, either in the sign-off issue or in the
Self-reviews disclosure in [REVIEWERS.md](REVIEWERS.md) (which lists every row whose Owner is also its
Reviewer). A self-reviewed deliverable can reach
🟢 Review complete. For the **initial public release only**, it may also be ✅ Published on the
maintainer's disclosed sign-off. From the next release on,
✅ Published needs a second, independent reviewer's sign-off, and `tools/gen_status.py --check`
enforces it. The initial release, 0.5, shipped on 2026-10-13, so the exception is off. The
self-reviewed deliverables it published (listed in `INITIAL_RELEASE_PUBLISHED`) stay ✅ while 0.5 is
the current release only: before the next release (a patch included) is cut, each needs its second, independent
sign-off or goes back to 🟢, and the check fails until it does.

