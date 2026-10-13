# ============================================================
# ORDM · Synthetic data · shared deploy context
# ============================================================
# DeployContext bundles the parameters every generator's `run(ctx)` needs, so the
# generate_all orchestrator and the per-generator CLIs both build and pass ONE
# object instead of threading positional args (catalog, a schema dict, mode,
# base_currency) through divergent signatures. Built once from get_param + the
# shared tools/ordm_config resolver (guardrail #1: schema names never hardcoded).
# ============================================================

import os
import sys
from dataclasses import dataclass
from typing import Any

try:
    from _common import get_param
except ImportError:  # importable as a sibling when run as a notebook / spark_python_task
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import get_param

_SUFFIX = "_schema"


def _schema_token_defaults():
    """{token -> schema_name} from databricks.yml via the shared resolver."""
    here = os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0]))
    repo_root = os.path.abspath(os.path.join(here, "..", "..", ".."))
    if os.path.join(repo_root, "tools") not in sys.path:
        sys.path.insert(0, os.path.join(repo_root, "tools"))
    import ordm_config
    return ordm_config.schema_defaults()


@dataclass
class DeployContext:
    """Everything a generator's run(ctx) needs. `schemas` maps a SHORT key
    ("marketing", "promo", "risk", ...) to its resolved UC schema name, so
    ctx.fq("marketing", "promotion") -> "<catalog>.<marketing_schema>.promotion"."""
    spark: Any
    catalog: str
    schemas: dict
    mode: str = "overwrite"
    base_currency: str = "USD"

    def fq(self, schema_key: str, table: str) -> str:
        return f"{self.catalog}.{self.schemas[schema_key]}.{table}"

    @classmethod
    def from_params(cls, spark):
        """Build from get_param (widget -> env -> --flag argv) + the resolver.
        A `--<token>` (e.g. --marketing_schema) overrides the databricks.yml default;
        the short key is the token minus its trailing '_schema'."""
        catalog = get_param("catalog", "")
        if not catalog:
            raise ValueError("`catalog` parameter is required (guardrail #1: no hardcoded catalog).")
        # schemas carries EVERY project schema token (incl. outcome-package ones a
        # given generator never writes); each generator indexes only its own keys.
        # --single_schema collapses every short key to ONE schema (design/59 lean per-PR
        # gate: a PR's domains generate into one isolated pr_<N> database), so generators
        # write to the same schema the apply step created. Wins over per-token overrides.
        single = get_param("single_schema", "")
        schemas = {}
        for token, default in _schema_token_defaults().items():
            key = token[: -len(_SUFFIX)] if token.endswith(_SUFFIX) else token
            schemas[key] = single or get_param(token, "") or default
        return cls(
            spark=spark,
            catalog=catalog,
            schemas=schemas,
            mode=get_param("mode", "overwrite"),
            base_currency=get_param("base_currency", "USD"),
        )
