"""Tests for the Inventory domain.

Static contract tests (no engine) keep the DDL and generator mutually consistent.
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
GENERATOR = os.path.join(REPO, "runtime", "synthetic-data", "generators", "inventory.py")

TABLES = {
    "inventory_position": ("canonical-core/inventory/tables/inventory_position.sql", "inventory_position_sk", "INVENTORY_POSITION_COLUMNS"),
}
COMMENT_LINE = re.compile(r"^\s*([a-z][a-z0-9_]*)\s+[A-Za-z].*?COMMENT\s+'([^']*)'")
ALLOWED_VALUES = re.compile(r"Allowed values:\s*([^.]+)\.")


def _detok(text):
    return resolve(text, "ordm")

def _ddl(table):
    return _detok(open(os.path.join(REPO, TABLES[table][0])).read())

def _ddl_columns(table):
    create = next(s for s in sqlglot.parse(_ddl(table), read="databricks", error_level="ignore")
                  if isinstance(s, E.Create))
    sk = TABLES[table][1]
    return [c.name for c in create.find_all(E.ColumnDef) if c.name != sk]

def _col_comments(table):
    out = {}
    for line in _ddl(table).splitlines():
        m = COMMENT_LINE.match(line)
        if m:
            out[m.group(1)] = m.group(2)
    return out

def _generator_constants():
    mod = ast.parse(open(GENERATOR).read())
    out = {}
    for node in mod.body:
        if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name) \
                and isinstance(node.value, ast.List) \
                and all(isinstance(e, ast.Constant) for e in node.value.elts):
            out[node.targets[0].id] = [e.value for e in node.value.elts]
    return out


@pytest.mark.parametrize("table", list(TABLES))
def test_ddl_parses_as_create(table):
    create = next((s for s in sqlglot.parse(_ddl(table), read="databricks", error_level="ignore")
                   if isinstance(s, E.Create)), None)
    assert create is not None, f"{table} did not parse as CREATE TABLE"


@pytest.mark.parametrize("table", list(TABLES))
def test_generator_columns_match_ddl(table):
    gen = set(_generator_constants()[TABLES[table][2]])
    ddl = set(_ddl_columns(table))
    assert gen == ddl, f"{table} drift — missing={sorted(ddl - gen)} extra={sorted(gen - ddl)}"
