import { test, expect } from "@playwright/test";
import { fetchModel } from "./helpers";

/**
 * L0 toolbar filters drive the DOM show/hide (one visibility mechanism, per the
 * overview redesign): typing in `#filter-q` narrows the visible cards and updates
 * the `#status-readout` ("showing N of M[ · K hidden]"); the layer select and the
 * PII-only checkbox filter too; clearing the search restores the full set.
 *
 * Filtered-out cards get a `.hidden` class (they are not detached), so a "visible"
 * card is `.pkg:not(.hidden)` / `.dom:not(.hidden)`.
 */

const visibleCards = ".pkg:not(.hidden), .dom:not(.hidden)";

async function readoutTotal(text: string): Promise<{ showing: number; of: number }> {
  const m = /showing (\d+) of (\d+)/.exec(text);
  if (!m) throw new Error(`readout not in expected form: "${text}"`);
  return { showing: Number(m[1]), of: Number(m[2]) };
}

test.describe("L0 filters", () => {
  test("search narrows the cards + updates the readout; clearing restores", async ({ page }) => {
    const model = await fetchModel(page);
    await page.goto("./?e2e=1#/");
    await page.locator(".pkg").first().waitFor({ state: "attached", timeout: 15_000 });

    const readout = page.locator("#status-readout");
    await expect(readout).toContainText(/showing \d+ of \d+/);
    const initial = await readoutTotal((await readout.textContent()) ?? "");
    const total = initial.of;
    expect(initial.showing).toBe(total); // unfiltered: all visible
    const fullCount = await page.locator(visibleCards).count();
    expect(fullCount).toBe(total);

    // Type a query that matches at least one but not all entities. "customer" is a
    // stable slug fragment in this model; assert it filters strictly narrower.
    const query = "customer";
    // Sanity from the model: at least one and not all units contain the query.
    const matching = model.units.filter((u) => u.name.includes(query)).length;
    expect(matching).toBeGreaterThan(0);
    expect(matching).toBeLessThan(model.units.length);

    await page.locator("#filter-q").fill(query);
    await expect
      .poll(async () => (await readoutTotal((await readout.textContent()) ?? "")).showing)
      .toBeLessThan(total);
    const narrowed = await readoutTotal((await readout.textContent()) ?? "");
    expect(narrowed.showing).toBeGreaterThan(0);
    expect(narrowed.of).toBe(total); // denominator is the full set
    expect(await page.locator(visibleCards).count()).toBe(narrowed.showing);

    // Clearing restores the full set.
    await page.locator("#filter-q").fill("");
    await expect
      .poll(async () => (await readoutTotal((await readout.textContent()) ?? "")).showing)
      .toBe(total);
    expect(await page.locator(visibleCards).count()).toBe(total);
  });

  test("layer select filters to core / outcome", async ({ page }) => {
    const model = await fetchModel(page);
    await page.goto("./?e2e=1#/");
    await page.locator(".pkg").first().waitFor({ state: "attached", timeout: 15_000 });

    const nCore = model.units.filter((u) => u.kind === "core").length;
    const nOutcome = model.units.filter((u) => u.kind === "outcome").length;

    // Core: only domain cards remain visible; no package cards.
    await page.locator("#filter-layer").selectOption("core");
    await expect.poll(() => page.locator(".dom:not(.hidden)").count()).toBe(nCore);
    await expect(page.locator(".pkg:not(.hidden)")).toHaveCount(0);

    // Outcome: only package cards remain visible; no domain cards.
    await page.locator("#filter-layer").selectOption("outcome");
    await expect.poll(() => page.locator(".pkg:not(.hidden)").count()).toBe(nOutcome);
    await expect(page.locator(".dom:not(.hidden)")).toHaveCount(0);

    // Back to all.
    await page.locator("#filter-layer").selectOption("all");
    await expect
      .poll(() => page.locator(".pkg:not(.hidden), .dom:not(.hidden)").count())
      .toBe(nCore + nOutcome);
  });

  test("PII-only checkbox narrows to PII-bearing cards", async ({ page }) => {
    await page.goto("./?e2e=1#/");
    await page.locator(".pkg").first().waitFor({ state: "attached", timeout: 15_000 });

    const full = await page.locator(".pkg:not(.hidden), .dom:not(.hidden)").count();

    await page.locator("#filter-pii").check();
    // The filter must NARROW the set (strict <, not <=, so a no-op filter fails
    // here rather than only in the data-pii loop below) and acts as a settle barrier.
    await expect
      .poll(() => page.locator(".pkg:not(.hidden), .dom:not(.hidden)").count())
      .toBeLessThan(full);
    const visiblePiiFlags = await page
      .locator(".pkg:not(.hidden), .dom:not(.hidden)")
      .evaluateAll((els) => els.map((e) => (e as HTMLElement).dataset["pii"]));
    for (const flag of visiblePiiFlags) expect(flag).toBe("true");

    await page.locator("#filter-pii").uncheck();
    await expect
      .poll(() => page.locator(".pkg:not(.hidden), .dom:not(.hidden)").count())
      .toBe(full);
  });
});
