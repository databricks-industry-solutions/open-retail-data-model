import json
import pytest
from tools.ordm_ddl.discovery import UnitDiscovery
from tools.ordm_ddl.model import Column, Table, Unit
from tools.ordm_ddl.parser import DdlParser
from tools.ordm_ddl.emitters.json_model import SOURCE_TREE_URL, JsonModelEmitter

def _customer():
    d = {u.rsplit("/",1)[-1]: u for u in UnitDiscovery().find({"customer"})}["customer"]
    return DdlParser().parse_unit(d)

def _unit(name):
    d = {u.rsplit("/",1)[-1]: u for u in UnitDiscovery().find({name})}[name]
    return DdlParser().parse_unit(d)

def test_unit_json_shape():
    obj = JsonModelEmitter().unit_dict(_customer())
    assert obj["name"] == "customer" and obj["kind"] == "core"
    prof = next(t for t in obj["tables"] if t["name"] == "profile")
    assert prof["layer"] == "silver"
    cols = {c["name"]: c for c in prof["columns"]}
    assert cols["profile_sk"]["pk"] is True
    assert cols["last_name"]["pii"] is True
    assert isinstance(cols["customer_status"]["enum_values"], list)
    assert obj["glossary_path"].endswith("customer/glossary.md")
    # The explorer's GitHub link: the unit's folder in the source repo (absolute https).
    assert SOURCE_TREE_URL.startswith("https://github.com/")
    assert obj["source_url"] == f"{SOURCE_TREE_URL}/canonical-core/customer"
    assert any(r["parent_table"] == "profile" for r in obj["relationships"])

def test_emit_is_valid_json_and_deterministic():
    u = _customer()
    s = JsonModelEmitter().emit(u)
    json.loads(s)
    assert JsonModelEmitter().emit(u) == s


def test_table_comment_is_emitted():
    # Post-#53 tooltip feature: the emitted table dict must carry the table-level
    # COMMENT so the explorer can show it on hover (self-contained fixture).
    unit = Unit(
        name="u", kind="core", relationships=[], checks=[],
        tables=[Table(
            name="t", schema_token="s",
            comment="A widget table.",
            columns=[Column(name="t_sk", sql_type="BIGINT", comment="Surrogate.")],
        )],
    )
    obj = JsonModelEmitter().unit_dict(unit)
    tbl = obj["tables"][0]
    assert tbl["comment"] == "A widget table."
    assert tbl["columns"][0]["comment"] == "Surrogate."


def test_use_cases_surface_from_manifest():
    # A package's use-cases.yaml planning tier must surface as `use_cases` in the
    # emitted model, in file order, names + status only (no owners).
    obj = JsonModelEmitter().unit_dict(_unit("early-risk-detection"))
    ucs = obj["use_cases"]
    assert [u["name"] for u in ucs] == [
        "Real Time Disruption Detection",
        "Supplier Score & Monitoring",
        "Procurement Risk Detection",
    ]
    assert all(u["status"] == "done" for u in ucs)
    # each entry has {name, status, tables} and optionally foreign_tables; owners are never emitted
    for u in ucs:
        assert {"name", "status", "tables"}.issubset(set(u.keys()))
        if "foreign_tables" in u:
            assert isinstance(u["foreign_tables"], list)


def test_use_cases_empty_when_absent():
    # Core domains carry no use-cases.yaml, so the field is an empty list (never
    # missing) — a stable shape the explorer can rely on.
    obj = JsonModelEmitter().unit_dict(_customer())
    assert obj["use_cases"] == []


def test_use_cases_absent_dir(tmp_path):
    # A unit whose dir has no use-cases.yaml emits an empty list rather than raising.
    unit = Unit(
        name="u", kind="outcome", relationships=[], checks=[], tables=[],
        dir=str(tmp_path),
    )
    assert JsonModelEmitter().unit_dict(unit)["use_cases"] == []


def test_use_cases_bad_status_fails_loud(tmp_path):
    # An unknown status must fail loud (no silent drop) so the drift gate names it.
    (tmp_path / "use-cases.yaml").write_text(
        "use_cases:\n  - name: X\n    status: bogus\n", encoding="utf-8"
    )
    unit = Unit(
        name="u", kind="outcome", relationships=[], checks=[], tables=[],
        dir=str(tmp_path),
    )
    with pytest.raises(ValueError, match="status"):
        JsonModelEmitter().unit_dict(unit)


def _gold_table(name):
    return Table(
        name=name, schema_token="s", layer="gold",
        columns=[Column(name=f"{name}_sk", sql_type="BIGINT")],
    )


def test_use_case_tables_surface(tmp_path):
    # An optional per-use-case `tables:` list must surface on the use case,
    # validated against the unit's own gold tables.
    (tmp_path / "use-cases.yaml").write_text(
        "use_cases:\n"
        "  - name: Pricing\n"
        "    status: in-progress\n"
        "    tables: [gold_price_actuals]\n"
        "  - name: NoTables\n"
        "    status: planned\n",
        encoding="utf-8",
    )
    unit = Unit(
        name="u", kind="outcome", relationships=[], checks=[],
        tables=[_gold_table("gold_price_actuals"), _gold_table("gold_other")],
        dir=str(tmp_path),
    )
    ucs = JsonModelEmitter().unit_dict(unit)["use_cases"]
    by_name = {u["name"]: u for u in ucs}
    assert by_name["Pricing"]["tables"] == ["gold_price_actuals"]
    # A use case with no `tables:` key gets an empty list (stable shape).
    assert by_name["NoTables"]["tables"] == []


def test_use_case_bad_table_fails_loud(tmp_path):
    # A typo / renamed table in `tables:` must fail loud, naming the file, use
    # case, and bad table (no silent drop) so the drift gate catches it.
    (tmp_path / "use-cases.yaml").write_text(
        "use_cases:\n"
        "  - name: Pricing\n"
        "    status: in-progress\n"
        "    tables: [gold_typo_here]\n",
        encoding="utf-8",
    )
    unit = Unit(
        name="u", kind="outcome", relationships=[], checks=[],
        tables=[_gold_table("gold_price_actuals")],
        dir=str(tmp_path),
    )
    with pytest.raises(ValueError, match="gold_typo_here"):
        JsonModelEmitter().unit_dict(unit)


def test_cross_package_table_reference(tmp_path):
    # A use case can reference a gold table in another package using "package.table" syntax.
    (tmp_path / "use-cases.yaml").write_text(
        "use_cases:\n"
        "  - name: CLV\n"
        "    status: done\n"
        "    tables:\n"
        "      - other-pkg.gold_customer_ltv\n"
        "      - gold_local_table\n",
        encoding="utf-8",
    )
    unit = Unit(
        name="u", kind="outcome", relationships=[], checks=[],
        tables=[_gold_table("gold_local_table")],
        dir=str(tmp_path),
    )
    jm = JsonModelEmitter()
    # Populate all_units with the referenced package
    jm.all_units = {
        "other-pkg": frozenset(["gold_customer_ltv", "other_gold_view"]),
        "u": frozenset(["gold_local_table"]),
    }
    ucs = jm.unit_dict(unit)["use_cases"]
    by_name = {u["name"]: u for u in ucs}
    clv = by_name["CLV"]
    # Local tables go in tables list, foreign tables in foreign_tables list
    assert clv["tables"] == ["gold_local_table"]
    assert clv["foreign_tables"] == [{"unit": "other-pkg", "table": "gold_customer_ltv"}]


def test_cross_package_reference_unknown_package_fails(tmp_path):
    # A reference to a non-existent package must fail loud.
    (tmp_path / "use-cases.yaml").write_text(
        "use_cases:\n"
        "  - name: CLV\n"
        "    status: done\n"
        "    tables: [unknown-pkg.gold_table]\n",
        encoding="utf-8",
    )
    unit = Unit(
        name="u", kind="outcome", relationships=[], checks=[],
        tables=[],
        dir=str(tmp_path),
    )
    jm = JsonModelEmitter()
    jm.all_units = {"u": frozenset()}
    with pytest.raises(ValueError, match="unknown-pkg.*not a known package"):
        jm.unit_dict(unit)


def test_cross_package_reference_unknown_table_fails(tmp_path):
    # A reference to a non-existent table in a known package must fail loud.
    (tmp_path / "use-cases.yaml").write_text(
        "use_cases:\n"
        "  - name: CLV\n"
        "    status: done\n"
        "    tables: [other-pkg.gold_typo]\n",
        encoding="utf-8",
    )
    unit = Unit(
        name="u", kind="outcome", relationships=[], checks=[],
        tables=[],
        dir=str(tmp_path),
    )
    jm = JsonModelEmitter()
    jm.all_units = {
        "other-pkg": frozenset(["gold_customer_ltv"]),
        "u": frozenset(),
    }
    with pytest.raises(ValueError, match="gold_typo.*does not exist"):
        jm.unit_dict(unit)


def test_cross_package_reference_to_own_package_fails(tmp_path):
    # A qualified reference to the package's OWN gold view is rejected (ADR 0045): the
    # bare name is the one spelling, so a view is never both local and "foreign".
    pkg = tmp_path / "unified-customer-view"
    pkg.mkdir()
    (pkg / "use-cases.yaml").write_text(
        "use_cases:\n"
        "  - name: CDP\n"
        "    status: done\n"
        "    tables: [unified-customer-view.gold_x]\n",
        encoding="utf-8",
    )
    unit = Unit(name="unified-customer-view", kind="outcome", relationships=[], checks=[], tables=[], dir=str(pkg))
    jm = JsonModelEmitter()
    jm.all_units = {"unified-customer-view": frozenset(["gold_x"])}
    with pytest.raises(ValueError, match="OWN package; use the bare name 'gold_x'"):
        jm.unit_dict(unit)


def test_cross_package_reference_to_core_domain_fails(tmp_path):
    # Core domains have no gold views, so a qualified reference into one fails loud.
    (tmp_path / "use-cases.yaml").write_text(
        "use_cases:\n"
        "  - name: CLV\n"
        "    status: done\n"
        "    tables: [customer.profile]\n",
        encoding="utf-8",
    )
    unit = Unit(name="u", kind="outcome", relationships=[], checks=[], tables=[], dir=str(tmp_path))
    jm = JsonModelEmitter()
    jm.all_units = {"customer": frozenset(), "u": frozenset()}
    with pytest.raises(ValueError, match="profile.*does not exist"):
        jm.unit_dict(unit)
