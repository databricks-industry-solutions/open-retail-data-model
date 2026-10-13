# ADR 0009 — UC Domains: derived mapping, no domains manifest

**Status:** Accepted (2026-07-06)

> Numbering note: ADR 0008 was retired with the closed PR #26 (metric-view artifact format) and is intentionally not reused; the series resumes at 0009.

## Context

Unity Catalog Domains organize catalogs and schemas for discovery. They are an
**account-level** concept (managed on the account Discover page), currently **Public
Preview**, with no workspace-level create API. ORDM already encodes its domain
structure in the filesystem: one domain per `canonical-core/<domain>/` and one per
`outcome-packages/<package>/`.

A recurring temptation is to add a hand-maintained manifest (for example
`governance/domains.yaml`) enumerating the domains and their members. That pattern
drifts from the actual repo structure and duplicates information the tree already
carries, and would need hand-maintenance to stay in sync.

## Decision

ORDM does **not** ship a domains manifest. The ORDM to UC Domain mapping is
**derived** from the repo layout (one UC Domain per `canonical-core/<domain>` and per
`outcome-packages/<package>`, with an optional parent "ORDM"). An account admin
applies it out-of-band (create the domains on the Discover page and assign the
deployed schemas), because there is no workspace API. UC Domains are **optional**
governance polish: ORDM deploys and is fully usable without them.

## Consequences

- No manifest to keep in sync; the filesystem tree is the single source of truth,
  and the mapping can be regenerated or verified from it at any time.
- Because Domains are account-level and in preview, the assignment step is manual
  and admin-gated; the concrete steps live in `docs/architecture.md`.
- If Databricks ships an **account-level** API for Domains (they are account-scoped,
  so any such API would be too — today the only interface is the Discover page), a thin
  derive-and-apply script can automate the assignment without introducing a manifest.
