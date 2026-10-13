import { defineConfig, devices } from "@playwright/test";

/**
 * Real-browser end-to-end harness for the explorer SPA.
 *
 * WHY this exists: the vitest suite runs under jsdom, which has NO canvas / real
 * layout engine, so it cannot exercise cytoscape's canvas interactions (edge
 * hover, node tap, zoom, pan). Every interactive regression that has bitten this
 * app (FK/PK highlight washed out, click-to-L2 blink, zoom reset on resize) lives
 * precisely in that jsdom-invisible layer. These specs drive the ACTUAL built app
 * in a headless Chromium against the Vite preview server, so those behaviours are
 * finally under an automated guard.
 *
 * The specs reach cytoscape through `window.__cy` - a dev/e2e-only handle exposed
 * in graph.ts mountGraph, guarded by `import.meta.env.DEV` so it never ships in a
 * production build. Under `vite preview` (which serves a DEV=false build) the site
 * is served with the harness flag `?e2e=1`, which re-enables the handle for tests
 * without shipping it to real users (see main.ts / graph.ts).
 */

const PORT = 4173; // vite preview default
const BASE_URL = `http://localhost:${PORT}`;

export default defineConfig({
  testDir: "./e2e",
  // The interactive assertions read real DOM/canvas state that settles a tick
  // after a gesture; give each a modest budget but keep the suite fast.
  timeout: 30_000,
  expect: { timeout: 7_500 },
  fullyParallel: false, // one preview server; keep the canvas interactions serial
  forbidOnly: !!process.env.CI, // a stray .only must fail CI, never pass silently
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : [["list"]],
  use: {
    baseURL: BASE_URL,
    trace: "on-first-retry",
    // Deterministic viewport so the width-aware column packing + minimap geometry
    // are stable across machines (the layout is a pure function of container size).
    viewport: { width: 1280, height: 900 },
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  // Build once, then serve the built site with `vite preview`. Building (rather
  // than `vite dev`) exercises the SAME artifact the deploy ships, and asserts the
  // `__cy` handle is correctly gated (present only under the `?e2e=1` flag, never
  // in a bare production load).
  webServer: {
    command: "npm run build && npm run preview -- --port " + PORT + " --strictPort",
    url: BASE_URL,
    timeout: 120_000,
    reuseExistingServer: !process.env.CI,
  },
});
