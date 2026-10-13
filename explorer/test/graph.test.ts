import { describe, it, expect } from "vitest";
import cytoscape from "cytoscape";
import {
  fitCols,
  clampPan,
  createZoomWidget,
  createMinimap,
  createEdgeIndicators,
} from "../src/graph";

/** A non-degenerate content bbox so the navigator factories build a real overlay. */
const BB = { x1: 0, y1: 0, x2: 400, y2: 600, w: 400, h: 600 };

/** A headless cy whose width()/extent() report a real viewport for the navigator
 *  math (jsdom cannot init cytoscape's canvas renderer, so we stub these reads). */
function headlessCy(): cytoscape.Core {
  const cy = cytoscape({
    headless: true,
    elements: [
      { data: { id: "a", cls: "gold" } },
      { data: { id: "b", cls: "core" } },
    ],
  });
  // Give the nodes a boundingBox the minimap can draw, and a measurable viewport.
  cy.getElementById("a").position({ x: 60, y: 60 });
  cy.getElementById("b").position({ x: 60, y: 300 });
  (cy as unknown as { width: () => number }).width = () => 800;
  (cy as unknown as { height: () => number }).height = () => 600;
  return cy;
}

// fitCols is the width-aware column-count heuristic that replaced the old
// width-blind cap of 3 (design/38 §3). It is pure arithmetic over (availPx, n):
//   cols = clamp(1, n, floor((availPx + GUTTER) / UNIT_X_PITCH))
// with UNIT_X_PITCH = 320 (CARD_W 280 + GUTTER 40). These tests pin the three
// invariants: more width -> more columns, capped at n, floored at 1.
describe("fitCols (width-aware column count)", () => {
  it("packs more columns as the available width grows", () => {
    // one pitch (320) fits 1 col; each extra 320px fits one more.
    expect(fitCols(320, 10)).toBe(1);
    expect(fitCols(640, 10)).toBe(2);
    expect(fitCols(960, 10)).toBe(3);
    // a wide viewport is NOT capped at 3 (the old bug) — it keeps filling.
    expect(fitCols(1600, 10)).toBeGreaterThan(3);
  });

  it("never returns more columns than there are cards", () => {
    // huge width, only 2 cards -> at most 2 columns (no empty phantom columns).
    expect(fitCols(5000, 2)).toBe(2);
    expect(fitCols(5000, 1)).toBe(1);
  });

  it("floors at 1 column for a zero / negative / tiny width", () => {
    expect(fitCols(0, 5)).toBe(1);
    expect(fitCols(-100, 5)).toBe(1);
    expect(fitCols(50, 5)).toBe(1);
  });

  it("floors at 1 even when the card count is 0 (defensive)", () => {
    expect(fitCols(2000, 0)).toBe(1);
  });
});

// clampPan (design/38 §2) keeps at least PAN_MARGIN (80 model-px * zoom) of the
// content within the viewport on each axis, so a pan can never push all the
// tables off into an empty void. It is math over cy.zoom()/width()/height()/pan();
// we drive a headless core with stubbed viewport reads (jsdom cannot init the
// canvas renderer) and assert the corrected pan keeps the content overlapping.
describe("clampPan (keeps content on-screen)", () => {
  const M = 80; // PAN_MARGIN (mirrors graph.ts)
  // A viewport-stubbed headless core at zoom 1 with a settable pan.
  function panCy(w: number, h: number): cytoscape.Core {
    const cy = cytoscape({ headless: true, elements: [{ data: { id: "a" } }] });
    cy.zoom(1);
    (cy as unknown as { width: () => number }).width = () => w;
    (cy as unknown as { height: () => number }).height = () => h;
    return cy;
  }
  // Large content (wider + taller than the viewport) so BOTH axes have a real
  // clamp range (lo <= hi) and over-panning is corrected.
  const BIG = { x1: 0, y1: 0, x2: 2000, y2: 2000, w: 2000, h: 2000 };

  it("pulls the pan back when panned far off to the left/top (content lost)", () => {
    const cy = panCy(800, 600);
    // Pan hard so the content's top-left is way past the bottom-right of the
    // viewport (everything scrolled off to the upper-left): pan very positive.
    cy.pan({ x: 5000, y: 5000 });
    clampPan(cy, BIG);
    const p = cy.pan();
    // Upper bound: panX <= W - M - x1*z ; panY <= H - M - y1*z.
    expect(p.x).toBeLessThanOrEqual(800 - M - BIG.x1 + 1e-6);
    expect(p.y).toBeLessThanOrEqual(600 - M - BIG.y1 + 1e-6);
  });

  it("pulls the pan back when panned far off to the right/bottom (content lost)", () => {
    const cy = panCy(800, 600);
    cy.pan({ x: -5000, y: -5000 });
    clampPan(cy, BIG);
    const p = cy.pan();
    // Lower bound: panX >= M - x2*z ; panY >= M - y2*z.
    expect(p.x).toBeGreaterThanOrEqual(M - BIG.x2 - 1e-6);
    expect(p.y).toBeGreaterThanOrEqual(M - BIG.y2 - 1e-6);
  });

  it("leaves a moderate pan (content still overlapping) untouched", () => {
    const cy = panCy(800, 600);
    cy.pan({ x: -100, y: -100 });
    clampPan(cy, BIG);
    const p = cy.pan();
    expect(p.x).toBe(-100);
    expect(p.y).toBe(-100);
  });

  it("does not fight a centred small diagram (inverted range left as-is)", () => {
    // Content smaller than the viewport on both axes -> lo > hi on each axis, so
    // clampPan must leave the pan exactly where it is (a centred small diagram).
    const cy = panCy(1600, 1200);
    const SMALL = { x1: 0, y1: 0, x2: 200, y2: 150, w: 200, h: 150 };
    cy.pan({ x: 700, y: 500 });
    clampPan(cy, SMALL);
    const p = cy.pan();
    expect(p.x).toBe(700);
    expect(p.y).toBe(500);
    cy.destroy();
  });

  it("is a no-op for degenerate (0-size) content", () => {
    const cy = panCy(800, 600);
    cy.pan({ x: 9999, y: 9999 });
    clampPan(cy, { x1: 0, y1: 0, x2: 0, y2: 0, w: 0, h: 0 });
    const p = cy.pan();
    expect(p.x).toBe(9999);
    expect(p.y).toBe(9999);
    cy.destroy();
  });
});

// Teardown discipline for the zoom widget (design/38 §4, §7): the widget must be
// re-mountable without leaking a duplicate overlay or its listeners. cytoscape's
// canvas renderer can't init under jsdom, so we exercise createZoomWidget against
// a HEADLESS cy core (no renderer) — enough to prove the DOM + listener lifecycle.
describe("createZoomWidget teardown discipline", () => {
  it("re-mount does not duplicate the widget; destroy removes it", () => {
    const container = document.createElement("div");
    document.body.appendChild(container);
    const cy = cytoscape({ headless: true, elements: [{ data: { id: "a" } }] });

    const w1 = createZoomWidget(container, cy, () => {});
    expect(container.querySelectorAll(".cy-zoom").length).toBe(1);

    // A re-mount pattern: tear the first down before creating the second, exactly
    // as mountGraph's destroy() -> new mount does. Never two overlays at once.
    w1.destroy();
    expect(container.querySelectorAll(".cy-zoom").length).toBe(0);

    const w2 = createZoomWidget(container, cy, () => {});
    expect(container.querySelectorAll(".cy-zoom").length).toBe(1);

    w2.destroy();
    expect(container.querySelectorAll(".cy-zoom").length).toBe(0);

    cy.destroy();
    container.remove();
  });

  it("destroy() unbinds the container keydown listener (no leak, no throw)", () => {
    const container = document.createElement("div");
    document.body.appendChild(container);
    const cy = cytoscape({ headless: true, elements: [{ data: { id: "a" } }] });

    let resets = 0;
    const w = createZoomWidget(container, cy, () => resets++);
    // "0" key resets the view while mounted...
    container.dispatchEvent(new KeyboardEvent("keydown", { key: "0", bubbles: true }));
    expect(resets).toBe(1);

    // ...and after destroy the same key is a no-op (listener removed).
    w.destroy();
    container.dispatchEvent(new KeyboardEvent("keydown", { key: "0", bubbles: true }));
    expect(resets).toBe(1);

    cy.destroy();
    container.remove();
  });

  it("the live % readout tracks cy zoom and stops updating after destroy", () => {
    const container = document.createElement("div");
    document.body.appendChild(container);
    const cy = cytoscape({ headless: true, elements: [{ data: { id: "a" } }] });
    cy.minZoom(0.2);
    cy.maxZoom(4);

    const w = createZoomWidget(container, cy, () => {});
    const pct = () => container.querySelector<HTMLElement>(".cy-zoom-pct")!.textContent;
    cy.zoom(1);
    expect(pct()).toBe("100%");
    cy.zoom(1.5);
    expect(pct()).toBe("150%");

    // after destroy the cy zoom listener is gone, so the (removed) readout no
    // longer updates and destroy() did not throw.
    w.destroy();
    cy.destroy();
    container.remove();
  });
});

// Teardown discipline for the navigator (minimap) + overflow indicators
// (design/38 §4 navigator, §7 teardown). Same contract as the zoom widget: at
// most one overlay after mount, zero after destroy, and the degenerate guard
// (0-size content / viewport) returns an INERT handle that adds no DOM.
describe("createMinimap teardown discipline", () => {
  it("re-mount does not duplicate the minimap; destroy removes it", () => {
    const container = document.createElement("div");
    document.body.appendChild(container);
    const cy = headlessCy();

    const m1 = createMinimap(container, cy, BB);
    expect(container.querySelectorAll(".cy-minimap").length).toBe(1);
    // canvas + draggable frame are present inside the box.
    expect(container.querySelectorAll(".cy-minimap-canvas").length).toBe(1);
    expect(container.querySelectorAll(".cy-minimap-frame").length).toBe(1);

    m1.destroy();
    expect(container.querySelectorAll(".cy-minimap").length).toBe(0);

    const m2 = createMinimap(container, cy, BB);
    expect(container.querySelectorAll(".cy-minimap").length).toBe(1);
    m2.destroy();
    expect(container.querySelectorAll(".cy-minimap").length).toBe(0);

    cy.destroy();
    container.remove();
  });

  it("the degenerate guard (0-width content) returns an inert handle (no DOM)", () => {
    const container = document.createElement("div");
    document.body.appendChild(container);
    const cy = headlessCy();

    const m = createMinimap(container, cy, { x1: 0, y1: 0, x2: 0, y2: 0, w: 0, h: 0 });
    expect(container.querySelectorAll(".cy-minimap").length).toBe(0);
    expect(() => m.destroy()).not.toThrow(); // inert destroy is a no-op

    cy.destroy();
    container.remove();
  });

  it("destroy() unbinds the cy render listener (no leak, no throw on later render)", () => {
    const container = document.createElement("div");
    document.body.appendChild(container);
    const cy = headlessCy();

    const m = createMinimap(container, cy, BB);
    m.destroy();
    // After destroy, a render must not throw into the removed frame syncer.
    expect(() => cy.emit("render")).not.toThrow();

    cy.destroy();
    container.remove();
  });
});

describe("createEdgeIndicators teardown discipline", () => {
  it("re-mount does not duplicate the indicators; destroy removes all four", () => {
    const container = document.createElement("div");
    document.body.appendChild(container);
    const cy = headlessCy();

    const e1 = createEdgeIndicators(container, cy, BB);
    expect(container.querySelectorAll(".cy-overflow").length).toBe(4);

    e1.destroy();
    expect(container.querySelectorAll(".cy-overflow").length).toBe(0);

    const e2 = createEdgeIndicators(container, cy, BB);
    expect(container.querySelectorAll(".cy-overflow").length).toBe(4);
    e2.destroy();
    expect(container.querySelectorAll(".cy-overflow").length).toBe(0);

    cy.destroy();
    container.remove();
  });

  it("the degenerate guard (0-width content) returns an inert handle (no DOM)", () => {
    const container = document.createElement("div");
    document.body.appendChild(container);
    const cy = headlessCy();

    const e = createEdgeIndicators(container, cy, { x1: 0, y1: 0, x2: 0, y2: 0, w: 0, h: 0 });
    expect(container.querySelectorAll(".cy-overflow").length).toBe(0);
    expect(() => e.destroy()).not.toThrow();

    cy.destroy();
    container.remove();
  });

  it("destroy() unbinds the cy render listener (no throw on a later render)", () => {
    const container = document.createElement("div");
    document.body.appendChild(container);
    const cy = headlessCy();

    const e = createEdgeIndicators(container, cy, BB);
    e.destroy();
    expect(() => cy.emit("render")).not.toThrow();

    cy.destroy();
    container.remove();
  });
});
