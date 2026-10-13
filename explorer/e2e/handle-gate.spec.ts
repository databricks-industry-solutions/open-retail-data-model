import { test, expect } from "@playwright/test";
import { gotoUnit, expectHandle, UNIT } from "./helpers";

/**
 * The `window.__cy` e2e handle must be exposed ONLY under the `?e2e=1` harness
 * flag (or a Vite dev build), never on a bare production load. This guards
 * against the handle silently shipping to real visitors of the deployed site.
 */

test.describe("e2e handle gate", () => {
  test("exposed under ?e2e=1", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    await expectHandle(page, true);
  });

  test("absent on a bare production load (no ?e2e flag)", async ({ page }) => {
    // Same route WITHOUT the flag: the production build must not expose __cy.
    await page.goto(`./#/u/${UNIT}`);
    // Give cytoscape time to mount (a card appears) before asserting the handle.
    await page.locator(".card").first().waitFor({ state: "attached", timeout: 15_000 });
    await expectHandle(page, false);
  });
});
