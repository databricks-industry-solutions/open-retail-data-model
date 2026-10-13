import { describe, it, expect, beforeEach } from "vitest";
import { mountApp } from "../src/main";
import { makeModel, installDom } from "./fixture";

// M3: mountApp registers document/window/media-query listeners. Without teardown
// each re-mount leaked a stale handler onto the same jsdom window. destroy() must
// remove them so the app is cleanly re-mountable.
describe("mountApp destroy() (M3 re-mountability)", () => {
  beforeEach(() => installDom());

  it("destroy() does not throw and the app can be cleanly re-mounted", () => {
    const app = mountApp(makeModel());
    expect(document.querySelectorAll(".pkg").length).toBe(12);
    expect(() => app.destroy()).not.toThrow();

    // A second mount onto the same window renders correctly (no stale-handler crash).
    const app2 = mountApp(makeModel());
    expect(document.querySelectorAll(".pkg").length).toBe(12);
    expect(document.querySelectorAll(".dom").length).toBe(12);
    // M1: destroy() must clear the once-built toolbar too — a re-mount that left
    // it in place would append a SECOND set of controls with duplicate IDs. Assert
    // exactly one of each (the old .pkg-count assertion was blind to this leak).
    expect(document.querySelectorAll("#theme-toggle").length).toBe(1);
    expect(document.querySelectorAll("#filter-q").length).toBe(1);
    expect(document.querySelectorAll("#filter-layer").length).toBe(1);
    app2.destroy();
  });

  it("after destroy, a stray hashchange does not throw against the torn-down app", () => {
    const app = mountApp(makeModel());
    app.destroy();
    // The router listener is removed; dispatching must be a no-op, not a crash.
    expect(() => window.dispatchEvent(new Event("hashchange"))).not.toThrow();
  });

  it("a post-destroy resize is inert and re-mount leaves no duplicate widget", () => {
    // The graph mounts a bottom-right .cy-zoom overlay + a window `resize` listener
    // (design/38 §4). This test's REAL assertion is the window listener: a resize
    // dispatched after destroy() must not fire a relayout into a dead graph. The
    // `.cy-zoom` COUNT checks are weak here on purpose: cytoscape's canvas renderer
    // cannot init under jsdom, so the widget is never created and the counts pass
    // trivially (0 <= 1, 0 after destroy). The widget's real create/destroy lifecycle
    // is covered against a headless cy in graph.test.ts; the counts stay only as a
    // cheap guard that the invariant would hold if a renderer ever did create it.
    const app = mountApp(makeModel());
    window.location.hash = "#/u/promote-with-purpose"; // a unit that would mount the ER
    window.dispatchEvent(new Event("hashchange"));
    expect(document.querySelectorAll(".cy-zoom").length).toBeLessThanOrEqual(1);
    app.destroy();
    expect(document.querySelectorAll(".cy-zoom").length).toBe(0);
    // The window resize listener was removed in destroy(); dispatching is a no-op.
    expect(() => window.dispatchEvent(new Event("resize"))).not.toThrow();

    const app2 = mountApp(makeModel());
    expect(document.querySelectorAll(".cy-zoom").length).toBeLessThanOrEqual(1);
    app2.destroy();
  });
});
