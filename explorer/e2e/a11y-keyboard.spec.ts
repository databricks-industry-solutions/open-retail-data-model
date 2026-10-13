import { test, expect } from "@playwright/test";
import { gotoUnit, cyZoom, emitNode, UNIT, CHILD_TABLE } from "./helpers";

/**
 * Keyboard + a11y affordances on the per-unit ER:
 *   - the zoom widget buttons expose aria-labels (screen-reader names);
 *   - with the #cy container focused, "+" / "-" change cy.zoom() and "0" resets
 *     to the default (the keydown handler is scoped to the container, not
 *     document — see createZoomWidget);
 *   - ESC on an L2 table view steps up to L1 (a real route change).
 */

test.describe("zoom widget a11y + keyboard", () => {
  test("zoom widget buttons expose aria-labels", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    for (const label of ["Zoom in", "Zoom out", "Fit to content", "Reset zoom"]) {
      await expect(page.locator(`.cy-zoom-btn[aria-label="${label}"]`)).toHaveCount(1);
    }
  });

  test("+ / - change zoom and 0 resets", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);

    // The keydown handler lives on #cy (made focusable via tabIndex). Focus it so
    // the +/-/0 keys reach the widget rather than the document.
    await page.locator("#cy").focus();
    // Wait for the L1 view to fully settle first: the side panel opens after mount
    // and narrows #cy, which reflows to a NARROWER default zoom. If we captured the
    // baseline before that reflow, a later reset (to the settled default) would not
    // match it. Wait for the panel, then let the reflow settle.
    await page.locator("#panel.open").waitFor({ state: "attached", timeout: 15_000 });
    await page.waitForTimeout(400);
    // Reset so the baseline is the deterministic (settled) default zoom.
    await page.keyboard.press("0");
    await expect.poll(() => cyZoom(page)).toBeGreaterThan(0);
    const base = await cyZoom(page);

    // "+" zooms in (multiplicative x1.2 about centre).
    await page.keyboard.press("+");
    await expect.poll(() => cyZoom(page)).toBeGreaterThan(base + 0.05);
    const zoomedIn = await cyZoom(page);

    // "-" zooms back out below the zoomed-in level.
    await page.keyboard.press("-");
    await expect.poll(() => cyZoom(page)).toBeLessThan(zoomedIn - 0.05);

    // Zoom in again so the level is clearly off the default, then "0" resets it
    // back to the post-mount default (within a hair of cytoscape float rounding).
    await page.keyboard.press("+");
    await expect.poll(() => cyZoom(page)).toBeGreaterThan(base + 0.05);
    await page.keyboard.press("0");
    await expect.poll(async () => Math.abs((await cyZoom(page)) - base)).toBeLessThan(0.01);
  });

  test("ESC on an L2 view steps up to L1", async ({ page }) => {
    // Deep-link straight to L2, then ESC should route up to the L1 unit.
    await gotoUnit(page, `/u/${UNIT}/${CHILD_TABLE}`);
    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe(
      `#/u/${UNIT}/${CHILD_TABLE}`
    );

    // ESC is a document-level handler (ignored inside inputs/selects). Press it on
    // the body so it steps up one level: L2 table -> L1 unit.
    await page.locator("body").click({ position: { x: 5, y: 5 } });
    await page.keyboard.press("Escape");
    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe(`#/u/${UNIT}`);
  });
});

/** Prove the tap path used by the ESC setup actually reaches L2 (sanity net). */
test("tapping a node reaches L2 before the ESC step-up", async ({ page }) => {
  await gotoUnit(page, `/u/${UNIT}`);
  await emitNode(page, CHILD_TABLE, "tap");
  await expect.poll(() => page.evaluate(() => window.location.hash)).toBe(
    `#/u/${UNIT}/${CHILD_TABLE}`
  );
});
