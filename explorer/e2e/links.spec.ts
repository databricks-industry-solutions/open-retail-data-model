import { test, expect } from "@playwright/test";
import { fetchModel, waitForGraph } from "./helpers";

/**
 * Guards the "failed to load contract / glossary" regression: the panel renders
 * Glossary / Contract links (base-rebased under the deployed root), and each
 * MUST resolve to a real staged asset. We open the L1 panel of a unit that has
 * BOTH a glossary_path and a contract_path (chosen from model.json at runtime),
 * read each link's resolved href, and fetch it — asserting HTTP 200 with a
 * non-empty body. A dead link (SPA 404 fallback or missing staged file) fails
 * here instead of only surfacing in the browser.
 */

test.describe("panel asset links resolve", () => {
  test("Glossary + Contract hrefs return HTTP 200 with a non-empty body", async ({ page }) => {
    const model = await fetchModel(page);
    const unit = model.units.find(
      (u) => u.glossary_path && u.contract_path && u.tables.length > 0
    );
    expect(unit, "no unit has both a glossary_path and a contract_path with tables").toBeTruthy();
    const name = unit!.name;

    await page.goto(`./?e2e=1#/u/${name}`);
    await waitForGraph(page);

    // The L1 side panel renders the links. Assert both labels are present.
    const panel = page.locator("#panel");
    const glossaryLink = panel.locator("a", { hasText: "Glossary" });
    const contractLink = panel.locator("a", { hasText: "Contract" });
    await expect(glossaryLink).toBeVisible();
    await expect(contractLink).toBeVisible();
    // The GitHub link targets the source repo, not a staged asset, so it is checked
    // against model.json rather than fetched (the repo may require sign-in).
    const githubLink = panel.locator("a", { hasText: "GitHub" });
    await expect(githubLink).toBeVisible();
    expect(await githubLink.getAttribute("href")).toBe(unit!.source_url);

    for (const link of [glossaryLink, contractLink]) {
      const href = await link.getAttribute("href");
      expect(href, "link is missing an href").toBeTruthy();
      // Resolve the (possibly base-relative) href against the current page URL,
      // then fetch it through Playwright's request context (same origin/server).
      const resolved = new URL(href!, page.url()).toString();
      const resp = await page.request.get(resolved);
      expect(resp.status(), `${resolved} did not return 200`).toBe(200);
      const body = await resp.text();
      expect(body.trim().length, `${resolved} returned an empty body`).toBeGreaterThan(0);
      // A dead link would fall through to the SPA's index.html shell; assert the
      // body is NOT that HTML doc (the served raw asset is yaml / markdown).
      expect(
        body.includes("<div id=\"toolbar\">") || body.includes("<title>ORDM Model Explorer"),
        `${resolved} served the SPA fallback instead of the raw asset`
      ).toBe(false);
    }
  });
});
