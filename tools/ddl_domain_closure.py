# ============================================================
# ORDM · CI · DDL domain closure (cross-package view dependencies)
# ============================================================
# Given the domain/package labels a PR changed, return the FULL set of labels whose
# DDL must be applied for that deploy to compile.
#
# The lean per-PR gate already expands the changed labels by what the selected
# GENERATORS write (`_registry.generator_domains`). That closes the *data* gap: a
# generator pulled in as an upstream provider also writes its own package's tables.
# It does NOT close the *view-compilation* gap:
#
#   A gold view or metric view may read another package's gold object with no FK and
#   no generator relationship — the deliberate NULL-safe cross-package read this model
#   uses throughout (ADR 0019/0021; see gold_joint_demand_plan, gold_category_growth,
#   gold_data_product_revenue). A plain view still has to RESOLVE its references at
#   CREATE time, so if the referenced package's DDL was never applied the deploy fails
#   with TABLE_OR_VIEW_NOT_FOUND even though nothing is wrong with the model.
#
# Concretely: a change to `data-sharing-with-suppliers` selects the `customer_ltv`
# generator (it provides `acu`), so actionable-customer-understanding's DDL is applied
# — including its metric view, which reads unified-customer-view's
# gold_activatable_audience_current. UCV ships NO generator, so `generator_domains`
# never yields it and the metric view cannot resolve. This module adds that closure by
# reading the committed SQL: for every unit being deployed, find the `${x_schema}`
# tokens its gold/metric views reference and pull in the units that own them, to a
# fixed point (a newly-added unit may itself read a third).
#
# The SAME resolve-at-apply-time requirement holds for FOREIGN KEYS: relationships.sql
# runs `ALTER TABLE ... ADD FOREIGN KEY ... REFERENCES ${x_schema}.parent`, which needs
# the parent table present or the deploy dies with TABLE_OR_VIEW_NOT_FOUND. Most packages
# also READ their FK parents from a view, so the parent came in for free — but a package
# whose gold views touch only its own tables (ai-assisted-store-associates: the queue and
# funnel views read no core object, yet its facts FK into store/customer/product) has no
# view edge to those parents. So the closure follows relationships.sql FK targets too.
#
# Pure stdlib + the repo's own schema-token map, so it is unit-testable without a
# workspace. Used by .github/workflows/ordm-lean-pr-deploy.yml.
#
# Usage:
#   python3 tools/ddl_domain_closure.py data-sharing-with-suppliers,customer
#   python3 tools/ddl_domain_closure.py --json <labels>
# ============================================================
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_ROOTS = ("canonical-core", "outcome-packages")

# `${catalog}.${some_schema}.object` — capture the schema TOKEN, which is what maps
# back to an owning unit. Matches the reference style every view in this repo uses.
_SCHEMA_TOKEN = re.compile(r"\$\{(\w+_schema)\}")


def _strip_sql_comments(sql: str) -> str:
    """Drop -- line comments and /* block */ comments.

    Load-bearing: these headers DISCUSS other packages by name (e.g. "NULL-safe read of
    the Smarter Demand package"), and a commented-out or merely-described reference must
    not drag a whole package into the deploy set.
    """
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    return re.sub(r"--[^\n]*", "", sql)


def schema_token_owners() -> dict[str, str]:
    """Map each `${x_schema}` token -> the unit label that owns it.

    Derived from the repo's own token map (databricks.yml via tools.ordm_config) matched
    against real unit directories, rather than a hand-maintained second list that could
    drift from it.
    """
    sys.path.insert(0, ROOT)
    from tools.ordm_config import schema_defaults

    # unit label (dir name) -> its underscored form, e.g. unified-customer-view ->
    # unified_customer_view. An outcome-package schema is the full package slug (§D).
    label_by_underscored = {}
    for root in _ROOTS:
        for path in sorted(glob.glob(os.path.join(ROOT, root, "*"))):
            if os.path.isdir(path):
                label = os.path.basename(path)
                label_by_underscored[label.replace("-", "_")] = label

    owners = {}
    for token, schema in schema_defaults().items():
        if not token.endswith("_schema"):
            continue
        label = label_by_underscored.get(schema)
        if label:
            owners[token] = label
    return owners


def _dependency_files(label: str) -> list[str]:
    """The unit SQL whose cross-unit references must be APPLIED for `label` to deploy:

    * gold + metric view SQL — a plain view RESOLVES its refs at CREATE time, so a
      referenced package's DDL must be applied (the view-compilation gap above); and
    * relationships.sql — its `ALTER TABLE ... ADD FOREIGN KEY ... REFERENCES
      ${x_schema}.parent` needs the parent table to exist at ALTER time, or the deploy
      dies with TABLE_OR_VIEW_NOT_FOUND. Most packages reach their FK parents through a
      view too, so this was latent; a package whose gold views read only its OWN tables
      (ai-assisted-store-associates: the queue/funnel views touch no core object, yet its
      facts FK into store/customer/product) has NO view path to those parents, so the FK
      target is the only edge that pulls them in.
    """
    out: list[str] = []
    for root in _ROOTS:
        base = os.path.join(ROOT, root, label)
        for sub in ("gold", "metric-views"):
            out += sorted(glob.glob(os.path.join(base, sub, "*.sql")))
        rels = os.path.join(base, "relationships.sql")
        if os.path.isfile(rels):
            out.append(rels)
    return out


def referenced_labels(label: str, owners: dict[str, str] | None = None) -> set[str]:
    """The unit labels `label` references (excluding itself): objects its views read
    plus the FK parents its relationships.sql targets — both must be applied to deploy."""
    owners = owners if owners is not None else schema_token_owners()
    found: set[str] = set()
    for path in _dependency_files(label):
        with open(path, encoding="utf-8") as fh:
            body = _strip_sql_comments(fh.read())
        for token in _SCHEMA_TOKEN.findall(body):
            owner = owners.get(token)
            if owner and owner != label:
                found.add(owner)
    return found


def ddl_domain_closure(labels) -> list[str]:
    """Close `labels` under "my views reference your objects", to a fixed point."""
    owners = schema_token_owners()
    pending = {str(x).strip() for x in labels if str(x).strip()}
    seen: set[str] = set()
    while pending:
        label = pending.pop()
        if label in seen:
            continue
        seen.add(label)
        pending |= referenced_labels(label, owners) - seen
    return sorted(seen)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("labels", help="comma-separated domain/package labels")
    ap.add_argument("--json", action="store_true", help="emit JSON")
    args = ap.parse_args()
    out = ddl_domain_closure(args.labels.split(","))
    print(json.dumps({"domains": out}) if args.json else ",".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
