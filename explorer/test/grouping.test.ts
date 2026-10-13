import { describe, it, expect } from "vitest";
import modelRaw from "../public/model.json?raw";
import { externalBandName, groupTablesByUseCase, UNASSIGNED_BAND } from "../src/grouping";
import type { Model, Unit, Table, UseCase } from "../src/model";

const model = JSON.parse(modelRaw) as Model;

function gold(name: string): Table {
  return {
    name,
    comment: "",
    role: "consumable",
    layer: "gold",
    materialized: true,
    scd2: false,
    columns: [],
  };
}
function silver(name: string): Table {
  return { ...gold(name), layer: "silver" };
}
function uc(name: string, tables: string[], over: Partial<UseCase> = {}): UseCase {
  return { name, status: "in-progress", tables, consumes: [], ...over };
}
function unit(tables: Table[], use_cases: UseCase[]): Unit {
  return {
    name: "u",
    kind: "outcome",
    tables,
    relationships: [],
    checks: [],
    glossary_path: null,
    contract_path: null,
    source_url: "https://github.com/example/repo/tree/main/outcome-packages/u",
    use_cases,
  };
}

describe("groupTablesByUseCase", () => {
  it("one band per use case that owns >=1 gold table, in manifest order", () => {
    const g = groupTablesByUseCase(
      unit(
        [gold("gold_a"), gold("gold_b")],
        [uc("First", ["gold_a"]), uc("Second", ["gold_b"])]
      )
    );
    expect(g.fallback).toBe(false);
    expect(g.bands.map((b) => b.name)).toEqual(["First", "Second"]);
    expect(g.bands[0].tables).toEqual(["gold_a"]);
    expect(g.bands[1].tables).toEqual(["gold_b"]);
  });

  it("draws a shared table ONCE, in its primary (first) band; others keep it as a member", () => {
    const g = groupTablesByUseCase(
      unit(
        [gold("gold_shared"), gold("gold_solo")],
        [uc("Primary", ["gold_shared"]), uc("Secondary", ["gold_shared", "gold_solo"])]
      )
    );
    const primary = g.bands.find((b) => b.name === "Primary")!;
    const secondary = g.bands.find((b) => b.name === "Secondary")!;
    // drawn only in the first band it appears in
    expect(primary.tables).toEqual(["gold_shared"]);
    expect(secondary.tables).toEqual(["gold_solo"]);
    // ...but still a MEMBER of both, so hover highlights it under either use case
    expect(primary.members).toContain("gold_shared");
    expect(secondary.members).toContain("gold_shared");
  });

  it("collects gold tables in no use case into a trailing Unassigned band", () => {
    const g = groupTablesByUseCase(
      unit(
        [gold("gold_used"), gold("gold_orphan")],
        [uc("Only", ["gold_used"])]
      )
    );
    expect(g.bands.map((b) => b.name)).toEqual(["Only", UNASSIGNED_BAND]);
    const un = g.bands.find((b) => b.name === UNASSIGNED_BAND)!;
    expect(un.tables).toEqual(["gold_orphan"]);
    expect(un.status).toBeNull();
    expect(un.consumes).toEqual([]);
  });

  it("keeps non-gold (silver) tables ungrouped, above the bands", () => {
    const g = groupTablesByUseCase(
      unit([silver("ingredient"), gold("gold_a")], [uc("A", ["gold_a"])])
    );
    expect(g.ungrouped).toEqual(["ingredient"]);
    expect(g.bands.flatMap((b) => b.tables)).not.toContain("ingredient");
  });

  it("falls back when no use case owns a gold table (flat masonry)", () => {
    // gold tables exist but nothing maps them -> only an Unassigned band would
    // form, so the caller should render the flat masonry instead.
    const g = groupTablesByUseCase(unit([gold("gold_a")], [uc("A", [])]));
    expect(g.fallback).toBe(true);
  });

  it("falls back for a package with no use cases at all", () => {
    const g = groupTablesByUseCase(unit([gold("gold_a")], []));
    expect(g.fallback).toBe(true);
  });

  it("derives sharedCount: a table in two use cases is 2, a solo table is 1", () => {
    const g = groupTablesByUseCase(
      unit(
        [gold("gold_shared"), gold("gold_solo")],
        [uc("Primary", ["gold_shared"]), uc("Secondary", ["gold_shared", "gold_solo"])]
      )
    );
    // gold_shared appears in both use cases -> 2; gold_solo in one -> 1.
    expect(g.sharedCount["gold_shared"]).toBe(2);
    expect(g.sharedCount["gold_solo"]).toBe(1);
    // sharedWith lists the owning use cases (manifest order) for the chip tooltip.
    expect(g.sharedWith["gold_shared"]).toEqual(["Primary", "Secondary"]);
    // the existing tables/members partition is untouched (drawn once, member of both).
    const primary = g.bands.find((b) => b.name === "Primary")!;
    expect(primary.tables).toEqual(["gold_shared"]);
    expect(primary.members).toContain("gold_shared");
  });

  it("carries the derived per-use-case consumes onto its band", () => {
    const g = groupTablesByUseCase(
      unit([gold("gold_a")], [uc("A", ["gold_a"], { consumes: ["product", "store"] })])
    );
    expect(g.bands[0].consumes).toEqual(["product", "store"]);
  });

  it("groups the real balancing-margin-and-volume unit into use-case bands", () => {
    const bmv = model.units.find((u) => u.name === "balancing-margin-and-volume")!;
    const g = groupTablesByUseCase(bmv);
    expect(g.fallback).toBe(false);
    // the two gold-bearing use cases surface as bands (+ possibly Unassigned)
    const names = g.bands.map((b) => b.name);
    expect(names).toContain("Dynamic Price Optimization");
    expect(names).toContain("Elasticity Modeling");
    // every gold table is drawn exactly once across all bands (no dup, no drop)
    const drawn = g.bands.flatMap((b) => b.tables);
    expect(new Set(drawn).size).toBe(drawn.length);
    const goldNames = bmv.tables.filter((t) => t.layer === "gold").map((t) => t.name).sort();
    expect([...drawn].sort()).toEqual(goldNames);
  });
});

describe("groupTablesByUseCase: other packages' use cases (external_use_cases)", () => {
  it("bands a gold view another package's use case maps to, instead of Unassigned", () => {
    const u = unit([gold("gold_a"), gold("gold_ltv")], [uc("Local", ["gold_a"])]);
    u.external_use_cases = [
      { unit: "pkg-b", name: "Lifetime Value", status: "done", tables: ["gold_ltv"], consumes: ["order"] },
    ];
    const g = groupTablesByUseCase(u);
    expect(g.bands.map((b) => b.name)).toEqual(["Local", "Lifetime Value (pkg-b)"]);
    const ext = g.bands[1];
    expect(ext.externalUnit).toBe("pkg-b");
    expect(ext.tables).toEqual(["gold_ltv"]);
    expect(ext.consumes).toEqual(["order"]);
    expect(g.bands.some((b) => b.name === UNASSIGNED_BAND)).toBe(false);
  });

  it("a view already drawn in a local band is only referenced by the external band", () => {
    const u = unit([gold("gold_ltv")], [uc("Local", ["gold_ltv"])]);
    u.external_use_cases = [
      { unit: "pkg-b", name: "Lifetime Value", status: "done", tables: ["gold_ltv"], consumes: [] },
    ];
    const g = groupTablesByUseCase(u);
    expect(g.bands[0].tables).toEqual(["gold_ltv"]);
    expect(g.bands[1].tables).toEqual([]);
    expect(g.bands[1].members).toEqual(["gold_ltv"]);
    expect(g.sharedCount["gold_ltv"]).toBe(2);
    expect(g.sharedWith["gold_ltv"]).toEqual(["Local", "Lifetime Value (pkg-b)"]);
  });

  it("names never collide with a local use case of the same name", () => {
    expect(externalBandName({ name: "Lifetime Value", unit: "pkg-b" })).toBe("Lifetime Value (pkg-b)");
  });

  it("real model: ACU's gold_customer_ltv is banded under UCV's Customer Lifetime Value", () => {
    const acu = model.units.find((x) => x.name === "actionable-customer-understanding")!;
    const g = groupTablesByUseCase(acu);
    const band = g.bands.find((b) => b.name === "Customer Lifetime Value (unified-customer-view)");
    expect(band?.tables).toContain("gold_customer_ltv");
    const unassigned = g.bands.find((b) => b.name === UNASSIGNED_BAND);
    expect(unassigned?.tables ?? []).not.toContain("gold_customer_ltv");
  });
});
