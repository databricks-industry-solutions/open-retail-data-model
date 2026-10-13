import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mountApp, type AppHandle } from "../src/main";
import { makeModel, installDom } from "./fixture";

/**
 * DOM/integration tests — the reason the filter/search/back/theme bugs shipped
 * was that the old suite only tested the pure matches() predicate against a fake
 * cytoscape, so dead filters passed CI. These MOUNT the real app against jsdom
 * and assert observable BEHAVIOUR.
 */

let app: AppHandle;

/** Poll until `cond` is true (jsdom back()/popstate is async). */
async function waitFor(cond: () => boolean, timeout = 1000): Promise<void> {
  const start = Date.now();
  while (!cond()) {
    if (Date.now() - start > timeout) throw new Error("waitFor timed out");
    await new Promise((r) => setTimeout(r, 5));
  }
}

function visibleCards(): HTMLElement[] {
  return Array.from(
    document.querySelectorAll<HTMLElement>(".pkg:not(.hidden), .dom:not(.hidden)")
  );
}
function visiblePkgs(): HTMLElement[] {
  return Array.from(document.querySelectorAll<HTMLElement>(".pkg:not(.hidden)"));
}
function visibleDoms(): HTMLElement[] {
  return Array.from(document.querySelectorAll<HTMLElement>(".dom:not(.hidden)"));
}
function readout(): string {
  return document.getElementById("status-readout")?.textContent ?? "";
}
function setInput(id: string, value: string): void {
  const el = document.getElementById(id) as HTMLInputElement;
  el.value = value;
  el.dispatchEvent(new Event("input"));
}

beforeEach(() => {
  installDom();
  app = mountApp(makeModel());
});

// Tear the app down between tests so its document/window listeners don't leak
// onto the shared jsdom globals and fire stale over a later test's DOM (M1).
afterEach(() => app.destroy());

describe("L0 landing renders the layered value-chain", () => {
  it("renders 12 packages in 4 themes and 12 core domains", () => {
    expect(document.querySelectorAll(".theme").length).toBe(4);
    expect(document.querySelectorAll(".pkg").length).toBe(12);
    expect(document.querySelectorAll(".dom").length).toBe(12);
  });

  it("shows a persistent legend and a dismissible onboarding hint", () => {
    expect(document.getElementById("legend")!.textContent).toMatch(/PII/);
    const hint = document.getElementById("hint")!;
    expect(hint.hidden).toBe(false);
    (hint.querySelector(".hint-close") as HTMLButtonElement).click();
    expect(hint.hidden).toBe(true);
  });

  it("derives status from the model (built / in-progress / planned)", () => {
    const built = document.querySelector('.pkg[data-unit="promote-with-purpose"]')!;
    const inProg = document.querySelector('.pkg[data-unit="actionable-customer-understanding"]')!;
    const planned = document.querySelector('.pkg[data-unit="agentic-commerce"]')!;
    expect(built.getAttribute("data-status")).toBe("built");
    expect(inProg.getAttribute("data-status")).toBe("in-progress");
    expect(planned.getAttribute("data-status")).toBe("planned");
  });

  it("renders a package's use-case names + statuses as a sub-list", () => {
    // promote-with-purpose has three use cases in the fixture (manifest order).
    const card = document.querySelector('.pkg[data-unit="promote-with-purpose"]')!;
    const items = Array.from(card.querySelectorAll<HTMLElement>(".uc-list .uc"));
    expect(items.map((li) => li.querySelector(".uc-name")!.textContent)).toEqual([
      "Trade Promotion",
      "Location-Based Offers",
      "Post-Promotion ROI Analysis",
    ]);
    // status drives both the data attribute and the shared status-dot class
    expect(items.map((li) => li.dataset["ucStatus"])).toEqual(["done", "planned", "done"]);
    expect(items[0].querySelector(".stat.done")).not.toBeNull();
    expect(items[1].querySelector(".stat.planned")).not.toBeNull();
  });

  it("shows no use-case sub-list for a package with none", () => {
    // agentic-commerce is "planned" with no use_cases in the fixture.
    const card = document.querySelector('.pkg[data-unit="agentic-commerce"]')!;
    expect(card.querySelector(".uc-list")).toBeNull();
  });
});

describe("search reduces the visible entity count (bug 4)", () => {
  it("typing a query hides non-matching cards and updates the readout", async () => {
    const total = visibleCards().length;
    expect(total).toBe(24);
    expect(readout()).toBe("showing 24 of 24");

    setInput("filter-q", "customer");
    // search input is debounced (~120ms) — wait for it to take effect.
    await waitFor(() => visibleCards().length < total);
    const after = visibleCards();
    expect(after.length).toBeGreaterThan(0);
    // every visible card actually matches the query
    for (const c of after) {
      const label = (c.querySelector(".pname, .dname")!.textContent ?? "").toLowerCase();
      const unit = (c.dataset["unit"] ?? "").toLowerCase();
      expect(label.includes("customer") || unit.includes("customer")).toBe(true);
    }
    expect(readout()).toMatch(/showing \d+ of 24 · \d+ hidden/);
  });

  it("a no-match query shows the empty state", async () => {
    setInput("filter-q", "zzzz-nothing-matches");
    await waitFor(() => visibleCards().length === 0);
    expect(visibleCards().length).toBe(0);
    expect(document.querySelector(".ov-empty")!.hasAttribute("hidden")).toBe(false);
    expect(readout()).toMatch(/showing 0 of 24/);
  });
});

describe("PII-only hides non-PII entities (bug 3)", () => {
  it("checking PII only keeps only PII-bearing cards", () => {
    const pii = document.getElementById("filter-pii") as HTMLInputElement;
    pii.checked = true;
    pii.dispatchEvent(new Event("change"));

    const shown = visibleCards();
    expect(shown.length).toBeGreaterThan(0);
    expect(shown.length).toBeLessThan(24);
    for (const c of shown) {
      expect(c.dataset["pii"]).toBe("true");
    }
    // customer + payment are the PII core domains in the fixture
    expect(document.querySelector('.dom[data-unit="customer"]')!.classList.contains("hidden")).toBe(
      false
    );
    expect(document.querySelector('.dom[data-unit="calendar"]')!.classList.contains("hidden")).toBe(
      true
    );
  });
});

describe("layer dropdown hides the other layer (bug 5)", () => {
  it("layer=core shows only core domains; layer=outcome shows only packages", () => {
    const sel = document.getElementById("filter-layer") as HTMLSelectElement;

    sel.value = "core";
    sel.dispatchEvent(new Event("change"));
    expect(visiblePkgs().length).toBe(0);
    expect(visibleDoms().length).toBe(12);
    expect(readout()).toBe("showing 12 of 24 · 12 hidden");

    sel.value = "outcome";
    sel.dispatchEvent(new Event("change"));
    expect(visiblePkgs().length).toBe(12);
    expect(visibleDoms().length).toBe(0);

    sel.value = "all";
    sel.dispatchEvent(new Event("change"));
    expect(visibleCards().length).toBe(24);
  });
});

describe("filters compose as AND (combined coverage)", () => {
  it("layer=core + PII-only keeps only PII-bearing CORE domains", () => {
    const sel = document.getElementById("filter-layer") as HTMLSelectElement;
    sel.value = "core";
    sel.dispatchEvent(new Event("change"));
    const pii = document.getElementById("filter-pii") as HTMLInputElement;
    pii.checked = true;
    pii.dispatchEvent(new Event("change"));

    const shown = visibleCards();
    expect(shown.length).toBeGreaterThan(0);
    expect(visiblePkgs().length).toBe(0); // outcome packages fail the core filter
    for (const c of shown) {
      expect(c.dataset["kind"]).toBe("core"); // AND: core
      expect(c.dataset["pii"]).toBe("true"); // AND: PII-bearing
    }
    // customer (PII core) survives both; calendar (non-PII core) is filtered by PII.
    expect(document.querySelector('.dom[data-unit="customer"]')!.classList.contains("hidden")).toBe(false);
    expect(document.querySelector('.dom[data-unit="calendar"]')!.classList.contains("hidden")).toBe(true);
  });

  it("PII-only + query keeps only cards matching BOTH predicates", async () => {
    const matchesCustomer = (c: HTMLElement): boolean => {
      const label = (c.querySelector(".pname, .dname")!.textContent ?? "").toLowerCase();
      const unit = (c.dataset["unit"] ?? "").toLowerCase();
      return label.includes("customer") || unit.includes("customer");
    };
    // Apply the (debounced) query FIRST and wait until it has actually settled -
    // every visible card matches "customer" - so we do not assert during the
    // debounce window.
    setInput("filter-q", "customer");
    await waitFor(() => {
      const cards = visibleCards();
      return cards.length > 0 && cards.every(matchesCustomer);
    });
    // Now add PII-only (synchronous). The result must satisfy BOTH predicates.
    const pii = document.getElementById("filter-pii") as HTMLInputElement;
    pii.checked = true;
    pii.dispatchEvent(new Event("change"));
    const shown = visibleCards();
    expect(shown.length).toBeGreaterThan(0);
    for (const c of shown) {
      expect(c.dataset["pii"]).toBe("true"); // AND: PII
      expect(matchesCustomer(c)).toBe(true); // AND: query
    }
  });
});

describe("drill into an entity, then Back returns to the overview (bug 1)", () => {
  it("clicking a domain pushes history; browser Back restores L0", async () => {
    const startLen = history.length;
    // click a core-domain card -> drill into unit (L1)
    (document.querySelector('.dom[data-unit="customer"]') as HTMLButtonElement).click();

    expect(window.location.hash).toBe("#/u/customer");
    expect(history.length).toBe(startLen + 1); // real history entry
    // breadcrumb reflects the drill, using the HUMANIZED unit label (m1), not the slug
    expect(document.querySelector(".crumbs")!.textContent).toMatch(/Customer/);
    // back button becomes available
    expect((document.getElementById("back-btn") as HTMLButtonElement).hidden).toBe(false);

    // browser Back — jsdom rolls back the hash + fires popstate asynchronously.
    history.back();
    await waitFor(() => app.router.current().unit === undefined);

    // L0 overview is shown again
    expect(app.router.current()).toEqual({ view: "overview" });
    expect(document.querySelectorAll(".pkg").length).toBe(12);
    expect((document.getElementById("overview-root") as HTMLElement).hidden).toBe(false);
  });

  it("a filter set on L0 is still applied after a drill -> Back round-trip (m3)", async () => {
    // Set PII-only on L0; it narrows the set.
    const pii = document.getElementById("filter-pii") as HTMLInputElement;
    pii.checked = true;
    pii.dispatchEvent(new Event("change"));
    const filtered = visibleCards().length;
    expect(filtered).toBeLessThan(24);

    // Drill into a PII core domain, then browser Back to L0.
    (document.querySelector('.dom[data-unit="customer"]') as HTMLButtonElement).click();
    expect(window.location.hash).toBe("#/u/customer");
    history.back();
    await waitFor(() => app.router.current().unit === undefined);

    // filterState survives at module scope and is re-applied on L0 re-mount: the
    // checkbox is re-checked and the same reduced, all-PII set is shown.
    expect((document.getElementById("filter-pii") as HTMLInputElement).checked).toBe(true);
    expect(visibleCards().length).toBe(filtered);
    for (const c of visibleCards()) expect(c.dataset["pii"]).toBe("true");
  });

  it("the Back button steps up a level", async () => {
    (document.querySelector('.dom[data-unit="product"]') as HTMLButtonElement).click();
    expect(window.location.hash).toBe("#/u/product");
    (document.getElementById("back-btn") as HTMLButtonElement).click();
    // Stepping up from a drilled-in level POPs (history.back), so it resolves on the
    // next tick via popstate - the same path browser Back already uses.
    await waitFor(() => app.router.current().unit === undefined);
    expect(app.router.current()).toEqual({ view: "overview" });
    expect(document.querySelectorAll(".pkg").length).toBe(12);
  });

  it("a single ESC at the L1 unit view steps up to L0 (M1: no orphan state)", async () => {
    (document.querySelector('.dom[data-unit="customer"]') as HTMLButtonElement).click();
    expect(window.location.hash).toBe("#/u/customer");
    // One ESC must land on L0 - not close the panel while leaving the URL at
    // #/u/customer (an orphan state that needed a second ESC before the fix). The
    // step-up POPs (history.back), so it resolves on the next tick.
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    await waitFor(() => app.router.current().unit === undefined);
    expect(app.router.current().unit).toBeUndefined();
    expect(window.location.hash === "#/" || window.location.hash === "").toBe(true);
  });

  it("drilling into a planned (0-table) package shows the canvas empty-state (M2)", () => {
    // agentic-commerce is a planned package in the fixture (no tables). The L1
    // routing branch renders .cy-empty instead of mounting cytoscape.
    (document.querySelector('.pkg[data-unit="agentic-commerce"]') as HTMLButtonElement).click();
    expect(window.location.hash).toBe("#/u/agentic-commerce");
    const empty = document.querySelector(".cy-empty");
    expect(empty).not.toBeNull();
    expect(empty!.textContent).toContain("planned");
  });

  it("filter controls are enabled on L0 but disabled on a drill view (M1)", () => {
    const search = document.getElementById("filter-q") as HTMLInputElement;
    const layer = document.getElementById("filter-layer") as HTMLSelectElement;
    expect(search.disabled).toBe(false); // L0: filters act on the grid
    (document.querySelector('.dom[data-unit="customer"]') as HTMLButtonElement).click();
    // L1 drill: filters don't act here, so they must be disabled (not live-but-inert)
    expect(search.disabled).toBe(true);
    expect(layer.disabled).toBe(true);
  });
});

describe("L1 ER container is visible before cytoscape mounts (bug 2)", () => {
  it("un-hides #cy synchronously on drill-in, before the async graph import", () => {
    // Regression guard for the "diagram view unavailable" bug: cytoscape must
    // never initialise against a hidden (display:none / 0x0) container. mountCy
    // un-hides #cy as its first synchronous statement — BEFORE it awaits the
    // dynamic ./graph import — so the element is laid out with real dimensions
    // by the time cytoscape() reads clientWidth/Height. Assert that visibility
    // flips synchronously (no await), which is what pins the ordering.
    const cy = document.getElementById("cy") as HTMLElement;
    expect(cy.hidden).toBe(true); // hidden on the L0 overview
    app.router.go({ view: "overview", unit: "customer" });
    // no `await` here on purpose — the un-hide is synchronous inside mountCy,
    // the graph import (and any canvas failure) resolves later on a microtask.
    expect(cy.hidden).toBe(false);
  });
});

describe("deep link opens the right state", () => {
  it("mounting with #/matrix renders the matrix view", () => {
    installDom();
    window.location.hash = "#/matrix";
    // This test mounts its OWN app; capture and destroy it so its window listeners
    // (router/keydown/theme) do not leak onto the shared jsdom window - afterEach only
    // tears down the beforeEach `app`.
    const appB = mountApp(makeModel());
    expect(document.querySelector("table.matrix")).not.toBeNull();
    // matrix has a row per package and a column per domain
    expect(document.querySelectorAll("table.matrix tbody tr").length).toBe(12);
    appB.destroy();
  });
});
