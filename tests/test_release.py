"""Guards for tools/release.py, the model-version release manager.

VERSION is the single source of the model version; every "-- Version:" / "# Version:"
header, notebook title and "> Status:" line is a stamp of it. These tests lock which
lines count as stamps (and which prose must never be rewritten), the byte-preserving
rewrite, the CHANGELOG cut, the merged-PR gap check, and that the committed repo agrees
with its own VERSION file.
"""
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import gen_status, release

URL = "https://github.com/databricks-industry-solutions/open-retail-data-model/pull/"

CHANGELOG = f"""# Changelog

Intro.

## [Unreleased]

<!-- Add new entries here, under the matching change-area heading. -->

### Outcome packages

- New thing ([#12]({URL}12))

## [0.2-beta] — 2026-10-07

Summary of 0.2-beta.

### Canonical core & data model

- Old thing ([#10]({URL}10))

## [0.1-beta] — 2026-09-03

- First
"""


def _git(root, *args):
    subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)


def _commit(root, subject):
    _git(root, "add", "-A")
    _git(root, "-c", "user.name=t", "-c", "user.email=t@example.com",
         "commit", "-q", "--allow-empty", "-m", subject)


@pytest.fixture
def repo(tmp_path):
    """A tiny git repo at 0.2-beta: one stamp of each kind plus history prose."""
    _git(tmp_path, "init", "-q")
    files = {
        "VERSION": "0.2-beta\n",
        "core/tables/t.sql": "-- ORDM canonical core\n-- Version: 0.2-beta · Generated: 2026-07-06\nCREATE TABLE t (a INT);\n",
        "core/crlf.sql": "-- Version: 0.2-beta\r\nSELECT 1;\r\n",
        "core/nb.sql": "-- Databricks notebook source\n-- MAGIC ORDM · Outcome Package · X · Version 0.2-beta\n-- MAGIC Version: 0.2-beta\n",
        "gen/g.py": "# ORDM generator\n# Version: 0.2-beta\nprint(1)\n",
        "core/README.md": "# Core\n\n> Status: 🟢 Review complete (0.2-beta) · Last reviewed: 2026-07-14\n",
        "docs/policy.md": "CMN `0.1-beta` → `0.2-beta`, in the 0.2-beta release.\n"
                          "Out of scope for v0.2-beta.\n-- Version grain is the INSTANT.\n",
        "CHANGELOG.md": CHANGELOG,
    }
    for rel, text in files.items():
        p = tmp_path / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(text.encode("utf-8"))
    _commit(tmp_path, "release 0.2-beta (#9)")
    _commit(tmp_path, "add new thing (#12)")
    return tmp_path


# ---- versions ------------------------------------------------------------------

@pytest.mark.parametrize("lo, hi", [
    ("0.2-beta", "0.5-beta"),
    ("0.5-alpha", "0.5-beta"),
    ("0.5-beta", "0.5-rc.1"),
    ("0.5-rc.1", "0.5-rc.2"),
    ("0.5-rc.2", "0.5"),
    ("0.5", "0.5.1"),
    ("0.9", "1.0-beta"),
    ("0.5", "0.10-beta"),
])
def test_versions_order(lo, hi):
    assert release.parse_version(lo) < release.parse_version(hi)


def test_two_and_three_part_finals_compare_equal():
    assert release.parse_version("0.5") == release.parse_version("0.5.0")


@pytest.mark.parametrize("bad", ["0.5beta", "v0.5-beta", "0.5-gamma", "5", "0.5-beta-1", "", "0.5 "])
def test_invalid_versions_are_rejected(bad):
    with pytest.raises(release.ReleaseError):
        release.parse_version(bad)


# ---- stamps --------------------------------------------------------------------

def test_finds_every_stamp_kind_and_no_prose(repo):
    stamps = {(rel, kind, v) for rel, _, kind, v in release.find_stamps(repo)}
    assert stamps == {
        ("core/tables/t.sql", "sql header", "0.2-beta"),
        ("core/crlf.sql", "sql header", "0.2-beta"),
        ("core/nb.sql", "notebook title", "0.2-beta"),
        ("core/nb.sql", "sql header", "0.2-beta"),
        ("gen/g.py", "python header", "0.2-beta"),
        ("core/README.md", "status line", "0.2-beta"),
    }


def test_check_passes_on_a_consistent_repo(repo):
    assert release.check(repo) == []


def test_check_reports_a_stale_stamp(repo):
    p = repo / "gen/g.py"
    p.write_text(p.read_text().replace("0.2-beta", "0.1-beta"))
    assert release.check(repo) == ["gen/g.py:2: python header says 0.1-beta, VERSION says 0.2-beta"]


def test_check_reports_a_malformed_header(repo):
    p = repo / "core/tables/t.sql"
    p.write_text(p.read_text().replace("0.2-beta", "0.2beta"))
    assert release.check(repo) == ["core/tables/t.sql:2: sql header is not a valid version stamp"]


def test_check_reports_changelog_release_ahead_of_version(repo):
    (repo / "VERSION").write_text("0.1-beta\n")
    problems = release.check(repo)
    assert any("newest release section is [0.2-beta]" in p for p in problems)


def test_a_longer_version_token_is_not_half_rewritten(repo):
    p = repo / "core/tables/t.sql"
    p.write_text("-- Version: 0.2-beta.1\n")
    assert release.rewrite_stamps(repo, "0.2-beta", "0.5", dry_run=False).get("core/tables/t.sql") is None
    assert p.read_text() == "-- Version: 0.2-beta.1\n"


def test_rewrite_preserves_every_other_byte(repo):
    changed = release.rewrite_stamps(repo, "0.2-beta", "0.5", dry_run=False)
    assert changed == {"core/README.md": 1, "core/crlf.sql": 1, "core/nb.sql": 2,
                       "core/tables/t.sql": 1, "gen/g.py": 1}
    assert (repo / "core/crlf.sql").read_bytes() == b"-- Version: 0.5\r\nSELECT 1;\r\n"
    assert (repo / "core/tables/t.sql").read_text() == (
        "-- ORDM canonical core\n-- Version: 0.5 · Generated: 2026-07-06\nCREATE TABLE t (a INT);\n")
    assert (repo / "core/README.md").read_text() == (
        "# Core\n\n> Status: 🟢 Review complete (0.5) · Last reviewed: 2026-07-14\n")
    assert "0.2-beta" in (repo / "docs/policy.md").read_text()  # history untouched


def test_dry_run_writes_nothing(repo):
    before = {p: p.read_bytes() for p in repo.rglob("*") if p.is_file() and ".git" not in p.parts}
    assert release.main(["--root", str(repo), "bump", "0.5", "--dry-run"]) == 0
    after = {p: p.read_bytes() for p in before}
    assert before == after


# ---- CHANGELOG -----------------------------------------------------------------

def test_cut_moves_entries_and_keeps_the_template_comment():
    out = release.cut_changelog(CHANGELOG, "0.5", "2026-10-13")
    assert out.count("## [Unreleased]") == 1
    unreleased = release.unreleased_body(out)
    assert unreleased.strip() == "<!-- Add new entries here, under the matching change-area heading. -->"
    notes = release.release_notes(out, "0.5")
    assert notes == f"### Outcome packages\n\n- New thing ([#12]({URL}12))\n"
    assert out.index("## [0.5] — 2026-10-13") < out.index("## [0.2-beta] — 2026-10-07")
    assert release.release_notes(out, "0.2-beta") == release.release_notes(CHANGELOG, "0.2-beta")


def test_cut_refuses_an_empty_unreleased():
    empty = release.cut_changelog(CHANGELOG, "0.5", "2026-10-13")
    with pytest.raises(release.ReleaseError, match="no entries"):
        release.cut_changelog(empty, "0.6-beta", "2026-10-14")


def test_cut_refuses_an_existing_version():
    with pytest.raises(release.ReleaseError, match="already has"):
        release.cut_changelog(CHANGELOG, "0.2-beta", "2026-10-13")


def test_notes_for_an_unknown_version_fail():
    with pytest.raises(release.ReleaseError):
        release.release_notes(CHANGELOG, "9.9")


# ---- gaps + bump end to end ------------------------------------------------------

def test_gaps_lists_merged_prs_missing_from_unreleased(repo):
    assert release.changelog_gaps(repo) == []
    _commit(repo, "fix something (#13)")
    assert release.changelog_gaps(repo) == [(13, "fix something (#13)")]


def test_bump_refuses_gaps_unless_allowed(repo, capsys):
    _commit(repo, "fix something (#13)")
    assert release.main(["--root", str(repo), "bump", "0.5"]) == 2
    assert "#13" in capsys.readouterr().err
    assert (repo / "VERSION").read_text() == "0.2-beta\n"
    assert release.main(["--root", str(repo), "bump", "0.5", "--allow-gaps",
                         "--date", "2026-10-13"]) == 0


@pytest.mark.parametrize("version", ["0.2-beta", "0.1-beta", "nope"])
def test_bump_refuses_a_version_that_is_not_newer(repo, version):
    assert release.main(["--root", str(repo), "bump", version]) == 2
    assert (repo / "VERSION").read_text() == "0.2-beta\n"


def test_bump_refuses_an_inconsistent_repo(repo):
    p = repo / "gen/g.py"
    p.write_text(p.read_text().replace("0.2-beta", "0.1-beta"))
    assert release.main(["--root", str(repo), "bump", "0.5"]) == 2
    assert (repo / "VERSION").read_text() == "0.2-beta\n"


def test_bump_end_to_end(repo):
    assert release.main(["--root", str(repo), "bump", "0.5", "--date", "2026-10-13"]) == 0
    assert (repo / "VERSION").read_text() == "0.5\n"
    assert release.check(repo) == []
    changelog = (repo / "CHANGELOG.md").read_text()
    assert "## [0.5] — 2026-10-13" in changelog
    assert release.unreleased_body(changelog).strip().startswith("<!--")
    assert {v for *_, v in release.find_stamps(repo)} == {"0.5"}
    # A second bump needs new [Unreleased] entries first.
    assert release.main(["--root", str(repo), "bump", "0.6-beta", "--allow-gaps"]) == 2


def test_bump_rejects_a_bad_date(repo):
    assert release.main(["--root", str(repo), "bump", "0.5", "--date", "13/10/2026"]) == 2
    assert (repo / "VERSION").read_text() == "0.2-beta\n"


# ---- the committed repo --------------------------------------------------------------

def test_committed_repo_agrees_with_its_version_file():
    assert release.check(ROOT) == []


def test_gen_status_reads_the_version_file():
    assert gen_status.MODEL_VERSION == (ROOT / "VERSION").read_text().strip()


# ---- edge cases ------------------------------------------------------------------

@pytest.mark.parametrize("bad", ["0.05", "00.5", "0.5-rc.01", "٠.٥", "0.５"])
def test_leading_zeros_and_non_ascii_digits_are_rejected(bad):
    with pytest.raises(release.ReleaseError):
        release.parse_version(bad)


def test_version_file_with_a_bom_reads_cleanly(repo):
    (repo / "VERSION").write_bytes(b"\xef\xbb\xbf0.2-beta\n")
    assert release.read_version(repo) == "0.2-beta"


def test_cut_without_a_template_comment():
    text = "# C\n\n## [Unreleased]\n\n- New ([#3](x/pull/3))\n\n## [0.1] — 2026-01-01\n\n- Old\n"
    out = release.cut_changelog(text, "0.2", "2026-02-01")
    assert out == ("# C\n\n## [Unreleased]\n\n## [0.2] — 2026-02-01\n\n- New ([#3](x/pull/3))\n\n"
                   "## [0.1] — 2026-01-01\n\n- Old\n")


def test_notes_for_the_oldest_release_drop_the_trailing_maintainer_comment():
    text = CHANGELOG + "\n<!-- Releases: run `make release`. -->\n"
    assert release.release_notes(text, "0.1-beta") == "- First\n"
    assert "Releases:" not in release.release_notes(release._read_changelog(ROOT), "0.1-beta")


def test_an_untracked_new_file_is_checked_and_bumped(repo):
    (repo / "core/new.sql").write_text("-- Version: 0.1-beta\n")
    assert release.check(repo) == ["core/new.sql:1: sql header says 0.1-beta, VERSION says 0.2-beta"]
    (repo / "core/new.sql").write_text("-- Version: 0.2-beta\n")
    assert "core/new.sql" in release.rewrite_stamps(repo, "0.2-beta", "0.5", dry_run=True)


def test_an_issue_link_covers_its_number_in_gaps(repo):
    p = repo / "CHANGELOG.md"
    p.write_text(p.read_text().replace(
        "- New thing", "- Sign-off ([#13](https://github.com/o/r/issues/13))\n- New thing"))
    _commit(repo, "sign off (#13)")
    assert release.changelog_gaps(repo) == []


def test_a_missing_changelog_is_a_clean_error(repo, capsys):
    (repo / "CHANGELOG.md").unlink()
    assert release.main(["--root", str(repo), "check"]) == 2
    assert "CHANGELOG.md" in capsys.readouterr().err
