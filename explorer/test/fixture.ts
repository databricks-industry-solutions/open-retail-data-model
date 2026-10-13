import type { Model, Unit, Table, Column } from "../src/model";
import { clearAll } from "../src/storage";

/**
 * A compact but structurally-faithful Model fixture for the DOM integration
 * tests: the 12 canonical-core domains + the 12 outcome packages the layered value-chain design
 * theme map expects, a couple of PII columns, and a few `consumes` edges so the
 * hover/matrix relationships have something to draw.
 */

function col(name: string, over: Partial<Column> = {}): Column {
  return { name, type: "STRING", pk: false, fk: false, pii: false, enum_values: [], comment: "", ...over };
}

function table(name: string, over: Partial<Table> = {}): Table {
  return {
    name,
    comment: "",
    role: "master",
    layer: "silver",
    materialized: true,
    scd2: false,
    columns: [col(`${name}_sk`, { pk: true, type: "BIGINT" })],
    ...over,
  };
}

function coreUnit(name: string, over: Partial<Unit> = {}): Unit {
  return {
    name,
    kind: "core",
    tables: [table(name)],
    relationships: [],
    checks: [],
    glossary_path: `canonical-core/${name}/glossary.md`,
    contract_path: `contracts/odcs/${name}.odcs.yaml`,
    source_url: `https://github.com/databricks-industry-solutions/open-retail-data-model/tree/main/canonical-core/${name}`,
    use_cases: [], // core domains carry no planning-tier use cases
    ...over,
  };
}

function outcomeUnit(name: string, over: Partial<Unit> = {}): Unit {
  return {
    name,
    kind: "outcome",
    tables: [],
    relationships: [],
    checks: [],
    glossary_path: `outcome-packages/${name}/glossary.md`,
    contract_path: `contracts/odcs/${name}.odcs.yaml`,
    source_url: `https://github.com/databricks-industry-solutions/open-retail-data-model/tree/main/outcome-packages/${name}`,
    use_cases: [],
    ...over,
  };
}

const CORE = [
  "calendar",
  "customer",
  "inventory",
  "logistics",
  "marketing",
  "order",
  "payment",
  "procurement",
  "product",
  "store",
  "supplier",
  "transaction",
];

const OUTCOME = [
  "unified-customer-view",
  "actionable-customer-understanding",
  "agentic-commerce",
  "commerce-media-networks",
  "balancing-margin-and-volume",
  "promote-with-purpose",
  "early-risk-detection",
  "smarter-demand-and-inventory-decisions",
  "data-sharing-with-suppliers",
  "connected-store-signals",
  "predictive-operations",
  "ai-assisted-store-associates",
];

export function makeModel(): Model {
  const coreUnits = CORE.map((n) => {
    // give `customer` and `payment` PII so PII-only filtering has something to keep
    if (n === "customer") {
      return coreUnit("customer", {
        tables: [
          table("profile", {
            role: "master",
            scd2: true,
            columns: [
              col("profile_sk", { pk: true, type: "BIGINT" }),
              col("email", { pii: true }),
            ],
          }),
        ],
        relationships: [
          {
            child_table: "profile",
            child_cols: ["profile_sk"],
            parent_table: "profile",
            parent_cols: ["profile_sk"],
            declared_fk: true,
          },
        ],
      });
    }
    if (n === "payment") {
      return coreUnit("payment", {
        tables: [table("payment", { columns: [col("pan", { pii: true })] })],
      });
    }
    return coreUnit(n);
  });

  const outcomeUnits = OUTCOME.map((n) => {
    // promote-with-purpose and early-risk-detection are "built" (tables + rels)
    if (n === "promote-with-purpose") {
      return outcomeUnit(n, {
        tables: [table("gold_promo", { layer: "gold" }), table("gold_promo_perf", { layer: "gold" })],
        relationships: [
          {
            child_table: "gold_promo_perf",
            child_cols: ["gold_promo_sk"],
            parent_table: "gold_promo",
            parent_cols: ["gold_promo_sk"],
            declared_fk: true,
          },
        ],
        // planning-tier use cases (name + status), in manifest order
        use_cases: [
          { name: "Trade Promotion", status: "done", tables: [], consumes: [] },
          { name: "Location-Based Offers", status: "planned", tables: [], consumes: [] },
          { name: "Post-Promotion ROI Analysis", status: "done", tables: [], consumes: [] },
        ],
      });
    }
    if (n === "early-risk-detection") {
      return outcomeUnit(n, {
        tables: [table("gold_risk", { layer: "gold" })],
        relationships: [
          {
            child_table: "gold_risk",
            child_cols: ["gold_risk_sk"],
            parent_table: "gold_risk",
            parent_cols: ["gold_risk_sk"],
            declared_fk: true,
          },
        ],
      });
    }
    // actionable-customer-understanding is "in-progress" (tables, no rels)
    if (n === "actionable-customer-understanding") {
      return outcomeUnit(n, { tables: [table("gold_acu", { layer: "gold" })] });
    }
    return outcomeUnit(n); // planned
  });

  return {
    generated_by: "test",
    overview: {
      nodes: [
        ...CORE.map((id) => ({ id, label: id, kind: "core" as const })),
        ...OUTCOME.map((id) => ({ id, label: id, kind: "outcome" as const })),
      ],
      edges: [
        { source: "promote-with-purpose", target: "product", kind: "consumes" },
        { source: "promote-with-purpose", target: "marketing", kind: "consumes" },
        { source: "promote-with-purpose", target: "store", kind: "consumes" },
        { source: "early-risk-detection", target: "supplier", kind: "consumes" },
        { source: "early-risk-detection", target: "product", kind: "consumes" },
      ],
    },
    units: [...coreUnits, ...outcomeUnits],
  };
}

/**
 * Build the DOM skeleton index.html provides, so mountApp() has its mount points.
 */
export function installDom(): void {
  document.body.innerHTML =
    `<header id="toolbar"></header>` +
    `<div id="hint" hidden></div>` +
    `<div id="main">` +
    `<div id="stage">` +
    `<div id="overview-root"></div>` +
    `<div id="cy" hidden></div>` +
    `<div id="loading">Loading model…</div>` +
    `</div>` +
    `<aside id="panel"></aside>` +
    `</div>` +
    `<footer id="legend"></footer>`;
  // reset hash + storage between tests
  window.location.hash = "";
  clearAll();
}
