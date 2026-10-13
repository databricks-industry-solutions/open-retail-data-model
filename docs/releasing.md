# Releasing

How a numbered ORDM release is cut, for example `0.5`. A release is a dated
`CHANGELOG.md` section plus one model version stamped across the repo. It is cut by a
maintainer through a normal pull request.

## Where the version lives

The one source is the [`VERSION`](../VERSION) file at the repo root. Every other copy is a
stamp derived from it:

| Stamp | Example | Written by |
|---|---|---|
| SQL file header | `-- Version: 0.5` (also `-- MAGIC Version:`) | `tools/release.py` |
| Python generator header | `# Version: 0.5` | `tools/release.py` |
| Notebook template title | `-- MAGIC ORDM · Outcome Package · … · Version 0.5` | `tools/release.py` |
| Status line | `> Status: 🟢 Review complete (0.5)` | `tools/gen_status.py` (reads `VERSION`) and `tools/release.py` |

`make check-version` (part of `make check`, and a CI step) fails when any stamp disagrees
with `VERSION`. A new file copies the header of a neighbouring file, so it starts at the
current version.

Only those anchored line patterns are stamps. Prose that mentions a version, such as a
`CHANGELOG.md` release section, "CMN `0.1-beta` → `0.2-beta`" in the versioning policy, or
"out of scope for v0.2-beta", is history and is never rewritten.

## Version numbers

Releases from 0.5 on have two parts and no pre-release label: `0.5`, `0.6`, `1.0`. The
earlier releases were betas (`0.1-beta`, `0.2-beta`). A release candidate, if one is ever
needed, is `0.6-rc.1`. The accepted forms are `MAJOR.MINOR[.PATCH][-alpha|-beta|-rc[.N]]`,
with ASCII digits and no leading zeros, ordered alpha < beta < rc < final; `0.5` and `0.5.0`
are the same version. A release must be newer than the current `VERSION`.

Which part to bump for a schema change is set by the [versioning policy](versioning-policy.md)
§2, and it binds once a package is published. Before publication nothing has adopters, so the
next staging release number is the maintainer's call (0.2-beta was followed by 0.5). A
patch release uses the third part, for example `0.5.1`.

## Cutting a release

1. Branch from `origin/main`, for example `release/0.6`.
2. Check that every merged PR since the last release has a `CHANGELOG.md` entry:

   ```bash
   python tools/release.py gaps
   ```

   It lists squash-merged PRs (subject ending in `(#N)`) that are not linked anywhere under
   `[Unreleased]`. Add the missing entries.
3. Preview, then run the bump:

   ```bash
   python tools/release.py bump 0.6 --dry-run
   make release NEW_VERSION=0.6               # RELEASE_ARGS="--date 2026-11-13" to set the date
   ```

   `make release` runs `tools/release.py bump` and then `make regen`. The bump:
   - refuses if the version is not newer, if any stamp already disagrees with `VERSION`, if
     `[Unreleased]` has no entries, or if `gaps` finds missing entries (`--allow-gaps`
     overrides the last one, for PRs that need no entry);
   - writes `VERSION` and rewrites every stamp, changing only the version token;
   - renames `[Unreleased]` to `## [0.6] — <date>` and opens an empty `[Unreleased]`
     above it with the contributor template comment.

   `make regen` then refreshes the derived copies, such as the explorer glossary mirrors.
4. Add a short summary paragraph under the new release heading, as earlier releases have.
5. Run `pytest -q` and `make check`, then open the release PR against `main`. Use one PR per
   release; it notifies the whole reviewer team.

If the PR merges on a later day, set the heading date to the merge date before merging.

A PR that merges into `main` while the release PR is open needs one of two fixes:
- **It merges first:** rebase the release branch and run
  `python tools/release.py check`. Restamp any new files to the release version, move the
  PR's `[Unreleased]` entry into the release section, and recheck the summary paragraph.
- **The release merges first:** the PR fails the `check-version` CI step until its new files
  carry the new version. Its CHANGELOG entry goes under the fresh `[Unreleased]`.

## After the release PR merges

Tag the merge commit and create the GitHub Release. Do this from an up-to-date `main`. The
tag goes on the commit that last changed `VERSION` (the release PR's merge), even if other PRs
have merged since:

```bash
git switch main && git pull --ff-only
test "$(cat VERSION)" = 0.5                               # the release PR has merged
! git rev-parse -q --verify refs/tags/v0.5                # not tagged yet
git tag -a v0.5 -m "ORDM 0.5" "$(git log -1 --format=%H -- VERSION)"
git push origin v0.5
python tools/release.py notes 0.5 \
  | gh release create v0.5 --title "ORDM 0.5" --notes-file -
```

Tags are annotated and prefixed with `v`. Releases are not marked `--prerelease`; add it only
for an `-rc` candidate. The
release notes are the `CHANGELOG.md` section, so the two never disagree.

## Fixing a stamp by hand

If `make check-version` fails on a single file (for example a new file copied from an old
branch), set that file's stamp to the value in `VERSION`. Never edit `VERSION` to match a
stray stamp; only a release changes it.
