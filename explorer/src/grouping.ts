import type { ExternalUseCase, Unit, UseCase } from "./model";

/**
 * L1 use-case grouping (pure, testable).
 *
 * The per-unit ER groups a package's gold tables into SWIMLANE BANDS by use case
 * (design/37). This module owns the pure partition; graph.ts owns the cytoscape
 * layout + overlay that renders it.
 *
 * Rules (per design/37):
 *  - One band per use case that has >=1 gold table in its `tables:` mapping, in
 *    manifest order.
 *  - A gold table serving several use cases is placed ONCE, in its PRIMARY (first,
 *    manifest-order) band; the other bands merely reference it for hover-highlight.
 *  - Gold tables in no use case collect into a trailing "Unassigned" band.
 *  - Non-gold tables (silver ingredients — rare at L1) stay UNGROUPED (drawn above
 *    the bands, not in any use case).
 *  - A package with no `tables:` mapping (or whose every gold table is unassigned)
 *    yields no real use-case bands, so the caller falls back to today's flat masonry.
 */

/**
 * The label for the trailing band that collects gold tables in no use case.
 * Phrased as an intent ("Not mapped to a use case") rather than the opaque
 * "Unassigned", so the reader understands it is a catch-all for gold tables the
 * first-pass `tables:` draft did not yet assign, not a real use case. The band
 * also carries a fuller one-line caption + a muted catch-all visual (graph.ts /
 * styles.css). This constant is the band's identity AND its rendered label.
 */
export const UNASSIGNED_BAND = "Not mapped to a use case";

/**
 * Band name (identity AND label) for another package's use case served by this
 * unit's gold views: "<use case> (<package>)", so it can never collide with a
 * local use case of the same name.
 */
export function externalBandName(e: Pick<ExternalUseCase, "name" | "unit">): string {
  return `${e.name} (${e.unit})`;
}

export interface Band {
  /** Use-case name, or UNASSIGNED_BAND for the catch-all. */
  name: string;
  /** Set when the use case belongs to another package (see externalBandName). */
  externalUnit?: string;
  /** Use-case status, or null for the Unassigned band. */
  status: UseCase["status"] | null;
  /** Tables DRAWN in this band (a shared table is drawn only in its primary band). */
  tables: string[];
  /**
   * All member tables of this use case (including ones drawn in another, earlier
   * band because this band is not their primary). Drives hover-highlight so a
   * shared table lights up under every use case it belongs to. Empty for Unassigned.
   */
  members: string[];
  /** Core/silver domains this use case consumes (derived; [] for Unassigned). */
  consumes: string[];
}

export interface Grouping {
  /** Non-gold tables that sit above the bands, ungrouped. */
  ungrouped: string[];
  /** Use-case bands (+ a trailing Unassigned band iff it has any tables). */
  bands: Band[];
  /**
   * True when there is nothing meaningful to group (no use case owns a gold
   * table), so the caller should fall back to today's flat masonry.
   */
  fallback: boolean;
  /**
   * table name -> number of use cases whose (filtered) members include it. 1 for
   * a solo table, >1 for a table shared across use cases. Drives the at-rest
   * "shared xN" card chip; the card is still DRAWN once (in its primary band).
   */
  sharedCount: Record<string, number>;
  /**
   * table name -> ordered list of use-case names that include it. Feeds the
   * shared chip's native `title` (the "Also in:" tooltip). EVERY table in any use
   * case carries an entry (a solo table lists its one use case); the shared chip
   * is only rendered when the list has more than one name.
   */
  sharedWith: Record<string, string[]>;
}

/**
 * Partition a unit's tables into use-case swimlane bands.
 *
 * `tableNames`/`goldNames` are derived from the unit's tables so the function is
 * pure over its input and easy to unit-test with a fixture.
 */
export function groupTablesByUseCase(unit: Unit): Grouping {
  const goldNames: string[] = [];
  const nonGold: string[] = [];
  for (const t of unit.tables) {
    (t.layer === "gold" ? goldNames : nonGold).push(t.name);
  }
  const goldSet = new Set(goldNames);
  const useCases: UseCase[] = unit.use_cases ?? [];

  // Which gold tables each use case owns, filtered to tables that actually exist
  // as gold in this unit (the generator validates this, but stay defensive).
  const placed = new Set<string>(); // gold tables already drawn in an earlier band
  const bands: Band[] = [];
  // sharedCount[t] = # of use cases whose (filtered) members include t. A table
  // in >1 use case is "shared" and earns an at-rest chip; a solo table stays 1.
  // sharedWith[t] lists those use-case names (in manifest order) for the tooltip.
  const sharedCount: Record<string, number> = {};
  const sharedWith: Record<string, string[]> = {};
  for (const uc of useCases) {
    // Dedupe within a use case's own list: a table listed twice would otherwise
    // double-count sharedCount/sharedWith and render a false "shared x2" chip
    // naming the same use case twice (the generator validates names, not repeats).
    const members = [...new Set((uc.tables ?? []).filter((t) => goldSet.has(t)))];
    for (const t of members) {
      sharedCount[t] = (sharedCount[t] ?? 0) + 1;
      (sharedWith[t] ??= []).push(uc.name);
    }
    if (members.length === 0) continue; // a use case with no gold tables gets no band
    // Draw a shared table only in its PRIMARY (first) band.
    const drawn = members.filter((t) => !placed.has(t));
    drawn.forEach((t) => placed.add(t));
    bands.push({
      name: uc.name,
      status: uc.status,
      tables: drawn,
      members,
      consumes: (uc.consumes ?? []).slice(),
    });
  }

  // Other packages' use cases served by this unit's gold views band AFTER the local
  // ones, with the same primary-band and shared-chip rules (a view already drawn in a
  // local band is only referenced here).
  for (const e of unit.external_use_cases ?? []) {
    const name = externalBandName(e);
    const members = [...new Set((e.tables ?? []).filter((t) => goldSet.has(t)))];
    for (const t of members) {
      sharedCount[t] = (sharedCount[t] ?? 0) + 1;
      (sharedWith[t] ??= []).push(name);
    }
    if (members.length === 0) continue;
    const drawn = members.filter((t) => !placed.has(t));
    drawn.forEach((t) => placed.add(t));
    bands.push({
      name,
      externalUnit: e.unit,
      status: e.status,
      tables: drawn,
      members,
      consumes: (e.consumes ?? []).slice(),
    });
  }

  // Gold tables owned by no use-case band -> trailing "Unassigned" band.
  const unassigned = goldNames.filter((t) => !placed.has(t));
  if (unassigned.length > 0) {
    bands.push({
      name: UNASSIGNED_BAND,
      status: null,
      tables: unassigned,
      members: unassigned.slice(),
      consumes: [],
    });
  }

  // Fallback when no use case owns a gold table (nothing meaningful to band):
  // the only band would be Unassigned (or none), so render the flat masonry.
  const hasRealBand = bands.some((b) => b.name !== UNASSIGNED_BAND);

  return { ungrouped: nonGold, bands, fallback: !hasRealBand, sharedCount, sharedWith };
}
