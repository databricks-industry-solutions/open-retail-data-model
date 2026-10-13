import { test, expect } from "@playwright/test";

/**
 * A planned package (0 tables) has no ER to draw. Navigating to it must show the
 * `.cy-empty` message (not a blank cytoscape mount) AND the side panel must list
 * its use cases, so the reader still sees WHAT the package is planned to enable.
 *
 * The model has matured past having a real 0-table planned package (every package now
 * ships tables), so rather than depend on that drift, we INJECT a synthetic planned unit
 * into the model the app boots from — intercepting the `model.json` fetch — and drive the
 * REAL empty-state render path against it. Deterministic, and coverage is retained
 * regardless of how many real packages get built out.
 */

const FIXTURE = {
  name: "e2e-planned-fixture",
  kind: "outcome" as const,
  tables: [] as { name: string }[],
  relationships: [] as { parent_table: string; child_table: string }[],
  glossary_path: null,
  contract_path: null,
  source_url: "https://github.com/databricks-industry-solutions/open-retail-data-model/tree/main/outcome-packages/e2e-planned-fixture",
  use_cases: [
    { name: "E2E Planned Use Case A", status: "planned", tables: [] as string[] },
    { name: "E2E Planned Use Case B", status: "planned", tables: [] as string[] },
  ],
};

test.describe("planned package empty-state", () => {
  test("0-table package shows .cy-empty and lists its use cases in the panel", async ({
    page,
  }) => {
    // Append the synthetic 0-table unit to the served model, BEFORE the app's boot fetch.
    // route.fetch() gets the real response (bypassing this handler), so every real unit
    // still loads and only our fixture is added.
    await page.route("**/model.json", async (route) => {
      const resp = await route.fetch();
      const model = await resp.json();
      if (!model.units.some((u: { name: string }) => u.name === FIXTURE.name)) {
        model.units.push(FIXTURE);
      }
      await route.fulfill({ json: model });
    });

    const ucNames = FIXTURE.use_cases.map((uc) => uc.name);
    await page.goto(`./?e2e=1#/u/${FIXTURE.name}`);

    // The empty-state message replaces the ER.
    const empty = page.locator(".cy-empty");
    await expect(empty).toBeVisible();
    await expect(empty).toContainText(/planned/i);

    // The side panel lists every use case this package enables.
    const panel = page.locator("#panel");
    await expect(panel.locator(".panel-uc-list")).toHaveCount(1);
    await expect(panel.locator(".panel-uc")).toHaveCount(ucNames.length);
    for (const uc of ucNames) {
      await expect(panel.locator(`.panel-uc[data-uc-name="${uc}"]`)).toHaveCount(1);
    }
  });
});
