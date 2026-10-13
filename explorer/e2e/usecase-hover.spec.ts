import { test, expect } from "@playwright/test";
import { gotoUnit, emitNode, UNIT } from "./helpers";

/**
 * Spec 2 - use-case panel hover + pin (design/38 §5, right-pane <-> band bridge).
 *
 * Hovering a `.panel-uc` row in the L1 side panel must highlight that use case's
 * member cards (`.uc-hl`) and fade the rest (`.uc-faded`). Clicking PINS the
 * highlight: it persists after the pointer leaves the row, and the row carries
 * `.panel-uc.pinned`.
 *
 * Data: `early-risk-detection`'s "Real Time Disruption Detection" use case owns
 * gold_control_tower / gold_shipment_current_state / gold_inventory_risk.
 */

const UC_NAME = "Real Time Disruption Detection";
const MEMBER = "gold_control_tower"; // in the use case
const NON_MEMBER = "gold_supplier_scorecard"; // a different use case's table

test.describe("use-case panel hover + pin", () => {
  test("hover lights member cards and fades others; leave restores", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);

    const row = page.locator(`.panel-uc[data-uc-name="${UC_NAME}"]`);
    await expect(row).toBeVisible();
    const member = page.locator(`.card[data-table="${MEMBER}"]`);
    const other = page.locator(`.card[data-table="${NON_MEMBER}"]`);

    await row.hover();
    await expect(member).toHaveClass(/uc-hl/);
    await expect(other).toHaveClass(/uc-faded/);

    // Moving the pointer off the row (to a neutral toolbar element) clears the
    // transient highlight (nothing is pinned).
    await page.locator("#toolbar .toolbar-title").hover();
    await expect(member).not.toHaveClass(/uc-hl/);
    await expect(other).not.toHaveClass(/uc-faded/);
  });

  test("click pins the highlight past mouseleave", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);

    const row = page.locator(`.panel-uc[data-uc-name="${UC_NAME}"]`);
    const member = page.locator(`.card[data-table="${MEMBER}"]`);

    await row.click();
    await expect(row).toHaveClass(/pinned/);

    // Move the pointer away: a PINNED highlight must survive the mouseleave.
    await page.locator("#toolbar .toolbar-title").hover();
    await expect(member).toHaveClass(/uc-hl/);
    await expect(row).toHaveClass(/pinned/);

    // Clicking the pinned row again un-pins it.
    await row.click();
    await expect(row).not.toHaveClass(/pinned/);
  });

  test("a pinned highlight SURVIVES a relayout (window resize) (M1)", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    const row = page.locator(`.panel-uc[data-uc-name="${UC_NAME}"]`);
    const member = page.locator(`.card[data-table="${MEMBER}"]`);

    await row.click();
    await expect(row).toHaveClass(/pinned/);
    await expect(member).toHaveClass(/uc-hl/);

    // A resize fires the debounced relayout, which destroys/rebuilds the band
    // overlay and regenerates every card's DOM - wiping the transient .uc-hl class.
    // The active use case must be RE-ASSERTED afterward, not left desynced (panel
    // pinned / canvas blank).
    const vp = page.viewportSize()!;
    await page.setViewportSize({ width: vp.width - 60, height: vp.height });
    await page.waitForTimeout(300); // settle past the relayout debounce

    await expect(member).toHaveClass(/uc-hl/); // still lit on the canvas
    await expect(row).toHaveClass(/pinned/); // and still pinned in the panel
  });

  test("a pinned highlight SURVIVES hovering a table card and leaving it (M1)", async ({
    page,
  }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    const row = page.locator(`.panel-uc[data-uc-name="${UC_NAME}"]`);
    const member = page.locator(`.card[data-table="${MEMBER}"]`);

    await row.click();
    await expect(row).toHaveClass(/pinned/);
    await expect(member).toHaveClass(/uc-hl/);

    // Hover a (different) table card, then leave it. Cards are DOM overlays, so drive
    // the cytoscape node mouseover/mouseout directly. On mouseout the handler must
    // RE-ASSERT the pin, not clearHover() it away - previously it blanked the canvas
    // while the panel row stayed .pinned, so the two hover surfaces desynced.
    await emitNode(page, NON_MEMBER, "mouseover");
    await emitNode(page, NON_MEMBER, "mouseout");
    await page.waitForTimeout(60);

    await expect(member).toHaveClass(/uc-hl/); // pin restored on the canvas
    await expect(row).toHaveClass(/pinned/); // and still pinned in the panel
  });
});
