from __future__ import annotations
from abc import ABC, abstractmethod
from ..model import Unit

class Emitter(ABC):
    """Turns a parsed Unit into a serialized artifact (a string)."""
    @abstractmethod
    def emit(self, unit: Unit, **opts) -> str: ...
