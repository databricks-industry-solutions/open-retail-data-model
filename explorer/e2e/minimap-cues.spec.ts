import { test, expect } from "@playwright/test";
import { gotoUnit, UNIT } from "./helpers";

/**
 * Spec 6 - navigator (minimap) + directional overflow cues (design/38 §4) and the
 * minimap's table-name labels + highlight mirroring (design/39 Task 2).
 *
 * A tall unit ER must render the bottom-left navigator thumbnail and the
 * directional edge-shadow overflow indicators, so the "there is more content
 * below, pan down" affordance is present at rest. The navigator now also LABELS
 * each box with its table name and MIRRORS the main diagram's highlight state, so
 * a highlighted table reads emphasized in the thumbnail. Canvas pixels are hard to
 * assert, so the minimap exposes DOM hooks: `title` + `data-tables` list every
 * table name, and `data-hl` lists the currently-highlighted tables (updated on
 * every redraw).
 */

const UC_NAME = "Real Time Disruption Detection";
const MEMBER = "gold_control_tower"; // a member of UC_NAME

test.describe("minimap + overflow cues", () => {
  test("a tall unit shows the navigator and directional cues", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);

    // The navigator thumbnail (bottom-left) and its viewport frame exist.
    const minimap = page.locator(".cy-minimap");
    await expect(minimap).toBeVisible();
    await expect(minimap.locator(".cy-minimap-frame")).toHaveCount(1);

    // The four directional overflow vignettes are mounted (toggled `.on` by the
    // extent sync). At least the bottom cue should be `.on` for a top-anchored
    // tall ER (more content below the initial viewport).
    await expect(page.locator(".cy-overflow")).toHaveCount(4);
    await expect(page.locator(".cy-overflow.bottom.on")).toHaveCount(1);
  });

  test("the minimap exposes its table names as a DOM hook", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    const minimap = page.locator(".cy-minimap");

    // data-tables + title list every table name drawn in the thumbnail. (The
    // names are also drawn inside the boxes on the canvas; the DOM hook makes the
    // rendering assertable without pixel-reading.)
    const names = await minimap.getAttribute("data-tables");
    expect(names).toBeTruthy();
    expect(names!.split(",")).toContain(MEMBER);

    const title = await minimap.getAttribute("title");
    expect(title).toContain(MEMBER);
  });

  test("a use-case hover is mirrored onto the minimap's highlight state", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);
    const minimap = page.locator(".cy-minimap");

    // At rest nothing is highlighted.
    await expect(minimap).toHaveAttribute("data-hl", "");

    // Hover the use case in the right-pane list: its member cards light `.uc-hl`,
    // and the minimap redraws to reflect that (its `data-hl` now lists the member).
    await page.locator(`.panel-uc[data-uc-name="${UC_NAME}"]`).hover();
    await expect(page.locator(`.card[data-table="${MEMBER}"]`)).toHaveClass(/uc-hl/);
    await expect(minimap).not.toHaveAttribute("data-hl", "");
    const hl = await minimap.getAttribute("data-hl");
    expect(hl!.split(",")).toContain(MEMBER);

    // Moving off the row clears the highlight; the minimap redraws back to empty.
    await page.locator("#toolbar .toolbar-title").hover();
    await expect(minimap).toHaveAttribute("data-hl", "");
  });
});
