import pytest
from tools.ordm_ddl.emitters.base import Emitter
from tools.ordm_ddl.model import Unit

def test_emitter_is_abstract():
    with pytest.raises(TypeError):
        Emitter()

def test_concrete_subclass_emits():
    class Dummy(Emitter):
        def emit(self, unit, **opts): return unit.name
    u = Unit(name="x", kind="core", tables=[], relationships=[], checks=[])
    assert Dummy().emit(u) == "x"
