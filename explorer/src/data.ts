import type { Model, Unit, UseCase } from "./model";
export type { UseCase } from "./model";

/**
 * Derived view-model for the layered value-chain landing (the layered value-chain design).
 *
 * model.json carries no theme or status field, so both are derived here — the
 * single place that turns the raw model into the shape the overview renders.
 * This keeps the render code declarative and the derivation testable.
 */

export type Status = "built" | "in-progress" | "planned";

export interface PackageVM {
  name: string; // unit.name (slug)
  label: string; // human label
  status: Status;
  tableCount: number;
  pii: boolean;
  consumes: string[]; // core-domain unit names this package consumes
  useCases: UseCase[]; // planning-tier use cases (name + status), in manifest order
}

export interface DomainVM {
  name: string;
  label: string;
  tableCount: number;
  pii: boolean;
  role: string; // dominant role: master | transactional | reference
  consumedBy: string[]; // package names that consume this domain
}

export interface ThemeVM {
  title: string;
  packages: PackageVM[];
}

export interface DerivedModel {
  themes: ThemeVM[];
  domains: DomainVM[];
  /** flat lookup: unit name -> package view-model */
  packageByName: Map<string, PackageVM>;
  /** flat lookup: unit name -> domain view-model */
  domainByName: Map<string, DomainVM>;
  totals: {
    packages: number;
    themes: number;
    domains: number;
  };
}

/**
 * Theme -> package membership, taken verbatim from the layered value-chain design mockup, which
 * is the spec of record for the outcome map. Package slugs match unit.name in
 * model.json.
 */
const THEME_MAP: { title: string; packages: string[] }[] = [
  {
    title: "Respond & Predict to Customer Behavior",
    packages: [
      "unified-customer-view",
      "actionable-customer-understanding",
      "agentic-commerce",
      "commerce-media-networks",
    ],
  },
  {
    title: "Profitable Volume Growth",
    packages: ["balancing-margin-and-volume", "promote-with-purpose"],
  },
  {
    title: "Collaborative Supply Chain",
    packages: [
      "early-risk-detection",
      "smarter-demand-and-inventory-decisions",
      "data-sharing-with-suppliers",
    ],
  },
  {
    title: "Intelligent In-Store Experience",
    packages: [
      "connected-store-signals",
      "predictive-operations",
      "ai-assisted-store-associates",
    ],
  },
];

/**
 * Title of the fallback lane that renders any outcome package present in
 * model.json but absent from THEME_MAP (see deriveModel). Exported so the drift
 * test can assert a healthy model never populates it.
 */
export const UNTHEMED_LANE_TITLE = "Other outcome packages";

/** Turn a slug into a readable label ("unified-customer-view" -> "Unified Customer View"). */
export function humanize(slug: string): string {
  return slug
    .split(/[-_]/)
    .map((w) => (w.length ? w[0].toUpperCase() + w.slice(1) : w))
    .join(" ");
}

/**
 * Derive status from the ACTUAL generated model, not the mockup's illustrative
 * dots — so the badge can never drift from what model.json contains.
 *   planned      = no tables generated yet
 *   in-progress  = tables exist but no relationships wired
 *   built        = tables and relationships present
 *
 * IMPORTANT: this is a STRUCTURAL signal (does the unit have tables and wired
 * relationships in the DDL), NOT the Definition-of-Done maturity that STATUS.md
 * tracks. A package can read "built" here while STATUS.md still marks it 🟡 In
 * progress (metric views, docs-sync, and reviewer gates are DoD concerns this
 * badge does not measure). The two are independent axes; do not conflate them.
 */
export function deriveStatus(unit: Unit): Status {
  if (unit.tables.length === 0) return "planned";
  if (unit.relationships.length === 0) return "in-progress";
  return "built";
}

function tableCount(u: Unit): number {
  return u.tables.length;
}
function hasPii(u: Unit): boolean {
  return u.tables.some((t) => t.columns.some((c) => c.pii));
}
function dominantRole(u: Unit): string {
  const counts = new Map<string, number>();
  for (const t of u.tables) counts.set(t.role, (counts.get(t.role) ?? 0) + 1);
  let best = "";
  let bestN = -1;
  for (const [role, n] of counts) {
    if (n > bestN) {
      best = role;
      bestN = n;
    }
  }
  return best;
}

export function deriveModel(model: Model): DerivedModel {
  const unitByName = new Map(model.units.map((u) => [u.name, u]));

  // forward + reverse consumption maps from the overview `consumes` edges
  const consumes = new Map<string, string[]>(); // package -> [domain]
  const consumedBy = new Map<string, string[]>(); // domain -> [package]
  const pushInto = (m: Map<string, string[]>, key: string, value: string): void => {
    const arr = m.get(key);
    if (arr) arr.push(value);
    else m.set(key, [value]);
  };
  for (const e of model.overview.edges) {
    if (e.kind !== "consumes") continue;
    pushInto(consumes, e.source, e.target);
    pushInto(consumedBy, e.target, e.source);
  }

  const packageByName = new Map<string, PackageVM>();
  // Build (and register in packageByName) a package view-model from an outcome
  // unit, whether it is placed by a theme or falls through to the catch-all lane
  // below, so lookups and the package total see every outcome unit exactly once.
  const toPackageVM = (u: Unit): PackageVM => {
    const vm: PackageVM = {
      name: u.name,
      label: humanize(u.name),
      status: deriveStatus(u),
      tableCount: tableCount(u),
      pii: hasPii(u),
      consumes: (consumes.get(u.name) ?? []).slice().sort(),
      // Use cases stay in manifest order (the emitter preserves it) so the
      // planning narrative reads the way the package authors laid it out.
      useCases: u.use_cases ?? [],
    };
    packageByName.set(u.name, vm);
    return vm;
  };

  const themes: ThemeVM[] = THEME_MAP.map((t) => ({
    title: t.title,
    packages: t.packages
      .map((slug) => unitByName.get(slug))
      .filter((u): u is Unit => !!u)
      .map(toPackageVM),
  }));

  // Core domains, in the deterministic order they appear in model.json.
  const domainByName = new Map<string, DomainVM>();
  const domains: DomainVM[] = model.units
    .filter((u) => u.kind === "core")
    .map((u) => {
      const vm: DomainVM = {
        name: u.name,
        label: humanize(u.name),
        tableCount: tableCount(u),
        pii: hasPii(u),
        role: dominantRole(u),
        consumedBy: (consumedBy.get(u.name) ?? []).slice().sort(),
      };
      domainByName.set(u.name, vm);
      return vm;
    });

  // Catch-all: any outcome unit present in model.json but absent from the
  // hardcoded THEME_MAP would otherwise be silently dropped from the L0 gold lane,
  // the Matrix, and the "of N" total. Collect the stragglers so they still render
  // (under a clearly-labelled fallback lane) rather than vanishing without a trace
  // (contrast core domains, derived directly from model.units). THEME_MAP
  // completeness is ALSO enforced by test/data.test.ts (fails CI on drift) + the
  // dev warning below, but this repo has no branch protection so a red test can
  // still be merged: this lane is the production safety net of last resort. In a
  // healthy model it is empty and no lane is added.
  const unthemedOutcomes = model.units.filter(
    (u) => u.kind === "outcome" && !packageByName.has(u.name)
  );

  // Dev-only heads-up so the fallback is noticed during development rather than a
  // package quietly landing under "Other". Never reaches end users.
  if ((import.meta as { env?: { DEV?: boolean } }).env?.DEV && unthemedOutcomes.length > 0) {
    console.warn(
      `deriveModel: outcome unit(s) missing from THEME_MAP, shown under ` +
        `"${UNTHEMED_LANE_TITLE}": ${unthemedOutcomes.map((u) => u.name).join(", ")}. ` +
        `Add them to THEME_MAP in data.ts to place them under the right theme.`
    );
  }

  if (unthemedOutcomes.length > 0) {
    themes.push({ title: UNTHEMED_LANE_TITLE, packages: unthemedOutcomes.map(toPackageVM) });
  }

  const allPackages = [...packageByName.values()];

  return {
    themes,
    domains,
    packageByName,
    domainByName,
    totals: {
      packages: allPackages.length,
      themes: themes.length,
      domains: domains.length,
    },
  };
}
