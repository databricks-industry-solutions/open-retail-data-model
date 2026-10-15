## What this PR adds/changes

<!-- Brief description. Link the issue: Closes #___ -->

## PR base

- [ ] Targeting `main` (checked by `base-must-be-main`; no stacked PRs)

## Layer

- [ ] Canonical core (entity: ______)
- [ ] Outcome package (package: ______)
- [ ] Synthetic data
- [ ] Docs / governance / tooling

## Checklist

- [ ] Follows [data model principles](https://github.com/databricks-industry-solutions/open-retail-data-model/blob/main/docs/data-model-standards.md)
- [ ] Vendor-neutral comments (no Informatica/Salesforce/brand examples)
- [ ] Strict typing; no derived metrics on master tables
- [ ] Synthetic data only — no real customer data
- [ ] Local checks pass: `pytest -q` and `make check` (data-quality checks run on a workspace when a deploy is configured)
- [ ] Ran `make regen` and committed the result (if model changed)
- [ ] Docs in sync: STATUS.md, README, glossary.md updated
- [ ] Requested a domain reviewer (see [REVIEWERS.md](https://github.com/databricks-industry-solutions/open-retail-data-model/blob/main/REVIEWERS.md)); for 🟢 Review complete, a review-signoff issue must be linked there

## Reviewer notes

<!-- Anything reviewers should focus on -->
