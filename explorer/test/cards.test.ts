import { describe, it, expect } from "vitest";
import { renderCard } from "../src/cards";

// Mnr2: renderCard() builds an innerHTML string that is injected into the
// cytoscape node HTML label. Every string field it renders MUST route through
// escapeHtml, otherwise a hostile model.json (name / comment / enum value /
// role / label) becomes stored XSS. These tests feed a <script> payload and a
// double-quote into every string-bearing field and assert the raw markup never
// survives unescaped.

const XSS = `<script>alert(1)</script>`;
const QUOTE = `a"b`;

function tableNode(overrides: Record<string, unknown> = {}) {
  return {
    id: "t",
    label: XSS,
    cls: "core" as const,
    role: XSS,
    scd2: false,
    columns: [
      {
        name: XSS,
        type: QUOTE,
        pk: true,
        fk: false,
        pii: true,
        enum_values: [XSS, "other"],
        comment: XSS,
      },
    ],
    ...overrides,
  };
}

describe("renderCard() escaping (Mnr2)", () => {
  it("escapes every string field of a table node", () => {
    const html = renderCard(tableNode() as Parameters<typeof renderCard>[0]);
    // No raw <script> anywhere
    expect(html).not.toContain("<script>");
    expect(html).not.toContain("</script>");
    // Payload is present but escaped
    expect(html).toContain("&lt;script&gt;");
    // Raw double-quote from a data value must not leak into markup
    expect(html).toContain("&quot;");
  });

  it("escapes the label and layer badge on an overview (chip) node", () => {
    const html = renderCard({
      id: "u",
      label: XSS,
      cls: "gold" as const,
    } as Parameters<typeof renderCard>[0]);
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });

  it("escapes the enum preview value", () => {
    const html = renderCard(
      tableNode({
        columns: [
          {
            name: "status",
            type: "string",
            pk: false,
            fk: false,
            pii: false,
            enum_values: [XSS],
            comment: "",
          },
        ],
      }) as Parameters<typeof renderCard>[0]
    );
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });
});

// Hover-tooltip feature: renderCard adds a native `title="..."` to the card header
// (table COMMENT) and to each column row (column COMMENT). The comment MUST be
// escaped and MUST be omitted entirely when empty.
describe("renderCard() comment tooltips", () => {
  it("adds a title on the header from the table comment (escaped)", () => {
    const html = renderCard(
      tableNode({
        comment: `Table comment "quoted".`,
        columns: [
          { name: "id", type: "BIGINT", pk: true, fk: false, pii: false, enum_values: [], comment: "" },
        ],
      }) as Parameters<typeof renderCard>[0]
    );
    // header carries the escaped table comment as a title attribute
    expect(html).toContain(`title="Table comment &quot;quoted&quot;."`);
  });

  it("adds a title on a column row from the column comment", () => {
    const html = renderCard(
      tableNode({
        comment: "",
        columns: [
          { name: "id", type: "BIGINT", pk: true, fk: false, pii: false, enum_values: [], comment: "The surrogate key." },
        ],
      }) as Parameters<typeof renderCard>[0]
    );
    expect(html).toContain(`class="col-row" data-col="id" title="The surrogate key."`);
  });

  it("escapes a hostile comment in the title (no XSS breakout)", () => {
    const html = renderCard(
      tableNode({
        comment: `x"><img src=x onerror=alert(1)>`,
        columns: [
          { name: "id", type: "BIGINT", pk: true, fk: false, pii: false, enum_values: [], comment: XSS },
        ],
      }) as Parameters<typeof renderCard>[0]
    );
    expect(html).not.toContain(`<img`);
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });

  it("omits the title attribute when the comment is empty", () => {
    const html = renderCard(
      tableNode({
        comment: "",
        columns: [
          { name: "id", type: "BIGINT", pk: true, fk: false, pii: false, enum_values: [], comment: "" },
        ],
      }) as Parameters<typeof renderCard>[0]
    );
    // no stray empty title="" on header or column row
    expect(html).not.toContain(`title=""`);
    expect(html).toContain(`class="card-hd">`);
    expect(html).toContain(`class="col-row" data-col="id">`);
  });
});

// Shared-table affordance (design/38 §5): a table serving >1 use case shows an
// at-rest "shared xN" chip carrying a native title listing the owning use cases.
// A solo (or unset) table shows no chip. Both the count and the use-case names
// route through escapeHtml.
describe("renderCard() shared-table chip", () => {
  it("renders a .chip.shared with count + title when shared > 1", () => {
    const html = renderCard(
      tableNode({
        label: "gold_x",
        comment: "",
        shared: 3,
        shared_with: ["Alpha", "Beta", "Gamma"],
        columns: [
          { name: "id", type: "BIGINT", pk: true, fk: false, pii: false, enum_values: [], comment: "" },
        ],
      }) as Parameters<typeof renderCard>[0]
    );
    expect(html).toContain(`class="chip shared"`);
    // count rendered (× is entity-encoded in the markup)
    expect(html).toContain(`shared &times;3`);
    // native tooltip lists the owning use cases
    expect(html).toContain(`title="Also in: Alpha, Beta, Gamma"`);
  });

  it("does NOT render a shared chip for a solo table (shared === 1)", () => {
    const html = renderCard(
      tableNode({
        shared: 1,
        shared_with: ["Only"],
        comment: "",
        columns: [
          { name: "id", type: "BIGINT", pk: true, fk: false, pii: false, enum_values: [], comment: "" },
        ],
      }) as Parameters<typeof renderCard>[0]
    );
    expect(html).not.toContain(`chip shared`);
  });

  it("does NOT render a shared chip when shared is absent (defaults to solo)", () => {
    const html = renderCard(
      tableNode({
        comment: "",
        columns: [
          { name: "id", type: "BIGINT", pk: true, fk: false, pii: false, enum_values: [], comment: "" },
        ],
      }) as Parameters<typeof renderCard>[0]
    );
    expect(html).not.toContain(`chip shared`);
  });

  it("escapes hostile use-case names in the shared chip title (no breakout)", () => {
    const html = renderCard(
      tableNode({
        shared: 2,
        shared_with: [`x"><img src=x onerror=alert(1)>`, "safe"],
        comment: "",
        columns: [
          { name: "id", type: "BIGINT", pk: true, fk: false, pii: false, enum_values: [], comment: "" },
        ],
      }) as Parameters<typeof renderCard>[0]
    );
    expect(html).toContain(`class="chip shared"`);
    expect(html).not.toContain(`<img`);
    expect(html).toContain(`&quot;`); // the double-quote survived only as an entity
  });
});

describe("renderCard() hover-expand (all columns)", () => {
  const many = {
    id: "t",
    label: "gold_x",
    cls: "gold" as const,
    role: "gold",
    scd2: false,
    columns: Array.from({ length: 14 }, (_, i) => ({
      name: `c${i}`,
      type: "STRING",
      pk: false,
      fk: false,
      pii: false,
      enum_values: [] as string[],
      comment: "",
    })),
  };
  it("at rest: truncates and shows a 'hover for all' hint", () => {
    const html = renderCard(many as Parameters<typeof renderCard>[0]);
    expect(html).toContain("hover for all 14 columns");
    expect(html).not.toContain("expanded");
    expect((html.match(/col-row/g) || []).length).toBeLessThan(14);
  });
  it("expanded: renders every column and no 'more' row", () => {
    const html = renderCard({ ...many, expanded: true } as Parameters<typeof renderCard>[0]);
    expect(html).toContain("card gold expanded");
    expect(html).not.toContain("more");
    for (let i = 0; i < 14; i++) expect(html).toContain(`>c${i}</span>`);
  });
  it("expanded + capped: caps the list and shows a 'click to see all' footer, not a scrollbar", () => {
    // When graph.ts flags expandCapped (the fully expanded card would overflow the
    // viewport), the list is clipped+faded (styles.css) and a click-to-open affordance
    // names the total - hover stays a bounded peek; full scroll lives in the side panel.
    const html = renderCard({ ...many, expanded: true, expandCapped: true } as Parameters<typeof renderCard>[0]);
    expect(html).toContain("col-list capped"); // the clip+fade class
    expect(html).toContain("col-expand-all"); // the footer
    expect(html).toContain("click to see all 14 columns");
    for (let i = 0; i < 14; i++) expect(html).toContain(`>c${i}</span>`); // all rows still in the DOM
  });
  it("expanded but NOT capped: no cap class, no footer (card fits)", () => {
    const html = renderCard({ ...many, expanded: true } as Parameters<typeof renderCard>[0]);
    expect(html).toContain('class="col-list"'); // plain, uncapped
    expect(html).not.toContain("col-list capped");
    expect(html).not.toContain("col-expand-all");
  });
});
