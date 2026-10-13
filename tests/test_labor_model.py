"""Static consistency tests for the ORDM labor domain.

These run WITHOUT a Spark cluster or Databricks workspace — they validate
that the DDL, the synthetic-data generator, and the data-quality checks stay
mutually consistent and within the ORDM guardrails. Cluster-dependent checks
live in canonical-core/labor/checks.sql and run via runtime/data-quality/run_checks.py.
"""

import ast
import glob
import os
import re

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.ordm_config import resolve

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LABOR = os.path.join(REPO, "canonical-core", "labor")
TABLES = [
    "employee",
    "employee_skill",
    "employee_availability",
    "employee_store_eligibility",
    "labor_schedule",
    "labor_actuals",
]
GENERATOR = os.path.join(REPO, "runtime", "synthetic-data", "generators", "labor.py")
CHECKS = os.path.join(LABOR, "checks.sql")

COMMENT_LINE = re.compile(r"^\s*([a-z][a-z0-9_]*)\s+[A-Za-z].*?COMMENT\s+'([^']*)'")
ALLOWED_VALUES = re.compile(r"Allowed values:\s*([^.]+)\.")


# ---------- helpers ----------

def _ddl_text(table):
    raw = open(os.path.join(LABOR, "tables", f"{table}.sql")).read()
    return resolve(raw, "c")  # ${catalog}/${labor_schema} -> real identifiers


def _ddl_columns(table):
    """Ordered column names from the CREATE TABLE (excludes the IDENTITY *_sk)."""
    create = next(s for s in sqlglot.parse(_ddl_text(table), read="databricks", error_level="ignore")
                  if isinstance(s, E.Create))
    cols = [c.name for c in create.find_all(E.ColumnDef)]
    return [c for c in cols if c != f"{table}_sk"]


def _col_comments(table):
    """Map column -> COMMENT text. Handles same-line and next-line COMMENT forms."""
    out = {}
    pending_col = None
    col_start = re.compile(r"^\s*([a-z][a-z0-9_]*)\s+[A-Za-z]")
    comment_only = re.compile(r"^\s*COMMENT\s+'([^']*)'")
    for line in _ddl_text(table).splitlines():
        m = COMMENT_LINE.match(line)
        if m:
            out[m.group(1)] = m.group(2)
            pending_col = None
            continue
        cm = comment_only.match(line)
        if cm and pending_col:
            out[pending_col] = cm.group(1)
            pending_col = None
            continue
        cs = col_start.match(line)
        if cs:
            # New column; keep pending until its COMMENT arrives (possibly next line).
            pending_col = cs.group(1)
    return out


def _generator_constants():
    """Module-level list[str] constants in the generator (read via AST, no import)."""
    mod = ast.parse(open(GENERATOR).read())
    out = {}
    for node in mod.body:
        if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name) \
                and isinstance(node.value, ast.List):
            elts = node.value.elts
            if all(isinstance(e, ast.Constant) for e in elts):
                out[node.targets[0].id] = [e.value for e in elts]
    return out


# Generator constant feeding each closed-enum (Allowed values) column.
ENUM_COLUMN_TO_CONST = {
    ("employee", "primary_role_code"): "PRIMARY_ROLE_CODES",
    ("employee", "employment_status"): "EMPLOYMENT_STATUS",
    ("employee", "employment_type"): "EMPLOYMENT_TYPES",
    ("employee_skill", "skill_code"): "SKILL_CODES",
    ("employee_skill", "proficiency_level"): "PROFICIENCY_LEVELS",
    ("employee_availability", "availability_type"): "AVAILABILITY_TYPES",
    ("labor_schedule", "role_code"): "ROLE_CODES",
    ("labor_schedule", "schedule_status"): "SCHEDULE_STATUS",
    ("labor_schedule", "schedule_source"): "SCHEDULE_SOURCES",
    ("labor_actuals", "role_code"): "ROLE_CODES",
    ("labor_actuals", "actuals_status"): "ACTUALS_STATUS",
}

TABLE_TO_COLUMNS_CONST = {
    "employee": "EMPLOYEE_COLUMNS",
    "employee_skill": "EMPLOYEE_SKILL_COLUMNS",
    "employee_availability": "EMPLOYEE_AVAILABILITY_COLUMNS",
    "employee_store_eligibility": "EMPLOYEE_STORE_ELIGIBILITY_COLUMNS",
    "labor_schedule": "LABOR_SCHEDULE_COLUMNS",
    "labor_actuals": "LABOR_ACTUALS_COLUMNS",
}


# ---------- DDL ----------

@pytest.mark.parametrize("table", TABLES)
def test_ddl_parses_as_create(table):
    create = next((s for s in sqlglot.parse(_ddl_text(table), read="databricks", error_level="ignore")
                   if isinstance(s, E.Create)), None)
    assert create is not None, f"{table}.sql did not parse as a CREATE TABLE"


@pytest.mark.parametrize("table", TABLES)
def test_ddl_has_surrogate_pk_and_business_key(table):
    cols = set(_ddl_columns(table)) | {f"{table}_sk"}
    assert f"{table}_sk" in cols, f"{table} missing surrogate key"
    assert f"{table}_id" in cols, f"{table} missing business key"


# ---------- generator <-> DDL ----------

@pytest.mark.parametrize("table", TABLES)
def test_generator_columns_match_ddl(table):
    consts = _generator_constants()
    name = TABLE_TO_COLUMNS_CONST[table]
    gen = set(consts[name])
    ddl = set(_ddl_columns(table))
    assert gen == ddl, (f"{table} column drift — "
                        f"missing={sorted(ddl - gen)} extra={sorted(gen - ddl)}")


@pytest.mark.parametrize("key", list(ENUM_COLUMN_TO_CONST))
def test_generator_enum_within_ddl_domain(key):
    table, column = key
    consts = _generator_constants()
    gen_vals = set(consts[ENUM_COLUMN_TO_CONST[key]])
    comment = _col_comments(table).get(column, "")
    m = ALLOWED_VALUES.search(comment)
    assert m, f"{table}.{column} DDL comment has no 'Allowed values:' enum"
    ddl_vals = {v.strip() for v in m.group(1).split(",")}
    assert gen_vals <= ddl_vals, (f"{table}.{column}: generator produces values "
                                  f"outside the DDL enum: {sorted(gen_vals - ddl_vals)}")


# ---------- data-quality checks ----------

def _parse_checks(text):
    header = re.compile(r"^--\s*check:\s*(\w+)\s*\|\s*severity:\s*(error|warn|metric)\s*$", re.I)
    checks, current, buf = [], None, []
    for line in text.splitlines():
        m = header.match(line.strip())
        if m:
            current, buf = (m.group(1), m.group(2).lower()), []
            continue
        if current is None or line.strip().startswith("--"):
            continue
        buf.append(line)
        if ";" in line:
            checks.append((current[0], current[1], "\n".join(buf).rstrip().rstrip(";")))
            current, buf = None, []
    return checks


def test_dq_checks_well_formed():
    checks = _parse_checks(open(CHECKS).read())
    assert len(checks) >= 15, f"expected a meaningful suite, found {len(checks)} checks"
    names = [c[0] for c in checks]
    assert len(names) == len(set(names)), "duplicate check names"
    for name, severity, query in checks:
        assert severity in ("error", "warn", "metric")
        assert "${catalog}.${labor_schema}." in query, f"{name} does not use the catalog/schema tokens"


def test_dq_checks_reference_known_tables():
    text = open(CHECKS).read()
    refs = set(re.findall(r"\$\{catalog\}\.\$\{labor_schema\}\.(\w+)", text))
    assert refs <= set(TABLES), f"checks reference unknown tables: {sorted(refs - set(TABLES))}"


@pytest.mark.parametrize("table", TABLES)
def test_every_table_has_a_check(table):
    text = open(CHECKS).read()
    assert f"${{catalog}}.${{labor_schema}}.{table}" in text, f"no DQ check covers {table}"


# ---------- guardrails ----------

AUTHORED_DIRS = [
    os.path.join(REPO, "canonical-core", "labor"),
]


def _authored_files(exts):
    files = []
    for d in AUTHORED_DIRS:
        for ext in exts:
            files += glob.glob(os.path.join(d, "**", f"*.{ext}"), recursive=True)
    # Also cover the labor generator.
    files.append(GENERATOR)
    return [f for f in files if os.path.isfile(f)]


def test_no_hardcoded_catalog_or_workspace():
    bad = []
    for f in _authored_files(["sql", "py", "yaml", "yml", "md"]):
        txt = open(f).read()
        if re.search(r"https?://[\w.-]*databricks", txt) or "retail_prod" in txt or "retail_dev" in txt:
            bad.append(os.path.relpath(f, REPO))
    assert not bad, f"hardcoded catalog/workspace in: {bad}"


def test_no_license_headers():
    pat = re.compile(r"Copyright|SPDX-License|Licensed under|All rights reserved", re.I)
    bad = [os.path.relpath(f, REPO) for f in _authored_files(["sql", "py", "md", "yaml", "yml"])
           if pat.search(open(f).read())]
    assert not bad, f"license/copyright header present (guardrail #4): {bad}"


def test_no_banned_sql_patterns():
    pat = re.compile(r"GROUP\s+BY\s+ALL|\b1\s*=\s*1\b", re.I)
    bad = [os.path.relpath(f, REPO) for f in _authored_files(["sql"]) if pat.search(open(f).read())]
    assert not bad, f"banned SQL pattern (guardrail #5): {bad}"
