import { describe, it, expect } from "vitest";
import { modelToElements } from "../src/elements";
import type { Model } from "../src/model";

const model: Model = {
  generated_by: "t",
  overview: {
    nodes: [
      { id: "customer", label: "customer", kind: "core" },
      { id: "ucv", label: "ucv", kind: "outcome" },
    ],
    edges: [{ source: "ucv", target: "customer", kind: "consumes" }],
  },
  units: [
    {
      name: "customer",
      kind: "core",
      tables: [
        {
          name: "profile",
          comment: "Customer master.",
          role: "master",
          layer: "silver",
          materialized: true,
          scd2: true,
          columns: [
            { name: "profile_sk", type: "BIGINT", pk: true, fk: false, pii: false, enum_values: [], comment: "" },
            { name: "last_name", type: "STRING", pk: false, fk: false, pii: true, enum_values: [], comment: "" },
          ],
        },
        {
          name: "address",
          comment: "",
          role: "detail",
          layer: "silver",
          materialized: true,
          scd2: false,
          columns: [
            { name: "address_sk", type: "BIGINT", pk: true, fk: false, pii: false, enum_values: [], comment: "" },
            { name: "profile_sk", type: "BIGINT", pk: false, fk: true, pii: false, enum_values: [], comment: "" },
          ],
        },
      ],
      relationships: [
        {
          child_table: "address",
          child_cols: ["profile_sk"],
          parent_table: "profile",
          parent_cols: ["profile_sk"],
          declared_fk: true,
        },
        {
          // Cross-domain reference: the parent lives in another unit, so it is NOT
          // a node in this unit. modelToElements must drop this edge (regression:
          // it used to emit it, and cytoscape threw "Can not create edge with
          // nonexistent source" on cy.add, taking down the whole per-unit ER view).
          child_table: "address",
          child_cols: ["external_master_sk"],
          parent_table: "external_master",
          parent_cols: ["external_master_sk"],
          declared_fk: true,
        },
      ],
      checks: [],
      glossary_path: null,
      contract_path: "c",
      source_url: "https://github.com/example/repo/tree/main/canonical-core/u",
      use_cases: [],
    },
  ],
};

describe("modelToElements", () => {
  it("overview level -> unit nodes + consumes edges", () => {
    const { nodes, edges } = modelToElements(model, "overview");
    expect(nodes.map((n) => n.data.id).sort()).toEqual(["customer", "ucv"]);
    expect(nodes.find((n) => n.data.id === "customer")!.data.cls).toBe("core");
    expect(nodes.find((n) => n.data.id === "ucv")!.data.cls).toBe("gold");
    expect(edges).toHaveLength(1);
  });
  it("unit level -> table nodes + fk edges + pii flag", () => {
    const { nodes, edges } = modelToElements(model, "unit", "customer");
    expect(nodes.map((n) => n.data.id).sort()).toEqual(["address", "profile"]);
    expect(nodes.find((n) => n.data.id === "profile")!.data.pii).toBe(true);
    expect(edges).toHaveLength(1);
    expect(edges[0].data.source).toBe("profile");
    // column-level endpoints are carried on the edge for the FK/PK highlight
    expect(edges[0].data.parent_cols).toEqual(["profile_sk"]);
    expect(edges[0].data.child_cols).toEqual(["profile_sk"]);
  });

  it("threads the table comment into node data (hover-tooltip feature)", () => {
    const { nodes } = modelToElements(model, "unit", "customer");
    expect(nodes.find((n) => n.data.id === "profile")!.data.comment).toBe(
      "Customer master."
    );
  });

  it("drops cross-unit relationships so no edge references a nonexistent node", () => {
    const { nodes, edges } = modelToElements(model, "unit", "customer");
    const nodeIds = new Set(nodes.map((n) => n.data.id));
    // Every emitted edge must connect two real nodes; otherwise cytoscape's
    // cy.add throws "Can not create edge with nonexistent source" and the whole
    // ER view fails to mount.
    for (const e of edges) {
      expect(nodeIds.has(e.data.source)).toBe(true);
      expect(nodeIds.has(e.data.target)).toBe(true);
    }
    // The address -> external_master relationship (parent in another domain) is
    // not drawn, and only the intra-unit profile <- address edge remains.
    expect(edges.some((e) => e.data.target === "external_master")).toBe(false);
    expect(edges).toHaveLength(1);
  });

  it("a silver table that consumes no core carries an empty consumes_tables", () => {
    // profile is a silver master with no consumed core table, so []. This is NOT a
    // gold-only property: association/silver tables that reach core via a declared FK
    // DO carry entries (covered by the gen_model_json tests).
    const { nodes } = modelToElements(model, "unit", "customer");
    expect(nodes.find((n) => n.data.id === "profile")!.data.consumes_tables).toEqual([]);
  });

  it("threads a gold mview's silver lineage into unit node data (L1 overlay)", () => {
    const m: Model = {
      generated_by: "t",
      overview: { nodes: [], edges: [] },
      units: [
        {
          name: "acu",
          kind: "outcome",
          tables: [
            {
              name: "gold_customer_ltv",
              comment: "",
              role: "metric",
              layer: "gold",
              materialized: true,
              scd2: false,
              columns: [],
              consumes_tables: [
                { table: "customer_order_line", unit: "order" },
                { table: "product", unit: "product" },
              ],
            },
          ],
          relationships: [],
          checks: [],
          glossary_path: null,
          contract_path: null,
          source_url: "https://github.com/example/repo/tree/main/outcome-packages/u",
          use_cases: [],
        },
      ],
    };
    const { nodes } = modelToElements(m, "unit", "acu");
    expect(nodes[0].data.consumes_tables).toEqual([
      { table: "customer_order_line", unit: "order" },
      { table: "product", unit: "product" },
    ]);
  });
});
