import "./styles.css";
import type { Model, Unit } from "./model";
import { deriveModel, humanize, type DerivedModel } from "./data";
import { initTheme } from "./theme";
import { Router, type RouteState, parentState } from "./router";
import {
  renderOverview,
  renderMatrix,
  type OverviewHandle,
  type FilterState,
} from "./overview";
import { openPanel, openUnitPanel, closePanel } from "./panel";
import { getItem, setItem } from "./storage";
import type { GraphHandle } from "./graph";

/**
 * App orchestrator. Loads model.json, derives the view-model, builds the
 * toolbar (breadcrumbs / back / view toggle / search / filters / legend / hint),
 * and drives the router. The overview (L0) is DOM/CSS-grid; cytoscape is loaded
 * lazily only for the opt-in Graph view and the per-unit ER (L1/L2).
 */

const LEGEND_HTML =
  `<span class="lg"><span class="lg-swatch core"></span>Core / silver</span>` +
  `<span class="lg"><span class="lg-swatch gold"></span>Gold / outcome</span>` +
  `<span class="lg"><span class="stat built"></span>built / done</span>` +
  `<span class="lg"><span class="stat in-progress"></span>in&#8209;progress</span>` +
  `<span class="lg"><span class="stat planned"></span>planned</span>` +
  `<span class="lg"><span class="stat blocked"></span>blocked</span>` +
  `<span class="lg"><span class="pii-dot">PII</span> contains PII</span>`;

const HINT_TEXT =
  "This is a two-layer retail data model: outcome packages on top, conformed " +
  "core below. Hover a card to see what it consumes; click to drill in.";
const HINT_KEY = "ordm-explorer-hint-dismissed";

export interface AppHandle {
  filterState: FilterState;
  /** the currently-mounted overview (null when on matrix / graph / a drill view). */
  readonly overview: OverviewHandle | null;
  applyFilters: () => void;
  router: Router;
  /** Tear down all global listeners (document keydown, router, theme) so the app
   *  can be cleanly re-mounted without leaking stale handlers onto window/document. */
  destroy: () => void;
}

export function mountApp(model: Model): AppHandle {
  const dm: DerivedModel = deriveModel(model);
  const unitByName = new Map(model.units.map((u) => [u.name, u]));

  const toolbar = document.getElementById("toolbar")!;
  const hintEl = document.getElementById("hint")!;
  const overviewRoot = document.getElementById("overview-root")!;
  const cyEl = document.getElementById("cy")!;
  const loadingEl = document.getElementById("loading");
  const legendEl = document.getElementById("legend")!;

  loadingEl?.remove();

  const filterState: FilterState = { q: "", piiOnly: false, layer: "all", theme: undefined };
  const router = new Router();
  let overview: OverviewHandle | null = null;
  let graph: GraphHandle | null = null;
  // The right-pane use-case the user has PINNED (clicked): its highlight persists
  // after mouseleave. Hover shows a transient highlight but does not clear a pinned
  // one on leave (it re-asserts the pin). Cleared when the L1 panel is rebuilt.
  let pinnedUseCase: string | null = null;
  // What the currently-mounted cytoscape view is FOR, so render() can detect an
  // L1 <-> L2 transition WITHIN the same unit and skip the tearDown + re-mount +
  // re-fit (the "blink"); it then just opens/closes the L2 panel in place.
  // Both null whenever no graph is mounted (kept in lock-step with `graph`).
  let mountedView: RouteState["view"] | null = null;
  let mountedUnit: string | null = null;

  // ---------- toolbar scaffold ----------
  const title = el("span", "toolbar-title", "ORDM Model Explorer");

  const backBtn = el("button", "back-btn") as HTMLButtonElement;
  backBtn.id = "back-btn";
  backBtn.type = "button";
  backBtn.innerHTML = "&larr; Back";
  backBtn.hidden = true;
  backBtn.addEventListener("click", () => goUp());

  const crumbs = el("nav", "crumbs") as HTMLElement;
  crumbs.setAttribute("aria-label", "breadcrumb");

  const spacer = el("span", "toolbar-spacer");

  // search
  const search = el("input", "tb-search") as HTMLInputElement;
  search.type = "search";
  search.id = "filter-q";
  search.placeholder = "Search domains and packages…";
  search.setAttribute("aria-label", "Search entities");
  let searchTimer: ReturnType<typeof setTimeout> | undefined;
  search.addEventListener("input", () => {
    // Commit the query to state IMMEDIATELY. render() re-syncs controls from
    // filterState (`search.value = filterState.q`), so if we only set q inside
    // the debounce a re-render in that window would wipe what the user typed.
    filterState.q = search.value;
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => applyFilters(), 120);
  });

  // layer select
  const layerSel = el("select") as HTMLSelectElement;
  layerSel.id = "filter-layer";
  layerSel.setAttribute("aria-label", "Filter by layer");
  [
    ["all", "All layers"],
    ["core", "Core"],
    ["outcome", "Outcome"],
  ].forEach(([v, t]) => {
    const o = document.createElement("option");
    o.value = v;
    o.textContent = t;
    layerSel.appendChild(o);
  });
  layerSel.addEventListener("change", () => {
    filterState.layer = layerSel.value as FilterState["layer"];
    applyFilters();
  });

  // PII-only
  const piiLabel = el("label", "tb-pii");
  const piiCheck = el("input") as HTMLInputElement;
  piiCheck.type = "checkbox";
  piiCheck.id = "filter-pii";
  piiCheck.addEventListener("change", () => {
    filterState.piiOnly = piiCheck.checked;
    applyFilters();
  });
  piiLabel.appendChild(piiCheck);
  piiLabel.appendChild(document.createTextNode(" PII only"));

  // status readout
  const readout = el("span", "tb-readout");
  readout.id = "status-readout";
  readout.setAttribute("aria-live", "polite");

  // view segmented toggle
  const seg = el("div", "segmented") as HTMLElement;
  seg.setAttribute("role", "tablist");
  const segBtns: Record<string, HTMLButtonElement> = {};
  ([
    ["overview", "Layers"],
    ["matrix", "Matrix"],
    ["graph", "Graph"],
  ] as const).forEach(([view, label]) => {
    const b = el("button", "seg-btn") as HTMLButtonElement;
    b.type = "button";
    // role="tab" pairs with the seg container's role="tablist" and makes the
    // aria-selected set below valid ARIA (aria-selected is invalid on a plain button).
    b.setAttribute("role", "tab");
    b.textContent = label;
    b.dataset["view"] = view;
    b.addEventListener("click", () => {
      const cur = router.current();
      router.go({ view, theme: view === "overview" ? cur.theme : undefined });
    });
    segBtns[view] = b;
    seg.appendChild(b);
  });

  // theme toggle button is injected by initTheme() into #toolbar; we build the
  // rest around it.
  toolbar.append(title, backBtn, crumbs, spacer, search, layerSel, piiLabel, readout, seg);

  legendEl.innerHTML = LEGEND_HTML;

  // ---------- onboarding hint (dismissible; shown only on the L0 overview) ----------
  // Build the content once; per-route visibility is decided in render() so this
  // overview-specific copy never shows on an L1 / L2 / matrix / graph view.
  hintEl.innerHTML =
    `<span>${HINT_TEXT}</span>` +
    `<button class="hint-close" type="button" aria-label="Dismiss hint">&#x2715;</button>`;
  hintEl.querySelector(".hint-close")!.addEventListener("click", () => {
    hintEl.hidden = true;
    setItem(HINT_KEY, "1");
  });

  // ---------- theme (injects its own toggle button; re-colours graph edges) ----------
  // initTheme calls this back on EVERY theme flip - button click AND OS-preference
  // change (the latter fires only when the user has no stored choice). Debounce the
  // graph edge re-colour (the class is already applied by the time we're called; the
  // delay just coalesces rapid toggles and lets the CSS var settle). Wiring it through
  // the callback covers the OS-change path too, which a click-only listener missed (M1).
  let themeRefreshTimer: ReturnType<typeof setTimeout> | undefined;
  const themeTeardown = initTheme(() => {
    clearTimeout(themeRefreshTimer);
    themeRefreshTimer = setTimeout(() => graph?.refreshTheme(), 50);
  });

  // Opening/closing the L2 detail panel narrows/widens #cy (a flex sibling), but
  // nothing tells cytoscape its container changed size, so the diagram stays
  // fit to the wrong width. Debounce a relayout (mirrors themeRefreshTimer) so
  // the graph repacks + re-fits to the new canvas width. Cleared in destroy().
  let reflowTimer: ReturnType<typeof setTimeout> | undefined;
  function scheduleReflow(): void {
    clearTimeout(reflowTimer);
    reflowTimer = setTimeout(() => graph?.relayout(), 50);
  }

  // ---------- filters ----------
  function applyFilters(): void {
    if (overview) {
      overview.applyFilters(filterState);
      updateReadout(overview.visibleCount(), overview.totalCount());
    } else {
      // matrix / graph views: filters are less central; still surface the tally
      readout.textContent = "";
    }
  }
  function updateReadout(visible: number, total: number): void {
    const hidden = total - visible;
    readout.textContent = `showing ${visible} of ${total}${hidden ? ` · ${hidden} hidden` : ""}`;
  }

  // ---------- breadcrumb ----------
  function renderCrumbs(state: RouteState): void {
    const parts: { label: string; state: RouteState | null }[] = [];
    parts.push({ label: "Retail", state: { view: "overview" } });
    if (state.view === "matrix") parts.push({ label: "Matrix", state: null });
    else if (state.view === "graph") parts.push({ label: "Graph", state: null });
    else {
      if (state.theme) parts.push({ label: state.theme, state: { view: "overview", theme: state.theme } });
      if (state.unit) parts.push({ label: humanize(state.unit), state: state.table ? { view: "overview", unit: state.unit } : null });
      if (state.table) parts.push({ label: state.table, state: null });
    }
    crumbs.innerHTML = "";
    parts.forEach((p, i) => {
      if (i > 0) {
        const sep = document.createElement("span");
        sep.className = "crumb-sep";
        sep.textContent = "/";
        crumbs.appendChild(sep);
      }
      if (p.state) {
        const a = document.createElement("button");
        a.type = "button";
        a.className = "crumb-link";
        a.textContent = p.label;
        const target = p.state;
        // A crumb is always an ancestor, so step UP: pop when it is the immediate
        // previous entry (Forward keeps working), else push (multi-level jump), same
        // as before.
        a.addEventListener("click", () => router.stepUp(target));
        crumbs.appendChild(a);
      } else {
        const s = document.createElement("b");
        s.textContent = p.label;
        crumbs.appendChild(s);
      }
    });
  }

  // ---------- step up / back ----------
  function goUp(): void {
    const up = parentState(router.current());
    if (up) router.stepUp(up);
  }

  const onKeydown = (ev: KeyboardEvent): void => {
    if (ev.key !== "Escape") return;
    // ESC inside a form control (search box, layer select) is a clear/blur
    // gesture by convention, not navigation -- don't step up from there.
    const t = ev.target as HTMLElement | null;
    if (t && (t.tagName === "INPUT" || t.tagName === "SELECT")) return;
    // Otherwise ESC always steps up one level (L2 table -> L1 unit -> L0
    // overview), landing on a real route so the render rebuilds the right panel.
    goUp();
  };
  document.addEventListener("keydown", onKeydown);

  // ---------- teardown helpers ----------
  function tearDown(): void {
    // Cancel a pending search-debounce (main.ts search input) so it cannot fire
    // applyFilters() into the view we are about to mount and blank the readout that
    // view sets. tearDown() runs at the top of every render(), i.e. on navigation.
    clearTimeout(searchTimer);
    if (overview) {
      overview.destroy();
      overview = null;
    }
    if (graph) {
      graph.destroy();
      graph = null;
    }
    // The graph (if any) is gone; forget what it was for so the next render()
    // does a full mount rather than mistaking a stale context for an in-place hit.
    mountedView = null;
    mountedUnit = null;
    closePanel();
    overviewRoot.innerHTML = "";
    cyEl.innerHTML = "";
    overviewRoot.hidden = true;
    cyEl.hidden = true;
  }

  function setActiveSeg(view: string): void {
    for (const [k, b] of Object.entries(segBtns)) {
      b.classList.toggle("on", k === view);
      b.setAttribute("aria-selected", String(k === view));
    }
  }

  function setToolbarFiltersEnabled(on: boolean): void {
    [search, layerSel, piiCheck].forEach((c) => {
      (c as HTMLInputElement | HTMLSelectElement).disabled = !on;
    });
  }

  // ---------- lazy cytoscape import ----------
  // Cytoscape is loaded only for the opt-in Graph and the per-unit ER (L1/L2),
  // never for the DOM overview. Any renderer failure (e.g. no canvas) is caught
  // so it can't reject unhandled and break navigation.
  async function mountCy(mode: "graph" | "unit", unit: string | undefined, gen: number): Promise<void> {
    // Un-hide the container FIRST, before the dynamic import, so it is laid out
    // with real width/height by the time cytoscape() reads it. tearDown() leaves
    // #cy hidden (display:none), and cytoscape initialises against a zero-size
    // container if it mounts while still hidden — the graph then renders blank /
    // mis-fit (the "diagram view unavailable" fallback fires when init throws on
    // a 0x0 canvas). The await below also gives the layout a tick to settle.
    cyEl.hidden = false;
    try {
      const { mountGraph } = await import("./graph");
      // Force a reflow so the freshly-un-hidden container has measured its size
      // before cytoscape reads clientWidth/Height at init and layout time.
      void cyEl.offsetHeight;
      // If a newer route superseded us during the async import, bail BEFORE
      // reviving `graph` into the now torn-down / hidden container (tearDown
      // already nulled it). Otherwise this orphan keeps receiving refreshTheme().
      if (gen !== renderSeq) return;
      graph = mountGraph(cyEl, model, mode, unit, (tableId) => {
        if (mode === "unit" && unit) {
          // unit ER: the tapped node is a table -> open its L2 detail.
          router.go({ view: "overview", unit, table: tableId });
        } else if (mode === "graph") {
          // whole-model graph: the tapped node is a unit -> drill into its L1.
          router.go({ view: "overview", unit: tableId });
        }
      });
    } catch (err) {
      console.error("graph view failed to mount", err);
      // If a newer route superseded this one (or the app was destroyed) while the
      // import/mount was in flight, do NOT rewrite #cy - it belongs to the current
      // view now (M1).
      if (gen !== renderSeq) return;
      cyEl.hidden = false;
      cyEl.innerHTML = "";
      const box = document.createElement("div");
      box.id = "loading";
      box.textContent = "Diagram view unavailable in this environment.";
      // In dev, surface the real error + stack in-page so a mount failure is
      // diagnosable without a debugger (the generic message above hid a genuine
      // browser-runtime throw). Production keeps just the graceful message.
      if ((import.meta as { env?: { DEV?: boolean } }).env?.DEV) {
        const pre = document.createElement("pre");
        pre.style.cssText =
          "white-space:pre-wrap;text-align:left;font-size:12px;margin-top:12px;color:#c4320a;max-width:900px";
        pre.textContent = String((err as Error)?.stack ?? err);
        box.appendChild(pre);
      }
      cyEl.appendChild(box);
    }
  }

  // Reflect the pinned use case as a `.pinned` class on its right-pane list item
  // (a persistent visual, distinct from the transient :hover style). Toggles off
  // every other row so only the pinned one carries it.
  function syncPinnedUcClass(): void {
    const panel = document.getElementById("panel");
    if (!panel) return;
    panel.querySelectorAll<HTMLElement>(".panel-uc").forEach((li) => {
      li.classList.toggle("pinned", li.dataset["ucName"] === pinnedUseCase);
    });
  }

  // ---------- render a route ----------
  // Bumped on every render. An in-flight mountCy().then() from a route that has
  // since been superseded compares against this and bails, so a slow prior unit
  // can't open its panel over the route you already navigated to.
  let renderSeq = 0;
  function render(state: RouteState): void {
    const gen = ++renderSeq;

    // ---- in-place L1 <-> L2 (no tearDown, no re-mount, no re-fit) ----
    // When only the SELECTED TABLE changes within the same already-mounted unit
    // ER (L1 -> L2, L2 -> L1, or L2 -> L2'), keep the live graph and just open /
    // close / swap the L2 panel + update the toolbar chrome, then reflow. Tearing
    // the graph down and re-fitting it on every table click was the "blink". Only
    // reached when a unit ER is actually mounted for THIS unit (so a cold
    // deep-link to L2 (graph still null) falls through to the full mount below,
    // which mounts the ER then opens L2). renderSeq is still bumped above, so any
    // in-flight prior mountCy bails.
    if (
      graph &&
      mountedView === "overview" &&
      state.view === "overview" &&
      state.unit &&
      state.unit === mountedUnit &&
      !state.theme
    ) {
      const unit = unitByName.get(state.unit)!;
      renderCrumbs(state);
      backBtn.hidden = parentState(state) == null;
      setActiveSeg(state.view);
      hintEl.hidden = true; // never the L0 overview here
      setToolbarFiltersEnabled(false); // within a unit, filters are inert
      readout.textContent = `${unit.tables.length} tables`;
      if (state.table) {
        const t = unit.tables.find((x) => x.name === state.table);
        // Open (or swap to) the L2 detail panel over the SAME graph.
        if (t) openTablePanel(t, unit);
        else openL1UnitPanel(unit); // unknown table -> fall back to the L1 summary
      } else {
        // Step back to L1: reopen the unit summary panel (re-asserts any pin).
        openL1UnitPanel(unit);
      }
      // The panel opened/closed, changing #cy's width; re-fit WITHOUT re-fitting
      // the whole diagram (relayout preserves the user's zoom once adjusted).
      scheduleReflow();
      return;
    }

    tearDown();
    filterState.theme = state.view === "overview" ? state.theme : undefined;
    layerSel.value = filterState.layer;
    piiCheck.checked = filterState.piiOnly;
    search.value = filterState.q;

    renderCrumbs(state);
    backBtn.hidden = parentState(state) == null;
    setActiveSeg(state.view);
    // Onboarding hint: only on the L0 overview (its copy is overview-specific),
    // and only until the user dismisses it.
    hintEl.hidden = getItem(HINT_KEY) === "1" || !(state.view === "overview" && !state.unit);

    if (state.view === "matrix") {
      setToolbarFiltersEnabled(false);
      overviewRoot.hidden = false;
      renderMatrix(overviewRoot, dm, (name) => router.go({ view: "overview", unit: name }));
      readout.textContent = `${dm.totals.packages} packages × ${dm.totals.domains} domains`;
      return;
    }

    if (state.view === "graph") {
      setToolbarFiltersEnabled(false);
      readout.textContent = "";
      void mountCy("graph", undefined, gen);
      return;
    }

    // overview family (L0 / L1 / L2). Filters only act on the L0 overview grid
    // (there is no `overview` handle on a drill view), so keep them enabled ONLY
    // there -- otherwise they are live-but-inert on L1/L2 and applyFilters() would
    // blank the "N tables" readout the drill view just set.
    setToolbarFiltersEnabled(state.view === "overview" && !state.unit);

    if (state.unit) {
      const unit = unitByName.get(state.unit);
      if (!unit) {
        router.replace({ view: "overview" });
        render({ view: "overview" });
        return;
      }
      readout.textContent = `${unit.tables.length} tables`;
      if (unit.tables.length === 0) {
        // Planned/empty package: there is no ER to draw. Show a canvas empty-state
        // (the side panel lists the use cases + a "planned" note) instead of an
        // empty cytoscape mount, which otherwise leaves the whole left pane blank.
        cyEl.hidden = false;
        cyEl.innerHTML =
          `<div class="cy-empty">No tables yet. This package is planned; its use cases are listed in the panel.</div>`;
        openUnitPanel(unit, () => router.go({ view: "overview" }));
        return;
      }
      // L1: per-unit ER via cytoscape + a summary side panel
      pinnedUseCase = null; // a fresh L1 render starts with nothing pinned
      const unitName = state.unit;
      void mountCy("unit", unitName, gen).then(() => {
        if (gen !== renderSeq) return; // a newer route superseded this one
        // Record what this graph is for, so a subsequent L1 <-> L2 change within
        // the SAME unit takes the in-place path above (no tearDown / re-fit). Only
        // when the graph actually mounted (mountCy swallows a renderer failure and
        // leaves `graph` null; the in-place guard also re-checks `graph`, so this
        // is belt-and-suspenders).
        if (graph) {
          mountedView = "overview";
          mountedUnit = unitName;
        }
        openL1UnitPanel(unit);
        // L2: a table is selected -> open the ER detail panel over the fresh graph
        // (a cold deep-link straight to L2 lands here, not the in-place path).
        if (state.table) {
          const t = unit.tables.find((x) => x.name === state.table);
          if (t) openTablePanel(t, unit);
        }
        // The panel just opened (narrowing #cy); re-fit the graph to the new width.
        scheduleReflow();
      });
      return;
    }

    // L0 overview
    overviewRoot.hidden = false;
    overview = renderOverview(overviewRoot, dm, {
      onUnit: (name) => router.go({ view: "overview", unit: name }),
      onTheme: (theme) => {
        // toggle: click active theme again clears it
        const cur = router.current().theme;
        router.go({ view: "overview", theme: theme === cur ? undefined : theme });
      },
    });
    applyFilters();
  }

  function openTablePanel(table: Unit["tables"][number], unit: Unit): void {
    openPanel(
      {
        id: table.name,
        label: table.name,
        cls: table.layer === "gold" ? "gold" : "core",
        role: table.role,
        scd2: table.scd2,
        comment: table.comment,
        pii: table.columns.some((c) => c.pii),
        columns: table.columns,
      },
      unit,
      // Closing the L2 panel steps UP to L1 (like ESC), so the route stays in sync
      // with the view - otherwise the hash would keep #/u/<unit>/<table> while
      // nothing is shown and a reload/reshare would reopen L2 (M2). Use stepUp (not
      // router.go) so it POPS the L2 entry exactly like ESC/back, instead of pushing a
      // redundant L1 entry that would clear the browser Forward button.
      () => router.stepUp({ view: "overview", unit: unit.name })
    );
  }

  // Open the L1 unit summary panel with its full wiring (table-drill + use-case
  // hover/pin). Extracted so BOTH the fresh L1 mount and an in-place L2 -> L1
  // step-back (which does NOT re-mount the graph) reopen the same panel; the pin
  // callbacks close over `pinnedUseCase`, which survives the in-place transition.
  function openL1UnitPanel(unit: Unit): void {
    openUnitPanel(
      unit,
      () => router.go({ view: "overview" }),
      (tableName) => router.go({ view: "overview", unit: unit.name, table: tableName }),
      // Hover a use-case row: show a transient highlight; on leave, restore the
      // pinned one (or clear if none). A pinned highlight is never cleared by a
      // stray hover-out.
      (name) => {
        if (name) graph?.highlightUseCase(name);
        else if (pinnedUseCase) graph?.highlightUseCase(pinnedUseCase);
        else graph?.clearUseCaseHighlight();
      },
      // Click a use-case row: toggle the pin. Clicking the pinned one again (or a
      // different one) re-pins/unpins; the highlight persists past mouseleave.
      (name) => {
        if (pinnedUseCase === name) {
          pinnedUseCase = null;
          graph?.clearUseCaseHighlight();
        } else {
          // Only pin a use case that actually has a band to highlight. An unmapped
          // use case (no `tables:`) has no band, so pinning it would add `.pinned`
          // while nothing lights up on the canvas - a dead control. highlightUseCase
          // returns false in that case, so we leave the pin untouched.
          if (!graph?.highlightUseCase(name)) return;
          pinnedUseCase = name;
        }
        syncPinnedUcClass();
      }
    );
    // Re-assert a pin that survived an in-place transition (no-op on a fresh mount
    // where pinnedUseCase is null).
    if (pinnedUseCase) {
      graph?.highlightUseCase(pinnedUseCase);
      syncPinnedUcClass();
    }
  }

  router.onChange(render);
  // normalise + render the initial URL
  const initial = router.current();
  router.replace(initial);
  render(initial);

  return {
    filterState,
    get overview() {
      return overview;
    },
    applyFilters,
    router,
    destroy() {
      // Invalidate any in-flight mountCy() continuation: bumping renderSeq makes its
      // captured `gen !== renderSeq`, so neither its .then (openL1UnitPanel /
      // scheduleReflow) nor its catch branch runs against the DOM we are tearing
      // down (M1 - which would, via mountGraph, re-register a window.resize handler).
      renderSeq += 1;
      clearTimeout(searchTimer); // don't let a pending debounce fire into a torn-down DOM
      clearTimeout(themeRefreshTimer); // nor a pending graph theme-refresh
      clearTimeout(reflowTimer); // nor a pending panel/resize reflow
      document.removeEventListener("keydown", onKeydown);
      router.destroy();
      themeTeardown();
      tearDown();
      // tearDown() clears only the per-render surfaces (overview-root, #cy). The
      // toolbar, hint, and legend are built ONCE per mountApp, so without clearing
      // them here a re-mount would append a SECOND set of controls with duplicate
      // IDs (filter-q, theme-toggle, …). Clear them so re-mount rebuilds cleanly.
      toolbar.innerHTML = "";
      hintEl.innerHTML = "";
      hintEl.hidden = true;
      legendEl.innerHTML = "";
    },
  };
}

function el(tag: string, cls?: string, text?: string): HTMLElement {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}

// ---- bootstrap (skipped under test, which calls mountApp directly) ----
async function boot(): Promise<void> {
  const model = (await fetch("./model.json").then((r) => r.json())) as Model;
  mountApp(model);
}

// Only auto-boot in a real browser context (has fetch + a #toolbar). Tests
// import mountApp and drive it against a jsdom document without booting.
if (typeof document !== "undefined" && document.getElementById("toolbar")) {
  boot().catch((err) => {
    console.error(err);
    const loading = document.getElementById("loading");
    if (loading) loading.textContent = "Failed to load model.";
  });
}
