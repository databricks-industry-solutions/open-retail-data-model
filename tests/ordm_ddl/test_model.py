from tools.ordm_ddl.model import Column, Table, Relationship, Check, Unit

def test_table_pk_and_pii_helpers():
    cols = [
        Column(name="profile_sk", sql_type="BIGINT", required=True, comment="Surrogate."),
        Column(name="last_name", sql_type="STRING", required=False, comment="Family name.",
               tags=("dbx_pii_name",)),
    ]
    t = Table(name="profile", schema_token="customer_schema", columns=cols,
              primary_key=("profile_sk",), role="master", comment="Person master.", layer="silver")
    assert t.pk_columns == ("profile_sk",)
    assert t.column("last_name").is_pii is True
    assert t.column("profile_sk").is_pii is False

def test_unit_groups_tables_rels_checks():
    u = Unit(name="customer", kind="core", tables=[], relationships=[], checks=[])
    assert u.kind == "core" and u.is_core is True
