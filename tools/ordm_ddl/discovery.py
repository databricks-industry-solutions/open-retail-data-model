"""Find ORDM units (domains under canonical-core/, packages under outcome-packages/)."""
from __future__ import annotations
import os


class UnitDiscovery:
    def __init__(self, repo_root: str | None = None):
        self.repo_root = repo_root or os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", ".."))

    def find(self, include: set[str] | None = None) -> list[str]:
        dirs: list[str] = []
        for base in ("canonical-core", "outcome-packages"):
            root = os.path.join(self.repo_root, base)
            if not os.path.isdir(root):
                continue
            for name in sorted(os.listdir(root)):
                d = os.path.join(root, name)
                if os.path.isdir(d) and (os.path.isdir(os.path.join(d, "tables"))
                                         or os.path.isdir(os.path.join(d, "gold"))):
                    if include is None or name in include:
                        dirs.append(d)
        return dirs
