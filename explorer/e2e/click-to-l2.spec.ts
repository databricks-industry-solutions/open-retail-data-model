import { test, expect } from "@playwright/test";
import { gotoUnit, cyIdentity, cyZoom, emitNode, UNIT, CHILD_TABLE } from "./helpers";

/**
 * Spec 5 - click-to-L2 must NOT re-mount the graph (design/38, the "blink" fix).
 *
 * Tapping a table node opens its L2 detail panel. Navigating L1 -> L2 WITHIN the
 * same unit must keep the existing cytoscape instance (just open the panel +
 * reflow), NOT tear it down and re-fit the whole diagram (the jarring "blink").
 *
 * We prove identity with a stamp on the live instance (see cyIdentity): a stable
 * token across the tap means the SAME cy survived; a re-mount would yield a fresh,
 * unstamped instance. We also assert the zoom does not jump (a re-fit would).
 */

test.describe("click-to-L2 does not re-mount the graph", () => {
  test("tapping a table opens L2 with a stable cy instance and no zoom jump", async ({
    page,
  }) => {
    await gotoUnit(page, `/u/${UNIT}`);

    const id0 = await cyIdentity(page);
    const zoom0 = await cyZoom(page);

    // Tap a table node -> drill to L2 (main.ts routes to #/u/<unit>/<table>).
    await emitNode(page, CHILD_TABLE, "tap");

    // The L2 panel opened.
    await expect(page.locator("#panel .panel-col-row").first()).toBeVisible();
    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe(
      `#/u/${UNIT}/${CHILD_TABLE}`
    );

    // The SAME cytoscape instance is still mounted (stamp preserved): no
    // tearDown() + re-mount happened for the L1 -> L2 transition.
    const id1 = await cyIdentity(page);
    expect(id1).toBe(id0);

    // The zoom did not jump (no whole-diagram re-fit). The panel-open reflow may
    // re-pack columns but must preserve the current zoom.
    const zoom1 = await cyZoom(page);
    expect(Math.abs(zoom1 - zoom0)).toBeLessThan(0.02);
  });
});
