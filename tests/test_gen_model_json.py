"""Guards for the gold-SQL FROM/JOIN lineage pass in tools/gen_model_json.py.

Gold tables are materialized VIEWS with no declared FK relationships, so the
FK-only `consumes` derivation was always empty for gold-anchored use cases (the
explorer's L1 chip strip rendered nothing). The lineage pass reads each gold
view's SQL FROM/JOIN refs and resolves them back to core units, populating both
the per-use-case `consumes` and the L0 overview edges.

These tests assert:
  - a known gold-anchored use case now derives a NON-empty `consumes`,
  - the L0 overview edges include the gold-derived core domains,
  - a missing gold SQL file (a real authoring error) fails loud.
"""
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import copy
import functools
import os

from tools.gen_model_json import (
    PUBLIC,
    _gold_consumes,
    build_model as _build_model,
    staged_assets,
    staged_orphans,
)


@functools.lru_cache(maxsize=1)
def _model_once():
    return _build_model()


def build_model():
    # Shadows the imported build_model on purpose, so the call sites stay unchanged.
    # Building the whole model takes seconds and the tests here only READ it, so build it
    # once per test process and hand each test its own deep copy (a test that mutates its
    # copy cannot leak into another).
    return copy.deepcopy(_model_once())


def _use_case(model, package, use_case):
    unit = next(u for u in model["units"] if u["name"] == package)
    return next(uc for uc in unit["use_cases"] if uc["name"] == use_case)


def _l0_targets(model, package):
    return sorted(
        e["target"]
        for e in model["overview"]["edges"]
        if e["kind"] == "consumes" and e["source"] == package
    )


def test_gold_anchored_use_case_consumes_is_non_empty():
    # bmv "Dynamic Price Optimization" is anchored on gold views that reach core
    # through SQL FROM/JOIN (e.g. gold_price_actuals -> sales/product/product_price).
    # The FK-only derivation left this empty; the lineage pass must populate it,
    # including at least `product` and `transaction`.
    model = build_model()
    uc = _use_case(model, "balancing-margin-and-volume", "Dynamic Price Optimization")
    assert uc["consumes"], "gold-anchored use case must derive a non-empty consumes"
    assert {"product", "transaction"} <= set(uc["consumes"])
    # Determinism: sorted, unique.
    assert uc["consumes"] == sorted(set(uc["consumes"]))


def test_second_package_use_case_consumes():
    # A use case from another package resolves through gold-to-gold chaining and an
    # ingredient table's FKs (promotion_scope -> marketing/product/store).
    # Subset assertion (not exact-equality): these core domains MUST be in the derived
    # lineage, but adding a new source to a promote-with-purpose gold view should not
    # break this test — it pins the required lineage, not the full live set.
    model = build_model()
    uc = _use_case(model, "promote-with-purpose", "Trade Promotion")
    assert {"calendar", "marketing", "product", "store", "transaction"} <= set(uc["consumes"])


def test_use_case_consumes_follow_their_mapping():
    # consumes is derived ONLY from a use case's mapped gold views: its own `tables:` and,
    # since ADR 0045, its `foreign_tables` (qualified `<package>.<gold_view>` entries in
    # use-cases.yaml, surfaced in model.json). So an unmapped use case derives [] and a
    # mapped one reaches at least one core domain. Read from model.json, where the parsed
    # split lives (use-cases.yaml carries only `tables:`). Every use case is mapped today,
    # so the mapped direction is the one exercised; the positive single-use-case
    # counterpart is test_product_affinity_use_case_consumes.
    model = build_model()
    mapped = 0
    for unit in model["units"]:
        for uc in unit.get("use_cases") or []:
            if uc["tables"] or uc.get("foreign_tables"):
                assert uc["consumes"], f"{unit['name']} :: {uc['name']} is mapped but derives no consumes"
                mapped += 1
            else:
                assert uc["consumes"] == [], (
                    f"{unit['name']} :: {uc['name']} has no mapping but derived consumes={uc['consumes']}")
    assert mapped > 0

def test_product_affinity_use_case_consumes():
    # Product Affinity's gold views read customer_order_line (order) + product, so its
    # derived consumes must include those core domains (mirrors the gold-anchored cases).
    model = build_model()
    uc = _use_case(model, "actionable-customer-understanding", "Product Affinity")
    assert {"order", "product"} <= set(uc["consumes"])
    assert uc["consumes"] == sorted(set(uc["consumes"]))


def test_l0_edges_include_gold_derived_core_domains():
    # The home-screen (L0) overview edges are the UNION of the FK-based derivation
    # and the gold-SQL lineage, so bmv now consumes `transaction` (via sales in its
    # gold views), not only the FK-declared `product`.
    model = build_model()
    targets = _l0_targets(model, "balancing-margin-and-volume")
    assert "transaction" in targets and "product" in targets
    # L0 must be a superset of the union of its use-case chips (consistency).
    unit = next(u for u in model["units"] if u["name"] == "balancing-margin-and-volume")
    uc_union = set()
    for uc in unit["use_cases"]:
        uc_union |= set(uc["consumes"])
    assert uc_union <= set(targets)


def test_cross_package_use_case_consumes_resolves():
    # UCV's "Customer Lifetime Value" use case maps to ACU's gold_customer_ltv
    # (a cross-package reference via "actionable-customer-understanding.gold_customer_ltv").
    # Its `consumes` must resolve through ACU's lineage, not return empty.
    model = build_model()
    uc = _use_case(model, "unified-customer-view", "Customer Lifetime Value")
    # Verify the foreign_tables field exists
    assert "foreign_tables" in uc, "UCV CLV use case should have foreign_tables"
    assert uc["foreign_tables"] == [{"unit": "actionable-customer-understanding", "table": "gold_customer_ltv"}]
    # Verify consumes is non-empty and contains expected core domains
    assert uc["consumes"], "cross-package-referenced use case must derive a non-empty consumes"
    # gold_customer_ltv should reach customer (and possibly rfm/other ACU domains)
    # At minimum we expect core domains that ACU's gold views consume
    assert any(c in uc["consumes"] for c in ["customer", "transaction", "product"]), \
        f"CLV use case should consume core domains, got: {uc['consumes']}"
    # The chips are CORE DOMAIN names resolved through the owning package's lineage, the
    # same set the owning view's consumes_tables reaches (not raw table names).
    units = {u["name"]: u for u in model["units"]}
    core = {n for n, u in units.items() if u["kind"] == "core"}
    assert set(uc["consumes"]) <= core, uc["consumes"]
    ltv = next(t for t in units["actionable-customer-understanding"]["tables"] if t["name"] == "gold_customer_ltv")
    assert set(uc["consumes"]) == {e["unit"] for e in ltv["consumes_tables"]}
    # Reverse index on the owning package (ADR 0045): exactly one entry for this use case,
    # carrying the same tables and consumes, so ACU bands gold_customer_ltv under it.
    ext = units["actionable-customer-understanding"]["external_use_cases"]
    assert ext == [{
        "unit": "unified-customer-view",
        "name": "Customer Lifetime Value",
        "status": uc["status"],
        "tables": ["gold_customer_ltv"],
        "consumes": uc["consumes"],
    }]
    # Every outcome package carries the key; every reverse entry has a matching forward one.
    for u in units.values():
        if u["kind"] != "outcome":
            continue
        for e in u["external_use_cases"]:
            src = _use_case(model, e["unit"], e["name"])
            assert {"unit": u["name"], "table": e["tables"][0]} in src["foreign_tables"]


def test_missing_gold_sql_fails_loud(tmp_path):
    # A gold table with no SQL file is a real authoring error and must fail loud,
    # naming the offending table (mirrors _load_use_cases' no-silent-drops posture).
    (tmp_path / "gold").mkdir()
    with pytest.raises(RuntimeError, match="gold_absent"):
        _gold_consumes(
            str(tmp_path),
            ["gold_absent"],
            core_tables={"sales": "transaction"},
            relationships=[],
            known_tables={"sales", "gold_absent"},
        )


def test_ignores_unknown_qualified_refs(tmp_path):
    # A qualified ref to an unknown name (a CTE or function) is ignored, not fatal;
    # only refs matching a known table drive consumption.
    gold_dir = tmp_path / "gold"
    gold_dir.mkdir()
    (gold_dir / "gold_x.sql").write_text(
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${pkg_schema}.gold_x AS\n"
        "SELECT * FROM ${catalog}.${transaction_schema}.sales s\n"
        "JOIN ${catalog}.${pkg_schema}.some_cte_not_a_table c ON s.id = c.id;\n",
        encoding="utf-8",
    )
    result = _gold_consumes(
        str(tmp_path),
        ["gold_x"],
        core_tables={"sales": "transaction"},
        relationships=[],
        known_tables={"sales", "gold_x"},  # some_cte_not_a_table is NOT known
    )
    assert result.units["gold_x"] == {"transaction"}


def test_bare_ref_to_known_table_fails_loud(tmp_path):
    # A BARE (unqualified) FROM/JOIN to a real table would be dropped from lineage
    # (mistaken for a CTE), silently under-reporting `consumes`. The guard fails loud.
    gold_dir = tmp_path / "gold"
    gold_dir.mkdir()
    (gold_dir / "gold_y.sql").write_text(
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${pkg_schema}.gold_y AS\n"
        "SELECT * FROM sales s;\n",  # bare `sales`, a known table -> must fail loud
        encoding="utf-8",
    )
    with pytest.raises(RuntimeError, match="BARE name"):
        _gold_consumes(
            str(tmp_path),
            ["gold_y"],
            core_tables={"sales": "transaction"},
            relationships=[],
            known_tables={"sales", "gold_y"},
        )


def test_from_inside_a_string_literal_is_not_a_bare_ref(tmp_path):
    # A quoted string containing "from <table>" (e.g. a label/default) must NOT trip
    # the bare-ref guard - string literals are stripped before the FROM/JOIN scan. The
    # real qualified ref still resolves. (The pre-strip code raised on the string here.)
    gold_dir = tmp_path / "gold"
    gold_dir.mkdir()
    (gold_dir / "gold_s.sql").write_text(
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${pkg_schema}.gold_s AS\n"
        "SELECT 'derived from sales' AS note,\n"
        "       * FROM ${catalog}.${transaction_schema}.sales s;\n",
        encoding="utf-8",
    )
    result = _gold_consumes(
        str(tmp_path),
        ["gold_s"],
        core_tables={"sales": "transaction"},
        relationships=[],
        known_tables={"sales", "gold_s"},
    )
    assert result.units["gold_s"] == {"transaction"}


def test_column_list_cte_name_is_not_a_bare_ref(tmp_path):
    # A CTE in the column-list form `name (cols) AS (...)` whose name collides with a
    # real table must be recognized as a CTE, not false-tripped by the bare-ref guard
    # (M2). The older `name AS (` regex missed this form and would raise here.
    gold_dir = tmp_path / "gold"
    gold_dir.mkdir()
    (gold_dir / "gold_w.sql").write_text(
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${pkg_schema}.gold_w AS\n"
        "WITH sales (id, amt) AS (\n"
        "  SELECT id, amt FROM ${catalog}.${transaction_schema}.txn\n"
        ")\n"
        "SELECT * FROM sales;\n",  # `sales` here is the CTE above, not the known table
        encoding="utf-8",
    )
    result = _gold_consumes(
        str(tmp_path),
        ["gold_w"],
        core_tables={"txn": "transaction"},
        relationships=[],
        known_tables={"sales", "txn", "gold_w"},  # `sales` is also a known table name
    )
    assert result.units["gold_w"] == {"transaction"}


def test_gold_consumes_tables_resolves_to_leaf_silver_tables(tmp_path):
    # `.tables` resolves each gold view (transitively) to the leaf CORE (silver)
    # TABLES it reads, each tagged with its owning domain - the finer lineage the L1
    # overlay draws (vs the domain-level `.units`). Sorted by table name, deterministic.
    gold_dir = tmp_path / "gold"
    gold_dir.mkdir()
    (gold_dir / "gold_x.sql").write_text(
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${pkg_schema}.gold_x AS\n"
        "SELECT * FROM ${catalog}.${order_schema}.customer_order_line col\n"
        "JOIN ${catalog}.${product_schema}.product pr ON pr.product_sk = col.product_sk;\n",
        encoding="utf-8",
    )
    r = _gold_consumes(
        str(tmp_path),
        ["gold_x"],
        core_tables={"customer_order_line": "order", "product": "product"},
        relationships=[],
        known_tables={"customer_order_line", "product", "gold_x"},
    )
    assert r.units["gold_x"] == {"order", "product"}
    assert r.tables["gold_x"] == [
        {"table": "customer_order_line", "unit": "order"},
        {"table": "product", "unit": "product"},
    ]


def test_cross_package_refs_resolve_through_to_core(tmp_path):
    # A gold view may read ANOTHER package's ingredient table or gold view. Given the
    # other packages' parsed gold views + FKs, the walk reaches core through them;
    # without them the ref is a dead end and the view's core lineage silently drops
    # out (e.g. DSWS gold_supplier_media_report reading CMN's campaign_day).
    gold_dir = tmp_path / "gold"
    gold_dir.mkdir()
    (gold_dir / "gold_a.sql").write_text(
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${a_schema}.gold_a AS\n"
        "SELECT * FROM ${catalog}.${b_schema}.b_fact f\n"
        "JOIN ${catalog}.${b_schema}.gold_b g ON g.id = f.id;\n",
        encoding="utf-8",
    )
    common = dict(
        core_tables={"product": "product", "store": "store"},
        relationships=[],
        known_tables={"product", "store", "b_fact", "gold_b", "gold_a"},
    )
    assert _gold_consumes(str(tmp_path), ["gold_a"], **common).units["gold_a"] == set()
    r = _gold_consumes(
        str(tmp_path),
        ["gold_a"],
        **common,
        foreign_gold_sources={"gold_b": {"store"}},
        foreign_relationships=[
            {
                "child_table": "b_fact",
                "child_cols": ["product_sk"],
                "parent_table": "product",
                "parent_cols": ["product_sk"],
                "declared_fk": True,
            }
        ],
    )
    assert r.units == {"gold_a": {"product", "store"}}  # only this package's views
    assert r.tables["gold_a"] == [
        {"table": "product", "unit": "product"},
        {"table": "store", "unit": "store"},
    ]


def test_ingredient_chain_reaches_core_through_an_intermediate(tmp_path):
    # An ingredient whose core link is two FK hops away (CMN campaign -> advertiser ->
    # supplier) must still reach core; a one-hop walk returned nothing for it.
    gold_dir = tmp_path / "gold"
    gold_dir.mkdir()
    (gold_dir / "gold_p.sql").write_text(
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${pkg_schema}.gold_p AS\n"
        "SELECT * FROM ${catalog}.${pkg_schema}.campaign c;\n",
        encoding="utf-8",
    )

    def fk(child, parent):
        return {
            "child_table": child,
            "child_cols": [f"{parent}_sk"],
            "parent_table": parent,
            "parent_cols": [f"{parent}_sk"],
            "declared_fk": True,
        }

    r = _gold_consumes(
        str(tmp_path),
        ["gold_p"],
        core_tables={"supplier": "supplier"},
        relationships=[fk("campaign", "advertiser"), fk("advertiser", "supplier"),
                       fk("advertiser", "advertiser")],  # a self-FK must not loop
        known_tables={"campaign", "advertiser", "supplier", "gold_p"},
    )
    assert r.units["gold_p"] == {"supplier"}
    assert r.tables["gold_p"] == [{"table": "supplier", "unit": "supplier"}]


def test_cross_package_gold_view_lineage_in_model():
    # Live-model counterpart: DSWS gold_supplier_media_report reads CMN's campaign_day /
    # campaign / advertiser, which reach product, store and supplier through CMN's FKs.
    # Subset assertion, so a new source does not break it.
    model = build_model()
    unit = next(u for u in model["units"] if u["name"] == "data-sharing-with-suppliers")
    t = next(t for t in unit["tables"] if t["name"] == "gold_supplier_media_report")
    assert {"product", "store", "supplier"} <= {c["unit"] for c in t["consumes_tables"]}
    uc = _use_case(model, "data-sharing-with-suppliers", "Media Measurement")
    assert {"product", "store", "supplier"} <= set(uc["consumes"])
    # The gold-on-gold path: gold_store_operational_risk reads only OTHER packages' gold
    # views (early-risk-detection, balancing-margin-and-volume), so its product/supplier
    # lineage exists only if build_model hands over the foreign gold sources.
    po = next(u for u in model["units"] if u["name"] == "predictive-operations")
    risk = next(t for t in po["tables"] if t["name"] == "gold_store_operational_risk")
    assert {"product", "supplier"} <= {c["unit"] for c in risk["consumes_tables"]}


def test_from_in_a_comment_is_not_a_bare_ref(tmp_path):
    # Prose like "-- ... derived from sales ..." must NOT trip the bare-ref guard
    # (comments are stripped before scanning); the real qualified ref still resolves.
    gold_dir = tmp_path / "gold"
    gold_dir.mkdir()
    (gold_dir / "gold_z.sql").write_text(
        "-- features derived from sales history\n"
        "CREATE OR REFRESH MATERIALIZED VIEW ${catalog}.${pkg_schema}.gold_z AS\n"
        "SELECT * FROM ${catalog}.${transaction_schema}.sales s;\n",
        encoding="utf-8",
    )
    result = _gold_consumes(
        str(tmp_path),
        ["gold_z"],
        core_tables={"sales": "transaction"},
        relationships=[],
        known_tables={"sales", "gold_z"},
    )
    assert result.units["gold_z"] == {"transaction"}


@pytest.mark.writes_repo
def test_write_then_check_is_clean():
    # The regenerated model.json must be byte-stable: --write then --check clean.
    w = subprocess.run([sys.executable, "tools/gen_model_json.py", "--write"], cwd=ROOT)
    assert w.returncode == 0
    c = subprocess.run([sys.executable, "tools/gen_model_json.py", "--check"], cwd=ROOT)
    assert c.returncode == 0


@pytest.mark.writes_repo
def test_orphan_staged_copy_is_flagged(tmp_path):
    """A staged copy under explorer/public/ whose source the model no longer
    references (a renamed/deleted contract or glossary) must be detected as an
    orphan and fail --check (M1 - the explorer/public mirror gets the same
    missing/extra/changed guarantee the ODCS gate has)."""
    model = build_model()
    expected = {os.path.abspath(os.path.join(PUBLIC, rel)) for _, rel in staged_assets(model)}
    # Precondition: the committed tree has no orphans.
    assert staged_orphans(expected) == []

    orphan = Path(PUBLIC) / "canonical-core" / "__orphan_test__" / "glossary.md"
    orphan.parent.mkdir(parents=True, exist_ok=True)
    orphan.write_text("orphaned staged copy\n", encoding="utf-8")
    try:
        assert str(orphan.resolve()) in staged_orphans(expected)  # detected
        r = subprocess.run(
            [sys.executable, "tools/gen_model_json.py", "--check"],
            cwd=ROOT, capture_output=True, text=True,
        )
        assert r.returncode == 1  # --check flags it as stale
        assert "orphan" in (r.stdout + r.stderr).lower()
    finally:
        # Restore the tree by hand (do NOT use --write, which would also rewrite
        # model.json); the pruning path is exercised by the manual --write flow.
        orphan.unlink(missing_ok=True)
        try:
            orphan.parent.rmdir()
        except OSError:
            pass
    # Clean again once the orphan is gone.
    assert staged_orphans(expected) == []


@pytest.mark.writes_repo
def test_write_prunes_an_orphan_staged_copy():
    """--write must PRUNE (os.remove) a staged mirror the model no longer references,
    so a renamed/deleted source cannot leave a served-but-stale copy under
    explorer/public/. The DETECTION side is covered above; this exercises the prune
    side, which is python-only (no JSON drift test reaches it) - round-21 M3."""
    orphan = Path(PUBLIC) / "canonical-core" / "__prune_test__" / "glossary.md"
    orphan.parent.mkdir(parents=True, exist_ok=True)
    orphan.write_text("orphaned staged copy\n", encoding="utf-8")
    try:
        assert orphan.exists()
        # --write regenerates model.json + re-stages from source (byte-identical on an
        # in-sync tree) AND prunes orphans; here it must delete the orphan file.
        r = subprocess.run([sys.executable, "tools/gen_model_json.py", "--write"], cwd=ROOT)
        assert r.returncode == 0
        assert not orphan.exists()  # pruned by os.remove
    finally:
        orphan.unlink(missing_ok=True)  # no-op if pruned; safety if the assert failed
        try:
            orphan.parent.rmdir()  # --write removes the file, not its now-empty dir
        except OSError:
            pass
    # The tree is back in sync (the orphan was the only change --write made).
    r = subprocess.run([sys.executable, "tools/gen_model_json.py", "--check"], cwd=ROOT)
    assert r.returncode == 0
