"""DdlParser: wraps the ORDM DDL-parsing helpers and returns typed model objects
from tools.ordm_ddl.model.  This module is the SINGLE HOME for all DDL-parsing
logic; tools/generate_odcs.py imports from here.
"""
from __future__ import annotations

import glob
import os
import re

from tools.ordm_config import schema_defaults
from tools.ordm_ddl.model import Check, Column, Relationship, Table, Unit

# ============================================================
# Private DDL-parsing helpers — the canonical copy.
# tools/generate_odcs.py imports these rather than defining its own.
# ============================================================

_CREATE_TABLE_RE = re.compile(
    r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?"
    r"\$\{catalog\}\.\$\{(?P<schema>\w+)\}\.(?P<name>\w+)\s*\(",
    re.IGNORECASE,
)
_CREATE_VIEW_RE = re.compile(
    r"CREATE\s+(?:OR\s+(?:REPLACE|REFRESH)\s+)?(?:MATERIALIZED\s+)?VIEW\s+"
    r"\$\{catalog\}\.\$\{(?P<schema>\w+)\}\.(?P<name>\w+)\b",
    re.IGNORECASE,
)
_TABLE_COMMENT_RE = re.compile(r"\)\s*(?:[^;]*?)COMMENT\s+'((?:[^']|'')*)'\s*;", re.IGNORECASE | re.DOTALL)
_COLUMN_RE = re.compile(
    r"^\s*(?P<name>[a-z_][a-z0-9_]*)\s+"
    # Type capture accepts Databricks scalar AND complex/collection types (#53 H1):
    #   scalar with optional precision — DECIMAL(18,2), VARCHAR(255)
    #   collection/complex with angle brackets, possibly nested —
    #     ARRAY<STRING>, MAP<STRING,INT>, STRUCT<a:INT,b:ARRAY<STRING>>
    # The `<...>` part is matched with a nesting-tolerant balanced pattern
    # (up to 4 levels) so a nested STRUCT/MAP/ARRAY isn't truncated. The old
    # `[A-Za-z]+(precision)?` never matched `<>` and SILENTLY DROPPED such columns.
    # KNOWN LIMIT: multi-word interval types capture only the bare keyword — e.g.
    # `INTERVAL DAY TO SECOND` yields type="INTERVAL" (the qualifier lands in `rest`);
    # the column still emits. Extend the type sub-pattern if precise INTERVAL types
    # are ever needed (#55 review M2). No committed DDL uses INTERVAL today.
    r"(?P<type>[A-Za-z][A-Za-z0-9_]*"
    r"(?:\s*\(\s*\d+(?:\s*,\s*\d+)?\s*\))?"        # scalar precision  (18,2)
    r"(?:\s*<[^<>]*(?:<[^<>]*(?:<[^<>]*(?:<[^<>]*>[^<>]*)*>[^<>]*)*>[^<>]*)*>)?"  # nested <...>
    r")(?=\s|,|$)"
    r"(?P<rest>.*)$",
    re.IGNORECASE | re.DOTALL,
)
_COMMENT_IN_RE = re.compile(r"COMMENT\s+'((?:[^']|'')*)'", re.IGNORECASE | re.DOTALL)
_PK_RE = re.compile(r"CONSTRAINT\s+\w+\s+PRIMARY\s+KEY\s*\(([^)]*)\)", re.IGNORECASE)
_COLUMN_TAG_RE = re.compile(
    r"ALTER\s+COLUMN\s+(?P<col>\w+)\s+SET\s+TAGS\s*\((?P<tags>[^)]*)\)",
    re.IGNORECASE,
)
_TABLE_TAG_RE = re.compile(
    r"SET\s+TAGS\s*\(\s*'dbx_data_type'\s*=\s*'([^']*)'\s*\)", re.IGNORECASE)
_PII_TAG_RE = re.compile(r"dbx_pii\w*", re.IGNORECASE)

_FK_RE = re.compile(
    r"ALTER\s+TABLE\s+\$\{catalog\}\.\$\{\w+\}\.(?P<child>\w+)\s+"
    r"ADD\s+CONSTRAINT\s+\w+\s+FOREIGN\s+KEY\s*\((?P<cols>[^)]*)\)\s+"
    r"REFERENCES\s+\$\{catalog\}\.\$\{(?P<pschema>\w+)\}\.(?P<parent>\w+)\s*\((?P<pcols>[^)]*)\)",
    re.IGNORECASE,
)
_CHECK_ENUM_RE = re.compile(
    r"ALTER\s+TABLE\s+\$\{catalog\}\.\$\{\w+\}\.(?P<table>\w+)\s+"
    r"ADD\s+CONSTRAINT\s+\w+\s+CHECK\s*\((?P<expr>.*?)\)\s*;",
    re.IGNORECASE | re.DOTALL,
)
_IN_LIST_RE = re.compile(r"(?P<col>\w+)\s+IN\s*\((?P<vals>[^)]*)\)", re.IGNORECASE)
_SQL_FUNCS = {"char_length", "length", "lower", "upper", "trim", "abs", "coalesce"}

_CHECK_HEADER_RE = re.compile(r"--\s*check:\s*(?P<name>[\w-]+)\s*\|\s*severity:\s*(?P<sev>\w+)", re.IGNORECASE)

_META_PREFIXES = ("ordm", "view:", "table:", "layer:", "version:", "generated:",
                  "llm-", "last reviewed", "materialization")


def _unquote(s: str) -> str:
    return s.replace("''", "'").strip()


def _split_top_level(body: str) -> list[str]:
    """Split a CREATE-TABLE body on top-level commas, ignoring commas inside:
      - the parentheses of a scalar type   — DECIMAL(18,2)
      - the angle brackets of a complex type — MAP<STRING,INT>, STRUCT<a:INT,b:STRING> (#53 H1)
      - a quoted COMMENT string.
    Both `()` and `<>` are tracked with a shared depth counter. NOTE: this assumes
    `<`/`>` appear ONLY as complex-type brackets or inside quoted strings. A bare
    unquoted comparison operator in the body (e.g. an inline `CHECK (col > 0)` or
    `GENERATED ALWAYS AS (a > b)`) would skew `depth`; ORDM keeps CHECKs as separate
    ALTER TABLE statements so this can't arise today, but add handling before putting
    an inline `>`/`<` in a CREATE-TABLE body (#55 review M1)."""
    parts, buf, depth, in_str = [], [], 0, False
    i, n = 0, len(body)
    while i < n:
        c = body[i]
        if in_str:
            buf.append(c)
            if c == "'":
                if i + 1 < n and body[i + 1] == "'":
                    buf.append(body[i + 1]); i += 2; continue
                in_str = False
        elif c == "'":
            in_str = True; buf.append(c)
        elif c in "(<":
            depth += 1; buf.append(c)
        elif c in ")>":
            depth -= 1; buf.append(c)
        elif c == "," and depth == 0:
            parts.append("".join(buf)); buf = []
        else:
            buf.append(c)
        i += 1
    if buf:
        parts.append("".join(buf))
    if depth != 0:
        # Unbalanced ()/<> — a stray unquoted comparison operator or malformed type
        # skews the shared depth counter and could mis-split a column so the pieces
        # still individually match _COLUMN_RE (silent wrong columns). Fail loud: this
        # is the "no silent drops" invariant (#55 review Mnr1).
        raise ValueError(
            f"Unbalanced ()/<> in CREATE TABLE body (end depth={depth}); refusing to "
            "risk a silent mis-split. If this is a bare inline comparison (e.g. "
            "CHECK (a > b)), move it to a separate ALTER TABLE ADD CONSTRAINT."
        )
    return parts


def _strip_line_comments(body: str) -> str:
    """Remove `-- ...` line comments from a CREATE body WITHOUT touching text
    inside single-quoted strings (a COMMENT '...' can legitimately contain `--`)."""
    out, in_str = [], False
    i, n = 0, len(body)
    while i < n:
        c = body[i]
        if in_str:
            out.append(c)
            if c == "'":
                if i + 1 < n and body[i + 1] == "'":
                    out.append(body[i + 1]); i += 2; continue
                in_str = False
        elif c == "'":
            in_str = True; out.append(c)
        elif c == "-" and i + 1 < n and body[i + 1] == "-":
            while i < n and body[i] != "\n":  # drop to end of line
                i += 1
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def parse_columns(create_body: str) -> list[dict]:
    """Return [{name, sql_type, required, comment}] from a CREATE-TABLE body.
    IDENTITY surrogate keys are still real columns and are included."""
    cols = []
    for frag in _split_top_level(_strip_line_comments(create_body)):
        stripped = frag.strip()
        u = stripped.upper()
        # Table-level constraint clauses are not columns (handled elsewhere) — skip
        # them whether or not they carry the optional CONSTRAINT name. Bare inline
        # PRIMARY KEY / FOREIGN KEY / CHECK / UNIQUE are legal Databricks SQL and must
        # not hit the fail-loud raise below (#55 review m1). The CHECK/UNIQUE match
        # requires a following "(" so a column literally named e.g. check_flag isn't skipped.
        if (not stripped
                or u.startswith(("CONSTRAINT", "PRIMARY KEY", "FOREIGN KEY"))
                or re.match(r"(?:CHECK|UNIQUE)\s*\(", u)):
            continue
        m = _COLUMN_RE.match(frag)
        if not m:
            # A non-empty, non-CONSTRAINT fragment that doesn't parse as a column
            # is a real problem: silently skipping it drops the column from ALL
            # five projections (ODCS/model.json/DBML/Mermaid) and the drift gate
            # would happily pass over the hole. Fail loud instead (#53 H1).
            raise ValueError(
                f"Unparseable column definition in CREATE TABLE body: {stripped!r}. "
                "If this is an unnamed table constraint, add the CONSTRAINT keyword; if it "
                "is a Databricks column type the parser doesn't cover yet (e.g. complex-type "
                "nesting deeper than the 4 levels _COLUMN_RE handles), broaden _COLUMN_RE "
                "in tools/ordm_ddl/parser.py."
            )
        rest = m.group("rest") or ""
        rest_upper = rest.upper()
        cm = _COMMENT_IN_RE.search(rest)
        cols.append({
            "name": m.group("name"),
            "sql_type": re.sub(r"\s+", "", m.group("type")).upper(),
            "required": "NOT NULL" in rest_upper,
            "comment": _unquote(cm.group(1)) if cm else "",
        })
    return cols


def _balanced_body(sql_text: str, open_paren_idx: int) -> str:
    """Return the text between the CREATE-TABLE `(` at open_paren_idx and its
    MATCHING `)`, honouring nested parens (DECIMAL(18,2), PRIMARY KEY (...)) and
    ignoring parens inside single-quoted COMMENT strings AND inside `-- ...` line
    comments.

    The line-comment skip is not cosmetic. An APOSTROPHE in a `-- ...` comment inside the
    body — "the supermarket's own staff" — would otherwise be read as a string delimiter,
    inverting `in_str` for the rest of the body. The matching `)` is then missed, the
    returned body runs past `USING DELTA` into the CLUSTER BY clause, and
    `_split_top_level` raises on the resulting imbalance. That raise is the good outcome;
    the bad one is a body that happens to re-balance and yields silently wrong columns.
    """
    depth, in_str = 0, False
    i, n = open_paren_idx, len(sql_text)
    start = open_paren_idx + 1
    while i < n:
        c = sql_text[i]
        if in_str:
            if c == "'":
                if i + 1 < n and sql_text[i + 1] == "'":
                    i += 2; continue
                in_str = False
        elif c == "'":
            in_str = True
        elif c == "-" and i + 1 < n and sql_text[i + 1] == "-":
            while i < n and sql_text[i] != "\n":
                i += 1
            continue
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return sql_text[start:i]
        i += 1
    return sql_text[start:]  # unbalanced (shouldn't happen for committed DDL)


def parse_table_sql(sql_text: str) -> dict | None:
    """Parse one tables/*.sql (or a gold view) into a table dict, or None."""
    m = _CREATE_TABLE_RE.search(sql_text)
    if m:
        body = _balanced_body(sql_text, m.end() - 1)
        cols = parse_columns(body)
        pk_m = _PK_RE.search(body)
        pk = [c.strip() for c in pk_m.group(1).split(",")] if pk_m else []
        tc = _TABLE_COMMENT_RE.search(sql_text)
        role_m = _TABLE_TAG_RE.search(sql_text)
        return {
            "name": m.group("name"), "schema_token": m.group("schema"),
            "kind": "table", "columns": cols, "primary_key": pk,
            "comment": _unquote(tc.group(1)) if tc else "",
            "role": role_m.group(1) if role_m else "",
            "column_tags": _column_pii_tags(sql_text),
        }
    v = _CREATE_VIEW_RE.search(sql_text)
    if v:
        # Is this a MATERIALIZED VIEW or a plain VIEW? Decide from the matched
        # CREATE VIEW statement itself (not a re-scan of the whole file), so a
        # COMMENT elsewhere that mentions "view" can't flip it (#53 M1).
        materialized = "materialized" in v.group(0).lower()
        return {
            "name": v.group("name"), "schema_token": v.group("schema"),
            "kind": "view", "materialized_view": materialized,
            "columns": [], "primary_key": [],
            "comment": _leading_header_comment(sql_text), "role": "gold",
            "column_tags": {},
        }
    return None


def _leading_header_comment(sql_text: str) -> str:
    """The prose description block in a file's leading `-- ...` banner."""
    in_meta_continuation = False
    prose: list[str] = []
    for line in sql_text.splitlines():
        s = line.strip()
        if not s.startswith("--"):
            break
        txt = s.lstrip("-").strip()
        if not txt or set(txt) <= {"="}:
            if prose:
                break
            continue
        low = txt.lower()
        if low.startswith(_META_PREFIXES):
            in_meta_continuation = True
            continue
        if in_meta_continuation and (line.startswith("--  ") or line.startswith("--\t")):
            continue
        in_meta_continuation = False
        prose.append(txt)
    return " ".join(prose)


def _column_pii_tags(sql_text: str) -> dict:
    """{column: [pii_tag, ...]} from ALTER COLUMN ... SET TAGS ('dbx_pii_*'='true')."""
    tags: dict[str, list[str]] = {}
    for m in _COLUMN_TAG_RE.finditer(sql_text):
        found = _PII_TAG_RE.findall(m.group("tags"))
        if found:
            tags.setdefault(m.group("col"), []).extend(t.lower() for t in found)
    return tags


def _check_col(expr: str) -> str | None:
    """Best-effort column a CHECK constrains, for BOTH enum (`col IN (...)`) and
    range/comparison (`col IS NULL OR col BETWEEN …`, `rate > 0`, `char_length(col)=3`)
    forms."""
    im = _IN_LIST_RE.search(expr)
    if im:
        return im.group("col")
    m = re.match(r"\s*\(?\s*(?P<tok>\w+)\s*(?P<paren>\()?", expr)
    if not m:
        return None
    tok = m.group("tok")
    if m.group("paren") or tok.lower() in _SQL_FUNCS:
        inner = re.search(r"\(\s*(\w+)", expr)
        return inner.group(1) if inner else None
    return tok


def parse_relationships(sql_text: str) -> dict:
    """Return {'fks': {child: [{cols, parent, pschema, pcols}]},
               'checks': {table: [{col, values, expr}]}}."""
    fks: dict[str, list[dict]] = {}
    for m in _FK_RE.finditer(sql_text):
        fks.setdefault(m.group("child"), []).append({
            "cols": [c.strip() for c in m.group("cols").split(",")],
            "parent": m.group("parent"),
            "pschema": m.group("pschema"),
            "pcols": [c.strip() for c in m.group("pcols").split(",")],
        })
    checks: dict[str, list[dict]] = {}
    for m in _CHECK_ENUM_RE.finditer(sql_text):
        expr = " ".join(m.group("expr").split())
        im = _IN_LIST_RE.search(expr)
        checks.setdefault(m.group("table"), []).append({
            "col": _check_col(expr),
            "values": [_unquote(v).strip().strip("'") for v in im.group("vals").split(",")] if im else [],
            "expr": expr,
        })
    return {"fks": fks, "checks": checks}


def parse_checks(sql_text: str) -> list[dict]:
    checks = []
    lines = sql_text.splitlines()
    i, n = 0, len(lines)
    while i < n:
        hm = _CHECK_HEADER_RE.search(lines[i])
        if not hm:
            i += 1
            continue
        desc_parts, j = [], i + 1
        while j < n and lines[j].strip().startswith("--"):
            desc_parts.append(lines[j].strip().lstrip("-").strip())
            j += 1
        body_parts = []
        while j < n and not lines[j].strip().startswith("-- check:"):
            body_parts.append(lines[j])
            if lines[j].rstrip().endswith(";"):
                j += 1
                break
            j += 1
        query = "\n".join(body_parts).strip().rstrip(";").strip()
        tm = re.search(r"\$\{catalog\}\.\$\{\w+\}\.(\w+)", query)
        checks.append({
            "name": hm.group("name"),
            "severity": hm.group("sev").lower(),
            "description": " ".join(p for p in desc_parts if p),
            "query": query,
            "table": tm.group(1) if tm else None,
        })
        i = j
    return checks


# ------------------------------------------------------------
# comments.sql: COMMENT ON COLUMN <fqn>.<col> IS '...'  -> column descriptions
# for gold views (whose columns are not statically typed from the SELECT).
# ------------------------------------------------------------
_COMMENT_ON_RE = re.compile(
    r"COMMENT\s+ON\s+COLUMN\s+\$\{catalog\}\.\$\{\w+\}\.(?P<table>\w+)\.(?P<col>\w+)\s+IS\s+'((?P<txt>(?:[^']|'')*))'",
    re.IGNORECASE,
)


def parse_comments(sql_text: str) -> dict:
    """{table: [{name, comment}]} in file order (column order for gold views)."""
    out: dict[str, list[dict]] = {}
    for m in _COMMENT_ON_RE.finditer(sql_text):
        out.setdefault(m.group("table"), []).append(
            {"name": m.group("col"), "comment": _unquote(m.group("txt"))})
    return out


def _sqlglot_view_columns(sql_text: str) -> list[str]:
    """Gold-view output column NAMES from its SELECT projection, via sqlglot's
    `databricks` dialect. The FALLBACK for a gold view that comments.sql does NOT
    document (e.g. a multi-CTE `WITH ... AS (...)` view whose projection the
    COMMENT ON COLUMN convention never enumerated): its card would otherwise render
    empty. Returns the projection's output names in order. sqlglot's databricks
    dialect parses `CREATE OR REFRESH MATERIALIZED VIEW`, multi-CTE views, and the
    `${catalog}.${schema}` tokens directly (verified across every gold view in the
    repo). Returns [] if sqlglot cannot parse the view, so that one view stays empty
    rather than breaking the build; a MISSING sqlglot import fails loud (it is a
    pinned dev dependency), never a silent empty that would drift the gate.
    """
    import sqlglot
    from sqlglot.errors import SqlglotError

    try:
        expr = sqlglot.parse_one(sql_text, dialect="databricks")
        # `named_selects` resolves the final projection past any WITH block, but only
        # exists on query-bearing nodes; a non-SELECT parse (Comment/Command, e.g. a
        # metric-view YAML body that degrades to Command) has no such attribute.
        names = list(expr.named_selects) if expr is not None else []
        # Guard the `SELECT *` case: if a view's FINAL projection were a bare star that
        # qualify did not expand, named_selects yields a literal "*" - never a real column
        # name. Drop it so a "*" can't leak into model.json / a contract. (No view does
        # this today; the one repo `SELECT *` is inside a CTE that qualify expands.)
        return [n for n in names if n != "*"]
    except (SqlglotError, AttributeError):
        return []


def union_gold_column_names(projected: list, comment_names: list) -> list:
    """Ordered UNION of a gold view's sqlglot SELECT projection and its comments.sql column
    names: the projection first (authoritative + complete when sqlglot resolves), then any
    comments-only column sqlglot did not surface, so NEITHER source can silently DROP a
    column. Single implementation shared by DdlParser._gold_columns (drives model.json + ER
    diagrams) and generate_odcs.build_contract (drives the ODCS contracts) so the two paths
    can never diverge (previously each re-implemented this and had to be kept in lockstep)."""
    ordered = list(projected)
    for n in comment_names:
        if n not in ordered:
            ordered.append(n)
    return ordered


# sqlglot normalises some Databricks types to ANSI spellings; map back for display.
# Fold sqlglot's generic-dialect spellings to their Databricks-strict equivalents.
# Databricks SQL has no TIMESTAMPTZ / TIMESTAMP_LTZ; sqlglot annotates CURRENT_TIMESTAMP()
# as TIMESTAMPTZ, which would leak the one non-Databricks type spelling into a contract.
_GOLD_TYPE_ALIASES = {
    "TEXT": "STRING", "VARCHAR": "STRING", "CHAR": "STRING",
    "TIMESTAMPTZ": "TIMESTAMP", "TIMESTAMP_LTZ": "TIMESTAMP",
}


def _normalize_gold_type(t: str) -> str:
    up = t.upper()
    for k, v in _GOLD_TYPE_ALIASES.items():
        if up == k or up.startswith(k + "("):
            return v
    return up


def infer_gold_column_types(sql_text: str, silver_schema: dict) -> dict:
    """Infer a gold view's output column TYPES from its SELECT projection, given the
    silver source schema {table: {col: sqltype}}, via sqlglot's optimizer. Gold views
    are materialized VIEWS with no declared column types, but sqlglot can annotate the
    projection's types once the source tables' columns are known (pass-through columns
    resolve to their source type; expressions to their computed type).

    Returns {output_column: DISPLAY_TYPE} for the columns sqlglot can resolve; columns
    it cannot (complex expressions, unresolved refs) are OMITTED so the caller leaves
    them blank. BEST EFFORT: any parse/qualify/annotate failure yields {} (types stay
    blank), never raising - types are an enrichment, not a gate. A MISSING sqlglot
    import fails loud (pinned dev dependency).
    """
    import sqlglot
    from sqlglot import exp
    from sqlglot.errors import SqlglotError
    from sqlglot.optimizer.annotate_types import annotate_types
    from sqlglot.optimizer.qualify import qualify

    try:
        expr = sqlglot.parse_one(sql_text, dialect="databricks")
        sel = expr.find(exp.Select) if expr is not None else None
        if sel is None:
            return {}
        # validate_qualify_columns=False: do not fail if a column can't be traced to a
        # source (the schema may be incomplete for a computed expression); annotate what
        # it can and leave the rest UNKNOWN.
        q = qualify(sel.copy(), schema=silver_schema, dialect="databricks",
                    validate_qualify_columns=False)
        annotated = annotate_types(q, schema=silver_schema)
        out: dict[str, str] = {}
        for s in annotated.selects:
            t = str(s.type) if s.type is not None else ""
            if t and t not in ("UNKNOWN", "NULL"):
                out[s.alias_or_name] = _normalize_gold_type(t)
        return out
    except (SqlglotError, KeyError, AttributeError, RecursionError):
        return {}


def infer_all_gold_types(silver_schema: dict, gold_sql: dict) -> dict:
    """Infer every gold view's column types, resolving gold-on-gold dependencies.

    ``gold_sql`` is {view_name: sql_text}. Many gold views read from OTHER gold views
    (e.g. gold_promo_roi rolls up gold_promo_roi_by_category, gold_promo_performance
    reads gold_trade_promotion) rather than directly from silver, so a single pass with
    a silver-only schema leaves them wholly or partly type-less. This iterates to a
    fixpoint: each pass infers what it can with the schema so far (silver + gold views
    resolved in earlier passes), feeds the newly-resolved gold-view types back into the
    schema, and repeats until a pass adds nothing new. Column counts are monotonic, so
    it always terminates; a small pass cap guards against pathological cycles.

    Returns {view_name: {output_column: DISPLAY_TYPE}} - the same per-view shape
    ``infer_gold_column_types`` returns, so callers stay unchanged apart from the
    single up-front call.
    """
    resolved: dict = {}
    schema = dict(silver_schema)
    # A gold view can depend on another gold view; a chain of length N needs N passes.
    # Cap at len(gold_sql)+1 (a topological order can be no longer) so cycles can't spin.
    for _ in range(len(gold_sql) + 1):
        changed = False
        for name, sql in gold_sql.items():
            types = infer_gold_column_types(sql, schema)
            # Accept a view's result only when it resolved MORE columns than before. This
            # relies on types being MONOTONIC IN VALUE, not just count: a column only enters
            # the result once it has a concrete source type (UNKNOWN/NULL are filtered in
            # infer_gold_column_types), and feeding more source schema only lets previously
            # unresolved columns resolve - it never re-types an already-resolved one. So a
            # strictly-growing count is a sufficient change signal, and it guarantees
            # termination (count is bounded by the column set, capped at the topo depth).
            if len(types) > len(resolved.get(name, {})):
                resolved[name] = types
                # Feed this view's resolved columns back so views built ON it resolve.
                schema[name] = dict(types)
                changed = True
        if not changed:
            break
    return resolved


def build_silver_schema(unit_dirs: list[str]) -> dict:
    """Scan every unit's canonical-core silver tables into {table: {column: sql_type}}
    - the source schema gold views resolve their column types against. Built across
    ALL units (a gold view in one outcome package references silver tables that live
    in canonical-core), independent of any emit filter. Co-located with
    infer_all_gold_types / union_gold_column_names so the collection and the inference
    that consumes it live together (previously duplicated in generate_odcs.py and
    gen_model_json.py)."""
    schema: dict[str, dict] = {}
    for unit_dir in unit_dirs:
        for path in sorted(glob.glob(os.path.join(unit_dir, "tables", "*.sql"))):
            parsed = parse_table_sql(_read(path))
            if parsed and parsed["kind"] == "table":
                schema[parsed["name"]] = {
                    c["name"]: (c.get("sql_type") or "STRING") for c in parsed["columns"]
                }
    return schema


def build_gold_sql(unit_dirs: list[str]) -> dict:
    """Collect every gold view's SQL as {view_name: sql_text}, keyed by the view name
    (how sibling views reference it in FROM/JOIN) so gold-on-gold type inference can
    resolve one view against another. Spans all units for the same reason as the
    silver schema."""
    gold_sql: dict[str, str] = {}
    for unit_dir in unit_dirs:
        for path in sorted(glob.glob(os.path.join(unit_dir, "gold", "*.sql"))):
            gold_sql[os.path.splitext(os.path.basename(path))[0]] = _read(path)
    return gold_sql


def _resolve_schema(token: str, overrides: dict) -> str:
    """Map a `<x>_schema` token to its concrete schema name via databricks.yml
    defaults (guardrail #1: never hardcode). Overrides win, mirroring resolve()."""
    defaults = schema_defaults()
    if overrides:
        defaults.update({k: v for k, v in overrides.items() if v})
    return defaults.get(token, token)


_QUERY_FQN_RE = re.compile(r"\$\{catalog\}\.\$\{(?P<schema>\w+)\}\.(?P<name>\w+)")


def _resolve_query(query: str, catalog: str, overrides: dict) -> str:
    """Resolve `${catalog}.${<schema>}.<table>` tokens in a check query the SAME way
    physicalName is resolved, so a consumer (DQX) runs concrete SQL rather than literal
    `${catalog}`. Catalog-optional, mirroring physicalName: with `--catalog` set the
    query is fully qualified, without it the schema resolves and the catalog prefix is
    dropped (a 2-part name)."""
    def repl(m):
        schema = _resolve_schema(m.group("schema"), overrides)
        prefix = f"{catalog}." if catalog else ""
        return f"{prefix}{schema}.{m.group('name')}"
    return _QUERY_FQN_RE.sub(repl, query)


# ============================================================
# Module-level helpers used by DdlParser methods
# ============================================================

def _read(path: str) -> str:
    """Read a file's text — no leaked handle, no platform-dependent encoding."""
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _apply_enums(tables: list[Table], enum_checks: list[Check]) -> list[Table]:
    """Return tables with each Column.enum_values populated from matching enum Checks.

    A match is: check.table == table.name AND check.column == column.name.
    Uses dataclasses.replace to rebuild frozen Column/Table instances.
    """
    from dataclasses import replace

    # Build lookup: (table_name, column_name) -> enum_values tuple
    enum_map: dict[tuple[str, str], tuple[str, ...]] = {}
    for chk in enum_checks:
        if chk.table and chk.column and chk.enum_values:
            key = (chk.table, chk.column)
            enum_map[key] = chk.enum_values

    if not enum_map:
        return tables

    result: list[Table] = []
    for tbl in tables:
        new_cols = []
        changed = False
        for col in tbl.columns:
            key = (tbl.name, col.name)
            if key in enum_map:
                new_cols.append(replace(col, enum_values=enum_map[key]))
                changed = True
            else:
                new_cols.append(col)
        result.append(replace(tbl, columns=new_cols) if changed else tbl)
    return result


# ============================================================
# DdlParser: public API that returns typed model objects
# ============================================================

class DdlParser:
    """Wraps the private DDL-parsing helpers and maps their dict/list returns
    onto the frozen dataclasses in tools.ordm_ddl.model."""

    # ------------------------------------------------------------------
    # check_column: thin public wrapper over _check_col
    # ------------------------------------------------------------------

    def check_column(self, expr: str) -> str | None:
        """Return the column name a CHECK expression constrains, or None."""
        return _check_col(expr)

    # ------------------------------------------------------------------
    # parse_table: parse a single DDL text block -> Table | None
    # ------------------------------------------------------------------

    def parse_table(self, sql_text: str) -> Table | None:
        """Parse a CREATE TABLE (or CREATE VIEW) DDL block into a Table object."""
        raw = parse_table_sql(sql_text)
        if raw is None:
            return None

        tags_map: dict[str, list[str]] = raw.get("column_tags", {})

        columns: list[Column] = []
        for col_dict in raw["columns"]:
            col_name = col_dict["name"]
            pii_tags = tags_map.get(col_name, [])
            columns.append(Column(
                name=col_name,
                sql_type=col_dict.get("sql_type", ""),
                required=bool(col_dict.get("required", False)),
                comment=col_dict.get("comment", ""),
                tags=tuple(pii_tags),
            ))

        primary_key = tuple(raw.get("primary_key", []))

        # layer is derived from the DIRECTORY (parse_unit sets "gold" for gold/ files),
        # never from free-text header prose — a comment mentioning "gold" must not flip a
        # silver core table to gold (AI review #53 H1).
        layer = "silver"

        # materialized: True for tables + MATERIALIZED VIEWs; False only for plain views.
        # Key off the ALREADY-PARSED kind (from parse_table_sql), NOT a fresh regex over
        # the whole file text — a COMMENT mentioning e.g. "create or replace view" must not
        # misclassify a real CREATE TABLE (#53 M1). A CREATE TABLE is materialized; a view
        # is materialized only when it is a MATERIALIZED VIEW.
        materialized = (raw["kind"] == "table") or bool(raw.get("materialized_view"))

        # scd2: any column named "is_current"
        scd2 = any(c.name == "is_current" for c in columns)

        return Table(
            name=raw["name"],
            schema_token=raw["schema_token"],
            columns=columns,
            primary_key=primary_key,
            role=raw.get("role", ""),
            comment=raw.get("comment", ""),
            layer=layer,
            materialized=materialized,
            scd2=scd2,
        )

    # ------------------------------------------------------------------
    # parse_relationships: relationships.sql -> (list[Relationship], list[Check])
    # ------------------------------------------------------------------

    def parse_relationships(self, sql_text: str) -> tuple[list[Relationship], list[Check]]:
        """Parse a relationships.sql block.

        Returns a 2-tuple:
          - list[Relationship]  (declared_fk=True for every FK)
          - list[Check]         (enum CHECK constraints; column + enum_values set)
        """
        raw = parse_relationships(sql_text)

        relationships: list[Relationship] = []
        for child_table, fk_list in raw.get("fks", {}).items():
            for fk in fk_list:
                relationships.append(Relationship(
                    child_table=child_table,
                    child_cols=tuple(fk["cols"]),
                    parent_table=fk["parent"],
                    parent_cols=tuple(fk["pcols"]),
                    declared_fk=True,
                ))

        checks: list[Check] = []
        for table_name, check_list in raw.get("checks", {}).items():
            for idx, chk in enumerate(check_list):
                checks.append(Check(
                    name=f"chk_{table_name}_{idx}",
                    table=table_name,
                    column=chk.get("col"),
                    severity="error",
                    enum_values=tuple(chk.get("values", [])),
                    query=chk.get("expr", ""),
                ))

        return relationships, checks

    # ------------------------------------------------------------------
    # parse_checks: checks.sql -> list[Check]
    # ------------------------------------------------------------------

    def parse_checks(self, sql_text: str) -> list[Check]:
        """Parse a checks.sql block into a list of Check objects."""
        raw_checks = parse_checks(sql_text)
        result: list[Check] = []
        for chk in raw_checks:
            result.append(Check(
                name=chk["name"],
                table=chk.get("table") or "",
                # checks.sql checks are table-level SQL assertions, not column-scoped —
                # running _check_col on the full SELECT returned "SELECT" for all of them
                # (#53 H2). Column-scoped enum/domain checks come via parse_relationships.
                column=None,
                severity=chk.get("severity", "error"),
                query=chk.get("query", ""),
            ))
        return result

    # ------------------------------------------------------------------
    # parse_unit: assemble a Unit from a domain/package folder
    # ------------------------------------------------------------------

    def parse_unit(self, unit_dir: str) -> "Unit":
        """Assemble a Unit from a domain or package folder.

        Reads tables/*.sql and gold/*.sql (best-effort; unparseable files are
        skipped), relationships.sql, and checks.sql, then applies enum CHECK
        constraints to Column.enum_values via _apply_enums.
        """
        import os
        import glob
        from dataclasses import replace

        kind = "core" if "canonical-core" in unit_dir else "outcome"
        tables: list[Table] = []
        table_files = sorted(glob.glob(os.path.join(unit_dir, "tables", "*.sql")))
        gold_files = sorted(glob.glob(os.path.join(unit_dir, "gold", "*.sql")))
        gold_sql: dict[str, str] = {}  # gold table name -> its view SQL (sqlglot fallback)
        for f in table_files + gold_files:
            sql = _read(f)
            t = self.parse_table(sql)
            if t is None:  # gold VIEW/AS-SELECT files may not parse as CREATE TABLE — skip
                continue
            if os.path.basename(os.path.dirname(f)) == "gold":
                t = replace(t, layer="gold")
                gold_sql[t.name] = sql
            tables.append(t)

        rels: list[Relationship] = []
        enum_checks: list[Check] = []
        rel_path = os.path.join(unit_dir, "relationships.sql")
        if os.path.exists(rel_path):
            rels, enum_checks = self.parse_relationships(_read(rel_path))

        tables = _apply_enums(tables, enum_checks)

        # Gold views are CREATE VIEW AS SELECT (no column DDL). Their TRUE column set is the
        # SELECT projection, which sqlglot resolves; comments.sql (COMMENT ON COLUMN) supplies
        # curated descriptions but frequently documents only SOME columns. So we UNION the two
        # - the sqlglot projection (in SELECT order) plus any comments.sql column sqlglot did
        # not surface - which guarantees NEITHER source can silently DROP a projected column.
        # (Using comments.sql alone dropped every undocumented projected column: e.g.
        # gold_trend_features projects 6 columns but comments.sql documents only 2.)
        com_path = os.path.join(unit_dir, "comments.sql")
        comments = parse_comments(_read(com_path)) if os.path.exists(com_path) else {}

        def _gold_columns(t: "Table") -> list:
            desc = {c["name"]: c.get("comment", "") for c in comments.get(t.name, [])}
            ordered = union_gold_column_names(
                _sqlglot_view_columns(gold_sql.get(t.name, "")),
                [c["name"] for c in comments.get(t.name, [])],
            )
            if not ordered:
                return t.columns  # neither sqlglot nor comments -> leave columnless
            return [Column(name=n, comment=desc.get(n, "")) for n in ordered]

        tables = [
            replace(t, columns=_gold_columns(t)) if (t.layer == "gold" and not t.columns) else t
            for t in tables
        ]

        checks: list[Check] = []
        chk_path = os.path.join(unit_dir, "checks.sql")
        if os.path.exists(chk_path):
            checks = self.parse_checks(_read(chk_path))

        return Unit(
            name=os.path.basename(unit_dir),
            kind=kind,
            tables=tables,
            relationships=rels,
            checks=checks,
            dir=unit_dir,
            has_glossary=os.path.exists(os.path.join(unit_dir, "glossary.md")),
        )
