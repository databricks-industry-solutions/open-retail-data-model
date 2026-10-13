"""Guard: no subquery predicate inside a JOIN's ON clause that Databricks rejects at query time.

Why: Databricks rejects a correlated subquery in a join predicate that references both join inputs
(UNSUPPORTED_CORRELATED_EXPRESSION_IN_JOIN_CONDITION), and it does so only when the query is
planned, not at CREATE VIEW. gold_supplier_media_report shipped that shape: the deploy created the
view, so every gate stayed green, while every read of it failed. Express such a rule as an
anti-join (LEFT JOIN + IS NULL in WHERE) or a semi-join in a CTE instead.

Flagged inside a JOIN ... ON: EXISTS (...), IN (SELECT ...), and a scalar subquery that is
correlated (references a column qualified by a table the subquery does not itself define).
An uncorrelated scalar subquery (e.g. "= (SELECT MAX(d) FROM t)") is allowed.

Metric views are checked too: their YAML `source:` query is extracted and parsed. In files that
carry queries (gold/, metric-views/, sample-queries.sql, notebook-templates/), a statement the
parser cannot read is reported as unchecked rather than silently passed.

Cluster-free: parses every committed .sql file with sqlglot; no Spark / workspace.
"""
import glob
import logging
import os
import re

import pytest
import sqlglot
import yaml
from sqlglot import exp

logging.getLogger("sqlglot").setLevel(logging.ERROR)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
_SKIP = (os.path.join(REPO, "explorer") + os.sep,)
_METRIC_VIEW = re.compile(r"WITH\s+METRICS\s+LANGUAGE\s+YAML\s+AS\s*\$\$(.*?)\$\$", re.I | re.S)


def _sql_files():
    for f in sorted(glob.glob(os.path.join(REPO, "**", "*.sql"), recursive=True)):
        if not f.startswith(_SKIP):
            yield f


def _carries_queries(path):
    rel = os.path.relpath(path, REPO).replace(os.sep, "/")
    return ("/gold/" in rel or "/metric-views/" in rel or "/notebook-templates/" in rel
            or rel.endswith("sample-queries.sql"))


def _strip_comments_and_strings(sql):
    sql = re.sub(r"'(?:[^']|'')*'", "''", sql)
    return re.sub(r"--[^\n]*", "", sql)


def _parse(sql):
    return [t for t in sqlglot.parse(sql, dialect="databricks", error_level=sqlglot.ErrorLevel.IGNORE)
            if t is not None]


def _trees(path):
    """(trees, unchecked): parsed statements, plus statements that carry a query but can't be read."""
    text = re.sub(r"\$\{(\w+)\}", r"\1", open(path).read())
    trees, unchecked = [], []
    metric_views = iter(_METRIC_VIEW.findall(text))
    for tree in _parse(text):
        if not isinstance(tree, exp.Command):
            trees.append(tree)
            continue
        raw = tree.sql(dialect="databricks")
        if re.search(r"WITH\s+METRICS", raw, re.I):
            body = next(metric_views, None)
            source = str((yaml.safe_load(body) or {}).get("source", "")).strip() if body else ""
            if re.match(r"(SELECT|WITH)\b", source, re.I):
                parsed = [t for t in _parse(source) if not isinstance(t, exp.Command)]
                if parsed:
                    trees.extend(parsed)
                else:
                    unchecked.append("metric-view source query")
        elif re.search(r"\bJOIN\b", _strip_comments_and_strings(raw), re.I):
            unchecked.append(raw[:80].replace("\n", " "))
    return trees, unchecked


def _defined_aliases(select):
    names = set()
    for t in select.find_all(exp.Table):
        names.add((t.alias_or_name or "").lower())
    for cte in select.find_all(exp.CTE):
        names.add((cte.alias_or_name or "").lower())
    for sub in select.find_all(exp.Subquery):
        if sub.alias:
            names.add(sub.alias.lower())
    return names


def _is_correlated(subquery):
    inner = subquery.this if isinstance(subquery, exp.Subquery) else subquery
    defined = _defined_aliases(inner)
    return any(c.table and c.table.lower() not in defined for c in inner.find_all(exp.Column))


def _join_problems(tree):
    hits = []
    for join in tree.find_all(exp.Join):
        on = join.args.get("on")
        if on is None:
            continue
        bad = any(not isinstance(n, exp.In) or n.args.get("query") for n in on.find_all(exp.Exists, exp.In))
        if not bad:
            bad = any(_is_correlated(s) for s in on.find_all(exp.Subquery)
                      if not isinstance(s.parent, (exp.Exists, exp.In)))
        if bad:
            hits.append(join.sql(dialect="databricks")[:120])
    return hits


def test_no_subquery_predicate_in_join_condition():
    offenders, unchecked = {}, {}
    for f in _sql_files():
        trees, cant_read = _trees(f)
        rel = os.path.relpath(f, REPO)
        hits = [h for t in trees for h in _join_problems(t)]
        if hits:
            offenders[rel] = hits
        if cant_read and _carries_queries(f):
            unchecked[rel] = cant_read
    assert not offenders, (
        "EXISTS / IN-subquery / correlated scalar subquery inside JOIN ... ON is not allowed in "
        "ORDM SQL (Databricks rejects the correlated forms at query time with "
        "UNSUPPORTED_CORRELATED_EXPRESSION_IN_JOIN_CONDITION); rewrite it as an anti-join or "
        f"semi-join:\n{offenders}")
    assert not unchecked, f"statements with joins that this guard could not parse (unchecked):\n{unchecked}"


@pytest.mark.parametrize("sql,flagged", [
    # the pre-fix gold_supplier_media_report predicate, reduced
    ("SELECT 1 FROM r JOIN e ON e.a = r.a AND NOT (e.c IS NULL AND EXISTS "
     "(SELECT 1 FROM e e2 WHERE e2.p = e.p AND e2.c = r.c))", True),
    ("SELECT 1 FROM r JOIN e ON e.a = r.a AND e.c IN (SELECT c FROM x)", True),
    ("SELECT 1 FROM r JOIN e ON e.a = r.a AND e.d = (SELECT MAX(d) FROM x WHERE x.k = r.k)", True),
    ("SELECT 1 FROM r JOIN e ON e.a = r.a AND e.d = (SELECT MAX(d) FROM x)", False),
    ("SELECT 1 FROM r LEFT JOIN e ON e.a = r.a WHERE e.a IS NULL", False),
])
def test_guard_classifies_join_predicates(sql, flagged):
    tree = sqlglot.parse_one(sql, dialect="databricks")
    assert bool(_join_problems(tree)) is flagged
