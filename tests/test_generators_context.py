"""Unit tests for DeployContext (_context.py) — the shared deploy context.

`fq()` and the schema-key derivation in `from_params` are pure and Spark-free but
load-bearing: a wrong short key (e.g. `risk_schema` must derive to `"risk"`)
surfaces only as a deploy-time `KeyError` in `ctx.schemas[...]`. These lock the
mapping and the FQ-name helper the same way test_generators_registry guards the
run order.

`_context` imports `_common`, which imports pyspark at module scope. To keep this
a genuinely no-Spark test (pyspark is `importorskip`-ed elsewhere), we inject a
tiny `_common` stub whose `get_param` reads env/default (the same precedence the
real one uses under pytest, where there are no widgets/argv), then restore
sys.modules so no other test is affected.
"""
import os
import sys
import types

import pytest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GENERATORS = os.path.join(REPO, "runtime", "synthetic-data", "generators")
if GENERATORS not in sys.path:
    sys.path.insert(0, GENERATORS)


def _stub_get_param(name, default=None):
    return os.environ.get(name.upper()) or default or ""


_saved_common = sys.modules.get("_common")
_stub = types.ModuleType("_common")
_stub.get_param = _stub_get_param
sys.modules["_common"] = _stub
try:
    from _context import DeployContext, _SUFFIX, _schema_token_defaults  # noqa: E402
finally:
    if _saved_common is not None:
        sys.modules["_common"] = _saved_common
    else:
        sys.modules.pop("_common", None)


def test_fq_builds_fully_qualified_name():
    ctx = DeployContext(spark=None, catalog="cat", schemas={"marketing": "mk", "risk": "erd"})
    assert ctx.fq("marketing", "promotion") == "cat.mk.promotion"
    assert ctx.fq("risk", "disruption_alert") == "cat.erd.disruption_alert"


def test_fq_unknown_key_raises():
    ctx = DeployContext(spark=None, catalog="cat", schemas={"marketing": "mk"})
    with pytest.raises(KeyError):
        ctx.fq("nope", "t")


def test_schema_keys_are_token_minus_suffix():
    """Every short key is its databricks.yml token minus the trailing '_schema'."""
    tokens = _schema_token_defaults()
    assert tokens, "resolver returned no schema tokens"
    assert all(t.endswith(_SUFFIX) for t in tokens), f"unexpected token(s): {sorted(tokens)}"
    derived = {t[: -len(_SUFFIX)]: v for t, v in tokens.items()}
    for key in ("risk", "order", "promo", "marketing", "customer", "logistics"):
        assert key in derived, f"expected short key {key!r} missing"
        assert derived[key], f"{key} resolved to empty schema name"


def test_from_params_derives_short_keys(monkeypatch):
    monkeypatch.setenv("CATALOG", "unit_cat")
    ctx = DeployContext.from_params(spark=None)
    assert ctx.catalog == "unit_cat"
    assert {"risk", "order"} <= set(ctx.schemas)
    assert all(not k.endswith(_SUFFIX) for k in ctx.schemas)
    assert ctx.fq("risk", "disruption_alert").startswith("unit_cat.")


def test_from_params_requires_catalog(monkeypatch):
    monkeypatch.delenv("CATALOG", raising=False)
    with pytest.raises(ValueError, match="catalog"):
        DeployContext.from_params(spark=None)


def test_single_schema_collapses_every_key_to_one_schema(monkeypatch):
    """--single_schema (design/59 lean per-PR gate) collapses ALL schema keys to one value
    so generators write into the same isolated pr_<N> database the apply step created.
    Every key must map to that single schema, so fq() always targets it."""
    monkeypatch.setenv("CATALOG", "ordm_cicd")
    monkeypatch.setenv("SINGLE_SCHEMA", "pr_108")
    try:
        ctx = DeployContext.from_params(spark=None)
        assert set(ctx.schemas.values()) == {"pr_108"}, ctx.schemas
        assert ctx.fq("risk", "disruption_alert") == "ordm_cicd.pr_108.disruption_alert"
        assert ctx.fq("customer", "account") == "ordm_cicd.pr_108.account"
    finally:
        monkeypatch.delenv("SINGLE_SCHEMA", raising=False)


def test_single_schema_wins_over_a_per_token_override(monkeypatch):
    """single_schema is the explicit 'one database' request, so it beats a per-token
    --<key>_schema override (which otherwise sets just that one schema)."""
    monkeypatch.setenv("CATALOG", "ordm_cicd")
    monkeypatch.setenv("MARKETING_SCHEMA", "custom_mk")   # a per-token override
    monkeypatch.setenv("SINGLE_SCHEMA", "pr_9")
    try:
        ctx = DeployContext.from_params(spark=None)
        assert ctx.schemas["marketing"] == "pr_9"          # single_schema wins, not custom_mk
        assert set(ctx.schemas.values()) == {"pr_9"}
    finally:
        monkeypatch.delenv("MARKETING_SCHEMA", raising=False)
        monkeypatch.delenv("SINGLE_SCHEMA", raising=False)


def test_per_token_override_applies_when_no_single_schema(monkeypatch):
    """Without --single_schema, a per-token --<key>_schema override sets ONLY that key;
    the rest keep their databricks.yml defaults (proves single_schema is not always-on)."""
    monkeypatch.delenv("SINGLE_SCHEMA", raising=False)
    monkeypatch.setenv("CATALOG", "cat")
    monkeypatch.setenv("MARKETING_SCHEMA", "custom_mk")
    try:
        ctx = DeployContext.from_params(spark=None)
        assert ctx.schemas["marketing"] == "custom_mk"     # the override took
        # another key is unaffected (keeps its default, which is non-empty)
        assert ctx.schemas["risk"] and ctx.schemas["risk"] != "custom_mk"
    finally:
        monkeypatch.delenv("MARKETING_SCHEMA", raising=False)
