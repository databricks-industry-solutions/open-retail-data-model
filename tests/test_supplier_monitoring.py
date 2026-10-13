"""Tests for the Supplier Score & Monitoring use case.

Static contract tests keep the DDL, generator and gold view consistent and
guardrail-clean. Engine tests run the REAL gold_supplier_scorecard SQL on Spark
(the Databricks engine) over temp-view fixtures with hand-computed KPIs, proving
each KPI, the composite from documented weights, and that OTIF requires BOTH
on-time AND in-full.
"""

import ast
import os
import re

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.ordm_config import resolve, view_select_body

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GENERATOR = os.path.join(REPO, "runtime", "synthetic-data", "generators", "supplier_monitoring.py")
SUPPLIER_DDL = os.path.join(REPO, "canonical-core", "supplier", "tables", "supplier.sql")
POL_DDL = os.path.join(REPO, "canonical-core", "procurement", "tables", "purchase_order_line.sql")
SCORECARD = os.path.join(REPO, "outcome-packages", "early-risk-detection", "gold", "gold_supplier_scorecard.sql")

TABLES = {
    "supplier": (SUPPLIER_DDL, "supplier_sk", "SUPPLIER_COLUMNS"),
    "purchase_order_line": (POL_DDL, "po_line_sk", "PO_LINE_COLUMNS"),
}


def _ddl_columns(path, sk):
    create = next(s for s in sqlglot.parse(resolve(open(path).read(), "c"), read="databricks", error_level="ignore")
                  if isinstance(s, E.Create))
    return [c.name for c in create.find_all(E.ColumnDef) if c.name != sk]


def _generator_constants():
    mod = ast.parse(open(GENERATOR).read())
    return {n.targets[0].id: [e.value for e in n.value.elts] for n in mod.body
            if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)
            and isinstance(n.value, ast.List) and all(isinstance(e, ast.Constant) for e in n.value.elts)}


# ---------- static ----------

@pytest.mark.parametrize("table", list(TABLES))
def test_generator_columns_match_ddl(table):
    path, sk, const = TABLES[table]
    gen = set(_generator_constants()[const])
    ddl = set(_ddl_columns(path, sk))
    assert gen == ddl, f"{table} drift — missing={sorted(ddl - gen)} extra={sorted(gen - ddl)}"


def test_scorecard_exposes_required_columns():
    # Parse the SELECT body (form-agnostic: gold_supplier_scorecard is a materialized view).
    sel = sqlglot.parse_one(view_select_body(resolve(open(SCORECARD).read(), "c")),
                            read="databricks", error_level="ignore")
    outputs = set(sel.named_selects)
    required = {"supplier_id", "fiscal_year", "fiscal_period", "order_lines", "otif_pct",
                "fill_rate", "avg_lead_time_days", "lead_time_variance", "defect_rate",
                "price_compliance_pct", "composite_score"}
    assert required <= outputs, f"scorecard missing: {sorted(required - outputs)}"


def test_supplier_uses_gln_and_iso_country():
    ddl = open(SUPPLIER_DDL).read()
    assert re.search(r"\bgln\b", ddl) and "Global Location Number" in ddl
    assert "ISO 3166" in ddl


def test_no_banned_or_hardcoded():
    paths = [SUPPLIER_DDL, POL_DDL, SCORECARD,
             os.path.join(REPO, "canonical-core", "procurement", "relationships.sql"),
             os.path.join(REPO, "canonical-core", "supplier", "checks.sql"),
             os.path.join(REPO, "canonical-core", "procurement", "checks.sql"),
             os.path.join(REPO, "outcome-packages", "early-risk-detection", "checks.sql")]
    bad = [os.path.relpath(p, REPO) for p in paths
           if re.search(r"GROUP\s+BY\s+ALL|\b1\s*=\s*1\b", open(p).read(), re.I)
           or re.search(r"https?://[\w.-]*databricks|retail_prod|retail_dev|Copyright|SPDX|Licensed under",
                        open(p).read(), re.I)]
    assert not bad, f"banned/hardcoded/license in: {bad}"


# ---------- engine: Spark fixture running the real scorecard SQL ----------

import datetime

_SUBS = [
    ("${catalog}.${procurement_schema}.purchase_order_line", "purchase_order_line"),
    ("${catalog}.${calendar_schema}.fiscal_calendar", "fiscal_calendar"),
    ("${catalog}.${supplier_schema}.supplier", "supplier"),
]
_OD = datetime.date(2024, 1, 7)


def _scorecard_body():
    # The REAL scorecard SQL with UC names rewritten to the fixture temp views.
    # No dialect translation -- Spark is the target engine (datediff is native).
    # view_select_body handles the materialized-view header.
    body = view_select_body(open(SCORECARD).read())
    for a, b in _SUBS:
        body = body.replace(a, b)
    return body


def _build(spark):
    spark.createDataFrame(
        [(1, "SUP1", "Supplier 1", "US", True), (2, "SUP2", "Supplier 2", "DE", True)],
        "supplier_sk int, supplier_id string, supplier_name string, country_code string, is_current boolean",
    ).createOrReplaceTempView("supplier")
    spark.createDataFrame([(_OD, 2024, 1)], "date_key date, fiscal_year int, fiscal_period int") \
         .createOrReplaceTempView("fiscal_calendar")

    def line(ssk, sid, prom_off, act_off, ordered, received, defective, unit, contract):
        return (ssk, sid, _OD, _OD + datetime.timedelta(days=prom_off),
                _OD + datetime.timedelta(days=act_off), ordered, received, defective, 0, float(unit), float(contract))

    rows = [
        # SUP1: 4 lines -> OTIF 2/4, fill 380/400, lead {4,5,4,8}, defect 0, price all compliant
        line(1, "SUP1", 5, 4, 100, 100, 0, 6, 6),   # on-time + in-full  -> OTIF
        line(1, "SUP1", 5, 5, 100, 100, 0, 6, 6),   # on-time + in-full  -> OTIF
        line(1, "SUP1", 5, 4, 100, 80, 0, 6, 6),    # on-time but SHORT  -> not OTIF
        line(1, "SUP1", 5, 8, 100, 100, 0, 6, 6),   # LATE but in-full   -> not OTIF
        # SUP2: 2 lines -> OTIF 0, fill 0.7, defect 20/140, late
        line(2, "SUP2", 5, 9, 100, 70, 10, 6, 6),
        line(2, "SUP2", 5, 9, 100, 70, 10, 6, 6),
    ]
    spark.createDataFrame(
        rows,
        "supplier_sk int, supplier_id string, order_date date, promised_date date, actual_delivery_date date, "
        "ordered_qty int, received_qty int, defective_qty int, returned_qty int, unit_price double, contract_price double",
    ).createOrReplaceTempView("purchase_order_line")

    spark.sql("CREATE OR REPLACE TEMP VIEW gold_supplier_scorecard AS " + _scorecard_body())


def _row(spark, sid):
    return spark.sql(f"""SELECT otif_pct, fill_rate, avg_lead_time_days, lead_time_variance,
                                defect_rate, price_compliance_pct, composite_score
                         FROM gold_supplier_scorecard WHERE supplier_id='{sid}'""").first()


def test_one_row_per_supplier_period(spark):
    _build(spark)
    n = spark.sql("SELECT COUNT(*) AS n FROM gold_supplier_scorecard").first().n
    assert n == 2, f"expected one row per supplier x fiscal period, got {n}"


def test_kpis_and_composite_known_values(spark):
    _build(spark)
    otif, fill, lead, var, defect, price, comp = (float(x) for x in _row(spark, 'SUP1'))
    assert otif == pytest.approx(0.5)
    assert fill == pytest.approx(0.95)
    assert lead == pytest.approx(5.25)
    assert var == pytest.approx(2.6875)
    assert defect == pytest.approx(0.0)
    assert price == pytest.approx(1.0)
    # composite = (35*50 + 25*95 + 20*89.25 + 15*100 + 5*100)/100 = 79.1
    assert comp == pytest.approx(79.1)


def test_otif_requires_both_on_time_and_in_full(spark):
    _build(spark)
    otif = float(_row(spark, 'SUP1')[0])
    # 4 lines: 2 fully OK, 1 on-time-but-short, 1 late-but-full.
    # Only-on-time would give 0.75; only-in-full would give 0.75; BOTH gives 0.5.
    assert otif == pytest.approx(0.5)


def test_composite_spread_not_all_identical(spark):
    _build(spark)
    c1 = float(_row(spark, 'SUP1')[6])
    c2 = float(_row(spark, 'SUP2')[6])
    assert c2 == pytest.approx(42.5)
    assert c1 != c2
    distinct = spark.sql("SELECT COUNT(DISTINCT ROUND(composite_score,4)) AS n "
                         "FROM gold_supplier_scorecard").first().n
    assert distinct > 1
