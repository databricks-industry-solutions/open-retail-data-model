from tools.ordm_ddl.parser import (
    DdlParser,
    _sqlglot_view_columns,
    infer_gold_column_types,
    infer_all_gold_types,
)


def test_sqlglot_fallback_extracts_cte_view_columns():
    # A gold view whose columns comments.sql does NOT document (multi-CTE): the sqlglot
    # fallback derives its output column NAMES from the final SELECT past the WITH block,
    # in projection order. Mirrors the real gold_promo_roi_by_category shape.
    sql = (
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${promo_schema}.gold_x AS\n"
        "WITH base AS (\n"
        "  SELECT id, amt FROM ${catalog}.${sales_schema}.sales\n"
        ")\n"
        "SELECT id AS promo_id, amt AS total_spend, amt * 2 AS doubled\n"
        "FROM base;\n"
    )
    assert _sqlglot_view_columns(sql) == ["promo_id", "total_spend", "doubled"]


def test_sqlglot_fallback_is_graceful():
    # No SELECT projection / empty input yields [] (view stays empty), never raises.
    assert _sqlglot_view_columns("") == []
    assert _sqlglot_view_columns("COMMENT ON COLUMN ${catalog}.${s}.t.c IS 'x';") == []


def test_infer_gold_column_types_from_silver_schema():
    # Gold view over a silver source: types are inferred from the source column types
    # (passed through the SELECT) plus literal/expression annotation, so the mview carries
    # SQL types even though its DDL declares none. TEXT/VARCHAR normalize to STRING.
    sql = (
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${promo_schema}.gold_x AS\n"
        "SELECT s.id AS promo_id, s.amt AS spend, s.amt * 2 AS doubled,\n"
        "       CAST(s.note AS STRING) AS note\n"
        "FROM ${catalog}.${sales_schema}.sales AS s;\n"
    )
    schema = {"sales": {"id": "STRING", "amt": "BIGINT", "note": "TEXT"}}
    types = infer_gold_column_types(sql, schema)
    assert types["promo_id"] == "STRING"
    assert types["spend"] == "BIGINT"
    assert types["doubled"] == "BIGINT"
    assert types["note"] == "STRING"


def test_infer_gold_column_types_is_graceful():
    # Empty input, no SELECT, or an unknown source resolves to {} (columns stay
    # type-less) rather than raising.
    assert infer_gold_column_types("", {}) == {}
    assert infer_gold_column_types(
        "COMMENT ON COLUMN ${catalog}.${s}.t.c IS 'x';", {}) == {}
    # Unknown source table: qualify can't resolve columns; degrade to {} not a crash.
    unresolved = infer_gold_column_types(
        "SELECT x FROM ${catalog}.${s}.missing;", {})
    assert isinstance(unresolved, dict)


def test_infer_all_gold_types_resolves_gold_on_gold():
    # A gold view built on ANOTHER gold view (not silver) resolves nothing in a single
    # silver-only pass; the topological fixpoint infers the parent view first, feeds its
    # types back, then resolves the child. Mirrors gold_promo_roi -> gold_promo_roi_by_category.
    silver = {"sales": {"id": "STRING", "amt": "BIGINT"}}
    gold_sql = {
        # parent reads silver
        "gold_parent": (
            "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${s}.gold_parent AS\n"
            "SELECT s.id AS promo_id, s.amt AS spend FROM ${catalog}.${s}.sales AS s;"
        ),
        # child reads the parent GOLD view, not silver
        "gold_child": (
            "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${s}.gold_child AS\n"
            "SELECT g.promo_id, g.spend FROM ${catalog}.${s}.gold_parent AS g;"
        ),
    }
    # Single silver-only pass leaves the child blank.
    assert infer_gold_column_types(gold_sql["gold_child"], silver) == {}
    # Topological pass resolves both.
    out = infer_all_gold_types(silver, gold_sql)
    assert out["gold_parent"] == {"promo_id": "STRING", "spend": "BIGINT"}
    assert out["gold_child"] == {"promo_id": "STRING", "spend": "BIGINT"}

SAMPLE = """
-- ============================================================
-- ORDM · Canonical Core · Sample
-- ============================================================
CREATE TABLE IF NOT EXISTS ${catalog}.${customer_schema}.widget (
  widget_sk    BIGINT GENERATED ALWAYS AS IDENTITY COMMENT 'Surrogate key.',
  widget_id    STRING NOT NULL COMMENT 'Business key.',
  -- Attributes
  status       STRING COMMENT 'Lifecycle. Allowed values: active, inactive.',
  price_amount DECIMAL(18,2) COMMENT 'Price.',
  secret_id    STRING COMMENT 'Sensitive.',
  CONSTRAINT pk_widget PRIMARY KEY (widget_sk)
) USING DELTA COMMENT 'ORDM sample widget master.';
ALTER TABLE ${catalog}.${customer_schema}.widget SET TAGS ('dbx_data_type' = 'master');
ALTER TABLE ${catalog}.${customer_schema}.widget ALTER COLUMN secret_id SET TAGS ('dbx_pii' = 'true');
"""

def test_parse_table_columns_pk_role_pii():
    t = DdlParser().parse_table(SAMPLE)
    by = {c.name: c for c in t.columns}
    assert set(by) == {"widget_sk", "widget_id", "status", "price_amount", "secret_id"}  # no `-- Attributes` phantom
    assert by["price_amount"].sql_type == "DECIMAL(18,2)"   # comma inside type not split
    assert by["widget_id"].required is True and by["status"].required is False
    assert t.primary_key == ("widget_sk",) and t.role == "master"
    assert by["secret_id"].is_pii is True

def test_check_col_resolves_enum_range_comparison_function():
    p = DdlParser()
    assert p.check_column("status IS NULL OR status IN ('a','b')") == "status"
    assert p.check_column("m IS NULL OR m BETWEEN 1 AND 12") == "m"
    assert p.check_column("rate IS NULL OR rate > 0") == "rate"
    assert p.check_column("char_length(code) = 3") == "code"


def test_gold_type_timestamptz_normalized_to_databricks_timestamp():
    # sqlglot's databricks dialect annotates a TIMESTAMP (e.g. from CURRENT_TIMESTAMP()) as
    # TIMESTAMPTZ - a spelling Databricks SQL does not have. _GOLD_TYPE_ALIASES folds it to
    # TIMESTAMP so an inferred type never leaks a non-Databricks spelling into a contract
    # (PR #61 review M1).
    sql = (
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${s}.gold_x AS\n"
        "SELECT CAST(CURRENT_TIMESTAMP() AS TIMESTAMP) AS scored_at\n"
        "FROM ${catalog}.${s}.sales;\n"
    )
    types = infer_gold_column_types(sql, {"sales": {"id": "STRING"}})
    assert types.get("scored_at") == "TIMESTAMP"  # not TIMESTAMPTZ


def test_sqlglot_view_columns_drops_bare_star():
    # A gold view whose FINAL projection is a bare `SELECT *` must never leak a literal "*"
    # column into model.json / a contract (PR #61 review minor). named_selects yields "*"
    # for an unexpanded star; it is filtered out.
    sql = (
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${s}.gold_x AS\n"
        "SELECT * FROM ${catalog}.${s}.sales;\n"
    )
    assert "*" not in _sqlglot_view_columns(sql)
