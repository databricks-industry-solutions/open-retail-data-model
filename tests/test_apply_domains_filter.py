"""Pin the deploy DDL applier's `--domains` subset filter (design/57 §5d item 4).

A lean per-PR CI deploys ONLY the domains a PR changed (targeting 3-5 min instead of the
full ~13 min). apply()/_phases grew a `domains` param (comma-separated, default empty =
ALL = today's behaviour). The semantics under test:

  1. `domains="customer"` narrows discovery to the customer core domain (+ the always-on
     schema bootstrap) and nothing else.
  2. Requesting an OUTCOME PACKAGE (e.g. "unified-customer-view") auto-includes ALL of
     canonical-core, because outcome packages depend on core (gold reads core tables,
     relationships FK to core). Coarse but safe: core is the shared foundation.
  3. No `--domains` (None or "") is byte-identical to today -- the full phase set.
  4. The schema bootstrap is ALWAYS present regardless of the filter.

Imports mirror tests/test_apply_model_ddl.py: the pure functions (_phases, apply) run with
no pyspark on the dry-run path; conftest.py puts the repo root on sys.path.
"""
import os

from tools.apply_model_ddl import (
    REPO_ROOT,
    _domain_of,
    _effective_domain_filter,
    _phases,
    apply,
)


def _labels_and_domains(domains):
    """Run _phases with a filter and return (set-of-phase-labels, set-of-domain-labels)
    over the paths it yields. `schemas`/bootstrap has no domain (None), so its domain is
    dropped from the domain set but its 'schemas' label is kept."""
    labels, doms = set(), set()
    for label, path, _stmts in _phases("retail_prod", {}, domains=domains):
        labels.add(label)
        d = _domain_of(path)
        if d is not None:
            doms.add(d)
    return labels, doms


def _core_domains():
    return {os.path.basename(p)
            for p in __import__("glob").glob(os.path.join(REPO_ROOT, "canonical-core", "*"))
            if os.path.isdir(p)}


# --- 1. A single core domain narrows discovery to just that domain + schemas ----------

def test_apply_dry_run_single_domain_returns_applied_and_only_that_domain():
    """apply(dry_run, domains='customer') applies >0 and, via _phases, only customer +
    schemas paths are present (no other core domain, no outcome package)."""
    applied, skipped = apply(spark=None, catalog="retail_prod", dry_run=True, domains="customer")
    assert applied > 0 and skipped == 0

    labels, doms = _labels_and_domains("customer")
    assert "schemas" in labels          # bootstrap always present
    assert doms == {"customer"}, doms   # ONLY the customer domain, nothing else


def test_single_core_domain_yields_fewer_statements_than_all():
    """A single-domain filter must apply strictly fewer statements than the unfiltered run
    (the whole point of the lean gate)."""
    all_applied, _ = apply(spark=None, catalog="retail_prod", dry_run=True, domains=None)
    one_applied, _ = apply(spark=None, catalog="retail_prod", dry_run=True, domains="customer")
    assert 0 < one_applied < all_applied


# --- 2. An outcome package auto-includes ALL canonical-core (dependency caveat) --------

def test_outcome_package_includes_all_canonical_core():
    """Requesting an outcome package pulls in ALL canonical-core labels too, because gold
    views read core tables and package relationships FK to core."""
    labels, doms = _labels_and_domains("unified-customer-view")
    assert "unified-customer-view" in doms          # the requested package itself
    assert "customer" in doms                        # a specific core domain is present
    assert _core_domains().issubset(doms), doms      # ALL core domains included
    # and it did not silently pull in a SIBLING outcome package
    assert "agentic-commerce" not in doms


def test_effective_filter_core_only_stays_narrow():
    """A request naming only core domains stays narrow: just those, no outcome packages,
    no auto-expansion to all core."""
    eff = _effective_domain_filter("customer,order")
    assert eff == {"customer", "order"}
    # an outcome package in the request DOES expand to include all core
    eff2 = _effective_domain_filter("unified-customer-view")
    assert "unified-customer-view" in eff2
    assert _core_domains().issubset(eff2)


# --- 3. No filter == today's full phase set -------------------------------------------

def test_no_domains_matches_full_phase_set():
    """No --domains (None and "") yields exactly the same (label, path) set as today's
    unfiltered discovery -- byte-identical backward-compatible default."""
    baseline = [(lbl, path) for lbl, path, _ in _phases("retail_prod", {})]
    for empty in (None, ""):
        filtered = [(lbl, path) for lbl, path, _ in _phases("retail_prod", {}, domains=empty)]
        assert filtered == baseline, f"domains={empty!r} changed the full phase set"
    assert _effective_domain_filter(None) is None
    assert _effective_domain_filter("") is None
    assert _effective_domain_filter("  ,  ") is None  # only-separators == no filter


def test_apply_dry_run_no_domains_same_count_as_default():
    """apply() dry-run count with domains=None equals the default-arg call (no regression)."""
    default_applied, _ = apply(spark=None, catalog="retail_prod", dry_run=True)
    none_applied, _ = apply(spark=None, catalog="retail_prod", dry_run=True, domains=None)
    assert default_applied == none_applied


# --- 4. Bootstrap/schemas always present regardless of the filter ---------------------

def test_schemas_bootstrap_always_present_under_any_filter():
    """The schema bootstrap ('schemas' phase) is yielded for every filter, including one
    that matches NO real domain, so downstream DDL always has its schemas."""
    for domains in (None, "", "customer", "unified-customer-view", "does-not-exist"):
        labels, _ = _labels_and_domains(domains)
        assert "schemas" in labels, f"schemas missing for domains={domains!r}"


def test_domain_of_extracts_root_label_for_flat_and_nested_paths():
    """_domain_of anchors on the dir under canonical-core/outcome-packages regardless of
    depth: nested tables/gold files AND flat relationships/comments all map to the domain,
    and the bootstrap (under neither root) maps to None so it is never filtered."""
    assert _domain_of(os.path.join(REPO_ROOT, "canonical-core", "customer", "tables", "account.sql")) == "customer"
    assert _domain_of(os.path.join(REPO_ROOT, "canonical-core", "customer", "relationships.sql")) == "customer"
    assert _domain_of(os.path.join(REPO_ROOT, "canonical-core", "customer", "comments.sql")) == "customer"
    assert _domain_of(os.path.join(REPO_ROOT, "outcome-packages", "unified-customer-view", "gold", "g.sql")) == "unified-customer-view"
    assert _domain_of(os.path.join(REPO_ROOT, "runtime", "examples", "deploy-with-dab", "00_bootstrap_schemas.sql")) is None


# ---- DeployConfig seam (design/58): value object + single construction point ----

def test_deployconfig_from_params(monkeypatch):
    """DeployConfig.from_params resolves the deploy knobs via get_param (widget->env->flag),
    the single construction point a future Deployer / pip-package driver builds from."""
    from tools.apply_model_ddl import DeployConfig
    monkeypatch.setattr(
        "sys.argv",
        ["prog", "--catalog", "ordm_cicd", "--max_workers", "24",
         "--demote-materialized", "--domains", "customer,marketing"],
    )
    c = DeployConfig.from_params()
    assert c.catalog == "ordm_cicd"
    assert c.max_workers == 24
    assert c.demote_materialized is True
    assert c.domains == "customer,marketing"
    assert c.dry_run is False
    assert c.warehouse is None  # not provided -> None, not ""
    assert c.refresh_gold_tables is False
    assert c.refresh_materialized is False  # absent -> default off


def test_deployconfig_parses_refresh_materialized_flag(monkeypatch):
    """--refresh_materialized (AI review #108 H1, Approach B) parses as a bare boolean, and
    stays off by default so the ordinary apply path is unchanged."""
    from tools.apply_model_ddl import DeployConfig
    monkeypatch.setattr(
        "sys.argv",
        ["prog", "--catalog", "open_retail_data_model_catalog",
         "--warehouse", "wh-1", "--refresh_materialized"],
    )
    c = DeployConfig.from_params()
    assert c.refresh_materialized is True
    assert c.warehouse == "wh-1"
    # default off when the flag is absent
    monkeypatch.setattr("sys.argv", ["prog", "--catalog", "c"])
    assert DeployConfig.from_params().refresh_materialized is False


def test_deployconfig_parses_refresh_gold_tables_flag(monkeypatch):
    from tools.apply_model_ddl import DeployConfig
    monkeypatch.setattr(
        "sys.argv",
        ["prog", "--catalog", "ordm_cicd", "--warehouse", "wh-1", "--refresh_gold_tables"],
    )
    config = DeployConfig.from_params()
    assert config.refresh_gold_tables is True
    monkeypatch.setattr("sys.argv", ["prog", "--catalog", "c"])
    assert DeployConfig.from_params().refresh_gold_tables is False


def test_deployconfig_parses_reconcile_and_recreate_flags(monkeypatch):
    """--reconcile_schema (daily table-drift fix) and --recreate (admin clean-reinstall) both
    parse as bare booleans and default OFF, so neither the daily default nor the ordinary apply
    path silently gains destructive behavior (AI review #108 table-drift)."""
    from tools.apply_model_ddl import DeployConfig
    monkeypatch.setattr(
        "sys.argv",
        ["prog", "--catalog", "open_retail_data_model_catalog", "--warehouse", "wh-1",
         "--reconcile_schema"],
    )
    c = DeployConfig.from_params()
    assert c.reconcile_schema is True and c.recreate is False
    monkeypatch.setattr(
        "sys.argv",
        ["prog", "--catalog", "c", "--warehouse", "wh-1", "--recreate"],
    )
    c = DeployConfig.from_params()
    assert c.recreate is True and c.reconcile_schema is False
    # both OFF by default (a bare apply is never destructive)
    monkeypatch.setattr("sys.argv", ["prog", "--catalog", "c"])
    c = DeployConfig.from_params()
    assert c.reconcile_schema is False and c.recreate is False


def test_deployconfig_parses_reconcile_materialized_flag(monkeypatch):
    """--reconcile_materialized (AI review #108 M2, MV-definition drift) parses as a bare boolean,
    defaults OFF, and is independent of --reconcile_schema so the serving job can request both."""
    from tools.apply_model_ddl import DeployConfig
    monkeypatch.setattr(
        "sys.argv",
        ["prog", "--catalog", "open_retail_data_model_catalog", "--warehouse", "wh-1",
         "--reconcile_schema", "--reconcile_materialized"],
    )
    c = DeployConfig.from_params()
    assert c.reconcile_schema is True and c.reconcile_materialized is True
    # OFF by default, and independent of --reconcile_schema
    monkeypatch.setattr("sys.argv", ["prog", "--catalog", "c", "--warehouse", "w", "--reconcile_schema"])
    c = DeployConfig.from_params()
    assert c.reconcile_schema is True and c.reconcile_materialized is False


def test_reconcile_materialized_without_reconcile_schema_errors(monkeypatch):
    """AI review #108 M1: a standalone --reconcile_materialized (no --reconcile_schema) must FAIL
    LOUDLY, not silently fall through to a full apply() with the flag discarded. Run under
    --dry_run so main()'s dispatch is reached without a live Spark/warehouse."""
    import pytest
    from tools.apply_model_ddl import main
    monkeypatch.setattr(
        "sys.argv",
        ["prog", "--catalog", "c", "--reconcile_materialized", "--dry_run"],
    )
    with pytest.raises(ValueError, match="must be combined with --reconcile_schema"):
        main()


def test_deployconfig_is_frozen():
    """It is a struct, not mutable state to pass around ad hoc (design/58: no scope creep)."""
    import dataclasses
    import pytest
    from tools.apply_model_ddl import DeployConfig
    c = DeployConfig(catalog="c")
    with pytest.raises(dataclasses.FrozenInstanceError):
        c.catalog = "other"


def test_domains_filter_pulls_in_sibling_packages_gold_deps():
    """M1 (AI review): a package whose gold reads a SIBLING package's gold (e.g.
    predictive-operations reads bmv/equipment/inventory/risk) must transitively include those
    siblings under its own --domains, or the gold fixpoint hits missing deps and hard-fails."""
    from tools.apply_model_ddl import _effective_domain_filter
    f = _effective_domain_filter("predictive-operations")
    assert "predictive-operations" in f
    # sibling OUTCOME PACKAGES its gold references are pulled in transitively
    assert {"balancing-margin-and-volume", "early-risk-detection"} <= f
    # canonical-core is always in for any outcome package
    assert {"equipment", "inventory"} <= f
    # a core-only request stays narrow (no package pull-in)
    core_only = _effective_domain_filter("customer")
    assert core_only == {"customer"}


# ---- --single_schema: collapse all domains into one pr_<N> database (design/59) ----

def test_single_schema_overrides_collapses_every_token():
    """single_schema_overrides(name) maps EVERY schema token to `name`, so a per-PR gate
    deploys a PR's domains into one isolated pr_<N> schema instead of 23 per-domain ones.
    Empty name -> no override (today's per-domain behaviour)."""
    from tools.ordm_config import single_schema_overrides, schema_defaults
    o = single_schema_overrides("pr_123")
    assert set(o) == set(schema_defaults())       # every token present
    assert set(o.values()) == {"pr_123"}          # all point at the one schema
    assert single_schema_overrides("") == {}
    assert single_schema_overrides(None) == {}


def test_single_schema_resolves_all_objects_into_one_schema():
    """Under --single_schema, _phases resolves every object (and the schema bootstrap) into
    the single schema -- so CREATE targets and the bootstrap CREATE SCHEMA all name pr_123."""
    import re
    from tools.ordm_config import single_schema_overrides
    ov = single_schema_overrides("pr_123")
    schema_targets, saw_table = set(), False
    for label, path, stmts in _phases("ordm_cicd", ov):
        for s in stmts:
            for m in re.finditer(r"ordm_cicd\.(\w+)\.", s):
                schema_targets.add(m.group(1))
            if label == "schemas":
                mm = re.search(r"CREATE SCHEMA IF NOT EXISTS ordm_cicd\.(\w+)", s)
                if mm:
                    schema_targets.add(mm.group(1))
            if "CREATE TABLE" in s:
                saw_table = True
    assert saw_table
    # every schema referenced anywhere is the single pr_123 (no per-domain schema leaks)
    assert schema_targets == {"pr_123"}, f"leaked non-pr schemas: {schema_targets - {'pr_123'}}"


def test_no_cross_schema_object_name_collision():
    """M2 (AI review #108): the single-schema (pr_<N>) lean deploy is safe ONLY because no two
    committed objects across different schema tokens share a name -- collapsing all schemas
    into one would otherwise silently overwrite/clash, and only inside the lean gate. Enforce
    that load-bearing invariant: every CREATE TABLE/VIEW target `${catalog}.${<key>_schema}.<obj>`
    across canonical-core/ + outcome-packages/ must have a globally-unique <obj> name.

    Scans tables/, gold/, AND metric-views/ (AI review #108 M1): _phases yields the metric-views
    phase too, and resolve() collapses its ${*_schema} tokens under --single_schema exactly like
    every other object -- and the sibling-package expansion pulls several packages' metric-views
    into ONE pr_<N> (e.g. --domains predictive-operations also deploys bmv/equipment/inventory/
    risk), so a duplicate mv_* name across packages WOULD clash. Omitting this glob left that
    reachable collision class unguarded."""
    import glob
    import re
    obj_re = re.compile(
        r"CREATE\s+(?:OR\s+(?:REPLACE|REFRESH)\s+)?(?:MATERIALIZED\s+)?(?:VIEW|TABLE)"
        r"(?:\s+IF\s+NOT\s+EXISTS)?\s+\$\{catalog\}\.\$\{(\w+_schema)\}\.(\w+)",
        re.IGNORECASE)
    seen = {}          # obj_name -> schema_token that first created it
    collisions = []
    files = (glob.glob(os.path.join(REPO_ROOT, "canonical-core", "*", "tables", "*.sql"))
             + glob.glob(os.path.join(REPO_ROOT, "outcome-packages", "*", "tables", "*.sql"))
             + glob.glob(os.path.join(REPO_ROOT, "outcome-packages", "*", "gold", "*.sql"))
             + glob.glob(os.path.join(REPO_ROOT, "outcome-packages", "*", "metric-views", "*.sql")))
    for f in files:
        with open(f) as fh:
            text = fh.read()
        for token, obj in obj_re.findall(text):
            if obj in seen and seen[obj] != token:
                collisions.append(f"{obj}: {seen[obj]} vs {token}")
            seen[obj] = token
    assert not collisions, (
        "cross-schema object-name collision would clash under --single_schema (pr_<N>): "
        + "; ".join(sorted(collisions)))
    assert len(seen) > 100, f"expected the full committed object set, saw {len(seen)}"
    # the metric-views (mv_*) are now in scope, so the guard actually covers that phase
    assert any(o.startswith("mv_") for o in seen), "metric-views not scanned -- glob regressed"


def test_no_cross_schema_constraint_name_collision():
    """M2 (AI review #108, 24ff7cb): Unity Catalog requires CONSTRAINT names unique WITHIN a
    schema. Under --single_schema every domain's pk_/fk_/chk_/unique constraints land in ONE
    pr_<N>, so a duplicate constraint name across two domains would fail `ALTER TABLE ... ADD
    CONSTRAINT` ONLY in the lean gate (never in the per-domain daily deploy) -- a gate-only
    surprise for whichever PR introduces it. Enforce the same global-uniqueness invariant the
    object-name guard does, for named constraints across tables/ + relationships/.

    The regex REQUIRES the constraint kind (PRIMARY KEY | FOREIGN KEY | CHECK | UNIQUE) after the
    name, so it never mis-captures a bare word inside a CHECK expression (e.g. `... IS NOT NULL`)
    as a constraint name -- a loose `CONSTRAINT\\s+\\w+` match does, producing false collisions."""
    import glob
    import re
    con_re = re.compile(
        r"CONSTRAINT\s+(\w+)\s+(?:PRIMARY\s+KEY|FOREIGN\s+KEY|CHECK|UNIQUE)", re.IGNORECASE)
    files = (glob.glob(os.path.join(REPO_ROOT, "canonical-core", "*", "tables", "*.sql"))
             + glob.glob(os.path.join(REPO_ROOT, "outcome-packages", "*", "tables", "*.sql"))
             + glob.glob(os.path.join(REPO_ROOT, "canonical-core", "*", "relationships.sql"))
             + glob.glob(os.path.join(REPO_ROOT, "outcome-packages", "*", "relationships.sql")))
    seen, collisions = {}, []
    for f in files:
        with open(f) as fh:
            text = fh.read()
        rel = os.path.relpath(f, REPO_ROOT)
        for name in con_re.findall(text):
            if name in seen and seen[name] != rel:
                collisions.append(f"{name}: {seen[name]} vs {rel}")
            seen[name] = rel
    assert not collisions, (
        "cross-schema CONSTRAINT-name collision would fail ADD CONSTRAINT under --single_schema "
        "(pr_<N>): " + "; ".join(sorted(collisions)))
    assert len(seen) > 400, f"expected the full committed constraint set, saw {len(seen)}"
