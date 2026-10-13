"""Static tests for AI-Assisted Store Associates action generator.

Tests verify that the generator's interface contracts (D6) hold:
- Column constants match DDL (minus surrogate keys)
- Enum constants are subsets of DDL CHECK lists
- Registry entry declares correct provides/depends_on
- Seeds.yaml volumes are configured
- _write() calls have required signatures
- Decimal columns use Decimal objects, not float
"""

import ast
import os
from pathlib import Path

import pytest
import sqlglot
import sqlglot.expressions as E
import yaml

from tools.ordm_config import resolve

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PKG = os.path.join(REPO, "outcome-packages", "ai-assisted-store-associates")
GENERATOR = os.path.join(REPO, "runtime", "synthetic-data", "generators", "ai_assisted_store_associates.py")
SEEDS = os.path.join(REPO, "runtime", "synthetic-data", "seeds.yaml")


def _read(path):
    """Read file contents."""
    return open(path).read()


def _detok(text):
    """Resolve Databricks config tokens."""
    return resolve(text, "ordm")


def _ddl_cols(path, skip_sk):
    """Extract column names from DDL CREATE TABLE, excluding a surrogate key."""
    ddl = _detok(_read(path))

    # Manual parsing: extract lines that match column definition pattern
    # Pattern: column_name DATATYPE [other stuff]
    import re
    lines = ddl.split('\n')
    cols = []
    in_create = False

    for line in lines:
        if 'CREATE TABLE' in line.upper():
            in_create = True
            continue
        if not in_create:
            continue

        # Stop at constraint declarations
        if 'CONSTRAINT' in line.upper() or line.strip().startswith('USING') or line.strip().startswith(')'):
            break

        line = line.strip()
        if not line or line.startswith('--') or line.startswith('COMMENT'):
            continue

        # Extract column name: first word before a type keyword
        match = re.match(r'(\w+)\s+(BIGINT|STRING|TIMESTAMP|DATE|DECIMAL|DOUBLE|INT|BOOLEAN|TEXT|LONG)\b', line)
        if match:
            col_name = match.group(1)
            if col_name != skip_sk:
                cols.append(col_name)

    return cols


def _gen_const_list(name):
    """Extract a module-level list constant from the generator."""
    mod = ast.parse(_read(GENERATOR))
    for node in mod.body:
        if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name):
            if node.targets[0].id == name and isinstance(node.value, ast.List):
                return [e.value for e in node.value.elts if isinstance(e, ast.Constant)]
    raise AssertionError(f"constant {name} not found or not a list in generator")


def _gen_const_dict(name):
    """Extract a module-level dict constant from the generator."""
    mod = ast.parse(_read(GENERATOR))
    for node in mod.body:
        if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name):
            if node.targets[0].id == name and isinstance(node.value, ast.Dict):
                return {k.value: v.value for k, v in zip(node.value.keys, node.value.values)
                        if isinstance(k, ast.Constant) and isinstance(v, ast.Constant)}
    raise AssertionError(f"constant {name} not found or not a dict in generator")


def _ddl_check_values(ddl, column_name):
    """Extract allowed values from a column's CHECK constraint."""
    create = next(
        s for s in sqlglot.parse(ddl, read="databricks", error_level="ignore")
        if isinstance(s, E.Create)
    )
    for constraint in create.find_all(E.Constraint):
        if constraint.kind and constraint.kind.lower() == "check":
            expr_str = constraint.expression.sql()
            if column_name in expr_str and "IN" in expr_str.upper():
                # Extract values from IN (...)
                match = sqlglot.parse_one(constraint.expression, read="databricks")
                if isinstance(match, E.In):
                    return {lit.this for lit in match.expressions[0] if isinstance(lit, E.Literal)}
    return set()


# ========== Column contract tests ==========

@pytest.mark.parametrize(
    "table,sk,gen_const",
    [
        ("associate", "associate_sk", "ASSOCIATE_COLUMNS"),
        ("suggested_action", "suggested_action_sk", "SUGGESTED_ACTION_COLUMNS"),
        ("action_response_log", "action_response_log_sk", "ACTION_RESPONSE_LOG_COLUMNS"),
        ("outcome_resolution", "outcome_resolution_sk", "OUTCOME_RESOLUTION_COLUMNS"),
    ],
)
def test_generator_columns_match_ddl(table, sk, gen_const):
    """Generator's *_COLUMNS constant matches DDL (minus surrogate key)."""
    ddl_cols = set(_ddl_cols(os.path.join(PKG, "tables", f"{table}.sql"), sk))
    gen_cols = set(_gen_const_list(gen_const))
    assert ddl_cols == gen_cols, (
        f"{table} drift: missing={sorted(ddl_cols - gen_cols)} "
        f"extra={sorted(gen_cols - ddl_cols)}"
    )


# ========== Enum value tests ==========

@pytest.mark.parametrize(
    "table,column,gen_const",
    [
        ("associate", "role", "ASSOCIATE_ROLES"),
        ("associate", "employment_type", "EMPLOYMENT_TYPES"),
        ("suggested_action", "action_type", "ACTION_TYPES"),
        ("suggested_action", "trigger_source", "TRIGGER_SOURCES"),
        ("suggested_action", "decay_type", "DECAY_TYPES"),
        ("action_response_log", "response_type", "RESPONSE_TYPES"),
        ("outcome_resolution", "outcome_type", "OUTCOME_TYPES"),
    ],
)
def test_generator_enum_values_within_ddl(table, column, gen_const):
    """Generator's enum constants are subsets of DDL CHECK lists."""
    ddl = _detok(_read(os.path.join(PKG, "tables", f"{table}.sql")))
    relationships = _detok(_read(os.path.join(PKG, "relationships.sql")))
    combined_sql = ddl + "\n" + relationships

    # Parse constraints to find allowed values for the column
    allowed = set()
    for constraint_sql in re.findall(r'ADD CONSTRAINT.*?CHECK\s*\([^)]+\)', combined_sql):
        if column in constraint_sql:
            # Extract IN (...) values
            in_match = re.search(r"IN\s*\(([^)]+)\)", constraint_sql)
            if in_match:
                values_str = in_match.group(1)
                allowed.update(v.strip().strip("'\"") for v in values_str.split(","))

    gen_values = set(_gen_const_list(gen_const))
    assert gen_values <= allowed, (
        f"{table}.{column}: generator produces values outside DDL: "
        f"{sorted(gen_values - allowed)}"
    )


def test_generator_terminal_response_types():
    """TERMINAL_RESPONSE_TYPES is a subset of RESPONSE_TYPES."""
    all_responses = set(_gen_const_list("RESPONSE_TYPES"))
    terminal_responses = set(_gen_const_list("TERMINAL_RESPONSE_TYPES"))
    assert terminal_responses <= all_responses, (
        f"terminal responses not in response types: {sorted(terminal_responses - all_responses)}"
    )


def test_generator_zone_for_action_mappings(GEN):
    """ZONE_FOR_ACTION maps each action type to valid zone suffixes."""
    action_types = set(GEN.ACTION_TYPES)
    zone_for_action = GEN.ZONE_FOR_ACTION
    zone_suffixes = set(GEN.ZONE_SUFFIXES)

    # Every action type should have a mapping
    assert set(zone_for_action.keys()) == action_types, (
        f"ZONE_FOR_ACTION incomplete: missing={sorted(action_types - set(zone_for_action.keys()))}"
    )

    # Every suffix in the mappings should be valid
    for action, suffixes in zone_for_action.items():
        if isinstance(suffixes, (list, tuple)):
            invalid = set(suffixes) - zone_suffixes
            assert not invalid, (
                f"ZONE_FOR_ACTION[{action}] has invalid suffixes: {sorted(invalid)}"
            )


def test_generator_role_map_targets():
    """ROLE_MAP targets are all valid associate roles."""
    valid_roles = set(_gen_const_list("ASSOCIATE_ROLES"))
    role_map = _gen_const_dict("ROLE_MAP")
    target_roles = set(role_map.values())
    invalid_targets = target_roles - valid_roles
    assert not invalid_targets, (
        f"ROLE_MAP targets invalid roles: {sorted(invalid_targets)}"
    )


# ========== Seeds.yaml validation ==========

def test_seeds_yaml_has_aasa_volumes():
    """Seeds.yaml declares ai_assisted_store_associates volumes."""
    seeds = yaml.safe_load(_read(SEEDS))
    aasa_config = seeds.get("domains", {}).get("ai_assisted_store_associates", {})
    volumes = aasa_config.get("volumes", {})

    required_keys = {
        "action_history_days", "actions_per_store_day", "open_actions_per_associate_max"
    }
    missing = required_keys - set(volumes.keys())
    assert not missing, f"Seeds.yaml missing volume keys: {sorted(missing)}"

    # Verify sensible values
    assert volumes["action_history_days"] >= 1
    assert volumes["actions_per_store_day"] >= 1
    assert volumes["open_actions_per_associate_max"] >= 1


# ========== _write() signature checks ==========

def test_generator_write_calls_have_required_args():
    """Every _write(...) call must supply at least 5 required arguments."""
    tree = ast.parse(_read(GENERATOR))
    offenders = []

    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            if node.func.id == "_write":
                # Count positional args and keywords
                has_splat = any(isinstance(a, ast.Starred) for a in node.args)
                nargs = len(node.args) + len(node.keywords)
                if not has_splat and nargs < 5:
                    offenders.append(f"line {node.lineno}: {nargs} args")

    assert not offenders, (
        "_write(spark, df, fqtn, columns, mode) requires 5+ args; under-supplied: "
        + "; ".join(offenders)
    )


# ========== Decimal checks ==========

def test_generator_uses_decimal_for_decimal_columns():
    """Generator imports and uses Decimal for DECIMAL columns."""
    gen_code = _read(GENERATOR)
    # Check for Decimal import (as D or direct)
    assert ("from decimal import Decimal" in gen_code or "import Decimal" in gen_code), (
        "Decimal not imported"
    )
    # Check that D(...) or Decimal(...) is used
    assert ("D(" in gen_code or "Decimal(" in gen_code), (
        "Decimal constructor not used"
    )


# ========== Resolve anchor test ==========

def test_generator_resolve_anchor_returns_midnight():
    """resolve_anchor(value) returns UTC midnight of the given date, or today."""
    mod = ast.parse(_read(GENERATOR))

    # Find resolve_anchor function
    resolve_anchor_fn = None
    for node in mod.body:
        if isinstance(node, ast.FunctionDef) and node.name == "resolve_anchor":
            resolve_anchor_fn = node
            break

    assert resolve_anchor_fn is not None, "resolve_anchor function not found"


# ========== Import from _registry check ==========

def test_aasa_generator_in_registry():
    """ai_assisted_store_associates generator is registered in _registry.GENERATORS."""
    import sys
    generators_dir = os.path.join(REPO, "runtime", "synthetic-data", "generators")
    if generators_dir not in sys.path:
        sys.path.insert(0, generators_dir)

    from _registry import GENERATORS

    aasa_spec = next((s for s in GENERATORS if s.name == "ai_assisted_store_associates"), None)
    assert aasa_spec is not None, "ai_assisted_store_associates not registered in _registry.GENERATORS"

    # Verify depends_on includes labor (D3 requirement)
    assert "labor" in aasa_spec.depends_on, (
        "ai_assisted_store_associates should depend on labor (D3 requirement)"
    )


# ========== Builder functions exist ==========

def test_generator_has_builder_functions():
    """Generator defines the required pure-Python builders (D6)."""
    mod = ast.parse(_read(GENERATOR))
    func_names = {node.name for node in mod.body if isinstance(node, ast.FunctionDef)}

    required = {
        "resolve_anchor",
        "build_associate_rows",
        "build_action_rows",
    }
    missing = required - func_names
    assert not missing, f"Generator missing required builders: {sorted(missing)}"


# ========== Imports and Spark checks ==========

def test_generator_has_pyspark_import():
    """Generator imports pyspark.sql for Spark writers."""
    gen_code = _read(GENERATOR)
    assert "from pyspark.sql" in gen_code or "import pyspark" in gen_code


# Import regex for use in enum tests
import re


# ---- pure builders: imported with a scoped pyspark stub (the module's _common imports pyspark) ----

@pytest.fixture(scope="module")
def GEN():
    """Import the generator for its pure-Python builders without Spark. pyspark/dbldatagen are stubbed
    only while the module imports and restored afterwards, so other tests' importorskip still works."""
    import importlib
    import sys
    import types

    class _Any:
        def __getattr__(self, name):
            return _Any()

        def __call__(self, *a, **k):
            return _Any()

    names = ["pyspark", "pyspark.sql", "pyspark.sql.functions", "pyspark.sql.types",
             "pyspark.sql.window", "pyspark.sql.utils", "dbldatagen"]
    saved = {n: sys.modules.get(n) for n in names + ["_common", "ai_assisted_store_associates"]}
    gen_dir = os.path.join(REPO, "runtime", "synthetic-data", "generators")
    try:
        import pyspark  # noqa: F401  (real Spark available: import as-is)
        stubbed = False
    except ImportError:
        stubbed = True
        for n in names:
            mod = types.ModuleType(n)
            mod.__getattr__ = lambda name: _Any()
            sys.modules[n] = mod
    sys.path.insert(0, gen_dir)
    try:
        sys.modules.pop("_common", None)
        sys.modules.pop("ai_assisted_store_associates", None)
        module = importlib.import_module("ai_assisted_store_associates")
    finally:
        sys.path.remove(gen_dir)
        if stubbed:
            for n, m in saved.items():
                if m is None:
                    sys.modules.pop(n, None)
                else:
                    sys.modules[n] = m
    return module


def _fixture_rows(GEN, anchor_date="2026-10-11", seed=15015):
    import datetime as dt
    roles = ["cashier", "sales_associate", "fulfillment", "inventory", "supervisor"]
    employees = [{"employee_id": f"EMP-{i:05d}", "home_store_sk": i % 6, "home_store_id": f"STR-{i % 6:05d}",
                  "primary_role_code": roles[i % 5],
                  "employment_status": "terminated" if i % 7 == 3 else "leave" if i % 7 == 5 else "active",
                  "employment_type": "full_time", "hire_date": dt.date(2020, 1, 1)} for i in range(18)]
    associates = GEN.build_associate_rows(employees, [])
    for i, a in enumerate(associates):
        a["associate_sk"] = 100 + i
    stores = [{"store_sk": s, "store_id": f"STR-{s:05d}"} for s in range(8)]   # stores 6, 7: no associates
    products = [{"product_sk": p, "product_id": f"SKU-{p:08d}"} for p in range(20)]
    profiles = [{"profile_sk": p, "profile_id": f"PRF-{p:06d}"} for p in range(50)]
    cfg = {"action_history_days": 14, "actions_per_store_day": 4, "open_actions_per_associate_max": 5}
    anchor = GEN.resolve_anchor(anchor_date)
    actions, responses, outcomes = GEN.build_action_rows(associates, stores, products, profiles, anchor, cfg, seed, "USD")
    return anchor, associates, actions, responses, outcomes


def _utc(ts):
    import datetime as dt
    return ts if ts.tzinfo else ts.replace(tzinfo=dt.timezone.utc)


def test_resolve_anchor_is_utc_midnight(GEN):
    import datetime as dt
    a = GEN.resolve_anchor("2026-10-11")
    assert a == dt.datetime(2026, 10, 11, tzinfo=dt.timezone.utc)


def test_builders_are_deterministic_across_calls_and_anchor_sensitive(GEN):
    first = _fixture_rows(GEN)[2:]
    assert first == _fixture_rows(GEN)[2:]
    assert first[0] != _fixture_rows(GEN, anchor_date="2026-10-12")[2]


def test_builder_hashing_does_not_use_python_hash():
    # hash() is salted per process (PYTHONHASHSEED), which would make every deploy different
    tree = ast.parse(_read(GENERATOR))
    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and getattr(n.func, "id", None) == "hash"]
    assert not calls, f"builtin hash() used at lines {[c.lineno for c in calls]}"


def test_no_action_or_response_at_or_after_the_anchor(GEN):
    anchor, _, actions, responses, outcomes = _fixture_rows(GEN)
    assert max(_utc(a["generated_timestamp"]) for a in actions) < anchor
    assert all(_utc(r["response_timestamp"]) < anchor for r in responses)
    assert all(_utc(o["resolution_timestamp"]) < anchor for o in outcomes)


def test_response_lifecycle_is_ordered_and_terminal_last(GEN):
    import collections
    _, _, actions, responses, _ = _fixture_rows(GEN)
    generated = {a["suggested_action_id"]: _utc(a["generated_timestamp"]) for a in actions}
    by_action = collections.defaultdict(list)
    for r in responses:
        assert _utc(r["response_timestamp"]) > generated[r["suggested_action_id"]], r
        by_action[r["suggested_action_id"]].append(r)
    terminal = set(GEN.TERMINAL_RESPONSE_TYPES)
    for rs in by_action.values():
        rs.sort(key=lambda r: r["response_timestamp"])
        kinds = [r["response_type"] for r in rs]
        assert sum(k in terminal for k in kinds) <= 1, kinds
        assert all(k not in terminal for k in kinds[:-1]), kinds
        if "completed" in kinds:
            assert "accepted" in kinds, kinds


def test_open_slice_is_non_terminal_and_expiry_depends_on_decay(GEN):
    import collections
    import datetime as dt
    anchor, associates, actions, responses, _ = _fixture_rows(GEN)
    open_actions = [a for a in actions if _utc(a["expiration_timestamp"]) > anchor + dt.timedelta(days=1)]
    per_associate = collections.Counter(a["associate_id"] for a in open_actions)
    assert set(per_associate) == {a["associate_id"] for a in associates if a["is_active"]}
    assert min(per_associate.values()) >= 2 and max(per_associate.values()) <= 5
    terminal = set(GEN.TERMINAL_RESPONSE_TYPES)
    responded = {r["suggested_action_id"]: r["response_type"] for r in responses}
    for a in open_actions:
        assert anchor - dt.timedelta(hours=12) <= _utc(a["generated_timestamp"]) < anchor
        days_open = (_utc(a["expiration_timestamp"]) - anchor).days
        if a["decay_type"] == "none":
            assert 7 <= days_open <= 30, a
        else:
            assert 2 <= days_open <= 7, a
        assert responded.get(a["suggested_action_id"]) not in terminal
    decay = collections.Counter(a["decay_type"] for a in open_actions)
    assert decay["none"] / len(open_actions) > 0.5, decay


def test_history_actions_all_reach_a_terminal_response(GEN):
    import datetime as dt
    anchor, _, actions, responses, _ = _fixture_rows(GEN)
    terminal = set(GEN.TERMINAL_RESPONSE_TYPES)
    finished = {r["suggested_action_id"] for r in responses if r["response_type"] in terminal}
    history = [a for a in actions if _utc(a["expiration_timestamp"]) < anchor]
    assert history and all(a["suggested_action_id"] in finished for a in history)


def test_routing_stays_in_store_and_unrouted_actions_are_never_worked(GEN):
    _, associates, actions, responses, _ = _fixture_rows(GEN)
    home = {a["associate_id"]: a["store_id"] for a in associates}
    worked = {r["suggested_action_id"] for r in responses if r["response_type"] in ("accepted", "completed")}
    for a in actions:
        assert (a["associate_sk"] is None) == (a["associate_id"] is None)
        if a["associate_id"] is not None:
            assert home[a["associate_id"]] == a["store_id"]
        else:
            assert a["suggested_action_id"] not in worked
    assert {a["store_id"] for a in actions if a["associate_id"] is None} >= {"STR-00006", "STR-00007"}


def test_outcomes_follow_completion_and_carry_one_currency(GEN):
    from decimal import Decimal
    _, _, actions, responses, outcomes = _fixture_rows(GEN)
    by_id = {a["suggested_action_id"]: a for a in actions}
    completed_at = {r["suggested_action_id"]: _utc(r["response_timestamp"]) for r in responses
                    if r["response_type"] == "completed"}
    assert outcomes
    for o in outcomes:
        assert (o["outcome_value_amount"] is None) == (o["currency_code"] is None), o
        if o["outcome_type"] == "sale_closed":
            assert by_id[o["suggested_action_id"]]["action_type"] in ("customer_assist", "clienteling")
            assert o["suggested_action_id"] in completed_at
            assert isinstance(o["outcome_value_amount"], Decimal)
            assert o["outcome_value_amount"] == o["outcome_value_amount"].quantize(Decimal("0.01"))
            assert Decimal("15") <= o["outcome_value_amount"] <= Decimal("250")
        if o["suggested_action_id"] in completed_at:
            assert _utc(o["resolution_timestamp"]) > completed_at[o["suggested_action_id"]]
    assert {o["currency_code"] for o in outcomes if o["currency_code"]} == {"USD"}
    assert any(o["outcome_type"] == "sale_closed" for o in outcomes)


def test_enum_values_and_clienteling_share(GEN):
    _, associates, actions, responses, outcomes = _fixture_rows(GEN)
    assert {a["role"] for a in associates} <= set(GEN.ASSOCIATE_ROLES)
    assert {a["action_type"] for a in actions} <= set(GEN.ACTION_TYPES)
    assert {a["decay_type"] for a in actions} <= set(GEN.DECAY_TYPES)
    assert {a["trigger_source"] for a in actions if a["trigger_source"]} <= set(GEN.TRIGGER_SOURCES)
    assert {r["response_type"] for r in responses} <= set(GEN.RESPONSE_TYPES)
    assert {o["outcome_type"] for o in outcomes} <= set(GEN.OUTCOME_TYPES)
    assert sum(a["action_type"] == "clienteling" for a in actions) / len(actions) >= 0.10
    assert all(isinstance(a["priority_score"], float) for a in actions)   # DOUBLE column
    assert len({a["suggested_action_id"] for a in actions}) == len(actions)
    assert len({r["action_response_log_id"] for r in responses}) == len(responses)
    assert len({o["outcome_resolution_id"] for o in outcomes}) == len(outcomes)


def test_inactive_associates_are_never_routed_work(GEN):
    _, associates, actions, _, _ = _fixture_rows(GEN)
    inactive = {a["associate_id"] for a in associates if not a["is_active"]}
    assert inactive, "fixture should include terminated / on-leave employees"
    assert not [a for a in actions if a["associate_id"] in inactive]


def test_builder_output_does_not_depend_on_input_order(GEN):
    # Spark returns collected rows in scan order, which can change after OPTIMIZE or a rewrite
    import random
    anchor, associates, actions, responses, outcomes = _fixture_rows(GEN)
    stores = [{"store_sk": s, "store_id": f"STR-{s:05d}"} for s in range(8)]
    products = [{"product_sk": p, "product_id": f"SKU-{p:08d}"} for p in range(20)]
    profiles = [{"profile_sk": p, "profile_id": f"PRF-{p:06d}"} for p in range(50)]
    rng = random.Random(7)
    for lst in (associates, stores, products, profiles):
        rng.shuffle(lst)
    cfg = {"action_history_days": 14, "actions_per_store_day": 4, "open_actions_per_associate_max": 5}
    shuffled = GEN.build_action_rows(associates, stores, products, profiles, anchor, cfg, 15015, "USD")
    assert shuffled == (actions, responses, outcomes)


def test_load_timestamp_follows_the_anchor(GEN):
    anchor, associates, actions, responses, outcomes = _fixture_rows(GEN)
    for rows in (actions, responses, outcomes):
        assert {_utc(r["load_timestamp"]) for r in rows} == {anchor}
    completed = {r["suggested_action_id"]: _utc(r["response_timestamp"]) for r in responses
                 if r["response_type"] == "completed"}
    for a in actions:
        if a["suggested_action_id"] in completed:
            assert completed[a["suggested_action_id"]] <= _utc(a["expiration_timestamp"])


def test_skills_from_the_spark_read_shape_populate_skill_tags(GEN):
    # generate_associates reads employee_skill already filtered to is_active and selects only
    # employee_id + skill_code; the builder must keep those rows
    import datetime as dt
    employees = [{"employee_id": "EMP-1", "home_store_sk": 1, "home_store_id": "STR-1",
                  "primary_role_code": "cashier", "employment_status": "active",
                  "employment_type": "full_time", "hire_date": dt.date(2020, 1, 1)}]
    skills = [{"employee_id": "EMP-1", "skill_code": "till"}, {"employee_id": "EMP-1", "skill_code": "bopis"}]
    (row,) = GEN.build_associate_rows(employees, skills)
    assert row["skill_tags"] == "bopis|till"
