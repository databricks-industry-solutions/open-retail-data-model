import { describe, it, expect, beforeEach, afterEach } from "vitest";
import CSS from "../src/styles.css?raw";
import { mountApp, type AppHandle } from "../src/main";
import { makeModel, installDom } from "./fixture";

/**
 * bug 2: the canvas stayed white in light AND dark because --page-bg was
 * defined in styles.css but bound to nothing (#cy / body had no background).
 *
 * Two things must be true and are asserted here:
 *  1. Toggling the theme flips the .theme-dark class on <html> (the DOM lever
 *     that swaps which --page-bg value applies) — asserted against the mounted
 *     app in jsdom.
 *  2. body AND #cy actually bind their background to var(--page-bg), and the
 *     light vs dark --page-bg values differ — asserted against the real
 *     styles.css source (jsdom+vitest does not populate document.styleSheets
 *     from Vite's JS-injected CSS, so we read the authoritative file).
 */


let app: AppHandle;
beforeEach(() => {
  installDom();
  app = mountApp(makeModel());
});
// Tear down between tests so listeners don't leak onto the shared jsdom window (M1).
afterEach(() => app.destroy());

describe("theme toggle changes the page/canvas background (bug 2)", () => {
  it("starts in light mode (no theme-dark class)", () => {
    expect(document.documentElement.classList.contains("theme-dark")).toBe(false);
  });

  it("clicking the toggle adds theme-dark, then removes it", () => {
    const btn = document.getElementById("theme-toggle") as HTMLButtonElement;
    expect(btn).not.toBeNull();

    btn.click();
    expect(document.documentElement.classList.contains("theme-dark")).toBe(true);
    btn.click();
    expect(document.documentElement.classList.contains("theme-dark")).toBe(false);
  });

  it("body and #cy both bind their background to var(--page-bg)", () => {
    // strip comments so a mention in a comment can't satisfy the assertion
    const css = CSS.replace(/\/\*[\s\S]*?\*\//g, "");
    const bodyRule = /body\s*\{[^}]*\}/.exec(css)?.[0] ?? "";
    const cyRule = /#cy\s*\{[^}]*\}/.exec(css)?.[0] ?? "";
    expect(bodyRule).toMatch(/background:\s*var\(--page-bg\)/);
    expect(cyRule).toMatch(/background:\s*var\(--page-bg\)/);
  });

  it("light and dark define DIFFERENT --page-bg values (canvas actually changes)", () => {
    const css = CSS.replace(/\/\*[\s\S]*?\*\//g, "");
    const rootBlock = /:root\s*\{([\s\S]*?)\}/.exec(css)?.[1] ?? "";
    const darkBlock = /html\.theme-dark\s*\{([\s\S]*?)\}/.exec(css)?.[1] ?? "";
    const light = /--page-bg:\s*([^;]+);/.exec(rootBlock)?.[1].trim();
    const dark = /--page-bg:\s*([^;]+);/.exec(darkBlock)?.[1].trim();
    expect(light).toBeTruthy();
    expect(dark).toBeTruthy();
    expect(dark).not.toBe(light);
  });

  it("the toolbar has NO hard-coded background overriding the theme (bug 2)", () => {
    // The old index.html hard-coded #toolbar { background:#1b1b2f } which pinned
    // the toolbar dark regardless of theme. It must now track the theme var.
    const css = CSS.replace(/\/\*[\s\S]*?\*\//g, "");
    const toolbarRule = /#toolbar\s*\{[^}]*\}/.exec(css)?.[0] ?? "";
    expect(toolbarRule).toMatch(/background:\s*var\(--toolbar-bg\)/);
  });
});
