"""Tests for AI-Assisted Store Associates — Real-Time Data Access.

Covers: event current-state derivation, idempotency, late events, stock
status, price/promo eligibility, order masking, store-scope auth, freshness,
partial results, audit emission, schema/DQ static checks, and gold Spark
execution against deterministic fixtures.
"""

from __future__ import annotations

import ast
import os
import re
from datetime import datetime, timedelta, timezone

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.associate_realtime_access import (
    RESTRICTED_FIELDS,
    AssociateLookupService,
    authorize,
    current_state_from_events,
)
from tools.associate_realtime_access.envelope import AssociateLookupRequest
from tools.ordm_config import resolve, view_select_body

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PKG = os.path.join(REPO, "outcome-packages", "ai-assisted-store-associates")
GEN = os.path.join(REPO, "runtime", "synthetic-data", "generators", "ai_assisted_store_associates.py")

PII_OR_RESTRICTED = RESTRICTED_FIELDS | {
    "loyalty_id", "household_id", "first_name", "middle_name", "last_name",
    "date_of_birth", "name_prefix", "name_suffix", "contact_value", "tax_id",
}


def _read(path):
    return open(path).read()


def _outputs(path):
    sel = sqlglot.parse_one(
        view_select_body(resolve(_read(path), "c")),
        read="databricks",
        error_level="ignore",
    )
    return set(sel.named_selects)


def _ddl_cols(path, skip_sk):
    create = next(
        s for s in sqlglot.parse(resolve(_read(path), "c"), read="databricks", error_level="ignore")
        if isinstance(s, E.Create)
    )
    return {c.name for c in create.find_all(E.ColumnDef) if c.name != skip_sk}


def _gen_cols(name):
    mod = ast.parse(_read(GEN))
    for n in mod.body:
        if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == name:
            return {e.value for e in n.value.elts}
    raise AssertionError(f"column list {name} not found in generator")


# ---------- static / structural ----------

@pytest.mark.parametrize(
    "table,skip,gen_const",
    [
        ("associate_context_event", "associate_context_event_sk", "ASSOCIATE_CONTEXT_EVENT_COLUMNS"),
        ("associate_fulfillment_status", "associate_fulfillment_status_sk", "ASSOCIATE_FULFILLMENT_STATUS_COLUMNS"),
        ("associate_lookup_audit", "associate_lookup_audit_sk", "ASSOCIATE_LOOKUP_AUDIT_COLUMNS"),
    ],
)
def test_generator_columns_match_ddl(table, skip, gen_const):
    ddl = _ddl_cols(os.path.join(PKG, "tables", f"{table}.sql"), skip)
    gen = _gen_cols(gen_const)
    assert ddl == gen, f"{table} drift: missing={sorted(ddl - gen)} extra={sorted(gen - ddl)}"


@pytest.mark.parametrize(
    "view,required",
    [
        (
            "gold_associate_product_inventory_current.sql",
            {
                "product_id", "store_id", "stock_status", "quantity_on_hand",
                "quantity_available_to_sell", "freshness_status", "explanation", "warning",
                "source_system", "inventory_basis", "location_basis", "nearby_store_match_basis",
            },
        ),
        (
            "gold_associate_price_promotion_current.sql",
            {
                "product_id", "store_id", "base_price_amount", "effective_selling_price_amount",
                "customer_eligibility_status", "freshness_status",
            },
        ),
        (
            "gold_associate_order_status_current.sql",
            {
                "order_id", "fulfillment_type", "order_status", "pickup_readiness",
                "requires_customer_verification", "freshness_status",
            },
        ),
        (
            "gold_associate_data_freshness.sql",
            {"feed_name", "freshness_status", "sla_state", "freshness_lag_minutes"},
        ),
    ],
)
def test_gold_exposes_required_columns(view, required):
    outs = _outputs(os.path.join(PKG, "gold", view))
    assert required <= outs, f"{view} missing {sorted(required - outs)}"


@pytest.mark.parametrize(
    "view",
    [
        "gold_associate_product_inventory_current.sql",
        "gold_associate_price_promotion_current.sql",
        "gold_associate_order_status_current.sql",
        "gold_associate_operational_context_current.sql",
        "gold_associate_data_freshness.sql",
    ],
)
def test_no_restricted_columns_in_gold(view):
    leaked = PII_OR_RESTRICTED & _outputs(os.path.join(PKG, "gold", view))
    assert not leaked, f"{view} exposes restricted columns: {sorted(leaked)}"


def test_fulfillment_ddl_has_no_customer_pii():
    cols = _ddl_cols(
        os.path.join(PKG, "tables", "associate_fulfillment_status.sql"),
        "associate_fulfillment_status_sk",
    )
    assert not (cols & PII_OR_RESTRICTED)


def test_no_hardcoded_catalog_in_package_sql():
    for root, _, files in os.walk(PKG):
        for f in files:
            if not f.endswith(".sql"):
                continue
            txt = _read(os.path.join(root, f))
            assert not re.search(r"\bretail_prod\b|\bretail_dev\b", txt)
            if "CREATE" in txt.upper():
                assert "${catalog}" in txt or "${" in txt


def test_aasa_schema_token_registered():
    from tools.ordm_config import schema_defaults
    defaults = schema_defaults()
    assert defaults["aasa_schema"] == "ai_assisted_store_associates"


@pytest.mark.parametrize(
    "view,cluster_cols",
    [
        ("gold_associate_product_inventory_current.sql", ("store_id", "product_id")),
        ("gold_associate_order_status_current.sql", ("store_id", "order_id")),
    ],
)
def test_inventory_and_order_gold_are_materialized_views(view, cluster_cols):
    """P0 serving surfaces: MV create + trailing CLUSTER BY for point lookup."""
    txt = _read(os.path.join(PKG, "gold", view))
    assert re.search(
        r"CREATE\s+OR\s+REFRESH\s+MATERIALIZED\s+VIEW", txt, re.I
    ), f"{view} must be CREATE OR REFRESH MATERIALIZED VIEW"
    assert not re.search(r"CREATE\s+OR\s+REPLACE\s+VIEW", txt, re.I)
    cluster = re.search(r"CLUSTER\s+BY\s*\(([^)]+)\)", txt, re.I)
    assert cluster, f"{view} must declare CLUSTER BY (...)"
    cols = tuple(c.strip() for c in cluster.group(1).split(","))
    assert cols == cluster_cols, f"{view} CLUSTER BY {cols} != {cluster_cols}"


def test_store_scope_filters_sql_template():
    """Deploy-gated UC row filter template (defence in depth vs Python policy)."""
    path = os.path.join(PKG, "filters.sql")
    assert os.path.isfile(path)
    txt = _read(path)
    assert "associate_store_scope" in txt
    assert "SET ROW FILTER" in txt.upper()
    assert "is_account_group_member" in txt
    assert "aasa_cross_store" in txt
    assert "${catalog}.${aasa_schema}" in txt
    # Must cover the two MVs + remaining store-grained gold
    for name in (
        "gold_associate_product_inventory_current",
        "gold_associate_order_status_current",
        "gold_associate_price_promotion_current",
        "gold_associate_operational_context_current",
        "gold_associate_data_freshness",
    ):
        assert name in txt, f"filters.sql missing attach for {name}"
    nb = os.path.join(PKG, "notebook-templates", "store_scope_row_filters.sql")
    assert os.path.isfile(nb)


@pytest.mark.parametrize(
    "table,cluster_cols",
    [
        ("associate_context_event.sql", ("store_id", "product_id", "event_timestamp")),
        ("associate_fulfillment_status.sql", ("store_id", "order_id")),
        ("associate_lookup_audit.sql", ("store_id", "request_timestamp")),
    ],
)
def test_extension_tables_enable_cdf_and_lookup_clusters(table, cluster_cols):
    txt = _read(os.path.join(PKG, "tables", table))
    assert re.search(r"delta\.enableChangeDataFeed\s*=\s*true", txt, re.I), (
        f"{table} must enable Change Data Feed"
    )
    cluster = re.search(r"CLUSTER\s+BY\s*\(([^)]+)\)", txt, re.I)
    assert cluster, f"{table} must declare CLUSTER BY"
    cols = tuple(c.strip() for c in cluster.group(1).split(","))
    assert cols == cluster_cols, f"{table} CLUSTER BY {cols} != {cluster_cols}"


def test_genie_space_and_certification_tags():
    genie_path = os.path.join(PKG, "genie_space.json")
    assert os.path.isfile(genie_path)
    import json
    space = json.loads(_read(genie_path))
    assert space["version"] == 2
    ids = []
    for instr in space["instructions"]["text_instructions"]:
        ids.append(instr["id"])
        blob = " ".join(instr["content"]).lower()
        if "inventory_basis" in blob or "shelf" in blob or "nearest" in blob or "pii" in blob:
            pass  # covered below
    assert len(ids) == len(set(ids))
    joined = " ".join(
        " ".join(i["content"]) for i in space["instructions"]["text_instructions"]
    ).lower()
    assert "inventory_basis" in joined
    assert "not_modeled" in joined or "shelf" in joined
    assert "nearest" in joined
    assert "pii" in joined

    comments = _read(os.path.join(PKG, "comments.sql"))
    assert "system.certification_status" in comments
    assert comments.count("'certified'") >= 5


def test_ingest_and_lakebase_adopter_artifacts():
    assert os.path.isfile(
        os.path.join(PKG, "notebook-templates", "associate_context_event_ingest.sql")
    )
    ingest = _read(
        os.path.join(PKG, "notebook-templates", "associate_context_event_ingest.sql")
    )
    assert "MERGE INTO" in ingest.upper()
    assert "associate_context_event_id" in ingest
    assert "REFRESH MATERIALIZED VIEW" in ingest.upper()
    assert os.path.isfile(os.path.join(PKG, "LAKEBASE_SERVING.md"))
    lake = _read(os.path.join(PKG, "LAKEBASE_SERVING.md"))
    assert "ADR 0005" in lake or "0005" in lake
    assert "enableChangeDataFeed" in lake or "Change Data Feed" in lake


# ---------- event current-state / idempotency / late events ----------

def _ts(minutes_ago: int, base=None):
    base = base or datetime(2026, 8, 11, 15, 0, 0)
    return base - timedelta(minutes=minutes_ago)


def test_current_state_from_ordered_events():
    events = [
        {
            "associate_context_event_id": "E1",
            "product_id": "P1",
            "store_id": "S1",
            "quantity_on_hand": 10,
            "event_timestamp": _ts(30),
            "ingest_timestamp": _ts(29),
        },
        {
            "associate_context_event_id": "E2",
            "product_id": "P1",
            "store_id": "S1",
            "quantity_on_hand": 7,
            "event_timestamp": _ts(10),
            "ingest_timestamp": _ts(9),
        },
    ]
    cur = current_state_from_events(events, entity_keys=("product_id", "store_id"))
    assert len(cur) == 1
    assert cur[0]["quantity_on_hand"] == 7


def test_duplicate_event_id_idempotent():
    events = [
        {
            "associate_context_event_id": "E1",
            "product_id": "P1",
            "store_id": "S1",
            "quantity_on_hand": 10,
            "event_timestamp": _ts(10),
            "ingest_timestamp": _ts(9),
        },
        {
            "associate_context_event_id": "E1",
            "product_id": "P1",
            "store_id": "S1",
            "quantity_on_hand": 10,
            "event_timestamp": _ts(10),
            "ingest_timestamp": _ts(9),
        },
    ]
    cur = current_state_from_events(events, entity_keys=("product_id", "store_id"))
    assert len(cur) == 1


def test_late_arriving_older_event_does_not_win():
    events = [
        {
            "associate_context_event_id": "E-NEW",
            "product_id": "P1",
            "store_id": "S1",
            "quantity_on_hand": 5,
            "event_timestamp": _ts(10),
            "ingest_timestamp": _ts(9),
        },
        {
            "associate_context_event_id": "E-OLD-LATE",
            "product_id": "P1",
            "store_id": "S1",
            "quantity_on_hand": 99,
            "event_timestamp": _ts(60),
            "ingest_timestamp": _ts(1),
        },
    ]
    cur = current_state_from_events(events, entity_keys=("product_id", "store_id"))
    assert cur[0]["quantity_on_hand"] == 5


def test_out_of_order_input_still_picks_latest_event_time():
    events = [
        {
            "associate_context_event_id": "E-B",
            "product_id": "P1",
            "store_id": "S1",
            "quantity_on_hand": 2,
            "event_timestamp": _ts(5),
            "ingest_timestamp": _ts(4),
        },
        {
            "associate_context_event_id": "E-A",
            "product_id": "P1",
            "store_id": "S1",
            "quantity_on_hand": 9,
            "event_timestamp": _ts(20),
            "ingest_timestamp": _ts(19),
        },
    ]
    cur = current_state_from_events(events, entity_keys=("product_id", "store_id"))
    assert cur[0]["quantity_on_hand"] == 2


def test_deterministic_identical_input():
    events = [
        {
            "associate_context_event_id": f"E{i}",
            "product_id": "P1",
            "store_id": "S1",
            "quantity_on_hand": i,
            "event_timestamp": _ts(100 - i),
            "ingest_timestamp": _ts(99 - i),
        }
        for i in range(5)
    ]
    a = current_state_from_events(events, entity_keys=("product_id", "store_id"))
    b = current_state_from_events(events, entity_keys=("product_id", "store_id"))
    assert a == b


# ---------- policy / lookup service ----------

def _base_req(**overrides):
    raw = {
        "request_id": "REQ-1",
        "request_timestamp": datetime(2026, 8, 11, 15, 0, 0, tzinfo=timezone.utc),
        "store_id": "S1",
        "associate_id": "EMP-1",
        "associate_role": "sales_associate",
        "channel": "mobile",
        "requested_capability": "get_product_availability",
        "request_correlation_id": "CORR-1",
        "authorized_store_ids": ["S1"],
        "product_id": "P1",
    }
    raw.update(overrides)
    return raw


def test_product_location_not_modeled():
    svc = AssociateLookupService(
        inventory_rows=[{
            "product_id": "P1", "store_id": "S1", "stock_status": "IN_STOCK",
            "sales_floor_or_backroom_location": None, "location_basis": "not_modeled",
            "inventory_basis": "daily_snapshot",
            "freshness_status": "fresh", "source_system": "inv", "warning": "EOD",
        }]
    )
    resp = svc.lookup(_base_req(requested_capability="get_product_location"))
    assert resp.status == "NOT_AVAILABLE"
    assert resp.data["location_basis"] == "not_modeled"
    assert any("shelf/bay" in w.lower() or "planogram" in w.lower() for w in resp.warnings)


def test_product_location_optional_code_disclaims_geo():
    svc = AssociateLookupService(
        inventory_rows=[{
            "product_id": "P1", "store_id": "S1", "stock_status": "IN_STOCK",
            "sales_floor_or_backroom_location": "A-12", "location_basis": "event_location_code",
            "inventory_basis": "event_overlay",
            "nearby_store_with_stock_id": "S2",
            "nearby_store_match_basis": "same_region_on_hand",
            "freshness_status": "fresh", "source_system": "inv", "warning": None,
        }]
    )
    resp = svc.lookup(_base_req(requested_capability="get_product_location"))
    assert resp.status == "SUCCESS"
    assert resp.data["location_basis"] == "event_location_code"
    assert resp.data["nearby_store_match_basis"] == "same_region_on_hand"
    assert any("not shelf/bay" in w.lower() for w in resp.warnings)


def test_daily_snapshot_warning_surfaced_on_availability():
    svc = AssociateLookupService(
        inventory_rows=[{
            "product_id": "P1", "store_id": "S1", "stock_status": "IN_STOCK",
            "inventory_basis": "daily_snapshot",
            "freshness_status": "fresh", "source_system": "inv",
            "explanation": "End-of-day inventory_position snapshot",
            "warning": "Quantities are end-of-day snapshot grain — not intra-day real-time unless an inventory event overlay is present.",
        }]
    )
    resp = svc.lookup(_base_req())
    assert resp.status == "SUCCESS"
    assert resp.data["inventory_basis"] == "daily_snapshot"
    assert any("end-of-day" in w.lower() for w in resp.warnings)


def test_inventory_status_classification_via_lookup():
    svc = AssociateLookupService(
        inventory_rows=[{
            "product_id": "P1", "store_id": "S1", "stock_status": "LOW_STOCK",
            "quantity_on_hand": 3, "freshness_status": "fresh", "source_system": "inv",
            "explanation": "low", "warning": None,
        }]
    )
    resp = svc.lookup(_base_req())
    assert resp.status == "SUCCESS"
    assert resp.data["stock_status"] == "LOW_STOCK"


def test_store_scope_authorization_denied():
    audits = []
    svc = AssociateLookupService(audit_sink=audits.append)
    resp = svc.lookup(_base_req(store_id="S9", authorized_store_ids=["S1"]))
    assert resp.status == "ACCESS_DENIED"
    assert resp.access_decision["reason_code"] == "STORE_SCOPE_DENIED"
    assert audits and audits[0]["access_decision"] == "deny"


def test_product_fuzzy_search_denied():
    resp = AssociateLookupService().lookup(
        _base_req(product_id=None, product_search_term="blue shirt")
    )
    assert resp.status == "INVALID_REQUEST"
    assert resp.access_decision["reason_code"] == "PRODUCT_SEARCH_REQUIRES_EXACT_ID"


def test_order_requires_exact_id():
    resp = AssociateLookupService().lookup(
        _base_req(
            requested_capability="get_order_fulfillment_status",
            product_id=None,
            order_id=None,
        )
    )
    assert resp.status == "INVALID_REQUEST"
    assert resp.access_decision["reason_code"] == "MISSING_ORDER_ID"


def test_order_verification_and_no_pii():
    audits = []
    svc = AssociateLookupService(
        order_rows=[{
            "order_id": "ORD-1",
            "store_id": "S1",
            "order_status": "ready_for_pickup",
            "pickup_readiness": "ready",
            "requires_customer_verification": True,
            "freshness_status": "fresh",
            "source_system": "oms",
            "profile_id": "SHOULD_NEVER_LEAK",
            "warning": None,
            "explanation": "ready",
        }],
        audit_sink=audits.append,
    )
    denied = svc.lookup(
        _base_req(
            requested_capability="get_order_fulfillment_status",
            product_id=None,
            order_id="ORD-1",
        )
    )
    assert denied.status == "ACCESS_DENIED"
    assert denied.access_decision["reason_code"] == "ORDER_REQUIRES_CUSTOMER_VERIFICATION"

    allowed = svc.lookup(
        _base_req(
            requested_capability="get_order_fulfillment_status",
            product_id=None,
            order_id="ORD-1",
            customer_context_present=True,
            customer_verified=True,
        )
    )
    assert allowed.status == "SUCCESS"
    assert "profile_id" not in (allowed.data or {})


def test_customer_id_without_verification_denied():
    decision = authorize(AssociateLookupRequest.from_mapping(
        _base_req(customer_id="C-1", customer_context_present=False)
    ))
    assert not decision.allowed
    assert decision.reason_code == "CUSTOMER_PII_CONTEXT_DENIED"


def test_stale_data_status():
    svc = AssociateLookupService(
        inventory_rows=[{
            "product_id": "P1", "store_id": "S1", "stock_status": "IN_STOCK",
            "freshness_status": "stale", "source_system": "inv",
            "explanation": "stale", "warning": "verify",
        }]
    )
    resp = svc.lookup(_base_req())
    assert resp.status == "STALE_DATA"
    assert resp.warnings


def test_partial_result_when_price_missing():
    svc = AssociateLookupService(
        inventory_rows=[{
            "product_id": "P1", "store_id": "S1", "stock_status": "IN_STOCK",
            "freshness_status": "fresh", "source_system": "inv",
        }],
        price_rows=[],
    )
    resp = svc.lookup(_base_req(requested_capability="get_price_and_promotions"))
    assert resp.status == "PARTIAL_RESULT"
    assert "price" in (resp.source_lineage.get("missing_domains") or [])


def test_audit_for_permitted_and_denied():
    audits = []
    svc = AssociateLookupService(
        inventory_rows=[{
            "product_id": "P1", "store_id": "S1", "stock_status": "IN_STOCK",
            "freshness_status": "fresh", "source_system": "inv",
            "explanation": "ok", "warning": None,
        }],
        audit_sink=audits.append,
    )
    svc.lookup(_base_req())
    svc.lookup(_base_req(store_id="OTHER", authorized_store_ids=["S1"]))
    assert len(audits) == 2
    assert audits[0]["access_decision"] == "allow"
    assert audits[1]["access_decision"] == "deny"
    assert audits[0]["product_id_hash"]


def test_summary_partial_cross_domain():
    svc = AssociateLookupService(
        inventory_rows=[{
            "product_id": "P1", "store_id": "S1", "stock_status": "IN_STOCK",
            "freshness_status": "fresh", "source_system": "inv",
        }],
        price_rows=[],
        operations_rows=[],
    )
    resp = svc.lookup(_base_req(requested_capability="get_associate_context_summary"))
    assert resp.status == "PARTIAL_RESULT"
    assert "inventory" in resp.data


def test_price_expired_promo_not_active_in_fixture_row():
    svc = AssociateLookupService(
        price_rows=[{
            "product_id": "P1", "store_id": "S1",
            "base_price_amount": 10.0,
            "effective_selling_price_amount": 10.0,
            "active_promo_id": None,
            "store_channel_eligibility": "no_active_promotion",
            "customer_eligibility_status": "CUSTOMER_ELIGIBILITY_REQUIRES_AUTHORIZED_CONTEXT",
            "freshness_status": "fresh",
            "source_system": "price",
            "warning": None,
        }]
    )
    resp = svc.lookup(_base_req(requested_capability="get_price_and_promotions"))
    assert resp.status == "SUCCESS"
    assert resp.data["active_promo_id"] is None


# ---------- Spark gold engine tests ----------

_INV_SUBS = [
    ("${catalog}.${inventory_schema}.inventory_position", "inventory_position"),
    ("${catalog}.${product_schema}.product", "product"),
    ("${catalog}.${store_schema}.store", "store"),
    ("${catalog}.${aasa_schema}.associate_context_event", "associate_context_event"),
]


def _rewrite(path, subs):
    body = view_select_body(_read(path))
    for a, b in subs:
        body = body.replace(a, b)
    return body


def test_gold_inventory_spark_stock_and_overlay(spark):
    inv_path = os.path.join(PKG, "gold", "gold_associate_product_inventory_current.sql")
    now = datetime(2026, 8, 11, 15, 0, 0)
    spark.createDataFrame(
        [
            (1, "P1", "S1", datetime(2026, 8, 10).date(), 10.0, 2.0, False, False, "inv", now),
            (2, "P2", "S1", datetime(2026, 8, 10).date(), 0.0, 0.0, True, True, "inv", now),
            (3, "P2", "S2", datetime(2026, 8, 10).date(), 8.0, 0.0, False, False, "inv", now),
        ],
        "inventory_position_sk long, product_id string, store_id string, date_key date, "
        "units_on_hand_eod double, units_in_transit double, is_stockout boolean, "
        "replenishment_flag boolean, record_source string, load_timestamp timestamp",
    ).createOrReplaceTempView("inventory_position")

    spark.createDataFrame(
        [
            (1, "P1", "SKU1", "GTIN1", "Prod 1", "Brand", "Cat", "Dept", True),
            (2, "P2", "SKU2", "GTIN2", "Prod 2", "Brand", "Cat", "Dept", True),
        ],
        "product_sk long, product_id string, sku string, gtin string, product_name string, "
        "brand string, category string, department string, is_current boolean",
    ).createOrReplaceTempView("product")

    spark.createDataFrame(
        [
            (1, "S1", "Store 1", "WEST", "D1", "active", True),
            (2, "S2", "Store 2", "WEST", "D1", "active", True),
        ],
        "store_sk long, store_id string, store_name string, region string, district string, "
        "store_status string, is_current boolean",
    ).createOrReplaceTempView("store")

    spark.createDataFrame(
        [
            (1, "E1", "inventory", "P1", "S1", 4.0, 3.0, 1.0, 0.0, "IN_STOCK", "A-1",
             "ledger", now - timedelta(minutes=5), now - timedelta(minutes=4), now - timedelta(minutes=4)),
        ],
        "associate_context_event_sk long, associate_context_event_id string, event_domain string, "
        "product_id string, store_id string, quantity_on_hand double, quantity_available double, "
        "quantity_reserved double, quantity_in_transit double, status_code string, location_code string, "
        "source_system string, event_timestamp timestamp, ingest_timestamp timestamp, processed_timestamp timestamp",
    ).createOrReplaceTempView("associate_context_event")

    body = _rewrite(inv_path, _INV_SUBS)
    spark.sql(f"CREATE OR REPLACE TEMP VIEW gold_inv AS {body}")
    rows = {(r["product_id"], r["store_id"]): r for r in spark.table("gold_inv").collect()}
    assert rows[("P1", "S1")]["quantity_on_hand"] == 4.0
    assert rows[("P1", "S1")]["stock_status"] == "IN_STOCK"
    assert rows[("P1", "S1")]["sales_floor_or_backroom_location"] == "A-1"
    assert rows[("P2", "S1")]["stock_status"] == "OUT_OF_STOCK"
    assert rows[("P2", "S1")]["nearby_store_with_stock_id"] == "S2"


def test_gold_order_spark_safe_columns(spark):
    path = os.path.join(PKG, "gold", "gold_associate_order_status_current.sql")
    now = datetime(2026, 8, 11, 15, 0, 0)
    spark.createDataFrame(
        [(1, "S1", "Store 1", True)],
        "store_sk long, store_id string, store_name string, is_current boolean",
    ).createOrReplaceTempView("store")
    spark.createDataFrame(
        [(1, "AFS-1", "ORD-1", 1, "S1", "bopis", "ready_for_pickup", "ready", "PU-1",
          "none", now, "oms", False, now)],
        "associate_fulfillment_status_sk long, associate_fulfillment_status_id string, order_id string, "
        "store_sk long, store_id string, fulfillment_type string, order_status string, "
        "pickup_readiness string, pickup_location_code string, exception_state string, "
        "last_event_timestamp timestamp, source_system string, requires_customer_verification boolean, "
        "data_freshness_timestamp timestamp",
    ).createOrReplaceTempView("associate_fulfillment_status")
    spark.createDataFrame(
        [],
        "associate_context_event_sk long, associate_context_event_id string, event_domain string, "
        "order_id string, status_code string, source_system string, event_timestamp timestamp, "
        "ingest_timestamp timestamp, processed_timestamp timestamp",
    ).createOrReplaceTempView("associate_context_event")

    subs = [
        ("${catalog}.${aasa_schema}.associate_fulfillment_status", "associate_fulfillment_status"),
        ("${catalog}.${store_schema}.store", "store"),
        ("${catalog}.${aasa_schema}.associate_context_event", "associate_context_event"),
    ]
    body = _rewrite(path, subs)
    spark.sql(f"CREATE OR REPLACE TEMP VIEW gold_ord AS {body}")
    cols = set(spark.table("gold_ord").columns)
    assert "order_id" in cols
    assert "profile_id" not in cols
    row = spark.table("gold_ord").collect()[0]
    assert row["order_status"] == "ready_for_pickup"
    assert row["pickup_readiness"] == "ready"


def test_end_to_end_fixture_scenarios():
    audits = []
    inv = [
        {"product_id": "P-IN", "store_id": "S1", "stock_status": "IN_STOCK",
         "quantity_on_hand": 24, "freshness_status": "fresh", "source_system": "inv",
         "sales_floor_or_backroom_location": "A-12", "explanation": "in stock", "warning": None},
        {"product_id": "P-LOW", "store_id": "S1", "stock_status": "LOW_STOCK",
         "quantity_on_hand": 2, "freshness_status": "fresh", "source_system": "inv",
         "sales_floor_or_backroom_location": "BACK-1", "explanation": "low", "warning": None},
        {"product_id": "P-OOS", "store_id": "S1", "stock_status": "OUT_OF_STOCK",
         "quantity_on_hand": 0, "nearby_store_with_stock_id": "S2",
         "freshness_status": "fresh", "source_system": "inv", "explanation": "oos", "warning": None},
        {"product_id": "P-STALE", "store_id": "S1", "stock_status": "IN_STOCK",
         "freshness_status": "stale", "source_system": "inv", "explanation": "stale",
         "warning": "stale feed"},
    ]
    price = [
        {"product_id": "P-IN", "store_id": "S1", "base_price_amount": 12.99,
         "effective_selling_price_amount": 10.99, "active_promo_id": "PROMO-1",
         "customer_eligibility_status": "CUSTOMER_ELIGIBILITY_REQUIRES_AUTHORIZED_CONTEXT",
         "freshness_status": "fresh", "source_system": "price", "warning": None},
        {"product_id": "P-LOW", "store_id": "S1", "base_price_amount": 8.5,
         "effective_selling_price_amount": 8.5, "active_promo_id": None,
         "customer_eligibility_status": "CUSTOMER_ELIGIBILITY_REQUIRES_AUTHORIZED_CONTEXT",
         "freshness_status": "delayed", "source_system": "price", "warning": "delayed"},
    ]
    orders = [
        {"order_id": "ORD-READY", "store_id": "S1", "order_status": "ready_for_pickup",
         "pickup_readiness": "ready", "requires_customer_verification": False,
         "freshness_status": "fresh", "source_system": "oms", "warning": None},
        {"order_id": "ORD-EXC", "store_id": "S1", "order_status": "exception",
         "pickup_readiness": "not_ready", "exception_state": "missing_item",
         "requires_customer_verification": False, "freshness_status": "fresh",
         "source_system": "oms", "warning": None},
    ]
    ops = [
        {"store_id": "S1", "context_type": "replenishment_task", "severity": "medium",
         "freshness_status": "fresh", "warning": None},
    ]
    svc = AssociateLookupService(
        inventory_rows=inv, price_rows=price, order_rows=orders,
        operations_rows=ops, audit_sink=audits.append,
    )

    assert svc.lookup(_base_req(product_id="P-IN")).data["stock_status"] == "IN_STOCK"
    assert svc.lookup(_base_req(product_id="P-LOW")).data["stock_status"] == "LOW_STOCK"
    oos = svc.lookup(_base_req(product_id="P-OOS"))
    assert oos.data["nearby_store_with_stock_id"] == "S2"
    assert svc.lookup(_base_req(product_id="P-STALE")).status == "STALE_DATA"
    promo = svc.lookup(_base_req(product_id="P-IN", requested_capability="get_price_and_promotions"))
    assert promo.data["active_promo_id"] == "PROMO-1"
    delayed = svc.lookup(_base_req(product_id="P-LOW", requested_capability="get_price_and_promotions"))
    assert delayed.status == "UPSTREAM_DATA_DELAY"
    ready = svc.lookup(_base_req(
        requested_capability="get_order_fulfillment_status", product_id=None, order_id="ORD-READY"))
    assert ready.data["pickup_readiness"] == "ready"
    exc = svc.lookup(_base_req(
        requested_capability="get_order_fulfillment_status", product_id=None, order_id="ORD-EXC"))
    assert exc.data["exception_state"] == "missing_item"
    assert svc.lookup(_base_req(store_id="SX", authorized_store_ids=["S1"])).status == "ACCESS_DENIED"
    assert svc.lookup(_base_req(requested_capability="get_store_operations_context", product_id=None)).status == "SUCCESS"
    assert len(audits) >= 8
