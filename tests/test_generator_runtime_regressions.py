"""Regression tests for generator failures that only surfaced on serverless.

These tests stay Spark-free so the fast static gate catches the expression and
seed-shape regressions before an end-to-end Databricks deployment.
"""

import ast
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
CMN_GENERATOR = REPO / "runtime/synthetic-data/generators/commerce_media_networks.py"
SDI_GENERATOR = REPO / "runtime/synthetic-data/generators/smarter_demand_and_inventory_decisions.py"


def _function(path, name):
    tree = ast.parse(path.read_text())
    return next(
        node for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == name
    )


class _FakeColumn:
    def __init__(self, value):
        self.value = value
        self.casts = []

    def cast(self, data_type):
        self.casts.append(data_type)
        return self


class _FakeFunctions:
    def __init__(self):
        self.col_calls = []
        self.concat_args = ()

    def col(self, name):
        if not isinstance(name, str):
            raise TypeError("col() accepts a column name, not a Column expression")
        self.col_calls.append(name)
        return _FakeColumn(name)

    def concat_ws(self, separator, *columns):
        self.concat_args = columns
        return _FakeColumn(separator)

    @staticmethod
    def sha2(column, _bits):
        return column


def test_cmn_hash_accepts_column_names_and_column_expressions():
    """A literal Column must pass through instead of being sent to F.col()."""
    fake_functions = _FakeFunctions()
    namespace = {"F": fake_functions}
    function = _function(CMN_GENERATOR, "_hash")
    exec(compile(ast.Module(body=[function], type_ignores=[]), str(CMN_GENERATOR), "exec"), namespace)

    literal_column = _FakeColumn("hh")
    namespace["_hash"]("profile_id", literal_column)

    assert fake_functions.col_calls == ["profile_id"]
    assert fake_functions.concat_args[1] is literal_column
    assert all(column.casts == ["string"] for column in fake_functions.concat_args)


def test_cmn_attributed_outcome_populates_nullable_keyword_columns():
    """The emitted frame must contain every optional keyword field in its contract."""
    source = CMN_GENERATOR.read_text()
    block = source.split("# ---- 3. attributed_outcome", 1)[1].split(
        "# ---- 4. experiment_assignment_bridge", 1
    )[0]

    assert '.withColumn("keyword_sk"' in block
    assert '.withColumn("keyword_id"' in block


def _seed_rows(path, function_name):
    function = _function(path, function_name)
    return next(
        statement.value for statement in function.body
        if isinstance(statement, ast.Assign)
        and any(isinstance(target, ast.Name) and target.id == "rows" for target in statement.targets)
    )


def _is_decimal_constructor(node):
    return (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "D"
        and len(node.args) == 1
        and isinstance(node.args[0], ast.Constant)
        and isinstance(node.args[0].value, str)
    )


def test_sdi_decimal_schema_seeds_use_decimal_values():
    """Spark Connect requires Decimal objects for values bound to DECIMAL fields."""
    tree = ast.parse(SDI_GENERATOR.read_text())
    assert any(
        isinstance(node, ast.ImportFrom)
        and node.module == "decimal"
        and any(alias.name == "Decimal" and alias.asname == "D" for alias in node.names)
        for node in tree.body
    )

    targets = _seed_rows(SDI_GENERATOR, "generate_service_level_targets")
    assert all(
        _is_decimal_constructor(value)
        for row in targets.elts
        for value in row.elts[4:7]
    )

    loss_function = _seed_rows(SDI_GENERATOR, "generate_service_level_z")
    assert all(_is_decimal_constructor(row.elts[0]) for row in loss_function.elts)


AASA_GENERATOR = REPO / "runtime/synthetic-data/generators/ai_assisted_store_associates.py"


def test_generator_write_calls_supply_all_required_args():
    """Regression: the AI-Assisted Store Associates generator called the shared
    _common._write(spark, df, fqtn, columns, mode, merge_keys=None) as _write(df, fqtn, mode) --
    3 args -- so it failed at runtime with 'missing 2 required positional arguments'. Static tests
    passed because they never invoke _write. Guard every generator: each _write(...) call must
    supply at least the 5 required arguments (positional + keyword, or a *args splat), so a wrong
    calling convention fails here instead of only on the serverless deploy."""
    offenders = []
    for path in sorted(GENERATORS_DIR.glob("*.py")):
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                    and node.func.id == "_write"):
                has_splat = any(isinstance(a, ast.Starred) for a in node.args)
                nargs = len(node.args) + len(node.keywords)
                if not has_splat and nargs < 5:
                    offenders.append(f"{path.name}:{node.lineno} (_write called with {nargs} args)")
    assert not offenders, (
        "_write() must be called as (spark, df, fqtn, columns, mode[, merge_keys]); "
        "under-supplied call(s): " + "; ".join(offenders))


def _decimal_indices(schema_ddl):
    """Positions (0-based) of DECIMAL columns in a `name TYPE, ...` DDL string. Splits on
    TOP-LEVEL commas only -- DECIMAL(12,3) carries an inner comma that must not split the field."""
    fields, depth, cur = [], 0, ""
    for ch in schema_ddl:
        if ch == "(":
            depth += 1; cur += ch
        elif ch == ")":
            depth -= 1; cur += ch
        elif ch == "," and depth == 0:
            fields.append(cur); cur = ""
        else:
            cur += ch
    if cur.strip():
        fields.append(cur)
    return [i for i, field in enumerate(fields) if "DECIMAL" in field.upper()]


def _binds_decimal_safely(node):
    """A row element bound to a DECIMAL field must be an EXPLICIT Decimal -- `D(...)` or the
    `_dec(...)` wrapper -- or a None literal (nullable column). A bare float/int literal (Spark
    Connect rejects it) OR a bare Name (an unwrapped fixture value, e.g. `qoh` straight from a
    tuple of floats -- the exact shape of this bug) is unsafe: the decimal columns in this
    generator are always wrapped, so require the wrap explicitly rather than let a Name slip
    through as 'maybe already a Decimal'."""
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
        return node.func.id in ("D", "_dec")
    if isinstance(node, ast.Constant):
        return node.value is None
    return False


def test_aasa_decimal_createdataframe_fields_never_bind_bare_floats():
    """Regression: the AI-Assisted Store Associates generator's associate_context_event fixtures
    bound Python floats (24.0, 12.9900, ...) to DECIMAL(12,3)/(18,4) createDataFrame fields, which
    Spark Connect rejects on the serverless deploy -- it failed generate_all wave 2 with an empty
    exception. Same class as test_sdi_decimal_schema_seeds_use_decimal_values, which did not cover
    this generator. Guard it generically: for every createDataFrame(rows, schema=<ddl>) here, the
    row-append tuples must bind DECIMAL positions as Decimal (D(...)/_dec(...)), never bare floats."""
    tree = ast.parse(AASA_GENERATOR.read_text())
    assert any(isinstance(n, ast.ImportFrom) and n.module == "decimal"
               and any(a.name == "Decimal" and a.asname == "D" for a in n.names)
               for n in ast.walk(tree)), "AASA generator must import Decimal as D"

    checked = 0
    for fn in [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]:
        # find `schema_def = "<ddl>"` and the rows var fed to createDataFrame in this function
        schema_ddl = next((s.value.value for s in ast.walk(fn)
                           if isinstance(s, ast.Assign) and isinstance(s.value, ast.Constant)
                           and isinstance(s.value.value, str) and "DECIMAL" in s.value.value.upper()),
                          None)
        if schema_ddl is None:
            continue
        dec_idx = _decimal_indices(schema_ddl)
        # every `rows.append((...))` tuple in this function must bind those positions safely
        for call in [n for n in ast.walk(fn) if isinstance(n, ast.Call)
                     and isinstance(n.func, ast.Attribute) and n.func.attr == "append"]:
            for arg in call.args:
                if isinstance(arg, ast.Tuple):
                    for i in dec_idx:
                        if i < len(arg.elts):
                            assert _binds_decimal_safely(arg.elts[i]), (
                                f"{fn.name}: element {i} (a DECIMAL column) binds a bare float/int; "
                                f"wrap it as Decimal (_dec(...)/D(...)) for Spark Connect")
                            checked += 1
    assert checked, "no DECIMAL-column row bindings were checked -- test wiring is stale"


# --- serverless compatibility: no DataFrame cache/persist in any generator -------------

GENERATORS_DIR = REPO / "runtime/synthetic-data/generators"


def _cache_persist_calls(path):
    """Return the method names (cache/persist/unpersist/checkpoint) any expression in `path`
    invokes, via AST -- so `df.cache()`, `x.persist(...)`, `.unpersist()` are all caught
    regardless of the receiver, and a `.cache` mention inside a string/comment is NOT."""
    banned = {"cache", "persist", "unpersist", "checkpoint", "localCheckpoint"}
    found = []
    for node in ast.walk(ast.parse(path.read_text())):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr in banned):
            found.append(node.func.attr)
    return found


def test_no_generator_caches_or_persists_on_serverless():
    """The daily/serving deploy runs generate_all on SERVERLESS compute, which rejects
    PERSIST/CACHE ([NOT_SUPPORTED_WITH_SERVERLESS] PERSIST TABLE, SQLSTATE 0A000). This
    root-caused a daily-deploy failure in wave 4 (data_sharing_with_suppliers called
    scope.cache()). Guard EVERY generator: no .cache()/.persist()/.unpersist()/.checkpoint()
    method call, and no CACHE/PERSIST TABLE SQL. Recomputing a deterministic frame is correct
    and cheap on the bounded demo footprints; caching is never worth breaking serverless."""
    offenders = {}
    sql_offenders = {}
    import re
    sql_re = re.compile(r"\b(CACHE|PERSIST)\s+TABLE\b", re.IGNORECASE)
    for path in sorted(GENERATORS_DIR.glob("*.py")):
        calls = _cache_persist_calls(path)
        if calls:
            offenders[path.name] = calls
        # Scan source with comment lines stripped, so a `# ... PERSIST TABLE ...` explanatory
        # comment (like the one in data_sharing_with_suppliers documenting WHY there is no cache)
        # is not a false positive -- only real CACHE/PERSIST TABLE SQL should match.
        code_only = "\n".join(
            line for line in path.read_text().splitlines() if not line.lstrip().startswith("#"))
        if sql_re.search(code_only):
            sql_offenders[path.name] = "CACHE/PERSIST TABLE"
    assert not offenders, (
        "generators call cache/persist (unsupported on serverless): " + repr(offenders))
    assert not sql_offenders, (
        "generators issue CACHE/PERSIST TABLE SQL (unsupported on serverless): "
        + repr(sql_offenders))
