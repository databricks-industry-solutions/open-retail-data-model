"""Golden fixtures for the Assortment Optimization model outputs (Balancing Margin and Volume).

gold_assortment_optimization computes a heuristic space elasticity (within-product, cross-store
log-log slope of non-promo velocity on planogram facings, shrunk toward a 0.17 prior) and three
scenario projections tied to the rule-based recommendation. gold_affinity_features computes the
demand-transfer share those projections use. Spark runs the REAL gold SQL verbatim on temp-view
fixtures built with a KNOWN elasticity, so the estimator is checked against a true value rather
than against itself.

The static tests pin the synthetic-data contract that makes the same check possible on deployed
data: the sales generator and the planogram generator derive facings from one shared function.
"""
import ast
import math
import os
import re

import pytest

from tools.ordm_config import view_select_body

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GOLD = os.path.join(REPO, "outcome-packages", "balancing-margin-and-volume", "gold")
GEN = os.path.join(REPO, "runtime", "synthetic-data", "generators")

TRUE_ELASTICITY = 0.25
PRICE = 2.0
GM_PCT = 0.30            # unit margin = PRICE * GM_PCT = 0.60
UNIT_MARGIN = PRICE * GM_PCT
N_DAYS = 30
STORES = 6
FACINGS = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 2}     # store -> facings (same for every product)


def _body(name, subs):
    body = view_select_body(open(os.path.join(GOLD, name)).read())
    for a, b in subs:
        body = body.replace(a, b)
    return body


_AO_SUBS = [
    ("${catalog}.${bmv_schema}.gold_sales_actuals", "gold_sales_actuals"),
    ("${catalog}.${bmv_schema}.gold_price_actuals", "gold_price_actuals"),
    ("${catalog}.${bmv_schema}.gold_promotional_features", "gold_promotional_features"),
    ("${catalog}.${bmv_schema}.gold_affinity_features", "gold_affinity_features"),
    ("${catalog}.${bmv_schema}.gold_bucket_features", "gold_bucket_features"),
    ("${catalog}.${bmv_schema}.planogram", "planogram"),
    ("${catalog}.${bmv_schema}.product_relationship", "product_relationship"),
    ("${catalog}.${inventory_schema}.inventory_position", "inventory_position"),
]


def _units(product, store):
    """Known log-log space response with a small per-store wobble (so the fit has a non-zero SE)."""
    level = 10.0 + product
    wobble = 1.0 + 0.02 * ((store % 3) - 1)
    return level * (FACINGS[store] / 3.0) ** TRUE_ELASTICITY * wobble


def _build_assortment(spark):
    import datetime as dt
    start = dt.date(2025, 1, 1)
    days = [start + dt.timedelta(days=i) for i in range(N_DAYS)]
    last = days[-1]
    sales, price, promo, inv, bucket, aff = [], [], [], [], [], []
    for p in range(1, 5):
        for s in range(1, STORES + 1):
            u = _units(p, s)
            for d in days:
                sales.append((p, s, f"SKU-{p}", f"STR-{s}", d, u, u * PRICE))
                price.append((p, s, d, GM_PCT))
                promo.append((p, s, d, False))
                aff.append((p, s, d, 0.5 if p == 2 else 0.0))
            inv.append((p, s, last, 50.0))
            if (p, s) == (1, 1):
                bucket.append((p, s, last, "Fast Mover", "High"))      # tight stock -> EXPAND
            elif (p, s) == (2, 1):
                bucket.append((p, s, last, "Slow Mover", "Low"))       # -> DROP
            else:
                bucket.append((p, s, last, "Standard", "Healthy"))     # -> KEEP
    spark.createDataFrame(sales, "product_sk long, store_sk long, product_id string, store_id string, "
                                 "date_key date, units_sold double, net_sales_lc double"
                          ).createOrReplaceTempView("gold_sales_actuals")
    spark.createDataFrame(price, "product_sk long, store_sk long, date_key date, gross_margin_pct double"
                          ).createOrReplaceTempView("gold_price_actuals")
    spark.createDataFrame(promo, "product_sk long, store_sk long, date_key date, is_on_promo boolean"
                          ).createOrReplaceTempView("gold_promotional_features")
    spark.createDataFrame(aff, "product_sk long, store_sk long, date_key date, substitute_demand_transfer_pct double"
                          ).createOrReplaceTempView("gold_affinity_features")
    spark.createDataFrame(inv, "product_sk long, store_sk long, date_key date, units_on_hand_eod double"
                          ).createOrReplaceTempView("inventory_position")
    spark.createDataFrame(bucket, "product_sk long, store_sk long, date_key date, "
                                  "demand_velocity_bucket string, margin_health_bucket string"
                          ).createOrReplaceTempView("gold_bucket_features")
    # planogram for every product x store EXCEPT product 4 in store 6 (no allocation -> NULL elasticity)
    plano = [(p, s, "snacks", FACINGS[s], 1.5 * FACINGS[s], dt.date(2018, 1, 1), None)
             for p in range(1, 5) for s in range(1, STORES + 1) if (p, s) != (4, 6)]
    spark.createDataFrame(plano, "product_sk long, store_sk long, space_planning_category string, "
                                 "allocated_facings int, allocated_sqft double, "
                                 "effective_from_date date, effective_to_date date"
                          ).createOrReplaceTempView("planogram")
    # product 2's substitute is product 3
    spark.createDataFrame([(2, "SKU-2", 3, "SKU-3", "substitute", 0.5)],
                          "product_sk long, product_id string, related_product_sk long, "
                          "related_product_id string, relationship_type string, "
                          "affinity_coefficient double").createOrReplaceTempView("product_relationship")
    spark.sql("CREATE OR REPLACE TEMP VIEW ao AS " + _body("gold_assortment_optimization.sql", _AO_SUBS))
    return {(r.product_sk, r.store_sk): r for r in spark.sql("SELECT * FROM ao").collect()}


def test_space_elasticity_recovers_known_value(spark):
    rows = _build_assortment(spark)
    est = {float(r.space_elasticity) for k, r in rows.items() if r.space_elasticity is not None}
    assert len(est) == 1, f"one estimate per category expected, got {est}"
    e = est.pop()
    assert abs(e - TRUE_ELASTICITY) < 0.02, f"space_elasticity={e}, true={TRUE_ELASTICITY}"
    r = rows[(1, 1)]
    assert r.space_elasticity_n_obs == 23, r.space_elasticity_n_obs   # 4 x 6 minus the unallocated pair
    assert 0 < float(r.space_elasticity_se) < 0.05


def test_no_planogram_means_null_elasticity(spark):
    r = _build_assortment(spark)[(4, 6)]
    assert r.allocated_facings is None
    assert r.space_elasticity is None and r.space_elasticity_se is None


def test_projections_follow_the_recommendation(spark):
    rows = _build_assortment(spark)
    expand, drop = rows[(1, 1)], rows[(2, 1)]
    assert expand.recommendation == "EXPAND" and drop.recommendation == "DROP"

    # EXPAND: one more facing at the estimated elasticity; no substitutes mapped -> no drag
    e = float(expand.space_elasticity)
    want = float(expand.baseline_velocity) * (((FACINGS[1] + 1) / FACINGS[1]) ** e - 1)
    assert math.isclose(float(expand.projected_volume_lift), want, abs_tol=0.002)
    assert float(expand.projected_volume_lift) > 0
    assert float(expand.cannibalization_drag_lc) == 0
    assert math.isclose(float(expand.projected_margin_lift_lc), want * UNIT_MARGIN, abs_tol=0.01)

    # DROP: lose the SKU's own baseline; half of it is recaptured by the substitute (same unit margin)
    base = float(drop.baseline_velocity)
    assert math.isclose(float(drop.projected_volume_lift), -base, abs_tol=0.002)
    assert math.isclose(float(drop.cannibalization_drag_lc), -base * 0.5 * UNIT_MARGIN, abs_tol=0.01)
    assert math.isclose(float(drop.projected_margin_lift_lc), -base * UNIT_MARGIN * 0.5, abs_tol=0.01)

    for k, r in rows.items():
        if r.recommendation == "KEEP":
            assert float(r.projected_volume_lift) == 0, k


def test_drag_counts_only_substitutes_sold_in_the_store(spark):
    # The DROP SKU (product 2, store 1) gets a second substitute that sells nowhere. The product-level
    # transfer over both substitutes is 1 - 0.5 * 0.5 = 0.75, but only product 3 is ranged in store 1,
    # so the drag must use the store-conditional 0.5. The affinity-features input is set to the
    # product-level 0.75 so a regression back to it shows up as a 0.75 recapture.
    _build_assortment(spark)
    spark.createDataFrame([(2, "SKU-2", 3, "SKU-3", "substitute", 0.5),
                           (2, "SKU-2", 9, "SKU-9", "substitute", 0.5)],
                          "product_sk long, product_id string, related_product_sk long, "
                          "related_product_id string, relationship_type string, "
                          "affinity_coefficient double").createOrReplaceTempView("product_relationship")
    spark.sql("SELECT product_sk, store_sk, date_key, "
              "CASE WHEN product_sk = 2 THEN 0.75 ELSE substitute_demand_transfer_pct END "
              "AS substitute_demand_transfer_pct FROM gold_affinity_features"
              ).createOrReplaceTempView("gold_affinity_features_partial")
    subs = [(a, "gold_affinity_features_partial" if b == "gold_affinity_features" else b) for a, b in _AO_SUBS]
    rows = {(r.product_sk, r.store_sk): r
            for r in spark.sql(_body("gold_assortment_optimization.sql", subs)).collect()}
    drop = rows[(2, 1)]
    assert drop.recommendation == "DROP"
    base = float(drop.baseline_velocity)
    assert float(drop.substitute_demand_transfer_pct) == 0.75          # product-level input, unchanged
    assert math.isclose(float(drop.cannibalization_drag_lc), -base * 0.5 * UNIT_MARGIN, abs_tol=0.01)
    assert math.isclose(float(drop.projected_margin_lift_lc), -base * UNIT_MARGIN * 0.5, abs_tol=0.01)

def test_demand_transfer_is_noisy_or_of_substitute_affinities(spark):
    import datetime as dt
    d = dt.date(2025, 1, 1)
    spark.createDataFrame([
        (1, "SKU-1", 2, "SKU-2", "substitute", 0.5),
        (1, "SKU-1", 3, "SKU-3", "substitute", 0.5),
        (1, "SKU-1", 4, "SKU-4", "complement", 0.9),     # complements do not absorb demand
        (2, "SKU-2", 4, "SKU-4", "complement", 0.9),
    ], "product_sk long, product_id string, related_product_sk long, related_product_id string, "
       "relationship_type string, affinity_coefficient double").createOrReplaceTempView("product_relationship")
    spark.createDataFrame(
        [(p, 1, f"SKU-{p}", "STR-1", d, 10.0, 20.0, 22.0, 2.0) for p in range(1, 5)],
        "product_sk long, store_sk long, product_id string, store_id string, date_key date, "
        "units_sold double, net_sales_lc double, gross_sales_lc double, discount_value_lc double"
    ).createOrReplaceTempView("gold_sales_actuals")
    body = _body("gold_affinity_features.sql", [
        ("${catalog}.${bmv_schema}.product_relationship", "product_relationship"),
        ("${catalog}.${bmv_schema}.gold_sales_actuals", "gold_sales_actuals"),
    ])
    got = {r.product_sk: float(r.substitute_demand_transfer_pct)
           for r in spark.sql(body).collect()}
    assert math.isclose(got[1], 0.75, abs_tol=1e-4), got     # 1 - (1 - 0.5)(1 - 0.5)
    assert got[2] == 0.0 and got[4] == 0.0, got              # no substitute mapped


def _calls(path, fn):
    return [n for n in ast.walk(ast.parse(open(path).read()))
            if isinstance(n, ast.Call) and getattr(n.func, "id", None) == fn]


def test_sales_and_planogram_share_one_facings_function():
    """Sales is written before the planogram, so the two can only agree if both derive facings
    from _common.shelf_facings (directly, or via shelf_space_multiplier)."""
    assert _calls(os.path.join(GEN, "trade_promotion.py"), "shelf_space_multiplier")
    assert _calls(os.path.join(GEN, "balancing_margin_and_volume.py"), "shelf_facings")
    common = open(os.path.join(GEN, "_common.py")).read()
    assert re.search(r"def shelf_space_multiplier\(.*\):[\s\S]*?shelf_facings\(", common)


def test_every_synthetic_category_has_a_true_space_elasticity():
    tp = ast.parse(open(os.path.join(GEN, "trade_promotion.py")).read())
    cats = next(ast.literal_eval(n.value) for n in tp.body
                if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", None) == "CATEGORIES")
    cm = ast.parse(open(os.path.join(GEN, "_common.py")).read())
    truth = next(ast.literal_eval(n.value) for n in cm.body
                 if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", None) == "SPACE_ELASTICITY_BY_CATEGORY")
    assert set(cats) == set(truth), f"categories without a true elasticity: {set(cats) - set(truth)}"
    assert all(0 < v < 1 for v in truth.values())


@pytest.mark.parametrize("name", ["gold_assortment_optimization.sql", "gold_affinity_features.sql"])
def test_model_outputs_are_not_null_placeholders(name):
    text = open(os.path.join(GOLD, name)).read()
    for col in ("space_elasticity", "projected_volume_lift", "projected_margin_lift_lc",
                "cannibalization_drag_lc", "substitute_demand_transfer_pct"):
        assert not re.search(rf"CAST\s*\(\s*NULL\s+AS\s+[A-Z0-9(), ]+\)\s+AS\s+{col}\b", text, re.I), (name, col)
