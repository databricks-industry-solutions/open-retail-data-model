"""Pin the ODCS contract generator (tools/generate_odcs.py) so its DDL parsing
and contract assembly cannot regress.

These exercise the exact production functions the generator uses — pure-python,
text-only parsing (no Spark, no SDK, no Databricks connection), matching the
import-safe style of the rest of tests/. ODCS is an OPTIONAL ORDM integration;
this just proves that when an adopter runs the generator, it faithfully reflects
the committed DDL / relationships / checks (ORDM's source of truth).

conftest.py puts the repo root on sys.path.
"""
import pytest

from tools.ordm_ddl.parser import _balanced_body
from tools.generate_odcs import (
    _check_col,
    _metric_view_columns,
    _metric_view_description,
    build_contract,
    discover_units,
    parse_checks,
    parse_columns,
    parse_relationships,
    parse_table_sql,
)

# A compact but representative CREATE TABLE: IDENTITY surrogate, NOT NULL business
# key, a DECIMAL(p,s) (comma inside the type must NOT split the column), an inline
# `-- section` banner (must NOT be parsed as a column — this is the phantom-column
# regression), an enum column, a table COMMENT, a role tag and a PII column tag.
SAMPLE_TABLE = """
-- ============================================================
-- ORDM · Canonical Core · Sample
-- ============================================================
CREATE TABLE IF NOT EXISTS ${catalog}.${customer_schema}.widget (
  widget_sk    BIGINT GENERATED ALWAYS AS IDENTITY
                 COMMENT 'Surrogate key.',
  widget_id    STRING NOT NULL COMMENT 'Business key.',

  -- Attributes, conformed to every other master
  status       STRING COMMENT 'Lifecycle. Allowed values: active, inactive.',
  price_amount DECIMAL(18,2) COMMENT 'Price in base currency.',
  secret_id    STRING COMMENT 'Sensitive.',

  CONSTRAINT pk_widget PRIMARY KEY (widget_sk)
)
USING DELTA
COMMENT 'ORDM sample widget master.';

ALTER TABLE ${catalog}.${customer_schema}.widget SET TAGS ('dbx_data_type' = 'master');
ALTER TABLE ${catalog}.${customer_schema}.widget ALTER COLUMN secret_id SET TAGS ('dbx_pii' = 'true');
"""

SAMPLE_RELATIONSHIPS = """
ALTER TABLE ${catalog}.${customer_schema}.widget
  ADD CONSTRAINT fk_widget_profile
  FOREIGN KEY (profile_sk) REFERENCES ${catalog}.${customer_schema}.profile (profile_sk);

ALTER TABLE ${catalog}.${customer_schema}.widget
  ADD CONSTRAINT chk_widget_status
  CHECK (status IS NULL OR status IN ('active', 'inactive'));
"""

SAMPLE_CHECKS = """
-- check: widget_keys_not_null | severity: error
-- Keys are mandatory.
SELECT * FROM ${catalog}.${customer_schema}.widget
WHERE widget_sk IS NULL OR widget_id IS NULL;

-- check: widget_status_domain | severity: warn
SELECT * FROM ${catalog}.${customer_schema}.widget
WHERE status NOT IN ('active', 'inactive');
"""


# ------------------------------------------------------------
# Column parsing
# ------------------------------------------------------------

def test_parse_columns_names_and_types():
    # Feed the BALANCED column-list body (what the real parser passes), not a naive
    # slice-to-EOF that trails the table's `)` + ALTER statements — the parser now
    # fails loud on an unbalanced body (#55 review Mnr1).
    cols = parse_columns(_balanced_body(SAMPLE_TABLE, SAMPLE_TABLE.index("(")))
    by_name = {c["name"]: c for c in cols}
    # Every real column is present; the `-- section` banner is NOT a column.
    assert set(by_name) == {"widget_sk", "widget_id", "status", "price_amount", "secret_id"}
    # DECIMAL(18,2) survives the top-level comma split intact.
    assert by_name["price_amount"]["sql_type"] == "DECIMAL(18,2)"
    # NOT NULL becomes required; a plain column does not.
    assert by_name["widget_id"]["required"] is True
    assert by_name["status"]["required"] is False
    # Column comments are captured.
    assert by_name["widget_id"]["comment"] == "Business key."


def test_parse_table_pk_role_and_pii():
    tbl = parse_table_sql(SAMPLE_TABLE)
    assert tbl["name"] == "widget"
    assert tbl["schema_token"] == "customer_schema"
    assert tbl["primary_key"] == ["widget_sk"]
    assert tbl["role"] == "master"
    assert tbl["comment"] == "ORDM sample widget master."
    assert tbl["column_tags"].get("secret_id") == ["dbx_pii"]


# ------------------------------------------------------------
# Relationships (FK + enum CHECK) and DQ checks
# ------------------------------------------------------------

def test_parse_relationships_fk_and_check():
    rels = parse_relationships(SAMPLE_RELATIONSHIPS)
    fk = rels["fks"]["widget"][0]
    assert fk["cols"] == ["profile_sk"]
    assert fk["parent"] == "profile" and fk["pcols"] == ["profile_sk"]
    chk = rels["checks"]["widget"][0]
    assert chk["col"] == "status"
    assert chk["values"] == ["active", "inactive"]


def test_check_col_resolves_enum_range_and_function_forms():
    # AI review #41 M1: range/comparison CHECKs must resolve a column too, else they
    # silently drop out of the contract (only enum `col IN (...)` used to resolve).
    assert _check_col("status IS NULL OR status IN ('a', 'b')") == "status"
    assert _check_col("calendar_month IS NULL OR calendar_month BETWEEN 1 AND 12") == "calendar_month"
    assert _check_col("rate IS NULL OR rate > 0") == "rate"
    assert _check_col("char_length(from_currency_code) = 3") == "from_currency_code"


def test_range_check_is_retained_with_col():
    rel = "ALTER TABLE ${catalog}.${s}.t ADD CONSTRAINT chk_t_qty CHECK (qty IS NULL OR qty >= 0);"
    chk = parse_relationships(rel)["checks"]["t"][0]
    assert chk["col"] == "qty" and chk["values"] == []  # resolves a col; not an enum


def test_parse_checks_header_severity_and_query():
    checks = parse_checks(SAMPLE_CHECKS)
    assert [c["name"] for c in checks] == ["widget_keys_not_null", "widget_status_domain"]
    assert checks[0]["severity"] == "error" and checks[1]["severity"] == "warn"
    assert checks[0]["table"] == "widget"
    assert checks[0]["query"].startswith("SELECT * FROM ${catalog}.${customer_schema}.widget")
    assert not checks[0]["query"].rstrip().endswith(";")  # trailing ; stripped


# ------------------------------------------------------------
# End-to-end contract assembly against the REAL committed repo artifacts.
# ------------------------------------------------------------

def test_build_contract_customer_is_valid_odcs():
    units = {u.rsplit("/", 1)[-1]: u for u in discover_units({"customer"})}
    contract = build_contract(units["customer"], catalog="test_cat", overrides={})
    assert contract is not None

    # ODCS v3.1.0 fundamentals.
    assert contract["apiVersion"] == "v3.1.0"
    assert contract["kind"] == "DataContract"
    assert contract["id"] and contract["version"] and contract["status"]
    assert isinstance(contract["schema"], list) and contract["schema"]

    profile = next(o for o in contract["schema"] if o["name"] == "profile")
    # physicalName resolves the catalog + the databricks.yml schema (never hardcoded).
    assert profile["physicalName"] == "test_cat.customer.profile"
    assert profile["physicalType"] == "table"

    props = {p["name"]: p for p in profile["properties"]}
    # Surrogate PK is flagged AND forced required (a PK is non-nullable even without
    # a literal NOT NULL on the IDENTITY surrogate — AI review #41 M2).
    assert props["profile_sk"]["primaryKey"] is True
    assert props["profile_sk"]["required"] is True
    assert props["last_name"]["classification"] == "restricted"
    assert "dbx_pii_name" in props["last_name"]["tags"]
    # Every property has an ODCS logicalType + physicalType.
    assert all("logicalType" in p and "physicalType" in p for p in profile["properties"])

    # error/warn checks.sql -> SQL quality rules asserting 0 violating rows.
    q = profile["quality"]
    assert all(rule["type"] == "sql" for rule in q)
    assert all(rule["mustBe"] == 0 and rule["unit"] == "rows"
               for rule in q if rule["severity"] != "info")


def test_metric_checks_are_informational_not_zero_row_assertions():
    # AI review #41 H1: `metric`-severity checks SELECT an aggregate to report, not
    # violating rows, so they must NOT be coerced to `mustBe: 0`. They carry
    # `severity: info` and no `mustBe`; error/warn checks keep the zero-row assertion.
    units = {u.rsplit("/", 1)[-1]: u for u in discover_units({"early-risk-detection"})}
    contract = build_contract(units["early-risk-detection"], catalog="c", overrides={})
    rules = [r for o in contract["schema"] for r in o.get("quality", []) if r.get("type") == "sql"]
    info = [r for r in rules if r["severity"] == "info"]
    assert info, "expected at least one metric check carried as informational"
    assert all("mustBe" not in r and "unit" not in r for r in info)
    assert all(r["mustBe"] == 0 and r["unit"] == "rows" for r in rules if r["severity"] != "info")


def test_check_query_tokens_are_resolved():
    # AI review #41 H1: quality.query must resolve ${catalog}/${schema} the same way
    # physicalName does, so a consumer (DQX) executes concrete SQL, not literal ${catalog}.
    units = {u.rsplit("/", 1)[-1]: u for u in discover_units({"customer"})}
    c = build_contract(units["customer"], catalog="cat9", overrides={})
    qs = [r["query"] for o in c["schema"] for r in o.get("quality", []) if r.get("type") == "sql"]
    assert qs, "expected object-level SQL quality rules with queries"
    assert all("${" not in q for q in qs), "quality.query must not contain raw ${...} tokens"
    assert any("cat9.customer." in q for q in qs), "query should be catalog-qualified when --catalog is set"


def test_build_contract_schema_override_wins():
    units = {u.rsplit("/", 1)[-1]: u for u in discover_units({"store"})}
    contract = build_contract(units["store"], catalog="c", overrides={"store_schema": "retail_store"})
    obj = contract["schema"][0]
    assert obj["physicalName"].startswith("c.retail_store.")


def test_discover_units_filter():
    names = {u.rsplit("/", 1)[-1] for u in discover_units({"customer", "product"})}
    assert names == {"customer", "product"}


def test_gold_view_partial_comments_does_not_drop_columns(tmp_path):
    """Column-drop regression (reported 2026-07-12): a gold view whose comments.sql
    documents only SOME projected columns must emit ALL of them in the contract (UNION of
    the sqlglot SELECT projection and comments.sql), mirroring DdlParser so the contract
    and the explorer model never diverge."""
    (tmp_path / "gold").mkdir()
    (tmp_path / "gold" / "gold_x.sql").write_text(
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${s}.gold_x AS\n"
        "SELECT s.product_id, s.store_id, CAST(s.date_key AS DATE) AS date_key,\n"
        "       CAST(NULL AS DOUBLE) AS forecast, CAST(NULL AS DOUBLE) AS growth_pct\n"
        "FROM ${catalog}.${s}.gold_sales_actuals s;\n"
    )
    (tmp_path / "comments.sql").write_text(
        "COMMENT ON COLUMN ${catalog}.${s}.gold_x.growth_pct IS 'YoY growth.';\n"
        "COMMENT ON COLUMN ${catalog}.${s}.gold_x.forecast IS 'Baseline forecast.';\n"
    )
    contract = build_contract(str(tmp_path), catalog="", overrides={})
    obj = next(o for o in contract["schema"] if o["name"] == "gold_x")
    names = [p["name"] for p in obj["properties"]]
    assert names == ["product_id", "store_id", "date_key", "forecast", "growth_pct"]
    desc = {p["name"]: p.get("description") for p in obj["properties"]}
    assert desc["growth_pct"] == "YoY growth."      # documented -> described
    assert "product_id" in names                     # undocumented -> present, not dropped


# ---- UC Metric Views in the contract -----------------------------------------------------

_METRIC_VIEW_SQL = """
-- Metric View: sample
CREATE OR REPLACE VIEW ${catalog}.${customer_schema}.mv_sample
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "A sample metric view."
source: SELECT segment, order_date, spend FROM ${catalog}.${customer_schema}.something
fields:
  - name: segment
    expr: segment
    comment: "Behavioral segment label."
  - name: order_date
    expr: order_date
    comment: "Order date."
    format:
      type: date
measures:
  - name: member_count
    expr: COUNT(DISTINCT profile_id)
    comment: "Distinct members."
    format:
      type: number
  - name: reach_rate
    expr: SUM(reachable) / nullif(COUNT(*), 0)
    comment: "Reachable share."
    format:
      type: percentage
$$;
"""


def test_metric_view_columns_types_fields_and_measures():
    """_metric_view_columns reads the WITH METRICS YAML body: fields then measures, each with
    the YAML comment as description. Without a type schema, a field takes its type from an
    explicit format.type or is left untyped, and a measure defaults to number (format.type
    overrides both)."""
    cols = _metric_view_columns(_METRIC_VIEW_SQL)
    by = {c["name"]: c for c in cols}
    assert [c["name"] for c in cols] == ["segment", "order_date", "member_count", "reach_rate"]
    assert by["segment"]["logical_type"] is None              # field, no format, no schema -> untyped
    assert by["order_date"]["logical_type"] == "date"         # field, format.type: date
    assert by["member_count"]["logical_type"] == "number"     # measure -> number
    assert by["reach_rate"]["logical_type"] == "number"       # measure, percentage is numeric
    assert by["segment"]["comment"] == "Behavioral segment label."
    # A non-metric-view SQL (no WITH METRICS body) yields no columns.
    assert _metric_view_columns("CREATE OR REPLACE VIEW x AS SELECT 1;") == []


def test_build_contract_emits_typed_metric_view_objects():
    """A package's metric-views/*.sql are emitted as `metric-view`-tagged view objects whose
    every column carries a logicalType (never left untyped) and no physicalType (they are
    computed dimensions/measures with no physical DDL type). Regression for the ODCS gap:
    metric views were previously excluded from every contract."""
    units = {u.rsplit("/", 1)[-1]: u
             for u in discover_units({"actionable-customer-understanding"})}
    contract = build_contract(units["actionable-customer-understanding"],
                              catalog="test_cat", overrides={})
    mvs = [o for o in contract["schema"] if "metric-view" in (o.get("tags") or [])]
    assert mvs, "expected metric-view objects in the contract"
    # the four ACU metric views are all present
    assert {o["name"] for o in mvs} >= {
        "mv_segment_performance", "mv_market_share", "mv_product_affinity",
        "mv_competitive_position"}
    for o in mvs:
        assert o["physicalType"] == "view"
        assert o["physicalName"].startswith("test_cat.")
        props = o.get("properties", [])
        assert props, f"{o['name']} has no columns"
        # every metric-view column is typed (logicalType) and carries no physicalType
        assert all("logicalType" in p for p in props), f"{o['name']} has an untyped column"
        assert all("physicalType" not in p for p in props), \
            f"{o['name']} metric-view column must not carry a physicalType"
    # the addition is purely additive: the package's gold views are still present
    names = {o["name"] for o in contract["schema"]}
    assert "gold_customer_ltv" in names


def test_metric_view_description_prefers_yaml_comment_over_banner():
    """AI review #140 M1: a metric view's object description must be the authored YAML
    top-level `comment:` (grain / double-count caveats), not the SQL header banner, which is a
    generic 'Metric View: <name>' line and can concatenate unrelated banner lines. The banner is
    only a fallback when the YAML carries no comment."""
    assert _metric_view_description(_METRIC_VIEW_SQL, "Metric View: sample") == \
        "A sample metric view."
    no_comment = _METRIC_VIEW_SQL.replace('comment: "A sample metric view."\n', "")
    assert _metric_view_description(no_comment, "Metric View: sample") == "Metric View: sample"
    # and in a real generated contract, no metric-view object carries the generic banner
    units = {u.rsplit("/", 1)[-1]: u
             for u in discover_units({"actionable-customer-understanding"})}
    contract = build_contract(units["actionable-customer-understanding"],
                              catalog="c", overrides={})
    mvs = [o for o in contract["schema"] if "metric-view" in (o.get("tags") or [])]
    assert mvs
    assert all(not (o.get("description") or "").startswith("Metric View:") for o in mvs)


def test_every_shipped_metric_view_has_typed_columns():
    """AI review #140 rounds 2 and 5. Across ALL packages: every metric-view object has columns,
    no column carries a physicalType, every MEASURE is typed, and a FIELD is untyped only when its
    type is genuinely unknown (no source inference, no explicit format.type). In particular no
    field is ever guessed as string: three date keys whose upstream gold type is unresolved used to
    ship as logicalType string, which is confidently wrong."""
    import glob, os
    import tools.generate_odcs as g
    schema = g._default_type_schema()
    checked = 0
    for path in sorted(glob.glob(os.path.join(g.OUTCOME_PACKAGES, "*", "metric-views", "*.sql"))):
        sql = open(path).read()
        body = g._metric_view_yaml(sql)
        cols = g._metric_view_columns(sql, schema)
        assert cols, f"{path} has no columns"
        checked += 1
        inferred = g._metric_view_inferred_types(body, schema)
        fields = {f.get("name"): f for f in (body.get("fields") or [])}
        for c in cols:
            if c["name"] not in fields:
                assert c["logical_type"], f"{path}: measure {c['name']} is untyped"
                continue
            declared = ((fields[c["name"]].get("format") or {}).get("type"))
            if c["logical_type"] is None:
                assert c["name"] not in inferred and not declared, \
                    f"{path}: field {c['name']} left untyped although its type is known"
            elif c["logical_type"] == "string":
                assert inferred.get(c["name"]) or declared, \
                    f"{path}: field {c['name']} guessed as string"
    assert checked >= 50, f"expected the model's metric views to be checked, got {checked}"
    # the contract never carries a physicalType on a metric-view column
    for unit in discover_units(None):
        contract = build_contract(unit, catalog="c", overrides={})
        for o in (contract or {}).get("schema", []):
            if "metric-view" in (o.get("tags") or []):
                assert o.get("properties"), f"{o['name']} has no columns"
                assert all("physicalType" not in p for p in o["properties"])


def test_metric_view_field_measure_name_collision_keeps_field_and_warns(capsys):
    """AI review #140 m1: a measure that reuses a field's name is not dropped silently; the
    field wins (documented precedence) and the collision is reported on stderr."""
    sql = _METRIC_VIEW_SQL.replace("  - name: member_count\n", "  - name: segment\n")
    cols = _metric_view_columns(sql)
    names = [c["name"] for c in cols]
    assert names.count("segment") == 1
    assert next(c for c in cols if c["name"] == "segment")["logical_type"] is None  # field kept
    assert "declared as both a field and a measure" in capsys.readouterr().err


def test_metric_view_columns_infer_types_from_source():
    """AI review #140 M1: a dimension with no format.type must not default to string when its
    real type is knowable. Columns are typed by annotating `SELECT <expr> AS <name> FROM
    <source>` against the silver + gold schema; format.type / kind defaults apply only to what
    sqlglot cannot resolve."""
    sql = """
CREATE OR REPLACE VIEW ${catalog}.${customer_schema}.mv_t
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
source: SELECT order_date, store_id, is_online, amount FROM ${catalog}.${customer_schema}.fact_t
fields:
  - name: order_date
    expr: order_date
  - name: is_online
    expr: is_online
  - name: label
    expr: unknown_col
measures:
  - name: n_orders
    expr: COUNT(*)
  - name: avg_amount
    expr: SUM(amount) / NULLIF(COUNT(*), 0)
$$;
"""
    schema = {"fact_t": {"order_date": "DATE", "store_id": "STRING",
                         "is_online": "BOOLEAN", "amount": "DECIMAL(18,2)"}}
    by = {c["name"]: c["logical_type"] for c in _metric_view_columns(sql, schema)}
    assert by["order_date"] == "date"          # was string before inference
    assert by["is_online"] == "boolean"
    assert by["n_orders"] == "integer"         # COUNT -> integer, not just number
    assert by["avg_amount"] == "number"        # a ratio stays non-integer
    assert by["label"] is None                 # unresolvable field -> untyped, never a guessed string
    # without a schema the old defaults still apply
    assert {c["name"]: c["logical_type"] for c in _metric_view_columns(sql)}["order_date"] is None


def test_shipped_metric_view_date_dimension_is_typed_date():
    """The reviewer's concrete case: commerce-media-networks mv_campaign_performance.metric_date
    declares no format.type but is a DATE in its source, so the contract must say date."""
    units = {u.rsplit("/", 1)[-1]: u for u in discover_units({"commerce-media-networks"})}
    contract = build_contract(units["commerce-media-networks"], catalog="c", overrides={})
    mv = next(o for o in contract["schema"] if o["name"] == "mv_campaign_performance")
    props = {p["name"]: p for p in mv["properties"]}
    assert props["metric_date"]["logicalType"] == "date"
    assert "physicalType" not in props["metric_date"]


def test_metric_view_agent_metadata_reaches_the_contract():
    """AI review #140 M1: display_name and synonyms are the terms a Genie-style consumer resolves
    against, so they must survive into the contract (ODCS businessName and a `synonyms`
    customProperty), not just the source YAML."""
    sql = _METRIC_VIEW_SQL.replace(
        '    comment: "Behavioral segment label."\n',
        '    comment: "Behavioral segment label."\n'
        '    display_name: "Segment"\n'
        '    synonyms: ["audience", "cohort"]\n')
    seg = next(c for c in _metric_view_columns(sql) if c["name"] == "segment")
    assert seg["business_name"] == "Segment"
    assert seg["synonyms"] == ["audience", "cohort"]
    # end to end on a shipped package: ACU's product_affinity.category carries both
    units = {u.rsplit("/", 1)[-1]: u for u in discover_units({"actionable-customer-understanding"})}
    contract = build_contract(units["actionable-customer-understanding"], catalog="c", overrides={})
    mv = next(o for o in contract["schema"] if o["name"] == "mv_product_affinity")
    cat = next(p for p in mv["properties"] if p["name"] == "category")
    assert cat["businessName"] == "Category"
    syn = next(cp["value"] for cp in cat["customProperties"] if cp["property"] == "synonyms")
    assert "product_category" in syn


def test_metric_view_type_inference_retries_columns_a_partial_pass_missed(monkeypatch):
    """AI review #140 m1: when the combined pass types SOME columns, each still-untyped column is
    retried on its own instead of silently keeping its kind default."""
    import tools.generate_odcs as g
    calls = []

    def fake_infer(sql, schema):
        calls.append(sql)
        if "AS `segment`" in sql and "AS `member_count`" in sql:   # combined pass: partial
            return {"segment": "STRING"}
        if "AS `member_count`" in sql:                              # single-column retry
            return {"member_count": "BIGINT"}
        return {}

    monkeypatch.setattr(g, "infer_gold_column_types", fake_infer)
    by = {c["name"]: c["logical_type"] for c in g._metric_view_columns(_METRIC_VIEW_SQL, {"x": {}})}
    assert by["member_count"] == "integer"     # recovered by the per-column retry
    assert len(calls) > 1                      # the retry actually ran


# ODCS v3.1.0 logicalType enum, from bitol-io odcs-json-schema-v3.1.0.json.
_ODCS_V310_LOGICAL_TYPES = {"string", "date", "timestamp", "time", "number", "integer",
                            "object", "array", "boolean"}


def test_every_emitted_logical_type_is_in_the_odcs_v310_enum():
    """AI review #140 round 6: a strict ODCS consumer validates logicalType against the spec's
    closed enum, and metric-view columns have no physicalType to fall back on. Pin that every
    logicalType the generator emits, on any object kind, is a valid ODCS v3.1.0 value
    (timestamp IS in v3.1.0, so timestamp dimensions are conformant as emitted)."""
    bad = []
    for unit in discover_units(None):
        contract = build_contract(unit, catalog="c", overrides={})
        for o in (contract or {}).get("schema", []):
            for p in o.get("properties", []):
                lt = p.get("logicalType")
                if lt is not None and lt not in _ODCS_V310_LOGICAL_TYPES:
                    bad.append(f"{o['name']}.{p['name']}={lt}")
    assert not bad, "logicalType outside the ODCS v3.1.0 enum: " + ", ".join(bad[:20])
