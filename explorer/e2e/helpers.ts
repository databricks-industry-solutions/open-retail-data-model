import { type Page, expect } from "@playwright/test";

/**
 * Shared e2e helpers for driving the explorer's cytoscape ER through the
 * `window.__cy` handle (exposed under the `?e2e=1` flag - see graph.ts).
 *
 * The specs load routes with `?e2e=1` in the QUERY string and the app route in
 * the HASH (e.g. `/?e2e=1#/u/early-risk-detection`). The query survives hash
 * navigation, so the handle stays exposed as the user drills L1 <-> L2.
 */

/** A built ER unit that HAS intra-unit FK edges + use-case bands (real data). */
export const UNIT = "early-risk-detection";
/** A gold table in `UNIT` that is the FK child of two in-unit parents. */
export const CHILD_TABLE = "disruption_alert";

/** Load a hash route with the e2e handle enabled, and wait for the ER to mount. */
export async function gotoUnit(page: Page, hash: string): Promise<void> {
  // base is "./" so a relative "?e2e=1#..." resolves under the preview root.
  await page.goto(`./?e2e=1#${hash}`);
  await waitForGraph(page);
}

/** Resolve once cytoscape has mounted, laid out, and rendered its card DOM. */
export async function waitForGraph(page: Page): Promise<void> {
  await page.waitForFunction(
    () => {
      const cy = (window as unknown as { __cy?: { nodes: () => { length: number } } }).__cy;
      return !!cy && cy.nodes().length > 0;
    },
    undefined,
    { timeout: 15_000 }
  );
  // The html-label cards render a tick after the preset layout; wait for at least
  // one real card to exist in the DOM before asserting on card classes.
  await page.locator(".card").first().waitFor({ state: "attached", timeout: 15_000 });
}

/** Current cytoscape zoom level via the handle. */
export function cyZoom(page: Page): Promise<number> {
  return page.evaluate(() => (window as unknown as { __cy: { zoom: () => number } }).__cy.zoom());
}

/**
 * A stable identity token for the mounted cytoscape instance. cytoscape has no
 * public id, so we stamp a monotonic marker onto the instance the FIRST time we
 * observe it; a later read returns the SAME token iff the instance was not
 * re-created (destroy() + new mountGraph() would yield a fresh, unstamped one).
 */
export function cyIdentity(page: Page): Promise<number> {
  return page.evaluate(() => {
    const w = window as unknown as { __cy: Record<string, number>; __cyStamp?: number };
    const cy = w.__cy;
    if (cy["__e2eId"] == null) {
      w.__cyStamp = (w.__cyStamp ?? 0) + 1;
      cy["__e2eId"] = w.__cyStamp;
    }
    return cy["__e2eId"];
  });
}

/** Emit a raw cytoscape event on the first edge whose id matches `edgeId`. */
export async function emitEdge(page: Page, edgeId: string, event: string): Promise<void> {
  await page.evaluate(
    ({ edgeId, event }) => {
      const cy = (window as unknown as {
        __cy: { getElementById: (id: string) => { length: number; emit: (e: string) => void } };
      }).__cy;
      const e = cy.getElementById(edgeId);
      if (e.length) e.emit(event);
    },
    { edgeId, event }
  );
}

/** Emit a raw cytoscape event on the node with id `nodeId`. */
export async function emitNode(page: Page, nodeId: string, event: string): Promise<void> {
  await page.evaluate(
    ({ nodeId, event }) => {
      const cy = (window as unknown as {
        __cy: { getElementById: (id: string) => { length: number; emit: (e: string) => void } };
      }).__cy;
      const n = cy.getElementById(nodeId);
      if (n.length) n.emit(event);
    },
    { nodeId, event }
  );
}

/** Pan the canvas by a rendered-space delta via the handle (drives a `render`). */
export async function panBy(page: Page, dx: number, dy: number): Promise<void> {
  await page.evaluate(
    ({ dx, dy }) => {
      const cy = (window as unknown as {
        __cy: { panBy: (p: { x: number; y: number }) => void };
      }).__cy;
      cy.panBy({ x: dx, y: dy });
    },
    { dx, dy }
  );
}

/** Force a cytoscape re-render (the html-label plugin rebuilds each card's DOM). */
export async function forceRender(page: Page): Promise<void> {
  await page.evaluate(() => {
    const cy = (window as unknown as {
      __cy: { forceRender: () => void };
    }).__cy;
    cy.forceRender();
  });
}

/**
 * The current viewport extent and the content bounding box via the handle. Used
 * by the pan-clamp spec to assert the two boxes still overlap after a hard pan.
 */
export function extentAndContentBB(page: Page): Promise<{
  ext: { x1: number; y1: number; x2: number; y2: number };
  bb: { x1: number; y1: number; x2: number; y2: number };
}> {
  return page.evaluate(() => {
    const cy = (window as unknown as {
      __cy: {
        extent: () => { x1: number; y1: number; x2: number; y2: number };
        elements: () => { boundingBox: () => { x1: number; y1: number; x2: number; y2: number } };
      };
    }).__cy;
    const ext = cy.extent();
    const bb = cy.elements().boundingBox();
    return {
      ext: { x1: ext.x1, y1: ext.y1, x2: ext.x2, y2: ext.y2 },
      bb: { x1: bb.x1, y1: bb.y1, x2: bb.x2, y2: bb.y2 },
    };
  });
}

/** Assert `window.__cy` is (un)defined - proves the handle gate. */
export async function expectHandle(page: Page, present: boolean): Promise<void> {
  const has = await page.evaluate(
    () => typeof (window as unknown as { __cy?: unknown }).__cy !== "undefined"
  );
  expect(has).toBe(present);
}

/** The number of nodes currently in the mounted cytoscape, via the handle. */
export function cyNodeCount(page: Page): Promise<number> {
  return page.evaluate(
    () => (window as unknown as { __cy: { nodes: () => { length: number } } }).__cy.nodes().length
  );
}

/**
 * The parsed model that the served site loads. Fetched from the SAME
 * `./model.json` the app boots from, so the specs derive their unit/table lists
 * at runtime instead of hard-coding names that drift as the model grows. The
 * fetch is issued through the page so it resolves against the preview base URL.
 */
export interface ModelUnit {
  name: string;
  kind: "core" | "outcome";
  tables: { name: string }[];
  relationships: { parent_table: string; child_table: string }[];
  glossary_path: string | null;
  contract_path: string | null;
  source_url: string;
  use_cases: { name: string; status: string; tables: string[] }[];
}
export interface ModelJson {
  overview: { nodes: { id: string }[]; edges: unknown[] };
  units: ModelUnit[];
}

/** Fetch and parse the served `./model.json` in the page context. */
export async function fetchModel(page: Page): Promise<ModelJson> {
  // Land on the app first so a relative fetch resolves under the preview root.
  if (!page.url().startsWith("http")) await page.goto("./?e2e=1#/");
  return page.evaluate(
    async () => (await fetch("./model.json").then((r) => r.json())) as unknown as ModelJson
  );
}

/**
 * Collect every `console` message of type "error" a spec produces. cytoscape
 * emits a benign wheel-sensitivity WARNING (not an error), so filtering to
 * type === "error" keeps the smoke test honest without whitelisting text.
 * Returns a live array that fills as the page runs; read it after the load.
 */
export function collectConsoleErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on("console", (msg) => {
    if (msg.type() === "error") errors.push(msg.text());
  });
  // A thrown, uncaught page error would also indicate an unhealthy load.
  page.on("pageerror", (err) => errors.push(String(err?.message ?? err)));
  return errors;
}
