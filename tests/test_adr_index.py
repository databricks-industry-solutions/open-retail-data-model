"""governance/decisions/README.md indexes every ADR file exactly once."""
import re
from pathlib import Path

DECISIONS = Path(__file__).resolve().parents[1] / "governance" / "decisions"


def test_adr_index_lists_every_decision_file():
    index = (DECISIONS / "README.md").read_text()
    linked = re.findall(r"^\| \[\d{4}\]\(([^)]+)\) \|", index, re.M)
    files = sorted(p.name for p in DECISIONS.glob("0*.md"))
    assert sorted(linked) == files, (
        "add a row for each new ADR to governance/decisions/README.md (missing: "
        f"{sorted(set(files) - set(linked))}, stale: {sorted(set(linked) - set(files))})")
    assert len(linked) == len(set(linked))



def test_adr_index_status_matches_each_record():
    """The Status column carries the first word of each record's **Status:** line, so a record
    that changes status (as 0028 did) cannot leave the index stale."""
    index = (DECISIONS / "README.md").read_text()
    shown = dict(re.findall(r"^\| \[\d{4}\]\(([^)]+)\) \| [^|]* \| ([A-Za-z]+) \|$", index, re.M))
    for p in sorted(DECISIONS.glob("0*.md")):
        m = re.search(r"\*\*Status:?\*\*:?\s*([A-Za-z]+)", p.read_text())
        assert m, p.name
        assert shown[p.name] == m.group(1).capitalize(), p.name
