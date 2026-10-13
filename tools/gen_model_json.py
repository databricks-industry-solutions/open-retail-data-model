"""Generate explorer/public/model.json from the DDL (all units + overview),
and stage the files it links to (ODCS contracts + per-unit glossaries) into
explorer/public/ so the deployed site actually serves them.
  python tools/gen_model_json.py --write | --check
Sibling of tools/gen_er_diagrams.py."""
from __future__ import annotations
import argparse
import glob
import json
import os
import re
import shutil
import sys
from typing import NamedTuple

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from tools.ordm_ddl.discovery import UnitDiscovery
from tools.ordm_ddl.parser import (
    DdlParser,
    build_gold_sql,
    build_silver_schema,
    infer_all_gold_types,
)
from tools.ordm_ddl.emitters.json_model import JsonModelEmitter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PUBLIC = os.path.join(ROOT, "explorer", "public")
OUT = os.path.join(PUBLIC, "model.json")

# A qualified table reference in a gold MV's SQL: one or more ${...} schema/catalog
# placeholders, then a final `.<name>`. The captured `\w+` is the referenced table
# name. Only QUALIFIED refs are matched; bare names in a gold view are CTE aliases
# (WITH clauses) or functions, never real tables, so this cleanly excludes them.
_QUALIFIED_REF = re.compile(r"\$\{[^}]*\}(?:\.\$\{[^}]*\})*\.(\w+)")


class GoldLineage(NamedTuple):
    """Per-gold-table SQL lineage, resolved two ways from a single parse.

    `units` is the domain-level rollup (gold table -> core UNIT names) that drives
    the L0 landing edges + per-use-case `consumes`. `tables` is the finer resolution
    (gold table -> the leaf core/silver TABLES it reads, each tagged with its owning
    unit) that the L1 lineage reveal draws.
    """

    units: dict[str, set[str]]
    tables: dict[str, list[dict]]


def _gold_sources(
    package_dir: str, gold_tables: list[str], known_tables: set[str]
) -> dict[str, set[str]]:
    """Parse each of a package's gold views into the KNOWN tables its SQL references.

    For each gold table `outcome-packages/<pkg>/gold/<gold_table>.sql`:
      1. Extract QUALIFIED table refs (`${...}.<name>` / `${...}.${...}.<name>`),
         taking the final `\\w+` as the referenced table name.
      2. Keep only refs that match a KNOWN table name in the model (any unit's
         table: core, ingredient, or gold). An unknown name is a CTE/function and
         is simply ignored (never fails).

    Fails loud if a listed gold table has no SQL file (a real authoring error,
    mirroring _load_use_cases' no-silent-drops posture), or if a gold view names a
    known table BARE in FROM/JOIN (see the guard below).
    """
    gold_sources: dict[str, set[str]] = {}
    for g in sorted(gold_tables):
        sql_path = os.path.join(package_dir, "gold", g + ".sql")
        if not os.path.exists(sql_path):
            raise RuntimeError(
                f"gold table {g!r} in package "
                f"{os.path.relpath(package_dir, ROOT)!r} has no SQL file at "
                f"{os.path.relpath(sql_path, ROOT)!r}"
            )
        with open(sql_path, encoding="utf-8") as fh:
            sql = fh.read()
        # Strip SQL comments first so prose like "-- ... derived from product ..."
        # is not mistaken for a FROM/JOIN table reference by the bare-ref guard.
        sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.DOTALL)
        sql = re.sub(r"--[^\n]*", " ", sql)
        # ...then single-quoted string literals ('' escapes a quote), so text INSIDE a
        # string (e.g. a label 'derived from sales') isn't scanned as a FROM/JOIN ref.
        sql = re.sub(r"'(?:[^']|'')*'", " ", sql)
        refs = {m for m in _QUALIFIED_REF.findall(sql) if m in known_tables}
        refs.discard(g)  # the view's own CREATE ... AS target is not a source
        gold_sources[g] = refs

        # Guard (no silent drops): the lineage only recognizes QUALIFIED refs
        # (${catalog}.${schema}.table); a BARE FROM/JOIN reference to a real table
        # would be mistaken for a CTE/function and dropped, silently under-reporting
        # `consumes`. Gold views reference sources qualified, so flag any bare
        # FROM/JOIN identifier that is NOT a CTE defined in this file yet matches a
        # known table - enforcing the convention loudly instead of failing open.
        # Match CTE names after WITH / WITH RECURSIVE / a comma, allowing the optional
        # column-list form `name (a, b) AS (...)`, so a CTE whose name collides with a
        # real table is recognized as a CTE and does not false-trip the bare-ref guard.
        cte_names = set(
            re.findall(
                r"(?:WITH\s+(?:RECURSIVE\s+)?|,)\s*(\w+)\s*(?:\([^)]*\))?\s+AS\s*\(",
                sql,
                re.IGNORECASE,
            )
        )
        bare_refs = set(re.findall(r"\b(?:FROM|JOIN)\s+(\w+)", sql, re.IGNORECASE))
        suspicious = sorted((bare_refs - cte_names - {g}) & known_tables)
        if suspicious:
            raise RuntimeError(
                f"gold view {g!r} in package "
                f"{os.path.relpath(package_dir, ROOT)!r} references known table(s) "
                f"{suspicious} by a BARE name in FROM/JOIN; gold views must qualify "
                f"source tables (${{catalog}}.${{schema}}.table) so their lineage is "
                f"not silently dropped from `consumes`. Qualify the reference (or, if "
                f"it is a CTE whose name collides with a real table, rename the CTE)."
            )
    return gold_sources


def _gold_consumes(
    package_dir: str,
    gold_tables: list[str],
    core_tables: dict[str, str],
    relationships: list[dict],
    known_tables: set[str],
    foreign_gold_sources: dict[str, set[str]] | None = None,
    foreign_relationships: list[dict] | None = None,
    own_gold_sources: dict[str, set[str]] | None = None,
) -> GoldLineage:
    """Map each gold table to the CORE it consumes (units AND leaf tables), via SQL lineage.

    Gold tables are materialized VIEWS with no declared FK relationships, so the
    FK-only `consumes` derivation is empty for them. This reads each gold view's
    SQL FROM/JOIN lineage instead (`_gold_sources`) and resolves it back to core
    units, reusing the existing `core_tables` map and FK `relationships`.

    `consumes_units(table)` resolves, transitively (with a cycle guard):
      - a CORE table    -> {core_tables[table]}
      - a GOLD table    -> union of consumes_units(s) for s in its sources
      - else (ingredient, i.e. non-gold non-core) -> follow its FK relationships:
        union of consumes_units(r.parent_table) for r in the relationships where
        r.child_table == table, so an ingredient -> ingredient -> core chain (CMN
        campaign -> advertiser -> supplier) reaches core instead of stopping after one hop

    A gold view may read ANOTHER package's gold view or ingredient table (e.g. DSWS's
    gold_supplier_media_report reads CMN's campaign_day). `foreign_gold_sources` (the
    other packages' parsed gold views) and `foreign_relationships` (their FKs) let the
    walk continue through those to core; without them a cross-package ref is a dead
    end and its core lineage silently drops out of `consumes` and `consumes_tables`.
    Table names are unique across the model, so a name identifies its owner (enforced by
    tests/test_apply_domains_filter.py::test_no_cross_schema_object_name_collision).
    `own_gold_sources` is this package's already-parsed `_gold_sources` map, when the
    caller has it (build_model does), so the SQL is not scanned twice.
    """
    if own_gold_sources is None:
        own_gold_sources = _gold_sources(package_dir, gold_tables, known_tables)
    gold_sources = {**(foreign_gold_sources or {}), **own_gold_sources}
    # child table -> its FK parent tables, indexed once instead of scanning every
    # package's relationships at each step of the walk.
    fk_parents: dict[str, list[str]] = {}
    for r in relationships + (foreign_relationships or []):
        fk_parents.setdefault(r["child_table"], []).append(r["parent_table"])

    def consumes_units(table: str, seen: frozenset[str]) -> set[str]:
        if table in seen:  # cycle guard (gold views can reference each other)
            return set()
        seen = seen | {table}
        if table in core_tables:
            return {core_tables[table]}
        if table in gold_sources:
            out: set[str] = set()
            for src in gold_sources[table]:  # deterministic below via sort
                out |= consumes_units(src, seen)
            return out
        # An ingredient table (non-gold, non-core): follow its declared FKs, through any
        # intermediate ingredient (e.g. CMN campaign -> advertiser -> supplier), to core.
        out = set()
        for parent in fk_parents.get(table, ()):
            out |= consumes_units(parent, seen)
        return out

    def consumes_core_tables(table: str, seen: frozenset[str]) -> set[str]:
        # Same transitive walk as consumes_units, but resolving to the leaf CORE
        # (silver) TABLE names rather than their owning units - the finer lineage the
        # L1 view draws.
        if table in seen:
            return set()
        seen = seen | {table}
        if table in core_tables:
            return {table}
        if table in gold_sources:
            out: set[str] = set()
            for src in gold_sources[table]:
                out |= consumes_core_tables(src, seen)
            return out
        out = set()
        for parent in fk_parents.get(table, ()):
            out |= consumes_core_tables(parent, seen)
        return out

    return GoldLineage(
        units={g: consumes_units(g, frozenset()) for g in sorted(gold_tables)},
        tables={
            g: [
                {"table": t, "unit": core_tables[t]}
                for t in sorted(consumes_core_tables(g, frozenset()))
            ]
            for g in sorted(gold_tables)
        },
    )


def staged_assets(model: dict) -> list[tuple[str, str]]:
    """The files model.json links to, as (source_abs, dest_rel) pairs.

    The explorer panel renders `contract_path` / `glossary_path` as links; those
    strings are repo-relative paths whose source lives at the repo root, NOT in
    explorer/public/. Vite serves (and the deploy publishes) only explorer/public/,
    so each linked file must be staged there under the EXACT same relative path
    the link uses, or the link dead-ends on the SPA fallback.

    Only the specific files the model references are staged — never a bulk copy of
    repo content. Deterministic order (sorted, de-duplicated).
    """
    rels: set[str] = set()
    for u in model["units"]:
        for key in ("contract_path", "glossary_path"):
            p = u.get(key)
            if p:
                rels.add(p)
    pairs: list[tuple[str, str]] = []
    for rel in sorted(rels):
        src = os.path.join(ROOT, rel)
        if os.path.exists(src):  # a link to a not-yet-authored file is skipped
            pairs.append((src, rel))
    return pairs


def staged_orphans(expected: set[str]) -> list[str]:
    """Staged copies under explorer/public/ that model.json no longer references.

    staged_assets() mirrors each referenced contract_path / glossary_path into
    explorer/public/; if a source is renamed or deleted, its old mirror lingers and
    keeps being served. This reverse sweep finds those orphans so --check flags them
    and --write prunes them - the same missing/extra/changed guarantee the ODCS gate
    already has (via git), now for the explorer/public mirror. `expected` is the set
    of absolute dest paths staged_assets() would (re)write.
    """
    present: set[str] = set()
    # contract_path and glossary_path are the only staged link types. The
    # `contracts/odcs/**/*` sweep matches ANY file (not just *.yaml) under the MIRROR
    # dir, so a stray non-generated file staged there (nothing does today) is reported
    # and pruned rather than silently served; the hand-authored contracts/odcs/README.md
    # lives only in the SOURCE tree, is never mirrored, and so is never swept.
    for pat in ("contracts/odcs/**/*", "**/glossary.md"):
        for p in glob.glob(os.path.join(PUBLIC, pat), recursive=True):
            if os.path.isfile(p):
                present.add(os.path.abspath(p))
    return sorted(present - expected)


def _read_bytes(path: str) -> bytes:
    with open(path, "rb") as fh:
        return fh.read()


def build_model() -> dict:
    parser, jm = DdlParser(), JsonModelEmitter()
    units = []
    unit_dirs: dict[str, str] = {}  # unit name -> its source dir (for gold SQL lineage)

    # Parse every unit first, so each package's gold tables are known before any unit is
    # emitted: a use case may name another package's gold view (ADR 0045), and the
    # emitter validates it against that package. Each unit is parsed once.
    parsed = []
    for d in UnitDiscovery(ROOT).find(None):
        try:
            unit = parser.parse_unit(d)
        except Exception as exc:
            raise RuntimeError(
                f"failed to build model.json for unit '{os.path.relpath(d, ROOT)}': {exc}"
            ) from exc
        jm.all_units[unit.name] = frozenset(t.name for t in unit.tables if t.layer == "gold")
        parsed.append((d, unit))

    for d, unit in parsed:
        try:
            ud = jm.unit_dict(unit)
        except Exception as exc:
            # Fail loud but NAME the offending unit (mirrors gen_er_diagrams) so a
            # drift-gate failure from the parser's fail-loud path is readable rather
            # than a bare, unit-less traceback (#55 review M1).
            raise RuntimeError(
                f"failed to build model.json for unit '{os.path.relpath(d, ROOT)}': {exc}"
            ) from exc
        # Scope FK to (child_table, column) pairs — a unit-wide name set wrongly flagged a
        # PK on its own parent table (e.g. profile.profile_sk) as an FK (#53 H2).
        fk_pairs = {(r["child_table"], c) for r in ud["relationships"] for c in r["child_cols"]}
        for t in ud["tables"]:
            for c in t["columns"]:
                if (t["name"], c["name"]) in fk_pairs:
                    c["fk"] = True
        units.append(ud)
        unit_dirs[ud["name"]] = d
    ov_nodes = [{"id": u["name"], "label": u["name"], "kind": u["kind"]} for u in units]
    core_tables = {
        t["name"]: u["name"]
        for u in units
        if u["kind"] == "core"
        for t in u["tables"]
    }
    # Every table name known to the model (core, ingredient, or gold) across all
    # units. The second CTE/function filter for the gold-SQL lineage pass: a
    # qualified ref not in this set is a CTE or function and is ignored.
    known_tables = {t["name"] for u in units for t in u["tables"]}
    # Silver schema {table: {col: sqltype}} + gold-view SQL {view: sql} for gold-view
    # TYPE inference (gold mviews declare no column types; sqlglot annotates each
    # projection from the sources, resolving gold-on-gold to a fixpoint). Both are
    # collected by the shared helpers in parser.py - the SAME collection generate_odcs
    # uses, co-located with the inference so the two consumers can't diverge.
    dirs = list(unit_dirs.values())
    silver_schema = build_silver_schema(dirs)
    gold_sql = build_gold_sql(dirs)
    gold_types_all = infer_all_gold_types(silver_schema, gold_sql)
    # Every outcome package's parsed gold views + FKs, so one package's lineage can
    # walk THROUGH another's gold view or ingredient table on its way to core (each
    # unit is handed the OTHER packages' maps as `foreign_*`).
    outcome_units = [u for u in units if u["kind"] == "outcome"]
    all_gold_sources = {
        u["name"]: _gold_sources(
            unit_dirs[u["name"]],
            [t["name"] for t in u["tables"] if t["layer"] == "gold"],
            known_tables,
        )
        for u in outcome_units
    }
    ov_edges = []
    gold_consumes_by_unit: dict[str, dict[str, set[str]]] = {}
    for u in units:
        if u["kind"] != "outcome":
            continue
        # FK-based L0 consumption: declared FKs sit on the package's INGREDIENT
        # tables (e.g. competitor_price, promotion_scope) pointing into core.
        fk_refs = {
            core_tables[r["parent_table"]]
            for r in u["relationships"]
            if r["parent_table"] in core_tables
        }
        # Gold-SQL FROM/JOIN lineage: each gold view reaches core via qualified
        # table refs in its SQL (the FKs do not sit on the gold views). Derive, per
        # gold table, the set of core units it consumes (transitively through other
        # gold views and through ingredient tables' FKs).
        gold_tables = [t["name"] for t in u["tables"] if t["layer"] == "gold"]
        others = [o for o in outcome_units if o["name"] != u["name"]]
        gold_lineage = _gold_consumes(
            unit_dirs[u["name"]],
            gold_tables,
            core_tables,
            u["relationships"],
            known_tables,
            foreign_gold_sources={
                g: s for o in others for g, s in all_gold_sources[o["name"]].items()
            },
            foreign_relationships=[r for o in others for r in o["relationships"]],
            own_gold_sources=all_gold_sources[u["name"]],
        )
        gold_consumes = gold_lineage.units
        # Attach each gold view's leaf silver-table lineage to its table dict, so the
        # L1 view can reveal mview -> silver (domain + table) links + highlight the
        # silver keys, reusing the L0 hover UX. Empty list for a gold view that reads
        # no core table.
        for t in u["tables"]:
            if t["layer"] == "gold":
                t["consumes_tables"] = gold_lineage.tables.get(t["name"], [])
                # Fill the type-less gold columns from the topological inference above;
                # blank where sqlglot still can't resolve (computed expressions).
                col_types = gold_types_all.get(t["name"], {})
                for c in t["columns"]:
                    if not c.get("type"):
                        c["type"] = col_types.get(c["name"], "")
            else:
                # Association / ingredient tables (non-gold, e.g. promotion_scope) reach core
                # via declared FKs, not SQL. Attach the SAME consumes_tables shape (core table
                # + its domain) so the L1 hover arcs them to the core tables they reference,
                # exactly like a gold view's consumes arcs. A table with no core FK gets [].
                refs = sorted({
                    (r["parent_table"], core_tables[r["parent_table"]])
                    for r in u["relationships"]
                    if r.get("child_table") == t["name"] and r.get("parent_table") in core_tables
                })
                t["consumes_tables"] = [{"table": tbl, "unit": dom} for tbl, dom in refs]
        # L0 overview edges: UNION of the FK-based derivation and the gold-SQL
        # derivation, so the home-screen lineage is complete and consistent with
        # the per-use-case chips (e.g. bmv now also consumes `transaction` via
        # `sales`). Edge shape {source, target, kind:"consumes"} is unchanged.
        gold_refs: set[str] = set()
        for units_for_gold in gold_consumes.values():
            gold_refs |= units_for_gold
        refs = sorted(fk_refs | gold_refs)
        ov_edges += [{"source": u["name"], "target": c, "kind": "consumes"} for c in refs]
        gold_consumes_by_unit[u["name"]] = gold_consumes
    # Per-use-case core consumption: the union of gold-SQL consumes over each use
    # case's `tables:` (its own gold views) and `foreign_tables:` (another package's
    # gold views, resolved through THAT package's lineage, so the chips are domain
    # names either way). Computed after the loop so every package's lineage exists.
    # A use case with neither gets `consumes: []`.
    by_name = {u["name"]: u for u in outcome_units}
    for u in outcome_units:
        for uc in u["use_cases"]:
            uc_refs: set[str] = set()
            for g in uc.get("tables") or []:
                uc_refs |= gold_consumes_by_unit[u["name"]].get(g, set())
            for ft in uc.get("foreign_tables") or []:
                uc_refs |= gold_consumes_by_unit[ft["unit"]].get(ft["table"], set())
            uc["consumes"] = sorted(uc_refs)
    # Reverse index on the OWNING package: the other packages' use cases its gold
    # views serve (e.g. ACU's gold_customer_ltv serves UCV's Customer Lifetime Value),
    # so the owner's L1 can band those views under that use case instead of "Not
    # mapped to a use case". Order: owner-independent manifest order (deterministic).
    for u in outcome_units:
        u["external_use_cases"] = []
    for u in outcome_units:
        for uc in u["use_cases"]:
            per_owner: dict[str, list[str]] = {}
            for ft in uc.get("foreign_tables") or []:
                per_owner.setdefault(ft["unit"], [])
                if ft["table"] not in per_owner[ft["unit"]]:
                    per_owner[ft["unit"]].append(ft["table"])
            for owner, tables in per_owner.items():
                owner_refs: set[str] = set()
                for t in tables:
                    owner_refs |= gold_consumes_by_unit[owner].get(t, set())
                by_name[owner]["external_use_cases"].append({
                    "unit": u["name"],
                    "name": uc["name"],
                    "status": uc["status"],
                    "tables": tables,
                    "consumes": sorted(owner_refs),
                })
    return {
        "generated_by": "tools/gen_model_json.py",
        "overview": {"nodes": ov_nodes, "edges": ov_edges},
        "units": units,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    model = build_model()
    content = json.dumps(model, indent=2, sort_keys=True) + "\n"
    have = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else None
    assets = staged_assets(model)
    expected = {os.path.abspath(os.path.join(PUBLIC, rel)) for _, rel in assets}
    orphans = staged_orphans(expected)

    stale = have != content
    # An asset is stale if its staged copy is missing or differs from the source...
    for src, rel in assets:
        dest = os.path.join(PUBLIC, rel)
        if not os.path.exists(dest) or _read_bytes(dest) != _read_bytes(src):
            stale = True
            break
    # ...or if a staged copy lingers whose source the model no longer references (a
    # renamed/deleted contract or glossary). Without this reverse sweep the explorer
    # would keep serving the stale file; mirrors the ODCS gate's orphan awareness.
    if orphans:
        stale = True

    if not stale:
        return 0

    if a.write:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with open(OUT, "w", encoding="utf-8") as fh:
            fh.write(content)
        for src, rel in assets:
            dest = os.path.join(PUBLIC, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copyfile(src, dest)
        for path in orphans:  # prune staged copies the model no longer references
            os.remove(path)
        return 0
    if a.check:
        detail = ""
        if orphans:
            rels = ", ".join(os.path.relpath(p, ROOT) for p in orphans)
            detail = f" (orphaned staged copies from a removed/renamed source: {rels})"
        print(
            "explorer/public is stale" + detail + ", regenerate model.json and the staged "
            "contract/glossary files. Run: python tools/gen_model_json.py --write"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
