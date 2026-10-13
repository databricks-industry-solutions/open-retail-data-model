/**
 * Defensive localStorage wrapper.
 *
 * localStorage can be absent or throw: private-browsing modes, sandboxed
 * iframes, and some test runners (jsdom without a concrete origin) expose it as
 * a partial `{}` with no methods. The app must degrade gracefully — a missing
 * store just means "no persisted preference", never a crash. These helpers
 * swallow any access error and fall back to in-memory for the session.
 */

const memory = new Map<string, string>();

function ls(): Storage | null {
  try {
    const s = globalThis.localStorage;
    if (s && typeof s.getItem === "function" && typeof s.setItem === "function") {
      return s;
    }
  } catch {
    /* access can throw (SecurityError) */
  }
  return null;
}

export function getItem(key: string): string | null {
  // Prefer the in-memory value when we hold one: setItem always writes memory but
  // the real-store write can silently fail (Safari private mode / quota 0). If we
  // read the store first there, we would return a stale/absent value and lose the
  // preference the user just set this session. Memory is empty on a fresh load, so
  // a genuinely persisted value from a prior session is still read from the store.
  if (memory.has(key)) return memory.get(key)!;
  const s = ls();
  if (s) {
    try {
      return s.getItem(key);
    } catch {
      /* fall through */
    }
  }
  return null;
}

export function setItem(key: string, value: string): void {
  memory.set(key, value);
  const s = ls();
  if (s) {
    try {
      s.setItem(key, value);
    } catch {
      /* memory already updated */
    }
  }
}

/** Clear both the in-memory fallback and the real store (used by tests). */
export function clearAll(): void {
  memory.clear();
  const s = ls();
  if (s) {
    try {
      s.clear();
    } catch {
      /* ignore */
    }
  }
}
