import { test, expect } from "@playwright/test";
import { fetchModel, cyNodeCount, collectConsoleErrors } from "./helpers";

/**
 * The two opt-in views reachable from the segmented toggle:
 *   - Matrix: a packages x domains grid; clicking a row/column/cell header drills
 *     into that unit's L1 (#/u/<name>).
 *   - Graph: mounts cytoscape (whole-model) with nodes > 0 (asserted via __cy)
 *     and NO console error.
 */

test.describe("Matrix + Graph views", () => {
  test("Matrix mounts a packages x domains grid and a header click drills in", async ({
    page,
  }) => {
    const model = await fetchModel(page);
    const nDomains = model.units.filter((u) => u.kind === "core").length;
    const nPackages = model.units.filter((u) => u.kind === "outcome").length;

    await page.goto("./?e2e=1#/");
    await page.locator(".seg-btn").first().waitFor({ state: "attached", timeout: 15_000 });
    await page.locator('.seg-btn[data-view="matrix"]').click();
    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe("#/matrix");

    const matrix = page.locator("table.matrix");
    await expect(matrix).toBeVisible();
    // One column header per domain (plus the corner cell) and one row per package.
    await expect(matrix.locator("th.mx-dom")).toHaveCount(nDomains);
    await expect(matrix.locator("th.mx-pkg")).toHaveCount(nPackages);
    // At least one consumption dot lit somewhere in the grid.
    expect(await matrix.locator("td.mx-cell.on").count()).toBeGreaterThan(0);

    // Click a package row header -> drill into that unit's L1.
    const firstPkgBtn = matrix.locator("th.mx-pkg button[data-unit]").first();
    const unit = await firstPkgBtn.getAttribute("data-unit");
    await firstPkgBtn.click();
    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe(`#/u/${unit}`);
  });

  test("Graph mounts cytoscape with nodes > 0 and no console error", async ({ page }) => {
    const errors = collectConsoleErrors(page);
    await page.goto("./?e2e=1#/");
    await page.locator(".seg-btn").first().waitFor({ state: "attached", timeout: 15_000 });
    await page.locator('.seg-btn[data-view="graph"]').click();
    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe("#/graph");

    // The whole-model graph mounts cytoscape; wait for its nodes via the handle.
    await page.waitForFunction(
      () => {
        const cy = (window as unknown as { __cy?: { nodes: () => { length: number } } }).__cy;
        return !!cy && cy.nodes().length > 0;
      },
      undefined,
      { timeout: 15_000 }
    );
    expect(await cyNodeCount(page)).toBeGreaterThan(0);
    expect(errors, `graph view logged console error(s): ${errors.join(" | ")}`).toEqual([]);
  });
});
