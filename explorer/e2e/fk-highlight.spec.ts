import { test, expect, type Page } from "@playwright/test";
import { gotoUnit, emitEdge, panBy, forceRender, UNIT, CHILD_TABLE } from "./helpers";

/**
 * Spec 1 - FK/PK relationship highlight, driven by the COLUMN (design/39).
 *
 * The old edge-hover trigger was effectively unusable: cytoscape draws edges
 * UNDER the cards and the node hit-area sits on top, so the thin FK arrow is only
 * hittable in narrow gaps and a hover "blinks then clears". The trigger is now:
 *  - PRIMARY: hover the actual FK/PK column ROW (a real DOM element inside the
 *    html-label card). Both that column and its joined counterpart light `.col-hl`,
 *    the cards are NOT washed out by the use-case fade, and the connecting edge is
 *    highlighted. The highlight survives a pan / forced re-render.
 *  - SECONDARY: tap the edge to PIN the relationship. The pin persists across a
 *    pan and until the same edge is tapped again or the background is tapped.
 *
 * Data: `early-risk-detection` has intra-unit FK edges. The edge
 * `disruption_event->disruption_alert` joins on `disruption_event_sk` (a PK on the
 * parent, an FK on the child), so BOTH cards carry a `data-col` row for it. Both
 * columns render as visible `.col-row` elements (key columns are drawn first).
 */

const PARENT = "disruption_event";
const EDGE = `${PARENT}->${CHILD_TABLE}`; // graph.ts edge id = `${parent}->${child}`
const JOIN_COL = "disruption_event_sk"; // PK on parent, FK on child

/** Read whether the edge with `edgeId` currently carries the `.highlighted` class. */
function edgeHighlighted(page: Page, edgeId: string): Promise<boolean> {
  return page.evaluate((id) => {
    const cy = (window as unknown as {
      __cy: { getElementById: (i: string) => { hasClass: (c: string) => boolean } };
    }).__cy;
    return cy.getElementById(id).hasClass("highlighted");
  }, edgeId);
}

/** Tap the cytoscape BACKGROUND (core), which clears a pinned relationship. */
function tapBackground(page: Page): Promise<void> {
  return page.evaluate(() => {
    const cy = (window as unknown as { __cy: { emit: (e: string) => void } }).__cy;
    cy.emit("tap"); // a core tap: evt.target === cy in the handler
  });
}

test.describe("FK/PK relationship highlight (column hover + edge pin)", () => {
  test("hovering a key column lights it + its joined counterpart, clears the fade, highlights the edge", async ({
    page,
  }) => {
    await gotoUnit(page, `/u/${UNIT}`);

    const parentRow = page.locator(
      `.card[data-table="${PARENT}"] .col-row[data-col="${JOIN_COL}"]`
    );
    const childRow = page.locator(
      `.card[data-table="${CHILD_TABLE}"] .col-row[data-col="${JOIN_COL}"]`
    );
    const parentCard = page.locator(`.card[data-table="${PARENT}"]`);
    const childCard = page.locator(`.card[data-table="${CHILD_TABLE}"]`);

    // Hover the ACTUAL parent PK column row with a real mouse.
    await parentRow.hover();

    // Both the hovered column and its joined counterpart column light up.
    await expect(parentRow).toHaveClass(/col-hl/);
    await expect(childRow).toHaveClass(/col-hl/);

    // The cards carrying them are NOT washed out by the use-case fade (design/39
    // reconcile: hovering a column enters the card + fires the node hover, which
    // used to add `.uc-faded`; the FK highlight clears it so the columns read).
    await expect(parentCard).not.toHaveClass(/uc-faded/);
    await expect(childCard).not.toHaveClass(/uc-faded/);

    // The connecting edge is highlighted.
    expect(await edgeHighlighted(page, EDGE)).toBe(true);
  });

  test("the highlight SURVIVES a pan / forced re-render", async ({ page }) => {
    // The regression this guards (design/38 §1, carried to design/39): the
    // html-label plugin REGENERATES each card's innerHTML on every `render`
    // (pan/zoom/forceRender), wiping `.col-hl` off the rows. The fix re-applies the
    // highlight on every render while a relationship is active.
    await gotoUnit(page, `/u/${UNIT}`);

    const parentRow = page.locator(
      `.card[data-table="${PARENT}"] .col-row[data-col="${JOIN_COL}"]`
    );
    const childRow = page.locator(
      `.card[data-table="${CHILD_TABLE}"] .col-row[data-col="${JOIN_COL}"]`
    );

    await parentRow.hover();
    await expect(parentRow).toHaveClass(/col-hl/);
    await expect(childRow).toHaveClass(/col-hl/);

    // Pan the canvas (drives a `render`) and force an extra render, both of which
    // make the html-label plugin rebuild the card DOM. Keep the pointer over the
    // row so the delegated hover state stays active.
    await panBy(page, 40, 0);
    await forceRender(page);
    // Settle PAST the plugin's regeneration window before asserting. A post-applied
    // (non-data-driven) `.col-hl` is wiped a frame after regeneration, so without
    // this wait a poll could catch a transient flash and pass while it's broken.
    await page.waitForTimeout(250);

    // The highlight is still present because it is baked into the regenerated
    // markup (data-driven), not toggled on after the fact.
    await expect(parentRow).toHaveClass(/col-hl/);
    await expect(childRow).toHaveClass(/col-hl/);
  });

  test("tapping the edge PINS the relationship; it persists past a pan; tapping the background clears it", async ({
    page,
  }) => {
    await gotoUnit(page, `/u/${UNIT}`);

    const parentRow = page.locator(
      `.card[data-table="${PARENT}"] .col-row[data-col="${JOIN_COL}"]`
    );
    const childRow = page.locator(
      `.card[data-table="${CHILD_TABLE}"] .col-row[data-col="${JOIN_COL}"]`
    );

    // Tap the edge to PIN the relationship (the reliable "click the arrow" path;
    // the thin edge is hard to hover, but a tap registers via __cy).
    await emitEdge(page, EDGE, "tap");

    // The relationship highlight is applied (parent PK cols + child FK cols + edge).
    await expect(parentRow).toHaveClass(/col-hl/);
    await expect(childRow).toHaveClass(/col-hl/);
    expect(await edgeHighlighted(page, EDGE)).toBe(true);

    // A PINNED highlight PERSISTS across a pan + forced re-render (unlike a
    // transient column hover, it does not clear on mouseout either).
    await panBy(page, 60, 20);
    await forceRender(page);
    // Settle past the regeneration window: a pin has NO held cursor to re-trigger
    // it, so if the highlight were post-applied it would be gone here (the exact
    // bug that shipped). Data-driven `.col-hl` survives.
    await page.waitForTimeout(250);
    await expect(parentRow).toHaveClass(/col-hl/);
    await expect(childRow).toHaveClass(/col-hl/);
    expect(await edgeHighlighted(page, EDGE)).toBe(true);

    // Tapping the background clears the pin.
    await tapBackground(page);
    await forceRender(page);
    await expect(parentRow).not.toHaveClass(/col-hl/);
    await expect(childRow).not.toHaveClass(/col-hl/);
    expect(await edgeHighlighted(page, EDGE)).toBe(false);
  });
});
