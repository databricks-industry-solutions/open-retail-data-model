"""Tests for Customer Lifetime Value (gold_customer_ltv).

Static contract tests (incl. a PII-absence assertion on the gold schema) plus
Spark fixtures (the Databricks engine) running the REAL view: RFM quintile assignment, historical_clv
= sum of margin, predicted_clv reproduced from the documented heuristic, and
predicted_clv never negative.
"""

import ast
import os
import re

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.ordm_config import resolve, view_select_body

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DDL = os.path.join(REPO, "canonical-core", "order", "tables", "customer_order_line.sql")
PAYMENT_DDL = os.path.join(REPO, "canonical-core", "payment", "tables", "payment.sql")
LTV = os.path.join(REPO, "outcome-packages", "actionable-customer-understanding", "gold", "gold_customer_ltv.sql")
SEGMENT_MEMBERSHIP_DDL = os.path.join(REPO, "outcome-packages", "actionable-customer-understanding", "tables", "segment_membership.sql")
GENERATOR = os.path.join(REPO, "runtime", "synthetic-data", "generators", "customer_ltv.py")

PII_COLUMNS = {"loyalty_id", "household_id", "first_name", "middle_name", "last_name",
               "date_of_birth", "name_prefix", "name_suffix", "contact_value"}


def _outputs():
    # Parse the SELECT body (form-agnostic: gold_customer_ltv is a materialized view).
    sel = sqlglot.parse_one(view_select_body(resolve(open(LTV).read(), "c")),
                            read="databricks", error_level="ignore")
    return set(sel.named_selects)


# ---------- static ----------

def test_generator_columns_match_ddl():
    create = next(s for s in sqlglot.parse(resolve(open(DDL).read(), "c"), read="databricks", error_level="ignore")
                  if isinstance(s, E.Create))
    ddl = {c.name for c in create.find_all(E.ColumnDef) if c.name != "order_line_sk"}
    mod = ast.parse(open(GENERATOR).read())
    gen = {e.value for n in mod.body if isinstance(n, ast.Assign)
           and getattr(n.targets[0], "id", "") == "CUSTOMER_ORDER_LINE_COLUMNS" for e in n.value.elts}
    assert ddl == gen, f"drift: missing={sorted(ddl - gen)} extra={sorted(gen - ddl)}"


def test_payment_columns_match_ddl():
    create = next(s for s in sqlglot.parse(resolve(open(PAYMENT_DDL).read(), "c"), read="databricks", error_level="ignore")
                  if isinstance(s, E.Create))
    ddl = {c.name for c in create.find_all(E.ColumnDef) if c.name != "payment_sk"}
    mod = ast.parse(open(GENERATOR).read())
    gen = {e.value for n in mod.body if isinstance(n, ast.Assign)
           and getattr(n.targets[0], "id", "") == "PAYMENT_COLUMNS" for e in n.value.elts}
    assert ddl == gen, f"payment drift: missing={sorted(ddl - gen)} extra={sorted(gen - ddl)}"


def test_segment_membership_columns_match_ddl():
    create = next(s for s in sqlglot.parse(resolve(open(SEGMENT_MEMBERSHIP_DDL).read(), "c"), read="databricks", error_level="ignore")
                  if isinstance(s, E.Create))
    ddl = {c.name for c in create.find_all(E.ColumnDef) if c.name != "segment_membership_sk"}
    mod = ast.parse(open(GENERATOR).read())
    gen = {e.value for n in mod.body if isinstance(n, ast.Assign)
           and getattr(n.targets[0], "id", "") == "SEGMENT_MEMBERSHIP_COLUMNS" for e in n.value.elts}
    assert ddl == gen, f"segment_membership drift: missing={sorted(ddl - gen)} extra={sorted(gen - ddl)}"


def test_view_exposes_required_columns():
    required = {"profile_sk", "recency_periods", "frequency", "total_spend", "avg_order_value",
                "historical_clv", "predicted_clv", "r_score", "f_score", "m_score", "rfm_score",
                "value_tier", "churn_risk_proxy"}
    assert required <= _outputs(), f"missing: {sorted(required - _outputs())}"


def test_no_raw_pii_in_gold_schema():
    # The PII-absence guarantee: no PII column appears in the view's output.
    leaked = PII_COLUMNS & _outputs()
    assert not leaked, f"gold view exposes raw PII: {sorted(leaked)}"
    assert "profile_sk" in _outputs(), "view must key on the customer surrogate"


def test_no_banned_or_hardcoded():
    txt = open(LTV).read()
    assert not re.search(r"GROUP\s+BY\s+ALL|\b1\s*=\s*1\b", txt, re.I)
    assert not re.search(r"https?://[\w.-]*databricks|retail_prod|retail_dev|Copyright|SPDX|Licensed under", txt, re.I)


# ---------- engine: Spark fixture running the real view ----------

import datetime

_SUBS = [
    ("${catalog}.${order_schema}.customer_order_line", "customer_order_line"),
    ("${catalog}.${product_schema}.product", "product"),
    ("${catalog}.${calendar_schema}.fiscal_calendar", "fiscal_calendar"),
]
_ORDER_SCHEMA = ("profile_sk int, profile_id string, order_id string, product_sk int, "
                 "order_date date, units int, net_amount double")


def _view_body():
    # The REAL gold SQL with UC names rewritten to fixture temp views; Spark runs it
    # verbatim. view_select_body handles the materialized-view header.
    body = view_select_body(open(LTV).read())
    for a, b in _SUBS:
        body = body.replace(a, b)
    return body


def _date(fp):
    # unique date per fiscal period (the value only matters as a join key)
    return datetime.date(2024, 1, 1) + datetime.timedelta(days=fp * 31)


def _build(spark, cal_fps, order_rows):
    spark.createDataFrame([(1, 6.0)], "product_sk int, unit_cost double").createOrReplaceTempView("product")
    spark.createDataFrame([(_date(fp), 2024, fp) for fp in cal_fps],
                          "date_key date, fiscal_year int, fiscal_period int").createOrReplaceTempView("fiscal_calendar")
    spark.createDataFrame(order_rows, _ORDER_SCHEMA).createOrReplaceTempView("customer_order_line")
    spark.sql("CREATE OR REPLACE TEMP VIEW gold_customer_ltv AS " + _view_body())


def _rfm_build(spark):
    # 5 customers spanning the STABLE fixed-threshold R/F/M/value buckets (not NTILE).
    # units=2, unit_cost=6 -> margin/order = net - 12. cur_period = max fp = 20 (C1).
    # profile_sk: (n_orders, net_per_order, last_fp).
    #   C1: 1 order @50, fp20  -> rec 0 (R5), F1, spend 50 (M1),   clv 38    -> BRONZE
    #   C2: 2 orders @150,fp18 -> rec 2 (R3), F2, spend 300 (M2),  clv 276   -> SILVER
    #   C3: 3 orders @400,fp16 -> rec 4 (R2), F3, spend 1200 (M3), clv 1164  -> GOLD
    #   C4: 6 orders @350,fp14 -> rec 6 (R1), F4, spend 2100 (M4), clv 2028  -> GOLD
    #   C5: 12 orders @500,fp15-> rec 5 (R1), F5, spend 6000 (M5), clv 5856  -> PLATINUM
    plan = {1: (1, 50.0, 20), 2: (2, 150.0, 18), 3: (3, 400.0, 16),
            4: (6, 350.0, 14), 5: (12, 500.0, 15)}
    rows = [(sk, f"C{sk}", f"C{sk}-O{o}", 1, _date(fp), 2, net)
            for sk, (n_orders, net, fp) in plan.items() for o in range(1, n_orders + 1)]
    _build(spark, (14, 15, 16, 18, 20), rows)


def test_one_row_per_customer(spark):
    _rfm_build(spark)
    assert spark.sql("SELECT COUNT(*) AS n FROM gold_customer_ltv").first().n == 5


def test_rfm_quintiles_assigned(spark):
    _rfm_build(spark)
    c1 = spark.sql("SELECT r_score,f_score,m_score,rfm_score FROM gold_customer_ltv WHERE profile_id='C1'").first()
    c5 = spark.sql("SELECT r_score,f_score,m_score,rfm_score FROM gold_customer_ltv WHERE profile_id='C5'").first()
    # C1: most recent (R=5) but fewest orders/spend (F=1,M=1)
    assert tuple(c1) == (5, 1, 1, 511)
    # C5: most dormant (R=1) but most orders/spend (F=5,M=5)
    assert tuple(c5) == (1, 5, 5, 155)


def test_value_tier_spread_and_historical_clv(spark):
    _rfm_build(spark)
    tiers = {r.profile_id: r.value_tier for r in
             spark.sql("SELECT profile_id, value_tier FROM gold_customer_ltv").collect()}
    assert tiers['C5'] == 'PLATINUM' and tiers['C1'] == 'BRONZE'
    assert spark.sql("SELECT COUNT(DISTINCT value_tier) AS n FROM gold_customer_ltv").first().n == 4
    # historical_clv(C3) = 3 orders * (400 - 2*6) = 1164 (stable-threshold fixture)
    clv3 = float(spark.sql("SELECT historical_clv FROM gold_customer_ltv WHERE profile_id='C3'").first()[0])
    assert clv3 == pytest.approx(1164.0)


def test_predicted_clv_reproduces_from_inputs(spark):
    # CP: 4 orders one per period (10..13); a later dummy order (CD) sets the
    # current period to 16 so recency = 3, tenure = 7.
    rows = [(1, "CP", f"CP-O{o}", 1, _date(fp), 2, 50.0) for o, fp in enumerate([10, 11, 12, 13], start=1)]
    rows.append((9, "CD", "CD-O1", 1, _date(16), 2, 50.0))
    _build(spark, (10, 11, 12, 13, 16), rows)
    pred = float(spark.sql("SELECT predicted_clv FROM gold_customer_ltv WHERE profile_id='CP'").first()[0])
    # avg_order_margin=38 ; freq_per_period=4/7 ; expected_active=min(7,12)-3=4
    expected = 38 * (4 / 7) * 4
    assert pred == pytest.approx(expected, abs=1e-6)


def test_predicted_clv_never_negative(spark):
    # net 30 < units(10) * unit_cost(6)=60 -> margin -30 (realized loss is real)
    _build(spark, (10,), [(1, "CN", "CN-O1", 1, _date(10), 10, 30.0)])
    hist, pred = spark.sql(
        "SELECT historical_clv, predicted_clv FROM gold_customer_ltv WHERE profile_id='CN'").first()
    assert float(hist) == pytest.approx(-30.0)   # historical can be negative
    assert float(pred) == pytest.approx(0.0)     # predicted is clamped to >= 0


# ---------- build_segment_membership: rule-seeded, semantically consistent (M1) ----------

def _load_generator():
    """Load the customer_ltv generator module with its sibling _common importable."""
    import importlib.util
    gen_dir = os.path.join(REPO, "runtime", "synthetic-data", "generators")
    if gen_dir not in os.sys.path:
        os.sys.path.insert(0, gen_dir)
    spec = importlib.util.spec_from_file_location("ordm_customer_ltv_gen", GENERATOR)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _seg_fixture(spark):
    """Order lines engineered so each rule segment has a member who genuinely
    satisfies its predicate, plus a calendar. period_index = fiscal_year*12+period."""
    import datetime as dt
    # calendar: 12 monthly periods in 2024, date_key = first of month.
    cal = spark.createDataFrame(
        [(dt.date(2024, m, 1), 2024, m) for m in range(1, 13)],
        "date_key date, fiscal_year int, fiscal_period int")
    # cur_period = 2024*12+12 = 24300. Build customers with distinct behaviors.
    #  LAPSING: last order a few periods before cur, recency > cadence.
    #  NEW: single order in the current period (first==last==cur).
    #  DISCOUNT: every line net<gross.
    #  VIP/HIGH-VALUE: big spend + frequency.
    rows = []
    def line(pid, m, units, gross, net):
        # product_sk=1 for all; value_tier tiers on MARGIN = net - units*unit_cost.
        return (pid, f"{pid}-O{m}", 1, dt.date(2024, m, 1), units, float(gross), float(net))
    # NEW-TO-BRAND: only period 12 (current)
    rows += [line("NEW1", 12, 1, 50, 50)]
    # LAPSING: orders in periods 1..3 (frequent early), none since -> recency high vs cadence
    rows += [line("LAP1", 1, 1, 40, 40), line("LAP1", 2, 1, 40, 40), line("LAP1", 3, 1, 40, 40)]
    # DISCOUNT-DRIVEN: all lines discounted (net<gross), recent
    rows += [line("DSC1", 11, 2, 100, 60), line("DSC1", 12, 2, 100, 60)]
    # VIP / HIGH-VALUE-REPEAT: 4 recent orders. margin = 4*(800 - 5*30) = 2600 >= 2500
    # -> PLATINUM (on historical_clv/margin, not net spend — see H1 fix).
    rows += [line("VIP1", 9, 5, 800, 800), line("VIP1", 10, 5, 800, 800),
             line("VIP1", 11, 5, 800, 800), line("VIP1", 12, 5, 800, 800)]
    schema = "profile_id string, order_id string, product_sk int, order_date date, units int, gross_amount double, net_amount double"
    lines = spark.createDataFrame(rows, schema)
    # products_current with unit_cost=30 (VIP1 margin clears the PLATINUM cutoff).
    products = spark.createDataFrame([(1, 30.0)], "product_sk int, unit_cost double")
    return lines, products, cal


def test_segment_membership_is_rule_consistent(spark):
    """M1: a member seeded into a rule-based segment actually satisfies that segment's
    criteria in the derived trait signals (not a blind hash). Assert the diagnostic
    cases land in the right segments and NOT in contradictory ones."""
    gen = _load_generator()
    lines, products, cal = _seg_fixture(spark)
    m = gen.build_segment_membership(spark, lines, products, cal, seed=42)
    by_seg = {}
    for r in m.collect():
        by_seg.setdefault(r["audience_id"], set()).add(r["profile_id"])

    # NEW1 is new-to-brand (single current-period order), never lapsing/churned.
    assert "NEW1" in by_seg.get("SEG-NEW-TO-BRAND", set())
    assert "NEW1" not in by_seg.get("SEG-LAPSING", set())
    # LAP1 stopped ordering after period 3 -> lapsing or churned, not new.
    assert "LAP1" in (by_seg.get("SEG-LAPSING", set()) | by_seg.get("SEG-CHURNED-WINBACK", set()))
    assert "LAP1" not in by_seg.get("SEG-NEW-TO-BRAND", set())
    # DSC1 buys only on discount -> discount-driven, never full-price-loyal.
    assert "DSC1" in by_seg.get("SEG-DISCOUNT-DRIVEN", set())
    assert "DSC1" not in by_seg.get("SEG-FULL-PRICE-LOYAL", set())
    # VIP1: big full-price spend + frequency 4 -> VIP + high-value-repeat, not discount-driven.
    assert "VIP1" in by_seg.get("SEG-VIP", set())
    assert "VIP1" in by_seg.get("SEG-HIGH-VALUE-REPEAT", set())
    assert "VIP1" not in by_seg.get("SEG-DISCOUNT-DRIVEN", set())
    # every emitted audience_id is a known canned segment id.
    from _common import BEHAVIORAL_SEGMENT_IDS
    assert set(by_seg).issubset(set(BEHAVIORAL_SEGMENT_IDS))


# ---------- payment generator: enum-domain legality + coverage (no Spark) ----------

def _check_domain(checks_path, check_name):
    """Parse the NOT IN (...) allowed-value list for a named check in checks.sql."""
    text = open(checks_path).read()
    block = text.split(f"-- check: {check_name}")[1].split("-- check:")[0]
    return set(re.findall(r"'([a-z_]+)'", block))


PAYMENT_CHECKS = os.path.join(REPO, "canonical-core", "payment", "checks.sql")


def test_payment_generator_enums_within_and_covering_check_domains():
    src = open(GENERATOR).read()
    type_domain = _check_domain(PAYMENT_CHECKS, "payment_type_domain")
    status_domain = _check_domain(PAYMENT_CHECKS, "payment_status_domain")
    emitted_types = set(re.findall(r'payment_type",\s*F\.lit\("([a-z_]+)"\)', src))
    # payment_status is emitted both as plain .withColumn("payment_status", F.lit(...))
    # AND via the sale settlement-status F.when(...) mix assigned to `sale_status`.
    # Capture both so coverage reflects the real emitted literals, not dead strings.
    emitted_statuses = set(re.findall(r'payment_status",\s*F\.lit\("([a-z_]+)"\)', src))
    mix = re.search(r"sale_status = \((.*?)\n\s*\)", src, re.DOTALL)
    if mix:
        emitted_statuses |= set(re.findall(r'F\.lit\("([a-z_]+)"\)', mix.group(1)))
    # Legality: everything emitted is inside the CHECK domain.
    assert emitted_types <= type_domain, f"illegal types: {emitted_types - type_domain}"
    assert emitted_statuses <= status_domain, f"illegal statuses: {emitted_statuses - status_domain}"
    # Coverage: the generator exercises every allowed value (DoD MUST #8 realism).
    assert emitted_types == type_domain, f"uncovered types: {type_domain - emitted_types}"
    assert emitted_statuses == status_domain, f"uncovered statuses: {status_domain - emitted_statuses}"
