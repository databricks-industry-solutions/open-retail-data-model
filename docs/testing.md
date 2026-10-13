# Testing and CI

This explains what the tests and CI do, when they run, and how to run them yourself, so CI is never the first place you see a failure. The rules they enforce live in the standard, [`docs/data-model-standards.md`](data-model-standards.md); this page is about how they are checked.

## The idea

Machines enforce conformance, fast and cluster-free, and humans judge substance. The standard is split into mandates (the machine-checkable rules) and design principles (the judgment calls a script cannot make). CI runs the mandates on every PR; a reviewer reads the model for the principles. So the automated gate is an auto-review of mechanics, not of whether the model is good. That is what the human review is for.

The tests form a pyramid: many fast static tests at the base, fewer Spark tests in the middle, and one deploy smoke test at the top.

## The layers

Static conformance (cluster-free). The standards-conformance suite in `tests/standards/` enforces the machine-checkable mandates by parsing the committed DDL. It checks: one CREATE per file (ARTIFACT-ONE-CREATE), no markdown under a tables directory (ARTIFACT-NO-MD-UNDER-TABLES), layer integrity (LAYER-INTEGRITY, with the tree self-FK exception), the primary-key contract (PK-CONTRACT), strict typing including the money rule (TYPING-MONEY), no inline CHECK constraints (NO-INLINE-CHECK), required data-type tags (TAGS-DATA-TYPE), SCD2 join correctness (SCD2-JOIN-CONTRACT), FK completeness (FK-COMPLETENESS), and clustering-key type discipline (CLUSTER-KEY-TYPE). Additional mandates are listed in `standards/rules.yaml` with status: planned and will be added to CI as they mature. No Spark and no workspace are needed.

Static model-consistency (cluster-free). The existing suite (for example `tests/test_customer_model.py`) parses each table with sqlglot and asserts the synthetic-generator columns match the DDL, generator enum values are a subset of the declared allowed values, nothing hardcodes a catalog or workspace, no banned SQL appears, and no license header sits in authored DDL.

Spark logic tests. The gold-view tests run the real gold SQL on small temp-view fixtures with known answers, so the business logic (RFM, LTV, supplier scorecard, promo ROI, category growth) is verified without a workspace. They skip cleanly when pyspark is absent and run in CI where Java and pyspark are present.

Data-quality runner. `runtime/data-quality/run_checks.py` executes the `-- check: <name> | severity: error|warn|metric` assertions in each `checks.sql`, COUNT-wrapped so no rows ship to the driver, and fails on any error-severity check.

Deploy smoke. The Databricks Asset Bundle validate, deploy, and destroy step proves the model actually loads against the real engine. It needs a workspace and runs after the static gate passes.

## The single source of truth, and why docs and CI cannot drift

The enforceable rules are data, in [`standards/rules.yaml`](../standards/rules.yaml). Three things derive from that one file: the CI checks execute the rules marked enforced, the conformance matrix in the standard is generated from it by `tools/gen_conformance_matrix.py`, and a meta-test (`tests/standards/test_standards_meta.py`) fails the build if any of the three disagree. So you cannot add a rule to the prose without a check, write a check that maps to no rule, or let the matrix go stale. The registry, the checks, and the standard stay one entity.

The `known_exceptions` list in the registry is a baseline of tracked debt. A check excuses only the violations listed there, so the suite stays green while the debt stays visible, and the list shrinks as fixes land.

## When it runs

On every PR to `main` and on push (see `.github/workflows/databricks-ci.yml`):

- the `test` job runs the static model-consistency, Spark tests, and the DDL-correctness conformance suite as **4 parallel shards** (check names **"unit + spark tests (1/4)"** to **"(4/4)"**). Each shard runs whole test files, balanced on the measured CI time per file in `tests/ci_test_durations.json` (refresh it with `tools/ci_test_durations.py` from the shards' JUnit artifacts), on every runner core via `pytest-xdist`. Shard 1 also runs the DDL-correctness conformance gate, the drift guard (before anything rewrites the generated files), and, serially, the tests marked `writes_repo` (generator `--write` round-trips that rewrite files in the checkout, so they never run while another test reads those files). The `test-summary` job (check name **"unit + spark tests"**) passes only when every shard passed; it is the intended hard gate before the deploy (merge-blocking once it is a required check in branch protection, which this repo does not have yet; see below). Locally, plain `pytest` runs everything; to use every core, run `pytest -n auto --dist loadgroup -m "not writes_repo"` and then `pytest -m writes_repo` (`tests/conftest.py` groups each file onto one worker). The parallel CI run fails if it leaves a tracked file changed or a new file under `explorer/public/` or `contracts/`, so a repo-writing test must carry `writes_repo` (the guard cannot see a byte-identical rewrite or a new file elsewhere, so the marker is still the rule).
- the `standards-conformance` job (display name **"standards conformance"**) re-runs the full `tests/standards` suite (rule tests included) plus the conformance matrix sync and README status surfaces sync checks. It is advisory for now, a separate job not in the required set, so it reports without blocking merge. It will be promoted to a required check once the baseline is clean. The conformance rule checks themselves (the GATING mandates) run inside the `test` job and fail it, so they share its hard-gate status.
- the `regen-artifacts` job (display name **"generated artifacts in sync"**) regenerates derived artifacts (ODCS contracts, ER diagram sources and their SVGs, model.json) from the DDL and commits them on same-repo PRs; the `test` job's drift-guard steps fail fork PRs and push to main if any drift is detected.
- the `validate-and-test` job (display name **"bundle deploy smoke (workspace)"**) runs the bundle deploy smoke test against a workspace, after `test` passes.

The job **ids** above are `test`, `test-summary`, `standards-conformance`, `regen-artifacts` and `validate-and-test`; `test-summary` is new and the others are unchanged; only their check-run **display names** were made descriptive (the workflow itself is "ORDM CI"). This matters only if branch protection is ever enabled: GitHub matches a required status check by its check-run name, which is the job's `name:` when set. This repo has no branch protection today (a private repo cannot enforce it until it is on a paid plan or made public), so nothing is gated by name yet. When branch protection is turned on, list the required checks by the **display names** above (e.g. "unit + spark tests", the `test-summary` job, rather than the four shard names, so the gate does not depend on the shard count), not the bare job ids, or the gate will not match.
- a `pr-base-guard` workflow (check-run name `base-must-be-main`) fails any PR whose base is not `main` (no stacked PRs). It is not yet a required check (the repo has no branch protection), but is intended to prevent content loss from the merge history.
- an `auto-request-reviewers` workflow requests review from 3 members of the `@open-retail-data-model/reviewers` pool on every non-draft PR, skipping the author. The 3 are a random subset seeded by the PR number, so re-runs pick the same people. It does not read `REVIEWERS.md`, so still request the domain reviewer from `REVIEWERS.md` yourself (see `CONTRIBUTING.md`). Never blocks.
- the `explorer-ci` workflow runs the model explorer's typecheck + vitest + build; an **advisory** `explorer-e2e` workflow runs its Playwright browser tests (comment/report only, never blocks merge).
- an **advisory** `link-check` workflow runs [lychee](https://github.com/lycheeverse/lychee) over the Markdown docs: an offline (local-links-only) pass on PRs and a full external sweep weekly + on demand. Both run with `fail:false`, so they report broken links into the job summary but never block a merge.
- an **advisory** `docs-guard` workflow warns (never fails) when a PR changes `canonical-core/`/`outcome-packages/` but no hand-authored docs (a keep-docs-in-sync nudge).
- an **advisory** `ordm-lean-pr-deploy` workflow (the lean per-PR deploy gate) computes the domains a PR touched and, into an isolated per-PR schema (`pr_<N>`), applies only those domains' DDL, generates their synthetic data, and runs their DQ checks on the review workspace — a fast, scoped real-deploy signal (minutes, not the full job). It no-ops when a PR touches no `canonical-core/`/`outcome-packages/` files, skips for fork PRs (no secrets) and when no workspace is configured, and keys concurrency on the PR number so different PRs run in parallel. The synced dir holds only what the job runs (model SQL, generators, tools, DQ runner; no diagrams, docs or explorer), uploaded in parallel by `tools/sync_workspace_bundle.sh`, and the gate's runner job is capped at 40 minutes. Materialized views are demoted to plain views in this gate, so MV column comments take the inline path here and the separate `COMMENT ON COLUMN` path only in the daily deploy: a broken MV column comment shows up in the daily deploy, not in this gate. The `pr_<N>` schema and synced dir are **kept while the PR is open** (refreshed on every push) so a contributor can browse their pre-created objects in the workspace; the daily deploy's sweep reaps them once the PR is closed or merged (closed-PRs only). On a run that deployed, the gate posts (and updates in place, once) a sticky PR comment linking to the ephemeral `pr_<N>` schema, the synced job dir, and the permanent serving catalog, noting the PR database lives only while the PR is open. If the changed domains ship no synthetic-data generator (e.g. `unified-customer-view`), it raises a GitHub `::warning::` that the DQ ran against empty tables (a vacuous pass, not a real data signal) so a contributor is not misled by the green. The `databricks-ci` `test` job remains the source of truth; this is an extra scoped check.
- an `ordm-daily-deploy` workflow (scheduled) deploys the whole model + data + DQ into the main serving catalog (`ORDM_MAIN_CATALOG`, default `open_retail_data_model_catalog` — the durable catalog, distinct from the lean gate's `ordm_cicd`) once a day via the `deploy_ordm_daily` bundle job, which carries a native `on_failure` email (recipients set in the bundle's `serving` target). It targets **6pm America/Denver**: the workspace-side schedule carries `timezone_id America/Denver` and is DST-correct, while the GitHub cron is UTC-only and pinned to the MDT offset (`0 0 * * *` = 00:00 UTC = 6pm MDT; during MST it fires at 5pm MT, harmless for an off-peak deploy). Also runnable on demand (`workflow_dispatch`). After the deploy it runs a best-effort **sweep** (never fails the deploy) that reaps leaked lean-gate resources for **closed PRs only**: it drops each closed PR's `pr_<N>` schema in the CI catalog (`ORDM_CI_CATALOG`, default `ordm_cicd`) and deletes that PR's `/Workspace/Shared/ordm-lean-ci/pr-<N>` synced dir. It queries the open-PR set and skips those, because an open PR's `pr_<N>` may be mid-deploy (the lean gate and the daily job can overlap) and dropping it under a live run would corrupt it; a closed (merged or abandoned) PR can never have a live run, so its resources are the true permanent leak. The sweep only ever touches the CI catalog + the lean-CI dir, never the serving catalog.
- a `publish` workflow deploys the documentation site to GitHub Pages on manual trigger (`workflow_dispatch`).

### Enabling the deploy workflows (operator setup)

The lean per-PR gate and the daily deploy touch a real workspace, so they stay dormant until it is wired:

- **Required (shared with `databricks-ci`):** the `DATABRICKS_HOST` repository **variable** and the `DEPLOY_NOTEBOOK_TOKEN` **secret**. With neither set, all three deploy workflows skip (never fail).
- **Optional catalog overrides:** `ORDM_CI_CATALOG` (per-PR gate target, default `ordm_cicd`) and `ORDM_MAIN_CATALOG` (daily-deploy target, default `open_retail_data_model_catalog`). Note: the daily sweep `DROP SCHEMA ... CASCADE`s any `pr_<digits>` schema in `ORDM_CI_CATALOG` that does not belong to an open PR, so this catalog must be **dedicated to the lean per-PR gate** — never hand-create a `pr_<N>`-named schema there or point `ORDM_CI_CATALOG` at a catalog holding durable data.
- **Daily failure alert:** the `serving` target's `alert_emails` in [`databricks.yml`](../databricks.yml) must hold at least one real recipient — the daily workflow **fails fast** on a placeholder or empty list (a complex/list variable can only be overridden per target, not via `--var`, so it lives in the bundle config, not a repo variable). A fork/maintainer redeploying elsewhere should repoint it at their own address.

## Run it locally

```sh
pip install -r requirements-dev.txt

pytest -q                                        # the required suite (static + Spark)
pytest -q tests/standards                        # the standards-conformance suite
python tools/gen_conformance_matrix.py --check   # the conformance matrix is in sync
python runtime/data-quality/run_checks.py                # the data-quality assertions (needs Spark)
make check                                       # every generated artifact is in sync with the DDL
```

`make check` runs the artifact-drift gates (`check-odcs`/`check-er`/`check-model`/`check-svg`/`check-status`, plus the matrix) and `check-version` (every version stamp equals `VERSION`) that CI also runs; run **`make regen`** after any model change to regenerate and commit them (and `make regen-svg` if you touched an ER diagram - that render needs Node + mermaid-cli, though the `check-svg` gate itself is pure-python). See [CONTRIBUTING](../CONTRIBUTING.md) for the full source-of-truth flow.


## Adding a new check

Three steps, and the meta-test makes sure you do all three. Add the rule to `standards/rules.yaml` with `status: enforced` and the `test` path. Implement the check in `tests/standards/test_standards_conformance.py` and map its function to the rule id in the `ENFORCES` dict. Regenerate the matrix with `python tools/gen_conformance_matrix.py --write`. If any of the three is missing, the meta-test fails.
