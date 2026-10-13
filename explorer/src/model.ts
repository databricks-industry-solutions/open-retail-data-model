export interface Column {
  name: string;
  type: string;
  pk: boolean;
  fk: boolean;
  pii: boolean;
  enum_values: string[];
  comment: string;
}

/**
 * A core table (and its owning domain) that another table consumes: a gold mview
 * reads it via SQL lineage, or an association/silver table reaches it via a
 * declared FK. See Table.consumes_tables.
 */
export interface ConsumesTable {
  table: string;
  unit: string;
}

export interface Table {
  name: string;
  comment: string;
  role: string;
  layer: "silver" | "gold";
  materialized: boolean;
  scd2: boolean;
  columns: Column[];
  /**
   * The core (silver) tables this table consumes, driving the L1 lineage reveal.
   * Populated for gold mviews (resolved transitively from their SQL FROM/JOIN
   * lineage, since gold carries no FK metadata) AND for association/silver tables
   * that reach core via a declared FK (e.g. promotion_scope). Absent or empty when
   * a table consumes no core table (e.g. a plain silver master).
   */
  consumes_tables?: ConsumesTable[];
}

export interface Relationship {
  child_table: string;
  child_cols: string[];
  parent_table: string;
  parent_cols: string[];
  declared_fk: boolean;
}

/** Planning-tier use-case status (per-package use-cases.yaml). */
export type UseCaseStatus = "blocked" | "in-progress" | "planned" | "done";

/** A gold table from another package serving this use case. */
export interface ForeignTable {
  /** Package (unit) that owns this gold table. */
  unit: string;
  /** Gold table name. */
  table: string;
}

export interface UseCase {
  name: string;
  status: UseCaseStatus;
  /**
   * Gold tables (in this unit) that serve this use case. Optional/[] when the
   * package has not authored a `tables:` mapping in use-cases.yaml. Drives the
   * L1 swimlane grouping + use-case hover highlight.
   */
  tables: string[];
  /**
   * Cross-package gold tables ({unit, table}) that serve this use case.
   * For example, a UCV use case might reference ACU's gold_customer_ltv.
   * Shown as linked/foreign cards in the explorer. Optional/[] when none.
   */
  foreign_tables?: ForeignTable[];
  /**
   * Core/silver domains this use case consumes, derived (not authored) by the
   * generator: the L0 `consumes` scoped to this use case's `tables`. Drives the
   * L1 use-case-hover chip-strip reveal. [] when nothing is derivable.
   */
  consumes: string[];
}

export interface Unit {
  name: string;
  kind: "core" | "outcome";
  tables: Table[];
  relationships: Relationship[];
  checks: any[];
  glossary_path: string | null;
  contract_path: string | null;
  /**
   * The unit's folder in the source repo on GitHub (absolute URL), rendered as the
   * panel's GitHub link. Not staged into the site, unlike glossary/contract.
   */
  source_url: string;
  /** Business use cases this package enables (planning tier); [] for core domains. */
  use_cases: UseCase[];
  /**
   * Other packages' use cases that THIS package's gold views serve (the reverse of
   * their `foreign_tables`), e.g. ACU's gold_customer_ltv serving UCV's Customer
   * Lifetime Value. Banded in this unit's L1 so those views are not "Not mapped".
   * Optional/[] when none (and absent on core domains).
   */
  external_use_cases?: ExternalUseCase[];
}

/** A use case of ANOTHER package served by some of this package's gold views. */
export interface ExternalUseCase {
  /** The package that declares the use case. */
  unit: string;
  name: string;
  status: UseCase["status"];
  /** This package's gold views it maps to. */
  tables: string[];
  /** Core domains those views consume. */
  consumes: string[];
}

export interface OverviewNode {
  id: string;
  label: string;
  kind: "core" | "outcome";
}

export interface OverviewEdge {
  source: string;
  target: string;
  kind: string;
}

export interface Model {
  generated_by: string;
  overview: {
    nodes: OverviewNode[];
    edges: OverviewEdge[];
  };
  units: Unit[];
}

// Cytoscape element types
export interface CyNode {
  data: {
    id: string;
    label: string;
    cls: "core" | "gold";
    [k: string]: any;
  };
}

export interface CyEdge {
  data: {
    id: string;
    source: string;
    target: string;
    [k: string]: any;
  };
}

export interface Elements {
  nodes: CyNode[];
  edges: CyEdge[];
}
