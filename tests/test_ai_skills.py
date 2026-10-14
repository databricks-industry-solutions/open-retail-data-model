"""The ORDM modeling skill ships in two folders because AI tools read different ones:
Claude Code reads .claude/skills/, OpenAI Codex reads .agents/skills/, GitHub Copilot reads
both (docs/ai-skills.md). The copies must stay identical; edit .agents/skills/ and copy it."""
import re
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

ROOT = Path(__file__).resolve().parents[1]
SKILL = "ordm-data-modeling"


def _folder(base):
    root = ROOT / base / "skills" / SKILL
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()}


def test_modeling_skill_copies_are_identical():
    """Every file, not just SKILL.md: a script or reference added to one copy only would drift."""
    agents, claude = _folder(".agents"), _folder(".claude")
    assert "SKILL.md" in agents
    assert sorted(agents) == sorted(claude), f"copy .agents/skills/{SKILL}/ to .claude/skills/{SKILL}/"
    assert all(agents[f] == claude[f] for f in agents), f"copy .agents/skills/{SKILL}/ to .claude/skills/{SKILL}/"


def test_modeling_skill_follows_the_agent_skills_format():
    """agentskills.io: frontmatter `name` (lowercase letters, digits and hyphens, at most 64
    characters, equal to the folder name) and a non-empty `description` of at most 1024."""
    text = (ROOT / ".agents" / "skills" / SKILL / "SKILL.md").read_text(encoding="utf-8")
    assert text.startswith("---\n"), "SKILL.md starts with YAML frontmatter"
    meta = yaml.safe_load(text.split("---", 2)[1])
    assert meta["name"] == SKILL and re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", meta["name"])
    assert len(meta["name"]) <= 64 and 0 < len(meta["description"]) <= 1024
