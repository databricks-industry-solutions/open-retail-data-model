"""PR 2 contracts and Spark semantics for Market Analysis."""

import datetime as dt
import importlib.util
import os
import re
import sys

import pytest

from tools.ordm_config import view_select_body


REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GENERATOR_DIR = os.path.join(REPO, "runtime", "synthetic-data", "generators")
if GENERATOR_DIR not in sys.path:
    sys.path.insert(0, GENERATOR_DIR)

from _registry import GENERATORS as SPECS  # noqa: E402


PKG = os.path.join(REPO, "outcome-packages", "actionable-customer-understanding")
TABLE_DIR = os.path.join(PKG, "tables")
GOLD_MARKET_SHARE = os.path.join(PKG, "gold", "gold_market_share.sql")
MV_MARKET_SHARE = os.path.join(PKG, "metric-views", "market_share.sql")
RELATIONSHIPS = os.path.join(PKG, "relationships.sql")
CHECKS = os.path.join(PKG, "checks.sql")
GENERATOR = os.path.join(REPO, "runtime", "synthetic-data", "generators", "_market_analysis.py")
CUSTOMER_LTV_GENERATOR = os.path.join(
    REPO, "runtime", "synthetic-data", "generators", "customer_ltv.py"
)


TABLE_COLUMNS = {
    "competitor_promotion": {
        "competitor_promotion_sk", "competitor_promotion_id", "source_observation_id",
        "competitor_sk", "competitor_id", "competitor_item_ref", "product_sk",
        "product_id", "category_ref", "match_type", "match_method", "match_confidence",
        "competitor_location_ref", "channel_code", "promo_vehicle", "promo_type",
        "promo_price", "regular_price", "discount_depth_pct", "promo_start_date",
        "promo_end_date", "date_key", "observed_at_ts", "placement_rank",
        "is_front_page", "currency_code", "transaction_currency_code", "data_source",
        "raw_data_uri", "record_source", "load_timestamp",
    },
    "competitor_assortment": {
        "competitor_assortment_sk", "competitor_assortment_id", "source_observation_id",
        "competitor_sk", "competitor_id", "competitor_item_ref", "product_sk",
        "product_id", "category_ref", "match_type", "match_method", "match_confidence",
        "competitor_location_ref", "channel_code", "date_key", "observed_at_ts",
        "is_listed", "is_available", "search_rank", "marketplace_seller",
        "data_source", "raw_data_uri", "record_source", "load_timestamp",
    },
    "competitor_product_match": {
        "competitor_product_match_sk", "competitor_product_match_id", "competitor_sk",
        "competitor_id", "competitor_item_ref", "product_sk", "product_id",
        "match_type", "match_method", "match_confidence", "first_matched_date",
        "last_verified_date", "is_active", "created_timestamp",
        "source_updated_timestamp", "record_source", "load_timestamp",
    },
    "market_benchmark": {
        "market_benchmark_sk", "market_benchmark_id", "source_observation_id",
        "benchmark_cell_id", "competitor_sk", "competitor_id", "market_definition",
        "geography_level", "geography_code", "category_ref", "subject_type",
        "subject_id", "period_type", "period_end_date", "sales_amount", "unit_volume",
        "market_share_pct", "market_growth_rate_pct", "eq_volume",
        "acv_weighted_distribution_pct", "numeric_distribution_pct", "tdp",
        "promo_sales_amount", "base_sales_amount", "currency_code", "is_restatement",
        "restates_market_benchmark_id", "observed_at_ts", "provider_updated_at_ts",
        "raw_data_uri", "record_source", "load_timestamp",
    },
}


def _read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def _ddl_columns(table):
    text = _read(os.path.join(TABLE_DIR, f"{table}.sql"))
    return {
        match.group(1)
        for match in re.finditer(
            r"^\s{2}([a-z][a-z0-9_]*)\s+(?:BIGINT|STRING|DATE|TIMESTAMP|BOOLEAN|"
            r"TINYINT|SMALLINT|INT|DECIMAL\s*\()",
            text,
            re.MULTILINE,
        )
    }


def _metric_expr(path, name):
    match = re.search(
        rf"^\s*- name: {re.escape(name)}\s*$\n\s+expr:\s*(.+)$",
        _read(path),
        re.MULTILINE,
    )
    assert match, f"metric measure {name!r} is missing"
    return match.group(1).strip()


def _market_share_body():
    body = view_select_body(_read(GOLD_MARKET_SHARE))
    for source, target in {
        "${catalog}.${acu_schema}.market_benchmark": "market_benchmark",
        "${catalog}.${bmv_schema}.competitor": "competitor",
    }.items():
        body = body.replace(source, target)
    return body


def _load_helper():
    spec = importlib.util.spec_from_file_location("ordm_market_analysis_gen", GENERATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_four_source_tables_follow_the_pr2_contract():
    for table, expected in TABLE_COLUMNS.items():
        path = os.path.join(TABLE_DIR, f"{table}.sql")
        text = _read(path)
        assert expected == _ddl_columns(table), table
        assert f"CONSTRAINT pk_{table} PRIMARY KEY ({table}_sk)" in text
        assert "BIGINT GENERATED ALWAYS AS IDENTITY" in re.sub(r"\s+", " ", text)
        assert "SET TAGS ('dbx_data_type'" in text


def test_observation_and_match_identity_are_independent_of_mutable_matching():
    source = _read(GENERATOR)
    assert 'F.concat_ws("|", F.col("record_source"), F.col("source_observation_id"))' in source
    assert 'F.concat_ws("|", F.col("competitor_id"), F.col("competitor_item_ref"))' in source
    match_id_block = re.search(
        r'withColumn\(\s*"competitor_product_match_id"(.*?)\.withColumn\("match_type"',
        source,
        re.DOTALL,
    )
    assert match_id_block
    assert "product_id" not in match_id_block.group(1)
    assert 'F.col("competitor_location_ref"), F.col("channel_code")' in source
    assert 'F.col("competitor_location_ref"), F.col("promo_vehicle")' in source
    assert '"market_definition", "geography_level"' in source


def test_generator_avoids_global_windows_and_samples_competitor_ranges():
    source = _read(GENERATOR)
    assert "Window.orderBy" not in source
    assert "_restatement_rank" not in source
    assert "F.datediff" in source
    assert 'F.hash("competitor_id", "product_id")' in source


def test_relationships_cover_parent_surrogates_logical_competitors_and_enum_domains():
    text = _read(RELATIONSHIPS)
    checks = _read(CHECKS)
    for table in TABLE_COLUMNS:
        assert f"fk_{table}_competitor" not in text
        assert f"{table}_competitor_logical_fk_orphan" in checks
    for table in ("competitor_promotion", "competitor_assortment", "competitor_product_match"):
        assert f"fk_{table}_product" in text
    for constraint in (
        "chk_competitor_promotion_channel", "chk_competitor_promotion_vehicle",
        "chk_competitor_promotion_type", "chk_competitor_assortment_channel",
        "chk_competitor_assortment_match_type", "chk_competitor_product_match_method",
        "chk_market_benchmark_subject", "chk_market_benchmark_period_type",
    ):
        assert constraint in text


def test_customer_ltv_invokes_helper_and_declares_bmv_dependency():
    source = _read(CUSTOMER_LTV_GENERATOR)
    assert "generate_market_analysis" in source
    spec = next(item for item in SPECS if item.name == "customer_ltv")
    assert "bmv" in spec.depends_on
    assert "promo" in spec.depends_on


def test_generator_story_has_sparse_unmatched_changes_remainder_and_restatement(spark):
    helper = _load_helper()
    dates = [dt.date(2026, 1, day) for day in (1, 8, 15, 22, 29)]
    competitors = spark.createDataFrame(
        [(1, "C1"), (2, "C2")], "competitor_sk long, competitor_id string"
    )
    products = spark.createDataFrame(
        [(11, "P1", "snacks", 10.0), (12, "P2", "snacks", 8.0),
         (13, "P3", "drinks", 5.0)],
        "product_sk long, product_id string, category string, list_price double",
    )
    calendar = spark.createDataFrame([(value,) for value in dates], "date_key date")
    frames = helper.build_market_analysis_frames(
        spark, competitors, products, calendar, seed=41, base_currency="USD"
    )

    assortment = frames["competitor_assortment"]
    matches = frames["competitor_product_match"]
    benchmark = frames["market_benchmark"]
    assert matches.count() < competitors.count() * products.count()
    assert assortment.where("product_id IS NULL").count() > 0
    assert assortment.where("is_listed = false AND is_available IS NOT NULL").count() == 0
    assert assortment.select("date_key").distinct().count() < len(dates)
    assert assortment.groupBy("competitor_id", "competitor_item_ref").count().where("count > 1").count() > 0
    assert benchmark.where("is_restatement = true").count() > 0
    assert benchmark.groupBy("benchmark_cell_id").count().where("count > 1").count() > 0
    measured = benchmark.where("subject_type <> 'total_category'").groupBy(
        "market_definition", "geography_level", "geography_code", "category_ref",
        "subject_type", "period_type", "period_end_date"
    ).sum("market_share_pct")
    assert measured.where("`sum(market_share_pct)` >= 100").count() == 0


def test_market_share_latest_wins_and_keeps_separate_grain(spark):
    ts1 = dt.datetime(2026, 2, 10, 12)
    ts2 = dt.datetime(2026, 2, 11, 12)
    rows = [
        ("MB-TOTAL-1", "CELL-TOTAL", "OBS-TOTAL-1", None, None, "synthetic_benchmark",
         "measured_market", "total", "US", "snacks", "total_category", None,
         "quad_week", dt.date(2026, 1, 31), 1000.0, 100.0, 100.0, 2.0,
         100.0, 90.0, 85.0, 50.0, 220.0, 780.0, "USD",
         False, None, ts1, ts1, ts1),
        ("MB-OWN-1", "CELL-OWN", "OBS-OWN-1", None, None, "synthetic_benchmark",
         "measured_market", "total", "US", "snacks", "own_banner", "OWN",
         "quad_week", dt.date(2026, 1, 31), 200.0, 20.0, 20.0, 3.0,
         20.0, 70.0, 65.0, 25.0, 44.0, 156.0, "USD",
         False, None, ts1, ts1, ts1),
        ("MB-OWN-2", "CELL-OWN", "OBS-OWN-2", None, None, "synthetic_benchmark",
         "measured_market", "total", "US", "snacks", "own_banner", "OWN",
         "quad_week", dt.date(2026, 1, 31), 250.0, 25.0, 25.0, 3.5,
         25.0, 72.0, 67.0, 27.0, 55.0, 195.0, "USD",
         True, "MB-OWN-1", ts2, ts2, ts2),
        ("MB-C1-1", "CELL-C1", "OBS-C1-1", 1, "C1", "synthetic_benchmark",
         "measured_market", "total", "US", "snacks", "competitor_banner", "C1",
         "quad_week", dt.date(2026, 1, 31), 300.0, 30.0, 30.0, 1.0,
         30.0, 75.0, 70.0, 30.0, 66.0, 234.0, "USD",
         False, None, ts1, ts1, ts1),
    ]
    schema = (
        "market_benchmark_id string, benchmark_cell_id string, source_observation_id string, "
        "competitor_sk long, competitor_id string, record_source string, market_definition string, "
        "geography_level string, geography_code string, category_ref string, subject_type string, "
        "subject_id string, period_type string, period_end_date date, sales_amount double, "
        "unit_volume double, market_share_pct double, market_growth_rate_pct double, "
        "eq_volume double, acv_weighted_distribution_pct double, numeric_distribution_pct double, "
        "tdp double, promo_sales_amount double, base_sales_amount double, currency_code string, "
        "is_restatement boolean, restates_market_benchmark_id string, observed_at_ts timestamp, "
        "provider_updated_at_ts timestamp, load_timestamp timestamp"
    )
    spark.createDataFrame(rows, schema).createOrReplaceTempView("market_benchmark")
    spark.createDataFrame(
        [(1, "C1", "Current C1", dt.date(2020, 1, 1), None)],
        "competitor_sk long, competitor_id string, competitor_name string, "
        "effective_from_date date, effective_to_date date",
    ).createOrReplaceTempView("competitor")
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_market_share AS " + _market_share_body())

    assert spark.sql("SELECT COUNT(*) FROM gold_market_share").first()[0] == 2
    assert spark.sql(
        "SELECT COUNT(*) FROM gold_market_share WHERE subject_type = 'total_category'"
    ).first()[0] == 0
    own = spark.sql("SELECT * FROM gold_market_share WHERE benchmark_cell_id='CELL-OWN'").first()
    assert own.market_share_sales_amount == pytest.approx(250.0)
    assert own.market_size_sales_amount == pytest.approx(1000.0)
    assert own.market_share_pct == pytest.approx(25.0)
    competitor = spark.sql("SELECT * FROM gold_market_share WHERE benchmark_cell_id='CELL-C1'").first()
    assert competitor.competitor_name == "Current C1"


def test_market_share_metric_uses_ratio_of_sums():
    expr = _metric_expr(MV_MARKET_SHARE, "market_share_pct").upper()
    assert "SUM(MARKET_SHARE_SALES_AMOUNT)" in expr
    assert "SUM(MARKET_SIZE_SALES_AMOUNT)" in expr
    assert "NULLIF(" in expr
    assert "AVG(" not in expr
    assert "GOLD_COMPETITIVE_POSITION" not in _read(GOLD_MARKET_SHARE).upper()


def test_market_share_metric_uses_deployable_portable_money_formats():
    text = _read(MV_MARKET_SHARE)
    assert "currency_code_field" not in text
    assert text.count("format: {type: number, decimal_places: {type: exact, places: 2}}") >= 3
    for filename in os.listdir(os.path.join(PKG, "metric-views")):
        if filename.endswith(".sql"):
            assert "type: currency" not in _read(os.path.join(PKG, "metric-views", filename))
