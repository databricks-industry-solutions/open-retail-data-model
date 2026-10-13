import type { DerivedModel, PackageVM, DomainVM, UseCase } from "./data";
import { escapeHtml as esc } from "./esc";

/**
 * The L0 layered value-chain landing (the layered value-chain design) rendered as REAL DOM, not a
 * cytoscape overlay. This is deliberate: the old force-directed overview drove
 * the shipped bugs (search / PII / layer filters set `display:none` on cytoscape
 * *nodes* while the visible artifact was the html-label overlay that ignored it).
 * Rendering the overview as ordinary DOM cards means filtering hides exactly what
 * is seen, so one visibility mechanism drives search + PII + layer, and the
 * layout is deterministic (fixed grid, no physics).
 *
 * Consumption edges are drawn on demand into an SVG overlay only on hover /
 * selection — never at rest — so the overview is pure structure (no hairball).
 */

export interface FilterState {
  q: string;
  piiOnly: boolean;
  layer: "all" | "core" | "outcome";
  theme?: string;
}

export interface OverviewCallbacks {
  onUnit: (name: string) => void; // drill into a package or domain (L1)
  onTheme: (title: string | undefined) => void; // theme filter toggled
}

export interface OverviewHandle {
  /** re-run filtering against the current state and update the readout. */
  applyFilters: (state: FilterState) => void;
  /** visible entity count after the last applyFilters (for tests / status). */
  visibleCount: () => number;
  totalCount: () => number;
  destroy: () => void;
}

const STATUS_LABEL: Record<string, string> = {
  built: "built",
  "in-progress": "in-progress",
  planned: "planned",
};

/**
 * The planning-tier use cases a package enables, as a compact sub-list. Each
 * item is a small status dot (reusing the shared .stat styling) plus the use-
 * case name. Kept visually calm and constrained so it never adds horizontal
 * overflow (see Piece 3 — names wrap, the row does not push the card wider).
 */
function useCaseList(useCases: UseCase[]): string {
  if (useCases.length === 0) return "";
  const items = useCases
    .map(
      (uc) =>
        `<li class="uc" data-uc-status="${esc(uc.status)}">` +
        `<span class="stat ${esc(uc.status)}" aria-hidden="true"></span>` +
        `<span class="uc-name">${esc(uc.name)}</span>` +
        `</li>`
    )
    .join("");
  return `<ul class="uc-list" role="list">${items}</ul>`;
}

/** Compact aria hint: "3 use cases" so the sub-list is announced but not verbose. */
function useCaseAria(useCases: UseCase[]): string {
  if (useCases.length === 0) return "";
  return `, ${useCases.length} use case${useCases.length === 1 ? "" : "s"}`;
}

function pkgCard(p: PackageVM): string {
  const tbl = p.tableCount === 1 ? "1 tbl" : `${p.tableCount} tbl`;
  const piiTag = p.pii ? `<span class="pii-dot" title="contains PII">PII</span>` : "";
  return (
    `<button class="pkg" data-unit="${esc(p.name)}" data-kind="outcome" ` +
    `data-pii="${p.pii}" data-status="${esc(p.status)}" ` +
    `aria-label="${esc(p.label)} outcome package, ${esc(STATUS_LABEL[p.status])}, ${tbl}${useCaseAria(
      p.useCases
    )}">` +
    `<span class="pname">${esc(p.label)}</span>` +
    `<span class="pmeta">` +
    `<span class="stat ${esc(p.status)}" aria-hidden="true"></span>` +
    `<span class="pstatus">${esc(STATUS_LABEL[p.status])}</span>` +
    piiTag +
    `<span class="cnt">${esc(tbl)}</span>` +
    `</span>` +
    useCaseList(p.useCases) +
    `</button>`
  );
}

function domCard(d: DomainVM): string {
  const tbl = d.tableCount === 1 ? "1 tbl" : `${d.tableCount} tbl`;
  const pii = d.pii ? " &middot; <span class=\"pii-dot\">PII</span>" : "";
  return (
    `<button class="dom" data-unit="${esc(d.name)}" data-kind="core" ` +
    `data-pii="${d.pii}" ` +
    `aria-label="${esc(d.label)} core domain, ${esc(d.role)}, ${tbl}">` +
    `<span class="dname">${esc(d.label)}</span>` +
    `<span class="dkind">${esc(d.role)}</span>` +
    `<span class="dmeta">${esc(tbl)}${pii}</span>` +
    `</button>`
  );
}

function themeColumn(title: string, packages: PackageVM[]): string {
  return (
    `<div class="theme" data-theme="${esc(title)}">` +
    `<button class="theme-title" data-theme-filter="${esc(title)}" ` +
    `aria-label="Filter to theme ${esc(title)}">${esc(title)}</button>` +
    `<div class="pkgs">${packages.map(pkgCard).join("")}</div>` +
    `</div>`
  );
}

/**
 * Render the layered landing into `root` and wire interaction. Returns a handle
 * whose applyFilters() the caller drives from the toolbar controls.
 */
export function renderOverview(
  root: HTMLElement,
  dm: DerivedModel,
  cb: OverviewCallbacks
): OverviewHandle {
  const t = dm.totals;

  root.innerHTML =
    `<div class="ov-canvas">` +
    // GOLD LANE
    `<div class="tier">` +
    `<span class="tier-label">Consumption layer</span>` +
    `<div class="lane gold">` +
    `<div class="lane-head">` +
    `<span class="tag gold">Gold</span>` +
    `<h3>Outcome packages</h3>` +
    `<span class="sub">${t.packages} packages &middot; ${t.themes} themes</span>` +
    `</div>` +
    `<div class="themes">` +
    dm.themes.map((th) => themeColumn(th.title, th.packages)).join("") +
    `</div>` +
    `</div>` +
    `</div>` +
    // FLOW HINT
    `<div class="flow"><span>outcome packages consume the core</span>` +
    `<span class="arrows" aria-hidden="true">&darr; &darr; &darr;</span>` +
    `<span>hover a card to light its edges</span></div>` +
    // CORE LANE
    `<div class="tier">` +
    `<span class="tier-label">Foundational layer</span>` +
    `<div class="lane core">` +
    `<div class="lane-head">` +
    `<span class="tag core">Silver</span>` +
    `<h3>Canonical-core domains</h3>` +
    `<span class="sub">conformed &middot; published once &middot; reused</span>` +
    `</div>` +
    `<div class="domains">` +
    dm.domains.map(domCard).join("") +
    `</div>` +
    `</div>` +
    `</div>` +
    // SVG edge overlay (empty at rest)
    `<svg class="edge-layer" aria-hidden="true"></svg>` +
    `</div>` +
    // empty / no-results state
    `<div class="ov-empty" hidden>No entities match. Clear the filters to see everything.</div>`;

  const canvas = root.querySelector<HTMLElement>(".ov-canvas")!;
  const edgeLayer = root.querySelector<SVGSVGElement>(".edge-layer")!;
  const emptyEl = root.querySelector<HTMLElement>(".ov-empty")!;

  const pkgEls = Array.from(root.querySelectorAll<HTMLElement>(".pkg"));
  const domEls = Array.from(root.querySelectorAll<HTMLElement>(".dom"));
  const allCards = [...pkgEls, ...domEls];

  // ---- consumption edge overlay (hover / focus reveal) ----
  function clearEdges(): void {
    while (edgeLayer.firstChild) edgeLayer.removeChild(edgeLayer.firstChild);
    canvas.classList.remove("edges-active");
    allCards.forEach((el) => el.classList.remove("edge-src", "edge-dst", "edge-dim"));
  }

  function drawEdgesFor(name: string): void {
    clearEdges();
    const pkg = dm.packageByName.get(name);
    const dom = dm.domainByName.get(name);
    // find the source card + its related core-domain cards (or reverse)
    let srcEl: HTMLElement | undefined;
    let targets: string[] = [];
    if (pkg) {
      srcEl = pkgEls.find((e) => e.dataset["unit"] === name);
      targets = pkg.consumes;
    } else if (dom) {
      srcEl = domEls.find((e) => e.dataset["unit"] === name);
      targets = dom.consumedBy;
    }
    if (!srcEl || targets.length === 0) return;

    canvas.classList.add("edges-active");
    // dim everything, then un-dim the participants
    allCards.forEach((el) => el.classList.add("edge-dim"));
    srcEl.classList.remove("edge-dim");
    srcEl.classList.add("edge-src");

    const canvasRect = canvas.getBoundingClientRect();
    edgeLayer.setAttribute("viewBox", `0 0 ${canvasRect.width} ${canvasRect.height}`);
    edgeLayer.setAttribute("width", String(canvasRect.width));
    edgeLayer.setAttribute("height", String(canvasRect.height));

    const srcRect = srcEl.getBoundingClientRect();
    const sx = srcRect.left + srcRect.width / 2 - canvasRect.left;
    const sy = pkg
      ? srcRect.bottom - canvasRect.top
      : srcRect.top - canvasRect.top;

    for (const tName of targets) {
      const tEl = (pkg ? domEls : pkgEls).find((e) => e.dataset["unit"] === tName);
      if (!tEl) continue;
      tEl.classList.remove("edge-dim");
      tEl.classList.add("edge-dst");
      const r = tEl.getBoundingClientRect();
      const tx = r.left + r.width / 2 - canvasRect.left;
      const ty = pkg ? r.top - canvasRect.top : r.bottom - canvasRect.top;
      const midY = (sy + ty) / 2;
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", `M ${sx} ${sy} C ${sx} ${midY}, ${tx} ${midY}, ${tx} ${ty}`);
      path.setAttribute("class", "edge-path");
      edgeLayer.appendChild(path);
    }
  }

  // ---- wire hover + focus (reveal edges) ----
  function bindReveal(el: HTMLElement): void {
    const name = el.dataset["unit"]!;
    el.addEventListener("mouseenter", () => drawEdgesFor(name));
    el.addEventListener("focus", () => drawEdgesFor(name));
    el.addEventListener("mouseleave", () => clearEdges());
    el.addEventListener("blur", () => clearEdges());
    // The cards are native <button>s, so Enter/Space already synthesize a click;
    // a keydown handler here would fire cb.onUnit a SECOND time (a redundant
    // teardown + re-mount). The click handler alone covers mouse and keyboard.
    el.addEventListener("click", () => cb.onUnit(name));
  }
  allCards.forEach(bindReveal);

  // ---- theme title -> toggle theme filter ----
  root.querySelectorAll<HTMLElement>(".theme-title").forEach((el) => {
    el.addEventListener("click", () => {
      const title = el.dataset["themeFilter"];
      cb.onTheme(title);
    });
  });

  // ---- filtering (real DOM show/hide) ----
  let lastVisible = allCards.length;

  function applyFilters(state: FilterState): void {
    clearEdges();
    const q = state.q.trim().toLowerCase();
    let visible = 0;

    for (const el of allCards) {
      const kind = el.dataset["kind"]; // "outcome" | "core"
      const unit = el.dataset["unit"] ?? "";
      const label = (el.querySelector(".pname, .dname")?.textContent ?? "").toLowerCase();
      const isPii = el.dataset["pii"] === "true";

      let show = true;

      // layer filter
      if (state.layer === "core" && kind !== "core") show = false;
      if (state.layer === "outcome" && kind !== "outcome") show = false;

      // PII-only
      if (show && state.piiOnly && !isPii) show = false;

      // theme filter — only constrains packages; when a theme is active the
      // core lane still shows (it is the shared foundation), unless the layer
      // filter narrows to outcome.
      if (show && state.theme && kind === "outcome") {
        const themeEl = el.closest<HTMLElement>(".theme");
        if (themeEl?.dataset["theme"] !== state.theme) show = false;
      }

      // text search (label or slug). Both sides lowercased: `q` in applyFilters above,
      // `label` at read time, and the slug here (symmetry).
      if (show && q !== "" && !label.includes(q) && !unit.toLowerCase().includes(q)) show = false;

      el.classList.toggle("hidden", !show);
      if (show) visible++;
    }

    // hide theme columns / lanes that ended up empty, and mark active theme
    root.querySelectorAll<HTMLElement>(".theme").forEach((themeEl) => {
      const anyVisible = themeEl.querySelector(".pkg:not(.hidden)");
      themeEl.classList.toggle("theme-empty", !anyVisible);
      themeEl.classList.toggle(
        "theme-active",
        !!state.theme && themeEl.dataset["theme"] === state.theme
      );
    });
    root.querySelectorAll<HTMLElement>(".lane").forEach((laneEl) => {
      const anyVisible = laneEl.querySelector(".pkg:not(.hidden), .dom:not(.hidden)");
      laneEl.classList.toggle("lane-empty", !anyVisible);
    });

    lastVisible = visible;
    emptyEl.hidden = visible !== 0;
    canvas.style.display = visible === 0 ? "none" : "";
  }

  return {
    applyFilters,
    visibleCount: () => lastVisible,
    totalCount: () => allCards.length,
    destroy: () => {
      clearEdges();
      root.innerHTML = "";
    },
  };
}

/**
 * Render the packages × core-domains consumption Matrix (the layered value-chain design concept C).
 * A DOM table with a dot at each consumption intersection — the exhaustive
 * "who consumes what" with zero crossing lines.
 */
export function renderMatrix(
  root: HTMLElement,
  dm: DerivedModel,
  onUnit: (name: string) => void
): void {
  const domains = dm.domains;
  const packages = [...dm.packageByName.values()];

  const head =
    `<tr><th class="corner" scope="col">package \\ domain</th>` +
    domains
      .map(
        (d) =>
          `<th scope="col" class="mx-dom"><button data-unit="${esc(d.name)}">${esc(
            d.label
          )}</button></th>`
      )
      .join("") +
    `</tr>`;

  const rows = packages
    .map((p) => {
      const cells = domains
        .map((d) => {
          const on = p.consumes.includes(d.name);
          return `<td class="mx-cell ${on ? "on" : ""}" ${
            on ? `aria-label="${esc(p.label)} consumes ${esc(d.label)}"` : ""
          }>${on ? "<span class=\"mx-dot\"></span>" : ""}</td>`;
        })
        .join("");
      return (
        `<tr><th scope="row" class="mx-pkg"><button data-unit="${esc(p.name)}">${esc(
          p.label
        )}</button> <span class="stat ${esc(p.status)}" title="${esc(
          p.status
        )}"></span></th>${cells}</tr>`
      );
    })
    .join("");

  root.innerHTML =
    `<div class="matrix-wrap"><table class="matrix"><thead>${head}</thead><tbody>${rows}</tbody></table></div>`;

  root.querySelectorAll<HTMLButtonElement>("button[data-unit]").forEach((b) => {
    b.addEventListener("click", () => onUnit(b.dataset["unit"]!));
  });
}
