import { escapeHtml as esc } from "./esc";

function chipHtml(cls: string, text: string): string {
  return `<span class="chip ${esc(cls)}">${esc(text)}</span>`;
}

/**
 * Build a ` title="..."` attribute for a native hover tooltip from a COMMENT.
 * Returns "" when the comment is empty so no empty tooltip is emitted. The
 * comment is ALWAYS routed through esc() — a hostile model.json comment must
 * never break out of the attribute (see cards.test.ts). Note the leading space.
 */
function titleAttr(comment: string | undefined): string {
  return comment ? ` title="${esc(comment)}"` : "";
}

/**
 * Build the RAW (unescaped) tooltip text for the shared chip from the list of
 * owning use cases. Returned unescaped on purpose: titleAttr escapes it once,
 * so escaping here too would double-encode. Returns "" when there is no list
 * (titleAttr then omits the attribute entirely).
 */
function sharedTitle(useCases: string[] | undefined): string {
  return useCases && useCases.length > 0 ? `Also in: ${useCases.join(", ")}` : "";
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

interface NodeData {
  id: string;
  label: string;
  cls: "core" | "gold";
  layer?: string;
  role?: string;
  scd2?: boolean;
  pii?: boolean;
  comment?: string;
  /** # of use cases this table serves; >1 renders an at-rest "shared" chip. */
  shared?: number;
  /** Use-case names this table is shared with (for the chip's title tooltip). */
  shared_with?: string[];
  columns?: ColData[];
  /** When true, the card renders ALL columns (hover expand), not the compact preview. */
  expanded?: boolean;
  /** When expanded AND the full card would overflow the viewport: cap+fade the list and
   *  show a "click to see all N columns" footer (set by graph.ts on hover). */
  expandCapped?: boolean;
  [k: string]: unknown;
}

function isKeyCol(c: ColData): boolean {
  return (
    c.pk ||
    c.fk ||
    c.pii ||
    (c.enum_values && c.enum_values.length > 0) ||
    c.name.endsWith("_sk") ||
    c.name.endsWith("_id")
  );
}

function renderColumnRow(c: ColData, highlighted: boolean): string {
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

  // Native tooltip: show the column COMMENT on hover (escaped) when present.
  // data-col lets a column/edge hover highlight this exact column row. `col-hl` is
  // DATA-DRIVEN (baked into the markup here), not toggled onto the DOM after the
  // fact: the node-html-label plugin REGENERATES this innerHTML on every render, so
  // a post-applied class is wiped a frame later. Emitting it in the template means
  // the highlight survives every re-render (design/39).
  const cls = highlighted ? "col-row col-hl" : "col-row";
  return (
    `<div class="${cls}" data-col="${esc(c.name)}"${titleAttr(c.comment)}>` +
    `<span class="col-type">${esc(c.type)}</span>` +
    `<span class="col-name">${esc(c.name)}</span>` +
    keyChips +
    piiChip +
    enumChip +
    `</div>`
  );
}

/**
 * Render a card / chip HTML string for cytoscape-node-html-label.
 *
 * `hlCols` is the set of column names to light with `.col-hl` for THIS table (the
 * active FK/PK relationship highlight). It is baked into the generated markup so
 * the highlight survives the plugin regenerating the card DOM on every render
 * (design/39); it defaults to empty (no highlight).
 */
export function renderCard(data: NodeData, hlCols?: ReadonlySet<string>): string {
  // Unit-level table node: has columns array
  if (data.columns && data.columns.length > 0) {
    const expanded = data.expanded === true;
    const cls =
      (data.cls === "gold" ? "card gold" : "card core") + (expanded ? " expanded" : "");

    // Header
    const roleLabel = data.role ? esc(data.role) : "";
    const roleChip = roleLabel ? `<span class="chip role">${roleLabel}</span>` : "";
    const scd2Chip = data.scd2 ? `<span class="chip scd2">&#x29D7; SCD2</span>` : "";

    // Shared-table affordance (at rest): a table serving >1 use case shows a
    // "shared xN" chip, with a native title listing the owning use cases so the
    // reader can find the other bands (which also light up on hover). The count
    // and every use-case name are escaped (stored-XSS guard).
    const sharedN = typeof data.shared === "number" ? data.shared : 1;
    const sharedChip =
      sharedN > 1
        ? `<span class="chip shared"` +
          titleAttr(sharedTitle(data.shared_with)) +
          `>shared &times;${esc(String(sharedN))}</span>`
        : "";

    // Native tooltip: show the table COMMENT on hover (escaped) when present.
    const header =
      `<div class="card-hd"${titleAttr(data.comment)}>` +
      `<span class="card-title">${esc(data.label)}</span>` +
      roleChip +
      scd2Chip +
      sharedChip +
      `</div>`;

    // Columns: key-ish first, then up to 8 others
    const cols: ColData[] = data.columns;
    const keyCols = cols.filter(isKeyCol);
    const otherCols = cols.filter((c) => !isKeyCol(c));

    const MAX_OTHERS = 8;
    // Hover-expanded card shows EVERY column; at rest it previews key columns + up to
    // MAX_OTHERS others and a "hover for all" hint.
    const shownOthers = expanded ? otherCols : otherCols.slice(0, MAX_OTHERS);
    const hiddenCount = otherCols.length - shownOthers.length;

    const colRows = [...keyCols, ...shownOthers]
      .map((c) => renderColumnRow(c, hlCols?.has(c.name) ?? false))
      .join("");
    const moreRow =
      !expanded && hiddenCount > 0
        ? `<div class="col-row col-more">+${hiddenCount} more &middot; hover for all ${cols.length} columns</div>`
        : "";

    // When expanded, show ALL columns. If the fully expanded card would overflow the
    // viewport (graph.ts sets `expandCapped`), the column list is height-capped and its
    // bottom faded (styles.css); this footer is the "there's more" affordance and doubles
    // as the click target - clicking the card opens the side panel with every column,
    // scrollable (hover stays a bounded peek; scrolling a transient hover is an anti-pattern).
    const capped = expanded && data.expandCapped === true;
    const listCls = capped ? "col-list capped" : "col-list";
    const expandFooter = capped
      ? `<div class="col-more col-expand-all">click to see all ${cols.length} columns</div>`
      : "";

    return (
      `<div class="${cls}" data-table="${esc(data.label)}">` +
      header +
      `<div class="${listCls}">` +
      colRows +
      moreRow +
      `</div>` +
      expandFooter +
      `</div>`
    );
  }

  // Overview unit node: compact chip
  const cls = data.cls === "gold" ? "unit-chip gold" : "unit-chip core";
  const layerBadge =
    data.cls === "gold"
      ? `<span class="chip layer-badge outcome">outcome</span>`
      : `<span class="chip layer-badge core-badge">core</span>`;

  return (
    `<div class="${cls}">` +
    `<span class="unit-label">${esc(data.label)}</span>` +
    layerBadge +
    `</div>`
  );
}
