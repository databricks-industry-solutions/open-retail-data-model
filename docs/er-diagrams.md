# ER diagrams

ORDM's entity-relationship diagrams are **generated from the DDL** — never hand-drawn — so they
cannot silently drift from the model. Each domain and each outcome package has diagrams committed
alongside its SQL, and they render inline on the GitHub folder page.

## What's generated

For every unit (a `canonical-core/<domain>/` or `outcome-packages/<package>/`), `tools/gen_er_diagrams.py`
writes into that unit's `diagrams/` folder:

| Artifact | What it is |
|---|---|
| `<unit>.light.mmd` / `<unit>.dark.mmd` | Mermaid source, one per theme (the single source of the diagram) |
| `<unit>.dbml` | [DBML](https://dbml.org) — a portable, tool-agnostic interchange format for the same model |
| `<unit>.light.svg` / `<unit>.dark.svg` | rendered images with a baked-in background (produced by `tools/render_diagrams.sh`) |

The unit's `README.md` gets a `<picture>` block (between `<!-- ORDM:ERD:START -->` / `<!-- ORDM:ERD:END -->`
markers) that shows the **dark** SVG in dark mode and the **light** SVG in light mode, auto-switching
with the reader's GitHub theme. The root [`README.md`](../README.md) carries a hand-authored Tier-0
overview map the same way (`docs/diagrams/ordm-overview.*`).

## Hybrid rendering

- **Canonical-core domains → `erDiagram`.** A single-layer domain is best shown as a clean column
  grid (types, PK/FK, PII/enum markers, crow's-foot cardinality).
- **Outcome packages → `flowchart`.** These mix layers, so per-node color earns its place: the
  Databricks-adjacent palette renders **canonical core = slate** and **outcome / gold = amber**, so
  "core feeds gold" reads at a glance. Columns collapse into node labels here.

Themes use Mermaid's built-in `default` (light) and `dark` (dark) so every sub-element stays legible;
brand colors are layered on top only as flowchart `classDef`s.

## How to regenerate

After changing any DDL (`tables/*.sql`, `relationships.sql`, `checks.sql`), regenerate:

```bash
python tools/gen_er_diagrams.py --write   # regenerate .mmd + .dbml + README <picture> blocks
tools/render_diagrams.sh                  # render the .mmd -> committed .svg (needs mermaid-cli)
```

`tools/render_diagrams.sh` requires [`mermaid-cli`](https://github.com/mermaid-js/mermaid-cli) (`mmdc`)
and uses the pinned, committed `tools/mermaid-config.json` (`deterministicIds`, `htmlLabels:false`,
fixed config) plus a baked opaque background rect, so repeated renders are stable.

## Drift gate & what CI does

On same-repo PRs, CI **auto-generates and commits** the *deterministic* artifacts — the ODCS contracts,
the Mermaid `.mmd` + `.dbml` sources, the README `<picture>` blocks, and `model.json` — so contributors
only edit the DDL. (Fork PRs can't be pushed to, so they instead get a check-only drift gate:
`python tools/gen_er_diagrams.py --check` fails if those text artifacts are stale. Push-to-`main` is
gated the same way.) All of these are pure-python and byte-reproducible.

The rendered **`.svg` images are *not* byte-reproducible**: mermaid's `erDiagram` edge routing gives
the curved relationship lines different coordinates each render, so the SVG bytes cannot be
drift-gated. Instead, freshness is tracked by a **sha stamp**: `tools/render_diagrams.sh` bakes each
`.mmd`'s sha into its `.svg`, and `tools/check_diagram_svgs.py --check` (run by `make check-svg`, part
of `make check`) fails if a committed SVG's stamp no longer matches its `.mmd`. That compare is
deterministic even though the render is not, so the SVGs **are gated now**, like every other derived
type. To avoid a per-run Chromium cost churning unchanged images, `render_diagrams.sh` is
**incremental** (it skips any SVG already stamped with its `.mmd`'s sha), so it re-renders only the
diagrams whose `.mmd` changed. On **same-repo PRs, CI renders + commits the changed SVGs for you**
(the `regen-artifacts` job installs `mermaid-cli` and runs `make regen-svg`); working locally, run
`make regen-svg` after editing an ER diagram. The **source of truth remains the `.mmd` / `.dbml` /
`model.json`**; the SVG is a sha-tracked visual snapshot of it.

## Architecture

The generator reuses the shared DDL parser package `tools/ordm_ddl/` (one parse → many emitters), so
the ODCS contracts, DBML, and Mermaid all derive from the same model and cannot diverge:

```
tools/ordm_ddl/
  model.py        # typed model: Column, Table, Relationship, Check, Unit
  parser.py       # DdlParser — parses Databricks SQL DDL into the model
  discovery.py    # UnitDiscovery — finds domains/packages
  emitters/
    base.py       # Emitter ABC
    dbml.py       # DbmlEmitter
    json_model.py # JsonModelEmitter (explorer/public/model.json)
    mermaid.py    # MermaidEmitter (hybrid erDiagram / flowchart, light + dark)
```

(ODCS assembly is not an emitter here — it lives in `tools/generate_odcs.py`, which
rides this same parser.)

## The interactive explorer

The committed SVGs above are the **inline-on-GitHub** view. For the **full-fidelity** view — a layered
value-chain landing (the outcome packages over the conformed core, with what each package consumes shown
on hover), filter/search, Matrix and Graph views, and drill-down (landing → per-unit ER → table detail)
with per-column PII accents, FK/PK column highlighting, use-case grouping that reveals the core each use
case consumes, a navigator minimap, and click-through to each table's glossary term and ODCS contract —
ORDM ships an **interactive explorer**: a self-contained static SPA (Cytoscape.js, all-MIT deps) generated
from `explorer/public/model.json` and deployed to a public GitHub Pages site. Run it locally:

```bash
cd explorer && npm ci && npm run dev
```

> The use-case → core lineage is derived by parsing each gold view's `FROM`/`JOIN` sources, so **gold
> views must qualify their source tables** (`${catalog}.${schema}.table`, the convention every committed
> gold view already uses). A bare, unqualified source name is not captured as lineage, and if it collides
> with a known table it fails `make check` loud rather than silently dropping the edge.

Why the explorer and not richer inline diagrams: GitHub renders Mermaid in a sandboxed iframe whose
background follows the viewer's theme and can't be per-entity colored, so those accents/cards are only
achievable in HTML/CSS. See [ADR 0012](../governance/decisions/0012-model-visualization.md).

The full **"why five formats?"** rationale (one parse, five projections, single-source-gated) lives in
[Anatomy of a model](anatomy-of-a-model.md).
