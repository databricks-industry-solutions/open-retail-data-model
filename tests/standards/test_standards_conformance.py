"""Static conformance checks: the machine-enforceable ORDM mandates.

Cluster-free. Each test enforces one rule in standards/rules.yaml and is mapped
to its rule id in ENFORCES, which tests/standards/test_standards_meta.py uses to
prove every enforced rule has a check and every check maps to a rule.

These read the committed DDL directly; no Spark and no workspace.
"""
from __future__ import annotations

import re
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
CORE = REPO_ROOT / "canonical-core"
OUTCOME = REPO_ROOT / "outcome-packages"
RULES = yaml.safe_load((REPO_ROOT / "standards" / "rules.yaml").read_text())

# function name -> rule id it enforces. The meta-test checks this against the registry.
ENFORCES = {
    "test_one_create_per_file": "ARTIFACT-ONE-CREATE",
    "test_no_markdown_under_tables": "ARTIFACT-NO-MD-UNDER-TABLES",
    "test_layer_integrity": "LAYER-INTEGRITY",
    "test_pk_contract": "PK-CONTRACT",
    "test_typing_money": "TYPING-MONEY",
    "test_tags_data_type": "TAGS-DATA-TYPE",
    "test_no_inline_check": "NO-INLINE-CHECK",
    "test_fk_completeness": "FK-COMPLETENESS",
    "test_cluster_key_type": "CLUSTER-KEY-TYPE",
    "test_scd2_join_contract": "SCD2-JOIN-CONTRACT",
}

CREATE_RE = re.compile(r"(?im)^\s*CREATE\s+(?:OR\s+REPLACE\s+)?(?:MATERIALIZED\s+)?(?:TABLE|VIEW)\b")
_DATA_TYPE_TAG = re.compile(
    r"dbx_data_type'\s*=\s*'(master|transactional|reference|association)'", re.I
)
# Shared PK-constraint parser (used by test_pk_contract and test_fk_completeness).
_PK_RE = re.compile(r"CONSTRAINT\s+(pk_[a-z_]+)\s+PRIMARY\s+KEY\s*\(\s*([a-z_]+)\s*\)", re.I)


def _core_table_files() -> list[Path]:
    return sorted(CORE.glob("*/tables/*.sql"))


def _all_table_files() -> list[Path]:
    return sorted([*CORE.glob("*/tables/*.sql"), *OUTCOME.glob("*/tables/*.sql")])


def _exceptions_for(rule_id: str) -> list[str]:
    return [e["match"] for e in (RULES.get("known_exceptions") or []) if e.get("rule") == rule_id]


# ---------------------------------------------------------------------------

def test_one_create_per_file():
    """ARTIFACT-ONE-CREATE: exactly one CREATE per file under tables/."""
    offenders = []
    for f in _all_table_files():
        n = len(CREATE_RE.findall(f.read_text()))
        if n != 1:
            offenders.append(f"{f.relative_to(REPO_ROOT)} has {n} CREATE statements")
    assert not offenders, "Expected exactly one CREATE per tables/ file:\n" + "\n".join(offenders)


def test_no_markdown_under_tables():
    """ARTIFACT-NO-MD-UNDER-TABLES: no .md under any tables/ directory."""
    md = [p.relative_to(REPO_ROOT) for p in REPO_ROOT.glob("**/tables/**/*.md")]
    assert not md, "Markdown is not allowed under tables/ (move narrative to docs/ or docs/design/):\n" + "\n".join(
        str(m) for m in md
    )


def _schema_token_values() -> dict[str, str]:
    """Map schema-token name -> resolved schema value, parsed from tools/ordm_config.py."""
    cfg = (REPO_ROOT / "tools" / "ordm_config.py").read_text()
    return dict(re.findall(r'"([a-z_]+_schema)"\s*:\s*"([a-z_]+)"', cfg))


def _core_schema_values(token_values: dict[str, str]) -> set[str]:
    """Schema values that belong to canonical core (one per canonical-core/<domain> dir)."""
    values = set()
    for d in CORE.iterdir():
        if not d.is_dir():
            continue
        values.add(token_values.get(f"{d.name}_schema", d.name))
    return values


def test_layer_integrity():
    """LAYER-INTEGRITY: no canonical-core FK targets an outcome (gold) schema."""
    token_values = _schema_token_values()
    core_values = _core_schema_values(token_values)
    excused = set(_exceptions_for("LAYER-INTEGRITY"))
    ref_re = re.compile(r"REFERENCES\s+\$\{catalog\}\.\$\{([a-z_]+)\}\.([a-z_]+)")
    violations = []
    for rel in CORE.glob("*/relationships.sql"):
        domain = rel.parent.name
        for token, parent_table in ref_re.findall(rel.read_text()):
            target_value = token_values.get(token, token.replace("_schema", ""))
            if target_value in core_values:
                continue  # core -> core is fine
            signature = f"{domain}/relationships.sql -> {target_value}.{parent_table}"
            if signature in excused:
                continue
            violations.append(signature)
    assert not violations, (
        "Canonical core must not FK into a gold/outcome schema "
        "(promote it to core, or resolve the relationship in the outcome package):\n"
        + "\n".join(violations)
    )


def test_pk_contract():
    """PK-CONTRACT: pk_<table> on a _sk column that is BIGINT GENERATED ALWAYS AS IDENTITY."""
    offenders = []
    for f in _core_table_files():
        stem = f.stem
        text = f.read_text()
        m = _PK_RE.search(text)
        if not m:
            offenders.append(f"{stem}: no `CONSTRAINT pk_... PRIMARY KEY (...)` found")
            continue
        pk_name, pk_col = m.group(1).lower(), m.group(2).lower()
        if pk_name != f"pk_{stem}":
            offenders.append(f"{stem}: PK constraint is {pk_name}, expected pk_{stem}")
        if not pk_col.endswith("_sk"):
            offenders.append(f"{stem}: surrogate key {pk_col} does not end with _sk")
        # the PK column must be declared BIGINT GENERATED ALWAYS AS IDENTITY
        col_re = re.compile(
            rf"\b{re.escape(pk_col)}\s+BIGINT\s+GENERATED\s+ALWAYS\s+AS\s+IDENTITY", re.I
        )
        if not col_re.search(text):
            offenders.append(f"{stem}: {pk_col} is not BIGINT GENERATED ALWAYS AS IDENTITY")
    assert not offenders, "Primary-key contract violations:\n" + "\n".join(offenders)


# columns whose stored value is money: must be DECIMAL, never FLOAT/DOUBLE
_MONEY = re.compile(r"(amount|price|cost|revenue|fee|balance|spend|margin)", re.I)
# numeric-by-name columns must not be STRING
_NUMERIC_NAME = re.compile(r"(_count|_qty|_quantity|_rank|_score|_points|_amount)$", re.I)
_COL_DEF = re.compile(r"^\s*([a-z][a-z0-9_]*)\s+([A-Za-z][A-Za-z0-9_]*(?:\s*\([0-9, ]*\))?)", re.M)


def _columns(text: str):
    """Yield (name, type) for column definitions, skipping constraints/comments."""
    # only scan inside the CREATE TABLE (...) column list
    for name, typ in _COL_DEF.findall(text):
        low = name.lower()
        if low in {"constraint", "primary", "foreign", "using", "comment", "tblproperties", "cluster", "create", "table", "or", "replace"}:
            continue
        yield low, typ.upper().replace(" ", "")


def test_typing_money():
    """TYPING-MONEY: no STRING on numeric-named columns; no FLOAT/DOUBLE on money columns."""
    offenders = []
    for f in _core_table_files():
        for name, typ in _columns(f.read_text()):
            base_type = typ.split("(")[0]
            if _NUMERIC_NAME.search(name) and base_type == "STRING":
                offenders.append(f"{f.stem}.{name}: numeric-named column typed STRING")
            if _MONEY.search(name) and base_type in {"FLOAT", "DOUBLE"}:
                offenders.append(f"{f.stem}.{name}: monetary column typed {base_type} (use DECIMAL)")
    assert not offenders, "Strict-typing violations:\n" + "\n".join(offenders)


def test_tags_data_type():
    """TAGS-DATA-TYPE: every table sets dbx_data_type to a valid role value."""
    offenders = []
    for f in _all_table_files():
        if not _DATA_TYPE_TAG.search(f.read_text()):
            offenders.append(
                f"{f.relative_to(REPO_ROOT)}: missing a dbx_data_type tag "
                "('master'|'transactional'|'reference'|'association')"
            )
    assert not offenders, (
        "Every table must SET TAGS ('dbx_data_type' = ...):\n" + "\n".join(offenders)
    )


# `CONSTRAINT <name> CHECK (` inline in a CREATE; the supported form carries ADD CONSTRAINT.
_INLINE_CHECK = re.compile(r"\bCONSTRAINT\s+\w+\s+CHECK\s*\(", re.I)


def test_no_inline_check():
    """NO-INLINE-CHECK: CHECK constraints are added via ALTER TABLE ADD CONSTRAINT,
    never inline in a CREATE TABLE. Databricks supports only PRIMARY KEY and FOREIGN
    KEY constraints inline, so an inline CHECK fails to parse at deploy time."""
    offenders = []
    for f in _all_table_files():
        for i, line in enumerate(f.read_text().splitlines(), 1):
            if _INLINE_CHECK.search(line) and "ADD CONSTRAINT" not in line.upper():
                offenders.append(f"{f.relative_to(REPO_ROOT)}:{i}: {line.strip()[:70]}")
    assert not offenders, (
        "Inline CHECK in CREATE TABLE is not supported by Databricks; move it to "
        "`ALTER TABLE ... ADD CONSTRAINT ... CHECK (...)`:\n" + "\n".join(offenders)
    )


# ---------------------------------------------------------------------------
# FK-COMPLETENESS: every cross-entity reference is a declared FK on a surrogate.
# ---------------------------------------------------------------------------

# Column definitions of the form `<name>_sk BIGINT` / `<name>_id STRING` inside a
# CREATE. We only need the foreign-surrogate / business-key columns here.
_FK_SK_COL = re.compile(r"^\s*([a-z][a-z0-9_]*_sk)\s+BIGINT\b", re.I | re.M)
_BK_ID_COL = re.compile(r"^\s*([a-z][a-z0-9_]*_id)\s+STRING\b", re.I | re.M)
# A declared FOREIGN KEY on a single column, in a relationships.sql.
_FK_DECL = re.compile(r"FOREIGN\s+KEY\s*\(\s*([a-z_]+)\s*\)", re.I)


def _pk_stem_map() -> dict[str, str]:
    """Map each core table file-stem -> its PK stem (the PK column minus `_sk`).

    The PK stem — NOT the physical table name — is the entity's join key stem
    (ADR-0011: keys are named by grain/role, applied consistently). Examples that
    diverge from the table name: fiscal_calendar -> date, promotion -> promo,
    customer_order_line -> order_line, purchase_order_line -> po_line.
    """
    out: dict[str, str] = {}
    for f in _core_table_files():
        m = _PK_RE.search(f.read_text())
        if m:
            pk_col = m.group(2).lower()
            if pk_col.endswith("_sk"):
                out[f.stem] = pk_col[: -len("_sk")]
    return out


def _referenced_stem(prefix: str, pk_stems: set[str]) -> str | None:
    """Given a column prefix (the part before `_sk`/`_id`), return the PK stem it
    references, or None. Exact match wins; otherwise a role-qualified column such
    as `destination_store_sk` / `origin_store_sk` matches on its trailing stem
    (`store`). The longest trailing PK stem wins so `po_line` beats `line`."""
    if prefix in pk_stems:
        return prefix
    candidates = [s for s in pk_stems if prefix.endswith("_" + s)]
    return max(candidates, key=len) if candidates else None


def test_fk_completeness():
    """FK-COMPLETENESS: reference completeness on the surrogate key.

    Every canonical-core table that references another core entity (masters
    included, e.g. `account -> profile`) must carry a `<stem>_sk` foreign surrogate
    and declare the informational FK on it in that domain's relationships.sql. A
    cross-entity reference modeled only on a business key `<stem>_id` (no `<stem>_sk`)
    is a defect, not an exemption.

    Deterministic, regex over the committed DDL — no Spark. The PK-stem map (ADR
    0011) is used rather than naive table names, so date/calendar and role-qualified
    keys (`destination_store_sk`) don't produce false positives.
    """
    pk_stem_by_table = _pk_stem_map()
    pk_stems = set(pk_stem_by_table.values())
    # Suppressions from standards/rules.yaml `known_exceptions` (rule FK-COMPLETENESS).
    # Two accepted `match` forms:
    #   - a bare PK stem (e.g. `currency`) — a natural-code reference/lookup or a
    #     self-FK stem, suppressed globally (keyed on its ISO/standard code, no _sk);
    #   - a precise `<table>.<column>` signature — tracked debt for one column
    #     (a known `_id`-only reference scheduled for a surrogate; stays visible).
    excused = set(_exceptions_for("FK-COMPLETENESS"))

    def _is_excused(table_stem: str, col: str, ref: str) -> bool:
        return ref in excused or f"{table_stem}.{col}" in excused

    missing_fk = []       # has the foreign surrogate but no declared FK
    business_key_trap = []  # references via `_id` only, no `_sk` to FK on

    for f in _core_table_files():
        text = f.read_text()
        own_stem = pk_stem_by_table.get(f.stem)
        m = _PK_RE.search(text)
        own_pk_col = m.group(2).lower() if m else None

        sk_cols = {c.lower() for c in _FK_SK_COL.findall(text)}
        id_cols = {c.lower() for c in _BK_ID_COL.findall(text)}

        # FKs declared in this domain's relationships.sql (any table in the domain).
        rel = f.parent.parent / "relationships.sql"
        declared_fk_cols = set()
        if rel.exists():
            declared_fk_cols = {c.lower() for c in _FK_DECL.findall(rel.read_text())}

        # (2)+(3): required foreign surrogates -> must be declared as an FK.
        for col in sorted(sk_cols):
            if col == own_pk_col:
                continue  # the table's own PK is not a foreign surrogate
            prefix = col[: -len("_sk")]
            ref = _referenced_stem(prefix, pk_stems)
            if ref is None or ref == own_stem or _is_excused(f.stem, col, ref):
                continue  # not a cross-entity ref / self-ref / excused
            if col not in declared_fk_cols:
                missing_fk.append(
                    f"{f.stem}.{col}: foreign surrogate to `{ref}` has no "
                    f"FOREIGN KEY ({col}) in {rel.parent.name}/relationships.sql"
                )

        # (4): business-key trap — `<stem>_id` referencing another entity but with
        # no `<stem>_sk` to declare the FK on. Add the surrogate.
        for col in sorted(id_cols):
            prefix = col[: -len("_id")]
            ref = _referenced_stem(prefix, pk_stems)
            if ref is None or ref == own_stem or _is_excused(f.stem, col, ref):
                continue
            # is there a matching foreign surrogate (exact or role-qualified)?
            has_surrogate = (prefix + "_sk") in sk_cols or any(
                sk.lower()[: -len("_sk")] == prefix for sk in sk_cols
            )
            if not has_surrogate:
                business_key_trap.append(
                    f"{f.stem}.{col}: references `{ref}` via the business key but has "
                    f"no {prefix}_sk to FK on — add the surrogate and declare "
                    f"fk_{f.stem}_{ref} in relationships.sql"
                )

    problems = business_key_trap + missing_fk
    assert not problems, (
        "FK-COMPLETENESS violations (declare informational FKs on the `_sk` "
        "surrogate; a `_id`-only cross-entity reference is a defect, add the "
        "surrogate):\n" + "\n".join(problems)
    )


# ---------------------------------------------------------------------------
# CLUSTER-KEY-TYPE: a CLUSTER BY key must be a plausible filter/join column.
#
# Liquid Clustering earns its keep on the columns a table is filtered, joined, or
# MERGEd on (the engine builds min/max data-skipping stats and prunes files by
# them). In ORDM's dimensional model those are `_sk` / `_id` keys and dates. A
# continuous MEASURE column (a percentage, rate, score, or money amount) is never
# a predicate, so clustering on it buys no skipping and wastes one of the max-4
# key slots — this is the `service_level_pct DECIMAL(6,5)` class. That is the ONE
# clustering mistake reliably provable from DDL alone: the column's type AND its
# name both live in the CREATE. We do NOT try to detect "select-only" in general
# (a never-filtered id is byte-identical in DDL to a filtered one) — that needs
# query telemetry and would false-positive.
#
# Low-cardinality keys are FINE for clustering: unlike partitioning, Liquid
# Clustering is multi-dimensional and order-independent, so combining low-card
# keys, or a low-card key with a high-card one, skips well. So this rule does NOT
# flag enum keys or key ordering — see the standard §B prose.
# ---------------------------------------------------------------------------

_CLUSTER_RE = re.compile(r"CLUSTER\s+BY\s*\(([^)]*)\)", re.I)
# a cluster key that is a continuous measure: name says percentage/rate/score…
_MEASURE_NAME = re.compile(r"(_pct|_rate|_ratio|_score|percent|percentage)", re.I)
_MAX_CLUSTER_KEYS = 4


def _cluster_keys(text: str) -> list[str] | None:
    """The ordered cluster-key column list, or None if the file has no explicit
    CLUSTER BY (or uses CLUSTER BY AUTO / NONE, which set no named keys).

    Assumes the first `CLUSTER BY (...)` in the file is the real clause, not a
    parenthesized example inside a `-- comment` (consistent with the regex-parsing
    approach used elsewhere in this suite; every committed table keeps its rationale
    comment above a comment-free clause)."""
    m = _CLUSTER_RE.search(text)
    if not m:
        return None
    body = m.group(1).strip()
    if body.upper() in {"AUTO", "NONE"}:
        return None
    return [k.strip().lower() for k in body.split(",") if k.strip()]


# Suffixes that mark a CATEGORICAL / dimensional / temporal / key / label column —
# not a continuous measure — even though the name may contain a money/measure word:
# price_band, cost_center (dimensional); price_effective_date (temporal);
# fee_schedule_key (a surrogate/lookup key); price_tier_name, cost_center_label
# (a display string). All are legitimately clusterable on the view path, where there
# is no type to gate on.
_CATEGORICAL_SUFFIX = re.compile(
    r"(_band|_tier|_bucket|_type|_center|_category|_segment|_group|_class|_level"
    r"|_code|_flag|_status|_date|_key|_name|_label)$",
    re.I,
)


def _is_measure_cluster_key(name: str, base: str | None, is_table: bool) -> bool:
    """True if cluster key `name` (declared base type `base`, or None on a view
    where the type is a SELECT-output alias) is a continuous MEASURE — the
    CLUSTER-KEY-TYPE anti-pattern. A `_sk`/`_id` is a join key, never a measure
    (ADR 0011), so it is exempt even if its name contains a measure substring
    (price_tier_sk). On a table both a real continuous type AND a measure name are
    required (so latitude/longitude DOUBLE is spared). On a view (base is None) the
    name alone decides (so `CLUSTER BY (margin_pct)` is still caught), but a
    categorical/dimensional suffix (price_band, cost_center, margin_tier) is exempt
    since those are legitimate low-card dimension keys, not measures.

    The categorical-suffix carve-out is VIEW-ONLY by design: on a table the type is
    known, so a `price_band` typed INT/STRING already fails the type gate below and
    is spared, while a `price_band DECIMAL` on a table genuinely is suspect and
    should flag — only the type-less view path needs the name-based carve-out."""
    if name.endswith("_sk") or name.endswith("_id"):
        return False
    if not (_MEASURE_NAME.search(name) or _MONEY.search(name)):
        return False
    is_view = base is None and not is_table
    if is_view and _CATEGORICAL_SUFFIX.search(name):
        return False
    return base in {"FLOAT", "DOUBLE", "DECIMAL"} or is_view


def test_cluster_key_type():
    """CLUSTER-KEY-TYPE: no CLUSTER BY key is a continuous measure, and no clause
    exceeds the 4-key maximum.

    Deterministic, cluster-free — the cluster column's declared type + name come
    from the same DDL the suite already parses (`_columns`). FAILs: (1) a key whose
    type is FLOAT/DOUBLE/DECIMAL AND whose name is a measure (_pct/_rate/_ratio/
    _score/percent) or money (`_MONEY`) — a continuous non-predicate column
    clustered for no skipping benefit (type+name both required, so a legitimate
    range-filter DOUBLE such as latitude/longitude is not flagged); (2) more than 4
    keys (Databricks rejects >4 at CREATE, so this is a pre-deploy guard); (3) a key
    that is not a column declared in the same CREATE TABLE (typo / dropped column).
    Low-card and enum keys are allowed (§B: Liquid Clustering is order-independent).

    Coverage note: for a gold VIEW the cluster keys are SELECT-output aliases, so
    `_columns` cannot resolve their type. On a view the measure check falls back to
    the NAME alone (so `CLUSTER BY (margin_pct)` on a computed measure is still
    caught); on a table it requires type AND name. The not-a-column check applies
    only under `tables/` (a view alias is legitimately not a table column-def), and
    the >4-key check applies everywhere. Debt is tracked in standards/rules.yaml
    known_exceptions keyed `<file-stem>.<column>` (the >4-key case uses
    `<file-stem>.__count__`)."""
    excused = set(_exceptions_for("CLUSTER-KEY-TYPE"))
    # both layers' tables + gold views (a measure key could appear in either).
    files = sorted([
        *CORE.glob("*/tables/*.sql"), *OUTCOME.glob("*/tables/*.sql"),
        *CORE.glob("*/gold/*.sql"), *OUTCOME.glob("*/gold/*.sql"),
    ])
    offenders = []
    for f in files:
        text = f.read_text()
        keys = _cluster_keys(text)
        if not keys:
            continue
        is_table = "tables" in f.parts
        col_types = {name: typ.split("(")[0] for name, typ in _columns(text)}
        if len(keys) > _MAX_CLUSTER_KEYS:
            sig = f"{f.stem}.__count__"
            if sig not in excused:
                offenders.append(
                    f"{f.stem}: {len(keys)} cluster keys exceeds the max of "
                    f"{_MAX_CLUSTER_KEYS} ({keys})"
                )
        for k in keys:
            sig = f"{f.stem}.{k}"
            if sig in excused:
                continue
            base = col_types.get(k)
            if _is_measure_cluster_key(k, base, is_table):
                where = f"typed {base} and " if base else ""
                offenders.append(
                    f"{f.stem}.{k}: cluster key is {where}named like a measure/money "
                    "— a continuous measure is not a filter/join predicate; cluster "
                    "on keys/dates (§B)"
                )
            elif base is None and is_table:
                offenders.append(
                    f"{f.stem}.{k}: cluster key is not a column declared in this "
                    "CREATE TABLE (typo or dropped column)"
                )
    assert not offenders, (
        "CLUSTER-KEY-TYPE violations (cluster on filter/join columns — keys, "
        "business ids, dates; never a continuous measure; max 4 keys. Low-card "
        "keys are fine. See standard §B. Track intentional debt in "
        "standards/rules.yaml known_exceptions for CLUSTER-KEY-TYPE):\n"
        + "\n".join(offenders)
    )


def test_cluster_key_type_detector_fires():
    """Positive proof the CLUSTER-KEY-TYPE detector actually fires — the rule
    matches nothing on main (a forward guard), so without this it could silently
    rot if the regex broke and stay green. Asserts the measure classifier catches
    the target signatures and spares the legitimate ones."""
    # the service_level_pct DECIMAL signature from the #91 review discussion (a
    # DECIMAL measure on a table), and a computed measure alias on a view. (This is
    # a forward guard: no committed clause trips it — #91's head clusters on the
    # exempt `_id`, so this asserts the classifier directly.)
    assert _is_measure_cluster_key("service_level_pct", "DECIMAL", is_table=True)
    assert _is_measure_cluster_key("margin_pct", None, is_table=False)  # gold-view alias
    assert _is_measure_cluster_key("total_fee", "DOUBLE", is_table=True)
    # spared: range-filter DOUBLEs, and keys whose name merely contains a measure word
    assert not _is_measure_cluster_key("latitude", "DOUBLE", is_table=True)
    assert not _is_measure_cluster_key("longitude", "DOUBLE", is_table=True)
    assert not _is_measure_cluster_key("price_tier_sk", None, is_table=False)  # a join key
    assert not _is_measure_cluster_key("cost_center_id", None, is_table=False)
    assert not _is_measure_cluster_key("product_sk", "BIGINT", is_table=True)
    # spared on a view: categorical dimensions whose name contains a measure word
    assert not _is_measure_cluster_key("price_band", None, is_table=False)
    assert not _is_measure_cluster_key("price_type", None, is_table=False)
    assert not _is_measure_cluster_key("cost_center", None, is_table=False)
    assert not _is_measure_cluster_key("margin_tier", None, is_table=False)


# ---------------------------------------------------------------------------
# SCD2-JOIN-CONTRACT: gold / metric-view SQL must resolve SCD2 history correctly.
#
# ORDM facts carry an ingest-resolved, version-specific `_sk`, so a fact->dimension
# join on the dimension's PK `_sk` is a 1:1 equi-join that is already as-of-correct
# (no range join needed — see standard §A.16). The defects this catches are the four
# ways a consuming view gets SCD2 wrong anyway, all invisible today because the
# synthetic generators emit single-version masters (GROUP BY `_sk` == GROUP BY
# `_id`, every join 1:1). This lint reads gold/*.sql and metric-views/*.sql — the
# layers the earlier mandates never globbed, which is why these went uncaught.
#
# Detectors (rule + prose at standard §A.16; design rationale in local notes):
#   history-fanout    a JOIN to an SCD2 table on one of its NON-PK `_sk` columns
#                     with no version predicate -> fans out over every version.
#   reverse-bug       a JOIN equating two `_sk` AND filtering is_current=TRUE ->
#                     the version-specific `_sk` already pins the version, so the
#                     is_current filter drops historical-version fact rows.
#   frag-groupby      GROUP BY a version-specific SCD2 `_sk` (no date/period key)
#                     -> a re-versioned entity fragments across groups.
#   frag-partition    window PARTITION BY a version-specific SCD2 `_sk` (no
#                     date/period key) -> rolling windows reset at each boundary.
#   distinct-count-sk COUNT(DISTINCT ..._sk) / approx_count_distinct over an SCD2
#                     `_sk` -> a re-versioned entity is double-counted.
#
# Intentional debt is tracked via standards/rules.yaml `known_exceptions` for rule
# SCD2-JOIN-CONTRACT, keyed on a `<relpath>::<kind>` signature (mirrors the
# FK-COMPLETENESS escape hatch) so the suite stays green while the list is the
# visible defect ledger that shrinks as fixes land.
# ---------------------------------------------------------------------------

# A version-specific `_sk` in a GROUP BY / PARTITION BY is exempt only when the
# same clause carries a DAY-grain column: within a single calendar day a fact's
# resolved `_sk` is functionally fixed (a daily rollup keyed on `_sk, date_key`
# does not fragment). A multi-day PERIOD token (fiscal_period, week) is NOT
# exempt — a fiscal period spans weeks, long enough to contain a re-version, so
# `GROUP BY supplier_sk, fiscal_period` really does fragment a re-versioned
# entity (the reason gold_supplier_scorecard is a genuine defect).
#
# This is an EXPLICIT day-grain allow-list, not the broad `_date\b`: a `*_date_key`
# is a daily surrogate (unambiguously day grain), and the named transactional day
# columns below are true event dates. A bare `_date` suffix is deliberately NOT
# matched — an incidental non-grain date label (a dimension's own
# `effective_from_date`, a promo `start_date`/`end_date`, a coarse
# `week_ending_date`) must not silently exempt a genuinely-fragmenting clause.
# EXTENDING THIS LIST: it is a closed allow-list, so a genuine new DAY-grain column
# not listed here yields a SAFE false positive (a real day-grain rollup flagged as
# fragmentation) — fix by adding the exact day-grain token here, never by loosening
# back to a broad `_date` match.
# The date/period keys that make grouping by a version-specific `_sk` legitimate: with one
# present, the group is a version-DAY and no re-versioned entity is fragmented. This is a
# closed vocabulary rather than a `\w*_date` pattern on purpose — the latter would also match
# `effective_from_date`, and grouping by a version's own start date does NOT rescue the
# grouping. `trading_date` is the business date across connected-store-signals.
_DATEISH = re.compile(
    r"\w*date_key\b|\bsnapshot_date\b|\bday\b|\border_date\b|\bevent_date\b|\bsale_date\b"
    r"|\btrading_date\b",
    re.I,
)
_SK_TOKEN = re.compile(r"\b(\w+_sk)\b", re.I)
_YAML_BLOCK = re.compile(r"WITH\s+METRICS\s+LANGUAGE\s+YAML\s+AS\s*\$\$(.*?)\$\$", re.I | re.S)
# CREATE [OR REPLACE|REFRESH] [MATERIALIZED] VIEW <name> ... AS <select> — up to
# the SELECT body (self-contained so this suite stays cluster-free / import-light;
# mirrors tools/ordm_config.view_select_body).
_CREATE_VIEW_HDR = re.compile(
    r"CREATE\s+(?:OR\s+(?:REPLACE|REFRESH)\s+)?(?:MATERIALIZED\s+)?VIEW\b.*?\bAS\b",
    re.I | re.S)
_TRAILING_CLUSTER = re.compile(r"\s*CLUSTER\s+BY\s*\([^)]*\)\s*$", re.I)


def _view_select_body(raw: str) -> str:
    """The SELECT body of a CREATE ... VIEW (header + trailing CLUSTER BY removed).
    Raises ValueError when `raw` is not a view (so the caller falls back)."""
    m = _CREATE_VIEW_HDR.search(raw)
    if not m:
        raise ValueError("no CREATE ... VIEW ... AS")
    return _TRAILING_CLUSTER.sub("", raw[m.end():].strip().rstrip(";").rstrip()).rstrip()
# JOIN <fqtn> [AS] [alias] ... ON <predicate> — up to the next clause boundary.
_JOIN_RE = re.compile(
    r"\bJOIN\b\s+(\S+)(?:\s+(?:AS\s+)?([a-z]\w*))?\b(.*?)\bON\b(.+?)"
    r"(?=(?:\bLEFT\b|\bRIGHT\b|\bINNER\b|\bFULL\b|\bJOIN\b|\bWHERE\b|\bGROUP\b|\bWINDOW\b|\bQUALIFY\b|$))",
    re.I | re.S,
)
_GROUPBY_RE = re.compile(
    r"GROUP\s+BY\s+(.+?)(?=(?:\bHAVING\b|\bORDER\b|\bWINDOW\b|\bQUALIFY\b|\bUNION\b|\bSELECT\b|$))",
    re.I | re.S,
)
_PARTITION_RE = re.compile(r"PARTITION\s+BY\s+(.+?)(?=(?:\bORDER\b|\)|\bROWS\b|\bRANGE\b|$))", re.I | re.S)
_DISTINCT_RE = re.compile(r"(?:approx_count_distinct|count\s*\(\s*distinct)\b(.*?)\)", re.I | re.S)
_VERSION_PRED = re.compile(r"is_current|effective_from_date|effective_to_date", re.I)


def _scd2_registry() -> dict:
    """table_stem -> {pk, is_scd2, sk_cols}. Parsed from the committed table DDL."""
    reg: dict[str, dict] = {}
    for f in _all_table_files():
        t = f.read_text()
        m = _PK_RE.search(t)
        if not m:
            continue
        # Classify SCD2-ness on comment-stripped DDL: a non-SCD2 table whose column
        # COMMENTs merely mention these tokens (e.g. product_price's comment says
        # "resolved AS OF effective_from_date") must not be misread as SCD2.
        tl = _strip_sql_comments(t).lower()
        reg[f.stem] = {
            "pk": m.group(2).lower(),
            "is_scd2": ("effective_from_date" in tl and "effective_to_date" in tl and "is_current" in tl),
            "sk_cols": {c.lower() for c in re.findall(r"^\s*([a-z][a-z0-9_]*_sk)\s+BIGINT", t, re.I | re.M)},
        }
    return reg


def _strip_sql_comments(sql: str) -> str:
    """Drop `-- line comments` so a JOIN/GROUP BY/_sk mentioned in a comment (e.g.
    a file header or an explanatory note) can't produce a spurious match."""
    return re.sub(r"--[^\n]*", "", sql)


def _view_source_sql(raw: str) -> str:
    """The SELECT logic of a gold/metric view, comment-stripped. Metric views embed
    it as YAML `source:`; a plain/materialized view is the SELECT body after `AS`
    (header + trailing CLUSTER BY excluded via view_select_body). "" if neither."""
    ym = _YAML_BLOCK.search(raw)
    if ym:
        try:
            doc = yaml.safe_load(ym.group(1))
        except yaml.YAMLError:
            return ""
        if not isinstance(doc, dict):
            return ""
        src = doc.get("source", "") or ""
        # A metric view may also declare joins NATIVELY (a `joins:` list with
        # `source:`/`on:`), not just inside the `source:` SELECT. Synthesize a
        # `JOIN <source> ON <on>` per entry so the same detectors see them (a
        # native join to an SCD2 table on a non-PK `_sk` is the same fan-out the
        # SELECT-embedded form is checked for).
        synth = []
        for j in (doc.get("joins") or []):
            if not isinstance(j, dict):
                continue
            # YAML 1.1 gotcha: a bare `on:` key parses as the boolean True, not the
            # string "on" — so read both. (safe_load turns `on:` -> True.)
            on = j.get("on") or j.get(True)
            if j.get("source") and on:
                synth.append(f"JOIN {j['source']} ON {on}")
        return _strip_sql_comments("\n".join([src, *synth]))
    try:
        return _strip_sql_comments(_view_select_body(raw))
    except ValueError:
        # not a CREATE ... VIEW — scan the raw text, still comment-stripped.
        return _strip_sql_comments(raw)


def _sk_dimension_fields(raw: str, reg: dict) -> list[str]:
    """Metric-view dimension fields whose expr is a bare SCD2 `_sk` (exposes a
    non-portable, version-specific surrogate as a groupable dimension).

    A metric-view column is a DIMENSION purely by virtue of being listed under the
    top-level `fields:` block (or its backward-compatible alias `dimensions:`);
    measures live in the separate `measures:` list. There is no per-field `type:`
    key in the UC metric-view YAML spec (valid field keys: name, expr, comment,
    display_name, format, synonyms) — so this detector keys on the `fields`/
    `dimensions` block membership, not on a `type` value.

    Scoped to SCD2 surrogates only, consistent with the other four detectors and
    §16: a field flags only when its `expr` is the PK `_sk` of a table that is
    actually SCD2 (via `scd2_pk_stem`). A non-SCD2 surrogate exposed as a dimension
    (an append-only fact PK, or a non-master history PK like product_price_sk) is
    not the version-specific-surrogate defect the rule targets."""
    scd2_pk_stem = {d["pk"][:-3] for d in reg.values() if d["is_scd2"] and d["pk"].endswith("_sk")}
    ym = _YAML_BLOCK.search(raw)
    if not ym:
        return []
    try:
        doc = yaml.safe_load(ym.group(1))
    except yaml.YAMLError:
        return []
    out = []
    if isinstance(doc, dict):
        # `fields:` is the current keyword; `dimensions:` is its documented alias.
        dimension_fields = (doc.get("fields") or []) + (doc.get("dimensions") or [])
        for fld in dimension_fields:
            if not isinstance(fld, dict):
                continue
            expr = str(fld.get("expr", "")).strip().lower()
            if expr.endswith("_sk") and expr[:-3] in scd2_pk_stem:
                out.append(fld.get("name"))
    return out


def _scd2_findings(sql: str, reg: dict) -> list[str]:
    """Return `<kind>` finding strings for one view's SELECT body."""
    scd2_pk_stem = {d["pk"][:-3] for d in reg.values() if d["is_scd2"] and d["pk"].endswith("_sk")}
    finds: list[str] = []
    # An is_current filter can sit in a WHERE, not just the JOIN ... ON — the
    # reverse-drop defect is the same either way (a version-specific `_sk` equi-join
    # plus an is_current filter drops historical-version fact rows). `_JOIN_RE` stops
    # at WHERE, so capture the trailing WHERE span and consider both.
    wm = re.search(r"\bWHERE\b(.+?)(?=(?:\bGROUP\b|\bWINDOW\b|\bQUALIFY\b|\bORDER\b|\bUNION\b|$))",
                   sql, re.I | re.S)
    where_has_iscur = bool(wm and re.search(r"\bis_current\s*=\s*(?:true|1)\b", wm.group(1), re.I))

    for jm in _JOIN_RE.finditer(sql):
        fq_tbl, _alias, _mid, on = jm.groups()
        stem = fq_tbl.rstrip(",").split(".")[-1].lower()
        d = reg.get(stem)
        if not d or not d["is_scd2"]:
            continue
        # is_current for THIS join's table can be in the ON or in the WHERE (via the
        # joined table's alias or name). Detect either.
        on_iscur = bool(re.search(r"\bis_current\s*=\s*(?:true|1)\b", on, re.I))
        alias = (_alias or stem)
        where_iscur_this = where_has_iscur and bool(
            wm and re.search(rf"\b{re.escape(alias)}\.is_current\s*=\s*(?:true|1)\b", wm.group(1), re.I))
        has_iscur = on_iscur or where_iscur_this
        has_version = bool(_VERSION_PRED.search(on)) or where_iscur_this
        # reverse-bug: two `_sk` equated AND is_current filtered (ON or WHERE). The
        # version-specific `_sk` already pins the version, so the is_current filter
        # drops historical-version fact rows. Checked BEFORE the has_version short-
        # circuit below — a reverse-bug is DEFINED by carrying is_current.
        eq = re.search(r"\b\w+\.(\w+_sk)\s*=\s*\w+\.(\w+_sk)\b", on, re.I)
        # check BOTH sides of the _sk = _sk equality — an SCD2 PK _sk may be on
        # either side (the other side a non-SCD2 fact/scope _sk).
        if eq and has_iscur and (eq.group(1)[:-3] in scd2_pk_stem or eq.group(2)[:-3] in scd2_pk_stem):
            finds.append("reverse-bug")
            continue
        # history-fanout: joined on a NON-PK `_sk` of this SCD2 table with NO version
        # predicate (its PK `_sk` would be a correct 1:1 equi-join; a genuine as-of
        # predicate — is_current / effective-date — is the correct history join).
        if has_version:
            continue
        for sk_col in sorted(d["sk_cols"]):
            if sk_col != d["pk"] and re.search(rf"\.\s*{sk_col}\b", on, re.I):
                finds.append("history-fanout")
                break

    # reverse-bug, FROM-anchored: the JOIN loop only inspects tables in JOIN position.
    # An SCD2 master in the FROM clause (e.g. `FROM promotion p ... WHERE p.is_current`,
    # with `sc.promo_sk = p.promo_sk` in a join) carries the same reverse-drop shape —
    # its version-specific PK `_sk` is equated, then is_current filters it, dropping
    # historical-version rows. Detect it separately since it never appears after JOIN.
    # A view (with CTEs) has many FROM clauses; scan them all, not just the first.
    for fm in re.finditer(r"\bFROM\s+(\$\{[^}]+\}\.\$\{[^}]+\}\.[a-z_]+|\S+?)(?:\s+(?:AS\s+)?([a-z]\w*))?\s*(?:\bWHERE\b|\bJOIN\b|\bLEFT\b|\bINNER\b|\bGROUP\b|,|$)",
                          sql, re.I):
        if "reverse-bug" in finds:
            break
        from_stem = fm.group(1).rstrip(",").split(".")[-1].lower()
        d = reg.get(from_stem)
        if not (d and d["is_scd2"] and d["pk"].endswith("_sk")):
            continue
        alias = (fm.group(2) or from_stem)
        iscur = bool(wm and re.search(rf"\b{re.escape(alias)}\.is_current\s*=\s*(?:true|1)\b", wm.group(1), re.I))
        pk = d["pk"]
        # its PK _sk equated in some join (either side of an `_sk = _sk`)?
        pk_equated = re.search(rf"\b\w+\.{pk}\s*=\s*\w+\.\w+_sk\b|\b\w+\.\w+_sk\s*=\s*\w+\.{pk}\b", sql, re.I)
        if iscur and pk_equated:
            finds.append("reverse-bug")

    for gm in _GROUPBY_RE.finditer(sql):
        keys = gm.group(1)
        if _DATEISH.search(keys):
            continue
        if any(s[:-3] in scd2_pk_stem for s in _SK_TOKEN.findall(keys)):
            finds.append("frag-groupby")

    for pm in _PARTITION_RE.finditer(sql):
        keys = pm.group(1)
        if _DATEISH.search(keys):
            continue
        if any(s[:-3] in scd2_pk_stem for s in _SK_TOKEN.findall(keys)):
            finds.append("frag-partition")

    for cm in _DISTINCT_RE.finditer(sql):
        if any(s[:-3] in scd2_pk_stem for s in _SK_TOKEN.findall(cm.group(1))):
            finds.append("distinct-count-sk")

    return finds


def _consuming_view_files() -> list[Path]:
    """Gold views + metric views across both layers — the surfaces that consume
    SCD2 masters (NOT the tables/ DDL the other mandates already glob)."""
    return sorted([
        *OUTCOME.glob("*/gold/*.sql"), *OUTCOME.glob("*/metric-views/*.sql"),
        *CORE.glob("*/gold/*.sql"), *CORE.glob("*/metric-views/*.sql"),
    ])


def test_scd2_join_contract():
    """SCD2-JOIN-CONTRACT: gold/metric views resolve SCD2 history correctly.

    Deterministic, cluster-free — parses the committed gold/metric-view SQL (and
    the metric-view YAML `source:`) against the table DDL. Fan-out, reverse-drop,
    fragmentation, and distinct-count-by-surrogate are all caught. Intentional debt
    is enumerated in standards/rules.yaml known_exceptions (`<relpath>::<kind>`)."""
    reg = _scd2_registry()
    excused = set(_exceptions_for("SCD2-JOIN-CONTRACT"))
    offenders = []
    for f in _consuming_view_files():
        raw = f.read_text()
        rel = f.relative_to(REPO_ROOT).as_posix()
        kinds = _scd2_findings(_view_source_sql(raw), reg)
        for name in _sk_dimension_fields(raw, reg):
            kinds.append("sk-dimension")
        for kind in sorted(set(kinds)):
            sig = f"{rel}::{kind}"
            if sig not in excused:
                offenders.append(sig)
    assert not offenders, (
        "SCD2-JOIN-CONTRACT violations (resolve SCD2 as-of at ingest and equi-join "
        "on the dimension PK `_sk`; GROUP BY / PARTITION BY / COUNT DISTINCT on the "
        "durable `_id`, never a version-specific `_sk`; never join fact.`_sk` AND "
        "filter is_current. See standard §A.16. Track intentional debt in "
        "standards/rules.yaml known_exceptions for SCD2-JOIN-CONTRACT):\n"
        + "\n".join(offenders)
    )


def test_scd2_known_exceptions_all_live():
    """No dead SCD2 exceptions: every excused `<relpath>::<kind>` must still be
    produced by the current detectors. Without this, a detector that silently
    stops firing (as `reverse-bug` once did — the is_current short-circuit skipped
    it) leaves its ledger entry a no-op and the suite stays green — the exact
    regression this scaffold exists to prevent. So the ledger can only hold LIVE
    debt; when a defect is fixed, its entry must be removed in the same PR."""
    reg = _scd2_registry()
    live = set()
    for f in _consuming_view_files():
        raw = f.read_text()
        rel = f.relative_to(REPO_ROOT).as_posix()
        kinds = list(_scd2_findings(_view_source_sql(raw), reg))
        kinds += ["sk-dimension"] * len(_sk_dimension_fields(raw, reg))
        for kind in set(kinds):
            live.add(f"{rel}::{kind}")
    dead = sorted(set(_exceptions_for("SCD2-JOIN-CONTRACT")) - live)
    assert not dead, (
        "Dead SCD2-JOIN-CONTRACT exceptions — these signatures are excused in "
        "standards/rules.yaml but no detector produces them anymore (fixed defect "
        "with a stale ledger entry, or a broken detector). Remove them (if fixed) "
        "or repair the detector (if it stopped firing):\n" + "\n".join(dead)
    )


def test_scd2_detectors_fire_on_synthetic_defects():
    """Positive coverage: each detector kind fires on a minimal synthetic snippet,
    so a detector cannot ship asserting a capability with no evidence (every kind
    must also either have a live corpus hit or this test). `reverse-bug` in
    particular had no corpus-independent proof before this."""
    reg = _scd2_registry()
    cases = {
        "reverse-bug": "SELECT 1 FROM f s LEFT JOIN product p ON s.product_sk = p.product_sk AND p.is_current = TRUE",
        "history-fanout": "SELECT 1 FROM f s LEFT JOIN product_price pl ON s.product_sk = pl.product_sk AND pl.price_type = 'list'",
        "frag-groupby": "SELECT profile_sk FROM f GROUP BY profile_sk, fiscal_period",
        "frag-partition": "SELECT LAG(x) OVER (PARTITION BY product_sk, store_sk ORDER BY 1) FROM f",
        "distinct-count-sk": "SELECT approx_count_distinct(product_sk) FROM f",
    }
    for kind, sql in cases.items():
        finds = _scd2_findings(sql, reg)
        assert kind in finds, f"detector {kind} did not fire on its synthetic snippet; got {finds}"

    # sk-dimension is the 6th detector, from the separate _sk_dimension_fields — give
    # it a positive proof too (it exposes an SCD2 `_sk` as a groupable metric dimension).
    # A column under `fields:` IS a dimension; the UC metric-view YAML has no per-field
    # `type:` key, so the snippet declares the dimension purely by fields-block membership.
    sk_dim_mv = (
        "CREATE OR REPLACE VIEW x WITH METRICS LANGUAGE YAML AS$$\n"
        "source: SELECT product_sk FROM f\n"
        "fields:\n"
        "  - name: product_sk\n"
        "    expr: product_sk\n"
        "$$;"
    )
    assert _sk_dimension_fields(sk_dim_mv, reg), "sk-dimension detector did not fire on an SCD2 _sk dimension"
    # a non-SCD2 surrogate exposed as a dimension is NOT flagged (scoped to SCD2).
    non_scd2 = sk_dim_mv.replace("product_sk", "sales_sk")
    assert not _sk_dimension_fields(non_scd2, reg)


def test_scd2_native_metric_view_joins_are_parsed():
    """A metric view declaring a join NATIVELY (a `joins:` list with `source:`/`on:`,
    not inside the `source:` SELECT) must still be checked — otherwise a fan-out to
    an SCD2 history table via the native block is a silent false negative (the same
    class the reverse-bug fix closed). Note the YAML 1.1 `on:` -> True gotcha."""
    reg = _scd2_registry()
    fanout = (
        "CREATE OR REPLACE VIEW x WITH METRICS LANGUAGE YAML AS$$\n"
        "source: SELECT product_sk FROM f\n"
        "joins:\n"
        "  - name: pp\n"
        "    source: cat.sch.product_price\n"
        "    on: product_sk = product_price.product_sk\n"
        "$$;"
    )
    assert "history-fanout" in _scd2_findings(_view_source_sql(fanout), reg)
    # a native join to a NON-SCD2 table (fiscal_calendar) is not flagged.
    benign = fanout.replace("cat.sch.product_price", "cat.sch.fiscal_calendar") \
                   .replace("product_price.product_sk", "fiscal_calendar.date_key") \
                   .replace("product_sk = ", "date_key = ")
    assert not _scd2_findings(_view_source_sql(benign), reg)


def test_scd2_reverse_bug_in_where_is_detected():
    """The reverse-drop defect where the is_current filter sits in the WHERE clause
    (not the JOIN ON) must still be caught — `_JOIN_RE` stops at WHERE, so the
    detector reads the WHERE span too. Without this the empty-ledger-means-correct
    invariant would have a hole."""
    reg = _scd2_registry()
    where_form = "SELECT 1 FROM f s LEFT JOIN product p ON s.product_sk = p.product_sk WHERE p.is_current = TRUE"
    assert "reverse-bug" in _scd2_findings(where_form, reg)
    # a benign current-snapshot join (durable _id + is_current, no _sk=_sk) is fine.
    benign = "SELECT 1 FROM f s JOIN product p ON s.product_id = p.product_id WHERE p.is_current = TRUE"
    assert not _scd2_findings(benign, reg)


def test_scd2_reverse_bug_from_anchored_is_detected():
    """The reverse-drop where the SCD2 master anchors the FROM clause (not a JOIN) —
    `FROM product p ... JOIN f ON f.product_sk = p.product_sk WHERE p.is_current` —
    must be caught; the JOIN loop only inspects joined tables, so a FROM-anchored
    SCD2 master is checked separately. Covers gold_trade_promotion's shape."""
    reg = _scd2_registry()
    from_form = ("SELECT 1 FROM product p JOIN scope sc ON sc.product_sk = p.product_sk "
                 "WHERE p.is_current = true")
    assert "reverse-bug" in _scd2_findings(from_form, reg)
    # benign: FROM an SCD2 master, current-only, but NO _sk equi-join (durable id) — fine.
    benign = ("SELECT 1 FROM product p JOIN scope sc ON sc.product_id = p.product_id "
              "WHERE p.is_current = true")
    assert not _scd2_findings(benign, reg)


# ---------------------------------------------------------------------------
# Metric-view dimension exprs must resolve to a real DDL column.
#
# Recurrence guard for issue #102: BMV `sales_actuals` shipped a `fiscal_season`
# dimension whose `expr: fiscal_calendar.fiscal_season` referenced a column that
# did not exist, which passed every existing check (no test resolved metric-view
# exprs against the DDL) and only failed at deploy-time `apply_ddl` on the serde
# ([FIELD_NOT_FOUND]). This resolves each metric-view DIMENSION expr of the form
# `col` (base table) or `alias.col` (a joined table) against the committed table
# DDL. Deliberately conservative: MEASURE exprs are computed aggregates and are
# NOT checked, and any expr/alias/table it cannot confidently resolve is SKIPPED
# rather than flagged — so it only ever fires on a genuinely dangling column ref.
# ---------------------------------------------------------------------------

# `<schema-or-token>.<table>` — the trailing identifier is the table stem.
_MV_TABLEREF = re.compile(r"[A-Za-z0-9_${}]*\.?([a-z][a-z0-9_]*)\s*$")
# a dimension expr that is a simple column reference: `col` or `alias.col`
_SIMPLE_COLREF = re.compile(r"^([a-z][a-z0-9_]*)(?:\.([a-z][a-z0-9_]*))?$")


def _ddl_columns_by_stem() -> dict:
    """table stem -> set of column names, parsed from the committed table DDL.

    SCOPE (m2): globs `*/tables/*.sql` only, NOT gold views under `gold/`. A metric
    view's base `source:` is usually a gold view, so a bare-column dimension expr
    against the base resolves to a stem absent here and is SKIPPED (the conservative
    unresolvable-stem path in _dangling_dimension_refs). A typo'd ref to a *base
    gold-source* column is therefore deliberately out of scope; the guard covers
    JOINED-table refs (the exact #102 case) with zero false positives. Covering
    gold-source columns would require parsing gold view outputs (a follow-up)."""
    out: dict[str, set] = {}
    coldef = re.compile(
        r"^\s+([a-z][a-z0-9_]*)\s+(?:STRING|INT|BIGINT|DATE|TIMESTAMP|BOOLEAN|DECIMAL|DOUBLE|FLOAT)\b",
        re.I | re.M,
    )
    for f in _all_table_files():
        body = _strip_sql_comments(f.read_text())
        cols = {m.group(1).lower() for m in coldef.finditer(body)}
        if cols:
            out[f.stem] = cols
    return out


def _mv_alias_to_stem(doc: dict) -> dict:
    """Map each metric-view alias -> table stem. The `source:` is the base table
    (alias `source`); each `joins[].name` is an alias resolving to that join's
    `source:` table. Returns only aliases whose table resolves to a known stem."""
    alias: dict[str, str] = {}
    src = doc.get("source")
    if isinstance(src, str):
        m = _MV_TABLEREF.search(src.strip())
        if m:
            alias["source"] = m.group(1)
    for j in (doc.get("joins") or []):
        if not isinstance(j, dict):
            continue
        name, jsrc = j.get("name"), j.get("source")
        if isinstance(name, str) and isinstance(jsrc, str):
            m = _MV_TABLEREF.search(jsrc.strip())
            if m:
                alias[name.lower()] = m.group(1)
    return alias


def _dangling_dimension_refs(raw: str, ddl_cols: dict) -> list[str]:
    """`<dim-name>:<alias.col>` for every metric-view dimension whose simple
    column-ref expr does NOT resolve to a real DDL column. Skips computed exprs
    and any alias/table that can't be resolved (conservative — no false flags)."""
    ym = _YAML_BLOCK.search(raw)
    if not ym:
        return []
    try:
        doc = yaml.safe_load(ym.group(1))
    except yaml.YAMLError:
        return []
    if not isinstance(doc, dict):
        return []
    alias = _mv_alias_to_stem(doc)
    base = alias.get("source")
    out = []
    for fld in (doc.get("fields") or []) + (doc.get("dimensions") or []):
        if not isinstance(fld, dict):
            continue
        expr = str(fld.get("expr", "")).strip()
        m = _SIMPLE_COLREF.match(expr)
        if not m:
            continue  # computed / non-simple expr — not this check's job
        qual, col = m.group(1), m.group(2)
        if col is None:
            # bare column -> base table
            col, stem = qual, base
        else:
            stem = alias.get(qual.lower())
        if stem is None or stem not in ddl_cols:
            continue  # unresolvable alias/table — skip rather than false-flag
        if col.lower() not in ddl_cols[stem]:
            out.append(f"{fld.get('name')}:{expr}")
    return out


def test_metric_view_dimension_exprs_resolve_to_real_columns():
    """Every metric-view dimension expr that is a simple `col` / `alias.col`
    reference must point at a column that exists in the referenced table's DDL.
    Guards against issue #102 (a dimension mapped to a non-existent calendar
    column) recurring — that shipped because nothing resolved metric-view exprs
    against the DDL until deploy time."""
    ddl_cols = _ddl_columns_by_stem()
    offenders = []
    for f in _consuming_view_files():
        if f.parent.name != "metric-views":
            continue
        for ref in _dangling_dimension_refs(f.read_text(), ddl_cols):
            offenders.append(f"{f.relative_to(REPO_ROOT).as_posix()}::{ref}")
    assert not offenders, (
        "Metric-view dimension expr(s) reference a column absent from the table's "
        "DDL (would fail apply_ddl with FIELD_NOT_FOUND — see issue #102). Repoint "
        "to a real column or add the column to the conformed table:\n"
        + "\n".join(offenders)
    )


def test_metric_view_dimension_resolver_catches_a_dangling_ref():
    """Positive coverage: the resolver actually fires on a dangling ref, so it
    can't silently stop working and leave the guard vacuously green."""
    ddl_cols = {"fiscal_calendar": {"date_key", "fiscal_quarter", "fiscal_period"}}
    bad = (
        "CREATE OR REPLACE VIEW x WITH METRICS LANGUAGE YAML AS$$\n"
        "source: cat.sch.gold_sales_actuals\n"
        "joins:\n"
        "  - name: fiscal_calendar\n"
        "    source: cat.sch.fiscal_calendar\n"
        "    on: source.date_key = fiscal_calendar.date_key\n"
        "fields:\n"
        "  - name: fiscal_season\n"
        "    expr: fiscal_calendar.fiscal_season\n"
        "$$;\n"
    )
    assert _dangling_dimension_refs(bad, ddl_cols) == ["fiscal_season:fiscal_calendar.fiscal_season"]
    good = bad.replace("fiscal_calendar.fiscal_season", "fiscal_calendar.fiscal_quarter")
    assert _dangling_dimension_refs(good, ddl_cols) == []
