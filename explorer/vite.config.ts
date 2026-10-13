/// <reference types="vitest/config" />
import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  build: { outDir: "dist" },
  // jsdom so the DOM/integration tests can mount the app and assert real
  // behaviour (search/PII/layer visibly reduce the rendered card count, Back
  // restores the overview, dark mode changes the computed background). The old
  // suite only tested the pure matches() predicate against a fake cytoscape,
  // which is exactly why the dead filters shipped green.
  test: {
    // vitest owns ONLY the jsdom unit/integration suite under test/. The Playwright
    // real-browser e2e specs live in e2e/ and import "@playwright/test" (its own
    // runner, not vitest) - scope the glob so `vitest run` never tries to collect
    // them (they run via `npm run e2e`, a separate harness).
    include: ["test/**/*.test.ts"],
    exclude: ["e2e/**", "node_modules/**", "dist/**"],
    environment: "jsdom",
    // process CSS so `import css from "...styles.css?raw"` returns the real file
    // text (the theme test asserts against the authoritative CSS source).
    css: true,
    // A concrete origin so jsdom wires up history/hash navigation.
    environmentOptions: {
      jsdom: { url: "http://localhost/" },
    },
    // Polyfill matchMedia (absent in jsdom) before any test module loads.
    setupFiles: ["./test/setup.ts"],
  },
});
