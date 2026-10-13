import { test, expect } from "@playwright/test";
import { fetchModel } from "./helpers";

/**
 * L0 landing (the DOM layered value-chain, not a cytoscape overlay):
 *   - the landing renders domain (`.dom`) + package (`.pkg`) cards;
 *   - hovering a package card that has consumes lights its edges (the overview
 *     draws an SVG `.edge-path` into `.edge-layer` and flags `.edges-active`
 *     + `.edge-src` / `.edge-dst` on the participants — see overview.ts);
 *   - clicking a package navigates to `#/u/<name>`;
 *   - the breadcrumb (Retail crumb link) and Back button return to L0.
 */

test.describe("L0 overview landing", () => {
  test("renders domain + package cards", async ({ page }) => {
    await page.goto("./?e2e=1#/");
    await page.locator(".pkg").first().waitFor({ state: "attached", timeout: 15_000 });
    expect(await page.locator(".pkg").count()).toBeGreaterThan(0);
    expect(await page.locator(".dom").count()).toBeGreaterThan(0);
  });

  test("hovering a package card reveals its consumes edges", async ({ page }) => {
    const model = await fetchModel(page);
    // Pick an outcome package that actually consumes >=1 core domain, so hover
    // has edges to draw. Derived from the overview edges (source = package).
    const consumers = new Set(model.overview && "edges" in model.overview
      ? (model.overview.edges as { source: string }[]).map((e) => e.source)
      : []);
    // Fall back to any package that appears as an edge source.
    const pkgWithConsumes = model.units.find(
      (u) => u.kind === "outcome" && consumers.has(u.name)
    );
    // If the edge source shape differs, just pick a built package with tables.
    const target = pkgWithConsumes?.name
      ?? model.units.find((u) => u.kind === "outcome" && u.tables.length > 0)!.name;

    await page.goto("./?e2e=1#/");
    const card = page.locator(`.pkg[data-unit="${target}"]`);
    await card.waitFor({ state: "attached", timeout: 15_000 });

    await card.hover();
    // The overview flags the canvas active and paints at least one edge path.
    await expect(page.locator(".ov-canvas.edges-active")).toHaveCount(1);
    await expect(page.locator(".edge-layer .edge-path").first()).toBeAttached();
    await expect(card).toHaveClass(/edge-src/);
  });

  test("clicking a package navigates to #/u/<name>, breadcrumb + Back return to L0", async ({
    page,
  }) => {
    const model = await fetchModel(page);
    const target = model.units.find((u) => u.kind === "outcome" && u.tables.length > 0)!.name;

    await page.goto("./?e2e=1#/");
    const card = page.locator(`.pkg[data-unit="${target}"]`);
    await card.waitFor({ state: "attached", timeout: 15_000 });
    await card.click();

    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe(`#/u/${target}`);
    // The Back button becomes available on a drill-in.
    await expect(page.locator("#back-btn")).toBeVisible();

    // Back button steps up to L0.
    await page.locator("#back-btn").click();
    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe("#/");
    await page.locator(".pkg").first().waitFor({ state: "attached", timeout: 15_000 });

    // Drill in again, then use the breadcrumb "Retail" link to return to L0.
    await page.locator(`.pkg[data-unit="${target}"]`).click();
    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe(`#/u/${target}`);
    await page.locator(".crumbs .crumb-link", { hasText: "Retail" }).click();
    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe("#/");
  });
});
