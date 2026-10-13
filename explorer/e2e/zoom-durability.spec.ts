import { test, expect } from "@playwright/test";
import { gotoUnit, cyZoom, UNIT } from "./helpers";

/**
 * Spec 3 - zoom durability (design/38 §4 zoom-durability fix).
 *
 * The widget zoom-in raises cy.zoom(); once the user has manually adjusted the
 * zoom, a `window.resize` (which fires a relayout) must NOT snap it back to the
 * default. The earlier bug reset the user's zoom on every relayout.
 */

test.describe("zoom durability", () => {
  test("widget zoom-in raises zoom and a resize does not reset it", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);

    const before = await cyZoom(page);

    // Click the widget zoom-in a few times (multiplicative ×1.2 about centre).
    const zoomIn = page.locator('.cy-zoom-btn[data-act="in"]');
    await expect(zoomIn).toBeVisible();
    for (let i = 0; i < 3; i++) await zoomIn.click();

    const zoomed = await cyZoom(page);
    expect(zoomed).toBeGreaterThan(before);

    // A window resize fires the debounced relayout. The user's zoom must hold.
    await page.setViewportSize({ width: 1100, height: 820 });
    // Give the debounced relayout (80ms) time to run, then assert no snap-back.
    await page.waitForTimeout(300);

    const after = await cyZoom(page);
    // Allow a hair of tolerance for cytoscape's internal rounding, but the zoom
    // must remain clearly the user-adjusted level, not the recomputed default.
    expect(after).toBeGreaterThan(before + 0.05);
    expect(Math.abs(after - zoomed)).toBeLessThan(0.01);
  });
});
