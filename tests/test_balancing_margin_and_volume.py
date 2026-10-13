"""Tests for the Balancing Margin and Volume (BMV) outcome package.

Static contract tests to ensure the DDL definitions and the synthetic data
generator stay mutually consistent.
"""

import ast
import os

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.ordm_config import resolve

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GENERATOR = os.path.join(REPO, "runtime", "synthetic-data", "generators", "balancing_margin_and_volume.py")

# table -> (ddl path, surrogate key, generator *_COLUMNS constant)
TABLES = {
    "competitor": ("outcome-packages/balancing-margin-and-volume/tables/competitor.sql", "competitor_sk", "COMPETITOR_COLUMNS"),
    "product_relationship": ("outcome-packages/balancing-margin-and-volume/tables/product_relationship.sql", "product_relationship_sk", "PRODUCT_RELATIONSHIP_COLUMNS"),
    "competitor_price": ("outcome-packages/balancing-margin-and-volume/tables/competitor_price.sql", "competitor_price_sk", "COMPETITOR_PRICE_COLUMNS"),
    "planogram": ("outcome-packages/balancing-margin-and-volume/tables/planogram.sql", "planogram_sk", "PLANOGRAM_COLUMNS"),
}

def _detok(text):
    return resolve(text, "ordm")

def _ddl(table):
    return _detok(open(os.path.join(REPO, TABLES[table][0])).read())

def _ddl_columns(table):
    create = next(s for s in sqlglot.parse(_ddl(table), read="databricks", error_level="ignore")
                  if isinstance(s, E.Create))
    sk = TABLES[table][1]
    return [c.name for c in create.find_all(E.ColumnDef) if c.name != sk]

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
