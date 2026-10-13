from tools.ordm_ddl.discovery import UnitDiscovery
from tools.ordm_ddl.parser import DdlParser

def test_discovers_customer_and_parses_unit():
    units = {u.rsplit("/", 1)[-1]: u for u in UnitDiscovery().find({"customer"})}
    assert "customer" in units
    unit = DdlParser().parse_unit(units["customer"])
    assert unit.name == "customer" and unit.kind == "core" and unit.is_core is True
    names = {t.name for t in unit.tables}
    assert names >= {"profile", "address", "contact", "consent", "account"}
    assert any(r.parent_table == "profile" for r in unit.relationships)
    assert all(t.layer == "silver" for t in unit.tables)  # core domain = all silver

def test_find_filters_and_lists_all():
    all_units = UnitDiscovery().find(None)          # None => every domain + package
    assert len(all_units) >= 12                      # at least the 12 core domains
    just_two = {u.rsplit("/",1)[-1] for u in UnitDiscovery().find({"customer", "product"})}
    assert just_two == {"customer", "product"}
