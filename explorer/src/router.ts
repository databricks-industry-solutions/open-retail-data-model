/**
 * Deep-linkable URL-hash router for the Explorer's progressive-disclosure levels.
 *
 * Fixes the shipped "no back after drilling in" bug: every navigation is pushed
 * to browser history, so the browser Back button works, ESC steps up a level,
 * and any state is a shareable link. State lives entirely in `location.hash`.
 *
 * Hash grammar:
 *   #/                     L0 overview (layers view)
 *   #/theme/<slug>         L0 overview, filtered to one theme
 *   #/matrix               matrix view
 *   #/graph                force-directed graph view
 *   #/u/<unit>             L1 package/domain detail (ER of that unit)
 *   #/u/<unit>/<table>     L2 table selected (ER side panel open). The legacy
 *                          `#/u/<unit>/t/<table>` form is still parsed (so old
 *                          shared links keep working) but new links serialize to
 *                          the shorter bare-third-segment form.
 */

export type View = "overview" | "matrix" | "graph";

export interface RouteState {
  view: View;
  theme?: string; // active theme filter on the overview
  unit?: string; // drilled-into unit (L1)
  table?: string; // selected table (L2)
}

// decodeURIComponent throws URIError on a malformed escape (a hand-edited or
// truncated shared link like `#/theme/%` or `#/u/foo%E2`). parseHash runs on the
// very first paint (mountApp -> router.current()), so an unguarded throw would
// white-screen the whole deep-linkable app. Fall back to the raw segment (M1).
function safeDecode(s: string): string {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}

export function parseHash(hash: string): RouteState {
  // strip leading "#", "#/", "/"
  let h = hash.replace(/^#/, "");
  h = h.replace(/^\//, "");
  const parts = h.split("/").filter(Boolean);

  if (parts.length === 0) return { view: "overview" };

  if (parts[0] === "matrix") return { view: "matrix" };
  if (parts[0] === "graph") return { view: "graph" };
  if (parts[0] === "theme" && parts[1]) {
    return { view: "overview", theme: safeDecode(parts[1]) };
  }
  if (parts[0] === "u" && parts[1]) {
    const st: RouteState = { view: "overview", unit: safeDecode(parts[1]) };
    // Bare third segment IS the table (`#/u/<unit>/<table>`), so a fresh deep-link
    // preserves L2 instead of dropping it (the confirmed "deep-link to L2 drops the
    // table" bug). The legacy `#/u/<unit>/t/<table>` form is still accepted.
    if (parts[2] === "t" && parts[3]) st.table = safeDecode(parts[3]);
    else if (parts[2]) st.table = safeDecode(parts[2]);
    return st;
  }
  return { view: "overview" };
}

export function toHash(state: RouteState): string {
  if (state.view === "matrix") return "#/matrix";
  if (state.view === "graph") return "#/graph";
  if (state.unit) {
    let h = `#/u/${encodeURIComponent(state.unit)}`;
    // Serialize the table as the bare third segment so a shared L2 link round-trips
    // (parseHash preserves it). The old `/t/<table>` marker is dropped from output
    // but still parsed for back-compat.
    if (state.table) h += `/${encodeURIComponent(state.table)}`;
    return h;
  }
  if (state.theme) return `#/theme/${encodeURIComponent(state.theme)}`;
  return "#/";
}

/**
 * The "step up one level" target for ESC / a single Back — L2 table -> L1 unit
 * -> L0 overview. Returns null when already at the top.
 */
export function parentState(state: RouteState): RouteState | null {
  if (state.table) return { view: "overview", unit: state.unit };
  // A unit route never carries a theme (the hash grammar has no slot for it and
  // onUnit does not pass one), so stepping up from L1 lands on the unfiltered L0.
  if (state.unit) return { view: "overview" };
  if (state.view !== "overview") return { view: "overview" };
  if (state.theme) return { view: "overview" };
  return null;
}

export class Router {
  private handler: (s: RouteState) => void = () => {};
  // The last hash we rendered for. A single browser back/forward that changes the
  // fragment fires BOTH popstate AND hashchange (per the HTML spec), which used to
  // render twice (redundant tearDown + rebuild + mountCy). Deduping on this makes
  // the second event a no-op. (The old `applying` guard did nothing: neither
  // pushState nor replaceState emits hashchange, so it never suppressed anything.)
  private lastHash: string | null = null;
  private readonly onPop = (): void => this.emit();
  private readonly onHash = (): void => this.emit();

  constructor() {
    window.addEventListener("popstate", this.onPop);
    window.addEventListener("hashchange", this.onHash);
  }

  /** Remove the window listeners so the app can be cleanly re-mounted. */
  destroy(): void {
    window.removeEventListener("popstate", this.onPop);
    window.removeEventListener("hashchange", this.onHash);
  }

  onChange(fn: (s: RouteState) => void): void {
    this.handler = fn;
  }

  /** Current state parsed from the live hash. */
  current(): RouteState {
    return parseHash(window.location.hash);
  }

  /** Navigate, pushing a new history entry (browser Back returns to prior). */
  go(state: RouteState): void {
    const hash = toHash(state);
    if (hash === window.location.hash || (hash === "#/" && window.location.hash === "")) {
      // Same location — still notify so a re-render happens, but don't stack
      // an identical history entry.
      this.lastHash = window.location.hash;
      this.handler(state);
      return;
    }
    // Stamp the entry we are LEAVING onto the new one so stepUp() can tell whether a
    // browser Back would land exactly on a given parent (pop) or not (push).
    const from = window.location.hash || "#/";
    history.pushState({ ...state, __from: from }, "", hash); // does not fire popstate/hashchange
    this.lastHash = hash;
    this.handler(state);
  }

  /**
   * Navigate UP to `parent`. If a browser Back would land exactly on `parent` (the
   * normal drill-down case: the entry we came from IS the parent), POP instead of
   * pushing - that keeps repeated in-app Back from growing the history stack and
   * preserves the browser Forward button. Otherwise (a fresh deep-link with nothing
   * behind us, or the previous entry is a sibling / other view, not the parent) fall
   * back to a normal push, exactly as before.
   */
  stepUp(parent: RouteState): void {
    const from = (history.state as { __from?: string } | null)?.__from;
    if (from != null && from === toHash(parent)) {
      history.back(); // fires popstate -> emit() re-renders `parent` (same path as browser Back)
    } else {
      this.go(parent);
    }
  }

  /** Replace the current entry (used to normalise the initial URL). */
  replace(state: RouteState): void {
    history.replaceState(state, "", toHash(state));
    this.lastHash = window.location.hash;
  }

  /** Fire the handler for the current hash (initial load / popstate / hashchange),
   *  deduped so a fragment-changing back/forward renders only once. */
  emit(): void {
    const h = window.location.hash;
    if (h === this.lastHash) return;
    this.lastHash = h;
    this.handler(this.current());
  }
}
