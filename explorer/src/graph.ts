import cytoscape from "cytoscape";
import nodeHtmlLabel from "cytoscape-node-html-label";
import type { Model, Unit } from "./model";
import { modelToElements } from "./elements";
import { renderCard } from "./cards";
import { groupTablesByUseCase, UNASSIGNED_BAND } from "./grouping";
import { escapeHtml as esc } from "./esc";

/**
 * Cytoscape-backed views: the demoted opt-in force-directed **Graph** (whole
 * model) and the per-unit **ER** view used at L1. The layered L0 landing does
 * NOT use cytoscape (see overview.ts) — this module is only mounted when one of
 * those two views is active, and is torn down otherwise so its overlay labels
 * never fight the DOM overview (the root cause of the old filter bugs).
 */

cytoscape.use(nodeHtmlLabel);

/**
 * Whether to expose the `window.__cy` e2e handle. True in a Vite dev build
 * (`import.meta.env.DEV`), or when the page URL carries the `?e2e=1` harness flag
 * (so the Playwright suite can drive the PRODUCTION `vite preview` build it runs
 * against). Never true on a bare production load, so the handle never ships to a
 * real visitor. Defensive around jsdom / SSR where `window`/`location` may lack a
 * search string.
 */
function isE2eExposed(): boolean {
  if ((import.meta as { env?: { DEV?: boolean } }).env?.DEV) return true;
  try {
    return /(?:^|[?&])e2e=1(?:&|$)/.test(window.location.search);
  } catch {
    return false;
  }
}

// ---- module layout constants (single tuning surface for the L1 ER) ----
const CARD_W = 280; // table-card width (must match BASE_STYLE node.table-node width)
const GUTTER = 40; // horizontal gap between card columns
const UNIT_X_PITCH = CARD_W + GUTTER; // 320: column pitch, so columns never touch
const UNIT_GAP_Y = 40; // vertical gap between stacked cards in a column
const FIT_PADDING = 40; // model-space padding kept around the content on fit
// Card geometry (CSS px), shared by cardHeight (node-box sizing) and setExpanded (hover-cap
// math) so the two can't drift. These mirror the .card-hd / .col-row / .col-list CSS; if
// that stylesheet changes, change these. CARD_FOOTER_PX is the "click to see all" footer.
const CARD_HEADER_PX = 40; // header incl. its border + padding
const CARD_ROW_PX = 17; // one .col-row
const CARD_VPAD_PX = 18; // .col-list top + bottom padding
const CARD_FOOTER_PX = 26; // the capped-card "click to see all N columns" footer
const cardPxForRows = (rows: number): number =>
  CARD_HEADER_PX + rows * CARD_ROW_PX + CARD_VPAD_PX;
const DEFAULT_ZOOM_MIN = 0.55; // readable band floor (a tiny diagram isn't blown up)
const DEFAULT_ZOOM_MAX = 1.4; //  ...and ceiling (a wide one isn't microscopic)
const PAN_MARGIN = 80; // model-px of content kept within the viewport when panning

/**
 * How many card columns fit in `availPx` model-space pixels, never more than `n`
 * cards, never fewer than one. Width-aware (replaces the old width-blind cap of 3):
 * a wide viewport packs more columns and fills the canvas, a narrow one wraps.
 * Exported for unit tests (pure).
 */
export function fitCols(availPx: number, n: number): number {
  const byWidth = Math.floor((availPx + GUTTER) / UNIT_X_PITCH);
  return Math.max(1, Math.min(n, byWidth || 1));
}

/** Model-space width available for card columns (viewport minus fit padding). */
function availContentWidth(cy: cytoscape.Core): number {
  const w = cy.width();
  return Math.max(UNIT_X_PITCH, w - 2 * FIT_PADDING);
}

/**
 * Default-zoom heuristic: fit-to-WIDTH, clamped to a readable band, top-anchored.
 * A tall/sparse ER would otherwise be shrunk to fit its HEIGHT (cytoscape's
 * `fit:true`), rendering microscopic cards; instead we scale to the content
 * width, clamp to [MIN,MAX], centre horizontally and pin the content top to
 * FIT_PADDING so the user starts at the head of the diagram and pans DOWN.
 * Reads cy.width() live, so it self-corrects when the panel narrows the canvas.
 */
function applyDefaultZoom(cy: cytoscape.Core): void {
  const bb = cy.elements().boundingBox();
  const vw = cy.width();
  if (bb.w <= 0 || vw <= 0) {
    // degenerate (jsdom / empty): fall back to plain fit, no divide-by-zero.
    cy.fit(cy.elements(), FIT_PADDING);
    return;
  }
  const zoom = Math.max(
    DEFAULT_ZOOM_MIN,
    Math.min(DEFAULT_ZOOM_MAX, (vw - 2 * FIT_PADDING) / bb.w)
  );
  cy.zoom(zoom);
  cy.pan({ x: (vw - bb.w * zoom) / 2 - bb.x1 * zoom, y: FIT_PADDING - bb.y1 * zoom });
}

/** The content bounding box (model-space) the pan clamp / navigator map against. */
interface ContentBB {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  w: number;
  h: number;
}

/**
 * Clamp the current pan so the content keeps COVERING the viewport (design/38 §2).
 * The two per-axis bounds are the pans that put the content's near edge `M` px
 * inside the near viewport edge and its far edge `M` px inside the far edge, with
 * z=zoom, W/H the viewport size and M=PAN_MARGIN*z:
 *   a = M - contentBB.x1*z      (content left edge M px from the viewport left)
 *   b = W - M - contentBB.x2*z  (content right edge M px from the viewport right)
 * We clamp panX to [min(a,b), max(a,b)] (and the same on Y). When content is LARGER
 * than the viewport a>b, so the range lets you scroll from edge to edge but never
 * PAST the content into an empty void; when it is SMALLER a<b, so the content just
 * stays fully within the viewport. (The previous formula kept only `M` px of
 * content in view, which let a tall diagram be scrolled almost entirely off.)
 * Degenerate (0-size) content is a no-op. cy.pan() runs only when it changed.
 */
export function clampPan(cy: cytoscape.Core, contentBB: ContentBB, bottomInset = 0): void {
  if (contentBB.w <= 0 || contentBB.h <= 0) return;
  const z = cy.zoom();
  const W = cy.width();
  const H = cy.height();
  const M = PAN_MARGIN * z;
  const pan = cy.pan();

  const clampAxis = (p: number, a: number, b: number): number =>
    Math.max(Math.min(a, b), Math.min(Math.max(a, b), p));

  // `bottomInset` (screen px) reserves space at the viewport bottom for the consumes
  // rail, so the last row of cards can scroll ABOVE it and their hover arcs stay
  // visible (they were cut off against the rail). It shortens the usable viewport
  // bottom, allowing a bit more downward scroll.
  const nx = clampAxis(pan.x, M - contentBB.x1 * z, W - M - contentBB.x2 * z);
  const ny = clampAxis(pan.y, M - contentBB.y1 * z, H - bottomInset - M - contentBB.y2 * z);
  if (nx !== pan.x || ny !== pan.y) cy.pan({ x: nx, y: ny });
}

const BASE_STYLE: cytoscape.StylesheetStyle[] = [
  {
    selector: "node",
    style: {
      "background-color": "transparent",
      "background-opacity": 0,
      "border-width": 0,
      // Kill cytoscape's default tap/select overlay (a grey rounded box drawn at the
      // NODE box size). The visible card is the HTML label; a hover-expanded card grows
      // past its node box, so on click the overlay showed as a "shadow" at the original
      // compact size behind the expanded card. The card carries its own styling.
      "overlay-opacity": 0,
      width: 240,
      height: 130,
      label: "",
      shape: "rectangle",
    },
  },
  { selector: "node.overview-node", style: { width: 170, height: 46 } },
  { selector: "node.table-node", style: { width: 280, height: "data(h)" } },
  {
    selector: "edge",
    style: {
      width: 1.5,
      "target-arrow-shape": "triangle",
      "curve-style": "bezier",
      opacity: 0.7,
    },
  },
  { selector: "edge.faded", style: { opacity: 0.08 } },
  {
    selector: "edge.highlighted",
    style: {
      opacity: 1,
      width: 2.5,
      "line-color": "#c4320a",
      "target-arrow-color": "#c4320a",
    },
  },
  { selector: "node.faded", style: { opacity: 0.2 } },
  { selector: "node:selected", style: { "background-opacity": 0, "border-width": 0 } },
];

// The whole-model Graph is mostly DISCONNECTED units (only a few packages declare
// consumes-edges), so a force layout scatters them with overlapping labels. Lay it
// out DETERMINISTICALLY in two layers instead — outcome packages on top, conformed
// core below, edges flowing down — on a wide grid so the long labels don't collide.
function layoutGraphLayered(cy: cytoscape.Core): void {
  const COLS = 4;
  const X_PITCH = 380; // > the widest label, so neighbours never overlap
  const Y_PITCH = 84;
  const BAND_GAP = 220; // vertical gap between the outcome tier and the core tier
  const isOutcome = (n: cytoscape.NodeSingular): boolean => n.data("kind") === "outcome";
  const place = (coll: cytoscape.NodeCollection, yBase: number): void => {
    coll.forEach((n, i) => {
      n.position({ x: (i % COLS) * X_PITCH, y: yBase + Math.floor(i / COLS) * Y_PITCH });
    });
  };
  const outcome = cy.nodes().filter(isOutcome);
  const core = cy.nodes().filter((n) => !isOutcome(n));
  place(outcome, 0);
  place(core, Math.max(1, Math.ceil(outcome.length / COLS)) * Y_PITCH + BAND_GAP);
  cy.layout({ name: "preset", fit: false, padding: 50 } as cytoscape.LayoutOptions).run();
  // NB: default-zoom is NOT applied here. mountGraph applies it once after the
  // initial layout, and relayout() re-applies it only when the user has not
  // manually adjusted the zoom (design/38 §4 zoom-durability) — so the packing
  // functions must leave the current zoom untouched.
}

// Per-unit ER cards have VARIABLE height (a wide table renders many more column
// rows than a narrow one). Cytoscape lays out from each node's declared box, so a
// force layout that assumes a fixed size overlaps the tall cards (the "shared
// border" artifact) and flings the rest off-screen. Instead: tell cytoscape each
// card's true height, then place the cards deterministically in balanced columns
// (masonry) that cannot overlap and are fit to the viewport.
type ColLike = { pk: boolean; fk: boolean; pii: boolean; enum_values: string[]; name: string };
function cardHeight(columns: ColLike[]): number {
  // mirror renderCard's row set: key columns + up to 8 others + a "more" row.
  const isKey = (c: ColLike): boolean =>
    c.pk || c.fk || c.pii || (c.enum_values && c.enum_values.length > 0) || c.name.endsWith("_sk") || c.name.endsWith("_id");
  const keys = columns.filter(isKey).length;
  const others = columns.length - keys;
  const rows = keys + Math.min(8, others) + (others > 8 ? 1 : 0);
  return cardPxForRows(rows); // header + column rows + vertical padding (shared constants)
}

// Balanced-column masonry packer (the layout that fixed the tall-card overlap):
// greedily drop each card into the currently-shortest column, starting at yTop.
// Returns the bottom Y consumed, so bands can be stacked. `cols` is shared across
// a whole unit so every band lines its columns up on the same x-grid.
function packColumns(
  nodes: cytoscape.NodeCollection,
  cols: number,
  yTop: number
): number {
  const colBottom = new Array<number>(cols).fill(yTop);
  nodes.forEach((n) => {
    let c = 0;
    for (let i = 1; i < cols; i++) if (colBottom[i] < colBottom[c]) c = i;
    const h = (n.data("h") as number) || 200;
    n.position({ x: c * UNIT_X_PITCH, y: colBottom[c] + h / 2 }); // position is the node CENTER
    colBottom[c] += h + UNIT_GAP_Y;
  });
  return Math.max(...colBottom);
}

// The old width-blind heuristic. No longer the primary column count (fitCols is);
// retained only as the 0-width fallback FLOOR, for the degenerate case where the
// viewport reports no measurable width (jsdom, or a container mounted while hidden)
// so fitCols has no real avail to work from.
function unitCols(n: number): number {
  return Math.max(1, Math.min(3, Math.ceil(Math.sqrt(Math.max(1, n)))));
}

/**
 * Column count for a unit's cards: width-aware `fitCols` when the viewport has a
 * real width, otherwise the `unitCols` fallback floor (0-width / hidden mount).
 * Shared by the flat-grid and band layouts so both agree on the x-grid.
 */
function colsForUnit(cy: cytoscape.Core, n: number): number {
  return cy.width() > 0 ? fitCols(availContentWidth(cy), n) : unitCols(n);
}

// Flat masonry (today's behaviour): used for the whole unit when there is no
// use-case grouping to render (a package with no `tables:` mapping).
function layoutUnitGrid(cy: cytoscape.Core): void {
  const nodes = cy.nodes();
  packColumns(nodes, colsForUnit(cy, nodes.length), 0);
  cy.layout({ name: "preset", fit: false, padding: FIT_PADDING } as cytoscape.LayoutOptions).run();
  // Default-zoom applied by the caller (mountGraph / relayout), not here — see
  // layoutGraphLayered's note and design/38 §4 zoom-durability.
}

/** A laid-out swimlane band: its header text + the model-space box it occupies. */
export interface BandBox {
  name: string;
  status: string | null;
  /** tables DRAWN in this band (the cards this band physically owns). */
  tables: string[];
  /** member tables (for hover highlight); a superset of the tables drawn here. */
  members: string[];
  consumes: string[];
  /** model-space geometry (x/y are the top-left of the band's content area). */
  x: number;
  y: number; // top of the header
  width: number;
  height: number; // header + content
}

// Build a NodeCollection from a list of node ids (the array-of-singletons
// overload of cy.collection() is not typed, so union each into an empty base).
function nodesByIds(cy: cytoscape.Core, ids: string[]): cytoscape.NodeCollection {
  let coll = cy.collection();
  for (const id of ids) coll = coll.union(cy.getElementById(id));
  return coll as unknown as cytoscape.NodeCollection;
}

const BAND_HEADER_H = 24; // fallback header reserve when the real .band-head height is unmeasurable
const BAND_GAP = 20; // vertical gap between bands (tighter rhythm; header adds its own reserve)

/**
 * The real rendered height of a `.band-head` (model-space header reserve above a
 * band's cards). Measured off a throwaway node so the reserve tracks the actual
 * CSS (font/padding/border) rather than a hard-coded guess; falls back to the
 * constant under jsdom / when measurement yields 0.
 */
function bandHeadHeight(container: HTMLElement): number {
  const probe = document.createElement("div");
  probe.className = "band-head";
  probe.style.cssText = "position:absolute;visibility:hidden;left:-9999px;top:0";
  probe.textContent = "M";
  container.appendChild(probe);
  const h = probe.getBoundingClientRect().height;
  probe.remove();
  return h > 0 ? Math.ceil(h) + 6 : BAND_HEADER_H; // +6 breathing room under the underline
}

// Band-aware layout: partition the unit's cards into swimlane bands (one per use
// case, an "Unassigned" catch-all, plus any ungrouped non-gold cards on top),
// packing the balanced-column masonry WITHIN each band and stacking bands down
// the page. Returns each band's model-space box so the overlay can draw a header
// + chip strip that tracks pan/zoom. NOT cytoscape compound nodes (they fight the
// preset masonry — see design/37).
function layoutUnitBands(
  cy: cytoscape.Core,
  container: HTMLElement,
  ungrouped: string[],
  bands: { name: string; status: string | null; tables: string[]; members: string[]; consumes: string[] }[]
): BandBox[] {
  const cols = colsForUnit(cy, cy.nodes().length);
  const headerH = bandHeadHeight(container);
  const boxes: BandBox[] = [];
  let y = 0;

  // Ungrouped non-gold cards (rare at L1) pack at the very top, no header.
  if (ungrouped.length > 0) {
    y = packColumns(nodesByIds(cy, ungrouped), cols, y) + BAND_GAP;
  }

  for (const b of bands) {
    const headerTop = y;
    const contentTop = y + headerH;
    const contentBottom =
      b.tables.length > 0
        ? packColumns(nodesByIds(cy, b.tables), cols, contentTop)
        : contentTop;
    // Track each band's USED columns so a 1-card band shows a short header, not a
    // full-width rule across empty canvas. Left-aligned at x:0, only the right edge varies.
    const usedCols = Math.max(1, Math.min(cols, b.tables.length));
    const width = (usedCols - 1) * UNIT_X_PITCH + CARD_W;
    boxes.push({
      name: b.name,
      status: b.status,
      tables: b.tables,
      members: b.members,
      consumes: b.consumes,
      x: 0,
      y: headerTop,
      width,
      height: contentBottom - headerTop,
    });
    y = contentBottom + BAND_GAP;
  }

  cy.layout({ name: "preset", fit: false, padding: FIT_PADDING } as cytoscape.LayoutOptions).run();
  // Default-zoom applied by the caller (mountGraph / relayout), not here — see
  // layoutGraphLayered's note and design/38 §4 zoom-durability. The returned
  // boxes' geometry comes from the preset run above, independent of zoom, so the
  // band overlay + minimap rebuild against the final bbox regardless.
  return boxes;
}

function getCssVar(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

/**
 * Escape a string for use inside a CSS attribute selector. Prefers the native
 * `CSS.escape` (all real browsers), falling back to a minimal escaper when it is
 * unavailable (jsdom's CSS object does not implement escape, so a direct
 * `CSS.escape` throws under vitest). Table/column names in this model are plain
 * identifiers, so the fallback's conservative backslash-escaping is sufficient.
 */
function cssEscape(s: string): string {
  const c = (globalThis as { CSS?: { escape?: (v: string) => string } }).CSS;
  if (c && typeof c.escape === "function") return c.escape(s);
  return s.replace(/[^a-zA-Z0-9_-]/g, (ch) => "\\" + ch);
}

export interface GraphHandle {
  /** re-colour edges after a theme change. */
  refreshTheme: () => void;
  /**
   * Re-fit the view to the current container size (e.g. after the L2 panel opens
   * and narrows #cy, or on window resize): resize cytoscape, re-run the correct
   * layout with the now-correct column count, and rebuild the band overlay.
   */
  relayout: () => void;
  /**
   * Highlight a use case by name (fade non-members + light its member tables +
   * reveal its consumes chip strip), mirroring a band-header hover. Drives the
   * right-pane use-case list. Returns false when there is no band overlay (fallback /
   * graph mode) or no band with that name.
   */
  highlightUseCase: (name: string) => boolean;
  /** Clear any use-case highlight (no-op when no band overlay). */
  clearUseCaseHighlight: () => void;
  destroy: () => void;
  cy: cytoscape.Core;
}

/**
 * The FK/PK relationship highlight is threaded through NODE DATA (`data.hlCols`),
 * NOT a closure or a post-render class toggle. The node-html-label plugin caches
 * each node's rendered markup and only re-runs this template when the node's DATA
 * changes; a plain render (pan/zoom/forceRender) just replays the cached HTML. So
 * applyRel publishes the lit column names onto each node's `hlCols`, which forces
 * the plugin to re-run the template with the highlight baked into the markup - it
 * then survives every subsequent re-render (design/39).
 */
function applyHtmlLabels(cy: cytoscape.Core): void {
  (cy as unknown as { nodeHtmlLabel: (opts: unknown[]) => void }).nodeHtmlLabel([
    {
      query: "node",
      // Anchor each card's TOP edge to the node box top (not its centre): the plugin
      // places the wrapper corner at (node-centre-x, node-box-top) then centres it
      // horizontally with no vertical self-translate (valign top + valignBox bottom ->
      // translate(-50%, 0%)). At rest wrapperH == nodeH, so the resting geometry is
      // IDENTICAL to centre anchoring; but a hover-EXPANDED card (taller than its node
      // box) now grows DOWNWARD only, floating over the card below it (z-index 40),
      // instead of growing from the centre and covering the band/card ABOVE it. Cards
      // never overlap at rest — only transiently while one is hover-expanded.
      halign: "center",
      valign: "top",
      halignBox: "center",
      valignBox: "bottom",
      tpl: (data: Record<string, unknown>) =>
        renderCard(
          data as Parameters<typeof renderCard>[0],
          new Set((data["hlCols"] as string[] | undefined) ?? [])
        ),
    },
  ]);
}

function edgeColor(): string {
  return getCssVar("--edge-color") || "#55606b";
}

// ============================================================
// Use-case swimlane band overlay (unit / L1 ER)
// ============================================================

interface BandOverlay {
  /** Trigger the use-case hover for the band that DRAWS `table` (no-op if none). */
  hoverTable: (table: string) => void;
  /** Trigger the use-case hover for the band named `name` (no-op if none). Lets
   *  the right-pane use-case list mirror a band-header hover. */
  hoverUseCaseByName: (name: string) => boolean;
  /** Clear any active use-case hover state. */
  clearHover: () => void;
  destroy: () => void;
}

/**
 * DOM overlay for the use-case swimlane bands. Each band gets a header (the hover
 * target, carrying data-uc) and a chip strip listing the core/silver domains the
 * use case consumes (revealed on hover, mirroring the L0 landing's consumes
 * reveal). The overlay layer is transformed in lock-step with cytoscape's
 * pan/zoom so headers track their cards. A chip strip is DOM/SVG, not transient
 * cytoscape ghost nodes (design/37).
 *
 * Hovering a band header — or any member card — fades non-member cards (a
 * `.uc-faded` treatment mirroring cytoscape's `.faded`, which does not carry to
 * the html-label card DOM) and highlights the use case's member tables, so a
 * table shared across use cases lights up under each. Chip strips are only shown
 * for the hovered band.
 */
function createBandOverlay(
  container: HTMLElement,
  cy: cytoscape.Core,
  boxes: BandBox[],
  onChange?: () => void
): BandOverlay {
  // Absolutely-positioned layer inside #cy (which is position:relative). We move
  // the whole layer with cytoscape's pan/zoom rather than repositioning each box.
  const layer = document.createElement("div");
  layer.className = "band-layer";

  // All card DOM elements (html-labels) live under `container`; toggle
  // fade/highlight on them by data-table on use-case hover.
  const allCards = (): HTMLElement[] =>
    Array.from(container.querySelectorAll<HTMLElement>(".card"));

  // The band currently highlighted (hover OR pin), remembered so `sync` can RE-APPLY
  // its card classes after the html-label plugin regenerates card DOM on a render -
  // which would otherwise wipe the highlight (the classes live on the card overlays,
  // outside the plugin's knowledge; the band HEAD is a separate element and survives).
  let activeBox: BandBox | null = null;

  // Toggle the uc-hl / uc-faded classes for `box`'s members onto the (current) cards.
  // Split out of hoverBand so `sync` can cheaply re-apply it every render.
  const applyCardClasses = (box: BandBox): void => {
    const members = new Set(box.members);
    for (const card of allCards()) {
      const t = card.getAttribute("data-table") ?? "";
      card.classList.toggle("uc-hl", members.has(t));
      card.classList.toggle("uc-faded", !members.has(t));
    }
  };

  const clearHover = (): void => {
    activeBox = null;
    allCards().forEach((c) => c.classList.remove("uc-faded", "uc-hl"));
    layer.querySelectorAll(".band-head.active").forEach((h) => h.classList.remove("active"));
    // Let the caller mirror the (now-cleared) state onto the minimap (design/39
    // Task 2a). Cheap; a no-op when there is no minimap.
    onChange?.();
  };

  const hoverBand = (box: BandBox, headEl: HTMLElement): void => {
    clearHover();
    headEl.classList.add("active");
    applyCardClasses(box);
    activeBox = box; // remembered so `sync` re-applies it across card regens
    onChange?.(); // mirror the new use-case hl/fade onto the minimap
  };

  // table (drawn in this band) -> its band header, so a card hover reveals the
  // use case that OWNS the card. Cards render asynchronously (node-html-label), so
  // we do NOT bind to card DOM here; the caller drives hoverTable from cytoscape's
  // node mouseover, which fires regardless of DOM timing.
  const bandByTable = new Map<string, { box: BandBox; head: HTMLElement }>();
  // use-case NAME -> its band header, so the right-pane use-case list can drive the
  // same highlight a band-header hover does.
  const bandByName = new Map<string, { box: BandBox; head: HTMLElement }>();

  // One-line explanation shown inline on the catch-all band header (and as its
  // native tooltip), so the reader understands it is not a real use case but a
  // bucket for gold tables the first-pass `tables:` draft has not yet assigned.
  const UNASSIGNED_CAPTION = "gold tables not yet assigned to a use case";

  for (const box of boxes) {
    const isUnassigned = box.name === UNASSIGNED_BAND;
    const head = document.createElement("div");
    head.className = "band-head" + (isUnassigned ? " unassigned" : "");
    head.dataset["uc"] = box.name;
    if (isUnassigned) head.title = UNASSIGNED_CAPTION;
    // model-space geometry; the layer transform maps it to screen space.
    head.style.left = `${box.x}px`;
    head.style.top = `${box.y}px`;
    head.style.width = `${box.width}px`;

    const statusChip =
      box.status && !isUnassigned
        ? `<span class="band-status" data-uc-status="${esc(box.status)}">${esc(box.status)}</span>`
        : "";
    const chipStrip =
      box.consumes.length > 0
        ? `<span class="band-chips">consumes ${box.consumes
            .map((d) => `<span class="band-chip">${esc(d)}</span>`)
            .join("")}</span>`
        : "";
    // The catch-all band carries a muted inline caption instead of a status chip,
    // reinforcing that it is a bucket, not a planned use case.
    const caption = isUnassigned
      ? `<span class="band-caption">${esc(UNASSIGNED_CAPTION)}</span>`
      : "";
    head.innerHTML =
      `<span class="band-label">${esc(box.name)}</span>` + statusChip + caption + chipStrip;

    head.addEventListener("mouseenter", () => hoverBand(box, head));
    head.addEventListener("mouseleave", clearHover);
    layer.appendChild(head);

    for (const t of box.tables) bandByTable.set(t, { box, head });
    bandByName.set(box.name, { box, head });
  }

  container.appendChild(layer);

  const hoverTable = (table: string): void => {
    const b = bandByTable.get(table);
    if (b) hoverBand(b.box, b.head);
  };

  // Returns whether the named use case actually has a band to highlight, so a
  // caller can avoid pinning an unmapped use case (which would light up nothing).
  const hoverUseCaseByName = (name: string): boolean => {
    const b = bandByName.get(name);
    if (!b) return false;
    hoverBand(b.box, b.head);
    return true;
  };

  // Keep the layer glued to cytoscape's pan/zoom. `render` fires on every
  // pan/zoom/fit, so the headers stay pinned to their cards.
  const sync = (): void => {
    const pan = cy.pan();
    const zoom = cy.zoom();
    layer.style.transform = `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`;
    // A render often means the html-label plugin just regenerated card DOM; re-apply
    // the active band's card classes so a pinned/hovered highlight survives that regen.
    // Guarded to when a highlight is active, so the common (no-highlight) render path
    // stays a bare transform.
    if (activeBox) applyCardClasses(activeBox);
  };
  sync();
  cy.on("render", sync);

  return {
    hoverTable,
    hoverUseCaseByName,
    clearHover,
    destroy: () => {
      cy.off("render", sync);
      layer.remove();
    },
  };
}

// ============================================================
// Navigator (minimap) + directional overflow indicators (unit / L1 ER)
// ============================================================
// design/38's earlier "no minimap" call is SUPERSEDED by the 2026-07-11 navigator
// item (§4): a hand-rolled DOM+canvas DLT/Lakeflow-style navigator (MIT-only, no
// cytoscape-navigator/jQuery). Scoped to unit mode like the band overlay; both are
// rebuilt in doUnitLayout and torn down in destroy() before cy.destroy().

export interface EdgeIndicators {
  destroy: () => void;
}

export interface Minimap {
  /**
   * Redraw the minimap's node rects so they mirror the main diagram's current
   * highlight/fade state (use-case hover, FK column/edge highlight, pins). Cheap
   * (small N); called whenever that state changes. No-op on the inert handle.
   */
  refresh: () => void;
  destroy: () => void;
}

/** Inert handle for the degenerate guard (0-size content / viewport under jsdom). */
const INERT_OVERLAY = { destroy: () => {} };
/** Inert minimap handle (adds refresh() so the no-DOM guard still satisfies Minimap). */
const INERT_MINIMAP: Minimap = { refresh: () => {}, destroy: () => {} };

/**
 * Directional edge-shadow overflow indicators: four absolutely-positioned,
 * pointer-events:none vignettes on the #cy container, toggled `.on` when the
 * current viewport `cy.extent()` shows there is more content past that edge
 * (compared to the content bbox). A top-anchored tall ER thus shows a "more
 * below, pan down" cue at rest. Synced on cy's `render` (fires on pan/zoom/fit).
 */
export function createEdgeIndicators(
  container: HTMLElement,
  cy: cytoscape.Core,
  contentBB: ContentBB
): EdgeIndicators {
  if (contentBB.w <= 0 || cy.width() <= 0) return INERT_OVERLAY;

  const mk = (side: string): HTMLElement => {
    const el = document.createElement("div");
    el.className = `cy-overflow ${side}`;
    container.appendChild(el);
    return el;
  };
  const top = mk("top");
  const bottom = mk("bottom");
  const left = mk("left");
  const right = mk("right");

  const sync = (): void => {
    const ext = cy.extent();
    top.classList.toggle("on", ext.y1 > contentBB.y1 + 1);
    bottom.classList.toggle("on", ext.y2 < contentBB.y2 - 1);
    left.classList.toggle("on", ext.x1 > contentBB.x1 + 1);
    right.classList.toggle("on", ext.x2 < contentBB.x2 - 1);
  };
  sync();
  cy.on("render", sync);

  return {
    destroy: () => {
      cy.off("render", sync);
      top.remove();
      bottom.remove();
      left.remove();
      right.remove();
    },
  };
}

const MINIMAP_W = 230; // navigator thumbnail MAX width (CSS px)
const MINIMAP_H = 260; // navigator thumbnail MAX height (CSS px)

/**
 * How a table currently reads in the main diagram, so the minimap can mirror it.
 *  - "hl"     highlighted (use-case member, or an FK/PK-highlighted endpoint)
 *  - "faded"  dimmed (a non-member while some highlight is active)
 *  - "normal" at rest (no highlight active)
 */
type NodeVisual = "hl" | "faded" | "normal";

/**
 * Read a table's current visual from the live DOM + the active FK-highlight set.
 * The card wrapper carries `.uc-hl`/`.uc-faded` (toggled by the band overlay);
 * FK-highlighted tables come from the module-local highlight state (they are not
 * reflected on the card wrapper). A card with neither, while nothing is faded, is
 * "normal". Purely a read; the minimap never mutates card classes.
 */
function tableVisual(
  container: HTMLElement,
  table: string,
  fkTables: Set<string>
): NodeVisual {
  if (fkTables.has(table)) return "hl";
  const card = container.querySelector<HTMLElement>(
    `.card[data-table="${cssEscape(table)}"]`
  );
  if (card?.classList.contains("uc-hl")) return "hl";
  if (card?.classList.contains("uc-faded")) return "faded";
  return "normal";
}

/**
 * DLT/Lakeflow-style navigator (minimap): a small canvas thumbnail of the whole
 * ER (node rects drawn to scale, each labelled with its table name) with a
 * draggable viewport frame (from cy.extent()). Bottom-left corner, clear of the
 * bottom-right zoom widget.
 *
 * The canvas is redrawn on rebuild AND whenever the diagram's highlight/fade
 * state changes (via `refresh()`), so a highlighted table reads emphasized and a
 * faded one dimmed, mirroring the main diagram. It is DPR-aware so both the rects
 * and the table-name text stay crisp on retina. The frame follows the viewport on
 * cy's `render` hook. Dragging the frame pans the canvas: minimap px -> model
 * center -> cy.pan(). Pointer capture is taken on the minimap element (NOT
 * document) so teardown is leak-free.
 *
 * `fkTablesGetter` returns the set of table names currently FK/PK-highlighted (not
 * reflected on the card wrapper, so it cannot be read from the DOM); the minimap
 * unions it with the DOM `.uc-hl`/`.uc-faded` state to decide each rect's look.
 */
export function createMinimap(
  container: HTMLElement,
  cy: cytoscape.Core,
  contentBB: ContentBB,
  fkTablesGetter?: () => Set<string>
): Minimap {
  if (contentBB.w <= 0 || cy.width() <= 0) return INERT_MINIMAP;

  // Uniform scale so the whole content bbox fits the thumbnail; height derives.
  // Uniform scale that fits the content within the MAX width AND height, then size
  // the box to the SCALED content (both dimensions derived) so it tight-wraps the
  // thumbnail. A tall/narrow ER thus gets a tall/narrow minimap with no wasted
  // horizontal space, instead of a fixed-width box with an empty right margin.
  const s = Math.min(MINIMAP_W / contentBB.w, MINIMAP_H / contentBB.h);
  const mw = Math.max(1, Math.round(contentBB.w * s));
  const mh = Math.max(1, Math.round(contentBB.h * s));

  const box = document.createElement("div");
  box.className = "cy-minimap";
  box.style.width = `${mw}px`;
  box.style.height = `${mh}px`;

  const canvas = document.createElement("canvas");
  canvas.className = "cy-minimap-canvas";
  const dpr = (typeof window !== "undefined" && window.devicePixelRatio) || 1;
  canvas.width = Math.round(mw * dpr);
  canvas.height = Math.round(mh * dpr);
  canvas.style.width = `${mw}px`;
  canvas.style.height = `${mh}px`;

  const frame = document.createElement("div");
  frame.className = "cy-minimap-frame";

  // Caption: a small "Overview" label + gold/core legend dots so it is obvious
  // what the thumbnail is (a map of the whole ER) and what its colours mean.
  // Absolutely positioned OVER the canvas top with pointer-events:none, so it
  // never shifts the canvas origin (the frame drag math maps box px -> model
  // coords from the box's own top-left, which must stay the canvas top-left).
  const caption = document.createElement("div");
  caption.className = "cy-minimap-caption";
  caption.innerHTML =
    `<span class="cy-minimap-title">Overview</span>` +
    `<span class="cy-minimap-legend">` +
    `<span class="cy-minimap-dot gold" title="Gold / outcome"></span>` +
    `<span class="cy-minimap-dot core" title="Core / silver"></span>` +
    `</span>`;

  box.appendChild(canvas);
  box.appendChild(frame);
  box.appendChild(caption);
  container.appendChild(box);

  // getContext is wrapped because jsdom throws for a 2d context (no canvas pkg);
  // a real browser returns the context, jsdom degrades to a frame-only navigator.
  let ctx: CanvasRenderingContext2D | null = null;
  try {
    ctx = canvas.getContext("2d");
  } catch {
    ctx = null;
  }
  const goldColor = getCssVar("--gold-stroke") || "#e0834f";
  const coreColor = getCssVar("--core-stroke") || "#6a7f96";

  // Precompute each node's thumbnail rect + colour + name ONCE (positions are
  // static until the next relayout, which rebuilds the whole minimap). refresh()
  // then only re-reads the cheap per-node visual state and repaints (no bbox
  // reads). Names are threaded onto the box `title` (a DOM hook the e2e suite can
  // assert without pixel-reading the canvas) and onto a `data-tables` attribute.
  interface Rect { name: string; label: string; x: number; y: number; w: number; h: number; base: string }
  const rects: Rect[] = [];
  // The DRAWN label drops the redundant "gold_" prefix (the fill colour already
  // means gold), leaving the distinctive part; the hover tooltip keeps the FULL
  // name (design/39 user choice).
  const drawLabel = (full: string): string => full.replace(/^gold_/, "");
  cy.nodes().forEach((n) => {
    const bb = n.boundingBox();
    const name = String(n.data("label") ?? n.data("id") ?? "");
    rects.push({
      name,
      label: drawLabel(name),
      x: (bb.x1 - contentBB.x1) * s,
      y: (bb.y1 - contentBB.y1) * s,
      w: Math.max(1, bb.w * s),
      h: Math.max(1, bb.h * s),
      base: n.data("cls") === "gold" ? goldColor : coreColor,
    });
  });
  const names = rects.map((r) => r.name).filter((nm) => nm.length > 0);
  const allNames = names.join(", ");
  box.title = allNames;
  box.dataset["tables"] = names.join(",");

  // A rect wide/tall enough for any legible glyph gets its name drawn inside;
  // smaller ones fall back to the colour rect alone (the box `title` still lists
  // every name as a native tooltip). Font is small + DPR-aware (the ctx transform
  // scales by dpr, so glyphs render at device resolution and stay crisp).
  const MIN_LABEL_W = 26; // px of rect width below which no text fits legibly
  const MIN_LABEL_H = 8;
  const FONT_PX = 7;
  const LINE_PX = FONT_PX + 2; // line height for wrapped labels

  // Wrap a (prefix-stripped) label across the box: break preferentially AFTER
  // underscores (so `control_tower` -> "control_" / "tower"), pack segments
  // greedily into lines that fit the box width, ellipsize any segment too long for
  // one line, and clamp to the lines that fit the box height. Multi-line so a tall
  // box shows the full distinctive name (design/39); the full name is always on the
  // hover tooltip regardless.
  const wrapLabel = (
    c: CanvasRenderingContext2D,
    text: string,
    maxPx: number,
    maxLines: number
  ): string[] => {
    const ellipsize = (t: string): string => {
      let s = t;
      while (s.length > 1 && c.measureText(s + "…").width > maxPx) s = s.slice(0, -1);
      return s.length > 0 ? s + "…" : "";
    };
    const segs = text.match(/[^_]+_?/g) ?? [text]; // keep the trailing underscore
    const lines: string[] = [];
    let cur = "";
    for (const seg of segs) {
      if (!cur) cur = seg;
      else if (c.measureText(cur + seg).width <= maxPx) cur += seg;
      else {
        lines.push(cur);
        cur = seg;
      }
    }
    if (cur) lines.push(cur);
    for (let i = 0; i < lines.length; i++) {
      if (c.measureText(lines[i]).width > maxPx) lines[i] = ellipsize(lines[i]);
    }
    if (lines.length > maxLines) {
      lines.length = maxLines;
      const last = lines[maxLines - 1];
      if (!last.endsWith("…")) lines[maxLines - 1] = ellipsize(last);
    }
    return lines;
  };

  // Repaint all rects for the CURRENT highlight/fade state. Cheap: no layout
  // reads, just per-node DOM class lookups (small N). Highlighted rects render at
  // full opacity with a gold ring; faded ones dim; normal ones as-is.
  const draw = (): void => {
    const fkTables = fkTablesGetter ? fkTablesGetter() : new Set<string>();
    // DOM hook: mirror the CURRENT highlighted-table set onto a data attribute the
    // e2e suite can read (canvas pixels are hard to assert). Kept in sync with the
    // canvas paint below. Set BEFORE the ctx guard so the signal is observable even
    // where the canvas can't paint (jsdom). Empty string = nothing highlighted.
    const hl = rects
      .filter((r) => tableVisual(container, r.name, fkTables) === "hl")
      .map((r) => r.name);
    box.dataset["hl"] = hl.join(",");
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, mw, mh);
    ctx.textBaseline = "middle";
    ctx.font = `${FONT_PX}px var(--font-ui, sans-serif)`;
    for (const r of rects) {
      const vis = tableVisual(container, r.name, fkTables);
      ctx.globalAlpha = vis === "faded" ? 0.28 : 1;
      ctx.fillStyle = r.base;
      ctx.fillRect(r.x, r.y, r.w, r.h);
      if (vis === "hl") {
        ctx.globalAlpha = 1;
        ctx.strokeStyle = goldColor;
        ctx.lineWidth = 1.5;
        ctx.strokeRect(r.x + 0.75, r.y + 0.75, r.w - 1.5, r.h - 1.5);
      }
      // Table name inside the box when it can hold a legible glyph; else skip
      // (the box title still lists every name). The (gold_-stripped) label wraps
      // across the box and is vertically centred; text colour contrasts the fill.
      if (r.label && r.w >= MIN_LABEL_W && r.h >= MIN_LABEL_H) {
        const maxLines = Math.max(1, Math.floor((r.h - 2) / LINE_PX));
        const lines = wrapLabel(ctx, r.label, r.w - 4, maxLines);
        if (lines.length > 0) {
          ctx.globalAlpha = vis === "faded" ? 0.4 : 1;
          ctx.fillStyle = "#ffffff";
          let ty = r.y + Math.max(LINE_PX / 2 + 1, (r.h - lines.length * LINE_PX) / 2 + LINE_PX / 2);
          for (const ln of lines) {
            ctx.fillText(ln, r.x + 2, ty);
            ty += LINE_PX;
          }
        }
      }
    }
    ctx.globalAlpha = 1;
  };
  draw();

  // Position the viewport frame from cy.extent(), mapped by s and clamped to the
  // thumbnail. Runs on every `render` (pan/zoom/fit), so it follows automatically.
  const syncFrame = (): void => {
    const ext = cy.extent();
    const fx = Math.max(0, (ext.x1 - contentBB.x1) * s);
    const fy = Math.max(0, (ext.y1 - contentBB.y1) * s);
    const fw = Math.min(mw - fx, (ext.x2 - ext.x1) * s);
    const fh = Math.min(mh - fy, (ext.y2 - ext.y1) * s);
    frame.style.left = `${fx}px`;
    frame.style.top = `${fy}px`;
    frame.style.width = `${Math.max(0, fw)}px`;
    frame.style.height = `${Math.max(0, fh)}px`;
  };
  syncFrame();
  cy.on("render", syncFrame);

  // Pan the canvas to a minimap point. minimap px -> model coords (via s +
  // contentBB origin) -> pan so that model point sits at the viewport centre.
  // clampPan then keeps the content from being dragged entirely off-screen via
  // the frame drag (design/38 §2), just as the canvas-pan handler does.
  const panTo = (px: number, py: number): void => {
    const z = cy.zoom();
    const cx = contentBB.x1 + px / s;
    const cyModel = contentBB.y1 + py / s;
    cy.pan({ x: cy.width() / 2 - cx * z, y: cy.height() / 2 - cyModel * z });
    clampPan(cy, contentBB);
  };

  let dragging = false;
  const localPoint = (ev: PointerEvent): { px: number; py: number } => {
    const r = box.getBoundingClientRect();
    return {
      px: Math.max(0, Math.min(mw, ev.clientX - r.left)),
      py: Math.max(0, Math.min(mh, ev.clientY - r.top)),
    };
  };
  const onDown = (ev: PointerEvent): void => {
    // Take capture on the minimap element itself (never document) so the drag is
    // leak-free on teardown. stopPropagation/preventDefault so the gesture pans
    // the minimap, not the cytoscape canvas underneath.
    ev.stopPropagation();
    ev.preventDefault();
    dragging = true;
    box.setPointerCapture?.(ev.pointerId);
    const { px, py } = localPoint(ev);
    panTo(px, py);
  };
  // The box (rect) under a minimap point, for the hover tooltip. Topmost-last-drawn
  // wins on overlap (matches the paint order).
  const rectAt = (px: number, py: number): Rect | undefined => {
    for (let i = rects.length - 1; i >= 0; i--) {
      const r = rects[i];
      if (px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h) return r;
    }
    return undefined;
  };
  const onMove = (ev: PointerEvent): void => {
    const { px, py } = localPoint(ev);
    if (!dragging) {
      // Hover (not dragging): show the FULL table name of the box under the cursor
      // (design/39 - the drawn label drops the gold_ prefix + may wrap, so the
      // tooltip is where the complete, unabbreviated name is always available).
      const r = rectAt(px, py);
      box.title = r ? r.name : allNames;
      return;
    }
    ev.stopPropagation();
    ev.preventDefault();
    panTo(px, py);
  };
  const onUp = (ev: PointerEvent): void => {
    if (!dragging) return;
    ev.stopPropagation();
    dragging = false;
    box.releasePointerCapture?.(ev.pointerId);
  };
  box.addEventListener("pointerdown", onDown);
  box.addEventListener("pointermove", onMove);
  box.addEventListener("pointerup", onUp);
  box.addEventListener("pointercancel", onUp);

  return {
    refresh: draw,
    destroy: () => {
      cy.off("render", syncFrame);
      box.removeEventListener("pointerdown", onDown);
      box.removeEventListener("pointermove", onMove);
      box.removeEventListener("pointerup", onUp);
      box.removeEventListener("pointercancel", onUp);
      box.remove();
    },
  };
}

// ============================================================
// Zoom / pan widget (bottom-right overlay)
// ============================================================

export interface ZoomWidget {
  destroy: () => void;
}

/**
 * Bottom-right zoom/pan control overlay, an absolutely-positioned child of
 * `container` (the #cy element, position:relative, the same anchor as .cy-empty
 * and the band layer). Real <button>s (aria-label + title) for zoom in / out /
 * fit-to-content / reset-to-default plus a live % readout. Keyboard +/-/0 is bound
 * to `container` (made focusable via tabIndex), NOT document, so it never leaks a
 * global listener. destroy() removes every listener (click, keydown, cy zoom) and
 * the DOM node, so a re-mount cannot duplicate the widget (teardown discipline).
 */
export function createZoomWidget(
  container: HTMLElement,
  cy: cytoscape.Core,
  resetView: () => void,
  fitView?: () => void
): ZoomWidget {
  const wrap = document.createElement("div");
  wrap.className = "cy-zoom";
  const pct = () => `${Math.round(cy.zoom() * 100)}%`;
  wrap.innerHTML =
    `<button type="button" class="cy-zoom-btn" data-act="in" aria-label="Zoom in" title="Zoom in">+</button>` +
    `<button type="button" class="cy-zoom-btn" data-act="out" aria-label="Zoom out" title="Zoom out">&minus;</button>` +
    `<span class="cy-zoom-pct" aria-live="polite" title="Current zoom">${pct()}</span>` +
    `<button type="button" class="cy-zoom-btn" data-act="fit" aria-label="Fit to content" title="Fit whole diagram">&#x26F6;</button>` +
    `<button type="button" class="cy-zoom-btn" data-act="reset" aria-label="Reset zoom" title="Reset to default zoom">&#x21BA;</button>`;

  const readout = wrap.querySelector<HTMLElement>(".cy-zoom-pct")!;
  const updatePct = (): void => {
    readout.textContent = pct();
  };

  // multiplicative zoom about the viewport centre; cytoscape clamps to min/max.
  const zoomBy = (factor: number): void => {
    cy.zoom({
      level: cy.zoom() * factor,
      renderedPosition: { x: cy.width() / 2, y: cy.height() / 2 },
    });
  };

  const onClick = (ev: MouseEvent): void => {
    const act = (ev.target as HTMLElement).closest<HTMLElement>("[data-act]")?.dataset["act"];
    if (act === "in") zoomBy(1.2);
    else if (act === "out") zoomBy(1 / 1.2);
    else if (act === "fit")
      (fitView ?? (() => cy.animate({ fit: { eles: cy.elements(), padding: FIT_PADDING }, duration: 180 })))();
    else if (act === "reset") resetView();
  };
  wrap.addEventListener("click", onClick);

  // Keyboard +/-/0 scoped to the container (focusable), never to document.
  container.tabIndex = 0;
  const onKey = (ev: KeyboardEvent): void => {
    if (ev.key === "+" || ev.key === "=") zoomBy(1.2);
    else if (ev.key === "-" || ev.key === "_") zoomBy(1 / 1.2);
    else if (ev.key === "0") resetView();
    else return;
    ev.preventDefault();
  };
  container.addEventListener("keydown", onKey);

  cy.on("zoom", updatePct);
  container.appendChild(wrap);

  return {
    destroy: () => {
      wrap.removeEventListener("click", onClick);
      container.removeEventListener("keydown", onKey);
      cy.off("zoom", updatePct);
      wrap.remove();
    },
  };
}

const SVG_NS = "http://www.w3.org/2000/svg";

interface ConsumesRail {
  /** Reveal the arcs from a hovered gold card down to the core tables it consumes. */
  drawFor: (goldTable: string) => void;
  /** Clear the arcs + lit state (mouseout). */
  clear: () => void;
  /** Screen px the rail (+ arc breathing room) occupies at the viewport bottom, so
   *  the pan clamp can reserve it and the last row of cards stays scroll-clear of it. */
  bottomReserve: () => number;
  destroy: () => void;
}

/**
 * The L1 "consumes" rail: a bottom strip listing the CORE (silver) tables the
 * unit's tables consume (each table's `consumes_tables`), with bezier
 * ARCS drawn from a hovered gold card down to the tables it consumes - the L0
 * consumption-tier UX (overview.ts drawEdgesFor) brought into the per-unit ER.
 * For a gold view that set is FK-reachable, not only what its SQL joins: the core
 * tables it reads plus every core table reached by following declared FKs from a
 * non-core table it reads (see docs/anatomy-of-a-model.md). An ingredient /
 * association card's set is narrower, its own direct FKs into core.
 * The list is always shown; arcs are hover-only. Returns null for a unit whose
 * gold views read no core table (silver domains, unmapped golds), so there is no
 * rail. Uses RENDERED cytoscape coords (already pan/zoom-adjusted) for the card
 * anchor, and re-draws on cy "render" so the arcs stay glued while panning.
 */
function createConsumesRail(
  container: HTMLElement,
  cy: cytoscape.Core,
  unit: Unit
): ConsumesRail | null {
  const cardToCore = new Map<string, string[]>(); // gold OR association table -> [core table]
  const coreDomain = new Map<string, string>(); // core table -> its domain
  for (const t of unit.tables) {
    // Include gold views (consume core via SQL) AND association/ingredient tables like
    // promotion_scope (reach core via declared FKs). Both carry `consumes_tables`; a table
    // that reaches no core table has [] and is skipped, so it draws no arcs.
    const ct = t.consumes_tables ?? [];
    if (ct.length === 0) continue;
    cardToCore.set(t.name, ct.map((c) => c.table));
    for (const c of ct) coreDomain.set(c.table, c.unit);
  }
  if (coreDomain.size === 0) return null;

  const rail = document.createElement("div");
  rail.className = "consumes-rail";
  rail.innerHTML = `<span class="cr-label">consumes silver</span>`;
  const chips = new Map<string, HTMLElement>();
  for (const tbl of [...coreDomain.keys()].sort()) {
    const chip = document.createElement("div");
    chip.className = "cr-chip";
    chip.dataset["table"] = tbl;
    chip.innerHTML =
      `<span class="cr-tbl">${esc(tbl)}</span>` +
      `<span class="cr-dom">${esc(coreDomain.get(tbl) ?? "")}</span>`;
    chips.set(tbl, chip);
    rail.appendChild(chip);
  }
  container.appendChild(rail);

  const svg = document.createElementNS(SVG_NS, "svg");
  svg.setAttribute("class", "consumes-arcs");
  container.appendChild(svg);

  let activeGold: string | null = null;
  const wipe = (): void => {
    while (svg.firstChild) svg.removeChild(svg.firstChild);
  };

  const draw = (): void => {
    wipe();
    if (!activeGold) return;
    const el = cy.getElementById(activeGold);
    if (el.empty()) return;
    const box = container.getBoundingClientRect();
    svg.setAttribute("viewBox", `0 0 ${box.width} ${box.height}`);
    svg.setAttribute("width", String(box.width));
    svg.setAttribute("height", String(box.height));
    const g = el.renderedBoundingBox(); // rendered = relative to the canvas/container
    const sx = (g.x1 + g.x2) / 2;
    const sy = g.y2; // bottom-centre of the gold card
    for (const tbl of cardToCore.get(activeGold) ?? []) {
      const chip = chips.get(tbl);
      if (!chip) continue;
      chip.classList.add("lit");
      const cr = chip.getBoundingClientRect();
      const tx = cr.left + cr.width / 2 - box.left;
      const ty = cr.top - box.top; // top-centre of the chip
      const midY = (sy + ty) / 2;
      const path = document.createElementNS(SVG_NS, "path");
      path.setAttribute("d", `M ${sx} ${sy} C ${sx} ${midY}, ${tx} ${midY}, ${tx} ${ty}`);
      path.setAttribute("class", "cr-arc");
      svg.appendChild(path);
    }
  };

  const clear = (): void => {
    activeGold = null;
    rail.classList.remove("active");
    chips.forEach((c) => c.classList.remove("lit"));
    wipe();
  };

  const drawFor = (goldTable: string): void => {
    if (!cardToCore.has(goldTable)) {
      clear();
      return;
    }
    activeGold = goldTable;
    rail.classList.add("active");
    chips.forEach((c) => c.classList.remove("lit"));
    draw();
  };

  const sync = (): void => {
    if (activeGold) draw();
  };
  cy.on("render", sync);

  return {
    drawFor,
    clear,
    // rail's own height + its 10px bottom offset (see .consumes-rail CSS) + ~34px of
    // breathing room so the arcs into the top row of chips are not cramped.
    bottomReserve: () => rail.offsetHeight + 10 + 34,
    destroy: () => {
      cy.off("render", sync);
      rail.remove();
      svg.remove();
    },
  };
}

/**
 * Mount a cytoscape view into `container`.
 *  - mode "graph": whole-model overview (opt-in power-user view)
 *  - mode "unit": the tables + relationships of one unit (L1 ER)
 * onTableTap fires when a table node is tapped (drill to L2 in unit mode).
 */
export function mountGraph(
  container: HTMLElement,
  model: Model,
  mode: "graph" | "unit",
  unitName: string | undefined,
  onTableTap: (tableId: string) => void
): GraphHandle {
  const cy = cytoscape({
    container,
    style: BASE_STYLE,
    wheelSensitivity: 0.3,
    minZoom: 0.2,
    maxZoom: 4,
  });

  // e2e handle: expose the cytoscape instance so the real-browser Playwright
  // suite can drive canvas interactions precisely (emit an edge mouseover, read
  // cy.zoom(), assert instance identity across a route change). Gated so it NEVER
  // ships to real users: on in a Vite dev build, or when the page is loaded with
  // the `?e2e=1` harness flag (which `vite preview` honours for the specs but no
  // real visitor passes). A bare production load leaves window.__cy undefined.
  if (isE2eExposed()) {
    (window as unknown as { __cy?: cytoscape.Core }).__cy = cy;
  }

  // Cards sit at deterministic packed positions; grabbing one would drag it off
  // the masonry grid. Ungrabify so a drag pans the canvas instead (reinforcing
  // pan as the primary gesture) and positions stay authoritative.
  cy.autoungrabify(true);

  applyHtmlLabels(cy);

  const level = mode === "graph" ? "overview" : "unit";
  const { nodes, edges } = modelToElements(model, level, unitName);
  const nodeClass = mode === "graph" ? "overview-node" : "table-node";
  const nodeEls = nodes.map((n) => {
    if (mode === "unit") {
      const columns = (n.data as { columns?: ColLike[] }).columns ?? [];
      return { ...n, classes: nodeClass, data: { ...n.data, h: cardHeight(columns) } };
    }
    return { ...n, classes: nodeClass };
  });
  cy.add([...nodeEls, ...edges]);

  const ec = edgeColor();
  cy.style()
    .selector("edge")
    .style({ "line-color": ec, "target-arrow-color": ec } as cytoscape.Css.Edge)
    .update();

  // Re-measure the container before laying out. The container is un-hidden just
  // before mount; forcing cytoscape to re-read its (now real) size here means the
  // preset/fcose layout and fit() below use the correct dimensions rather than a
  // stale 0x0 read taken while the element was still hidden.
  cy.resize();

  // Use-case swimlane bands (unit mode only). Grouping is a pure partition; when
  // it has no real band (package with no `tables:` mapping) we fall back to the
  // flat masonry unchanged. `bandOverlay` is the DOM layer for band headers +
  // chip strips; null in fallback / graph mode. The band grouping is computed once
  // (data is static) but the LAYOUT + overlay are (re)built by doUnitLayout so the
  // initial mount and relayout() share one code path.
  let bandOverlay: BandOverlay | null = null;
  // The use case whose band highlight is currently shown (a hover or a pin). The
  // highlight is transient DOM state on the cards, so a relayout that rebuilds the
  // band overlay + regenerates the cards wipes it; doUnitLayout re-asserts this so
  // the highlight survives a window resize / panel reflow (M1).
  let activeUseCase: string | null = null;
  let minimap: Minimap | null = null;
  let edgeIndicators: EdgeIndicators | null = null;
  // Bottom "consumes silver" rail + hover arcs (unit mode, gold packages only).
  let consumesRail: ConsumesRail | null = null;
  const unit = mode === "unit" ? model.units.find((u) => u.name === unitName) : undefined;
  const grouping = unit ? groupTablesByUseCase(unit) : null;

  // Column -> relationship map for the unit ER (design/39: hover the COLUMN, not
  // the thin edge). Keyed `${table}|${col}` -> the joined counterpart(s):
  // each entry carries the connecting edge id + the OTHER table/column so hovering
  // either endpoint column knows what it joins to. Built from the model
  // relationships, filtered to edges whose BOTH endpoints are in-unit (mirrors
  // elements.ts, so a map key always resolves to a real edge + two real cards).
  interface ColLink { edgeId: string; otherTable: string; otherCol: string }
  const colLinks = new Map<string, ColLink[]>();
  if (unit) {
    const inUnit = new Set(unit.tables.map((t) => t.name));
    const key = (table: string, col: string): string => `${table}|${col}`;
    const addLink = (t: string, c: string, link: ColLink): void => {
      const k = key(t, c);
      const list = colLinks.get(k);
      if (list) list.push(link);
      else colLinks.set(k, [link]);
    };
    for (const r of unit.relationships) {
      if (!inUnit.has(r.parent_table) || !inUnit.has(r.child_table)) continue;
      const edgeId = `${r.parent_table}->${r.child_table}`;
      // A relationship pairs parent_cols[i] with child_cols[i]; index-align them
      // (defensive `?? ""` if a model.json row has a length mismatch).
      const n = Math.max(r.parent_cols.length, r.child_cols.length);
      for (let i = 0; i < n; i++) {
        const pc = r.parent_cols[i] ?? r.parent_cols[0] ?? "";
        const cc = r.child_cols[i] ?? r.child_cols[0] ?? "";
        if (!pc || !cc) continue;
        // Hovering the PARENT (PK) column knows the child (FK) counterpart, and
        // vice-versa, the highlight is symmetric on either endpoint.
        addLink(r.parent_table, pc, { edgeId, otherTable: r.child_table, otherCol: cc });
        addLink(r.child_table, cc, { edgeId, otherTable: r.parent_table, otherCol: pc });
      }
    }
  }

  // ---- relationship highlight state (design/39) ----
  // A single ACTIVE highlight describes which column rows + connecting edges are
  // lit. Set by a column-row hover (transient) OR an edge tap (pinned). The lit
  // columns are published onto each participating node's `hlCols` DATA (see
  // applyRel), because the node-html-label plugin caches per-node markup and only
  // re-runs the template on a data change - so `.col-hl` gets baked into the markup
  // and then survives every subsequent pan/zoom re-render on its own.
  interface RelHighlight {
    /** table -> the specific column rows to light with `.col-hl`. */
    cols: Map<string, Set<string>>;
    /** connecting edge ids to add `.highlighted` to. */
    edges: Set<string>;
    /** every table participating (drives the card `.uc-hl`-style read + minimap). */
    tables: Set<string>;
  }
  let activeRel: RelHighlight | null = null;
  // When set, activeRel is PINNED (an edge tap): it survives a column-row mouseout
  // and only clears on re-tapping the same edge or tapping the background.
  let pinnedEdge: string | null = null;

  // Tables the relationship highlight currently lights, for the minimap to mirror
  // (the FK highlight is not reflected on the card wrapper classList, unlike the
  // use-case fade, so the minimap reads it from here). Empty set when nothing lit.
  const fkTables = (): Set<string> => activeRel?.tables ?? new Set<string>();

  // The latest content bounding box (rebuilt by every doUnitLayout / relayout).
  // Threaded to the pan-clamp handler so a canvas pan is clamped against the
  // CURRENT geometry, not a stale one (design/38 §2). Null in graph mode / before
  // the first unit layout, when the clamp is a no-op.
  let currentContentBB: ContentBB | null = null;

  // Run the correct unit-mode layout and (re)build the band overlay + navigator
  // for the current container size. Destroys any prior overlays first: their
  // sync() tracks only pan/zoom, not new box geometry / node positions, so a
  // re-pack needs fresh ones. The minimap + edge indicators map against the
  // content bbox produced by the just-run preset layout (independent of zoom).
  const doUnitLayout = (): void => {
    bandOverlay?.destroy();
    bandOverlay = null;
    minimap?.destroy();
    minimap = null;
    edgeIndicators?.destroy();
    edgeIndicators = null;
    consumesRail?.destroy();
    consumesRail = null;
    if (unit) consumesRail = createConsumesRail(container, cy, unit);
    if (grouping && !grouping.fallback) {
      const boxes = layoutUnitBands(cy, container, grouping.ungrouped, grouping.bands);
      // onChange mirrors the band-header hover's use-case hl/fade onto the minimap.
      // Reads the live `minimap` var (created just below on the same rebuild), so a
      // relayout's fresh minimap is the one refreshed.
      bandOverlay = createBandOverlay(container, cy, boxes, () => minimap?.refresh());
    } else {
      layoutUnitGrid(cy); // deterministic masonry columns
    }
    const bb = cy.elements().boundingBox();
    const contentBB: ContentBB = {
      x1: bb.x1, y1: bb.y1, x2: bb.x2, y2: bb.y2, w: bb.w, h: bb.h,
    };
    currentContentBB = contentBB;
    minimap = createMinimap(container, cy, contentBB, fkTables);
    edgeIndicators = createEdgeIndicators(container, cy, contentBB);
    // Re-assert the active use-case highlight onto the freshly rebuilt overlay/cards
    // so a relayout does not leave the panel showing a pin while the canvas is blank.
    if (activeUseCase && bandOverlay) {
      bandOverlay.hoverUseCaseByName(activeUseCase);
      minimap.refresh();
    }
  };

  if (mode === "graph") {
    layoutGraphLayered(cy); // deterministic two-tier layout
  } else {
    doUnitLayout();
  }

  // ---- viewport controls: default-zoom reset + zoom/pan widget ----
  // Distinguish programmatic zoom (applyDefaultZoom / fit) from a user gesture
  // (wheel / widget +/-): a `cy.on("zoom")` handler sets userAdjustedZoom=true
  // only when the change was NOT programmatic. relayout then preserves the user's
  // zoom once set (design/38 §4 zoom-durability); Reset clears it and re-applies
  // the default. `programmaticZoom` brackets every zoom WE trigger.
  let userAdjustedZoom = false;
  let programmaticZoom = false;
  const withProgrammaticZoom = (fn: () => void): void => {
    programmaticZoom = true;
    try {
      fn();
    } finally {
      programmaticZoom = false;
    }
  };
  cy.on("zoom", () => {
    if (!programmaticZoom) userAdjustedZoom = true;
  });

  // ---- pan clamp (design/38 §2) ----
  // Keep the content overlapping the viewport by a margin so a canvas pan (or a
  // minimap frame drag) can never scroll all the tables off into an empty void.
  // clampPan sets cy.pan() when it corrects, which re-fires this `pan` handler;
  // the reentrancy flag stops it recursing. No-op in graph mode / before the first
  // unit layout (currentContentBB is null then).
  let clamping = false;
  // Expand/collapse a card to show ALL columns on hover. A tall card scrolled near the
  // viewport bottom would grow off-screen (below the consumes rail) where the pan clamp
  // forbids scrolling to it. Rather than PAN it into view (which moved the cytoscape hit-
  // box out from under the cursor and caused a 20-30x expand/collapse flicker on bottom
  // cards), CAP the card's column list to the space available below its top; the clipped
  // list is FADED (not scrolled - scrolling a transient hover is an anti-pattern) with a
  // "click to see all N columns" footer, and the full list opens in the side panel on
  // click. The cap is published as one CSS var on the container (only one card is expanded
  // at a time; the col-list inherits it). No pan and no node-geometry change, so this
  // never reflows siblings or fights the hover hit-testing.
  const setExpanded = (node: cytoscape.NodeSingular, on: boolean): void => {
    const cols = node.data("columns");
    if (!Array.isArray(cols) || cols.length === 0) return;
    if (on === (node.data("expanded") === true)) return; // idempotent
    if (!on) {
      node.data({ expanded: false, expandCapped: false });
      container.style.removeProperty("--ordm-expand-max");
      return;
    }
    // Would the fully expanded card overflow the usable viewport bottom (above the rail)?
    // cardTop is the stable, top-anchored node-box top; the label layer is zoom-scaled
    // (screen height = CSS height x z).
    const z = cy.zoom();
    const cardTop = node.renderedBoundingBox().y1; // container-relative, sync, stable
    const rail = consumesRail?.bottomReserve() ?? 0;
    const usableBottom = cy.height() - rail;
    const fullCardPx = cardPxForRows(cols.length) * z; // all columns, no "+more" row
    const capped = cardTop + fullCardPx > usableBottom + 4;
    if (capped) {
      // Cap the col-list so the WHOLE card (header + list + footer) stays on-screen: fit it
      // above the rail when there's room, else fall back to the full viewport bottom so the
      // footer - the "click to see all" indication - is NEVER pushed off-screen.
      // Chrome (header + footer) is CSS px but subtracted from screen-space measurements,
      // so scale it by the zoom - otherwise it under-reserves and the footer overflows.
      const chrome = (CARD_HEADER_PX + CARD_FOOTER_PX) * z;
      const compactPx = (node.data("h") as number) * z; // the at-rest card's screen height
      const roomAboveRail = usableBottom - cardTop;
      const roomInViewport = cy.height() - cardTop;
      const room = roomAboveRail >= compactPx + chrome ? roomAboveRail : roomInViewport;
      // CRITICAL: hovering must never SHRINK the card. If there is not enough room below the
      // card top to show MORE than the compact card already does (plus the footer), keep it
      // compact and rely on click - expanding here would render FEWER columns than at rest.
      if (room <= compactPx + CARD_FOOTER_PX * z) {
        node.data({ expanded: false, expandCapped: false });
        container.style.removeProperty("--ordm-expand-max");
        return;
      }
      const avail = Math.max(24, room - chrome);
      container.style.setProperty("--ordm-expand-max", Math.round(avail / z) + "px");
    } else {
      container.style.removeProperty("--ordm-expand-max");
    }
    node.data({ expanded: true, expandCapped: capped });
  };
  cy.on("pan", () => {
    if (clamping || !currentContentBB) return;
    clamping = true;
    try {
      clampPan(cy, currentContentBB, consumesRail?.bottomReserve() ?? 0);
    } finally {
      clamping = false;
    }
  });

  // Apply the default zoom ONCE, after the initial layout — never as an
  // unconditional tail of relayout (that was the "blink and reset" bug).
  withProgrammaticZoom(() => applyDefaultZoom(cy));

  // Widget Reset: clear the user-adjusted flag and re-apply the default (a
  // deliberate reset gesture), guarded so it does not itself set the flag.
  const resetView = (): void => {
    userAdjustedZoom = false;
    withProgrammaticZoom(() => applyDefaultZoom(cy));
  };
  // Widget Fit is programmatic too (it should not mark the zoom as user-adjusted),
  // but it IS a deliberate whole-diagram view the user asked for, so leave
  // userAdjustedZoom as-is; bracket only so the animate's zoom does not flip it.
  const fitView = (): void => {
    withProgrammaticZoom(() =>
      cy.animate({ fit: { eles: cy.elements(), padding: FIT_PADDING }, duration: 180 })
    );
  };
  const zoomWidget = createZoomWidget(container, cy, resetView, fitView);

  // ---- panel-aware + window reflow ----
  // Re-fit to the current container size. cy.resize() re-reads clientWidth/Height
  // (the panel may have narrowed #cy); the layout then repacks with the corrected
  // fitCols. The user's zoom is PRESERVED once they have manually adjusted it;
  // only until then does a relayout re-apply the default zoom (design/38 §4).
  const relayout = (): void => {
    cy.resize();
    if (mode === "graph") layoutGraphLayered(cy);
    else doUnitLayout();
    if (!userAdjustedZoom) withProgrammaticZoom(() => applyDefaultZoom(cy));
    // After the re-pack (which rebuilt currentContentBB) + any default-zoom pan,
    // clamp so the user's preserved zoom/pan cannot leave the content off-screen
    // against the new geometry (design/38 §2).
    if (currentContentBB) clampPan(cy, currentContentBB, consumesRail?.bottomReserve() ?? 0);
  };
  let resizeTimer: ReturnType<typeof setTimeout> | undefined;
  const debouncedRelayout = (): void => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(relayout, 80);
  };
  window.addEventListener("resize", debouncedRelayout);

  // hover highlight
  cy.on("mouseover", "node", (evt) => {
    const node = evt.target as cytoscape.NodeSingular;
    const nb = node.neighborhood();
    // Only DIM the rest of the diagram when this node actually has in-view relationships to
    // emphasize. A node whose FKs point out of the view (an association like
    // product_relationship, or a gold view) has no in-view edges - fading everything then
    // just made OTHER tables' FK edges vanish (a competitor->competitor_price edge
    // disappeared when hovering an unrelated third table). No in-view edges -> no fade.
    if (nb.edges().nonempty()) {
      cy.elements().not(node).not(nb).addClass("faded");
      nb.edges().addClass("highlighted");
    }
    // Hovering a card also reveals the use case that OWNS it (fade non-members +
    // chip-strip), so the ER's FK neighbourhood and the use-case grouping light
    // up together. BUT when a relationship highlight is active (the user is
    // hovering a key column, or a pin is set), do NOT re-fade: that fade washed
    // out the FK/PK columns before (design/39 fade reconcile). Re-assert the
    // relationship highlight instead so it survives the node mouseover.
    if (activeRel) {
      bandOverlay?.clearHover();
      applyRel();
    } else {
      bandOverlay?.hoverTable(String(node.data("id")));
    }
    // Hovering a card that reaches core arcs down to those silver tables (L0-style): gold
    // views (consume via SQL) AND association/ingredient tables like promotion_scope (via
    // declared FKs). Both carry `consumes_tables`; a table that reaches no core table has
    // none and draws nothing.
    const ct = node.data("consumes_tables");
    if (Array.isArray(ct) && ct.length > 0) consumesRail?.drawFor(String(node.data("id")));
    // Expand the card to ALL columns on hover (the plugin re-renders on this data
    // change). The card floats over neighbours via a raised z-index (styles.css) and
    // does NOT reflow the layout - other cards stay put. Only table cards (have
    // columns) expand; overview chips are unaffected.
    const cols = node.data("columns");
    if (Array.isArray(cols) && cols.length > 0) {
      // Expand to all columns; setExpanded caps + fades a bottom card's list (with a
      // "click to see all" footer) instead of it running off-screen (no pan, no reflow).
      setExpanded(node, true);
    }
  });
  cy.on("mouseout", "node", (evt) => {
    setExpanded(evt.target as cytoscape.NodeSingular, false); // collapse + clear the list cap
    cy.elements().removeClass("faded").removeClass("highlighted");
    if (activeRel) applyRel(); // a live relationship highlight keeps its edges lit
    // A PINNED use case must survive a card hover-out: leaving a card only clears
    // the transient card-hover reveal, never the pin (which persists past mouseleave,
    // matching the panel-row path in main.ts and the relayout re-assert above). Only
    // clear the overlay outright when nothing is pinned. The overlay re-applies the
    // active band's card classes on every render, so this re-assert survives the
    // html-label plugin's card regen (which the class toggles above trigger).
    else if (activeUseCase && bandOverlay) bandOverlay.hoverUseCaseByName(activeUseCase);
    else bandOverlay?.clearHover();
    consumesRail?.clear();
  });

  // ============================================================
  // FK/PK relationship highlight (design/39)
  // ============================================================
  // The trigger is the COLUMN, not the thin edge: cytoscape draws edges UNDER the
  // cards and the node hit-area sits on top, so the FK arrow is only hittable in
  // narrow gaps and an edge hover/click "blinks then clears". Instead we hover the
  // COLUMN ROW (a real DOM element inside the html-label card) and, secondarily,
  // TAP the edge to PIN. Both set `activeRel` and publish it onto node `hlCols`
  // data, which the plugin bakes into the card markup so it survives re-renders.

  // Node ids currently carrying an `hlCols` data highlight, and a signature of the
  // applied highlight, so we only WRITE node data when it actually CHANGES. Writing
  // identical data would re-trigger the plugin's per-node re-render and, mid-hover,
  // a regenerate-under-cursor mouseout/mouseover churn; the guard keeps a steady
  // hover steady.
  let hlNodeIds: string[] = [];
  let appliedSig: string | null = null;

  // Publish `activeRel` onto NODE DATA (`hlCols`): that is what makes the plugin
  // re-run the card template with `.col-hl` baked into the markup (design/39 - the
  // plugin caches per-node markup and only re-runs on a data change, so a closure
  // or a post-applied class is wiped). Also light the connecting edges (a native
  // cytoscape class) and clear the use-case fade so the lit columns read on
  // full-opacity cards. A no-op when nothing is active or nothing changed.
  const applyRel = (): void => {
    if (!activeRel) return;
    bandOverlay?.clearHover();
    for (const id of activeRel.edges) cy.getElementById(id).addClass("highlighted");
    const sig = [...activeRel.cols.entries()]
      .map(([t, cs]) => `${t}:${[...cs].sort().join(",")}`)
      .sort()
      .join("|");
    if (sig === appliedSig) return; // node data already reflects this relationship
    const nextIds = [...activeRel.cols.keys()];
    for (const id of hlNodeIds) if (!nextIds.includes(id)) cy.getElementById(id).data("hlCols", []);
    for (const [table, cols] of activeRel.cols) cy.getElementById(table).data("hlCols", [...cols]);
    hlNodeIds = nextIds;
    appliedSig = sig;
  };

  // Tear the relationship highlight down (unless pinned): drop the edge
  // `.highlighted`, clear every lit node's `hlCols` (so the template drops
  // `.col-hl` on its data-triggered re-run), forget the state, refresh the minimap.
  const clearRel = (force = false): void => {
    if (pinnedEdge && !force) return; // a pinned highlight ignores a mouseout
    if (activeRel) for (const id of activeRel.edges) cy.getElementById(id).removeClass("highlighted");
    for (const id of hlNodeIds) cy.getElementById(id).data("hlCols", []);
    hlNodeIds = [];
    appliedSig = null;
    activeRel = null;
    pinnedEdge = null;
    minimap?.refresh();
  };

  // Build the `activeRel` for hovering (table, col): the hovered column + each
  // joined counterpart column + the connecting edge(s). Returns null when that
  // column participates in no relationship (so a plain-column hover is a no-op).
  const relForColumn = (table: string, col: string): RelHighlight | null => {
    const links = colLinks.get(`${table}|${col}`);
    if (!links || links.length === 0) return null;
    const cols = new Map<string, Set<string>>();
    const edges = new Set<string>();
    const tables = new Set<string>();
    const add = (t: string, c: string): void => {
      (cols.get(t) ?? cols.set(t, new Set()).get(t)!).add(c);
      tables.add(t);
    };
    add(table, col);
    for (const l of links) {
      add(l.otherTable, l.otherCol);
      edges.add(l.edgeId);
    }
    return { cols, edges, tables };
  };

  // Build the `activeRel` for a PINNED edge tap: the edge's parent PK cols + child
  // FK cols + the edge itself. Read from the edge data (parent_cols/child_cols,
  // threaded by elements.ts).
  const relForEdge = (e: cytoscape.EdgeSingular): RelHighlight => {
    const parent = String(e.data("source"));
    const child = String(e.data("target"));
    const parentCols = (e.data("parent_cols") as string[]) ?? [];
    const childCols = (e.data("child_cols") as string[]) ?? [];
    const cols = new Map<string, Set<string>>();
    if (parentCols.length) cols.set(parent, new Set(parentCols));
    if (childCols.length) cols.set(child, new Set(childCols));
    return { cols, edges: new Set([String(e.id())]), tables: new Set([parent, child]) };
  };

  // PRIMARY trigger: delegated column-row hover. ONE mouseover/mouseout listener
  // on the container (NOT per-card): the html-label plugin regenerates card DOM on
  // every render, so a per-card listener would be lost; a delegated one on the
  // persistent container survives. On entering a `.col-row[data-col]` inside a
  // `.card[data-table]` that participates in a relationship, set + apply the
  // highlight; on leaving, clear it (unless pinned).
  // Publishing `hlCols` re-renders the hovered card, which replaces its DOM UNDER
  // the cursor and fires a mouseout+mouseover PAIR. A short debounce lets that pair
  // cancel itself (the mouseover re-enters within the window); only a real pointer
  // leave (no re-enter) actually clears. Cleared in destroy().
  let pendingClear: ReturnType<typeof setTimeout> | undefined;
  const scheduleClear = (): void => {
    clearTimeout(pendingClear);
    pendingClear = setTimeout(() => clearRel(), 40);
  };
  const onColOver = (ev: Event): void => {
    if (pinnedEdge) return; // a pin owns the highlight; a hover does not override it
    const row = (ev.target as HTMLElement).closest<HTMLElement>(".col-row[data-col]");
    if (!row) return;
    const card = row.closest<HTMLElement>(".card[data-table]");
    if (!card) return;
    const rel = relForColumn(card.getAttribute("data-table") ?? "", row.getAttribute("data-col") ?? "");
    if (rel) {
      clearTimeout(pendingClear); // over a key column: keep the highlight alive
      activeRel = rel;
      applyRel();
      minimap?.refresh();
    } else {
      scheduleClear(); // over a non-key column: let the current highlight fade out
    }
  };
  const onColOut = (ev: Event): void => {
    if (pinnedEdge) return; // a pinned highlight survives a column mouseout
    const row = (ev.target as HTMLElement).closest<HTMLElement>(".col-row[data-col]");
    if (!row) return;
    scheduleClear();
  };
  container.addEventListener("mouseover", onColOver);
  container.addEventListener("mouseout", onColOut);

  // SECONDARY trigger: edge tap to PIN. Tapping an edge toggles a PINNED
  // relationship highlight (its parent PK cols + child FK cols + the edge). It
  // persists across mouseout + pan/zoom until the SAME edge is tapped again or the
  // background is tapped. This is the reliable "click the arrow" path (the thin
  // edge is hard to hover, but a tap registers).
  cy.on("tap", "edge", (evt) => {
    const e = evt.target as cytoscape.EdgeSingular;
    const id = String(e.id());
    if (pinnedEdge === id) {
      clearRel(true); // re-tap the pinned edge -> unpin
      return;
    }
    activeRel = relForEdge(e);
    pinnedEdge = id;
    applyRel();
    minimap?.refresh();
  });

  // (No `cy.on("render", applyRel)`: `.col-hl` is data-driven via the card template
  // reading `relCols`, so it is re-baked on every regeneration automatically. A
  // render-time re-apply here would also recurse with applyRel's forceRender.)

  // tap on the BACKGROUND (core/empty canvas, not a node/edge) clears a pin. The
  // core tap fires for a node/edge tap too, so guard on the target being the core.
  cy.on("tap", (evt) => {
    if (evt.target === cy) clearRel(true);
  });

  // tap: unit mode -> drill to table (L2); graph mode -> drill into the unit
  cy.on("tap", "node", (evt) => {
    const id = String((evt.target as cytoscape.NodeSingular).data("id"));
    onTableTap(id);
  });

  return {
    refreshTheme: () => {
      const c = edgeColor();
      cy.style()
        .selector("edge")
        .style({ "line-color": c, "target-arrow-color": c } as cytoscape.Css.Edge)
        .update();
    },
    relayout,
    highlightUseCase: (name: string) => {
      const found = bandOverlay?.hoverUseCaseByName(name) ?? false;
      if (found) activeUseCase = name; // remember it so relayout re-asserts it (M1)
      minimap?.refresh(); // mirror the use-case hl/fade onto the minimap
      return found;
    },
    clearUseCaseHighlight: () => {
      activeUseCase = null;
      bandOverlay?.clearHover();
      minimap?.refresh();
    },
    destroy: () => {
      // Tear down everything registered in this mount BEFORE cy.destroy(), in
      // reverse order of construction, so no listener/overlay outlives the graph.
      clearTimeout(resizeTimer);
      clearTimeout(pendingClear); // don't let a pending relationship-clear fire post-teardown
      window.removeEventListener("resize", debouncedRelayout);
      container.style.removeProperty("--ordm-expand-max");
      // Delegated relationship-highlight listeners on the container (design/39):
      // removed here so a re-mount into the same #cy cannot stack duplicates.
      container.removeEventListener("mouseover", onColOver);
      container.removeEventListener("mouseout", onColOut);
      zoomWidget.destroy();
      edgeIndicators?.destroy();
      minimap?.destroy();
      bandOverlay?.destroy();
      consumesRail?.destroy();
      // Clear the e2e handle so it never points at a destroyed instance (it is
      // re-set on the next mount when the gate is on).
      const w = window as unknown as { __cy?: cytoscape.Core };
      if (w.__cy === cy) delete w.__cy;
      cy.destroy();
    },
    cy,
  };
}
