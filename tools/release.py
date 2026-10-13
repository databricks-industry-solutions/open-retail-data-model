#!/usr/bin/env python3
"""Release manager for the ORDM model version.

The model version has ONE source: the VERSION file at the repo root. Every other
place it appears is a *stamp* derived from it:

  - the "-- Version: X" / "-- MAGIC Version: X" / "# Version: X" file headers,
  - the "· Version X" title line of the notebook templates,
  - the "(X)" on every generated "> Status:" line (tools/gen_status.py reads
    VERSION, so a `make regen` keeps those in step on its own).

Only lines matching those anchored stamp patterns are touched. A status line is a stamp
only in the generated "> Status: <label> (<version>)" form; a hand-written one such as
"> Status: done (ADR 0043)" is prose. Narrative mentions
(CHANGELOG release sections, "CMN 0.1-beta -> 0.2-beta", "out of scope for v0.2-beta")
are left alone on purpose.

  python tools/release.py check                 fail if any stamp disagrees with VERSION
  python tools/release.py bump 0.6              rewrite VERSION + every stamp, cut CHANGELOG
  python tools/release.py bump 0.6 -n           dry run: show what would change
  python tools/release.py gaps                  merged PRs since the last release with no
                                                CHANGELOG [Unreleased] entry
  python tools/release.py notes 0.5             print a release's CHANGELOG section (for
                                                `gh release create --notes-file -`)

The release process (who runs what, and the post-merge tag step) is in docs/releasing.md.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
VERSION_FILE = "VERSION"
CHANGELOG = "CHANGELOG.md"

# 0.5, 0.6, 0.6-rc.1, 1.0, 1.0.1, and the earlier betas 0.1-beta and 0.2-beta. Two or three
# numeric parts and an optional alpha/beta/rc pre-release label. Matches the repo's history
# and the two-part pre-1.0 scheme in docs/versioning-policy.md. Numbers are ASCII digits with no
# leading zero (so 0.05 is not a second spelling of 0.5; `\d` would also match non-ASCII
# digits).
_N = r"(?:0|[1-9][0-9]*)"
VERSION_RE = rf"{_N}\.{_N}(?:\.{_N})?(?:-(?:alpha|beta|rc)(?:\.{_N})?)?"
_VERSION_FULL = re.compile(rf"^{VERSION_RE}$")
_VERSION_PARTS = re.compile(
    rf"^({_N})\.({_N})(?:\.({_N}))?(?:-(alpha|beta|rc)(?:\.({_N}))?)?$"
)
_STAGE_RANK = {"alpha": 0, "beta": 1, "rc": 2, None: 3}

# Stamp patterns. Each is anchored to the start of the line, and the version is the
# named group `v`. The token after `v` must end the stamp (end of line, " ·" or ")"),
# so "0.2-beta.1" is never half-rewritten as "0.5-beta.1".
STAMP_PATTERNS = {
    "sql header": re.compile(rf"^-- (?:MAGIC )?Version: (?P<v>{VERSION_RE})(?= ·|\s*$)"),
    "python header": re.compile(rf"^# Version: (?P<v>{VERSION_RE})(?= ·|\s*$)"),
    "notebook title": re.compile(rf"^-- MAGIC ORDM · .* · Version (?P<v>{VERSION_RE})(?=\s*$)"),
    "status line": re.compile(rf"^> Status: [^(\n]*\((?P<v>{VERSION_RE})\)"),
}

# Header-shaped lines whose value is not a valid version are reported by `check`, so a
# typo such as "-- Version: 0.5beta" cannot hide from the strict patterns above.
_LOOSE_PATTERNS = {
    "sql header": re.compile(r"^-- (?:MAGIC )?Version: (?P<v>\S+)"),
    "python header": re.compile(r"^# Version: (?P<v>\S+)"),
    "notebook title": re.compile(r"^-- MAGIC ORDM · .* · Version (?P<v>\S+)\s*$"),
}

# Files never scanned for stamps: CHANGELOG's release headings are history, and the
# VERSION file is the source itself.
_SKIP_FILES = {CHANGELOG, VERSION_FILE}


class ReleaseError(Exception):
    pass


# ---- versions ------------------------------------------------------------------

def parse_version(text: str) -> tuple:
    """Sort key for a version string; raises ReleaseError if it is not one."""
    m = _VERSION_PARTS.match(text)
    if not m or not _VERSION_FULL.match(text):
        raise ReleaseError(
            f"{text!r} is not a version (expected e.g. 0.6, 0.6-rc.1, 1.0, 1.0.1)"
        )
    major, minor, patch, stage, num = m.groups()
    return (int(major), int(minor), int(patch or 0), _STAGE_RANK[stage], int(num or 0))


def read_version(root: Path) -> str:
    path = root / VERSION_FILE
    if not path.is_file():
        raise ReleaseError(f"{VERSION_FILE} not found at {root}")
    version = path.read_text(encoding="utf-8-sig").strip()
    parse_version(version)
    return version


# ---- stamps --------------------------------------------------------------------

def tracked_files(root: Path) -> list[str]:
    """Tracked files plus untracked, not-ignored ones (a new file not yet committed)."""
    out = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root, check=True, capture_output=True,
    ).stdout
    return sorted(p for p in out.decode("utf-8").split("\0") if p and p not in _SKIP_FILES)


def _read_text(path: Path) -> str | None:
    try:
        data = path.read_bytes()
    except (FileNotFoundError, IsADirectoryError):
        return None  # tracked but deleted in the work tree, or a submodule
    if b"\0" in data[:8192]:
        return None  # binary
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def find_stamps(root: Path, files: list[str] | None = None) -> list[tuple[str, int, str, str | None]]:
    """Every stamp in the tracked files: (path, line number, kind, version).

    version is None for a header-shaped line whose value is not a valid version.
    """
    found = []
    for rel in files if files is not None else tracked_files(root):
        text = _read_text(root / rel)
        if text is None:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            for kind, pattern in STAMP_PATTERNS.items():
                m = pattern.match(line)
                if m:
                    found.append((rel, lineno, kind, m.group("v")))
                    break
            else:
                for kind, pattern in _LOOSE_PATTERNS.items():
                    if pattern.match(line):
                        found.append((rel, lineno, kind, None))
                        break
    return found


def plan_stamps(root: Path, old: str, new: str) -> dict[str, tuple[int, bytes]]:
    """New content for every file with a stamp at `old`: {path: (stamps, bytes)}.

    Nothing is written. Bytes outside the matched version token are preserved exactly
    (line endings, trailing text, encoding).
    """
    plan: dict[str, tuple[int, bytes]] = {}
    for rel in tracked_files(root):
        path = root / rel
        text = _read_text(path)
        if text is None:
            continue
        lines = text.splitlines(keepends=True)
        hits = 0
        for i, line in enumerate(lines):
            for pattern in STAMP_PATTERNS.values():
                m = pattern.match(line)
                if m:
                    if m.group("v") == old:
                        lines[i] = line[: m.start("v")] + new + line[m.end("v"):]
                        hits += 1
                    break
        if hits:
            plan[rel] = (hits, "".join(lines).encode("utf-8"))
    return plan


def rewrite_stamps(root: Path, old: str, new: str, *, dry_run: bool) -> dict[str, int]:
    """Replace `old` with `new` in every stamp. Returns {path: stamps changed}."""
    plan = plan_stamps(root, old, new)
    if not dry_run:
        for rel, (_, data) in plan.items():
            (root / rel).write_bytes(data)
    return {rel: hits for rel, (hits, _) in plan.items()}


def _read_changelog(root: Path) -> str:
    # Bytes, not read_text(): keep the file's own line endings on a rewrite.
    return (root / CHANGELOG).read_bytes().decode("utf-8")


def check(root: Path) -> list[str]:
    """Problems that make the repo's version inconsistent (empty list = consistent)."""
    version = read_version(root)
    problems = [
        f"{rel}:{lineno}: {kind} is not a valid version stamp" if v is None
        else f"{rel}:{lineno}: {kind} says {v}, VERSION says {version}"
        for rel, lineno, kind, v in find_stamps(root)
        if v != version
    ]
    changelog = _read_changelog(root)
    if not _UNRELEASED.search(changelog):
        problems.append(f"{CHANGELOG}: no '## [Unreleased]' section")
    released = [m.group(1) for m in _RELEASE_HEADING.finditer(changelog)]
    if released and released[0] != version:
        problems.append(
            f"{CHANGELOG}: newest release section is [{released[0]}], VERSION says {version}"
        )
    return problems


# ---- CHANGELOG -----------------------------------------------------------------

_UNRELEASED = re.compile(r"^## \[Unreleased\][^\n]*\n", re.M)
_RELEASE_HEADING = re.compile(rf"^## \[({VERSION_RE})\]", re.M)
_ANY_H2 = re.compile(r"^## ", re.M)
_LEADING_COMMENT = re.compile(r"\A(\s*<!--.*?-->[ \t]*\n)", re.S)
# GitHub numbers issues and PRs from one sequence, so an /issues/N link names PR N too.
_PR_LINK = re.compile(r"/(?:pull|issues)/([0-9]+)\b")
_TRAILING_COMMENT = re.compile(r"\s*<!--(?:(?!<!--).)*?-->\s*\Z", re.S)


def _unreleased_span(text: str) -> tuple[int, int, int]:
    """(heading start, body start, body end) of the [Unreleased] section."""
    m = _UNRELEASED.search(text)
    if not m:
        raise ReleaseError(f"{CHANGELOG} has no '## [Unreleased]' section")
    nxt = _ANY_H2.search(text, m.end())
    end = nxt.start() if nxt else len(text)
    return m.start(), m.end(), end


def unreleased_body(text: str) -> str:
    _, start, end = _unreleased_span(text)
    return text[start:end]


def cut_changelog(text: str, version: str, date: str) -> str:
    """Rename [Unreleased] to the dated release and open a fresh [Unreleased].

    The contributor template comment that sits right under the [Unreleased] heading
    stays with the new, empty [Unreleased]; the entries move to the release section.
    """
    if re.search(rf"^## \[{re.escape(version)}\]", text, re.M):
        raise ReleaseError(f"{CHANGELOG} already has a [{version}] section")
    head, start, end = _unreleased_span(text)
    body = text[start:end]
    cm = _LEADING_COMMENT.match(body)
    template = cm.group(1).strip("\n") if cm else ""
    entries = body[cm.end():] if cm else body
    if not re.search(r"^\s*[-*] ", entries, re.M):
        raise ReleaseError(f"{CHANGELOG} [Unreleased] has no entries to release")
    fresh = "## [Unreleased]\n\n" + (template + "\n\n" if template else "")
    released = f"## [{version}] — {date}\n\n" + entries.strip("\n") + "\n\n"
    return text[:head] + fresh + released + text[end:]


def release_notes(text: str, version: str) -> str:
    m = re.search(rf"^## \[{re.escape(version)}\][^\n]*\n", text, re.M)
    if not m:
        raise ReleaseError(f"{CHANGELOG} has no [{version}] section")
    nxt = _ANY_H2.search(text, m.end())
    body = text[m.end(): nxt.start() if nxt else len(text)]
    # The oldest release runs to the end of the file, where maintainer comments live.
    while _TRAILING_COMMENT.search(body):
        body = _TRAILING_COMMENT.sub("", body)
    return body.strip("\r\n") + "\n"


# ---- changelog gaps ----------------------------------------------------------------

_SQUASH_PR = re.compile(r"\(#(\d+)\)\s*$")


def _git(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=root, check=True, capture_output=True, text=True
    ).stdout


def changelog_gaps(root: Path) -> list[tuple[int, str]]:
    """Merged PRs since the last release with no link in [Unreleased].

    "Since the last release" means after the commit that added the newest release
    heading to CHANGELOG.md. PR numbers come from the squash-merge subject's trailing
    "(#N)". A PR linked anywhere in [Unreleased] counts as covered.
    """
    text = _read_changelog(root)
    released = [m.group(1) for m in _RELEASE_HEADING.finditer(text)]
    if not released:
        return []
    heading = f"## [{released[0]}]"
    commits = _git(root, "log", "--format=%H", "-S", heading, "--", CHANGELOG).split()
    if not commits:
        raise ReleaseError(f"no commit adds '{heading}' to {CHANGELOG} (shallow clone?)")
    # git log -S lists commits that change how often the heading appears; the oldest is the
    # first add. If a heading were ever reverted and re-added, the window would start early,
    # which reports more gaps, never fewer.
    since = commits[-1]
    covered = {int(n) for n in _PR_LINK.findall(unreleased_body(text))}
    gaps = []
    for line in _git(root, "log", "--format=%s", f"{since}..HEAD").splitlines():
        m = _SQUASH_PR.search(line)
        if m and int(m.group(1)) not in covered:
            gaps.append((int(m.group(1)), line))
    return gaps


# ---- commands ------------------------------------------------------------------

def cmd_check(root: Path, _args) -> int:
    problems = check(root)
    if problems:
        print(f"Version stamps disagree with {VERSION_FILE}:", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        print(
            "Fix: `python tools/release.py bump <version>` rewrites every stamp; for a single "
            "file, set its header to the VERSION value.",
            file=sys.stderr,
        )
        return 1
    stamps = find_stamps(root)
    print(f"OK: VERSION {read_version(root)}; {len(stamps)} stamps in "
          f"{len({s[0] for s in stamps})} files agree.")
    return 0


def cmd_bump(root: Path, args) -> int:
    new = args.version
    current = read_version(root)
    if parse_version(new) <= parse_version(current):
        raise ReleaseError(f"{new} is not newer than the current version {current}")
    problems = check(root)
    if problems:
        raise ReleaseError(
            "the repo is already inconsistent; fix these first (`release.py check`):\n  "
            + "\n  ".join(problems)
        )
    date = args.date or _dt.date.today().isoformat()
    try:
        _dt.date.fromisoformat(date)
    except ValueError:
        raise ReleaseError(f"--date {date!r} is not an ISO date (YYYY-MM-DD)") from None

    if not args.allow_gaps:
        try:
            gaps = changelog_gaps(root)
        except (ReleaseError, subprocess.CalledProcessError) as e:
            raise ReleaseError(f"could not check CHANGELOG coverage: {e}; "
                               "rerun with --allow-gaps to skip") from None
        if gaps:
            listing = "\n  ".join(f"#{n}  {s}" for n, s in gaps)
            raise ReleaseError(
                f"merged PRs with no {CHANGELOG} [Unreleased] entry:\n  {listing}\n"
                "Add entries (or rerun with --allow-gaps if they need none)."
            )

    # Compute every new file first, so a validation failure writes nothing.
    new_changelog = cut_changelog(_read_changelog(root), new, date)
    plan = plan_stamps(root, current, new)
    verb = "Would update" if args.dry_run else "Updating"
    print(f"{verb} {sum(h for h, _ in plan.values())} stamps in {len(plan)} files: "
          f"{current} -> {new}")
    if args.dry_run:
        for rel, (hits, _) in sorted(plan.items()):
            print(f"  {rel} ({hits})")
        print(f"Would write {VERSION_FILE} = {new} and cut {CHANGELOG} [{new}] — {date}")
        return 0
    writes = {rel: data for rel, (_, data) in plan.items()}
    writes[VERSION_FILE] = (new + "\n").encode("utf-8")
    writes[CHANGELOG] = new_changelog.encode("utf-8")
    try:
        for rel, data in writes.items():
            (root / rel).write_bytes(data)
    except OSError as e:
        raise ReleaseError(f"write failed ({e}); undo the partial bump with "
                           "`git checkout -- .` and rerun") from None
    print(f"Wrote {VERSION_FILE} = {new}; cut {CHANGELOG} [{new}] — {date}")
    problems = check(root)
    if problems:
        raise ReleaseError("bump left stamps behind:\n  " + "\n  ".join(problems))
    print("Next: `make regen`, review the diff and the release section, run the tests, "
          "and open the release PR (docs/releasing.md).")
    return 0


def cmd_gaps(root: Path, _args) -> int:
    gaps = changelog_gaps(root)
    for n, subject in gaps:
        print(f"#{n}  {subject}")
    if not gaps:
        print(f"Every merged PR since the last release is linked in {CHANGELOG} [Unreleased].")
    return 1 if gaps else 0


def cmd_notes(root: Path, args) -> int:
    sys.stdout.write(release_notes(_read_changelog(root), args.version))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--root", type=Path, default=REPO_ROOT, help=argparse.SUPPRESS)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check", help="fail if any version stamp disagrees with VERSION")
    b = sub.add_parser("bump", help="set a new version everywhere and cut the CHANGELOG")
    b.add_argument("version", help="the new version, newer than VERSION (e.g. 0.6, 0.6-rc.1, 1.0)")
    b.add_argument("--date", help="release date, YYYY-MM-DD (default: today)")
    b.add_argument("-n", "--dry-run", action="store_true")
    b.add_argument("--allow-gaps", action="store_true",
                   help="release even if merged PRs have no [Unreleased] entry")
    sub.add_parser("gaps", help="merged PRs since the last release missing from [Unreleased] "
                               "(exit 1 if any)")
    n = sub.add_parser("notes", help="print a release's CHANGELOG section")
    n.add_argument("version")
    args = parser.parse_args(argv)
    handler = {"check": cmd_check, "bump": cmd_bump, "gaps": cmd_gaps, "notes": cmd_notes}[args.cmd]
    try:
        return handler(args.root.resolve(), args)
    except ReleaseError as e:
        print(f"release: {e}", file=sys.stderr)
        return 2
    except (OSError, subprocess.CalledProcessError) as e:
        print(f"release: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
