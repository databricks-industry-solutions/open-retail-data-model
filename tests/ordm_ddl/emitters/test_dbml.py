from tools.ordm_ddl.discovery import UnitDiscovery
from tools.ordm_ddl.parser import DdlParser
from tools.ordm_ddl.emitters.dbml import DbmlEmitter


def _customer():
    d = {u.rsplit("/", 1)[-1]: u for u in UnitDiscovery().find({"customer"})}["customer"]
    return DdlParser().parse_unit(d)


def test_dbml_has_tables_pk_and_ref():
    out = DbmlEmitter().emit(_customer())
    assert "Table profile {" in out
    assert "[pk" in out                                  # a primary-key marker
    assert "profile_sk" in out
    assert "Ref:" in out                                 # at least one FK relationship
    assert "TableGroup" in out                           # subject-area grouping
    assert out.startswith("// GENERATED")                # do-not-edit banner


def test_dbml_is_deterministic():
    u = _customer()
    assert DbmlEmitter().emit(u) == DbmlEmitter().emit(u)


def test_dbml_is_a_subclass_of_emitter():
    from tools.ordm_ddl.emitters.base import Emitter
    assert issubclass(DbmlEmitter, Emitter)
