"""Unit tests for the synthetic-data generator registry (_registry.py).

The registry's topo_sort/select are pure and Spark-free, and after the
generators-v2 refactor they are the SINGLE source of run-order truth (replacing
the old hardcoded databricks.yml task chain). These tests lock in that guarantee:
a future edit to a provides/depends_on set that introduces a cycle or a wrong
order fails here instead of silently at deploy time.
"""
import ast
import os
import sys
from pathlib import Path

import pytest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GENERATORS = os.path.join(REPO, "runtime", "synthetic-data", "generators")
if GENERATORS not in sys.path:
    sys.path.insert(0, GENERATORS)

# Non-generator modules in the generators/ dir (shared layer / orchestrator).
_NON_GENERATOR = {"_common", "_context", "_registry", "generate_all", "__init__"}

from _registry import (  # noqa: E402
    GENERATORS as SPECS,
    GenSpec,
    select,
    generator_domains,
    topo_sort,
    waves,
    _label_to_schema_keys,
    _dir_labels,
)

# The documented run order (README "Generator order matters"). Ties in the DAG
# are broken by declared list order, so topo_sort is fully deterministic.
EXPECTED_ORDER = [
    "customer", "trade_promotion", "supplier_monitoring",
    "inventory", "balancing_margin_and_volume", "customer_ltv", "logistics", "early_risk_detection",
    "equipment", "labor", "predictive_operations",
    # connected_store_signals runs BEFORE commerce_media_networks: the footfall fact
    # moved from CMN to CSS (ADR 0033), so CMN now reads a table CSS writes.
    "connected_store_signals",
    "commerce_media_networks", "data_sharing_with_suppliers",
    "smarter_demand_and_inventory_decisions",
    # interaction depends only on customer/product/store/calendar (all provided early), so it
    # ties last by declared list order.
    "interaction",
    # agentic_commerce depends on customer/product/store/inventory/order (all provided
    # earlier), so it ties after interaction by declared list order.
    "agentic_commerce",
    # ai_assisted_store_associates depends on product/store/inventory (all earlier).
    "ai_assisted_store_associates",
    # unified_customer_view (the CDP activation layer) depends only on customer/marketing,
    # so it ties last by declared list order.
    "unified_customer_view",
]


def _names(specs):
    return [s.name for s in specs]


def test_topo_sort_matches_documented_order():
    assert _names(topo_sort(SPECS)) == EXPECTED_ORDER


def test_topo_sort_respects_every_dependency():
    """Each generator appears after every generator that provides a key it reads."""
    ordered = topo_sort(SPECS)
    pos = {s.name: i for i, s in enumerate(ordered)}
    provider = {k: s.name for s in SPECS for k in s.provides}
    for s in SPECS:
        for dep in s.depends_on:
            if dep in provider:  # external/never-provided keys impose no ordering
                assert pos[provider[dep]] < pos[s.name], (
                    f"{s.name} reads {dep} but runs before its provider {provider[dep]}"
                )


def test_topo_sort_valid_under_input_shuffle():
    """Ties break by input-list order, so the exact sequence is input-dependent,
    but the result is always a VALID topological order (every dependency honored)."""
    ordered = topo_sort(list(reversed(SPECS)))
    pos = {s.name: i for i, s in enumerate(ordered)}
    provider = {k: s.name for s in SPECS for k in s.provides}
    for s in SPECS:
        for dep in s.depends_on:
            if dep in provider:
                assert pos[provider[dep]] < pos[s.name]


def test_topo_sort_detects_cycle():
    cyclic = [
        GenSpec("a", frozenset({"ka"}), frozenset({"kb"})),
        GenSpec("b", frozenset({"kb"}), frozenset({"ka"})),
    ]
    with pytest.raises(ValueError, match="cyclic or unsatisfiable"):
        topo_sort(cyclic)


def test_topo_sort_detects_duplicate_provides():
    """Two generators providing the same schema key make ordering ambiguous."""
    dup = [
        GenSpec("a", frozenset({"shared"})),
        GenSpec("b", frozenset({"shared"})),
    ]
    with pytest.raises(ValueError, match="exactly one provider"):
        topo_sort(dup)


def test_waves_concatenate_to_a_valid_topological_order():
    """generate_all runs generators wave-by-wave (Kahn levels) concurrently. Concatenating
    the waves in order must yield a valid topological order (cross-check vs topo_sort's
    contract): every generator appears exactly once, and no generator precedes a provider
    of a schema it depends on."""
    levels = waves(SPECS)
    flat = [s.name for w in levels for s in w]
    assert sorted(flat) == sorted(s.name for s in SPECS)          # every gen once, no dupes
    provider = {k: s.name for s in SPECS for k in s.provides}
    pos = {n: i for i, n in enumerate(flat)}
    for s in SPECS:
        for dep in s.depends_on:
            if dep in provider:                                   # provided-here dep
                assert pos[provider[dep]] < pos[s.name], \
                    f"{s.name} must come after its provider of {dep}"


def test_waves_put_no_intra_wave_dependency_together():
    """Two generators in the SAME wave must not depend on each other's provided keys
    (that is the whole point of a level: they can run concurrently)."""
    levels = waves(SPECS)
    provider = {k: s.name for s in SPECS for k in s.provides}
    for wave in levels:
        names = {s.name for s in wave}
        for s in wave:
            deps_in_wave = {provider.get(d) for d in s.depends_on} & names
            assert not deps_in_wave, \
                f"{s.name} shares a wave with its provider(s) {deps_in_wave}"


def test_waves_first_level_has_no_provided_dependencies():
    """Level 0 = generators whose depends_on are satisfied by nothing or by a
    never-provided (pre-existing) key -- they can start immediately."""
    provider = {k: s.name for s in SPECS for k in s.provides}
    level0 = waves(SPECS)[0]
    for s in level0:
        assert all(d not in provider for d in s.depends_on), \
            f"{s.name} is in wave 0 but depends on a provided key"
    assert any(s.name == "customer" for s in level0)              # customer has no deps


def test_waves_detect_cycle_and_duplicate_provider():
    """waves raises the SAME errors as topo_sort on a cyclic or duplicate-provider graph."""
    cyc = [GenSpec("a", frozenset({"x"}), frozenset({"y"})),
           GenSpec("b", frozenset({"y"}), frozenset({"x"}))]
    with pytest.raises(ValueError):
        waves(cyc)
    dup = [GenSpec("a", frozenset({"s"})), GenSpec("b", frozenset({"s"}))]
    with pytest.raises(ValueError, match="exactly one provider"):
        waves(dup)


def test_select_empty_returns_all():
    assert _names(select(SPECS, "")) == _names(SPECS)


def test_select_pulls_transitive_upstream_by_generator_name():
    # logistics reads supplier(->supplier_monitoring) + product/store(->trade_promotion),
    # and supplier_monitoring reads product/store/calendar(->trade_promotion).
    got = set(_names(select(SPECS, "logistics")))
    assert got == {"logistics", "supplier_monitoring", "trade_promotion"}


def test_select_by_schema_key():
    # "order" is provided by customer_ltv. Its ACU Market Analysis helper also reads
    # BMV competitor identity, whose provider reads inventory, so both prerequisites
    # are part of the transitive closure.
    got = set(_names(select(SPECS, "order")))
    assert got == {
        "customer_ltv", "customer", "trade_promotion",
        "balancing_margin_and_volume", "inventory",
    }


def test_select_result_preserves_topo_order():
    sub = select(SPECS, "early_risk_detection")
    names = _names(sub)
    assert names == [n for n in EXPECTED_ORDER if n in set(names)]
    # early_risk_detection -> logistics -> {supplier_monitoring, trade_promotion}, PLUS inventory
    # (ERD's gold reads inventory_position -- gold-read expansion pulls in its generator).
    assert set(names) == {
        "early_risk_detection", "logistics", "supplier_monitoring", "trade_promotion", "inventory",
    }


def test_select_unknown_token_errors():
    with pytest.raises(ValueError, match="matched no domain/package"):
        select(SPECS, "does_not_exist")


def test_select_by_directory_label_resolves_to_schema_key(monkeypatch):
    """AI review #108 H1: the lean gate passes a changed DIRECTORY label (e.g.
    `actionable-customer-understanding`), whose slug is neither a generator name nor a
    provides key. select() must resolve it via the dir-label -> schema-key map so the
    right generators run. Hyphen/underscore agnostic."""
    got_hyphen = set(_names(select(SPECS, "actionable-customer-understanding")))
    got_under = set(_names(select(SPECS, "actionable_customer_understanding")))
    # acu's schema key is provided by customer_ltv (provides {order,payment,acu}); its
    # transitive upstream pulls in customer + trade_promotion.
    assert "customer_ltv" in got_hyphen
    assert got_hyphen == got_under                    # hyphen == underscore
    # resolving the schema key directly gives the same set (label -> key -> generator).
    assert got_hyphen == set(_names(select(SPECS, "acu")))


def test_select_unified_customer_view_includes_generator_and_gold_inputs():
    """unified-customer-view ships a generator (ucv: activation_destination, activation_job,
    campaign_touch) and its GOLD reads customer/acu/marketing, so selecting the package must
    pick the writer AND the generators that populate those gold inputs -- otherwise UCV's gold
    + DQ run against empty tables (the 'vacuous green' the gate warns about; AI review #108 H1
    is why a package label must never hard-fail the lean gate)."""
    got = set(_names(select(SPECS, "unified-customer-view")))
    assert "unified_customer_view" in got
    assert {"customer", "customer_ltv", "trade_promotion"} <= got
    assert any("ucv" in s.provides for s in SPECS)


def test_select_ai_assisted_store_associates_includes_generator_and_upstreams():
    """AI-Assisted Store Associates now ships a generator (aasa) plus gold that reads
    inventory/product/store/promo/marketing/equipment — selection must cover the writer
    and its upstreams / gold-read expansion."""
    got = set(_names(select(SPECS, "ai-assisted-store-associates")))
    assert "ai_assisted_store_associates" in got
    assert {"inventory", "trade_promotion"} & got  # product/store come via trade_promotion
    assert any("aasa" in s.provides for s in SPECS)


def test_select_genuine_typo_still_raises_beside_a_real_no_generator_label():
    """A token matching no domain/package at all is still a hard error, even next to a
    real-but-generatorless label -- so a typo never silently green-skips."""
    with pytest.raises(ValueError):
        select(SPECS, "unified-customer-view,does_not_exist")


def test_label_to_schema_keys_inverts_the_schema_defaults_map():
    """_label_to_schema_keys maps a directory slug -> the schema KEY the registry indexes on
    (the inverse of ordm_config.schema_defaults). Underscored, and it must at least carry the
    non-trivial package renames the H1 fix depends on."""
    l2k = _label_to_schema_keys()
    assert l2k, "expected a non-empty label->key map (ordm_config importable)"
    # a package whose directory name differs from its schema key must be present.
    assert l2k.get("actionable_customer_understanding") == "acu"
    assert all("-" not in slug for slug in l2k), "keys must be underscore-normalized"


def test_dir_labels_include_core_and_outcome_dirs_underscored():
    """_dir_labels is the ground truth of what a PR can name: every canonical-core and
    outcome-package directory, underscore-normalized (so a planned package with no schema
    var / no generator is still a known, no-op-not-error label)."""
    labels = _dir_labels()
    assert "customer" in labels                                   # a core domain
    assert "unified_customer_view" in labels                      # an outcome pkg
    assert all("-" not in l for l in labels)                      # underscore-normalized


def test_select_unknown_token_not_silently_swallowed_beside_a_valid_one():
    # AI review #43 M1: a valid token must not mask an unknown sibling — the whole
    # subset is rejected so a typo can never quietly run a different set than asked.
    with pytest.raises(ValueError, match="matched no domain/package"):
        select(SPECS, "order,does_not_exist")


# --- registry <-> filesystem consistency (guards the "unregistered generator
# silently never runs under generate_all" footgun the refactor documents) ---

def _modules_defining_run():
    """generators/*.py stems that define a top-level `def run(...)` (AST, no import
    — importing a generator would pull in pyspark)."""
    found = set()
    for f in Path(GENERATORS).glob("*.py"):
        if f.stem in _NON_GENERATOR:
            continue
        tree = ast.parse(f.read_text())
        if any(isinstance(n, ast.FunctionDef) and n.name == "run" for n in tree.body):
            found.add(f.stem)
    return found


def test_every_registered_generator_has_a_run_module():
    """A GenSpec name (or a typo'd one) must map to a module that defines run(ctx)."""
    missing = {s.name for s in SPECS} - _modules_defining_run()
    assert not missing, f"registered generators with no module defining run(ctx): {sorted(missing)}"


def test_every_run_module_is_registered():
    """A generator that defines run(ctx) but isn't in _registry.GENERATORS would pass
    CI yet never execute under generate_all — fail loudly instead."""
    unregistered = _modules_defining_run() - {s.name for s in SPECS}
    assert not unregistered, (
        "generator module(s) define run(ctx) but are absent from _registry.py GENERATORS, "
        f"so generate_all will never run them: {sorted(unregistered)}")


def _accessed_schema_keys(module_stem):
    """Schema keys a generator references by STRING LITERAL, via either access style
    the generators use: `ctx.schemas["k"]` / `schemas["k"]` subscripts, and
    `fq("k", <table>)` calls (both the shared `DeployContext.fq` and the per-generator
    `generate()` `fq(schema_key, table)` closures take the schema key as the first of
    two args — the `>= 2 args` guard skips any single-arg table helper). This is a
    subset check: a key resolved through a variable isn't captured, so it flags an
    *undeclared literal* access, not every conceivable one."""
    src = (Path(GENERATORS) / f"{module_stem}.py").read_text()
    keys = set()
    for node in ast.walk(ast.parse(src)):
        if isinstance(node, ast.Subscript):
            v = node.value
            if (isinstance(v, ast.Attribute) and v.attr == "schemas") or (
                isinstance(v, ast.Name) and v.id == "schemas"
            ):
                s = node.slice
                if isinstance(s, ast.Constant) and isinstance(s.value, str):
                    keys.add(s.value)
        elif isinstance(node, ast.Call):
            f = node.func
            is_fq = (isinstance(f, ast.Attribute) and f.attr == "fq") or (
                isinstance(f, ast.Name) and f.id == "fq"
            )
            if is_fq and len(node.args) >= 2 and isinstance(node.args[0], ast.Constant) \
                    and isinstance(node.args[0].value, str):
                keys.add(node.args[0].value)
    return keys


@pytest.mark.parametrize("spec", SPECS, ids=[s.name for s in SPECS])
def test_generator_schema_access_is_declared(spec):
    """reads/writes ⊆ declared: every schema key a generator references by literal is
    in its GenSpec provides∪depends_on, so the registry's declared ordering actually
    reflects the generator's real I/O — not just an unenforced claim (AI review #43 M1)."""
    declared = set(spec.provides) | set(spec.depends_on)
    undeclared = _accessed_schema_keys(spec.name) - declared
    assert not undeclared, (
        f"{spec.name} references schema key(s) {sorted(undeclared)} not in its registry "
        f"provides/depends_on {sorted(declared)} — update _registry.py (or the generator)")


# ---- generator_domains: the lean gate's DDL-domain expansion ------------------------------

def test_generator_domains_includes_every_selected_generators_package():
    """The daily-deploy / lean-gate bug: generate_all --include early-risk-detection pulls in
    trade_promotion as an upstream data provider (it provides the core product/store keys ERD
    depends on), and trade_promotion ALSO writes promote_with_purpose.promotion_scope. A narrow
    apply --domains early-risk-detection never created that table -> TABLE_OR_VIEW_NOT_FOUND.
    generator_domains must therefore include promote-with-purpose (and the other core domains
    those generators write) so apply creates exactly what generate_all populates."""
    labels = generator_domains(SPECS, "early-risk-detection")
    assert "promote-with-purpose" in labels, "the trade_promotion package must be in the DDL set"
    assert "early-risk-detection" in labels     # the requested package itself
    # core domains the selected generators write are present (product/store/transaction/...).
    assert {"product", "store", "transaction", "logistics", "supplier"} <= labels


def test_generator_domains_uses_real_dir_labels_not_schema_slugs():
    """The returned labels are on-disk DIRECTORY names (what apply --domains matches via
    _domain_of), so the order/orders slug quirk resolves to the real `order` dir and every
    label is a directory that exists."""
    import glob
    import os
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dirs = {os.path.basename(p) for root in ("canonical-core", "outcome-packages")
            for p in glob.glob(os.path.join(here, root, "*")) if os.path.isdir(p)}
    labels = generator_domains(SPECS, "")           # empty => all generators
    assert labels <= dirs, f"non-dir labels leaked: {sorted(labels - dirs)}"
    # the empty (all) selection writes to product/store and the order domain (slug 'orders')
    assert {"product", "store", "order"} <= labels


def test_generator_domains_empty_selection_covers_all_writer_packages():
    """Empty include => every generator selected => the union of all their provides labels."""
    all_labels = generator_domains(SPECS, "")
    assert "unified-customer-view" in all_labels         # ships the ucv generator
    assert "ai-assisted-store-associates" in all_labels  # ships aasa generator
    assert len(all_labels) >= 20                          # the writer packages/domains


# ---- select() covers generators for a package's GOLD-layer cross-domain reads --------------

def test_select_pulls_generators_for_gold_layer_cross_domain_reads():
    """early-risk-detection's GOLD (gold_inventory_risk, gold_control_tower) reads
    ${inventory_schema}.inventory_position, but the ERD generator's depends_on is only
    {logistics, product}. Without gold-read expansion, --include early-risk-detection never ran
    the inventory generator, so inventory_position was EMPTY and freshness_all_feeds_present
    FAILed. select() must now pull in the inventory generator."""
    names = {s.name for s in select(SPECS, "early-risk-detection")}
    assert "inventory" in names, "the inventory generator must be selected for ERD's gold reads"
    assert "early_risk_detection" in names          # the package's own generator still selected


def test_gold_read_expansion_works_for_every_token_form():
    """The gold-read expansion fires whether the package is named by its DIR label, its schema
    KEY, or its GENERATOR name -- all three resolve to the same package and pull inventory in."""
    for token in ("early-risk-detection", "risk", "early_risk_detection"):
        names = {s.name for s in select(SPECS, token)}
        assert "inventory" in names, f"inventory not selected for token {token!r}"


def test_gold_read_expansion_does_not_broaden_a_core_only_request():
    """A canonical-core domain whose gold does not read other domains stays narrow -- the
    expansion only adds generators for tables a requested package's gold actually reads."""
    assert {s.name for s in select(SPECS, "customer")} == {"customer"}


def test_every_outcome_package_gold_reads_are_satisfied_by_selection():
    """Systemic guard (maintainer chose 'derive gen deps from gold reads'): for EVERY outcome
    package, the generators select() returns must PROVIDE every schema key that package's gold
    reads (and that any generator produces) -- so no package's gold/DQ ever runs against an
    empty cross-domain table in the lean gate. Fails loudly if a future package's gold reads a
    table no selected generator populates."""
    from _registry import _gold_read_schema_keys
    import glob
    import os
    prov_map = {k: s.name for s in SPECS for k in s.provides}
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    pkgs = [os.path.basename(p) for p in glob.glob(os.path.join(here, "outcome-packages", "*"))
            if os.path.isdir(p)]
    gaps = {}
    for pkg in pkgs:
        provided = set()
        for s in select(SPECS, pkg):
            provided |= set(s.provides)
        reads = _gold_read_schema_keys({pkg.replace("-", "_")})
        gap = {k for k in reads if k in prov_map and k not in provided}
        if gap:
            gaps[pkg] = sorted(gap)
    assert not gaps, f"packages whose gold reads an unpopulated table: {gaps}"
