import { test, expect } from "@playwright/test";
import { UNIT } from "./helpers";

/**
 * On a phone-sized viewport the per-unit ER must stay usable:
 *   - the navigator (.cy-minimap) is hidden by the max-width media query (it is
 *     a desktop-only affordance that would crowd a small screen);
 *   - the page body has no horizontal overflow (documentElement.scrollWidth must
 *     not exceed window.innerWidth) — a wide diagram scrolls INSIDE #cy, never
 *     pushing the whole document sideways.
 *
 * Uses its own small viewport (the shared config viewport is desktop-width).
 */

test.use({ viewport: { width: 390, height: 800 } });

test.describe("phone-viewport ER", () => {
  test("minimap is hidden and the body does not scroll horizontally", async ({ page }) => {
    await page.goto(`./?e2e=1#/u/${UNIT}`);
    // Wait for the ER to mount so the minimap element exists and CSS has applied.
    await page.waitForFunction(
      () => {
        const cy = (window as unknown as { __cy?: { nodes: () => { length: number } } }).__cy;
        return !!cy && cy.nodes().length > 0;
      },
      undefined,
      { timeout: 15_000 }
    );
    await page.locator(".card").first().waitFor({ state: "attached", timeout: 15_000 });

    // On a phone the navigator must NOT be shown. Depending on how the full-width
    // side panel collapses #cy, the minimap is either created and hidden by the
    // <=560px media query, OR skipped entirely (an inert navigator when the
    // container measures ~0 wide). Either way it must not be VISIBLE. toBeHidden()
    // passes both for a display:none element and for one that is absent, so it is
    // robust to which of those two the layout produces.
    await expect(page.locator(".cy-minimap")).toBeHidden();

    // No horizontal body scroll: the document must not be wider than the viewport.
    const overflow = await page.evaluate(() => ({
      scrollWidth: document.documentElement.scrollWidth,
      innerWidth: window.innerWidth,
    }));
    expect(
      overflow.scrollWidth,
      `body overflows horizontally: scrollWidth=${overflow.scrollWidth} > innerWidth=${overflow.innerWidth}`
    ).toBeLessThanOrEqual(overflow.innerWidth);
  });
});
