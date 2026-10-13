/**
 * Vitest setup: polyfill browser APIs jsdom does not implement.
 *
 * jsdom ships no `window.matchMedia`, which theme.ts uses to read the OS
 * light/dark + reduced-motion preference. This is a standard jsdom shim — it
 * does not stub any app behaviour under test, only the missing platform API.
 */
if (typeof window !== "undefined" && typeof window.matchMedia !== "function") {
  // A minimal, mutable matchMedia. Tests that care about the OS preference can
  // override window.matchMedia; by default it reports "no preference".
  window.matchMedia = ((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addEventListener: () => {},
    removeEventListener: () => {},
    addListener: () => {},
    removeListener: () => {},
    dispatchEvent: () => false,
  })) as unknown as typeof window.matchMedia;
}
