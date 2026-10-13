# ADR 0010 — Align governed-tag and semantic conventions with Databricks native features

**Status:** Accepted (2026-07-06)

## Context
ORDM defined its `dbx_*` tag vocabulary and its `glossary.md` convention before several Unity Catalog governance and semantic features reached GA or preview: Governed Tags (GA), Data Classification system tags (`class.*`), **Domains** (built on governed tags), the **UC Glossary** object (preview), UC Metric Views with agent metadata, and **Genie Ontology** — an auto-inferred context layer that ranks assets by authority (source, reliance, ties to certified/widely-used assets, freshness) and is fed by metric views, certification, domains, and glossary terms.

To rank as a high-authority source in Genie Ontology and to interoperate with UC Business Semantics rather than run a parallel metadata scheme, ORDM's conventions should **map onto the native features** where a native concept exists. Two constraints shape how: (1) Databricks reserves the tag prefixes `system.`, `class.`, and `sap.` — custom tags must not use them; (2) governed tags (including Domains) are account-level and admin-created, so an open model cannot bake specific ones into shared DDL.

## Decision
1. **Certification → `system.certification_status`.** A certified entity carries the system-governed tag `system.certification_status = 'certified'` (values `certified` | `deprecated`), set declaratively via `SET TAG ON TABLE … `. This is the documented Genie Ontology authority signal, so certified metric views and core tables earn ranking "for free." Already reflected in the [Definition of Done](../../docs/definition-of-done.md) "Certified" item.
2. **PII → declarative tags now, `class.*` from scanning later, coexisting.** ORDM keeps its own declarative, deploy-time PII tags as the immediate governance signal (ABAC masks/row filters can key off them at deploy). Databricks Data Classification separately auto-applies the reserved `class.*` system tags (`class.name`, `class.email_address`, …) from **data scanning**, which is usage/scan-driven and not immediate. ORDM does **not** set `class.*` (reserved system namespace). The two coexist; adopters may point ABAC at either. We maintain both deliberately until auto-classification catches up.
3. **Subdomain → UC Domains governed tags (optional overlay).** ORDM publishes the domain/subdomain taxonomy; adopters map it to UC **Domains**, where a top-level domain *is* a governed tag and a **subdomain is a separate governed tag named `{parentDomainTag}/{subdomainName}`** (e.g. `Retail/Merchandising`; tagging `Retail/Merchandising` does not auto-tag `Retail`). Because these governed tags are account-level and admin-created, this is an **optional deploy-time overlay in the adopter's account** (via UI or `SET TAG`), not baked into shared DDL — consistent with the UC Domains overlay (PR #40, which adds the domains ADR). ORDM's in-model subdomain tag is a documentation hint that maps to the Domain governed tag.
4. **Business glossary → UC Glossary + SKOS-style relationships.** `glossary.md` is the interim authoritative source; the target is the UC **Glossary** object. Glossary terms adopt **SKOS-style relationships** (`broader` / `narrower` / `related` / synonyms) so they map cleanly onto UC Glossary pages, which connect to the underlying data and to each other. SKOS is the pragmatic vocabulary standard; full OWL is out of scope.
5. **Prefix hygiene.** ORDM's own tag keys must never use the reserved `system.` / `class.` / `sap.` prefixes. The current `dbx_` prefix is ORDM-defined (not a Databricks-official namespace); a rename to a neutral namespace for the vendor-neutral open model is a noted candidate, **deferred** (out of scope here).

## Consequences
- Certified metric views/tables become high-authority Genie Ontology sources with a one-line `SET TAG`.
- PII governance works at deploy (declarative) and strengthens as Data Classification runs, with no reserved-namespace collision.
- Adopters get first-class Domains discovery by applying the domain/subdomain governed tags in their own account; the shared model stays deployment-neutral.
- `glossary.md` is authored UC-Glossary-ready, so migration to the native object is a lift-and-map rather than a rewrite.
- The alignment is recorded in `docs/data-model-standards.md` (tags/semantics) and the Definition of Done; no CI rule changes (these are conventions/guidance, not new mechanical gates).

## References (public)
- [Governed tags](https://docs.databricks.com/aws/en/admin/governed-tags)
- [Flag data as certified or deprecated](https://docs.databricks.com/aws/en/data-governance/unity-catalog/certify-deprecate-data)
- [Supported classification tags (`class.*`)](https://docs.databricks.com/aws/en/data-governance/unity-catalog/data-classification-tags)
- [Discover page, domains, and subdomains](https://docs.databricks.com/aws/en/discover/discover-page)
- [Unity Catalog business semantics](https://docs.databricks.com/aws/en/business-semantics) · [Agent metadata in metric views](https://docs.databricks.com/aws/en/business-semantics/agent-metadata)
- [Introducing Genie One, Genie Ontology, and Genie Agents](https://www.databricks.com/blog/introducing-genie-one-genie-ontology-and-genie-agents) · [What's new with Unity Catalog at Data + AI Summit 2026](https://www.databricks.com/blog/whats-new-unity-catalog-data-ai-summit-2026)
