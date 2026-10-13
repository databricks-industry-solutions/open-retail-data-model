# ORDM derived-artifact regeneration + drift gates.
#
# The SOURCE of truth is the hand-authored input: the DDL under */tables/, each
# package's relationships.sql, the gold-view SQL under */gold/, use-cases.yaml,
# and the glossaries. EVERYTHING ELSE in the repo is GENERATED from that source:
# the ODCS contracts, the ER diagram sources (.mmd/.dbml + README <picture>), the
# explorer's model.json (schema + FK + use-case -> core lineage), the
# conformance matrix, and the README status surfaces (count badge + status
# tables, generated from STATUS.md by tools/gen_status.py).
#
# To keep the repo internally consistent there is ONE place that lists every
# generator: this file. Contributors run `make regen` before pushing; CI runs
# `make check` and fails if any committed artifact drifted from the source, and on
# same-repo PRs the regen-artifacts job runs `make regen-ci` to regenerate + commit
# them. Adding a new derived artifact means adding its generator here once (to
# `regen-ci`, so both local `make regen` and CI pick it up - or to `regen` plus a
# check target if a separate job gates it, as the conformance matrix is), and it is
# then regenerated and gated everywhere without editing the CI workflow.
#
#   make regen      regenerate every deterministic derived artifact in place
#   make check      fail if any committed artifact is out of sync with the source
#   make regen-svg  refresh the rendered ER-diagram SVG snapshots (needs Chromium)
#   make release NEW_VERSION=0.6        bump the model version + cut the CHANGELOG
#                   (docs/releasing.md)

# CI's setup-python provides `python`; local shells usually only have `python3`.
# Override with e.g. `make check PYTHON=python` if needed.
PYTHON ?= python3

.PHONY: regen regen-ci check regen-svg check-odcs check-er check-model check-matrix check-svg check-status check-version release

# ---- regenerate ----------------------------------------------------------------
# regen-ci: the deterministic, pure-python artifacts the same-repo CI
# regen-artifacts job regenerates AND auto-commits. This is the single generator
# list that job calls (via `make regen-ci`), so adding an auto-committed artifact
# is a one-line change here, not a parallel edit to the workflow. The conformance
# matrix is deliberately NOT here (nor in that CI job): it is gated separately by
# the advisory standards-conformance job, so auto-committing it from two places
# would race - see check-matrix.
#
# ORDER IS LOAD-BEARING: generate_odcs must run BEFORE gen_model_json, because
# gen_model_json reads each unit's committed ODCS file from disk to set model.json's
# contract_path (a missing file silently nulls the link). Keep odcs first if editing.
regen-ci:
	$(PYTHON) tools/generate_odcs.py
	$(PYTHON) tools/gen_er_diagrams.py --write
	$(PYTHON) tools/gen_model_json.py --write

# regen: everything regen-ci does PLUS the conformance matrix, so a local run
# regenerates the full superset before pushing. The rendered .svg IMAGES are NOT
# here: mermaid's layout is not byte-reproducible across hosts, so SVGs are
# snapshots refreshed via `make regen-svg` (or CI's renderer); the gated source of
# truth is the .mmd/.dbml.
#
# ORDER IS LOAD-BEARING: gen_status.py --write must run BEFORE regen-ci, because
# regen-ci includes gen_model_json.py which copies glossaries to explorer/public/.
# If gen_status rewrites glossaries after that copy, the explorer copies stay stale.
regen:
	$(PYTHON) tools/gen_status.py --write
	$(MAKE) regen-ci
	$(PYTHON) tools/gen_conformance_matrix.py --write

# Rendered ER-diagram SVGs (Chromium + mermaid-cli). Non-deterministic across
# hosts, so intentionally OUT of `regen`/`check`.
regen-svg:
	tools/render_diagrams.sh

# ---- drift gate ----------------------------------------------------------------
# `check` regenerates in place and FAILS if a committed artifact differs from what
# the source would produce. This is the single entry point CI uses as the gate.
check: check-odcs check-er check-model check-matrix check-svg check-status check-version

# ODCS contracts are a generated lockfile. Regenerate and fail on ANY difference
# (modified, newly-added, or orphaned), without staging into the index.
check-odcs:
	@$(PYTHON) tools/generate_odcs.py >/dev/null
	@if [ -n "$$(git status --porcelain -- contracts/odcs/)" ]; then \
		echo "ERROR: contracts/odcs/ is stale (a contract is missing, extra, or changed) - run 'make regen' and commit:"; \
		git status --porcelain -- contracts/odcs/; exit 1; \
	fi

# ER diagram sources (.mmd/.dbml + README <picture>) are self-checking.
check-er:
	@$(PYTHON) tools/gen_er_diagrams.py --check \
		|| { echo "ERROR: ER diagram sources are stale - run 'make regen' (then 'make regen-svg') and commit."; exit 1; }

# explorer/public/model.json (schema + FK + use-case -> core lineage).
check-model:
	@$(PYTHON) tools/gen_model_json.py --check \
		|| { echo "ERROR: explorer/public/model.json is stale - run 'make regen' and commit."; exit 1; }

# The conformance matrix. Part of the local `make check` superset, but NOT of the
# same-repo CI drift step (which runs check-odcs/er/model); the matrix is gated
# separately by the advisory standards-conformance CI job, which owns it. So a
# green same-repo CI does not by itself prove the matrix is fresh - `make check`
# (or that job) does.
check-matrix:
	@$(PYTHON) tools/gen_conformance_matrix.py --check \
		|| { echo "ERROR: the conformance matrix is stale - run 'make regen' and commit."; exit 1; }

# Rendered ER-diagram SVGs must be fresh vs their .mmd source. A deterministic
# sha-stamp comparison (NOT a byte compare - mermaid's render is not reproducible),
# so it is safe to gate on. This closes the last derived-artifact type that could
# drift. Refresh with `make regen-svg`. On same-repo PRs CI re-renders + commits SVGs
# for you (databricks-ci.yml regen-artifacts); forks/push are gated here.
check-svg:
	@$(PYTHON) tools/check_diagram_svgs.py --check \
		|| { echo "ERROR: diagram SVGs are stale vs their .mmd - run 'make regen-svg' and commit."; exit 1; }

# README status surfaces (count badge + core table + themed outcome tables) and
# per-folder "> Status:" lines in domain/package README and glossary files are
# all generated from STATUS.md (the hand-maintained source of truth). Gated like the
# conformance matrix - part of the local `make check` superset and the advisory
# standards-conformance CI job, NOT auto-committed (README is human-edited prose).
# Do not hand-edit the "> Status:" lines; edit STATUS.md and run `make regen` instead.
check-status:
	@$(PYTHON) tools/gen_status.py --check \
		|| { echo "ERROR: README status surfaces or domain/package status lines are stale vs STATUS.md - run 'make regen' and commit."; exit 1; }

# check-version: every version stamp (file headers, notebook titles, "> Status:" lines)
# must equal the VERSION file. tools/release.py is the only writer of either.
check-version:
	@$(PYTHON) tools/release.py check

# ---- release -------------------------------------------------------------------
# release: set NEW_VERSION in VERSION and every stamp, cut CHANGELOG [Unreleased] to the
# dated release, then regenerate the derived copies (explorer glossary mirrors). Refuses a
# version that is not newer, an empty [Unreleased], or merged PRs with no entry. Pass
# RELEASE_ARGS="--date 2026-10-13" or "--dry-run" through; a dry run skips the regen.
# See docs/releasing.md.
release:
	@test -n "$(NEW_VERSION)" || { echo "usage: make release NEW_VERSION=0.6 [RELEASE_ARGS=...]"; exit 2; }
	$(PYTHON) tools/release.py bump $(NEW_VERSION) $(RELEASE_ARGS)
	@case " $(RELEASE_ARGS) " in *" --dry-run "*|*" -n "*) ;; *) $(MAKE) regen ;; esac
