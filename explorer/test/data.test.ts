import { describe, it, expect } from "vitest";
// Read the real emitted model via ?raw + JSON.parse (the project deliberately
// avoids fs/@types/node; see theme.integration.test.ts for the same pattern).
import modelRaw from "../public/model.json?raw";
import { deriveModel, UNTHEMED_LANE_TITLE } from "../src/data";
import type { Model } from "../src/model";

const model = JSON.parse(modelRaw) as Model;

/**
 * M3 guard: THEME_MAP in data.ts is a hand-maintained allowlist of the 12
 * outcome packages. A package present in model.json but absent from THEME_MAP
 * now falls to a clearly-labelled catch-all lane (UNTHEMED_LANE_TITLE) so it can
 * never silently vanish from the UI, but it must still be placed under a REAL
 * theme before shipping. This asserts the map and the emitted model stay in
 * lockstep: a straggler landing in the catch-all lane fails CI here.
 */
describe("deriveModel: THEME_MAP covers exactly the model's outcome units (M3)", () => {
  const dm = deriveModel(model);

  it("every outcome unit is placed under a real theme (none fall to the catch-all)", () => {
    const outcomeUnits = model.units
      .filter((u) => u.kind === "outcome")
      .map((u) => u.name)
      .sort();
    // Exclude the fallback lane: a unit that landed there is NOT properly themed,
    // so it must be absent from `themed` and make the exact-coverage check fail.
    const realThemes = dm.themes.filter((t) => t.title !== UNTHEMED_LANE_TITLE);
    const themed = realThemes.flatMap((t) => t.packages.map((p) => p.name)).sort();
    // no package listed under two themes
    expect(new Set(themed).size).toBe(themed.length);
    // exact coverage in both directions (missing OR extra both fail)
    expect(themed).toEqual(outcomeUnits);
    // and a healthy model never populates the catch-all lane
    const catchAll = dm.themes.find((t) => t.title === UNTHEMED_LANE_TITLE);
    expect(catchAll?.packages ?? []).toHaveLength(0);
  });

  it("derives a valid package status for every package", () => {
    const statuses = dm.themes.flatMap((t) => t.packages.map((p) => p.status));
    expect(statuses.length).toBeGreaterThan(0);
    for (const s of statuses) {
      expect(["built", "in-progress", "planned"]).toContain(s);
    }
  });

  it("totals.packages matches the number of themed packages", () => {
    const themed = dm.themes.reduce((n, t) => n + t.packages.length, 0);
    expect(dm.totals.packages).toBe(themed);
  });
});
