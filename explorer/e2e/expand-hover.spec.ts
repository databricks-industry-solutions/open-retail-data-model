import { test, expect } from "@playwright/test";
import { gotoUnit, waitForGraph, panBy, emitNode } from "./helpers";

/**
 * Hover-expand + connection regression spec (L1 ER cards). Guards behaviours that only
 * manifest with real cytoscape rendering (a jsdom/vitest test cannot cover them). The
 * capped-list AFFORDANCE (fade + "click to see all N columns" footer) is unit-tested in
 * test/cards.test.ts; here we guard the interaction-level invariants:
 *
 *  1. Hovering a bottom card NEVER pans the canvas or moves siblings. Panning a tall card
 *     into view used to move the compact hit-box out from under a stationary cursor, so
 *     cytoscape re-hit-tested on every pan frame -> a 20-30x expand/collapse flicker. No
 *     pan + no node-geometry change = that loop is structurally impossible.
 *  2. Collapse clears the list cap.
 *  3. An ASSOCIATION table (promotion_scope) arcs to the core tables its FKs reference,
 *     just like a gold view arcs to the silver it consumes.
 *  4. The tap/select overlay is suppressed (no "shadow" box at the compact size).
 *  5. The zoom widget sits at the TOP (it used to overlap the bottom consumes rail).
 */

const UNIT = "promote-with-purpose";
const TALL = "gold_promo_roi";
const SIBLING = "gold_promo_roi_by_category";
const ASSOC = "promotion_scope";

test.use({ viewport: { width: 1280, height: 620 } });

test.describe("L1 card hover-expand + connections", () => {
  test("expanding a bottom card issues no pan and no reflow (root cause of the old flicker)", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    await page.waitForTimeout(350); // let the initial layout/default-zoom settle first
    await panBy(page, 0, -4000); // scroll to the bottom, where the flicker used to happen

    const before = await page.evaluate((sib) => {
      const cy = (window as unknown as { __cy: { pan: () => { y: number }; getElementById: (i: string) => { position: (a: string) => number } } }).__cy;
      return { panY: cy.pan().y, sibY: cy.getElementById(sib).position("y") };
    }, SIBLING);

    // The old flicker was a genuine-pointer hit-test re-entry loop that a synthetic event
    // can't reproduce. What this guards is its ROOT CAUSE: the expand path (setExpanded)
    // must issue NO cy.pan() and NO node-geometry change. A reintroduced peek-pan would
    // increment this counter on the same synthetic hover; a re-added box/position change
    // would move a sibling. Both are what made the loop possible.
    await page.evaluate(() => {
      const w = window as unknown as { __cy: { on: (e: string, f: () => void) => void }; __pans: number };
      w.__pans = 0;
      w.__cy.on("pan", () => { (window as unknown as { __pans: number }).__pans++; });
    });
    await emitNode(page, TALL, "mouseover");
    await page.waitForFunction(
      (id) => Array.from(document.querySelectorAll(".card")).some(
        (c) => c.getAttribute("data-table") === id && c.classList.contains("expanded")),
      TALL, { timeout: 3000 });
    await page.waitForTimeout(400);

    const after = await page.evaluate(({ sib }) => {
      const cy = (window as unknown as { __cy: { getElementById: (i: string) => { position: (a: string) => number } } }).__cy;
      const w = window as unknown as { __pans: number };
      return { sibY: cy.getElementById(sib).position("y"), pans: w.__pans };
    }, { sib: SIBLING });

    expect(after.pans).toBeLessThanOrEqual(2); // expand path issues no pan (a peek-pan would fire here)
    expect(after.sibY).toBe(before.sibY); // and no node-geometry change -> siblings never move
  });

  test("collapse clears the column cap", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    await panBy(page, 0, -4000);
    await emitNode(page, TALL, "mouseover");
    // Confirm the card ACTUALLY expanded first, so a slow-to-expand hover cannot let the
    // post-collapse assertion pass vacuously (post-collapse state == never-expanded).
    await page.waitForFunction(
      (id) => Array.from(document.querySelectorAll(".card")).some(
        (c) => c.getAttribute("data-table") === id && c.classList.contains("expanded")),
      TALL, { timeout: 3000 });
    await emitNode(page, TALL, "mouseout");
    await page.waitForTimeout(120);
    const r = await page.evaluate((id) => {
      const card = Array.from(document.querySelectorAll<HTMLElement>(".card")).find((c) => c.getAttribute("data-table") === id);
      return {
        expanded: !!card?.classList.contains("expanded"),
        capVar: getComputedStyle(document.querySelector("#cy")!).getPropertyValue("--ordm-expand-max").trim(),
      };
    }, TALL);
    expect(r.expanded).toBe(false);
    expect(r.capVar).toBe(""); // cap removed on collapse
  });

  test("an association table arcs to the core tables its FKs reference", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    await emitNode(page, ASSOC, "mouseover");
    // The card re-render can briefly churn the hover; poll until the rail settles on the
    // association's three FK targets rather than sampling one frame.
    await page.waitForFunction(
      () => Array.from(document.querySelectorAll<HTMLElement>(".cr-chip.lit"))
        .map((c) => c.dataset["table"]).sort().join(",") === "product,promotion,store",
      undefined, { timeout: 3000 });
    const arcs = await page.evaluate(() => ({
      railActive: !!document.querySelector(".consumes-rail.active"),
      arcs: document.querySelectorAll(".cr-arc").length,
    }));
    expect(arcs.railActive).toBe(true);
    expect(arcs.arcs).toBe(3); // one per FK target: promotion, product, store
  });

  test("nodes suppress the tap/select overlay (no shadow box)", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    const overlay = await page.evaluate((id) =>
      (window as unknown as { __cy: { getElementById: (i: string) => { style: (k: string) => string } } })
        .__cy.getElementById(id).style("overlay-opacity"),
    TALL);
    expect(Number(overlay)).toBe(0);
  });

  test("zoom widget sits at the top, clear of the bottom consumes rail", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    await waitForGraph(page);
    const geom = await page.evaluate(() => {
      const zoom = document.querySelector(".cy-zoom")!.getBoundingClientRect();
      const cont = document.querySelector("#cy")!.getBoundingClientRect();
      const rail = document.querySelector(".consumes-rail")?.getBoundingClientRect() ?? null;
      return {
        zoomInTopHalf: zoom.top - cont.top < cont.height / 2,
        clearsRail: rail ? zoom.bottom <= rail.top : true,
      };
    });
    expect(geom.zoomInTopHalf).toBe(true);
    expect(geom.clearsRail).toBe(true);
  });
  test("dark mode: the consumes rail is readable, not white-on-white (bug 2026-07-12)", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    await page.evaluate(() => document.documentElement.classList.add("theme-dark"));
    await emitNode(page, TALL, "mouseover"); // activate the rail
    await page.waitForTimeout(120);
    const c = await page.evaluate(() => {
      const lum = (s: string) => { const n = (s.match(/\d+/g) || []).map(Number); return n.length >= 3 ? 0.299 * n[0] + 0.587 * n[1] + 0.114 * n[2] : NaN; };
      const rail = document.querySelector(".consumes-rail")!;
      const chip = document.querySelector(".cr-chip")!;
      return { bg: lum(getComputedStyle(rail).backgroundColor), fg: lum(getComputedStyle(chip).color) };
    });
    expect(c.bg).toBeLessThan(90);          // dark surface (was a hard-coded white fallback)
    expect(c.fg - c.bg).toBeGreaterThan(80); // readable text/background contrast
  });

  test("hovering an out-of-view-FK table does not fade other tables' FK edges (bug 2026-07-12)", async ({ page }) => {
    await gotoUnit(page, "/u/balancing-margin-and-volume");
    await emitNode(page, "product_relationship", "mouseover"); // its FKs point out of view -> no in-view edges
    await page.waitForTimeout(120);
    const r = await page.evaluate(() => {
      const cy = (window as unknown as { __cy: { edges: () => { filter: (f: (e: { id: () => string }) => boolean) => { nonempty: () => boolean; hasClass: (c: string) => boolean } }; elements: (s: string) => { length: number } } }).__cy;
      const fk = cy.edges().filter((e) => e.id() === "competitor->competitor_price");
      return { exists: fk.nonempty(), faded: fk.nonempty() ? fk.hasClass("faded") : null, fadedCount: cy.elements(".faded").length };
    });
    expect(r.exists).toBe(true);
    expect(r.faded).toBe(false);  // the unrelated FK edge stays visible
    expect(r.fadedCount).toBe(0); // a node with no in-view edges dims nothing
  });

  test("a capped expanded card keeps its 'click to see all' footer on-screen (bug 2026-07-12)", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    // A genuinely TALL card (gold_promo_roi, 23 cols) whose compact height is well below its
    // full height, so there IS a window where it caps (grows past compact but not to full).
    // Place its top just below the container top so the full card overflows and must cap.
    await page.evaluate((id) => {
      const cy = (window as unknown as { __cy: { getElementById: (i: string) => { renderedBoundingBox: () => { y1: number } }; panBy: (p: { x: number; y: number }) => void; pan: (p?: { x: number; y: number }) => { x: number; y: number } } }).__cy;
      const n = cy.getElementById(id);
      cy.panBy({ x: 0, y: -4000 });
      cy.pan({ x: cy.pan().x, y: 60 - n.renderedBoundingBox().y1 + cy.pan().y });
    }, TALL);
    await emitNode(page, TALL, "mouseover");
    await page.waitForFunction(
      (id) => !!Array.from(document.querySelectorAll(".card"))
        .find((c) => c.getAttribute("data-table") === id)?.querySelector(".col-list.capped"),
      TALL, { timeout: 3000 });
    const r = await page.evaluate((id) => {
      const card = Array.from(document.querySelectorAll<HTMLElement>(".card")).find((c) => c.getAttribute("data-table") === id)!;
      const f = card.querySelector<HTMLElement>(".col-expand-all");
      const cont = document.querySelector("#cy")!.getBoundingClientRect();
      const fr = f?.getBoundingClientRect();
      return { footer: f?.textContent?.trim() ?? null, onScreen: fr ? fr.bottom <= cont.bottom + 1 && fr.top >= cont.top : false };
    }, TALL);
    expect(r.footer).toContain("click to see all"); // the "more columns" indication is present
    expect(r.onScreen).toBe(true);                  // and never pushed off-screen
  });

  test("hovering a bottom card never SHRINKS it below its compact size (bug 2026-07-13)", async ({ page }) => {
    await gotoUnit(page, "/u/balancing-margin-and-volume");
    const ID = "gold_promotional_features";
    // force the card near the bottom, where a naive cap would show fewer columns than compact
    await page.evaluate((id) => {
      const cy = (window as unknown as { __cy: { getElementById: (i: string) => { renderedBoundingBox: () => { y1: number } }; panBy: (p: { x: number; y: number }) => void; pan: (p?: { x: number; y: number }) => { x: number; y: number } } }).__cy;
      const n = cy.getElementById(id);
      cy.panBy({ x: 0, y: -4000 });
      const contH = document.querySelector("#cy")!.getBoundingClientRect().height;
      cy.pan({ x: cy.pan().x, y: (contH - 150) - n.renderedBoundingBox().y1 + cy.pan().y });
    }, ID);
    const compact = await page.evaluate((id) => {
      const c = Array.from(document.querySelectorAll<HTMLElement>(".card")).find((x) => x.getAttribute("data-table") === id);
      return c ? Math.round(c.getBoundingClientRect().height) : 0;
    }, ID);
    // A missing card measures 0 both times, so the >= below would pass vacuously; this
    // test silently checked nothing while ID named a table that no longer existed.
    expect(compact, `card ${ID} is not rendered on the L1 canvas`).toBeGreaterThan(0);
    await emitNode(page, ID, "mouseover");
    await page.waitForTimeout(200);
    const hovered = await page.evaluate((id) => {
      const c = Array.from(document.querySelectorAll<HTMLElement>(".card")).find((x) => x.getAttribute("data-table") === id);
      return c ? Math.round(c.getBoundingClientRect().height) : 0;
    }, ID);
    // hovering must GROW or keep the card, never shrink it (the old cap rendered FEWER
    // columns than the compact preview when the card sat near the viewport bottom).
    expect(hovered).toBeGreaterThanOrEqual(compact - 1);
  });
});
