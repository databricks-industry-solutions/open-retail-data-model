import { test, expect } from "@playwright/test";
import { gotoUnit } from "./helpers";

/**
 * Guards the assign-to-both mapping: a gold table serving MORE than one use case
 * renders an at-rest "shared xN" chip whose title tooltip lists the owning use
 * cases (see cards.ts sharedChip). On balancing-margin-and-volume, several
 * feature tables belong to BOTH "Dynamic Price Optimization" and "Elasticity
 * Modeling", so at least one card must carry a `.chip.shared` whose title names
 * both. If the both-use-case mapping regresses, the chip / title drops and this
 * fails.
 */

const UNIT = "balancing-margin-and-volume";
const UC_A = "Dynamic Price Optimization";
const UC_B = "Elasticity Modeling";

test.describe("shared-table chip", () => {
  test("a shared card shows a shared chip naming both use cases", async ({ page }) => {
    await gotoUnit(page, `/u/${UNIT}`);

    // At least one shared chip exists, and its text says "shared".
    const sharedChips = page.locator(".card .chip.shared");
    await expect(sharedChips.first()).toBeVisible();
    await expect(sharedChips.first()).toHaveText(/shared/i);

    // Some shared chip's title lists BOTH use cases (the assign-to-both mapping).
    const titles = await sharedChips.evaluateAll((els) =>
      els.map((e) => e.getAttribute("title") ?? "")
    );
    const both = titles.find((t) => t.includes(UC_A) && t.includes(UC_B));
    expect(
      both,
      `no shared chip title names both "${UC_A}" and "${UC_B}". Titles: ${JSON.stringify(titles)}`
    ).toBeTruthy();
  });
});
