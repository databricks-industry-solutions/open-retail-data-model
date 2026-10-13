import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { Unit } from "../src/model";
import { openPanel, openUnitPanel } from "../src/panel";

// Mnr2: openPanel() writes a template string into panel.innerHTML. Every table
// field (label, role) plus every column field (name, type, comment, enum value)
// and both unit link paths (glossary_path, contract_path) MUST route through
// escapeHtml/safeHref, or a hostile model.json is stored XSS.
//
// The project has no jsdom/happy-dom configured and we add no dependency, so we
// install a minimal DOM stub: openPanel only needs getElementById, the
// innerHTML setter, classList.add, style, and querySelector/addEventListener.
// We assert against the innerHTML string the function produced.

const XSS = `<script>alert(1)</script>`;

class StubElement {
  innerHTML = "";
  style: Record<string, string> = {};
  classList = { add() {}, remove() {} };
  querySelector(): StubElement | null {
    // Return an object that swallows addEventListener; the close button is not
    // under test here.
    return { addEventListener() {} } as unknown as StubElement;
  }
}

let panelEl: StubElement;

beforeEach(() => {
  panelEl = new StubElement();
  (globalThis as unknown as { document: unknown }).document = {
    getElementById: (id: string) => (id === "panel" ? panelEl : null),
  };
});

afterEach(() => {
  delete (globalThis as unknown as { document?: unknown }).document;
});

function unit(overrides: Partial<Unit> = {}): Unit {
  return {
    name: "customer",
    kind: "core",
    tables: [],
    relationships: [],
    checks: [],
    glossary_path: null,
    contract_path: "contracts/customer.odcs.yaml",
    source_url: "https://github.com/databricks-industry-solutions/open-retail-data-model/tree/main/canonical-core/customer",
    use_cases: [],
    ...overrides,
  };
}

describe("openPanel() escaping (Mnr2)", () => {
  it("escapes label, role, and every column string field", () => {
    openPanel(
      {
        id: "t",
        label: XSS,
        cls: "core",
        role: XSS,
        scd2: false,
        columns: [
          {
            name: XSS,
            type: XSS,
            pk: true,
            fk: false,
            pii: true,
            enum_values: [XSS, "b"],
            comment: XSS,
          },
        ],
      },
      unit()
    );

    expect(panelEl.innerHTML).not.toContain("<script>");
    expect(panelEl.innerHTML).not.toContain("</script>");
    expect(panelEl.innerHTML).toContain("&lt;script&gt;");
  });

  it("routes glossary_path / contract_path through safeHref (blocks javascript:)", () => {
    openPanel(
      { id: "t", label: "T", cls: "core", columns: [] },
      unit({
        glossary_path: "javascript:alert(1)",
        contract_path: "contracts/ok.yaml",
      })
    );

    // javascript: URL must not survive as an executable href
    expect(panelEl.innerHTML).not.toContain("javascript:alert(1)");
    // safeHref collapses a rejected scheme to "#"
    expect(panelEl.innerHTML).toContain(`href="#"`);
    // the clean relative path passes through
    expect(panelEl.innerHTML).toContain(`contracts/ok.yaml`);
  });

  it("escapes a quote/markup smuggled through a link path", () => {
    openPanel(
      { id: "t", label: "T", cls: "core", columns: [] },
      unit({
        glossary_path: `path"><script>alert(1)</script>`,
        contract_path: "contracts/ok.yaml",
      })
    );
    expect(panelEl.innerHTML).not.toContain("<script>");
  });

  it("renders contract/glossary as base-aware links that open in a new tab", () => {
    openPanel(
      { id: "t", label: "T", cls: "core", columns: [] },
      unit({
        glossary_path: "canonical-core/customer/glossary.md",
        contract_path: "contracts/odcs/customer.odcs.yaml",
      })
    );
    // base-prefixed (BASE_URL is "/" under vitest), never a bare site-absolute
    // path, so it resolves to the staged raw file regardless of the hash route.
    expect(panelEl.innerHTML).toContain(`href="/contracts/odcs/customer.odcs.yaml"`);
    expect(panelEl.innerHTML).toContain(`href="/canonical-core/customer/glossary.md"`);
    // new tab, safely
    expect(panelEl.innerHTML).toContain(`target="_blank"`);
    expect(panelEl.innerHTML).toContain(`rel="noopener"`);
  });

  it("shows the table comment (escaped) and omits it when empty", () => {
    openPanel(
      { id: "t", label: "T", cls: "core", comment: XSS, columns: [] },
      unit()
    );
    expect(panelEl.innerHTML).toContain("panel-table-comment");
    expect(panelEl.innerHTML).not.toContain("<script>");
    expect(panelEl.innerHTML).toContain("&lt;script&gt;");

    openPanel({ id: "t", label: "T", cls: "core", comment: "", columns: [] }, unit());
    expect(panelEl.innerHTML).not.toContain("panel-table-comment");
  });
});

describe("GitHub source link (both panels)", () => {
  const SRC = "https://github.com/databricks-industry-solutions/open-retail-data-model/tree/main/outcome-packages/unified-customer-view";

  it("renders a third link to the unit's GitHub folder, after Glossary and Contract", () => {
    const u = unit({
      name: "unified-customer-view",
      kind: "outcome",
      glossary_path: "outcome-packages/unified-customer-view/glossary.md",
      contract_path: "contracts/odcs/unified-customer-view.odcs.yaml",
      source_url: SRC,
    });
    for (const open of [
      () => openPanel({ id: "t", label: "T", cls: "gold", columns: [] }, u),
      () => openUnitPanel(u),
    ]) {
      open();
      const html = panelEl.innerHTML;
      // absolute, NOT rebased under the site base like the staged glossary/contract
      expect(html).toContain(`href="${SRC}" target="_blank" rel="noopener">GitHub</a>`);
      expect(html.indexOf(">Glossary<")).toBeLessThan(html.indexOf(">Contract<"));
      expect(html.indexOf(">Contract<")).toBeLessThan(html.indexOf(">GitHub<"));
    }
  });

  it("omits the link unless source_url is https:// (blocks javascript: and //host)", () => {
    const bad = [
      "javascript:alert(1)",
      "//evil.example/x",
      "http://example.com/x",
      " https://x",
      "https://x/\ty",
      "",
    ];
    for (const src of bad) {
      openPanel({ id: "t", label: "T", cls: "core", columns: [] }, unit({ source_url: src }));
      expect(panelEl.innerHTML).not.toContain(">GitHub<");
      expect(panelEl.innerHTML).toContain(">Contract<"); // the rest of the row still renders
    }
  });
});

describe("openUnitPanel() use-case planning tier", () => {
  it("lists the package's use cases with their status", () => {
    openUnitPanel(
      unit({
        name: "promote-with-purpose",
        kind: "outcome",
        use_cases: [
          { name: "Trade Promotion", status: "done", tables: [], consumes: [] },
          { name: "Location-Based Offers", status: "planned", tables: [], consumes: [] },
        ],
      })
    );
    expect(panelEl.innerHTML).toContain("panel-uc-list");
    expect(panelEl.innerHTML).toContain("Trade Promotion");
    expect(panelEl.innerHTML).toContain("Location-Based Offers");
    expect(panelEl.innerHTML).toContain(`data-uc-status="done"`);
    expect(panelEl.innerHTML).toContain(`data-uc-status="planned"`);
  });

  it("omits the use-case section for a unit with none (core domain)", () => {
    openUnitPanel(unit({ use_cases: [] }));
    expect(panelEl.innerHTML).not.toContain("panel-uc-list");
  });

  it("a use case served by another package's view links to it and stays non-interactive", () => {
    openUnitPanel(
      unit({
        name: "unified-customer-view",
        kind: "outcome",
        use_cases: [
          {
            name: "Customer Lifetime Value",
            status: "done",
            tables: [],
            consumes: ["order"],
            foreign_tables: [{ unit: "actionable-customer-understanding", table: "gold_customer_ltv" }],
          },
        ],
      })
    );
    const html = panelEl.innerHTML;
    expect(html).toContain(`data-uc-name="Customer Lifetime Value" data-uc-mapped="false"`);
    expect(html).toContain(`title="Served by another package&#39;s gold view"`);
    expect(html).toContain(`class="panel-uc-foreign" href="#/u/actionable-customer-understanding/gold_customer_ltv"`);
  });

  it("lists other packages' use cases this package serves under 'Also serves'", () => {
    openUnitPanel(
      unit({
        name: "actionable-customer-understanding",
        kind: "outcome",
        tables: [
          { name: "gold_customer_ltv", comment: "", role: "consumable", layer: "gold", materialized: true, scd2: false, columns: [] },
        ],
        use_cases: [{ name: "Behavioral Segmentation", status: "done", tables: [], consumes: [] }],
        external_use_cases: [
          { unit: "unified-customer-view", name: "Customer Lifetime Value", status: "done", tables: ["gold_customer_ltv"], consumes: [] },
        ],
      })
    );
    expect(panelEl.innerHTML).toContain("Also serves");
    expect(panelEl.innerHTML).toContain(
      `data-uc-name="Customer Lifetime Value (unified-customer-view)" data-uc-mapped="true"`
    );
  });

  it("escapes use-case names (a hostile manifest is stored XSS otherwise)", () => {
    openUnitPanel(
      unit({ kind: "outcome", use_cases: [{ name: XSS, status: "planned", tables: [], consumes: [] }] })
    );
    expect(panelEl.innerHTML).not.toContain("<script>");
    expect(panelEl.innerHTML).toContain("&lt;script&gt;");
  });
});
