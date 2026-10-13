import { getItem, setItem } from "./storage";

const STORAGE_KEY = "ordm-explorer-theme";

function getPrefersDark(): boolean {
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}

function getPrefersReducedMotion(): boolean {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

function applyTheme(dark: boolean): void {
  const html = document.documentElement;
  if (dark) {
    html.classList.add("theme-dark");
  } else {
    html.classList.remove("theme-dark");
  }
}

/**
 * Initialize theme toggle.
 * - Reads persisted preference from localStorage; falls back to OS preference.
 * - Injects a theme-toggle button into #toolbar.
 * - Persists changes to localStorage.
 * - Adds no transition when the user prefers reduced motion.
 */
// `onChange` is invoked after EVERY theme flip (button click OR OS-preference
// change), so the caller can re-colour anything CSS variables alone cannot reach -
// notably the cytoscape-painted graph/ER edges, which read `--edge-color` once at
// paint time and need an explicit refreshTheme(). Wiring it here (rather than a
// second click listener in main.ts) keeps the OS-change path covered too.
export function initTheme(onChange?: () => void): () => void {
  const stored = getItem(STORAGE_KEY);
  const reducedMotion = getPrefersReducedMotion();

  let dark: boolean;
  if (stored !== null) {
    dark = stored === "dark";
  } else {
    dark = getPrefersDark();
  }

  applyTheme(dark);

  // Create button and insert into toolbar
  const toolbar = document.getElementById("toolbar");
  if (!toolbar) return () => {};

  // Set the color transition only AFTER the toolbar guard, so the early-return
  // path never leaves an inline <html> transition the no-op teardown would leak
  // (the integration suite re-mounts onto the same jsdom window). The initial
  // applyTheme above is intentionally untransitioned (no flash on load); the
  // teardown below clears this.
  if (!reducedMotion) {
    document.documentElement.style.transition = "background 0.2s, color 0.2s";
  }

  const btn = document.createElement("button");
  btn.id = "theme-toggle";
  btn.title = "Toggle light/dark theme";
  btn.setAttribute("aria-pressed", String(dark));
  btn.textContent = dark ? "☀ Light" : "🌙 Dark";

  btn.addEventListener("click", () => {
    dark = !dark;
    applyTheme(dark);
    setItem(STORAGE_KEY, dark ? "dark" : "light");
    btn.textContent = dark ? "☀ Light" : "🌙 Dark";
    btn.setAttribute("aria-pressed", String(dark));
    onChange?.();
  });

  toolbar.appendChild(btn);

  // Also respond to OS changes (if user hasn't overridden)
  const mql = window.matchMedia("(prefers-color-scheme: dark)");
  const onOsChange = (e: MediaQueryListEvent): void => {
    if (getItem(STORAGE_KEY) === null) {
      dark = e.matches;
      applyTheme(dark);
      btn.textContent = dark ? "☀ Light" : "🌙 Dark";
      btn.setAttribute("aria-pressed", String(dark));
      onChange?.(); // recolour graph edges too, not just the CSS background (M1)
    }
  };
  mql.addEventListener("change", onOsChange);

  // Teardown: remove the OS-change listener AND the inline transition this set on
  // <html>, so the app can be cleanly re-mounted (integration tests re-mount onto
  // the same jsdom window) without leaving state behind.
  return () => {
    mql.removeEventListener("change", onOsChange);
    document.documentElement.style.transition = "";
  };
}
