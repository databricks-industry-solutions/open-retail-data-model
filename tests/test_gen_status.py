"""Guards for tools/gen_status.py — the README status surfaces are generated.

STATUS.md is the hand-maintained source of truth; the README count badge + status
tables are derived from it so they cannot drift. These tests lock the parser, the
layout↔STATUS.md consistency guard, and the fact that the committed README is in
sync (so a stale README fails CI, exactly like the conformance matrix).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import gen_status

# Status lines carry the model version; build fixtures from it so a release bump
# (tools/release.py) needs no test edits.
V = gen_status.MODEL_VERSION


def test_parse_status_reads_emoji_per_key():
    text = (
        "| Domain | Status | Working on it | Branch |\n"
        "|---|---|---|---|\n"
        "| customer | 🟢 Review complete | — | — |\n"
        "| calendar | 🟡 In progress | — | — |\n"
    )
    parsed = gen_status.parse_status(text)
    assert parsed == {"customer": "🟢", "calendar": "🟡"}


def test_render_badge_counts_done_core_domains():
    status = {k: "🟢" for k, _ in gen_status.CORE_LAYOUT}
    status["calendar"] = "🟡"
    badge = gen_status.render_badge(status)
    # one domain not done out of len(CORE_LAYOUT); the count is URL-encoded (e.g. 13%2F14).
    n = len(gen_status.CORE_LAYOUT)
    assert f"{n - 1}%2F{n}" in badge
    assert badge.endswith("(STATUS.md)")


def test_render_badge_counts_published_as_done():
    status = {k: "🟢" for k, _ in gen_status.CORE_LAYOUT}
    status["customer"] = "✅"  # published still counts toward the "done" total
    n = len(gen_status.CORE_LAYOUT)
    assert f"{n}%2F{n}" in gen_status.render_badge(status)


def test_nearing_complete_does_not_count_as_done():
    # 🔵 Nearing complete is BELOW 🟢 on the ladder — it must NOT be counted in the
    # review-complete badge. This guards the whole point of the tier: a future edit that
    # accidentally added 🔵 to DONE_EMOJI would be caught here.
    n = len(gen_status.CORE_LAYOUT)
    status = {k: "🟢" for k, _ in gen_status.CORE_LAYOUT}
    status["calendar"] = "🔵"  # one domain nearing-complete, not yet review-complete
    assert f"{n - 1}%2F{n}" in gen_status.render_badge(status)
    assert "🔵" not in gen_status.DONE_EMOJI


def test_core_table_has_a_row_per_layout_domain_with_links():
    status = {k: "🟢" for k, _ in gen_status.CORE_LAYOUT}
    table = gen_status.render_core_table(status, meta={})
    for key, name in gen_status.CORE_LAYOUT:
        assert f"[{name}](canonical-core/{key}/)" in table


def test_core_table_is_a_model_index_with_grain_and_tables():
    status = {k: "🟢" for k, _ in gen_status.CORE_LAYOUT}
    table = gen_status.render_core_table(status, meta={"customer": ("master", 5)})
    assert "| Domain | Grain | Tables | Status |" in table
    assert "| [Customer](canonical-core/customer/) | master | 5 | 🟢 |" in table


def test_domain_meta_grain_is_mode_with_master_tiebreak():
    meta = gen_status.domain_meta()  # reads the committed model.json
    # grain only (not the table COUNT) — the count is live data that changes when a domain
    # gains/loses a table; the mode+tiebreak logic under test does not. Pinning 8 here would
    # break on a routine customer-table change (the mutable-data-pin anti-pattern).
    assert meta["customer"][0] == "master"
    assert meta["customer"][1] >= 1                    # some tables present, exact count is live
    assert meta["calendar"][0] == "reference"
    assert meta["logistics"][0] == "transactional"   # 3 transactional outweigh 1 master
    assert meta["product"][0] == "master"             # 1 master + 1 reference -> master tiebreak


def test_outcome_tables_keep_the_editorial_annotation():
    status = {}
    tables = gen_status.render_outcome_tables(status)
    assert "control tower + metric views" in tables
    assert "**Collaborative Supply Chain**" in tables
    # A key with no STATUS row defaults to ⚪ rather than crashing.
    assert "⚪" in tables


def test_uc_cell_formats_the_rollup():
    # done use cases are NAMED, not just counted
    assert gen_status._uc_cell(3, 0, 3, ["A", "B", "C"]) == "3/3 done: A, B, C"
    assert gen_status._uc_cell(1, 3, 4, ["A"]) == "1/4 done: A · 3 in progress"
    assert gen_status._uc_cell(0, 3, 4, []) == "0/4 done · 3 in progress"   # none done -> count only
    assert gen_status._uc_cell(0, 0, 0, []) == "—"          # a package with no declared use cases
    assert gen_status._uc_cell(2, 0, 3) == "2/3 done"       # names optional -> falls back to count
    # a status:done use case lacking a name still counts toward done/total but isn't listed:
    # done=3 with only 2 names -> the count stays 3/3, naming the 2 that have names
    assert gen_status._uc_cell(3, 0, 3, ["A", "B"]) == "3/3 done: A, B"
    # a name containing the markdown column delimiter is escaped so it can't break the table
    assert gen_status._uc_cell(1, 0, 1, ["A | B"]) == "1/1 done: A \\| B"


def test_outcome_tables_show_use_case_rollup_as_a_second_axis():
    status = {}
    # inject use-case counts + done names so the test does not depend on live model.json
    uc = {"early-risk-detection": (3, 0, 3, ["Alpha", "Beta", "Gamma"]),  # fully delivered
          "unified-customer-view": (1, 3, 4, ["Delta"])}                  # partial + in-flight
    tables = gen_status.render_outcome_tables(status, uc=uc)
    assert "| Status | Package | Use cases |" in tables    # the new column exists
    assert "3/3 done: Alpha, Beta, Gamma" in tables         # done use cases are named
    assert "1/4 done: Delta · 3 in progress" in tables
    assert "—" in tables                                    # keys absent from uc -> no use cases
    # the two axes are labelled so build Status is not read as completeness
    assert "artifacts built and reviewed" in tables and "business outcomes for the package" in tables


def test_outcome_use_cases_matches_the_emitter_vocabulary_structurally():
    # Exercises the REAL parse against model.json, but asserts STRUCTURAL invariants,
    # not a mutable snapshot - so an ordinary use-case status flip (a routine, expected
    # event per ADR 0013) does NOT break this test; only an emitter status-vocabulary
    # rename does (it would zero the done/in-progress string matches).
    uc = gen_status.outcome_use_cases()   # reads explorer/public/model.json
    layout_keys = {k for _, rows in gen_status.OUTCOME_LAYOUT for k, _, _ in rows}
    assert layout_keys <= set(uc)                          # every laid-out package parsed
    for done, ip, tot, done_names in uc.values():
        assert done >= 0 and ip >= 0 and done + ip <= tot  # counts reconcile (planned = tot-done-ip >= 0)
        # done counts by STATUS; done_names is the display subset (only status:done WITH a name),
        # so names <= done. Not tautological: a status:done use case lacking a name still counts
        # toward `done` but drops out of `done_names`.
        assert len(done_names) <= done
    # at least one use case reads done/in-progress -> the "done"/"in-progress" strings
    # still match the emitter vocabulary (a rename would make this sum 0 and fail here)
    assert sum(done + ip for done, ip, _, _ in uc.values()) > 0


def test_layout_drift_is_detected():
    status = {k: "🟢" for k, _ in gen_status.CORE_LAYOUT}
    # drop a core domain to simulate a STATUS.md that lost a row
    status.pop("calendar")
    problems = gen_status.validate_layout(status)
    assert any("calendar" in p for p in problems)


def test_parse_status_text_extracts_emoji_and_description():
    text = (
        "| Domain | Status | Working on it | Branch |\n"
        "|---|---|---|---|\n"
        "| customer | 🟢 Review complete | — | — |\n"
        "| calendar | 🟡 In progress | — | — |\n"
    )
    parsed = gen_status.parse_status_text(text)
    assert parsed == {"customer": "🟢 Review complete", "calendar": "🟡 In progress"}


def test_parse_status_text_ignores_trailing_comments():
    text = (
        "| Domain | Status | Working on it | Branch |\n"
        "|---|---|---|---|\n"
        "| interaction | 🔵 Nearing complete | @Tagar | — |  <!-- all 9 MUST |\n"
    )
    parsed = gen_status.parse_status_text(text)
    assert parsed["interaction"] == "🔵 Nearing complete"


def test_extract_generic_suffix_preserves_last_reviewed():
    line = "> Status: 🟡 In progress (" + V + ") · Last reviewed: 2026-06-09"
    suffix = gen_status._extract_generic_suffix(line)
    assert suffix == "· Last reviewed: 2026-06-09"


def test_extract_generic_suffix_keeps_marketplace_drops_specific_text():
    line = "> Status: 🔵 Nearing complete · Marketplace listing: planned · in review in PR #60"
    suffix = gen_status._extract_generic_suffix(line)
    assert suffix == "· Marketplace listing: planned"


def test_generate_status_line_formats_correctly():
    status_text = {"customer": "🟢 Review complete"}
    line = gen_status._generate_status_line("customer", status_text)
    assert line == "> Status: 🟢 Review complete (" + V + ")"


def test_generate_status_line_returns_empty_for_unknown_key():
    status_text = {"customer": "🟢 Review complete"}
    line = gen_status._generate_status_line("nonexistent", status_text)
    assert line == ""


def test_update_status_line_in_file_leaves_synced_file_unchanged(tmp_path):
    """A file with status line already in sync should not be marked as changed."""
    test_file = tmp_path / "test_glossary.md"
    content = "# Customer Domain\n\n> Status: 🟢 Review complete (" + V + ")\n\nSome content.\n"
    test_file.write_text(content)

    status_text = {"customer": "🟢 Review complete"}
    changed = gen_status._update_status_line_in_file(test_file, "customer", status_text)

    # File should not be marked as changed since content is identical
    assert changed is False
    assert test_file.read_text() == content


def test_update_status_line_in_file_rewrites_stale_status(tmp_path):
    """A file with stale status line should be rewritten with new status."""
    test_file = tmp_path / "test_glossary.md"
    old_content = "# Customer Domain\n\n> Status: 🟡 In progress (" + V + ")\n\nSome content.\n"
    test_file.write_text(old_content)

    status_text = {"customer": "🟢 Review complete"}
    changed = gen_status._update_status_line_in_file(test_file, "customer", status_text)

    # File should be marked as changed
    assert changed is True
    new_content = test_file.read_text()
    assert "> Status: 🟢 Review complete (" + V + ")" in new_content
    assert "🟡" not in new_content


def test_update_status_line_in_file_preserves_generic_suffix(tmp_path):
    """Generic suffixes like 'Last reviewed' should be preserved when rewriting."""
    test_file = tmp_path / "test_glossary.md"
    old_content = (
        "# Customer Domain\n\n"
        "> Status: 🟡 In progress (" + V + ") · Last reviewed: 2026-06-09 · Some specific note to drop\n\n"
        "Some content.\n"
    )
    test_file.write_text(old_content)

    status_text = {"customer": "🟢 Review complete"}
    changed = gen_status._update_status_line_in_file(test_file, "customer", status_text)

    assert changed is True
    new_content = test_file.read_text()
    # New status should be there
    assert "> Status: 🟢 Review complete (" + V + ")" in new_content
    # Generic suffix should be preserved
    assert "· Last reviewed: 2026-06-09" in new_content
    # Specific note should be dropped
    assert "Some specific note to drop" not in new_content


def test_update_status_line_in_file_preserves_marketplace_listing(tmp_path):
    """Marketplace listing suffix should be preserved when rewriting."""
    test_file = tmp_path / "test_glossary.md"
    old_content = (
        "# Package\n\n"
        "> Status: 🟡 In progress (" + V + ") · Marketplace listing: planned · in review in PR #60\n\n"
        "Some content.\n"
    )
    test_file.write_text(old_content)

    status_text = {"unified-customer-view": "🟢 Review complete"}
    changed = gen_status._update_status_line_in_file(test_file, "unified-customer-view", status_text)

    assert changed is True
    new_content = test_file.read_text()
    # Marketplace listing should be preserved
    assert "· Marketplace listing: planned" in new_content
    # Specific PR reference should be dropped
    assert "PR #60" not in new_content


# The two REPO-STATE assertions (real STATUS.md<->LAYOUT agreement, and the committed
# README being in sync) live in tests/standards/test_status_generation.py — the ADVISORY
# suite, matching where the conformance-matrix sync test sits, so a stale generated
# surface does not asymmetrically HARD-block merge. The pure-unit tests above stay here.


def test_status_line_problem_flags_duplicates_and_missing(tmp_path):
    status = {"customer": "🟢 Review complete"}
    dup = tmp_path / "dup.md"
    dup.write_text("# T\n\n> Status: 🟢 Review complete (" + V + ")\n\n> Status: 🟢 Review complete (" + V + ")\n")
    assert "2 status lines" in gen_status._status_line_problem(dup, "customer", status)
    missing = tmp_path / "missing.md"
    missing.write_text("# T\n\nBody.\n")
    assert gen_status._status_line_problem(missing, "customer", status) == "missing status line"


def test_update_status_line_in_file_inserts_after_heading_with_blank_lines(tmp_path):
    f = tmp_path / "glossary.md"
    f.write_text("# Title\n\nBody text.\n")
    assert gen_status._update_status_line_in_file(f, "customer", {"customer": "🟢 Review complete"})
    assert f.read_text() == "# Title\n\n> Status: 🟢 Review complete (" + V + ")\n\nBody text.\n"
    # Idempotent: a second run changes nothing and leaves exactly one status line.
    assert not gen_status._update_status_line_in_file(f, "customer", {"customer": "🟢 Review complete"})
    assert f.read_text().count("> Status:") == 1


def test_update_status_line_in_file_inserts_at_top_when_there_is_no_heading(tmp_path):
    # A first commit with no "#" heading used to raise TypeError mid-`make regen`.
    status = {"customer": "🟢 Review complete"}
    f = tmp_path / "README.md"
    f.write_text("Body text.\n")
    assert gen_status._update_status_line_in_file(f, "customer", status)
    assert f.read_text() == "> Status: 🟢 Review complete (" + V + ")\n\nBody text.\n"
    assert gen_status._status_line_problem(f, "customer", status) == ""
    assert not gen_status._update_status_line_in_file(f, "customer", status)


def test_update_status_line_in_file_appends_when_heading_is_the_last_line(tmp_path):
    # A one-line "# X Glossary" stub used to be silently skipped, so --check stayed red forever.
    status = {"customer": "🟢 Review complete"}
    f = tmp_path / "glossary.md"
    f.write_text("# Customer Glossary")
    assert gen_status._update_status_line_in_file(f, "customer", status)
    assert f.read_text() == "# Customer Glossary\n\n> Status: 🟢 Review complete (" + V + ")\n"
    assert gen_status._status_line_problem(f, "customer", status) == ""
    assert not gen_status._update_status_line_in_file(f, "customer", status)


def test_status_line_in_a_code_fence_is_ignored_by_check_and_write(tmp_path):
    # --check and --write share one fence-aware scanner, so a fenced example is neither
    # counted as a duplicate nor rewritten, and --check never reports a red --write can't fix.
    status = {"customer": "🟢 Review complete"}
    example = "```markdown\n> Status: 🟡 In progress (" + V + ")\n```\n"
    f = tmp_path / "README.md"
    f.write_text("# T\n\n" + example + "\n> Status: 🟢 Review complete (" + V + ")\n")
    assert gen_status._status_line_problem(f, "customer", status) == ""
    assert not gen_status._update_status_line_in_file(f, "customer", status)

    # A stale real line is rewritten; the fenced example is left untouched.
    f.write_text("# T\n\n" + example + "\n> Status: 🟡 In progress (" + V + ")\n")
    assert gen_status._status_line_problem(f, "customer", status) == "stale status line"
    assert gen_status._update_status_line_in_file(f, "customer", status)
    assert f.read_text() == "# T\n\n" + example + "\n> Status: 🟢 Review complete (" + V + ")\n"
    assert gen_status._status_line_problem(f, "customer", status) == ""


def test_write_drops_duplicate_real_status_lines_and_keeps_fenced_examples(tmp_path):
    # --check reports duplicates, so --write must be able to clear them (keeping the first
    # real line), while a fenced example status line is left exactly as written.
    status = {"customer": "🟢 Review complete"}
    example = "```markdown\n> Status: 🟡 In progress (" + V + ")\n```\n"
    f = tmp_path / "README.md"
    f.write_text(
        "# T\n\n> Status: 🟡 In progress (" + V + ")\n\n"
        + example
        + "\n> Status: 🟢 Review complete (" + V + ")\n\nBody.\n"
    )
    assert "2 status lines" in gen_status._status_line_problem(f, "customer", status)
    assert gen_status._update_status_line_in_file(f, "customer", status)
    assert f.read_text() == (
        "# T\n\n> Status: 🟢 Review complete (" + V + ")\n\n" + example + "\nBody.\n"
    )
    assert gen_status._status_line_problem(f, "customer", status) == ""
    assert not gen_status._update_status_line_in_file(f, "customer", status)

    # A duplicate that ends the file takes the blank line before it, not the kept line's layout.
    g = tmp_path / "glossary.md"
    g.write_text("# T\n\n> Status: 🟢 Review complete (" + V + ")\n\n> Status: 🟢 Review complete (" + V + ")\n")
    assert gen_status._update_status_line_in_file(g, "customer", status)
    assert g.read_text() == "# T\n\n> Status: 🟢 Review complete (" + V + ")\n"
    assert gen_status._status_line_problem(g, "customer", status) == ""


def test_status_callout_in_a_body_section_is_left_alone(tmp_path):
    # Only the header (before the first "## ") is scanned, so a "> Status:" callout under a
    # body section is neither flagged by --check nor rewritten or removed by --write.
    status = {"customer": "🟢 Review complete"}
    body = "## Use case: churn\n\n> Status: 🟡 In progress (" + V + ")\n\nDetails.\n"
    f = tmp_path / "README.md"
    f.write_text("# T\n\n> Status: 🟢 Review complete (" + V + ")\n\n" + body)
    assert gen_status._status_line_problem(f, "customer", status) == ""
    assert not gen_status._update_status_line_in_file(f, "customer", status)
    assert f.read_text().endswith(body)

    # Header duplicates still collapse, and the body callout still survives.
    f.write_text(
        "# T\n\n> Status: 🟡 In progress (" + V + ")\n\n> Status: 🟡 In progress (" + V + ")\n\n" + body
    )
    assert "2 status lines" in gen_status._status_line_problem(f, "customer", status)
    assert gen_status._update_status_line_in_file(f, "customer", status)
    assert f.read_text() == "# T\n\n> Status: 🟢 Review complete (" + V + ")\n\n" + body
    assert gen_status._status_line_problem(f, "customer", status) == ""


def test_update_status_line_in_file_without_a_title_inserts_above_the_first_section(tmp_path):
    # With no "# " title, the line goes at the top (inside the header), never under the first
    # "## " section where the next run could not see it and would insert another one.
    status = {"customer": "🟢 Review complete"}
    f = tmp_path / "README.md"
    f.write_text("## Overview\n\nBody.\n")
    assert gen_status._update_status_line_in_file(f, "customer", status)
    assert f.read_text() == "> Status: 🟢 Review complete (" + V + ")\n\n## Overview\n\nBody.\n"
    assert gen_status._status_line_problem(f, "customer", status) == ""
    assert not gen_status._update_status_line_in_file(f, "customer", status)


def test_extract_generic_suffix_keeps_a_multi_word_marketplace_state():
    line = "> Status: 🟡 In progress (" + V + ") · Marketplace listing: in review · note to drop"
    assert gen_status._extract_generic_suffix(line) == "· Marketplace listing: in review"
    end = "> Status: 🟡 In progress (" + V + ") · Marketplace listing: in review\n"
    assert gen_status._extract_generic_suffix(end) == "· Marketplace listing: in review"


def test_generated_status_line_uses_the_model_version_constant(monkeypatch):
    monkeypatch.setattr(gen_status, "MODEL_VERSION", "0.2")
    line = gen_status._generate_status_line("customer", {"customer": "🟢 Review complete"})
    assert line == "> Status: 🟢 Review complete (0.2)"


_REVIEWERS_SAMPLE = """# Reviewers

| Entity | Owner | Reviewer | Sign-off |
|---|---|---|---|
| Customer | — | @Tagar | [#147](https://github.com/databricks-industry-solutions/open-retail-data-model/issues/147) |
| Labor | — | @Tagar | — |
| Interaction | @Tagar | — | — |

| Outcome package | Owner | Reviewer | Sign-off |
|---|---|---|---|
| Early Risk Detection | @sreekanthmunigati | @Tagar | #146 |
| Promote with Purpose | — | — | — |
"""


def test_parse_reviewers_reads_reviewer_and_signoff_by_display_name():
    reviewers = gen_status.parse_reviewers(_REVIEWERS_SAMPLE)
    assert reviewers == {
        "Customer": ("@Tagar", "[#147](https://github.com/databricks-industry-solutions/open-retail-data-model/issues/147)"),
        "Labor": ("@Tagar", "—"),
        "Interaction": ("—", "—"),
        "Early Risk Detection": ("@Tagar", "#146"),
        "Promote with Purpose": ("—", "—"),
    }
    # A row from before the Sign-off column existed reads as no sign-off.
    assert gen_status.parse_reviewers("| Customer | — | @Tagar |") == {"Customer": ("@Tagar", "")}


def test_validate_signoffs_passes_when_every_review_complete_row_is_signed_off():
    reviewers = gen_status.parse_reviewers(_REVIEWERS_SAMPLE)
    # 🔵 and below need neither a reviewer nor a sign-off: they are held, not review-complete.
    status = {"customer": "🟢", "early-risk-detection": "✅", "labor": "🔵",
              "interaction": "🔵", "promote-with-purpose": "🟡"}
    assert gen_status.validate_signoffs(status, reviewers) == []


def test_validate_signoffs_flags_a_reviewer_without_a_recorded_signoff():
    # Being listed as Reviewer is not a sign-off.
    reviewers = gen_status.parse_reviewers(_REVIEWERS_SAMPLE)
    assert gen_status.validate_signoffs({"labor": "🟢"}, reviewers) == [
        "labor is 🟢 in STATUS.md but has no recorded sign-off in REVIEWERS.md for 'Labor' "
        "(Sign-off is '—'; link the review-signoff issue, e.g. #123)"
    ]


def test_validate_signoffs_flags_no_assigned_reviewer_and_missing_rows():
    reviewers = gen_status.parse_reviewers(_REVIEWERS_SAMPLE)
    problems = gen_status.validate_signoffs({"promote-with-purpose": "🟢"}, reviewers)
    assert problems == [
        "promote-with-purpose is 🟢 in STATUS.md but has no assigned reviewer in REVIEWERS.md "
        "for 'Promote with Purpose' (Reviewer is '—')",
        "promote-with-purpose is 🟢 in STATUS.md but has no recorded sign-off in REVIEWERS.md "
        "for 'Promote with Purpose' (Sign-off is '—'; link the review-signoff issue, e.g. #123)",
    ]
    # ✅ Published implies review-complete, so it needs a sign-off too.
    assert gen_status.validate_signoffs({"interaction": "✅"}, reviewers)
    # A review-complete row missing from REVIEWERS.md entirely is reported as such.
    assert gen_status.validate_signoffs({"store": "🟢"}, reviewers) == [
        "store is 🟢 in STATUS.md but REVIEWERS.md has no 'Store' row"
    ]


def test_repo_review_complete_rows_all_have_a_recorded_signoff():
    status = gen_status.parse_status(gen_status.STATUS_PATH.read_text())
    reviewers = gen_status.parse_reviewers(gen_status.REVIEWERS_PATH.read_text())
    assert gen_status.validate_signoffs(status, reviewers) == []


def test_signoff_cell_must_be_an_issue_or_pr_reference():
    ok = gen_status._is_signoff_ref
    assert ok("#147")
    assert ok("[#147](https://github.com/databricks-industry-solutions/open-retail-data-model/issues/147)")
    assert ok("[#147](https://github.com/databricks-industry-solutions/open-retail-data-model/pull/147)")
    assert not ok("[#147](https://github.com/some-other-org/other-repo/issues/147)")  # pinned to this repo
    for bad in ("approved #147", "#147 (pending)", "see #147", "[#147](https://example.com/issues/147)",
                "[#147](https://github.com/databricks-industry-solutions/open-retail-data-model/issues/148)", "#", "TBD"):
        assert not ok(bad), bad
    reviewers = {"Customer": ("@Tagar", "approved in #147")}
    assert gen_status.validate_signoffs({"customer": "🟢"}, reviewers) == [
        "customer is 🟢 in STATUS.md but its REVIEWERS.md Sign-off for 'Customer' is not an "
        "issue/PR reference ('approved in #147'; expected "
        "#NNN or [#NNN](https://github.com/databricks-industry-solutions/open-retail-data-model/issues/NNN))"
    ]


def test_signoff_cell_may_list_several_references():
    refs = gen_status._signoff_refs
    assert refs("#165") == ["165"]
    assert refs("[#165](https://github.com/databricks-industry-solutions/open-retail-data-model/issues/165), #170") == ["165", "170"]
    assert refs("#165, see #170") is None
    reviewers = {"Customer": ("@Tagar", "#147, #170")}
    assert gen_status.validate_signoffs({"customer": "🟢"}, reviewers) == []


def test_initial_publication_flag_gates_the_self_review_check(monkeypatch):
    """GOVERNANCE.md: the initial public release may publish a self-reviewed row on one sign-off.
    The flag only switches the --check section; turning it off restores the requirement.
    Uses the repo's real inputs with Interaction (Owner = Reviewer = @Tagar) raised to ✅."""
    status, status_text, readme, reviewers = _repo_check_inputs()
    status = dict(status, interaction="✅")

    def self_review_sections():
        return [h for h, _ in gen_status.collect_check_problems(status, status_text, readme, reviewers)
                if h.startswith("Self-reviewed rows")]
    monkeypatch.setattr(gen_status, "INITIAL_PUBLICATION_SELF_REVIEW", True)
    assert self_review_sections() == []
    monkeypatch.setattr(gen_status, "INITIAL_PUBLICATION_SELF_REVIEW", False)
    assert len(self_review_sections()) == 1


def test_self_reviewed_row_needs_a_second_signoff_for_published():
    owners = {"Interaction": "@Tagar", "Customer": "—"}
    one = {"Interaction": ("@Tagar", "#165"), "Customer": ("@Tagar", "#147")}
    # 🟢 on a self-review is allowed.
    assert gen_status.validate_self_review({"interaction": "🟢"}, one, owners) == []
    # ✅ on a self-review with one sign-off is not.
    assert gen_status.validate_self_review({"interaction": "✅"}, one, owners) == [
        "interaction is ✅ in STATUS.md but is self-reviewed in REVIEWERS.md for 'Interaction' "
        "(Owner and Reviewer both @tagar) with 1 sign-off; add the second, independent reviewer's "
        "sign-off to the Sign-off cell as '#A, #B' (GOVERNANCE.md)"
    ]
    two = {"Interaction": ("@Tagar", "#165, #170")}
    assert gen_status.validate_self_review({"interaction": "✅"}, two, owners) == []
    # Not a self-review: one sign-off is enough for ✅.
    assert gen_status.validate_self_review({"customer": "✅"}, one, owners) == []


def test_parse_owners_reads_the_owner_column():
    assert gen_status.parse_owners(_REVIEWERS_SAMPLE)["Interaction"] == "@Tagar"
    assert gen_status.parse_owners(_REVIEWERS_SAMPLE)["Customer"] == "—"


def _repo_check_inputs():
    status_md = gen_status.STATUS_PATH.read_text()
    return (gen_status.parse_status(status_md), gen_status.parse_status_text(status_md),
            gen_status.README_PATH.read_text(), gen_status.REVIEWERS_PATH.read_text())


def test_check_reports_every_problem_in_one_run():
    status, status_text, readme, reviewers = _repo_check_inputs()
    assert gen_status.collect_check_problems(status, status_text, readme, reviewers) == []

    # A stale per-folder status line AND a missing sign-off: both are reported together,
    # rather than the sign-off problem only showing up on a second run.
    stale_text = dict(status_text, store="🟡 In progress")
    payment_row = next(l for l in reviewers.splitlines() if l.startswith("| Payment |"))
    no_signoff = reviewers.replace(payment_row, payment_row.rsplit("|", 2)[0] + "| — |")
    assert no_signoff != reviewers
    sections = gen_status.collect_check_problems(status, stale_text, readme, no_signoff)
    headings = [h for h, _ in sections]
    assert any(h.startswith("Missing, duplicated or stale status lines") for h in headings)
    assert any(h.startswith("Review-complete rows in STATUS.md need a recorded sign-off") for h in headings)
    items = [i for _, its in sections for i in its]
    assert "canonical-core/store/README.md: stale status line" in items
    assert any(i.startswith("payment is 🟢 in STATUS.md but has no recorded sign-off") for i in items)


def test_a_status_note_on_a_following_line_or_below_survives_write(tmp_path):
    # The two note patterns CONTRIBUTING documents: a following "> " line, or plain text below.
    status = {"customer": "🟢 Review complete"}
    for note in ("> Note: identity slice in review.\n", "\nIdentity slice is in review.\n"):
        f = tmp_path / "README.md"
        f.write_text("# T\n\n> Status: 🟡 In progress (" + V + ")\n" + note + "\nBody.\n")
        assert gen_status._update_status_line_in_file(f, "customer", status)
        assert f.read_text() == "# T\n\n> Status: 🟢 Review complete (" + V + ")\n" + note + "\nBody.\n"
        assert gen_status._status_line_problem(f, "customer", status) == ""
