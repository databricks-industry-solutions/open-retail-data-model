import type { Unit, UseCase } from "./model";
import { externalBandName } from "./grouping";
import { toHash } from "./router";
import { escapeHtml as esc, safeHref } from "./esc";

function chipHtml(cls: string, text: string): string {
  return `<span class="chip ${esc(cls)}">${esc(text)}</span>`;
}

/**
 * Resolve a model.json link path (contract_path / glossary_path — repo-relative,
 * e.g. "contracts/odcs/customer.odcs.yaml") to a URL under the deployed site's
 * base. The generator stages these files into explorer/public/ under the SAME
 * relative path, so prefixing the Vite BASE_URL yields the served raw file
 * regardless of the current hash route or a sub-path gh-pages deploy. Without
 * the base prefix a bare relative path resolves against the document URL and,
 * on a project-site sub-path, points outside the deployed tree.
 */
function assetHref(path: string): string {
  // Validate the ORIGINAL path first: safeHref collapses a dangerous scheme
  // (javascript:, data:, …) or a control-char smuggle to "#". Only a clean,
  // scheme-less relative path survives to be rebased.
  const validated = safeHref(path);
  if (validated === "#") return "#";
  const base = (import.meta as { env?: { BASE_URL?: string } }).env?.BASE_URL ?? "/";
  const clean = validated.replace(/^\/+/, ""); // never treat the path as site-absolute
  return base.replace(/\/+$/, "") + "/" + clean;
}

function linkHtml(path: string, label: string): string {
  return (
    `<a href="${esc(assetHref(path))}" target="_blank" rel="noopener">${esc(label)}</a>`
  );
}

/**
 * The unit's link row, shared by the L1 unit panel and the L2 table panel:
 * Glossary + Contract (staged files, base-rebased by assetHref) and GitHub (the
 * unit's folder in the source repo). source_url is an absolute URL, so it skips
 * assetHref (which would rebase it under the site). It must be https:// outright:
 * safeHref alone passes a scheme-less "//host/..." through as relative, and
 * without assetHref's rebase that would open another host. Anything else omits
 * the link rather than rendering a dead "#" that opens a blank tab.
 */
function unitLinksHtml(unit: Unit): string {
  const links: string[] = [];
  if (unit.glossary_path) links.push(linkHtml(unit.glossary_path, "Glossary"));
  if (unit.contract_path) links.push(linkHtml(unit.contract_path, "Contract"));
  const src = unit.source_url ?? "";
  if (/^https:\/\//i.test(src) && safeHref(src) !== "#") {
    links.push(`<a href="${esc(src)}" target="_blank" rel="noopener">GitHub</a>`);
  }
  return links.length > 0 ? `<div class="panel-links">${links.join("")}</div>` : "";
}

interface ColData {
  name: string;
  type: string;
  pk: boolean;
  fk: boolean;
  pii: boolean;
  enum_values: string[];
  comment: string;
}

interface TableData {
  id: string;
  label: string;
  cls: "core" | "gold";
  role?: string;
  scd2?: boolean;
  pii?: boolean;
  layer?: string;
  comment?: string;
  columns?: ColData[];
  [k: string]: unknown;
}

/**
 * Open / populate the detail panel with a table's full column list.
 *
 * `onClose` (optional) fires AFTER the panel is closed via its close button, so
 * the caller can react to the canvas widening again (e.g. re-fit the graph). It
 * does not fire on a route-driven teardown (which re-renders from scratch).
 */
export function openPanel(tableData: TableData, unit: Unit, onClose?: () => void): void {
  const panel = document.getElementById("panel");
  if (!panel) return;

  const cols: ColData[] = tableData.columns ?? [];

  // Build column rows
  const colRowsHtml = cols
    .map((c) => {
      const keyChips =
        (c.pk ? chipHtml("chip key pk", "PK") : "") +
        (c.fk ? chipHtml("chip key fk", "FK") : "");

      const piiChip = c.pii ? chipHtml("chip pii", "PII") : "";

      let enumChip = "";
      if (c.enum_values && c.enum_values.length > 0) {
        const preview = esc(c.enum_values[0]);
        const extra = c.enum_values.length - 1;
        enumChip =
          `<span class="chip enum">enum(${preview}` +
          (extra > 0 ? `,+${extra}` : "") +
          `)</span>`;
      }

      const comment =
        c.comment
          ? `<div class="panel-col-comment">${esc(c.comment)}</div>`
          : "";

      return (
        `<div class="panel-col-row">` +
        `<span class="panel-col-type">${esc(c.type)}</span>` +
        `<span class="panel-col-name">${esc(c.name)}</span>` +
        keyChips +
        piiChip +
        enumChip +
        comment +
        `</div>`
      );
    })
    .join("");

  const linksHtml = unitLinksHtml(unit);

  const scd2 = tableData.scd2
    ? ` <span class="chip scd2">&#x29D7; SCD2</span>`
    : "";
  const roleChip = tableData.role
    ? ` <span class="chip role">${esc(String(tableData.role))}</span>`
    : "";

  // Table-level COMMENT shown under the title (escaped); part of the hover/detail
  // comment feature so the panel matches the card tooltip.
  const tableComment = tableData.comment
    ? `<div class="panel-table-comment">${esc(String(tableData.comment))}</div>`
    : "";

  panel.innerHTML =
    `<button class="panel-close" aria-label="Close panel" title="Close">&#x2715;</button>` +
    `<div class="panel-title">${esc(tableData.label)}${roleChip}${scd2}</div>` +
    tableComment +
    linksHtml +
    `<div class="panel-cols">${colRowsHtml}</div>`;

  panel.classList.add("open");
  panel.style.display = "block";

  // Wire close button
  const closeBtn = panel.querySelector(".panel-close") as HTMLButtonElement | null;
  closeBtn?.addEventListener("click", () => {
    closePanel();
    onClose?.();
  });
}

export function closePanel(): void {
  const panel = document.getElementById("panel");
  if (!panel) return;
  panel.classList.remove("open");
  panel.style.display = "none";
  panel.innerHTML = "";
}

/**
 * L1 side panel: a scoped summary of one unit (package or core domain). Shows
 * the kind, table count, PII flag, and the contract / glossary links. The
 * per-table ER detail stays the L2 destination (openPanel above); this is the
 * lighter L1 context card the layered value-chain design spec calls for.
 */
export function openUnitPanel(
  unit: Unit,
  onCloseTop?: () => void,
  onTableNav?: (tableName: string) => void,
  onUseCaseHover?: (name: string | null) => void,
  onUseCaseClick?: (name: string) => void
): void {
  const panel = document.getElementById("panel");
  if (!panel) return;

  const kindLabel = unit.kind === "core" ? "Canonical-core domain (silver)" : "Outcome package (gold)";
  const nTables = unit.tables.length;
  const nCols = unit.tables.reduce((a, t) => a + t.columns.length, 0);
  const anyPii = unit.tables.some((t) => t.columns.some((c) => c.pii));

  const linksHtml = unitLinksHtml(unit);

  // Planning tier: the business use cases this package enables (name + status).
  // Core domains carry none, so the section is omitted for them.
  const useCases = unit.use_cases ?? [];
  // A use case is highlightable only if it maps to at least one of the unit's gold
  // tables (grouping.ts bands it). One that maps to none has no band, so its row is
  // rendered NON-interactive (see the wiring below) rather than a dead control that
  // "pins" but lights nothing up on the canvas.
  const goldTables = new Set(
    unit.tables.filter((t) => t.layer === "gold").map((t) => t.name)
  );
  const isMapped = (tables: string[] | undefined): boolean =>
    (tables ?? []).some((t) => goldTables.has(t));
  // A use case served by ANOTHER package's gold view (`foreign_tables`) has no band
  // here, so its row stays non-interactive; instead it links to that view in its
  // home package, where the view is banded under this use case.
  const foreignLinks = (uc: UseCase): string =>
    (uc.foreign_tables ?? [])
      .map(
        (ft) =>
          `<a class="panel-uc-foreign" href="${esc(toHash({ view: "overview", unit: ft.unit, table: ft.table }))}"` +
          ` title="Open ${esc(ft.table)} in ${esc(ft.unit)}">${esc(ft.table)} <span class="panel-uc-foreign-unit">in ${esc(ft.unit)}</span></a>`
      )
      .join("");
  const ucRow = (name: string, label: string, status: string, mapped: boolean, title: string, extra: string): string =>
    `<li class="${mapped ? "panel-uc" : "panel-uc unmapped"}" data-uc-status="${esc(status)}" data-uc-name="${esc(name)}" data-uc-mapped="${mapped}"${title ? ` title="${esc(title)}"` : ""}>` +
    `<span class="stat ${esc(status)}" aria-hidden="true"></span>` +
    `<span class="panel-uc-name">${esc(label)}</span>` +
    `<span class="panel-uc-status">${esc(status)}</span>` +
    extra +
    `</li>`;
  const useCasesHtml =
    useCases.length > 0
      ? `<div class="panel-section-label">Use cases</div>` +
        `<ul class="panel-uc-list" role="list">` +
        useCases
          .map((uc) => {
            const mapped = isMapped(uc.tables);
            const hasForeign = (uc.foreign_tables ?? []).length > 0;
            const title = mapped
              ? ""
              : hasForeign
                ? "Served by another package's gold view"
                : "No tables mapped to this use case yet";
            return ucRow(uc.name, uc.name, uc.status, mapped, title, hasForeign ? foreignLinks(uc) : "");
          })
          .join("") +
        `</ul>`
      : "";
  // Other packages' use cases this package's gold views serve: banded in this L1
  // under externalBandName(), so the rows highlight like local ones.
  const externalUseCases = unit.external_use_cases ?? [];
  const externalHtml =
    externalUseCases.length > 0
      ? `<div class="panel-section-label">Also serves</div>` +
        `<ul class="panel-uc-list" role="list">` +
        externalUseCases
          .map((e) =>
            ucRow(externalBandName(e), externalBandName(e), e.status, isMapped(e.tables),
                  isMapped(e.tables) ? "" : "No tables mapped to this use case yet", "")
          )
          .join("") +
        `</ul>`
      : "";

  const tableList =
    nTables > 0
      ? `<div class="panel-cols">` +
        unit.tables
          .map(
            (t) =>
              `<button class="panel-table-link" data-table="${esc(t.name)}">` +
              `<span class="panel-col-name">${esc(t.name)}</span>` +
              `<span class="chip role">${esc(t.role)}</span>` +
              (t.columns.some((c) => c.pii) ? chipHtml("chip pii", "PII") : "") +
              `</button>`
          )
          .join("") +
        `</div>`
      : `<div class="panel-empty">Planned. No tables generated yet.</div>`;

  panel.innerHTML =
    `<button class="panel-close" aria-label="Close panel" title="Close">&#x2715;</button>` +
    `<div class="panel-kind ${esc(unit.kind)}">${esc(kindLabel)}</div>` +
    `<div class="panel-title">${esc(unit.name)}</div>` +
    `<div class="panel-facts">${nTables} tables &middot; ${nCols} columns${
      anyPii ? ` &middot; <span class="pii-dot">PII</span>` : ""
    }</div>` +
    linksHtml +
    useCasesHtml +
    externalHtml +
    tableList;

  panel.classList.add("open");
  panel.style.display = "block";

  const closeBtn = panel.querySelector(".panel-close") as HTMLButtonElement | null;
  closeBtn?.addEventListener("click", () => {
    if (onCloseTop) onCloseTop();
    else closePanel();
  });

  // Wire the table rows to drill into the L2 table detail. Without this the
  // buttons render as interactive (cursor:pointer, hover tint) but silently
  // no-op — a dead control. The cytoscape ER node tap reaches L2 too, but the
  // panel list must navigate as well.
  if (onTableNav) {
    panel
      .querySelectorAll<HTMLButtonElement>(".panel-table-link")
      .forEach((btn) =>
        btn.addEventListener("click", () => onTableNav(btn.dataset["table"]!))
      );
  }

  // Wire the use-case rows to the graph's use-case highlight (mirrors a band-header
  // hover): hover fades non-members + lights the member tables + reveals the
  // consumes chip strip; click pins that highlight. Without this the list renders
  // as interactive (cursor:pointer) but silently no-ops — a dead control. The
  // data-uc-name attribute is the escaped bridge to the band overlay by name.
  if (onUseCaseHover || onUseCaseClick) {
    panel.querySelectorAll<HTMLElement>(".panel-uc").forEach((li) => {
      const name = li.dataset["ucName"];
      if (!name) return;
      if (li.dataset["ucMapped"] !== "true") return; // unmapped row: non-interactive
      if (onUseCaseHover) {
        li.addEventListener("mouseenter", () => onUseCaseHover(name));
        li.addEventListener("mouseleave", () => onUseCaseHover(null));
      }
      if (onUseCaseClick) li.addEventListener("click", () => onUseCaseClick(name));
    });
  }
}
