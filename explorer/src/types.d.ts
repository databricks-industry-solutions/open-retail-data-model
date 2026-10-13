declare module "cytoscape-node-html-label" {
  import type { Core, NodeSingular } from "cytoscape";

  interface NodeHtmlLabelOptions {
    query?: string;
    halign?: "left" | "center" | "right";
    valign?: "top" | "center" | "bottom";
    halignBox?: "left" | "center" | "right";
    valignBox?: "top" | "center" | "bottom";
    cssClass?: string;
    tpl?: (data: Record<string, unknown>) => string;
  }

  function cytoscapeNodeHtmlLabel(cy: typeof Core): void;
  export = cytoscapeNodeHtmlLabel;
}

declare module "cytoscape-fcose" {
  import type { Core } from "cytoscape";
  function cytoscapeFcose(cy: typeof Core): void;
  export = cytoscapeFcose;
}

// Vite `?raw` imports return the file's contents as a string (used by tests to
// assert against the authoritative CSS source without Node fs/@types/node).
declare module "*?raw" {
  const content: string;
  export default content;
}
