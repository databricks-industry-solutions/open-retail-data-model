"""Every column a UC Metric View's `source:` query reads must exist in the table or view
it reads it from, and every field/measure must only use columns the source exposes.

A metric view whose source names a column that is not there still parses, still
passes the YAML checks and still regenerates its ODCS contract; it only fails at
CREATE time on the workspace (UNRESOLVED_COLUMN). These static checks catch that
class before deploy, for every metric view in the repo. No Spark required.

Resolution: a qualified reference `alias.column` is checked when `alias` is bound to a
physical ORDM table or gold view (found by name under canonical-core/*/tables,
outcome-packages/*/tables and outcome-packages/*/gold). References through CTEs or
subqueries, and views whose columns cannot be read statically, are skipped rather
than guessed.
"""
import glob
import os
import re

import pytest
import sqlglot
import sqlglot.expressions as E
import yaml

from tools.ordm_config import resolve

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
METRIC_VIEWS = sorted(glob.glob(os.path.join(REPO, "outcome-packages", "*", "metric-views", "*.sql")))


def _physical_files():
    out = {}
    for pattern in ("canonical-core/*/tables/*.sql", "outcome-packages/*/tables/*.sql", "outcome-packages/*/gold/*.sql"):
        for path in glob.glob(os.path.join(REPO, pattern)):
            out[os.path.splitext(os.path.basename(path))[0]] = path
    return out


PHYSICAL = _physical_files()
_COLUMN_CACHE = {}


def _columns_of(table):
    """Column names of an ORDM table (DDL) or gold view (SELECT list), or None if unknown."""
    if table in _COLUMN_CACHE:
        return _COLUMN_CACHE[table]
    cols = None
    path = PHYSICAL.get(table)
    if path:
        for stmt in sqlglot.parse(resolve(open(path).read(), "ordm"), read="databricks", error_level="ignore"):
            if isinstance(stmt, E.Create) and stmt.this and stmt.this.find(E.Table) is not None \
                    and stmt.this.find(E.Table).name == table:
                if stmt.kind == "TABLE":
                    cols = {c.name for c in stmt.find_all(E.ColumnDef)}
                elif isinstance(stmt.expression, E.Query):
                    names = stmt.expression.named_selects
                    cols = None if "*" in names or not names else set(names)
                break
    _COLUMN_CACHE[table] = cols
    return cols


def _doc(path):
    m = re.search(r"WITH\s+METRICS\s+LANGUAGE\s+YAML\s+AS\s*\$\$(.*?)\$\$", open(path).read(), re.I | re.S)
    assert m, f"{os.path.basename(path)} has no metric-view YAML body"
    return yaml.safe_load(m.group(1))


def _source_query(doc):
    return sqlglot.parse_one(resolve(doc["source"], "ordm"), read="databricks")


@pytest.mark.parametrize("path", METRIC_VIEWS, ids=lambda p: os.path.relpath(p, REPO))
def test_source_columns_exist_in_the_tables_read(path):
    query = _source_query(_doc(path))
    problems = []
    for select in query.find_all(E.Select):
        aliases = {}
        for tbl in select.find_all(E.Table):
            if tbl.find_ancestor(E.Select) is not select:
                continue
            aliases[tbl.alias_or_name] = tbl.name
        for col in select.find_all(E.Column):
            if col.find_ancestor(E.Select) is not select or not col.table:
                continue
            table = aliases.get(col.table)
            known = _columns_of(table) if table else None
            if known is not None and col.name not in known:
                problems.append(f"{col.table}.{col.name} (not a column of {table})")
    assert not problems, f"{os.path.relpath(path, REPO)} source reads missing columns: {sorted(set(problems))}"


@pytest.mark.parametrize("path", METRIC_VIEWS, ids=lambda p: os.path.relpath(p, REPO))
def test_fields_and_measures_use_source_columns(path):
    doc = _doc(path)
    query = _source_query(doc)
    if isinstance(query, E.Query):
        exposed = set(query.named_selects)
    else:
        # `source:` names a table or view directly (catalog.schema.name).
        exposed = _columns_of(str(doc["source"]).strip().split(".")[-1]) or set()
    if "*" in exposed or not exposed:
        pytest.skip("source exposes * or no static column list")
    missing = set()
    for item in [*doc.get("fields", []), *doc.get("dimensions", []), *doc.get("measures", [])]:
        expr = str(item.get("expr", "")).strip()
        if not expr:
            continue
        for col in sqlglot.parse_one(expr, read="databricks").find_all(E.Column):
            if not col.table and col.name not in exposed:
                missing.add(col.name)
    assert not missing, f"{os.path.relpath(path, REPO)} fields/measures use columns the source does not expose: {sorted(missing)}"



def _package_of(path):
    return os.path.relpath(path, REPO).split(os.sep)[1]


# Metric views added with the "governed KPIs for every use case" change. Older views
# predate this rule (some intentionally repeat a measure across views of one package).
NEW_VIEWS = [
    "agentic-commerce/metric-views/intent_discovery_result_performance.sql",
    "agentic-commerce/metric-views/intent_discovery_intents.sql",
    "agentic-commerce/metric-views/conversational_shopping_session.sql",
    "unified-customer-view/metric-views/customer_360.sql",
    "unified-customer-view/metric-views/cdp_activation_eligibility.sql",
    "unified-customer-view/metric-views/cdp_activation_jobs.sql",
    "unified-customer-view/metric-views/cdp_campaign_touch.sql",
    "actionable-customer-understanding/metric-views/customer_lifetime_value.sql",
    "data-sharing-with-suppliers/metric-views/category_growth.sql",
]


@pytest.mark.parametrize("rel", NEW_VIEWS)
def test_new_view_names_and_synonyms_do_not_collide_within_its_package(rel):
    # A new view must not offer a measure name or synonym that another metric view of the
    # same package already uses for a different definition (e.g. a session-grain and a
    # result-grain add-to-cart rate), or Genie / AI-BI cannot tell which one is meant.
    path = os.path.join(REPO, "outcome-packages", rel)
    package = _package_of(path)
    mine = _doc(path).get("measures", [])
    clashes = []
    for other in (p for p in METRIC_VIEWS if _package_of(p) == package and p != path):
        theirs = _doc(other).get("measures", [])
        names = {m["name"] for m in theirs}
        syns = {s for m in theirs for s in (m.get("synonyms") or [])} | names
        for m in mine:
            if m["name"] in names:
                clashes.append(f"measure {m['name']!r} also in {os.path.basename(other)}")
            for syn in m.get("synonyms") or []:
                if syn in syns:
                    clashes.append(f"synonym {syn!r} of {m['name']} also in {os.path.basename(other)}")
    assert not clashes, clashes
