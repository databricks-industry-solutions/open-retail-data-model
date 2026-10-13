import { test, expect } from "@playwright/test";
import { fetchModel, collectConsoleErrors } from "./helpers";

/**
 * Broad health sweep: EVERY unit in the served model.json must deep-link to a
 * healthy L1 view. "Healthy" means one of:
 *   - an ER mounted (cytoscape has >0 nodes), OR
 *   - the planned/0-table empty state (`.cy-empty`) is shown,
 * AND the load logged NO console errors (warnings are fine — cytoscape emits a
 * benign wheel-sensitivity warning).
 *
 * The unit list is derived from model.json at runtime, so a unit added to the
 * model is automatically covered without editing this spec. A break fails with
 * the offending unit name + the captured error text so it is diagnosable.
 */

test.describe("all units smoke", () => {
  test("every unit deep-links to a healthy L1 (ER or empty-state, no console error)", async ({
    page,
  }) => {
    const errors = collectConsoleErrors(page);
    const model = await fetchModel(page);
    const units = model.units.map((u) => u.name);
    expect(units.length).toBeGreaterThan(0);

    for (const unit of units) {
      // Reset the shared error buffer per unit so a failure names the culprit.
      errors.length = 0;
      // A fresh full load per unit: the `?e2e=1` query is constant so a bare
      // `goto` to a hash-only change would NOT reload (it would be an in-page
      // hash nav, leaving the PRIOR unit's `window.__cy` handle + its stale node
      // count in place). Force a real reload so each unit boots clean and the
      // handle reflects THIS unit only.
      await page.goto(`./?e2e=1#/u/${unit}`);
      await page.reload();

      // Wait until the unit view has settled into ONE of the two healthy shapes.
      // Key the wait on the DOM the user actually sees (a painted `.card` for an
      // ER, or the planned/empty-state element) rather than the `__cy` node count
      // alone, so a stale handle can never mask a blank render.
      await page.waitForFunction(
        () => {
          const card = !!document.querySelector(".card");
          const empty = !!document.querySelector(".cy-empty");
          return card || empty;
        },
        undefined,
        { timeout: 15_000 }
      );

      const state = await page.evaluate(() => {
        const cy = (window as unknown as { __cy?: { nodes: () => { length: number } } }).__cy;
        const empty = !!document.querySelector(".cy-empty");
        return {
          nodes: cy ? cy.nodes().length : 0,
          cards: document.querySelectorAll(".card").length,
          empty,
        };
      });

      // Healthy = a planned/empty package (empty-state shown, and the ER is NOT
      // expected) OR an ER that actually mounted (>0 nodes) AND painted a card.
      // Reading BOTH shapes off this-load DOM avoids the stale-handle trap.
      const healthy = state.empty
        ? state.cards === 0 // an empty package must not also paint ER cards
        : state.nodes > 0 && state.cards > 0;
      expect(
        healthy,
        `unit "${unit}" is unhealthy: nodes=${state.nodes}, cards=${state.cards}, empty=${state.empty}`
      ).toBe(true);

      expect(
        errors,
        `unit "${unit}" logged console error(s): ${errors.join(" | ")}`
      ).toEqual([]);
    }
  });
});
