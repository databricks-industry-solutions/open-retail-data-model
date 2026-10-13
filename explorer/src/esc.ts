/**
 * Shared escaping utilities for safe HTML insertion.
 *
 * Centralises the previously-duplicated `esc()` helpers in cards.ts and panel.ts
 * and adds single-quote encoding + URL-scheme validation (M4).
 */

/**
 * Encode the five HTML-special characters so the result is safe in both
 * double- and single-quoted attribute values as well as element text.
 * Handles non-string input defensively: null/undefined → ""; other types
 * are coerced via String().
 */
export function escapeHtml(s: string): string {
  if (s == null) return "";
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * Validate a URL for use in an `href` attribute.
 *
 * Rules:
 * - null / undefined / empty → "#"
 * - any control character (0x00–0x1f) ANYWHERE in the raw input → "#"
 * - schemeless / relative paths → pass through as-is
 * - http: or https: scheme → pass through as-is
 * - any other scheme (javascript:, data:, vbscript:, …) → "#"
 *
 * Scheme detection: trim, lower-case, test for `^[a-z][a-z0-9+.-]*:`
 */
export function safeHref(url: string | null | undefined): string {
  if (url == null || url === "") return "#";

  // Reject any control character (0x00–0x1f) anywhere in the raw input.
  // trim() only strips leading/trailing whitespace, so an embedded \t/\n/\r
  // wedged mid-scheme (e.g. "java\tscript:") would otherwise slip past the
  // scheme test and reach href, where the browser strips it and executes the
  // smuggled scheme. Check BEFORE the scheme test on the untrimmed input.
  // eslint-disable-next-line no-control-regex
  if (/[\x00-\x1f]/.test(url)) return "#";

  const trimmed = url.trim().toLowerCase();

  // Detect whether this looks like a URL with a scheme
  const schemeMatch = /^([a-z][a-z0-9+.-]*):/.exec(trimmed);
  if (schemeMatch) {
    const scheme = schemeMatch[1];
    if (scheme !== "http" && scheme !== "https") return "#";
  }
  // No scheme matched → relative path, allow as-is
  return url;
}
