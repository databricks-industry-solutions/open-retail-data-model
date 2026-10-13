"""Guard every GitHub Actions workflow `run:` block against shell SYNTAX errors.

A `run:` step with a shell syntax error (an unbalanced if/fi, a stray `done`, a
mismatched quote) does not fail loudly at author time -- it fails only when that step
executes in CI, and a step that is CONDITIONAL (if: always(), if: failure(), a schedule)
may not execute on the PR that introduced it, so the break merges green and only surfaces
later in production. That is exactly what happened to the daily-deploy sweep (AI review
#108 B1: a stray `done` made the whole step un-parseable, so the leaked-schema reaper could
never run). `bash -n` parses a script without executing it, so it catches these statically
and cheaply.

This test extracts every `run:` block from every workflow and `bash -n`-checks it (only for
bash/sh steps -- a `shell:` override to python/pwsh is skipped). No workspace, no network.
"""
import glob
import os
import shutil
import subprocess

import pytest

yaml = pytest.importorskip("yaml")

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
# Both extensions: GitHub honors .yml AND .yaml for workflows, and this repo uses both (e.g.
# publish.yaml). Globbing only *.yml silently skipped a real workflow that imports non-stdlib
# modules -- exactly the gap the import guard exists to close (AI review #115 H1). ACTION_GLOBS
# below already covers both extensions; keep the workflow glob consistent.
WORKFLOW_GLOBS = (os.path.join(REPO, ".github", "workflows", "*.yml"),
                  os.path.join(REPO, ".github", "workflows", "*.yaml"))
# Composite ACTIONS (.github/actions/**/action.yml) also carry run: blocks under runs.steps.
# They are load-bearing (both deploy workflows `uses:` databricks-setup) and their run: blocks
# only execute on the live/scheduled path -- skipped in ordinary PR CI -- so a shell syntax
# error there merges green and surfaces only in production, exactly the B1 class this guards
# (AI review #108 M1). Cover them too, not just workflow jobs.
ACTION_GLOBS = (os.path.join(REPO, ".github", "actions", "**", "action.yml"),
                os.path.join(REPO, ".github", "actions", "**", "action.yaml"))

# Shells bash -n can validate. A step may override `shell:` (e.g. python) -- skip those.
_BASH_SHELLS = {None, "bash", "sh", "bash -e {0}"}


def _iter_run_steps():
    """Yield (source_file, container_id, step_index, step_name, shell, script) for every
    `run:` step across all workflows AND composite actions. `shell` is the effective shell
    (workflow: defaults/job/step; composite action: step-level, which GitHub REQUIRES)."""
    # 1. Workflow jobs.
    for wf in sorted(set(f for g in WORKFLOW_GLOBS for f in glob.glob(g))):
        doc = yaml.safe_load(open(wf))
        if not isinstance(doc, dict):
            continue
        defaults_shell = (((doc.get("defaults") or {}).get("run") or {}).get("shell"))
        for job_id, job in (doc.get("jobs") or {}).items():
            if not isinstance(job, dict):
                continue
            job_shell = (((job.get("defaults") or {}).get("run") or {}).get("shell")
                         or defaults_shell)
            for i, step in enumerate(job.get("steps") or []):
                if not isinstance(step, dict) or "run" not in step:
                    continue
                shell = step.get("shell") or job_shell
                yield (wf, job_id, i, step.get("name") or f"step[{i}]", shell, step["run"])
    # 2. Composite actions' runs.steps (only when using: composite; a JS/Docker action has none).
    seen = set()
    for pat in ACTION_GLOBS:
        for af in sorted(glob.glob(pat, recursive=True)):
            if af in seen:
                continue
            seen.add(af)
            doc = yaml.safe_load(open(af))
            if not isinstance(doc, dict):
                continue
            runs = doc.get("runs") or {}
            if runs.get("using") != "composite":
                continue
            for i, step in enumerate(runs.get("steps") or []):
                if not isinstance(step, dict) or "run" not in step:
                    continue
                # A composite run step MUST declare its own shell (no job default to inherit).
                yield (af, "runs", i, step.get("name") or f"step[{i}]", step.get("shell"),
                       step["run"])


def _clean_for_bash_n(script):
    """Normalize a run: block so `bash -n` checks the SHELL structure, not embedded data.

    Two things confuse a naive bash -n over a workflow run: block:
      * GitHub expands `${{ ... }}` before the shell sees it; the literal braces can look like
        an unbalanced expansion. Replace each with a plain token.
      * A heredoc BODY is literal data (e.g. `PROMPT=$(cat <<'PROMPT' ... PROMPT)` embeds prose
        with stray `)`/`'`, and `python3 - <<'PY' ... PY` embeds Python). bash itself parses
        heredocs fine, but only if the CLOSING delimiter is intact; to keep the check about the
        surrounding shell we blank each heredoc body to a single placeholder line, preserving
        the `<<TAG` opener and the closing `TAG` so the redirection still parses.
    """
    import re
    script = re.sub(r"\$\{\{[^}]*\}\}", "GHA_EXPR", script)
    lines = script.splitlines()
    out, i = [], 0
    heredoc_re = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = heredoc_re.search(line)
        if m:
            tag = m.group(1)
            i += 1
            # swallow the body until the closing tag (indented tag allowed for <<-)
            while i < len(lines) and lines[i].strip() != tag:
                i += 1
            out.append(f"{tag}")   # emit the closing delimiter so the heredoc is well-formed
        i += 1
    return "\n".join(out)


_STEPS = list(_iter_run_steps())

# All run: scripts of a job/composite-action, concatenated, keyed by (file, container_id). A pip
# install in an EARLIER step of a job persists for LATER steps in that same job (GitHub Actions
# semantics), so the import-install guard must check installs JOB-WIDE, not just within the block
# that does the import (AI review #115 M1). Concretely, publish.yaml installs markdown/bs4 in an
# "Install dependencies" step and imports them in a later step -- correct, and must not fail.
_JOB_SCRIPTS = {}
for _wf, _job, _i, _n, _s, _sc in _STEPS:
    _JOB_SCRIPTS.setdefault((_wf, _job), []).append(_sc)


def test_there_are_run_steps_to_check():
    """Sanity: the extractor actually found run: steps (guards against a silent no-op if
    the workflow layout changes and nothing is discovered)."""
    assert _STEPS, "no workflow run: steps discovered -- extractor or glob is wrong"


def test_both_workflow_extensions_are_scanned():
    """The workflow glob must cover BOTH .yml and .yaml (AI review #115 H1/m2): globbing only
    *.yml silently skipped publish.yaml, which imports non-stdlib modules the import guard targets.
    Assert a .yaml-extension workflow is actually in the scanned set, so the coverage can't
    regress back to .yml-only."""
    scanned = {os.path.basename(s[0]) for s in _STEPS}
    yaml_wfs = {os.path.basename(f)
                for f in glob.glob(os.path.join(REPO, ".github", "workflows", "*.yaml"))}
    if not os.path.exists(os.path.join(REPO, "tools", "publish", "manifest.yaml")):
        pytest.skip("public tree: the *.yaml workflows are staging-only")
    assert yaml_wfs, "no *.yaml workflow on disk to validate against -- update this test"
    assert yaml_wfs & scanned, (
        f".yaml-extension workflow(s) {sorted(yaml_wfs)} exist but none were scanned -- "
        f"the workflow glob regressed to .yml-only")


def test_composite_action_run_blocks_are_covered():
    """The guard must reach composite-action run: blocks, not just workflow jobs (AI review
    #108 M1): databricks-setup/action.yml has run: steps that only fire on the live deploy
    path, so a shell error there would merge green. Fail loudly if none are discovered, so the
    coverage can't silently regress when the extractor or action layout changes."""
    action_steps = [s for s in _STEPS if s[0].endswith("action.yml") or s[0].endswith("action.yaml")]
    assert action_steps, "no composite-action run: blocks discovered -- coverage regressed"
    assert any("databricks-setup" in s[0] for s in action_steps)


@pytest.mark.skipif(shutil.which("bash") is None, reason="bash not available")
@pytest.mark.parametrize(
    "wf,job,idx,name,shell,script",
    _STEPS,
    ids=[f"{os.path.basename(w)}:{j}:{n}" for (w, j, _i, n, _s, _sc) in _STEPS],
)
def test_run_block_has_valid_bash_syntax(wf, job, idx, name, shell, script):
    """`bash -n` each bash/sh run: block. A syntax error means the step can never execute
    (AI review #108 B1). Non-bash steps (a `shell:` override) are skipped."""
    if shell not in _BASH_SHELLS:
        pytest.skip(f"non-bash shell: {shell}")
    cleaned = _clean_for_bash_n(script)
    proc = subprocess.run(["bash", "-n"], input=cleaned, text=True,
                          capture_output=True)
    assert proc.returncode == 0, (
        f"shell syntax error in {os.path.basename(wf)} job '{job}' step '{name}':\n"
        f"{proc.stderr}")


# Non-stdlib modules an inline workflow python3 block might import. If a step imports one of
# these, that same step (bare ubuntu runner: only setup-python ran, no site-packages) MUST
# install it first, or it dies at import with ModuleNotFoundError. This exact bug took down the
# daily deploy 3 nights running: the "Require a real alert recipient" guard did `import yaml`
# with no `pip install pyyaml`, so it crashed before it could check anything and fail-fast the
# whole deploy. These workflows run on a SCHEDULE, so a broken import never surfaces in PR CI --
# hence a static guard.
# import-module -> its pip PACKAGE name (they differ: `import yaml` needs `pyyaml`, `import bs4`
# needs `beautifulsoup4`). This is a CURATED SUBSET -- the non-stdlib modules actually imported by
# THIS repo's inline workflow python, NOT a complete stdlib check (m1). If a new workflow step
# imports a non-stdlib module not listed here (e.g. jinja2, tomli), ADD it so the guard covers it;
# an unlisted import is silently not checked.
_IMPORT_TO_PIP_PKG = {
    "yaml": "pyyaml",
    "bs4": "beautifulsoup4",
    "markdown": "markdown",
    "dbldatagen": "dbldatagen",
    "sqlglot": "sqlglot",
    "databricks": "databricks-sdk",
    "requests": "requests",
    "pandas": "pandas",
    "numpy": "numpy",
}


@pytest.mark.parametrize(
    "wf,job,idx,name,shell,script",
    _STEPS,
    ids=[f"{os.path.basename(w)}:{j}:{n}" for (w, j, _i, n, _s, _sc) in _STEPS],
)
def test_run_block_installs_any_non_stdlib_python_import(wf, job, idx, name, shell, script):
    """A run: block whose inline python imports a non-stdlib module must have THAT module's pip
    package installed somewhere in the SAME JOB -- either an explicit `pip install ...<pkg>...`
    naming it, or a `-r <requirements>.txt` install (which pulls the repo deps in). Guards the
    ModuleNotFoundError class that broke the scheduled daily deploy (import yaml with no
    pip install pyyaml).

    Scope is the JOB, not the block (M1): a pip install in an earlier step of a job persists for
    later steps, which is the correct, working idiom publish.yaml uses (install deps in one step,
    import in a later step). Requiring same-block install would false-positive that valid pattern.

    The scan applies to ALL run: blocks regardless of shell (unlike the bash -n check): the target
    is python-in-bash heredocs, and a non-heredoc block simply won't contain import statements. A
    prose heredoc that happened to contain an `import <listed-mod>` example line could
    false-positive, but that is not the case in any current block (m2, conscious choice)."""
    import re
    # modules imported by this block: `import X`, `import X, Y`, `from X import ...`. Match only
    # to end-of-line (no \s in the class, or it eats the newline into the next statement, e.g.
    # `import sys, yaml\nd = ...` would capture "yaml\nd" and miss the real module name).
    imported = set()
    # `import X`, `import X, Y`, `import X as Z`. Allow `as <alias>` in the clause, then per token
    # take the FIRST whitespace-word before the `as` and its leading dotted component (M1: without
    # this, `import numpy as np` captured the literal "numpy as np" and never matched "numpy" --
    # the canonical aliased form of two listed modules silently went unchecked).
    for m in re.finditer(r"^[ \t]*import[ \t]+([\w.,\t as]+)", script, re.MULTILINE):
        for tok in m.group(1).split(","):
            first = tok.strip().split()[0] if tok.strip().split() else ""  # word before `as`
            if first:
                imported.add(first.split(".")[0])
    for m in re.finditer(r"^[ \t]*from[ \t]+([\w.]+)[ \t]+import\b", script, re.MULTILINE):
        imported.add(m.group(1).split(".")[0])
    needed = [mod for mod in _IMPORT_TO_PIP_PKG if mod in imported]
    if not needed:
        return
    # Check installs JOB-WIDE (all run: scripts of this job concatenated), not just this block.
    # NOTE (m1): this is ORDER-INSENSITIVE -- an install in a LATER step than the import still
    # satisfies the check, though at runtime GitHub runs steps in order and that would fail. This
    # is an accepted trade of the job-scope widening (same-block was too strict; it false-positived
    # publish.yaml's valid install-then-import). Real authoring installs first, so exposure is low.
    job_script = "\n".join(_JOB_SCRIPTS.get((wf, job), [script]))
    # `pip install`, `pip3 install`, `python -m pip install` all count (pip[0-9]* covers pip3).
    _PIP = r"pip[0-9]*\s+install\b"
    # EACH needed module must be NAMED in a pip install (M1, AI review #115): a blanket `-r
    # requirements.txt` pass is NOT sound here -- the repo's requirements files provide only
    # dbldatagen/PyYAML/sqlglot/databricks-sdk/pyspark/pytest, NOT numpy/pandas/requests/markdown/
    # bs4, so `pip install -r requirements.txt` + `import pandas` would green-light the exact
    # ModuleNotFoundError this guard exists to catch. So we always require the package be named
    # explicitly. Match the package as a whole token, so a version pin like `pyyaml>=6.0` still
    # matches on the leading name; `-r <file>` that also names the package on the line still
    # matches. (The repo's real -r jobs do not inline-import any mapped module, so this is not a
    # false-positive today.)
    missing = []
    for mod in needed:
        pkg = _IMPORT_TO_PIP_PKG[mod]
        named = re.search(rf"{_PIP}[^\n]*(?<![\w-]){re.escape(pkg)}(?![\w-])",
                          job_script, re.IGNORECASE)
        if not named:
            missing.append(f"{mod} (needs `pip install {pkg}`)")
    assert not missing, (
        f"{os.path.basename(wf)} job '{job}' (step '{name}') imports non-stdlib module(s) whose "
        f"pip package is not installed anywhere in the job: {missing}. On a bare runner this dies "
        f"with ModuleNotFoundError -- and on a scheduled workflow it won't show up in PR CI.")
