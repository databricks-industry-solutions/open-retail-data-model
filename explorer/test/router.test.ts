import { describe, it, expect, beforeEach } from "vitest";
import { parseHash, toHash, parentState, Router, type RouteState } from "../src/router";

/** Poll until `cond` is true (jsdom updates hash + fires popstate async). */
async function waitFor(cond: () => boolean, timeout = 1000): Promise<void> {
  const start = Date.now();
  while (!cond()) {
    if (Date.now() - start > timeout) throw new Error("waitFor timed out");
    await new Promise((r) => setTimeout(r, 5));
  }
}

describe("hash grammar round-trip", () => {
  const cases: RouteState[] = [
    { view: "overview" },
    { view: "matrix" },
    { view: "graph" },
    { view: "overview", theme: "Profitable Volume Growth" },
    { view: "overview", unit: "customer" },
    { view: "overview", unit: "customer", table: "profile" },
  ];
  for (const st of cases) {
    it(`toHash -> parseHash preserves ${JSON.stringify(st)}`, () => {
      expect(parseHash(toHash(st))).toEqual(st);
    });
  }

  it("empty hash parses to overview", () => {
    expect(parseHash("")).toEqual({ view: "overview" });
    expect(parseHash("#/")).toEqual({ view: "overview" });
  });

  it("decodes url-encoded theme/unit segments", () => {
    const h = toHash({ view: "overview", theme: "A & B" });
    expect(parseHash(h).theme).toBe("A & B");
  });

  it("survives a MALFORMED escape without throwing (M1: shared-link safety)", () => {
    // A hand-edited / truncated shared link has an invalid % escape; parseHash runs
    // on first paint, so it must NOT throw URIError (which would white-screen the
    // app). It falls back to the raw segment.
    expect(() => parseHash("#/theme/%")).not.toThrow();
    expect(parseHash("#/theme/%")).toEqual({ view: "overview", theme: "%" });
    expect(() => parseHash("#/u/foo%E2")).not.toThrow();
    expect(parseHash("#/u/foo%E2")).toEqual({ view: "overview", unit: "foo%E2" });
    expect(() => parseHash("#/u/customer/tbl%")).not.toThrow();
    expect(parseHash("#/u/customer/tbl%").table).toBe("tbl%");
  });

  // Confirmed bug: a fresh load of `#/u/<unit>/<table>` used to drop the third
  // segment, rewriting the hash to `#/u/<unit>` and opening only L1. The grammar
  // must PARSE and PRESERVE the bare third segment as the table, and serialize it
  // back round-trip so a shared L2 deep-link survives normalization.
  it("preserves the L2 table on a fresh `#/u/<unit>/<table>` deep-link", () => {
    const st = parseHash("#/u/early-risk-detection/disruption_alert");
    expect(st).toEqual({
      view: "overview",
      unit: "early-risk-detection",
      table: "disruption_alert",
    });
    // round-trips through serialize -> parse (so router.replace(initial) keeps it).
    expect(parseHash(toHash(st))).toEqual(st);
    // serializes to the shorter bare-third-segment form.
    expect(toHash(st)).toBe("#/u/early-risk-detection/disruption_alert");
  });

  it("still parses the legacy `#/u/<unit>/t/<table>` form (back-compat)", () => {
    expect(parseHash("#/u/customer/t/profile")).toEqual({
      view: "overview",
      unit: "customer",
      table: "profile",
    });
  });
});

describe("parentState (step-up ladder)", () => {
  it("L2 table -> L1 unit", () => {
    expect(parentState({ view: "overview", unit: "customer", table: "profile" })).toEqual({
      view: "overview",
      unit: "customer",
    });
  });
  it("L1 unit -> L0 overview (unit routes carry no theme, so it lands on plain L0)", () => {
    // The hash grammar has no theme slot on a unit route and onUnit never passes
    // one, so a real unit state is never themed; stepping up lands on plain L0.
    expect(parentState({ view: "overview", unit: "customer" })).toEqual({ view: "overview" });
  });
  it("matrix/graph -> overview", () => {
    expect(parentState({ view: "matrix" })).toEqual({ view: "overview" });
    expect(parentState({ view: "graph" })).toEqual({ view: "overview" });
  });
  it("themed overview -> plain overview", () => {
    expect(parentState({ view: "overview", theme: "X" })).toEqual({ view: "overview" });
  });
  it("plain overview -> null (already at top)", () => {
    expect(parentState({ view: "overview" })).toBeNull();
  });
});

describe("Router history integration (jsdom)", () => {
  beforeEach(() => {
    window.location.hash = "";
  });

  it("go() pushes a history entry and popstate restores the prior state", async () => {
    const seen: RouteState[] = [];
    const router = new Router();
    router.onChange((s) => seen.push(s));

    router.replace({ view: "overview" });
    const startLen = history.length;

    router.go({ view: "overview", unit: "customer" });
    expect(window.location.hash).toBe("#/u/customer");
    expect(history.length).toBe(startLen + 1); // a real history entry was added

    // browser Back — jsdom updates the hash + fires popstate asynchronously,
    // so poll until the hash has actually rolled back.
    history.back();
    await waitFor(() => window.location.hash === "#/" || window.location.hash === "");

    expect(router.current()).toEqual({ view: "overview" });
    // the router emitted the restored (overview) state on popstate
    expect(seen[seen.length - 1]).toEqual({ view: "overview" });
  });
});

describe("emit() dedupe (M2: a fragment-changing back fires popstate AND hashchange)", () => {
  it("renders once per distinct hash, skipping a repeat of the current hash", () => {
    const r = new Router();
    r.destroy(); // drop the window listeners so set-hash side effects don't interfere
    let calls = 0;
    r.onChange(() => (calls += 1));

    window.location.hash = "#/u/customer";
    r.emit(); // hash != lastHash -> renders
    r.emit(); // same hash (the second of the popstate+hashchange pair) -> deduped
    expect(calls).toBe(1);

    window.location.hash = "#/u/store";
    r.emit(); // a genuinely new hash -> renders again
    r.emit();
    expect(calls).toBe(2);
  });
});

describe("Router.stepUp (M2: pop when the parent is the previous entry, else push)", () => {
  beforeEach(() => {
    window.location.hash = "";
  });

  it("POPs to the parent when it is the immediate previous entry (no stack growth)", async () => {
    const router = new Router();
    router.replace({ view: "overview" }); // entry A: #/
    router.go({ view: "overview", unit: "customer" }); // entry B: #/u/customer, __from = #/
    expect(window.location.hash).toBe("#/u/customer");
    const lenAtChild = history.length;

    // The parent (#/) equals entry B's recorded __from, so stepUp walks BACK via
    // history.back() rather than pushing a duplicate overview entry - which keeps
    // the stack from growing and leaves the browser Forward button working.
    router.stepUp({ view: "overview" });
    await waitFor(() => window.location.hash === "#/" || window.location.hash === "");
    expect(router.current()).toEqual({ view: "overview" });
    expect(history.length).toBe(lenAtChild); // popped, not pushed
    router.destroy();
  });

  it("PUSHes when nothing behind us matches the parent (fresh deep-link)", () => {
    const router = new Router();
    // A deep-linked L2 entry, normalised with replace(): it carries no __from, so
    // there is no in-app parent to pop back to and stepUp must push instead.
    router.replace({ view: "overview", unit: "customer", table: "profile" });
    const lenBefore = history.length;

    router.stepUp({ view: "overview", unit: "customer" });
    expect(window.location.hash).toBe("#/u/customer");
    expect(history.length).toBe(lenBefore + 1); // pushed a fresh entry
    router.destroy();
  });
});
