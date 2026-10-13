"""Pin tools/ddl_domain_closure.py — the lean per-PR gate's view-dependency closure.

The gate already expands the changed labels by what the selected GENERATORS write
(_registry.generator_domains). That closes the DATA gap but not the VIEW-COMPILATION one:
a gold/metric view may read another package's gold object with no FK and no generator
relationship (the deliberate NULL-safe cross-package read, ADR 0019/0021), and a plain
view still has to RESOLVE its references at CREATE time. If that package's DDL was never
applied the deploy fails with TABLE_OR_VIEW_NOT_FOUND.

The concrete regression these tests pin: a `data-sharing-with-suppliers` change selects the
`customer_ltv` generator (it provides `acu`), so actionable-customer-understanding's DDL is
applied — including its metric view, which reads unified-customer-view's
gold_activatable_audience_current. UCV ships NO generator, so generator_domains never
yields it, and the lean deploy failed on every such PR. conftest.py puts the repo root on
sys.path.
"""
import os
import sys

from tools.ddl_domain_closure import (
    _strip_sql_comments,
    ddl_domain_closure,
    referenced_labels,
    schema_token_owners,
)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def test_schema_tokens_map_to_real_unit_directories():
    owners = schema_token_owners()
    assert owners, "expected a non-empty ${x_schema} -> unit map"
    for token, label in owners.items():
        assert token.endswith("_schema")
        assert any(os.path.isdir(os.path.join(REPO, root, label))
                   for root in ("canonical-core", "outcome-packages")), \
            f"{token} maps to {label!r}, which is not a unit directory"
    # spot-check the two ends of the failing dependency
    assert owners.get("ucv_schema") == "unified-customer-view"
    assert owners.get("acu_schema") == "actionable-customer-understanding"


def test_closure_pulls_in_a_package_reached_only_through_a_view():
    """ACU's views read UCV, and UCV has no generator — the exact deploy failure."""
    closed = ddl_domain_closure(["actionable-customer-understanding"])
    assert "unified-customer-view" in closed, (
        "actionable-customer-understanding's metric view reads unified-customer-view's "
        "gold_activatable_audience_current; without UCV's DDL the view cannot resolve")


def test_closure_is_a_fixed_point_not_one_hop():
    """A newly-added unit may itself read a third, so closure must iterate."""
    direct = referenced_labels("actionable-customer-understanding")
    closed = set(ddl_domain_closure(["actionable-customer-understanding"]))
    # everything reachable from a pulled-in unit is also present
    for label in direct:
        assert referenced_labels(label) <= closed, \
            f"{label} was added but its own references were not closed over"


def test_closure_covers_the_real_lean_deploy_selection():
    """End-to-end: the label set the workflow actually computes for a dss-only PR."""
    sys.path.insert(0, os.path.join(REPO, "runtime", "synthetic-data", "generators"))
    from _registry import GENERATORS, generator_domains

    changed = "data-sharing-with-suppliers"
    generator_expanded = generator_domains(GENERATORS, changed) | {changed}
    closed = set(ddl_domain_closure(sorted(generator_expanded)))

    assert generator_expanded <= closed, "closure must never DROP a label"
    assert "unified-customer-view" in closed, (
        "the lean deploy failed here: customer_ltv provides `acu`, so ACU's metric view is "
        "created, and it reads UCV — which has no generator")


def test_closure_is_idempotent_and_includes_its_input():
    once = ddl_domain_closure(["data-sharing-with-suppliers"])
    twice = ddl_domain_closure(once)
    assert once == twice
    assert "data-sharing-with-suppliers" in once


def test_unknown_and_blank_labels_are_harmless():
    # A label with no unit directory contributes no references rather than raising: the
    # gate must not hard-fail on a renamed/deleted package.
    assert ddl_domain_closure(["", "  ", "no-such-package"]) == ["no-such-package"]


def test_closure_follows_fk_targets_reached_only_through_relationships():
    """A package whose gold/metric views read only its OWN tables still FK-references the
    canonical core in relationships.sql; those parents must be applied or the ALTER ADD
    FOREIGN KEY dies with TABLE_OR_VIEW_NOT_FOUND. ai-assisted-store-associates is the exact
    case: its queue/funnel views touch no core object, so the FK edge is the only path."""
    label = "ai-assisted-store-associates"
    refs = referenced_labels(label)
    for parent in ("store", "customer", "product"):
        assert parent in refs, (
            f"{label} FK-references {parent} in relationships.sql; the closure must pull it "
            "in so the lean deploy applies the parent before the FK ALTER")
    assert set(ddl_domain_closure([label])) >= {label, "store", "customer", "product"}


def test_commented_out_references_do_not_drag_in_a_package():
    """View headers DISCUSS other packages in prose; only real SQL refs may count."""
    sql = """
    -- reads ${ucv_schema}.gold_activatable_audience_current when present
    /* also ${interaction_schema}.touchpoint */
    SELECT * FROM ${catalog}.${acu_schema}.gold_customer_ltv
    """
    stripped = _strip_sql_comments(sql)
    assert "ucv_schema" not in stripped
    assert "interaction_schema" not in stripped
    assert "acu_schema" in stripped
