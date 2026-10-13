from tools.ordm_ddl.discovery import UnitDiscovery
from tools.ordm_ddl.parser import DdlParser
from tools.ordm_ddl.emitters.mermaid import MermaidEmitter


def _unit(name):
    d = {u.rsplit("/", 1)[-1]: u for u in UnitDiscovery().find({name})}[name]
    return DdlParser().parse_unit(d)


def test_core_unit_is_themed_erdiagram():
    out = MermaidEmitter().emit(_unit("customer"), theme="light")
    assert out.startswith('%%{init: {"theme":"default"}}%%')
    assert "erDiagram" in out
    assert "profile {" in out and " PK" in out          # entity block + a PK marker
    assert out.rstrip().endswith("```") is False        # emitter returns raw mermaid source, no fences


def test_core_dark_theme_switches_init():
    out = MermaidEmitter().emit(_unit("customer"), theme="dark")
    assert '"theme":"dark"' in out and "erDiagram" in out


def test_outcome_unit_is_flowchart_with_classdefs():
    out = MermaidEmitter().emit(_unit("early-risk-detection"), theme="light")
    assert "flowchart" in out
    assert "classDef core" in out and "classDef gold" in out
    assert ":::gold" in out                              # at least one gold node (a gold/ view)


def test_deterministic():
    u = _unit("customer")
    assert MermaidEmitter().emit(u, theme="dark") == MermaidEmitter().emit(u, theme="dark")


def test_is_emitter_subclass():
    from tools.ordm_ddl.emitters.base import Emitter
    assert issubclass(MermaidEmitter, Emitter)
