import { describe, it, expect } from "vitest";
import { escapeHtml, safeHref } from "../src/esc";

describe("escapeHtml()", () => {
  it("encodes all five special characters: & < > \" '", () => {
    expect(escapeHtml("& < > \" '")).toBe("&amp; &lt; &gt; &quot; &#39;");
  });

  it("blocks a <script> injection sample", () => {
    const input = `<script>alert('xss')</script>`;
    const out = escapeHtml(input);
    expect(out).not.toContain("<");
    expect(out).not.toContain(">");
    expect(out).not.toContain("'");
    expect(out).toContain("&lt;script&gt;");
    expect(out).toContain("&#39;xss&#39;");
  });

  it("returns empty string for non-string falsy input", () => {
    // @ts-expect-error testing runtime defensive coercion
    expect(escapeHtml(null)).toBe("");
    // @ts-expect-error testing runtime defensive coercion
    expect(escapeHtml(undefined)).toBe("");
  });

  it("coerces numbers to string before escaping", () => {
    // @ts-expect-error testing runtime coercion
    expect(escapeHtml(42)).toBe("42");
  });

  it("leaves plain text unchanged", () => {
    expect(escapeHtml("hello world")).toBe("hello world");
  });
});

describe("safeHref()", () => {
  it("passes a relative path through unchanged", () => {
    const rel = "contracts/odcs/customer.odcs.yaml";
    expect(safeHref(rel)).toBe(rel);
  });

  it("passes an https:// URL through unchanged", () => {
    const url = "https://example.com/glossary?q=foo";
    expect(safeHref(url)).toBe(url);
  });

  it("passes an http:// URL through unchanged", () => {
    const url = "http://localhost:8080/docs";
    expect(safeHref(url)).toBe(url);
  });

  it("rejects javascript: scheme → returns '#'", () => {
    expect(safeHref("javascript:alert(1)")).toBe("#");
  });

  it("rejects javascript: scheme with mixed case → returns '#'", () => {
    expect(safeHref("JavaScript:alert(1)")).toBe("#");
  });

  it("rejects data: scheme → returns '#'", () => {
    expect(safeHref("data:text/html,<h1>xss</h1>")).toBe("#");
  });

  it("rejects vbscript: scheme → returns '#'", () => {
    expect(safeHref("vbscript:msgbox(1)")).toBe("#");
  });

  it("returns '#' for null input", () => {
    expect(safeHref(null)).toBe("#");
  });

  it("returns '#' for undefined input", () => {
    expect(safeHref(undefined)).toBe("#");
  });

  it("returns '#' for empty string", () => {
    expect(safeHref("")).toBe("#");
  });

  it("returns '#' for strings starting with control chars", () => {
    expect(safeHref("\x00javascript:evil")).toBe("#");
  });

  // ---- H1: control characters embedded *anywhere* must be rejected ----
  // trim() strips only leading/trailing whitespace, so a tab/newline/CR
  // wedged mid-scheme (e.g. "java\tscript:") slips past the scheme regex.
  // Browsers strip the control char and execute the smuggled scheme, so
  // any control char anywhere in the raw input must reject to "#".
  it("rejects an embedded tab in the scheme (java\\tscript:)", () => {
    expect(safeHref("java\tscript:alert(1)")).toBe("#");
  });

  it("rejects an embedded newline in the scheme (java\\nscript:)", () => {
    expect(safeHref("java\nscript:alert(1)")).toBe("#");
  });

  it("rejects an embedded carriage return in the scheme (java\\rscript:)", () => {
    expect(safeHref("java\rscript:alert(1)")).toBe("#");
  });

  it("rejects a control char embedded anywhere (not just the scheme)", () => {
    expect(safeHref("https://ok\x07.example.com")).toBe("#");
  });
});
