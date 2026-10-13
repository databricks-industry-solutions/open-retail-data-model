"""Advisory repo-state guards for the generated README status surfaces.

These read the actual STATUS.md / README, so they belong in the ADVISORY
standards-conformance suite (not the blocking `test` job) — matching where the
conformance-matrix sync test lives, so a stale generated surface reports without
asymmetrically hard-blocking merge. The pure-unit gen_status tests stay in
tests/test_gen_status.py.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import gen_status


def test_real_status_and_layout_agree():
    status = gen_status.parse_status(gen_status.STATUS_PATH.read_text())
    assert gen_status.validate_layout(status) == [], (
        "STATUS.md and gen_status.LAYOUT disagree — add the new row to both"
    )


def test_committed_readme_is_in_sync():
    # The README's generated blocks must match STATUS.md — same gate the
    # standards-conformance job runs via `python tools/gen_status.py --check`.
    assert gen_status.main(["--check"]) == 0
