# ADR 0003: The SCD2 current-version flag is is_current

**Status:** Accepted (2026-06-15)

## Context
The SCD Type 2 current-version indicator appeared under two names across early drafts: an older `current_flag` wording in the principles, and `is_current` in both reference contributions. A machine check for SCD2 correctness keys off this column name, so it has to be pinned to one form.

## Decision
The flag is `is_current`. This matches the project's `is_*` boolean naming convention and what both contributors already ship. The older `current_flag` wording is retired and the standard is updated to match.

## Consequences
- One column name for the SCD2 current indicator across every master, so the current-open and non-current-closed DQ checks and the SCD2 static checks all key off `is_current`.
- No code change for the existing contributions, which already use `is_current`.
