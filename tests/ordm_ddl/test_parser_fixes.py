"""Regression tests for the AI-review #53 fixes (H1, H2, M3) and the post-#53
follow-up fixes (H1 complex types, M1 materialized-from-kind).

Codes in the FIRST block (test_h1_*, test_h2_*, test_m3_*) refer to the original
#53 review; codes in the SECOND block (test_post53_*) refer to the post-#53
"approve with nits" review (comment 4909153002): H1 = complex-type drop, M1 =
materialized re-scans prose."""
import pytest

from tools.ordm_ddl.parser import DdlParser, parse_columns
from tools.ordm_ddl.discovery import UnitDiscovery

_TABLE = """
-- This is the gold-standard conformed reference table (prose mentions gold).
CREATE TABLE IF NOT EXISTS ${catalog}.${customer_schema}.widget (
  widget_sk BIGINT GENERATED ALWAYS AS IDENTITY COMMENT 'Surrogate.',
  CONSTRAINT pk_widget PRIMARY KEY (widget_sk)
) USING DELTA COMMENT 'A widget.';
"""


def test_h1_layer_not_flipped_by_gold_in_prose():
    # #53 H1: a "gold" mention in the header must NOT mark a silver core table gold.
    assert DdlParser().parse_table(_TABLE).layer == "silver"


def test_h2_materialized_true_for_tables_and_detected_for_views():
    # #53 H2: a CREATE TABLE is materialized; and across the real model, plain views are
    # now correctly detected as non-materialized (the old substring check made all True).
    assert DdlParser().parse_table(_TABLE).materialized is True
    p = DdlParser()
    mats = [t.materialized for d in UnitDiscovery().find(None)
            for t in p.parse_unit(d).tables]
    assert False in mats, "expected at least one non-materialized (plain) view in the model"


def test_h2_checks_sql_column_is_none():
    # #53 H2: checks.sql checks are table-level SQL assertions, not column "SELECT".
    checks = DdlParser().parse_checks(
        "-- check: t_not_null | severity: error\n"
        "SELECT * FROM ${catalog}.${customer_schema}.widget WHERE widget_sk IS NULL;\n")
    assert checks and all(c.column is None for c in checks)


def test_m3_gold_view_columns_from_comments_sql():
    # #53 M3: gold views get columns from comments.sql (parity with the ODCS path).
    d = {u.rsplit("/", 1)[-1]: u for u in UnitDiscovery().find({"early-risk-detection"})}["early-risk-detection"]
    unit = DdlParser().parse_unit(d)
    gold = [t for t in unit.tables if t.layer == "gold" and t.columns]
    assert gold, "expected at least one gold view with columns populated from comments.sql"


# ============================================================
# Post-#53 "approve with nits" review (comment 4909153002)
# ============================================================

# --- H1: complex/collection column types must NOT be silently dropped ---

_TABLE_ARRAY = """
CREATE TABLE IF NOT EXISTS ${catalog}.${customer_schema}.thing (
  thing_sk BIGINT GENERATED ALWAYS AS IDENTITY COMMENT 'Surrogate.',
  tags ARRAY<STRING> COMMENT 'Free-form tags.',
  attrs MAP<STRING,INT> COMMENT 'Attribute counts.',
  profile STRUCT<a:INT,b:ARRAY<STRING>> COMMENT 'Nested profile.',
  CONSTRAINT pk_thing PRIMARY KEY (thing_sk)
) USING DELTA COMMENT 'A thing with complex columns.';
"""


def test_post53_h1_array_column_is_parsed():
    # Post-#53 H1: an ARRAY<STRING> column must appear (was silently dropped by the
    # old `[A-Za-z]+` type regex).
    t = DdlParser().parse_table(_TABLE_ARRAY)
    by_name = {c.name: c for c in t.columns}
    assert "tags" in by_name, "ARRAY<STRING> column was dropped by the parser"
    assert by_name["tags"].sql_type == "ARRAY<STRING>"
    assert by_name["tags"].comment == "Free-form tags."


def test_post53_h1_map_and_nested_struct_columns_are_parsed():
    # Post-#53 H1: MAP<> and a nested STRUCT<...ARRAY<...>> must parse whole.
    t = DdlParser().parse_table(_TABLE_ARRAY)
    by_name = {c.name: c for c in t.columns}
    assert by_name["attrs"].sql_type == "MAP<STRING,INT>"
    assert by_name["profile"].sql_type == "STRUCT<A:INT,B:ARRAY<STRING>>"
    # Every declared column (4 incl. surrogate) is present — none dropped.
    assert set(by_name) == {"thing_sk", "tags", "attrs", "profile"}


def test_post53_h1_unparseable_column_fails_loud():
    # Post-#53 H1: a genuinely malformed column line must RAISE, not silently skip,
    # so the drift gate can never pass over a dropped column.
    bad_body = "thing_sk BIGINT, !!! this is not a column !!!, other STRING"
    with pytest.raises(ValueError, match="Unparseable column definition"):
        parse_columns(bad_body)


def test_post53_h1_angle_brackets_in_comment_do_not_break_split():
    # Guard: `<`/`>` inside a quoted COMMENT (e.g. "funded_by <> RETAILER", ">= 0")
    # must NOT be treated as complex-type brackets by the top-level splitter — the
    # column list must still split correctly (real committed DDL has these).
    body = (
        "a INT COMMENT 'required when funded_by <> RETAILER.',\n"
        "b DECIMAL(18,2) COMMENT 'magnitude, >= 0.',\n"
        "c STRING COMMENT 'plain'"
    )
    cols = parse_columns(body)
    assert [c["name"] for c in cols] == ["a", "b", "c"]
    assert cols[1]["sql_type"] == "DECIMAL(18,2)"


def test_post53_h1_constraint_and_blank_lines_still_skipped():
    # The fail-loud guard must NOT trip on table CONSTRAINT lines or blank fragments.
    body = (
        "thing_sk BIGINT COMMENT 'x',\n"
        "  , \n"  # blank fragment
        "CONSTRAINT pk PRIMARY KEY (thing_sk)"
    )
    cols = parse_columns(body)
    assert [c["name"] for c in cols] == ["thing_sk"]


def test_post53_review_m1_bare_inline_constraints_do_not_crash():
    # #55 review m1: bare inline table constraints WITHOUT the CONSTRAINT keyword
    # (legal Databricks SQL) must be skipped, not hit the fail-loud raise. A column
    # merely NAMED like a keyword (check_flag) must still be parsed as a column.
    body = (
        "id BIGINT COMMENT 'x',\n"
        "check_flag BOOLEAN,\n"
        "PRIMARY KEY (id),\n"
        "FOREIGN KEY (id) REFERENCES other(id),\n"
        "CHECK (id IS NOT NULL),\n"
        "UNIQUE (id)"
    )
    cols = parse_columns(body)
    assert [c["name"] for c in cols] == ["id", "check_flag"]


# --- M1: materialized keyed off parsed kind, not a prose re-scan ---

_TABLE_PROSE_MENTIONS_VIEW = """
-- This table is populated by a create or replace view upstream in the pipeline.
CREATE TABLE IF NOT EXISTS ${catalog}.${customer_schema}.fact (
  fact_sk BIGINT GENERATED ALWAYS AS IDENTITY COMMENT 'Surrogate.',
  CONSTRAINT pk_fact PRIMARY KEY (fact_sk)
) USING DELTA COMMENT 'A fact whose comment mentions a create or replace view.';
"""

_PLAIN_VIEW = """
-- A gold consumption view.
CREATE OR REPLACE VIEW ${catalog}.${customer_schema}.v_gold AS
SELECT fact_sk FROM ${catalog}.${customer_schema}.fact;
"""

_MATERIALIZED_VIEW = """
-- A gold materialized view.
CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${customer_schema}.mv_gold AS
SELECT fact_sk FROM ${catalog}.${customer_schema}.fact;
"""


def test_post53_m1_table_with_view_in_comment_stays_materialized():
    # Post-#53 M1: a CREATE TABLE whose COMMENT mentions "create or replace view"
    # must stay materialized=True (keyed off the parsed kind, not a prose re-scan).
    t = DdlParser().parse_table(_TABLE_PROSE_MENTIONS_VIEW)
    assert t.materialized is True


def test_post53_m1_plain_view_is_not_materialized():
    t = DdlParser().parse_table(_PLAIN_VIEW)
    assert t.materialized is False


def test_post53_m1_materialized_view_is_materialized():
    t = DdlParser().parse_table(_MATERIALIZED_VIEW)
    assert t.materialized is True


# ---------------------------------------------------------------------------
# Column-drop regression (reported 2026-07-12): a gold view whose comments.sql
# documents only SOME of its projected columns must NOT drop the undocumented
# ones. The column set is the UNION of the SELECT projection (sqlglot) and
# comments.sql, so neither source can silently drop a column.
# ---------------------------------------------------------------------------

def _write_gold_unit(tmp_path):
    (tmp_path / "gold").mkdir()
    (tmp_path / "gold" / "gold_x.sql").write_text(
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${s}.gold_x AS\n"
        "SELECT s.product_id, s.store_id, CAST(s.date_key AS DATE) AS date_key,\n"
        "       CAST(NULL AS DOUBLE) AS forecast, CAST(NULL AS DOUBLE) AS growth_pct\n"
        "FROM ${catalog}.${s}.gold_sales_actuals s;\n"
    )
    # comments.sql documents only 2 of the 5 projected columns
    (tmp_path / "comments.sql").write_text(
        "COMMENT ON COLUMN ${catalog}.${s}.gold_x.growth_pct IS 'YoY growth.';\n"
        "COMMENT ON COLUMN ${catalog}.${s}.gold_x.forecast IS 'Baseline forecast.';\n"
    )


def test_gold_view_partial_comments_does_not_drop_projected_columns(tmp_path):
    _write_gold_unit(tmp_path)
    gold = next(t for t in DdlParser().parse_unit(str(tmp_path)).tables if t.name == "gold_x")
    names = [c.name for c in gold.columns]
    # ALL FIVE projected columns present (previously only the 2 documented survived),
    # in SELECT-projection order.
    assert names == ["product_id", "store_id", "date_key", "forecast", "growth_pct"]


def test_gold_view_partial_comments_keeps_descriptions_where_documented(tmp_path):
    _write_gold_unit(tmp_path)
    gold = next(t for t in DdlParser().parse_unit(str(tmp_path)).tables if t.name == "gold_x")
    by = {c.name: c.comment for c in gold.columns}
    assert by["growth_pct"] == "YoY growth."   # documented -> description attached
    assert by["forecast"] == "Baseline forecast."
    assert by["product_id"] == ""              # undocumented -> blank, but PRESENT (not dropped)


# ---------------------------------------------------------------------------
# Apostrophe-in-line-comment regression (reported 2026-07-28, connected-store-signals).
# `_balanced_body` was quote-aware but not comment-aware, so an apostrophe in a
# `-- ...` comment INSIDE a CREATE-TABLE body inverted its in-string state, the
# matching `)` was missed, and the "body" ran on into CLUSTER BY / TBLPROPERTIES.
# ---------------------------------------------------------------------------

_TABLE_APOSTROPHE_IN_LINE_COMMENT = """
CREATE TABLE IF NOT EXISTS ${catalog}.${customer_schema}.gadget (
  gadget_sk BIGINT GENERATED ALWAYS AS IDENTITY COMMENT 'Surrogate.',
  gadget_id STRING NOT NULL COMMENT 'Durable key.',
  -- SCD2 because the supermarket's own staff roster changes.
  is_current BOOLEAN NOT NULL COMMENT 'SCD2 current flag.',
  CONSTRAINT pk_gadget PRIMARY KEY (gadget_sk)
)
USING DELTA
CLUSTER BY (gadget_id)
TBLPROPERTIES (delta.enableDeletionVectors = true)
COMMENT 'A gadget.';
"""


def test_apostrophe_in_body_line_comment_does_not_swallow_columns():
    t = DdlParser().parse_table(_TABLE_APOSTROPHE_IN_LINE_COMMENT)
    assert [c.name for c in t.columns] == ["gadget_sk", "gadget_id", "is_current"]
    assert list(t.primary_key) == ["gadget_sk"]


def test_apostrophe_in_body_line_comment_does_not_leak_clustering_clause():
    """The specific corruption: `CLUSTER BY (gadget_id)` parsed as a column named
    `CLUSTER`, or `delta.enableDeletionVectors` parsed as a column. Either yields a
    plausible-looking table with a fabricated column."""
    t = DdlParser().parse_table(_TABLE_APOSTROPHE_IN_LINE_COMMENT)
    names = {c.name.lower() for c in t.columns}
    assert not names & {"cluster", "tblproperties", "delta.enabledeletionvectors", "using"}
