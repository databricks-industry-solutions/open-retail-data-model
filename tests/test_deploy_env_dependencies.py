"""Guard: every third-party module a deploy task's entry script imports (transitively, including
lazy in-function imports) must be declared in that job's databricks.yml environment `dependencies`.

Why this exists: the daily deploy failed on `ModuleNotFoundError: No module named 'sqlglot'` in the
reconcile_schema task -- apply_model_ddl.py imports sqlglot lazily in _normalize_view_body (the
MV-definition reconcile path), but the job's serverless environment spec only listed pyyaml /
dbldatagen / databricks-sdk. It never surfaced in PR CI because the deploy runs on a SCHEDULE, and
the import is lazy so a shallow scan misses it. This is the same class as the earlier pyyaml gap.
Rather than chase these one runtime failure at a time, assert the invariant statically.

Cluster-free: parses YAML + walks the committed source with `ast`, no Spark / workspace.
"""
import ast
import glob
import os
import re
import sys

import pytest

yaml = pytest.importorskip("yaml")

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATABRICKS_YML = os.path.join(REPO, "databricks.yml")

# Modules provided by the Databricks serverless runtime itself (not a pip dependency the job must
# declare). pyspark + its friends are ambient on the cluster; the stdlib is always present.
_RUNTIME_PROVIDED = {"pyspark", "dbutils", "delta"}

# import-module -> the pip package name to look for in the env `dependencies` list. Only
# third-party modules the deploy scripts actually import need an entry.
_IMPORT_TO_PIP_PKG = {
    "yaml": "pyyaml",
    "sqlglot": "sqlglot",
    "dbldatagen": "dbldatagen",
    "databricks": "databricks-sdk",
}

# Deploy entry scripts are DERIVED from databricks.yml (every spark_python_task.python_file that
# resolves to a committed .py), not a hardcoded list -- see _job_environments (M1). The transitive
# local import graph of each is walked from there.


def _is_stdlib(mod):
    return mod in getattr(sys, "stdlib_module_names", set())


def _local_module_path(mod, from_file):
    """Resolve a LOCAL import (tools.x, _registry, ordm_config, ...) to a committed .py file, or
    None if it is third-party/stdlib. Resolves against the roots the deploy scripts actually put
    on sys.path at runtime: the repo root (for `tools.x` / `tools/x/__init__`), the sibling dir of
    the importing file (generators import `_registry` as a sibling), AND `tools/` +
    `runtime/synthetic-data/generators/` (apply_model_ddl/_context add these, so a BARE `import ordm_config`
    / `import _registry` resolves to tools/ordm_config.py / the generators dir)."""
    rel = mod.replace(".", os.sep)
    top = mod.split(".")[0]
    sys_path_roots = (REPO,
                      os.path.join(REPO, "tools"),
                      os.path.join(REPO, "runtime", "synthetic-data", "generators"),
                      os.path.dirname(from_file))
    candidates = [os.path.join(REPO, rel + ".py"),
                  os.path.join(REPO, rel, "__init__.py")]
    for root in sys_path_roots:
        candidates.append(os.path.join(root, top + ".py"))
        candidates.append(os.path.join(root, top, "__init__.py"))
    for c in candidates:
        if os.path.isfile(c):
            return c
    return None


def _imports_and_local_edges(path):
    """Return (third_party_top_modules, local_module_names) imported ANYWHERE in `path` --
    module level OR inside a function (ast.walk covers both, so a lazy `import sqlglot` counts)."""
    third_party, local = set(), set()
    with open(path) as fh:
        tree = ast.parse(fh.read())
    for node in ast.walk(tree):
        names = []
        if isinstance(node, ast.Import):
            names = [a.name for a in node.names]
        elif isinstance(node, ast.ImportFrom):
            if node.level:            # relative import -> local
                if node.module:
                    local.add(node.module.split(".")[0])      # from .pkg import x
                else:
                    # `from . import foo, bar` -> foo/bar are sibling MODULES; traverse into them
                    # (m1: previously dropped, a real hole in a transitivity guard).
                    for a in node.names:
                        local.add(a.name.split(".")[0])
                continue
            names = [node.module] if node.module else []
        for name in names:
            top = name.split(".")[0]
            # Classify purely by whether the import resolves to a COMMITTED file in this repo
            # (M1: no hardcoded local-name allowlist to silently misfile a future dep/module).
            # _local_module_path checks the package path AND the sibling-of-importer path, so
            # `tools.x`, a sibling `_registry`, etc. all resolve; anything that doesn't and isn't
            # stdlib is a third-party pip dependency the job must declare.
            if _local_module_path(name, path):
                local.add(name)
            elif not _is_stdlib(top):
                third_party.add(top)
    return third_party, local


def _dynamic_import_seeds(entry_rel):
    """Extra module files reached by DYNAMIC import that the AST walk can't follow (H1).
    generate_all.py loads each generator via `importlib.import_module(spec.name)`, so the
    generator modules (which `import dbldatagen`) are never reached from the static edges. Seed
    the walk with every generator module named in the registry, so their third-party imports are
    actually checked -- otherwise dbldatagen was 'covered' only by luck (hand-listed), and a
    generator importing a NEW undeclared module would slip through."""
    seeds = []
    if os.path.basename(entry_rel) == "generate_all.py":
        gendir = os.path.join(REPO, "runtime", "synthetic-data", "generators")
        sys.path.insert(0, gendir)
        try:
            import importlib
            reg = importlib.import_module("_registry")
            for spec in getattr(reg, "GENERATORS", []):
                p = os.path.join(gendir, spec.name + ".py")
                if os.path.isfile(p):
                    seeds.append(p)
        finally:
            if gendir in sys.path:
                sys.path.remove(gendir)
    return seeds


def _all_third_party_imports(entry_rel):
    """Every third-party top-level module the entry script needs, following its transitive LOCAL
    import graph (so a dep pulled in only via tools.ordm_ddl.parser etc. is still counted), PLUS
    modules reached only by dynamic import (see _dynamic_import_seeds)."""
    entry = os.path.join(REPO, entry_rel)
    seen_files, third_party = set(), set()
    stack = [entry] + _dynamic_import_seeds(entry_rel)
    while stack:
        f = stack.pop()
        if f in seen_files or not os.path.isfile(f):
            continue
        seen_files.add(f)
        tp, local = _imports_and_local_edges(f)
        third_party |= tp
        for mod in local:
            lp = _local_module_path(mod, f)
            if lp:
                stack.append(lp)
    return third_party


def _job_environments():
    """Yield (job_name, entry_scripts_used, declared_pip_packages) for every bundle job that runs
    spark_python_task entry scripts, across all targets. declared = the env `dependencies` list."""
    with open(DATABRICKS_YML) as fh:
        doc = yaml.safe_load(fh)

    def walk(node):
        # jobs can live under resources.jobs (top level) and targets.<t>.resources.jobs
        found = []
        if isinstance(node, dict):
            if "jobs" in node and isinstance(node["jobs"], dict):
                for jid, job in node["jobs"].items():
                    if isinstance(job, dict) and "tasks" in job:
                        found.append((jid, job))
            for v in node.values():
                found += walk(v)
        elif isinstance(node, list):
            for v in node:
                found += walk(v)
        return found

    seen = set()
    for jid, job in walk(doc):
        key = jid
        if key in seen:
            continue
        seen.add(key)
        # declared deps across the job's environments (usually one, "default"). Keep both the
        # bare package NAMES and the RAW specs (raw specs feed the pin-match check, M2).
        declared, declared_specs = set(), []
        for env in job.get("environments") or []:
            for dep in ((env.get("spec") or {}).get("dependencies") or []):
                declared_specs.append(str(dep))
                # Extract just the leading PEP 508 package name, robust to any spec form:
                # `sqlglot>=30,<31`, `pkg~=1.2`, `pkg!=1.0`, `pkg[extra]`, `pkg @ git+...` all
                # reduce to `pkg` (leading run of name chars before any operator/[/whitespace).
                m = re.match(r"\s*([A-Za-z0-9._-]+)", str(dep))
                if m:
                    declared.add(m.group(1))
        # Entry scripts = EVERY spark_python_task.python_file that resolves to a committed .py
        # (M1: derived from databricks.yml, not a hardcoded allowlist -- so a NEW task with a new
        # entry script is covered automatically instead of silently getting zero import checks).
        entries = set()
        for t in job.get("tasks") or []:
            pf = ((t.get("spark_python_task") or {}).get("python_file") or "").lstrip("./")
            if pf and os.path.isfile(os.path.join(REPO, pf)):
                entries.add(pf)
        if entries:
            yield job.get("name", jid), entries, declared, declared_specs


_JOBS = list(_job_environments())


def test_bundle_jobs_were_discovered():
    """Sanity: we actually found bundle jobs running the deploy entry scripts (guards against a
    silent no-op if databricks.yml structure changes)."""
    assert _JOBS, "no spark_python_task jobs running the deploy entry scripts found in databricks.yml"


@pytest.mark.parametrize("job_name,entries,declared,declared_specs", _JOBS,
                         ids=[j[0] for j in _JOBS])
def test_deploy_task_imports_are_declared_dependencies(job_name, entries, declared, declared_specs):
    """Every third-party module any of the job's entry scripts imports (transitively, incl. lazy
    in-function imports like `import sqlglot`) must map to a declared env dependency -- else the
    task dies at import on the serverless runtime, and only on the schedule (not in PR CI)."""
    missing = []
    for entry in sorted(entries):
        for mod in sorted(_all_third_party_imports(entry)):
            if mod in _RUNTIME_PROVIDED:
                continue
            pkg = _IMPORT_TO_PIP_PKG.get(mod)
            if pkg is None:
                missing.append(f"{entry}: imports '{mod}' -- not in _IMPORT_TO_PIP_PKG; add its "
                               f"pip package name to the map (and to the job's env dependencies)")
            elif pkg not in declared:
                missing.append(f"{entry}: imports '{mod}' -> needs '{pkg}' in job '{job_name}' "
                               f"environment dependencies (have: {sorted(declared)})")
    assert not missing, "deploy task import(s) not declared as env dependencies:\n  " + "\n  ".join(missing)


# The pins the deploy env MUST keep consistent with requirements-dev.txt, because the deploy
# parses/normalizes with these libs and the drift-gated tests validate against the requirements
# pin -- a major-version divergence would parse on a different lib than CI validated (M2). Map:
# env-dependency package name -> the requirements-file package name to compare against.
_PIN_CONSISTENCY = {"sqlglot": "sqlglot"}


def _requirements_spec(pkg):
    """The version spec for `pkg` as declared in requirements-dev.txt / requirements.txt (e.g.
    'sqlglot>=30,<31' -> '>=30,<31'), or None if absent."""
    for fn in ("requirements-dev.txt", "requirements.txt"):
        p = os.path.join(REPO, fn)
        if not os.path.isfile(p):
            continue
        with open(p) as fh:
            for line in fh:
                line = line.split("#", 1)[0].strip()
                m = re.match(rf"{re.escape(pkg)}\s*(.*)$", line, re.IGNORECASE)
                if m and (not m.group(1) or not m.group(1)[0].isalnum()):
                    return m.group(1).strip()
    return None


@pytest.mark.parametrize("job_name,entries,declared,declared_specs", _JOBS,
                         ids=[j[0] for j in _JOBS])
def test_pinned_deps_match_requirements(job_name, entries, declared, declared_specs):
    """Where a comment stakes correctness on the env pin matching requirements-dev.txt (sqlglot
    feeds the drift-gated MV-body normalization), ENFORCE it (M2): the version spec declared in
    databricks.yml must equal the one in the requirements file, so the deploy never parses on a
    different major than CI validated."""
    spec_by_pkg = {}
    for s in declared_specs:
        m = re.match(r"\s*([A-Za-z0-9._-]+)\s*(.*)$", s)
        if m:
            spec_by_pkg[m.group(1).lower()] = m.group(2).strip()
    mismatches = []
    for pkg, req_pkg in _PIN_CONSISTENCY.items():
        if pkg not in declared:
            continue                       # not used by this job; the import test covers presence
        env_spec = spec_by_pkg.get(pkg.lower(), "")
        req_spec = _requirements_spec(req_pkg)
        if req_spec is not None and env_spec != req_spec:
            mismatches.append(f"{pkg}: databricks.yml pins '{env_spec}' but {req_pkg} in "
                              f"requirements is '{req_spec}' -- keep them identical")
    assert not mismatches, ("deploy env pin(s) diverged from requirements:\n  "
                            + "\n  ".join(mismatches))


def test_lean_pr_submit_env_includes_dbldatagen_runtime_deps():
    """The lean per-PR workflow's one-off Databricks job must declare dbldatagen's
    runtime imports explicitly.

    dbldatagen imports numpy/pandas at runtime; they are not declared as package
    dependencies by dbldatagen itself, so relying on ambient cluster images is
    brittle and has caused runtime task failures when images changed.
    """
    wf = os.path.join(REPO, ".github", "workflows", "ordm-lean-pr-deploy.yml")
    if not os.path.exists(os.path.join(REPO, "tools", "publish", "manifest.yaml")):
        pytest.skip("public tree: ordm-lean-pr-deploy.yml is staging-only")
    text = open(wf).read()
    m = re.search(r"^\s*spec\s*=\s*(\{.*\})\s*$", text, re.MULTILINE)
    assert m, "could not find inline Databricks job environment spec in ordm-lean-pr-deploy.yml"
    spec = ast.literal_eval(m.group(1))
    deps = set(spec.get("dependencies") or [])
    missing = {"numpy", "pandas"} - deps
    assert not missing, (
        "lean per-PR Databricks environment is missing dbldatagen runtime dependencies: "
        + ", ".join(sorted(missing))
    )


def test_lean_pr_diff_base_fetch_is_not_shallow():
    """The lean PR domain-diff step must keep full history for merge-base computation.

    `git diff origin/$BASE_REF...HEAD` requires a merge base; a depth-limited fetch of the base
    branch can omit it and fail with `no merge base`.
    """
    wf = os.path.join(REPO, ".github", "workflows", "ordm-lean-pr-deploy.yml")
    if not os.path.exists(os.path.join(REPO, "tools", "publish", "manifest.yaml")):
        pytest.skip("public tree: ordm-lean-pr-deploy.yml is staging-only")
    text = open(wf).read()
    m = re.search(r"^\s*git fetch origin \"\$BASE_REF\"([^\n]*)$", text, re.MULTILINE)
    assert m, "could not find BASE_REF fetch command in ordm-lean-pr-deploy.yml"
    assert "--depth" not in m.group(1), (
        "BASE_REF fetch must not be shallow; depth-limited fetch can break "
        "`origin/$BASE_REF...HEAD` with `no merge base`"
    )


def _lean_sync_paths():
    """The PATHS array tools/sync_workspace_bundle.sh uploads for the lean per-PR job."""
    sh = open(os.path.join(REPO, "tools", "sync_workspace_bundle.sh")).read()
    m = re.search(r"^PATHS=\((.*?)\)", sh, re.MULTILINE | re.DOTALL)
    assert m, "could not find the PATHS=(...) array in tools/sync_workspace_bundle.sh"
    return m.group(1).split()


def _local_file_closure(entry_rel):
    """Every committed .py file the entry script reaches through its transitive LOCAL imports
    (plus the dynamically imported generators), i.e. the python files the remote job needs."""
    entry = os.path.join(REPO, entry_rel)
    seen = set()
    stack = [entry] + _dynamic_import_seeds(entry_rel)
    while stack:
        f = stack.pop()
        if f in seen or not os.path.isfile(f):
            continue
        seen.add(f)
        for mod in _imports_and_local_edges(f)[1]:
            lp = _local_module_path(mod, f)
            if lp:
                stack.append(lp)
    return seen


def test_lean_pr_workspace_sync_covers_the_job_python_files():
    """The lean per-PR job runs from a workspace folder that tools/sync_workspace_bundle.sh fills
    with a FIXED list of paths (not the whole checkout, unlike the daily deploy). If an entry
    script, or anything it imports, lives outside that list, the lean gate fails inside the
    remote job while the daily deploy still passes. Assert every python_file the job spec names,
    and its transitive local imports, is under a synced path.

    Data inputs read by path (the model SQL, examples, standards, databricks.yml) are not derived
    here; the comment above PATHS in the sync script lists them."""
    wf = os.path.join(REPO, ".github", "workflows", "ordm-lean-pr-deploy.yml")
    if not os.path.exists(os.path.join(REPO, "tools", "publish", "manifest.yaml")):
        pytest.skip("public tree: ordm-lean-pr-deploy.yml is staging-only")
    entries = re.findall(r'"python_file":\s*f"\{ws\}/([^"]+)"', open(wf).read())
    assert entries, "could not find any python_file in the lean per-PR job spec"
    paths = [p.rstrip("/") for p in _lean_sync_paths()]
    missing = []
    for entry in entries:
        for f in sorted(_local_file_closure(entry)):
            rel = os.path.relpath(f, REPO)
            if "/diagrams/" in f"/{rel}" or not any(rel == p or rel.startswith(p + "/") for p in paths):
                missing.append(f"{entry} -> {rel}")
    assert not missing, ("lean job python files not uploaded by sync_workspace_bundle.sh "
                         "(add their top-level path to PATHS):\n  " + "\n  ".join(missing))


def test_lean_pr_workspace_sync_includes_the_repo_root_marker_and_data_inputs():
    """Every lean job entry point finds the repo root by walking up to the first directory that
    holds databricks.yml (tools/apply_model_ddl.py, runtime/data-quality/run_checks.py). If the sync drops
    it, every glob resolves against the wrong root and the job can pass vacuously. The bootstrap
    SQL in runtime/examples/deploy-with-dab/ is read by apply_model_ddl. Neither is a python
    import, so the import-closure test above can't see them."""
    paths = {p.rstrip("/") for p in _lean_sync_paths()}
    src = open(os.path.join(REPO, "tools", "apply_model_ddl.py")).read()
    m = re.search(r'^BOOTSTRAP = os\.path\.join\(REPO_ROOT, (.*)\)$', src, re.MULTILINE)
    assert m, "could not find BOOTSTRAP = os.path.join(REPO_ROOT, ...) in tools/apply_model_ddl.py"
    bootstrap_dir = "/".join(re.findall(r'"([^"]+)"', m.group(1))[:-1])
    # runtime/synthetic-data/seeds.yaml is read by path (_common.load_domain_config), not imported;
    # without it the generators fall back to empty seeds and volumes on the workspace.
    seeds = "runtime/synthetic-data/seeds.yaml"
    if not any(seeds == p or seeds.startswith(p + "/") for p in paths):
        missing_seeds = {seeds}
    else:
        missing_seeds = set()
    missing = ({"databricks.yml", bootstrap_dir} - paths) | missing_seeds
    assert not missing, ("tools/sync_workspace_bundle.sh PATHS must include: "
                         + ", ".join(sorted(missing)))
