# ============================================================
# ORDM · Optional integration · ODCS data-contract generator
# ============================================================
# Emits an Open Data Contract Standard (ODCS) v3.1.0 YAML per canonical-core
# domain and per outcome package, DERIVED from the committed artifacts that are
# ORDM's source of truth — the DDL (tables/*.sql, gold/*.sql), UC Metric Views
# (metric-views/*.sql), relationships.sql (FK + CHECK), checks.sql (data-quality
# assertions), comments.sql and glossary.md. Nothing here is hand-authored and nothing in ORDM depends on it:
# ODCS is an OPTIONAL integration path (adoption is still niche), so the model
# stays fully usable without ever running this. See docs/odcs-integration.md.
#
# What maps to what (ODCS v3.1.0, Bitol / Linux Foundation):
#   DDL CREATE TABLE / gold view      -> schema[]  (one object per table/view)
#   metric-views/*.sql (UC Metric View) -> schema[] view object tagged `metric-view`;
#                                        YAML fields + measures -> properties[]
#                                        (logicalType only, no physicalType; typed
#                                        from the YAML `source:`); YAML
#                                        top-level `comment:` -> object description
#   columns + types + NOT NULL        -> schema[].properties[] (logicalType /
#                                        physicalType / required)
#   CONSTRAINT ... PRIMARY KEY (col)  -> property.primaryKey / primaryKeyPosition
#   column COMMENT '...' / comments.sql -> property.description
#   dbx_pii_* column tags             -> property.classification + tags
#   relationships.sql FOREIGN KEY     -> property.relationships[] (type foreignKey)
#   relationships.sql CHECK (enum)    -> property-level quality rule (type: text)
#   checks.sql `-- check:` + SELECT   -> object-level quality rule (type: sql)
#   glossary.md / data-model-standards -> authoritativeDefinitions[] (repo links)
#
# The catalog/schema is NEVER hardcoded: tokens are resolved via the shared
# tools.ordm_config resolver (reads databricks.yml), exactly like
# tools/apply_model_ddl.py. `--catalog` sets the physicalName catalog; schema
# names come from the databricks.yml `variables` defaults (overridable per token).
#
# Downstream (all OPTIONAL, none required by ORDM): the generated YAML can be
# executed/enforced by DQX (databrickslabs/dqx), synced to Unity Catalog by
# Lockstep, or presented as data products by Ontos (databrickslabs/ontos).
#
# Pure stdlib + PyYAML (no Spark, no SDK) so it runs anywhere, including CI.
#
# Usage:
#   python tools/generate_odcs.py                      # all domains + packages -> contracts/odcs/
#   python tools/generate_odcs.py --catalog retail_prod
#   python tools/generate_odcs.py --include customer,product
#   python tools/generate_odcs.py --domain customer --out -   # single, to stdout
# ============================================================
from __future__ import annotations

import argparse
import glob
import os
import re
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)
from tools.ordm_config import schema_defaults  # noqa: E402

ODCS_API_VERSION = "v3.1.0"
DEFAULT_OUT_DIR = os.path.join(REPO_ROOT, "contracts", "odcs")


# ============================================================
# DDL parsing — imported from the canonical home: tools.ordm_ddl.parser.
# These names are re-exported at module level so `from tools.generate_odcs import
# parse_columns` etc. continue to resolve for callers that import them directly.
# ============================================================
from tools.ordm_ddl.parser import (  # noqa: E402
    _read,
    build_gold_sql,
    build_silver_schema,
    _unquote,
    _split_top_level,
    _strip_line_comments,
    _balanced_body,
    parse_columns,
    parse_table_sql,
    _leading_header_comment,
    _column_pii_tags,
    _check_col,
    parse_relationships,
    parse_checks,
    parse_comments,
    _sqlglot_view_columns,
    union_gold_column_names,
    infer_all_gold_types,
    infer_gold_column_types,
    _resolve_schema,
    _resolve_query,
)

CANONICAL_CORE = os.path.join(REPO_ROOT, "canonical-core")
OUTCOME_PACKAGES = os.path.join(REPO_ROOT, "outcome-packages")

# ------------------------------------------------------------
# SQL type -> ODCS logicalType. ODCS v3.1.0 logicalTypes are a closed set: string, date,
# timestamp, time, number, integer, object, array, boolean (bitol-io
# odcs-json-schema-v3.1.0.json). For tables and gold views the SQL type is also kept verbatim
# as physicalType; metric-view columns carry logicalType only, so it must be one of these.
# ------------------------------------------------------------
_LOGICAL_BY_PREFIX = [
    ("BIGINT", "integer"), ("INT", "integer"), ("SMALLINT", "integer"),
    ("TINYINT", "integer"), ("LONG", "integer"),
    ("DECIMAL", "number"), ("NUMERIC", "number"), ("DOUBLE", "number"),
    ("FLOAT", "number"), ("REAL", "number"),
    ("BOOLEAN", "boolean"),
    ("TIMESTAMP", "timestamp"), ("DATE", "date"),
    ("STRING", "string"), ("VARCHAR", "string"), ("CHAR", "string"),
    ("BINARY", "string"),
    ("ARRAY", "array"), ("MAP", "object"), ("STRUCT", "object"),
]

# dbx_pii* column tag -> ODCS classification. ORDM tags PII at column level
# (principle #11); ODCS carries a free-form `classification` + tags per property.
_PII_TAG_RE = re.compile(r"dbx_pii\w*", re.IGNORECASE)


def _logical_type(sql_type: str) -> str:
    t = sql_type.strip().upper()
    for prefix, logical in _LOGICAL_BY_PREFIX:
        if t.startswith(prefix):
            return logical
    return "string"


# UC Metric View column extraction. A metric view is
# `CREATE ... VIEW ... WITH METRICS LANGUAGE YAML AS $$ <yaml> $$`; its columns are the YAML
# `fields` (dimensions) + `measures`, NOT a SELECT projection — sqlglot degrades that DDL to a
# Command and returns 0 columns. We read them from the YAML so the contract carries the
# semantic layer's real column set, typed. Types are inferred from the YAML `source:` (see
# _metric_view_inferred_types); where that cannot resolve, an explicit `format.type` applies.
# Failing both, a measure is still a numeric aggregation (logicalType number), but a field is
# left UNTYPED rather than guessed: a guessed `string` would be confidently wrong for a date key
# whose upstream type is unknown, and gold-view columns that cannot be resolved are likewise
# emitted without a type. Metric-view columns are COMPUTED — they have no physical DDL type — so
# only logicalType is emitted (never physicalType).
_METRIC_FORMAT_LOGICAL = {"number": "number", "percentage": "number",
                          "date": "date", "timestamp": "timestamp", "string": "string"}


def _metric_format_logical(fmt, default: str | None) -> str | None:
    if isinstance(fmt, dict):
        return _METRIC_FORMAT_LOGICAL.get(str(fmt.get("type", "")).lower(), default)
    return default


def _metric_view_yaml(sql: str) -> dict | None:
    """The parsed `WITH METRICS LANGUAGE YAML AS $$ ... $$` body of a UC Metric View, or None
    if the body is missing, unparseable, or not a mapping."""
    import yaml
    m = re.search(r"LANGUAGE\s+YAML\s+AS\s*\$\$(.*?)\$\$", sql, re.S | re.I)
    if not m:
        return None
    try:
        body = yaml.safe_load(m.group(1))
    except yaml.YAMLError:
        return None
    return body if isinstance(body, dict) else None


def _metric_view_description(sql: str, banner: str | None) -> str | None:
    """Object-level description for a metric view: the authored YAML top-level `comment:`
    (which carries the grain / double-count caveats), falling back to the SQL header banner
    only when the YAML has none. The banner alone is a generic 'Metric View: <name>' line
    (and can concatenate unrelated banner lines), so it is never preferred."""
    comment = ((_metric_view_yaml(sql) or {}).get("comment") or "").strip()
    return comment or banner


def _metric_view_columns(sql: str, type_schema: dict | None = None) -> list[dict]:
    """Columns of a UC Metric View, read from its `WITH METRICS LANGUAGE YAML` body:
    `fields` (dimensions) then `measures`, in that order. Each column carries a logical_type
    (from the source query, else an explicit `format.type`, else number for a measure and none
    for a field)
    and the YAML `comment` as its description. Returns [] if the body is missing/unparseable.

    Names are de-duplicated across fields AND measures, with the FIRST occurrence winning, so a
    field wins over a same-named measure. That collision is an authoring error in a UC Metric
    View (dimensions and measures should have distinct names), so it is reported on stderr
    rather than dropped silently."""
    body = _metric_view_yaml(sql)
    if not body:
        return []
    cols, seen = [], {}
    for kind, default in (("fields", None), ("measures", "number")):
        for item in (body.get(kind) or []):
            nm = item.get("name") if isinstance(item, dict) else None
            if not nm:
                continue
            if nm in seen:
                if seen[nm] != kind:
                    print(f"[ordm-odcs] metric view column '{nm}' is declared as both a "
                          f"{seen[nm][:-1]} and a {kind[:-1]}; keeping the {seen[nm][:-1]}",
                          file=sys.stderr)
                continue
            seen[nm] = kind
            col = {"name": nm, "comment": (item.get("comment") or ""),
                   "logical_type": _metric_format_logical(item.get("format"), default)}
            # Agent metadata a Genie-style consumer resolves terms with: display_name maps to
            # the ODCS property businessName, synonyms to a `synonyms` customProperty.
            if item.get("display_name"):
                col["business_name"] = str(item["display_name"])
            syn = item.get("synonyms")
            if isinstance(syn, list) and syn:
                col["synonyms"] = [str(x) for x in syn]
            cols.append(col)
    # Prefer the column's COMPUTED type, inferred from the metric view's `source:` with the same
    # sqlglot annotation gold views use. The YAML rarely declares format.type on a dimension, so
    # without this a date key (metric_date, date_key, trading_date ...) would ship as string.
    # Best effort: columns sqlglot cannot type keep the format.type / kind default above.
    if type_schema:
        inferred = _metric_view_inferred_types(body, type_schema)
        for c in cols:
            if inferred.get(c["name"]):
                c["logical_type"] = _logical_type(inferred[c["name"]])
    return cols


def _metric_view_inferred_types(body: dict, type_schema: dict) -> dict:
    """{column: SQL type} for a metric view's fields and measures, inferred by annotating a
    synthetic `SELECT <expr> AS <name>, ... FROM <source>` against the silver + gold schema.
    `source` is either a SQL query (wrapped as a subquery) or a table/view reference. Tries all
    columns in one pass, then retries each column still untyped on its own, so a single
    unresolvable expression does not lose the rest. Returns {} when nothing resolves."""
    src = body.get("source")
    if not isinstance(src, str) or not src.strip():
        return {}
    src = src.strip().rstrip(";")
    from_sql = f"({src}) AS ordm_src" if re.search(r"\bselect\b", src, re.I) else src
    items = []
    for kind in ("fields", "measures"):
        for item in (body.get(kind) or []):
            if isinstance(item, dict) and item.get("name") and item.get("expr"):
                items.append((str(item["name"]), str(item["expr"])))
    if not items:
        return {}

    def run(pairs):
        cols = ", ".join(f"{e} AS `{n}`" for n, e in pairs)
        return infer_gold_column_types(f"SELECT {cols} FROM {from_sql}", type_schema)

    out = run(items)
    # Retry, one column at a time, any column the combined pass left untyped (all of them when
    # the combined query failed outright), so one bad expression cannot cost the others a type.
    for n, e in items:
        if n not in out:
            out.update(run([(n, e)]))
    return out


# ============================================================
# Contract assembly
# ============================================================

def _property(col: dict, pk_cols: list[str], tags_map: dict) -> dict:
    prop = {"name": col["name"]}
    # Base-table columns carry an sql_type from the DDL. Gold-view columns get one from
    # sqlglot type inference (build_contract) where the SELECT projection resolves against
    # the silver schema; where it doesn't, sql_type is absent and type/required are omitted.
    sql_type = col.get("sql_type")
    if sql_type:
        prop["logicalType"] = _logical_type(sql_type)
        prop["physicalType"] = sql_type
    elif col.get("logical_type"):
        # A metric-view (UC Metric View) column: a computed dimension/measure whose logical
        # type is read from the YAML, but which has no physical DDL type — logicalType only.
        prop["logicalType"] = col["logical_type"]
    if col.get("business_name"):
        prop["businessName"] = col["business_name"]
    if col.get("synonyms"):
        prop["customProperties"] = [{"property": "synonyms", "value": col["synonyms"]}]
    if "required" in col:
        prop["required"] = bool(col["required"])
    if col["name"] in pk_cols:
        prop["primaryKey"] = True
        prop["primaryKeyPosition"] = pk_cols.index(col["name"]) + 1
        # A primary key is inherently non-nullable (ADR 0004 / PK-CONTRACT), even
        # though a `BIGINT GENERATED ALWAYS AS IDENTITY` surrogate carries no literal
        # NOT NULL token — so force required regardless of what the column parse found.
        prop["required"] = True
    if col.get("comment"):
        prop["description"] = col["comment"]
    pii = tags_map.get(col["name"])
    if pii:
        # PII -> restricted classification + the originating dbx tags (traceable).
        prop["classification"] = "restricted"
        prop["tags"] = sorted(set(pii))
    return prop


def _table_object(tbl: dict, catalog: str, overrides: dict,
                  rels: dict, checks: list[dict], view_cols: list[dict],
                  repo_links: list[dict]) -> dict:
    schema_name = _resolve_schema(tbl["schema_token"], overrides)
    physical = f"{catalog}.{schema_name}.{tbl['name']}" if catalog else f"{schema_name}.{tbl['name']}"

    obj: dict = {
        "name": tbl["name"],
        "physicalName": physical,
        "physicalType": "view" if tbl["kind"] == "view" else "table",
    }
    if tbl.get("comment"):
        obj["description"] = tbl["comment"]
    if tbl.get("role"):
        obj["tags"] = [tbl["role"]]
    if repo_links:
        obj["authoritativeDefinitions"] = repo_links

    pk_cols = tbl.get("primary_key", [])
    tags_map = tbl.get("column_tags", {})

    columns = tbl["columns"] if tbl["kind"] == "table" else view_cols
    props = []
    fk_by_col = {}
    for fk in rels.get("fks", {}).get(tbl["name"], []):
        # single-column FKs attach to the property; composite FKs go object-level.
        if len(fk["cols"]) == 1:
            fk_by_col[fk["cols"][0]] = fk
    check_by_col = {}
    for chk in rels.get("checks", {}).get(tbl["name"], []):
        if chk["col"]:
            check_by_col.setdefault(chk["col"], []).append(chk)

    for col in columns:
        prop = _property(col, pk_cols, tags_map)
        fk = fk_by_col.get(col["name"])
        if fk:
            parent_schema = _resolve_schema(fk["pschema"], overrides)
            prop["relationships"] = [{
                "to": f"{fk['parent']}.{fk['pcols'][0]}",
                "type": "foreignKey",
                "customProperties": [
                    {"property": "toSchema", "value": parent_schema},
                    {"property": "enforced", "value": False},  # UC FKs are informational
                ],
            }]
        for chk in check_by_col.get(col["name"], []):
            # Enum CHECK -> a per-property text quality rule listing the allowed set.
            prop.setdefault("quality", []).append({
                "type": "text",
                "dimension": "validity",
                "severity": "error",
                "description": f"Allowed values: {', '.join(chk['values'])}." if chk["values"]
                               else f"CHECK ({chk['expr']}).",
            })
        props.append(prop)
    if props:
        obj["properties"] = props

    # composite foreign keys -> object-level relationships[]
    composite = [fk for fk in rels.get("fks", {}).get(tbl["name"], []) if len(fk["cols"]) > 1]
    if composite:
        obj["relationships"] = []
        for fk in composite:
            obj["relationships"].append({
                "type": "foreignKey",
                "from": [f"{tbl['name']}.{c}" for c in fk["cols"]],
                "to": [f"{fk['parent']}.{c}" for c in fk["pcols"]],
            })

    # data-quality assertions (checks.sql) -> object-level SQL quality rules.
    obj_checks = [c for c in checks if c["table"] == tbl["name"]]
    if obj_checks:
        q = obj.setdefault("quality", [])
        for chk in obj_checks:
            is_metric = chk["severity"] == "metric"
            rule = {"name": chk["name"], "type": "sql", "dimension": "accuracy"}
            # `metric` checks SELECT an aggregate to REPORT (a rate, a distinct-count),
            # NOT violating rows — so they carry no zero-row assertion and are marked
            # informational (a DQX consumer reports them, it does not fail on them).
            # error/warn checks SELECT the VIOLATING rows, so a passing contract has 0.
            rule["severity"] = "info" if is_metric else ("error" if chk["severity"] == "error" else "warning")
            if not is_metric:
                rule["mustBe"] = 0
                rule["unit"] = "rows"
            rule["description"] = chk["description"] or chk["name"]
            rule["query"] = _resolve_query(chk["query"], catalog, overrides)
            q.append(rule)
    return obj


def _repo_links(rel_dir: str, has_glossary: bool) -> list[dict]:
    """authoritativeDefinitions pointing back at the repo artifacts (the true
    source). Kept as repo-relative paths so they resolve wherever ORDM is hosted."""
    rel_dir_posix = rel_dir.replace('\\', '/')
    links = [{
        "url": f"{rel_dir_posix}/README.md",
        "type": "businessDefinition",
    }]
    if has_glossary:
        links.append({"url": f"{rel_dir_posix}/glossary.md", "type": "businessDefinition"})
    links.append({"url": "docs/data-model-standards.md", "type": "businessDefinition"})
    return links


_TYPE_SCHEMA_CACHE: dict | None = None


def _default_type_schema() -> dict:
    """{table_or_view: {column: SQL type}} across every unit: silver tables plus gold views
    resolved to a fixpoint. Cached for the process, since it is expensive and identical for
    every contract."""
    global _TYPE_SCHEMA_CACHE
    if _TYPE_SCHEMA_CACHE is None:
        units = discover_units(None)
        silver = build_silver_schema(units)
        _TYPE_SCHEMA_CACHE = {**silver, **infer_all_gold_types(silver, build_gold_sql(units))}
    return _TYPE_SCHEMA_CACHE


def build_contract(unit_dir: str, catalog: str, overrides: dict,
                   gold_types: dict | None = None,
                   type_schema: dict | None = None) -> dict | None:
    """Assemble one ODCS v3.1.0 contract dict for a canonical-core domain or an
    outcome package directory, or None if it has no committed DDL.

    ``gold_types`` ({view_name: {column: display_type}}, pre-resolved across every
    unit incl. gold-on-gold dependencies) supplies the SQL type per gold-view column;
    omitted -> no gold-column types are emitted (names/descriptions still are)."""
    gold_types = gold_types or {}
    # silver + resolved gold column types, used to type metric-view columns from their
    # source query; computed once across every unit when the caller does not supply it.
    if type_schema is None:
        type_schema = _default_type_schema()
    rel_dir = os.path.relpath(unit_dir, REPO_ROOT)
    name = os.path.basename(unit_dir)
    is_core = os.path.dirname(unit_dir).endswith("canonical-core")
    kind_label = "canonical-core domain" if is_core else "outcome package"

    # Tables: canonical-core/<d>/tables/*.sql  and  outcome-packages/<p>/gold/*.sql
    table_sqls = sorted(glob.glob(os.path.join(unit_dir, "tables", "*.sql"))) + \
        sorted(glob.glob(os.path.join(unit_dir, "gold", "*.sql")))
    tables = []
    view_sql: dict[str, str] = {}  # view name -> its SQL (for the sqlglot column fallback)
    for path in table_sqls:
        sql = _read(path)
        parsed = parse_table_sql(sql)
        if parsed:
            tables.append(parsed)
            if parsed["kind"] == "view":
                view_sql[parsed["name"]] = sql
    if not tables:
        return None

    # relationships.sql (FK + enum CHECK), checks.sql (DQ), comments.sql (gold cols)
    rels = {"fks": {}, "checks": {}}
    rel_path = os.path.join(unit_dir, "relationships.sql")
    if os.path.isfile(rel_path):
        rels = parse_relationships(_read(rel_path))
    checks = []
    chk_path = os.path.join(unit_dir, "checks.sql")
    if os.path.isfile(chk_path):
        checks = parse_checks(_read(chk_path))
    view_comments = {}
    cmt_path = os.path.join(unit_dir, "comments.sql")
    if os.path.isfile(cmt_path):
        view_comments = parse_comments(_read(cmt_path))

    has_glossary = os.path.isfile(os.path.join(unit_dir, "glossary.md"))
    links = _repo_links(rel_dir, has_glossary)

    schema_objects = []
    for tbl in tables:
        view_cols = []
        if tbl["kind"] == "view":
            # A gold view's TRUE column set is its SELECT projection (sqlglot); comments.sql
            # supplies descriptions but often documents only SOME columns. UNION them - the
            # sqlglot projection in SELECT order, then any comments-only column - so NEITHER
            # source can silently DROP a projected column (comments-only dropped every
            # undocumented column, e.g. gold_trend_features projects 6, documents 2). Mirrors
            # DdlParser._gold_columns so the contract and the explorer model never diverge.
            desc = {c["name"]: c.get("comment", "") for c in view_comments.get(tbl["name"], [])}
            ordered = union_gold_column_names(
                _sqlglot_view_columns(view_sql.get(tbl["name"], "")),
                [c["name"] for c in view_comments.get(tbl["name"], [])],
            )
            view_cols = [{"name": n, "comment": desc.get(n, "")} for n in ordered]
            if not view_cols:
                print(f"[ordm-odcs] {name}: view '{tbl['name']}' resolved to 0 columns "
                      f"(no COMMENT ON COLUMN and sqlglot found no projection) - "
                      f"emitting columnless object", file=sys.stderr)
        if tbl["kind"] == "view" and view_cols:
            # Attach the pre-resolved SQL type per gold-view column (topological sqlglot
            # inference against the silver schema + sibling gold views) so the contract
            # carries logicalType/physicalType where resolvable — the same inference the
            # explorer model uses. Columns that don't resolve stay type-less rather than
            # guessing. A comments.sql-authored sql_type (if any) always wins.
            col_types = gold_types.get(tbl["name"], {})
            for vc in view_cols:
                if not vc.get("sql_type") and col_types.get(vc["name"]):
                    vc["sql_type"] = col_types[vc["name"]]
        schema_objects.append(
            _table_object(tbl, catalog, overrides, rels, checks, view_cols, links))

    # UC Metric Views (metric-views/*.sql): the semantic BI/Genie layer. Emitted as view
    # objects whose columns are the YAML fields+measures (see _metric_view_columns) — sqlglot
    # cannot read a WITH METRICS body, so they are parsed from the YAML, not a SELECT. Appended
    # AFTER the tables/gold objects so the addition is purely additive to existing contracts.
    metric_tbls = []
    for path in sorted(glob.glob(os.path.join(unit_dir, "metric-views", "*.sql"))):
        sql = _read(path)
        parsed = parse_table_sql(sql)
        if not parsed:
            continue
        mv = {"name": parsed["name"], "kind": "view",
              "schema_token": parsed["schema_token"],
              "comment": _metric_view_description(sql, parsed.get("comment")),
              "role": "metric-view", "primary_key": [], "column_tags": {}}
        mv_cols = _metric_view_columns(sql, type_schema)
        if not mv_cols:
            print(f"[ordm-odcs] {name}: metric view '{parsed['name']}' resolved to 0 columns "
                  f"(WITH METRICS YAML body missing or unparseable)", file=sys.stderr)
        metric_tbls.append(mv)
        schema_objects.append(
            _table_object(mv, catalog, overrides, rels, checks, mv_cols, links))

    # Faithfulness (no-silent-caps): warn on any check that matched no object in this
    # unit (its target table is None or lives in another schema), so the "contract and
    # checks.sql describe the same checks" claim never silently degrades.
    attached = {c["name"] for t in (tables + metric_tbls) for c in checks if c["table"] == t["name"]}
    for c in checks:
        if c["name"] not in attached:
            print(f"[ordm-odcs] {name}: check '{c['name']}' (severity={c['severity']}) "
                  f"attaches to no object (table={c['table']}) — not emitted in the contract",
                  file=sys.stderr)

    contract = {
        "apiVersion": ODCS_API_VERSION,
        "kind": "DataContract",
        # Stable, human-readable id derived from the unit — deterministic so the
        # generated file is byte-stable across runs (suitable for a CI lockfile).
        "id": f"ordm-{'core' if is_core else 'outcome'}-{name}",
        "name": f"ordm_{name.replace('-', '_')}",
        "version": "1.0.0",
        "status": "draft",
        "domain": name,
        "tags": ["ordm", "retail", "canonical-core" if is_core else "outcome-package"],
        "description": {
            "purpose": f"ORDM {kind_label} '{name}'. Generated from the committed "
                       f"DDL, relationships, quality checks and glossary — ORDM's "
                       f"source of truth. ODCS is an optional integration; the model "
                       f"does not depend on it.",
            "usage": "Optional. Consumable by contract-driven tools (e.g. DQX for "
                     "data-quality execution, Lockstep for Unity Catalog sync, Ontos "
                     "as data products). See docs/odcs-integration.md.",
        },
        "authoritativeDefinitions": links,
        "schema": schema_objects,
    }
    return contract


# ============================================================
# Discovery / CLI
# ============================================================

def discover_units(include: set[str] | None) -> list[str]:
    """All canonical-core domains + outcome packages that have DDL, optionally
    filtered to `include` (match by base directory name)."""
    units = []
    for base in (CANONICAL_CORE, OUTCOME_PACKAGES):
        for entry in sorted(glob.glob(os.path.join(base, "*"))):
            if not os.path.isdir(entry):
                continue
            name = os.path.basename(entry)
            if include and name not in include:
                continue
            units.append(entry)
    return units


def _dump_yaml(contract: dict) -> str:
    import yaml

    class _NoAlias(yaml.SafeDumper):
        # No anchors/aliases: a generated lockfile stays flat + diff-stable, and
        # repeated `&id00N` anchors otherwise break multi-document (`--out -`) output.
        def ignore_aliases(self, data):
            return True

    header = (
        "# GENERATED by tools/generate_odcs.py — do not edit by hand.\n"
        "# ODCS v3.1.0 (Bitol / Linux Foundation). OPTIONAL integration; ORDM's\n"
        "# source of truth is the committed DDL / checks.sql / glossary.md.\n"
        "# Regenerate: python tools/generate_odcs.py\n"
    )
    body = yaml.dump(contract, Dumper=_NoAlias, sort_keys=False, default_flow_style=False,
                     allow_unicode=True, width=100)
    return header + body


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Generate ODCS v3.1.0 data contracts from ORDM's committed "
                    "DDL/checks/glossary (optional integration; see docs/odcs-integration.md).")
    parser.add_argument("--catalog", default="",
                        help="Unity Catalog for physicalName (never hardcoded; "
                             "left blank -> schema.table only).")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--include",
                       help="Comma-separated domain/package names to emit (default: all).")
    group.add_argument("--domain",
                       help="Single domain/package name to emit (alias for --include with one).")
    parser.add_argument("--out", default="",
                        help="Output dir (default contracts/odcs/), or '-' for stdout.")
    for token in schema_defaults():
        parser.add_argument("--" + token, default="",
                            help=f"Override the {token} schema name.")
    args = parser.parse_args(argv)

    include = None
    if args.include:
        include = {s.strip() for s in args.include.split(",") if s.strip()}
    elif args.domain:
        include = {args.domain.strip()}

    overrides = {t: getattr(args, t) for t in schema_defaults() if getattr(args, t, "")}
    units = discover_units(include)
    if not units:
        print("[ordm-odcs] no matching domains/packages with DDL found.", file=sys.stderr)
        return 1

    to_stdout = args.out == "-"
    out_dir = args.out if (args.out and not to_stdout) else DEFAULT_OUT_DIR

    # Gold-view type inference, resolved once across EVERY unit (discover_units(None)),
    # not just an --include subset: an outcome package emitted alone still needs the
    # canonical-core silver columns its gold views reference, and gold-on-gold views
    # need their sibling views resolved first (topological fixpoint).
    all_units = discover_units(None)
    silver = build_silver_schema(all_units)
    gold_types = infer_all_gold_types(silver, build_gold_sql(all_units))
    type_schema = {**silver, **gold_types}

    written = 0
    for unit in units:
        try:
            contract = build_contract(unit, args.catalog, overrides, gold_types, type_schema)
        except Exception as exc:
            # Name the offending unit on a fail-loud parser error (parity with
            # gen_model_json / gen_er_diagrams) so the ODCS drift gate — the first
            # generator to run in CI — reports which unit, not a bare traceback
            # (#55 review M1).
            raise RuntimeError(
                f"failed to build ODCS contract for unit "
                f"'{os.path.basename(os.path.normpath(unit))}': {exc}"
            ) from exc
        if contract is None:
            continue  # placeholder package (no DDL yet) — skip silently
        text = _dump_yaml(contract)
        if to_stdout:
            if written:
                sys.stdout.write("---\n")  # YAML document separator between contracts
            sys.stdout.write(text)
        else:
            os.makedirs(out_dir, exist_ok=True)
            dest = os.path.join(out_dir, os.path.basename(unit) + ".odcs.yaml")
            with open(dest, "w", encoding="utf-8") as fh:
                fh.write(text)
            print(f"[ordm-odcs] wrote {os.path.relpath(dest, REPO_ROOT)} "
                  f"({len(contract['schema'])} object(s))")
        written += 1

    if not written:
        print("[ordm-odcs] nothing generated (units matched but had no DDL).", file=sys.stderr)
        return 1
    if not to_stdout:
        print(f"[ordm-odcs] {written} contract(s) generated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
