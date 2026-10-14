#!/usr/bin/env bash
# ============================================================
# ORDM · CI · sync the files a workspace job runs to a workspace folder, fast.
# ============================================================
# The lean per-PR gate submits a one-off job (generate_all -> refresh_gold_tables ->
# data_quality) whose python files must exist in the workspace. `databricks workspace
# import-dir .` uploaded the WHOLE checkout one file at a time (~1,050 files incl. the
# explorer, contracts, diagrams and docs) and took ~3 minutes before the job could start.
#
# This uploads only what the job reads (the model SQL, the generators, tools, the DQ runner,
# the bootstrap SQL and config, minus diagrams) and does it with bounded parallelism. Every
# python_file path the job spec names is unchanged under the synced folder, so the job and
# the PR comment link still work.
# Notebook-source files (e.g. notebook-templates/*.sql) may land at a different browsable path than
# import-dir gave them; the job does not run them. Measured: 568 files in ~30s.
#
# Usage: tools/sync_workspace_bundle.sh <workspace_dest_dir> [parallelism] [--clean]
#   --clean deletes <workspace_dest_dir> first, so a file removed or renamed in a later push does
#   not linger there (the remote job finds files by glob and would load the stale copy).
# Needs: git, databricks CLI (authenticated). Runs from the repo root.
# ============================================================
set -euo pipefail

DEST="${1:?usage: sync_workspace_bundle.sh <workspace_dest_dir> [parallelism] [--clean]}"
PAR="${2:-16}"
CLEAN="${3:-}"

# What the job reads. Keep in sync with the job spec's python files and their inputs
# (tools/apply_model_ddl.py reads canonical-core, outcome-packages, the bootstrap SQL in
# runtime/examples/deploy-with-dab, standards and databricks.yml; generate_all reads
# runtime/synthetic-data (generators and seeds.yaml); run_checks in runtime/data-quality reads the
# checks.sql files).
PATHS=(canonical-core outcome-packages runtime/synthetic-data runtime/data-quality
       runtime/examples/deploy-with-dab tools standards databricks.yml requirements-dev.txt)

STAGE="$(mktemp -d)"
FAILED="$(mktemp)"
trap 'rm -rf "$STAGE" "$FAILED"' EXIT
# git archive = exactly the committed tree at HEAD (no .git, no untracked or ignored files).
git archive HEAD -- "${PATHS[@]}" ':(exclude)*/diagrams/*' | tar -x -C "$STAGE"

cd "$STAGE"
n_files=$(find . -type f | wc -l | tr -d ' ')
echo "[ordm] syncing ${n_files} files to ${DEST} (parallelism ${PAR})"

if [ "$CLEAN" = "--clean" ]; then
  # "Not found" is expected on a PR's first run. Any other failure would leave stale files that
  # the remote job's globs load, so surface it.
  if ! del_err=$(databricks workspace delete --recursive "$DEST" 2>&1 >/dev/null); then
    case "$del_err" in
      *"does not exist"*|*RESOURCE_DOES_NOT_EXIST*|*"not found"*|*"Not Found"*) ;;
      *) echo "::warning::sync_workspace_bundle.sh --clean could not delete ${DEST}; stale files may remain: $(printf %s "$del_err" | tail -1)" ;;
    esac
  fi
fi

# Directories first, then files. The mkdirs calls run concurrently, so parent-before-child order is
# NOT guaranteed; this relies on `workspace mkdirs` creating missing parents (and being idempotent).
# (Newline-delimited then NUL-converted: portable across GNU and BSD find/sed/xargs.)
find . -type d | sed 's|^\.||' | tr '\n' '\0' \
  | xargs -0 -P "$PAR" -I{} sh -c '
      databricks workspace mkdirs "$0" >/dev/null 2>&1 \
        || { sleep 2; databricks workspace mkdirs "$0"; }' "${DEST}{}"

export DEST FAILED
find . -type f | sed 's|^\./||' | tr '\n' '\0' \
  | xargs -0 -P "$PAR" -I{} sh -c '
      databricks workspace import "$DEST/$1" --file "$1" --format AUTO --overwrite >/dev/null 2>&1 \
        || { sleep 2; err=$(databricks workspace import "$DEST/$1" --file "$1" --format AUTO --overwrite 2>&1 >/dev/null); } \
        || echo "$1: $(printf %s "$err" | tail -1)" >> "$FAILED"' _ {}

if [ -s "$FAILED" ]; then
  echo "[ordm] ERROR: $(wc -l < "$FAILED" | tr -d ' ') file(s) failed to upload:" >&2
  head -20 "$FAILED" >&2
  exit 1
fi
echo "[ordm] synced ${n_files} files"
