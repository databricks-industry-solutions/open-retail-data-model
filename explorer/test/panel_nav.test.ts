import { describe, it, expect, beforeEach } from "vitest";
import type { Unit } from "../src/model";
import { openUnitPanel } from "../src/panel";

// H1: the L1 unit panel renders each table as a <button class="panel-table-link">
// styled as interactive, but no click handler was wired — clicking did nothing.
// These run in the real jsdom document (no stub) so a click actually fires.

function unitWithTables(): Unit {
  const col = (name: string) => ({
    name,
    type: "BIGINT",
    pk: false,
    fk: false,
    pii: false,
    enum_values: [] as string[],
    comment: "",
  });
  const table = (name: string): Unit["tables"][number] => ({
    name,
    comment: "",
    role: "fact",
    layer: "gold",
    materialized: true,
    scd2: false,
    columns: [col(`${name}_sk`)],
  });
  return {
    name: "promote-with-purpose",
    kind: "outcome",
    tables: [table("gold_promo"), table("gold_promo_perf")],
    relationships: [],
    checks: [],
    glossary_path: null,
    contract_path: null,
    source_url: "https://github.com/example/repo/tree/main/outcome-packages/promote-with-purpose",
    use_cases: [],
  };
}

describe("openUnitPanel: table rows navigate to L2 (H1)", () => {
  beforeEach(() => {
    document.body.innerHTML = `<aside id="panel"></aside>`;
  });

  it("renders each table as an interactive button (not a dead control)", () => {
    openUnitPanel(unitWithTables(), undefined, () => {});
    const btns = document.querySelectorAll<HTMLButtonElement>(".panel-table-link");
    expect(btns.length).toBe(2);
    expect(btns[0].tagName).toBe("BUTTON");
    expect(btns[0].getAttribute("data-table")).toBe("gold_promo");
  });

  it("clicking a table row fires onTableNav with that table's name", () => {
    const nav: string[] = [];
    openUnitPanel(unitWithTables(), undefined, (t) => nav.push(t));
    document.querySelectorAll<HTMLButtonElement>(".panel-table-link")[1].click();
    expect(nav).toEqual(["gold_promo_perf"]);
  });

  it("does not throw when no nav callback is supplied", () => {
    expect(() => openUnitPanel(unitWithTables(), undefined)).not.toThrow();
    // buttons still render; they simply no-op without a callback
    expect(document.querySelectorAll(".panel-table-link").length).toBe(2);
  });

  it("each use-case row carries an escaped data-uc-name (bridge to the graph highlight)", () => {
    const u = unitWithTables();
    u.use_cases = [
      { name: "Trade Promotion", status: "done", tables: [], consumes: [] },
      { name: "Location-Based Offers", status: "planned", tables: [], consumes: [] },
    ];
    openUnitPanel(u, undefined, () => {});
    const items = document.querySelectorAll<HTMLElement>(".panel-uc");
    expect(items[0].dataset["ucName"]).toBe("Trade Promotion");
    expect(items[1].dataset["ucName"]).toBe("Location-Based Offers");
  });

  it("hovering / clicking a MAPPED use-case row invokes the hover / click callbacks", () => {
    const u = unitWithTables();
    // Maps to a real gold table -> highlightable -> interactive row.
    u.use_cases = [{ name: "Trade Promotion", status: "done", tables: ["gold_promo"], consumes: [] }];
    const hovers: (string | null)[] = [];
    const clicks: string[] = [];
    openUnitPanel(
      u,
      undefined,
      () => {},
      (name) => hovers.push(name),
      (name) => clicks.push(name)
    );
    const li = document.querySelector<HTMLElement>(".panel-uc")!;
    expect(li.dataset["ucMapped"]).toBe("true");
    li.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true }));
    expect(hovers).toEqual(["Trade Promotion"]);
    li.dispatchEvent(new MouseEvent("mouseleave", { bubbles: true }));
    expect(hovers).toEqual(["Trade Promotion", null]); // leave passes null
    li.click();
    expect(clicks).toEqual(["Trade Promotion"]);
  });

  it("an UNMAPPED use case (no gold tables) renders a non-interactive row (M1)", () => {
    const u = unitWithTables();
    // No `tables:` -> no band -> the row must NOT be wired, so it can't read as
    // pinned while nothing lights up on the canvas (the dead-control leak).
    u.use_cases = [{ name: "Unmapped UC", status: "planned", tables: [], consumes: [] }];
    const hovers: (string | null)[] = [];
    const clicks: string[] = [];
    openUnitPanel(u, undefined, () => {}, (n) => hovers.push(n), (n) => clicks.push(n));
    const li = document.querySelector<HTMLElement>(".panel-uc")!;
    expect(li.classList.contains("unmapped")).toBe(true);
    expect(li.dataset["ucMapped"]).toBe("false");
    li.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true }));
    li.click();
    expect(hovers).toEqual([]); // not wired
    expect(clicks).toEqual([]);
  });

  it("does not throw when no use-case callbacks are supplied (rows stay inert)", () => {
    const u = unitWithTables();
    u.use_cases = [{ name: "Trade Promotion", status: "done", tables: [], consumes: [] }];
    expect(() => openUnitPanel(u, undefined, () => {})).not.toThrow();
    const li = document.querySelector<HTMLElement>(".panel-uc")!;
    expect(() => li.click()).not.toThrow();
  });

  it("renders the use-cases list with names + status dots incl. blocked (m8/M2)", () => {
    const u = unitWithTables();
    // Covers every status in the enum, including `blocked` — which no real
    // use-cases.yaml uses today, so this is the only exercise of its render path.
    u.use_cases = [
      { name: "Trade Promotion", status: "done", tables: [], consumes: [] },
      { name: "Location-Based Offers", status: "planned", tables: [], consumes: [] },
      { name: "Supplier Sync", status: "blocked", tables: [], consumes: [] },
    ];
    openUnitPanel(u, undefined, () => {});
    const items = document.querySelectorAll<HTMLElement>(".panel-uc");
    expect(items.length).toBe(3);
    expect(items[0].querySelector(".panel-uc-name")?.textContent).toBe("Trade Promotion");
    expect(items[0].querySelector(".stat.done")).not.toBeNull();
    expect(items[1].querySelector(".stat.planned")).not.toBeNull();
    expect(items[2].querySelector(".stat.blocked")).not.toBeNull();
    expect(items[2].querySelector(".panel-uc-status")?.textContent).toBe("blocked");
  });
});
