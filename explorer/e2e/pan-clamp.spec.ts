import { test, expect } from "@playwright/test";
import { gotoUnit, panBy, extentAndContentBB, UNIT } from "./helpers";

/**
 * Spec 7 - pan clamp (design/38 §2).
 *
 * The user could pan the canvas (or drag the minimap frame) until NO tables were
 * visible - an empty void. The pan clamp keeps the content bounding box
 * overlapping the viewport by a margin on every pan, so however hard you drag in
 * any direction the tables can never scroll entirely off-screen.
 *
 * We drive big `panBy` deltas via the `__cy` handle (each fires a `render`, which
 * fires the pan-clamp handler) and assert `cy.elements().boundingBox()` still
 * overlaps `cy.extent()` afterwards. Two 1-D ranges [a1,a2] and [b1,b2] overlap
 * iff a1 <= b2 AND b1 <= a2; both axes must overlap for the boxes to overlap.
 */

/** True iff the content bbox and the viewport extent overlap on both axes. */
function overlaps(
  ext: { x1: number; y1: number; x2: number; y2: number },
  bb: { x1: number; y1: number; x2: number; y2: number }
): boolean {
  const onX = ext.x1 <= bb.x2 && bb.x1 <= ext.x2;
  const onY = ext.y1 <= bb.y2 && bb.y1 <= ext.y2;
  return onX && onY;
}

test.describe("pan clamp keeps content on-screen", () => {
  // Hammer each direction with a big rendered-space delta; after each the content
  // must still overlap the viewport (never a fully empty void).
  const HARD = 4000; // px, far larger than any unit ER
  const directions: Array<{ name: string; dx: number; dy: number }> = [
    { name: "left", dx: -HARD, dy: 0 },
    { name: "right", dx: HARD, dy: 0 },
    { name: "up", dx: 0, dy: -HARD },
    { name: "down", dx: 0, dy: HARD },
  ];

  for (const d of directions) {
    test(`panning hard ${d.name} does not push all tables off-screen`, async ({ page }) => {
      await gotoUnit(page, `/u/${UNIT}`);

      await panBy(page, d.dx, d.dy);

      const { ext, bb } = await extentAndContentBB(page);
      expect(overlaps(ext, bb)).toBe(true);
    });
  }

  test("repeated hard pans in every direction still leave content visible", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);

    for (const d of directions) {
      await panBy(page, d.dx, d.dy);
      const { ext, bb } = await extentAndContentBB(page);
      expect(overlaps(ext, bb)).toBe(true);
    }
  });
});
