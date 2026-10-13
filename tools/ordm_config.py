# ============================================================
# ORDM · shared SQL token resolver
# ============================================================
# Single source of truth for resolving the ${catalog} / ${<domain>_schema}
# tokens used throughout the SQL. Schema names are read from databricks.yml
# `variables` (the project config — guardrail #1: never hardcode a schema),
# so the DQ runner, the tests, and any future deploy runner all resolve
# tokens the same way. Pure stdlib + PyYAML (no Spark) so it imports anywhere.
# ============================================================

import os
import re
from functools import lru_cache

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATABRICKS_YML = os.path.join(REPO_ROOT, "databricks.yml")
RULES_YML = os.path.join(REPO_ROOT, "standards", "rules.yaml")

# Matches the CREATE header of a view OR a materialized view, regardless of
# CREATE [OR REPLACE|OR REFRESH] [MATERIALIZED] VIEW <name> [SCHEDULE ...] AS ...
_CREATE_VIEW_RE = re.compile(
    r"CREATE\s+(?:OR\s+(?:REPLACE|REFRESH)\s+)?(?:MATERIALIZED\s+)?VIEW\b.*?\bAS\b",
    re.IGNORECASE | re.DOTALL,
)

# A materialized view declares its physical layout as a trailing `CLUSTER BY (...)`
# after the SELECT. It is not part of the query logic, so it is stripped when the
# SELECT body is extracted for parsing/execution.
_TRAILING_CLUSTER_BY = re.compile(r"\s*CLUSTER\s+BY\s*\([^)]*\)\s*$", re.IGNORECASE)

# Safety net only — used when databricks.yml cannot be read. databricks.yml
# remains authoritative; keep these in sync with its `variables` defaults.
_FALLBACK = {
    "customer_schema": "customer",
    "product_schema": "product",
    "store_schema": "store",
    "calendar_schema": "calendar",
    "transaction_schema": "transaction",
    "marketing_schema": "marketing",
    "promo_schema": "promote_with_purpose",
    "supplier_schema": "supplier",
    "procurement_schema": "procurement",
    "risk_schema": "early_risk_detection",
    "order_schema": "orders",
    "payment_schema": "payment",
    "acu_schema": "actionable_customer_understanding",
    "dss_schema": "data_sharing_with_suppliers",
    "inventory_schema": "inventory",
    "logistics_schema": "logistics",
    "bmv_schema": "balancing_margin_and_volume",
    "ac_schema": "agentic_commerce",
    "ucv_schema": "unified_customer_view",
    "equipment_schema": "equipment",
    "labor_schema": "labor",
    # The predictive-operations package deploys ALL its objects (equipment
    # maintenance + store performance + workforce optimization) into one schema
    # named for the package, per standards §D (an outcome-package schema is the
    # full package slug). The earlier `in_store_equipment_maintenance` schema was
    # use-case-named naming drift from when #76's standalone package was folded
    # in (PR #83); ADR 0028 consolidates it here now, while pre-publication makes
    # the rename cheap. Workforce Optimization unlocked by ADR 0043 (labor core).
    "predops_schema": "predictive_operations",
    "cmn_schema": "commerce_media_networks",
    "css_schema": "connected_store_signals",
    "sdi_schema": "smarter_demand_and_inventory_decisions",
    "interaction_schema": "interaction",
    "aasa_schema": "ai_assisted_store_associates",
}

# SQL-expression tokens are deliberately separate from catalog/schema identifiers.
# Their defaults preserve production semantics, and callers may override them only
# through a validated helper such as rfid_clock_expressions() below.
_SQL_EXPRESSION_DEFAULTS = {
    "rfid_as_of_ts": "current_timestamp()",
    "rfid_fixed_freshness_minutes": "120",
    "rfid_mobile_freshness_minutes": "1440",
    "rfid_count_target_cadence_days": "7",
    "rfid_count_lookback_days": "30",
    # Smart Shelf evaluation clock: a parallel shelf-scope expression rather than a
    # rename of the shipped RFID tokens (additive; ADR 0038 mechanism, second consumer).
    "shelf_as_of_ts": "current_timestamp()",
    "shelf_fixed_freshness_minutes": "120",
    "shelf_mobile_freshness_minutes": "1440",
}


def schema_defaults():
    """Return {token: schema_name} read from databricks.yml `variables`."""
    defaults = dict(_FALLBACK)
    try:
        import yaml
        with open(DATABRICKS_YML) as fh:
            data = yaml.safe_load(fh) or {}
        for name, spec in (data.get("variables") or {}).items():
            if name.endswith("_schema") and isinstance(spec, dict) and "default" in spec:
                defaults[name] = spec["default"]
    except Exception:
        pass  # fall back to the built-in defaults
    return defaults


@lru_cache(maxsize=1)
def _lineage_policies():
    """Load deployed/static lineage-policy registries from the standards source."""
    import yaml

    with open(RULES_YML, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    policies = data.get("policy_registries") or {}
    if not isinstance(policies, dict):
        raise ValueError("standards/rules.yaml policy_registries must be a mapping")
    return policies


def lineage_policy(name):
    """Return one named cross-surface policy from standards/rules.yaml."""
    policies = _lineage_policies()
    if name not in policies:
        raise KeyError(f"unknown lineage policy: {name}")
    policy = policies[name]
    if not isinstance(policy, dict):
        raise ValueError(f"lineage policy {name!r} must be a mapping")
    return policy


def policy_schema_literals(name, schemas=None):
    """Render a registry's configured schema-scope tokens as safe SQL literals."""
    mapping = dict(schemas or schema_defaults())
    policy = lineage_policy(name)
    scope_key = str(policy.get("schema_scopes_key") or "price_producing_scopes")
    scopes = policy.get(scope_key) or []
    values = []
    for scope in scopes:
        token = scope.get("schema_token") if isinstance(scope, dict) else None
        if not token or token not in mapping:
            raise ValueError(
                f"lineage policy {name!r} has unknown schema token {token!r}"
            )
        value = str(mapping[token]).lower()
        if value not in values:
            values.append(value)
    if not values:
        raise ValueError(f"lineage policy {name!r} has no {scope_key}")
    return ", ".join("'" + value.replace("'", "''") + "'" for value in values)


def policy_object_values(name):
    """Render protected object names as a SQL VALUES row list."""
    objects = lineage_policy(name).get("protected_objects") or []
    if not objects:
        raise ValueError(f"lineage policy {name!r} has no protected objects")
    return ", ".join(
        "('" + str(value).lower().replace("'", "''") + "')" for value in objects
    )


def policy_name_pattern(name):
    """Render a registry-owned lowercase SQL regular-expression pattern."""
    pattern = str(
        lineage_policy(name).get("price_producing_name_pattern") or ""
    ).lower()
    if not pattern or not re.fullmatch(r"[a-z0-9_|]+", pattern):
        raise ValueError(
            f"lineage policy {name!r} has an invalid price-producing name pattern"
        )
    return pattern


def single_schema_overrides(name):
    """Return {every_schema_token: name} so a caller can collapse the whole model into ONE
    schema (design/59). Used by the per-PR lean CI gate to deploy a PR's domains into a
    single isolated `pr_<N>` database in the shared CI catalog, instead of the 23 per-domain
    schemas: passing one --single_schema value beats threading 23 --<domain>_schema overrides,
    and cross-domain object names are globally unique so nothing collides in one schema.
    Empty/falsy name -> {} (no override; today's per-domain behaviour)."""
    if not name:
        return {}
    return {token: name for token in schema_defaults()}


def view_select_body(sql_text):
    """Return the SELECT body of a CREATE [OR REPLACE | OR REFRESH] [MATERIALIZED]
    VIEW statement — form-agnostic, so plain views and materialized views are
    handled the same way (the SELECT logic is identical).

    A trailing `CLUSTER BY (...)` (materialized views declare a physical layout
    after the SELECT) is stripped so the returned text is a clean, parseable
    SELECT — sqlglot chokes on a `SELECT ... CLUSTER BY (...)` tail. This lets the
    Spark gold-view tests run the body verbatim for materialized views that end in
    a CLUSTER BY clause (e.g. the BMV gold views)."""
    m = _CREATE_VIEW_RE.search(sql_text)
    if not m:
        raise ValueError("no 'CREATE ... VIEW ... AS' found")
    body = sql_text[m.end():].strip().rstrip(";").rstrip()
    return _TRAILING_CLUSTER_BY.sub("", body).rstrip()


def rfid_clock_expressions(mode, catalog, overrides=None):
    """Return trusted SQL expressions for the RFID current-state evaluation clock.

    ``wall_clock`` needs no explicit override because it is the resolver default.
    ``data_max`` is for deterministic historical demos and evaluates item presence
    at the end of the RFID event-time window. Arbitrary SQL is never accepted.
    """
    normalized = str(mode or "wall_clock").strip().lower()
    if normalized == "wall_clock":
        return {}
    if normalized != "data_max":
        raise ValueError(
            "`rfid_as_of_mode` must be one of: wall_clock, data_max."
        )
    if not catalog:
        raise ValueError("`catalog` is required when rfid_as_of_mode=data_max.")

    schemas = schema_defaults()
    if overrides:
        schemas.update({k: v for k, v in overrides.items() if v})
    css_schema = schemas["css_schema"]
    return {
        "rfid_as_of_ts": (
            "COALESCE((SELECT MAX(event_ts) FROM "
            f"{catalog}.{css_schema}.rfid_read_event), current_timestamp())"
        ),
    }


def rfid_policy_expressions(
    fixed_freshness_minutes="120",
    mobile_freshness_minutes="1440",
    count_target_cadence_days="7",
    count_lookback_days="30",
):
    """Return validated integer literals for adopter-configurable RFID policies.

    These values become SQL expressions, so accept positive integers only. This
    keeps bundle/notebook overrides configurable without permitting arbitrary SQL.
    """
    values = {
        "rfid_fixed_freshness_minutes": fixed_freshness_minutes,
        "rfid_mobile_freshness_minutes": mobile_freshness_minutes,
        "rfid_count_target_cadence_days": count_target_cadence_days,
        "rfid_count_lookback_days": count_lookback_days,
    }
    expressions = {}
    for token, value in values.items():
        literal = str(value).strip()
        if not re.fullmatch(r"[1-9][0-9]*", literal):
            raise ValueError(f"`{token}` must be a positive integer.")
        expressions[token] = literal
    return expressions


def shelf_clock_expressions(mode, catalog, overrides=None):
    """Return trusted SQL expressions for the Smart Shelf evaluation clock.

    Second consumer of the ADR 0038 named-clock pattern, parallel to
    rfid_clock_expressions rather than a rename of its shipped tokens.
    ``data_max`` evaluates shelf currency at the end of the observation-time
    window for deterministic historical demos. Arbitrary SQL is never accepted.
    """
    normalized = str(mode or "wall_clock").strip().lower()
    if normalized == "wall_clock":
        return {}
    if normalized != "data_max":
        raise ValueError(
            "`shelf_as_of_mode` must be one of: wall_clock, data_max."
        )
    if not catalog:
        raise ValueError("`catalog` is required when shelf_as_of_mode=data_max.")

    schemas = schema_defaults()
    if overrides:
        schemas.update({k: v for k, v in overrides.items() if v})
    css_schema = schemas["css_schema"]
    return {
        "shelf_as_of_ts": (
            "COALESCE(GREATEST("
            "(SELECT MAX(observation_ts) FROM "
            f"{catalog}.{css_schema}.shelf_state_observation), "
            "(SELECT MAX(observed_at_ts) FROM "
            f"{catalog}.{css_schema}.esl_price_observation)"
            "), current_timestamp())"
        ),
    }


def shelf_policy_expressions(
    fixed_freshness_minutes="120",
    mobile_freshness_minutes="1440",
):
    """Return validated integer literals for adopter-configurable Smart Shelf
    freshness policies (positive integers only, same guardrail as the RFID helper)."""
    values = {
        "shelf_fixed_freshness_minutes": fixed_freshness_minutes,
        "shelf_mobile_freshness_minutes": mobile_freshness_minutes,
    }
    expressions = {}
    for token, value in values.items():
        literal = str(value).strip()
        if not re.fullmatch(r"[1-9][0-9]*", literal):
            raise ValueError(f"`{token}` must be a positive integer.")
        expressions[token] = literal
    return expressions


def resolve(sql, catalog, overrides=None, expressions=None):
    """Substitute catalog, schema, and trusted SQL-expression tokens in `sql`.

    `overrides` (token -> schema) wins over the databricks.yml defaults, so a
    deploy/DQ run can target non-default schemas via job parameters.

    `expressions` is separate so a SQL expression can never be mistaken for a
    schema name during catalog/schema bootstrap. Only known expression tokens are
    accepted; user-facing modes must be converted by a validating helper first.
    """
    mapping = schema_defaults()
    if overrides:
        mapping.update({k: v for k, v in overrides.items() if v})
    text = sql.replace("${catalog}", catalog)
    for token, value in mapping.items():
        text = text.replace("${" + token + "}", value)
    expression_mapping = dict(_SQL_EXPRESSION_DEFAULTS)
    for policy_name, policy in _lineage_policies().items():
        token = policy.get("sql_expression_token") if isinstance(policy, dict) else None
        if token and "${" + token + "}" in text:
            expression_mapping[token] = policy_schema_literals(policy_name, mapping)
        object_token = (
            policy.get("protected_objects_sql_expression_token")
            if isinstance(policy, dict) else None
        )
        if object_token and "${" + object_token + "}" in text:
            expression_mapping[object_token] = policy_object_values(policy_name)
        name_pattern_token = (
            policy.get("price_producing_name_pattern_sql_expression_token")
            if isinstance(policy, dict) else None
        )
        if name_pattern_token and "${" + name_pattern_token + "}" in text:
            expression_mapping[name_pattern_token] = policy_name_pattern(policy_name)
    if expressions:
        unknown = set(expressions) - set(expression_mapping)
        if unknown:
            raise ValueError(f"unknown SQL-expression token(s): {sorted(unknown)}")
        expression_mapping.update({k: v for k, v in expressions.items() if v})
    for token, value in expression_mapping.items():
        text = text.replace("${" + token + "}", value)
    return text
