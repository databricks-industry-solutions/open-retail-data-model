import { test, expect } from "@playwright/test";

/**
 * The theme toggle (#theme-toggle) flips the `theme-dark` class on
 * <documentElement>, and the choice PERSISTS across a reload (localStorage key
 * `ordm-explorer-theme`), so a user's dark/light preference survives navigation.
 */

const isDark = () =>
  document.documentElement.classList.contains("theme-dark");

test.describe("theme toggle persistence", () => {
  test("toggle flips the documentElement class and persists across reload", async ({ page }) => {
    await page.goto("./?e2e=1#/");
    const btn = page.locator("#theme-toggle");
    await expect(btn).toBeVisible();

    const before = await page.evaluate(isDark);
    await btn.click();
    // The class flips immediately.
    await expect.poll(() => page.evaluate(isDark)).toBe(!before);
    // And the choice is written to localStorage.
    const stored = await page.evaluate(() => localStorage.getItem("ordm-explorer-theme"));
    expect(stored).toBe(!before ? "dark" : "light");

    // Reload: the persisted choice must be re-applied on boot.
    await page.reload();
    await page.locator("#theme-toggle").waitFor({ state: "visible", timeout: 15_000 });
    await expect.poll(() => page.evaluate(isDark)).toBe(!before);

    // Toggling back restores and re-persists the original.
    await page.locator("#theme-toggle").click();
    await expect.poll(() => page.evaluate(isDark)).toBe(before);
    const restored = await page.evaluate(() => localStorage.getItem("ordm-explorer-theme"));
    expect(restored).toBe(before ? "dark" : "light");
  });

  test("the canvas background actually recolors on toggle (computed style, not just the class)", async ({
    page,
  }) => {
    // The jsdom unit test can only read the CSS source; here in a real browser we
    // read the RENDERED background of #cy and assert it changes when the theme flips
    // - closing the one place the claim could be over-read (m4).
    await page.goto("./?e2e=1#/u/early-risk-detection");
    await page.locator("#cy").waitFor({ state: "visible", timeout: 15_000 });
    const cyBg = () =>
      page.evaluate(() => getComputedStyle(document.getElementById("cy")!).backgroundColor);
    const first = await cyBg();
    expect(first).toBeTruthy();
    await page.locator("#theme-toggle").click();
    await expect.poll(cyBg).not.toBe(first); // the rendered canvas recolored
  });

  test("an OS color-scheme change recolors the graph EDGES when no preference is stored (M1)", async ({
    page,
  }) => {
    // The one runtime path a button-click-only refresh missed: with NO stored choice,
    // flipping the OS theme while a graph/ER view is mounted must recolour the
    // cytoscape-painted edges (--edge-color), not just the CSS canvas background.
    await page.emulateMedia({ colorScheme: "light" });
    await page.goto("./?e2e=1#/u/early-risk-detection");
    await page.evaluate(() => localStorage.removeItem("ordm-explorer-theme"));
    await page.reload();
    await page.locator("#cy").waitFor({ state: "visible", timeout: 15_000 });
    await page.waitForFunction(
      () => {
        const cy = (window as unknown as { __cy?: { edges: () => { length: number } } }).__cy;
        return !!cy && cy.edges().length > 0;
      },
      undefined,
      { timeout: 15_000 }
    );

    const edgeColor = () =>
      page.evaluate(
        () =>
          (
            window as unknown as {
              __cy: { edges: () => { first: () => { style: (p: string) => string } } };
            }
          ).__cy
            .edges()
            .first()
            .style("line-color")
      );
    const before = await edgeColor();
    // Flip the OS preference: onOsChange applies the theme AND, via the onChange
    // callback, schedules refreshTheme so the edges recolor (M1).
    await page.emulateMedia({ colorScheme: "dark" });
    await expect.poll(edgeColor, { timeout: 5_000 }).not.toBe(before);
  });
});
