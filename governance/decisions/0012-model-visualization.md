# ADR 0012 — Model visualization: generated diagrams + interactive explorer

**Status:** Accepted (2026-07-07)

## Context
ORDM needs its data model to be *seen*, not just deployed: reviewers, adopters, and partners want ER
diagrams that are accurate, current, and pleasant to read. Hand-drawn diagrams drift from the model the
moment the DDL changes. GitHub can render Mermaid inline, but only inside a sandboxed iframe whose
background follows the viewer's light/dark theme — so native Mermaid cannot carry a controlled palette
or a fixed background, and `erDiagram` cannot color entities per-layer. Rich fidelity (per-column PII
accents, metric-view cards, the full Databricks palette) is inherently HTML/CSS.

## Decision
Generate all visualization artifacts **from the DDL** via a shared parser (`tools/ordm_ddl`), so a
diagram is a projection of the source of truth and cannot silently be wrong:

1. **Static, GitHub-inline diagrams.** A hybrid renderer — `erDiagram` for canonical-core domains
   (clean column grid), `flowchart` for outcome packages (per-node slate/amber palette). Committed as
   **dual-theme SVGs** (`.svg` light/dark) embedded via `<picture>` + `prefers-color-scheme`, because
   GitHub-native Mermaid can't control the canvas. Mermaid `.mmd` source is kept committed as the render
   input + a native fallback.
2. **Portable interchange.** A `.dbml` per unit (dbdiagram.io / dbdocs / `@dbml/core`).
3. **Interactive explorer.** A self-contained static SPA (Cytoscape.js + `cytoscape-fcose` +
   `cytoscape-node-html-label`, all MIT) fed by a generated `model.json`, delivering the full-fidelity
   HTML/CSS look (per-column PII rose, metric-view cards, value-chain landing with drill-down to per-unit ER + table detail (redesigned; see Amendment),
   filter/search, light/dark, click-through to glossary + ODCS contract). Deployed to a **public repo's
   GitHub Pages** (free Pages + Actions; staging stays private; no paid org seats).
4. **One parse, five projections, single-source-gated.** DDL → `model.json` / `.mmd` / `.svg` / `.dbml`
   all derive from one parse; CI regenerates and drift-gates them so they cannot diverge.
5. **CI generates + commits** the derived artifacts on same-repo PR branches (contributors only edit
   DDL); fork PRs fall back to a check-only drift gate. This also makes CI the sole SVG renderer,
   removing cross-OS render non-determinism.

## Consequences
- Diagrams are always current or CI is red; reviewers see the model change rendered in the PR.
- The explorer is a static, publishable artifact (no runtime SaaS, no internal infra) — the curated
  subset promotes to the public `databricks-industry-solutions/open-retail-data-model` repo.
- Five committed generated formats add repo weight, accepted because each serves a distinct consumer and
  the drift gate prevents divergence.
- A model-changing PR spends a few CI minutes on Mermaid rendering (path-filtered, so only when the
  model changes).

## Alternatives rejected
- **Native Mermaid inline (no committed image).** Rejected: GitHub's iframe forces the viewer's theme
  background (unreadable in dark mode) and `erDiagram` can't be per-entity colored.
- **MkDocs + Mermaid docs site (the earlier "Phase 2").** Rejected: adds navigation but inherits the
  same Mermaid visual ceiling — no per-column/PII/card fidelity.
- **React Flow for the explorer.** Reasonable, but Cytoscape.js is lighter, graph-first, and needs no
  React build; chosen for the SPA.
- **dbdocs.io / Azimutt as the hosted explorer.** Rejected: SaaS / server-backed, not self-contained or
  publishable. DBML is still emitted for optional use with those tools.

See `docs/anatomy-of-a-model.md` and `docs/er-diagrams.md`. Full design: `design/31`, `design/32`, `design/34` (local).

## Amendment (2026-07-12): value-chain landing redesign

The interactive explorer's landing model was later redesigned (`design/34`): the original force-directed
overview is replaced by a **layered value-chain landing** (the outcome packages over the conformed core,
with what each package consumes revealed on hover), plus a **Matrix** view, with the force-directed graph
**demoted to an opt-in Graph view**. A navigator minimap and L1 **use-case swimlane grouping** (per
[ADR 0013](0013-use-cases-planning-artifact.md), which also drives the L1 reveal of the core domains each
use case consumes) were added. The one-parse, drift-gated generation contract (Decision items 4-5) is
unchanged; only the explorer's presentation evolved.
