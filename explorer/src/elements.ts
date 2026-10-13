import type { Model, Elements, CyNode, CyEdge } from "./model";
import { groupTablesByUseCase } from "./grouping";

/**
 * Transform a Model object into Cytoscape-ready node/edge arrays.
 *
 * @param model    The parsed model.json object.
 * @param level    "overview" — one node per unit, edges from model.overview.edges.
 *                 "unit"     — one node per table inside `unitName`, edges from relationships.
 * @param unitName Required when level === "unit". The unit's name field.
 */
export function modelToElements(
  model: Model,
  level: "overview" | "unit",
  unitName?: string
): Elements {
  if (level === "overview") {
    const nodes: CyNode[] = model.overview.nodes.map((n) => ({
      data: {
        id: n.id,
        label: n.label,
        kind: n.kind,
        cls: n.kind === "core" ? "core" : "gold",
      },
    }));

    const edges: CyEdge[] = model.overview.edges.map((e) => ({
      data: {
        id: `${e.source}->${e.target}`,
        source: e.source,
        target: e.target,
        kind: e.kind,
      },
    }));

    return { nodes, edges };
  }

  // level === "unit"
  const unit = model.units.find((u) => u.name === unitName);
  if (!unit) {
    return { nodes: [], edges: [] };
  }

  // How many use cases each table serves (>1 = shared), so the card can carry a
  // "shared xN" chip at rest. Derived from the same pure grouping the L1 bands use.
  const { sharedCount, sharedWith } = groupTablesByUseCase(unit);

  const nodes: CyNode[] = unit.tables.map((t) => ({
    data: {
      id: t.name,
      label: t.name,
      cls: t.layer === "gold" ? "gold" : "core",
      layer: t.layer,
      role: t.role,
      scd2: t.scd2,
      // Table-level COMMENT, surfaced as a hover tooltip on the card header.
      comment: t.comment,
      pii: t.columns.some((c) => c.pii),
      // # of use cases this table serves (>1 -> at-rest "shared" chip). Default 1.
      shared: sharedCount[t.name] ?? 1,
      // The use-case names for the shared chip's "Also in:" tooltip.
      shared_with: sharedWith[t.name] ?? [],
      columns: t.columns,
      // The core (silver) tables (+ domain) this table consumes, for the L1 lineage
      // reveal: gold mviews (via SQL lineage) and association/silver tables (via a
      // declared FK). [] when it consumes no core table (e.g. a plain silver master).
      consumes_tables: t.consumes_tables ?? [],
    },
  }));

  // Only draw relationships whose BOTH endpoints are tables in this unit. A unit's
  // relationships can point at tables in other domains (e.g. an association/bridge
  // table like `promotion_scope` references `promotion`, which lives elsewhere);
  // emitting such an edge makes cytoscape throw "Can not create edge with
  // nonexistent source", which took down the whole per-unit ER view. Cross-unit
  // references are shown at the overview/consumes level, not in the per-unit ER.
  const nodeIds = new Set(unit.tables.map((t) => t.name));
  const edges: CyEdge[] = unit.relationships
    .filter((r) => nodeIds.has(r.parent_table) && nodeIds.has(r.child_table))
    .map((r) => ({
      data: {
        id: `${r.parent_table}->${r.child_table}`,
        source: r.parent_table,
        target: r.child_table,
        declared_fk: r.declared_fk,
        // Column-level endpoints (source=parent, target=child) so an edge hover
        // can highlight the exact PK columns on the parent card and FK columns on
        // the child card. These were previously dropped.
        parent_cols: r.parent_cols,
        child_cols: r.child_cols,
      },
    }));

  return { nodes, edges };
}
