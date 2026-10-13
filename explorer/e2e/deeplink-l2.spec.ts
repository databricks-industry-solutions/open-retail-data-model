import { test, expect } from "@playwright/test";
import { gotoUnit, UNIT, CHILD_TABLE } from "./helpers";

/**
 * Spec 4 - deep-link straight to L2 (design/38, deep-link preservation).
 *
 * A fresh load of `#/u/<unit>/<table>` must mount the ER, keep the hash, and open
 * the L2 table-detail panel (its full column list) - NOT fall back to the L1 unit
 * summary. The earlier bug replaced the hash / showed the L1 summary on a cold
 * deep-link.
 */

test.describe("deep-link to L2", () => {
  test("cold load of #/u/<unit>/<table> keeps the hash and shows L2 columns", async ({
    page,
  }) => {
    await gotoUnit(page, `/u/${UNIT}/${CHILD_TABLE}`);

    // The hash is preserved (still the L2 route, not collapsed to L1).
    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe(
      `#/u/${UNIT}/${CHILD_TABLE}`
    );

    // The L2 detail panel is open: it shows the table title and its full column
    // rows (`.panel-col-row`), which the L1 summary panel does not render.
    const panel = page.locator("#panel");
    // The L2 title is the table name plus its role chip ("disruption_alert
    // transactional"), so assert it CONTAINS the table name rather than equals it.
    await expect(panel.locator(".panel-title")).toContainText(CHILD_TABLE);
    await expect(panel.locator(".panel-col-row").first()).toBeVisible();
    expect(await panel.locator(".panel-col-row").count()).toBeGreaterThan(1);

    // It is the L2 detail, not the L1 summary (which renders .panel-kind + the
    // use-case list). Those L1-only markers must be absent.
    await expect(panel.locator(".panel-kind")).toHaveCount(0);
    await expect(panel.locator(".panel-uc-list")).toHaveCount(0);
  });

  test("closing the L2 panel steps up to L1 so the route stays in sync (M2)", async ({
    page,
  }) => {
    await gotoUnit(page, `/u/${UNIT}/${CHILD_TABLE}`);
    const panel = page.locator("#panel");
    await expect(panel.locator(".panel-col-row").first()).toBeVisible();

    // Clicking the panel's close button must NOT just hide L2 while leaving the hash
    // at the table route (a stale deep-link that reopens L2 on reload). It steps up
    // to L1: the hash drops the table and the L1 summary (use-case list) shows.
    await panel.locator(".panel-close").click();
    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe(`#/u/${UNIT}`);
    await expect(panel.locator(".panel-uc-list")).toHaveCount(1); // L1 summary now
    await expect(panel.locator(".panel-col-row")).toHaveCount(0); // L2 columns gone
  });
});
