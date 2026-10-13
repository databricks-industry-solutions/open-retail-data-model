"""Unit tests for the generator dependency WAVES (_registry.waves()).

waves() computes Kahn dependency LEVELS so generate_all can run mutually-
independent generators concurrently on one shared SparkSession (design/57, rt04):
level 0 = generators with no unmet dependency, level k = generators whose every
provider lives in a level < k. This is the concurrency contract, so the tests lock
in three invariants that make parallel == serial safe:
  * a generator NEVER shares a wave with a provider of one of its depends_on
    (else a later reader could race an earlier writer);
  * every registered generator appears exactly once across the waves;
  * flattening the waves in order is a VALID topological order (cross-checked
    against the existing topo_sort, the run-order source of truth).
Pure logic, no Spark — imports ONLY _registry (the pyspark-free module), like
test_generators_registry.py, so it runs where pyspark is absent.
"""
import os
import sys

import pytest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GENERATORS = os.path.join(REPO, "runtime", "synthetic-data", "generators")
if GENERATORS not in sys.path:
    sys.path.insert(0, GENERATORS)

from _registry import GENERATORS as SPECS, GenSpec, topo_sort, waves  # noqa: E402


def _flatten(levels):
    return [s for wave in levels for s in wave]


def _provider_map(specs):
    return {k: s.name for s in specs for k in s.provides}


# ---- the real 14-generator registry ----

def test_waves_partition_every_spec_exactly_once():
    """Every registered generator appears exactly once across all waves."""
    flat = [s.name for s in _flatten(waves(SPECS))]
    assert sorted(flat) == sorted(s.name for s in SPECS)
    assert len(flat) == len(set(flat)) == len(SPECS)


def test_no_generator_shares_a_wave_with_a_provider_it_depends_on():
    """The core concurrency-safety property: a generator's providers all live in
    STRICTLY earlier waves, so a same-wave read can never race a same-wave write."""
    levels = waves(SPECS)
    wave_of = {s.name: i for i, wave in enumerate(levels) for s in wave}
    provider = _provider_map(SPECS)
    for s in SPECS:
        for dep in s.depends_on:
            if dep in provider:  # never-provided keys impose no ordering
                assert wave_of[provider[dep]] < wave_of[s.name], (
                    f"{s.name} (wave {wave_of[s.name]}) shares/precedes a wave with its "
                    f"provider {provider[dep]} (wave {wave_of[provider[dep]]}) for dep '{dep}'")


def test_flattened_waves_are_a_valid_topo_order():
    """Concatenating the waves in order yields a valid topological order: every
    generator appears after every provider of a key it reads."""
    flat = _flatten(waves(SPECS))
    pos = {s.name: i for i, s in enumerate(flat)}
    provider = _provider_map(SPECS)
    for s in SPECS:
        for dep in s.depends_on:
            if dep in provider:
                assert pos[provider[dep]] < pos[s.name]


def test_flattened_waves_match_topo_sort_as_a_set_per_prefix():
    """Cross-check against topo_sort: the two agree on a valid order. topo_sort is a
    total order and waves is a level order, so they need not be byte-identical, but
    every wave PREFIX must be a valid topo prefix (a superset closed under deps)."""
    levels = waves(SPECS)
    provider = _provider_map(SPECS)
    seen = set()
    for wave in levels:
        # Before running this wave, every dependency provider is already seen.
        for s in wave:
            for dep in s.depends_on:
                if dep in provider:
                    assert provider[dep] in seen, (
                        f"{s.name} runs in its wave before provider {provider[dep]}")
        seen.update(s.name for s in wave)
    # And the whole set matches topo_sort's set.
    assert seen == {s.name for s in topo_sort(SPECS)}


def test_waves_expected_level_structure_on_real_registry():
    """Lock in the concrete wave shape derived from the current registry, ordered within a
    wave by declared list order (the deterministic tie-break). Two independent
    dependency changes compose here. Market Analysis makes customer_ltv read BMV
    competitor identity, so customer_ltv follows the BMV provider and lands in W4,
    which pushes agentic_commerce (it reads the order schema customer_ltv provides)
    to W5. Separately, labor (Workforce Optimization) depends only on store so it
    joins W2, predictive_operations depends on labor and sits in W3, and
    ai_assisted_store_associates depends on inventory so it also sits in W3, last in
    the wave because it is last in the declared list. unified_customer_view (the CDP
    activation layer) depends only on customer and marketing, so it joins W2, last in the
    wave by declared order. CSS still follows logistics, CMN follows CSS, and DSS follows
    CMN: 19 generators in 6 dependency waves."""
    got = [[s.name for s in wave] for wave in waves(SPECS)]
    assert got == [
        ["customer", "trade_promotion"],
        ["supplier_monitoring", "inventory", "equipment", "labor", "interaction",
         "unified_customer_view"],
        ["balancing_margin_and_volume", "logistics", "predictive_operations",
         "smarter_demand_and_inventory_decisions", "ai_assisted_store_associates"],
        ["customer_ltv", "early_risk_detection", "connected_store_signals"],
        ["commerce_media_networks", "agentic_commerce"],
        ["data_sharing_with_suppliers"],
    ]


def test_waves_deterministic_ties_by_input_list_order():
    """Ties within a wave break by INPUT-list order (same rule as topo_sort), so the
    structure is fully deterministic for a given input. The level ASSIGNMENT is a pure
    function of the DAG, so reversing the input keeps identical wave membership; only
    the within-wave sequence follows the (reversed) input index."""
    forward = waves(SPECS)
    reversed_in = waves(list(reversed(SPECS)))
    # Same level membership regardless of input order.
    assert [sorted(s.name for s in w) for w in forward] \
        == [sorted(s.name for s in w) for w in reversed_in]
    # Within each wave, ordering follows the input list's index.
    rev_order = {s.name: i for i, s in enumerate(reversed(SPECS))}
    for wave in reversed_in:
        idxs = [rev_order[s.name] for s in wave]
        assert idxs == sorted(idxs)


# ---- small synthetic registries ----

def test_synthetic_fork_shares_a_wave():
    """A; B depends A; C depends A -> B and C land in the SAME wave after A."""
    specs = [
        GenSpec("A", frozenset({"ka"})),
        GenSpec("B", frozenset({"kb"}), frozenset({"ka"})),
        GenSpec("C", frozenset({"kc"}), frozenset({"ka"})),
    ]
    got = [[s.name for s in wave] for wave in waves(specs)]
    assert got == [["A"], ["B", "C"]]


def test_synthetic_chain_is_one_generator_per_wave():
    """A -> B -> C strict chain gives three single-generator waves."""
    specs = [
        GenSpec("A", frozenset({"ka"})),
        GenSpec("B", frozenset({"kb"}), frozenset({"ka"})),
        GenSpec("C", frozenset({"kc"}), frozenset({"kb"})),
    ]
    got = [[s.name for s in wave] for wave in waves(specs)]
    assert got == [["A"], ["B"], ["C"]]


def test_never_provided_dependency_is_level_zero():
    """A dep on a key no generator provides (a pre-existing table) imposes no
    ordering, so such a generator is level 0."""
    specs = [GenSpec("A", frozenset({"ka"}), frozenset({"external_key"}))]
    assert [[s.name for s in wave] for wave in waves(specs)] == [["A"]]


def test_waves_detects_cycle():
    """A cyclic graph raises the SAME error class/message as topo_sort."""
    cyclic = [
        GenSpec("a", frozenset({"ka"}), frozenset({"kb"})),
        GenSpec("b", frozenset({"kb"}), frozenset({"ka"})),
    ]
    with pytest.raises(ValueError, match="cyclic or unsatisfiable"):
        waves(cyclic)


def test_waves_detects_duplicate_provides():
    """Two generators providing one key make the wave assignment ambiguous -> raise,
    exactly like topo_sort."""
    dup = [
        GenSpec("a", frozenset({"shared"})),
        GenSpec("b", frozenset({"shared"})),
    ]
    with pytest.raises(ValueError, match="exactly one provider"):
        waves(dup)
