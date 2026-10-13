# ============================================================
# ORDM · Synthetic data · generator registry
# ============================================================
# Declarative registry of the synthetic-data generators: each declares the schema
# keys it PROVIDES (writes) and the ones it DEPENDS_ON (reads). A topological sort
# turns that into the run order — the single source of ordering truth, replacing the
# hardcoded databricks.yml task chain + the "run X first" comments. generate_all
# calls select() on every run: the default deploy passes no --include (runs the full
# set), and --include runs a domain subset plus its transitive upstreams. The
# domain->generator mapping is DERIVED from `provides` (no hand-maintained manifest).
# ============================================================

from dataclasses import dataclass, field


@dataclass(frozen=True)
class GenSpec:
    name: str                     # module under runtime/synthetic-data/generators (has run(ctx))
    provides: frozenset           # schema keys this generator populates
    depends_on: frozenset = field(default_factory=frozenset)   # schema keys it reads


# Ordering derives from provides/depends_on; the list order is not authoritative.
GENERATORS = [
    GenSpec("customer", frozenset({"customer"})),
    GenSpec("trade_promotion",
            frozenset({"product", "store", "calendar", "transaction", "marketing", "promo"})),
    GenSpec("balancing_margin_and_volume", frozenset({"bmv"}),
            frozenset({"product", "calendar", "transaction", "store", "inventory"})),
    GenSpec("supplier_monitoring", frozenset({"supplier", "procurement"}),
            frozenset({"product", "store", "calendar"})),
    # calendar: inventory positions span the sales calendar (fiscal_calendar), not a fixed year.
    GenSpec("inventory", frozenset({"inventory"}),
            frozenset({"product", "store", "calendar"})),
    GenSpec("customer_ltv", frozenset({"order", "payment", "acu"}),
            frozenset({"customer", "product", "store", "calendar", "marketing", "promo", "bmv"})),
    GenSpec("logistics", frozenset({"logistics"}),
            frozenset({"supplier", "product", "store", "procurement"})),
    GenSpec("early_risk_detection", frozenset({"risk"}),
            frozenset({"logistics", "product"})),
    GenSpec("equipment", frozenset({"equipment"}),
            frozenset({"store"})),
    GenSpec("labor", frozenset({"labor"}),
            frozenset({"store"})),
    GenSpec("predictive_operations", frozenset({"predops"}),
            frozenset({"equipment", "store", "labor"})),
    # css BEFORE cmn: the footfall fact moved from CMN to CSS (ADR 0033), and CMN now
    # reads it through a view, so CMN gained a dependency it did not have before. The
    # topological sort enforces the order; this comment records WHY it exists.
    GenSpec("connected_store_signals", frozenset({"css"}),
            frozenset({"store", "calendar", "equipment", "product", "inventory", "logistics"})),
    GenSpec("commerce_media_networks", frozenset({"cmn"}),
            frozenset({"supplier", "customer", "product", "store", "order", "css"})),
    # No `calendar` dependency: fiscal_week_id is a DEGENERATE week key (fiscal_year*100 +
    # week), not a resolved FK into fiscal_calendar (whose PK is date_sk at day grain), so
    # the generator never reads the calendar schema.
    GenSpec("data_sharing_with_suppliers", frozenset({"dss"}),
            frozenset({"cmn", "supplier", "product"})),
    GenSpec("smarter_demand_and_inventory_decisions", frozenset({"sdi"}),
            frozenset({"product", "store", "inventory", "transaction"})),
    GenSpec("interaction", frozenset({"interaction"}),
            frozenset({"customer", "product", "store", "calendar"})),
    GenSpec("agentic_commerce", frozenset({"ac"}),
            frozenset({"customer", "product", "store", "inventory", "order"})),
    GenSpec("ai_assisted_store_associates", frozenset({"aasa"}),
            frozenset({"product", "store", "inventory", "labor", "customer"})),
    GenSpec("unified_customer_view", frozenset({"ucv"}),
            frozenset({"customer", "marketing"})),
]


def topo_sort(specs):
    """Deterministic topological order: a generator runs only after every generator
    that provides a schema it depends_on. Ties broken by declared list order."""
    order = {s.name: i for i, s in enumerate(specs)}
    provider = {}
    for s in specs:
        for key in s.provides:
            # provides sets must be disjoint: two writers of one schema key would make
            # the "runs after its provider" ordering ambiguous (last-writer-wins).
            if key in provider:
                raise ValueError(
                    f"schema key '{key}' is provided by both {provider[key]} and "
                    f"{s.name}; each schema key must have exactly one provider")
            provider[key] = s.name
    done, result = set(), []
    remaining = list(specs)
    while remaining:
        ready = [s for s in remaining
                 if all(provider.get(dep, dep) in done or dep not in provider
                        for dep in s.depends_on)]
        if not ready:
            unresolved = [s.name for s in remaining]
            raise ValueError(f"cyclic or unsatisfiable generator dependencies: {unresolved}")
        ready.sort(key=lambda s: order[s.name])
        nxt = ready[0]
        result.append(nxt)
        done.add(nxt.name)
        remaining.remove(nxt)
    return result


def waves(specs):
    """Deterministic Kahn dependency LEVELS for concurrent execution: a list of
    waves, each a list of GenSpecs with no dependency on any generator in the SAME
    or a LATER wave. Level 0 = generators whose depends_on are satisfied by nothing
    or by a pre-existing (never-provided-here) key; level k = generators all of whose
    providers live in levels < k. generate_all runs each wave in parallel, then waits
    before the next (a later wave reads an earlier wave's tables).

    Reuses topo_sort's provider-map + readiness logic; ties inside a wave break by
    declared list order, so the structure is fully deterministic. Raises the SAME
    ValueError as topo_sort on a duplicate provider or a cyclic/unsatisfiable graph.
    Concatenating the waves in order yields a valid topological order (cross-checked
    against topo_sort in tests)."""
    order = {s.name: i for i, s in enumerate(specs)}
    provider = {}
    for s in specs:
        for key in s.provides:
            # provides sets must be disjoint (same rule topo_sort enforces): two
            # writers of one schema key would make the wave assignment ambiguous.
            if key in provider:
                raise ValueError(
                    f"schema key '{key}' is provided by both {provider[key]} and "
                    f"{s.name}; each schema key must have exactly one provider")
            provider[key] = s.name
    done, levels = set(), []
    remaining = list(specs)
    while remaining:
        # A whole LEVEL at once: every remaining spec whose deps are all satisfied by
        # an EARLIER wave (or by a never-provided key). Providers in this same wave are
        # not yet in `done`, so mutually-independent generators land together.
        ready = [s for s in remaining
                 if all(provider.get(dep, dep) in done or dep not in provider
                        for dep in s.depends_on)]
        if not ready:
            unresolved = [s.name for s in remaining]
            raise ValueError(f"cyclic or unsatisfiable generator dependencies: {unresolved}")
        ready.sort(key=lambda s: order[s.name])
        levels.append(ready)
        for s in ready:
            done.add(s.name)
            remaining.remove(s)
    return levels


def _label_to_schema_keys():
    """Map a domain/package DIRECTORY label (what a PR's changed-files produce, and what
    apply_model_ddl/run_checks --domains use) to the schema KEY the registry indexes on.
    Derived from ordm_config.schema_defaults(): the token `<key>_schema`'s VALUE is exactly
    the directory slug (e.g. acu_schema=actionable_customer_understanding,
    promo_schema=promote_with_purpose, ucv_schema=unified_customer_view). So the inverse of
    that map turns a directory label into its schema key. Hyphen/underscore agnostic.

    Without this, `select()` matched only labels whose slug equals a generator name / provides
    key, so packages whose directory name differs (ACU->customer_ltv/acu, promo->
    trade_promotion/promo, unified-customer-view->no generator) raised ValueError and
    hard-failed the lean per-PR gate (AI review #108 H1)."""
    try:
        import os
        import sys
        here = os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0]))
        root = os.path.join(here, "..", "..", "..", "tools")
        if root not in sys.path:
            sys.path.insert(0, root)
        import ordm_config
        defaults = ordm_config.schema_defaults()
    except ImportError:
        # ordm_config genuinely not importable in this context: warn loudly rather than
        # silently degrade -- without the label->key map, a package label whose dir name
        # differs from its generator/key (ACU, promote-with-purpose) would resolve to a
        # no-op and its generator would be skipped when it should run (m2). Callers still
        # get {} (dir-label fallback in _dir_labels keeps such a token from erroring), but
        # the operator sees why generation for those packages was skipped.
        print("[ordm] WARNING: could not import ordm_config for the domain-label->schema-key "
              "map; package labels whose directory name differs from their generator name "
              "will not select their generator.", file=sys.stderr)
        return {}
    out = {}
    for token, slug in defaults.items():
        key = token[:-len("_schema")] if token.endswith("_schema") else token
        out[slug.replace("-", "_")] = key          # dir slug (underscored) -> schema key
    return out


def _dir_labels():
    """Every domain/package DIRECTORY label on disk (canonical-core/* and outcome-packages/*),
    normalized to underscores. This is the ground truth of what a PR's changed files can name
    -- including planned packages that have no schema variable and no generator yet -- so
    `select()` treats such a label as a real no-op token rather than a typo."""
    import glob
    import os
    import sys
    here = os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0]))
    repo = os.path.abspath(os.path.join(here, "..", "..", ".."))
    labels = set()
    for root in ("canonical-core", "outcome-packages"):
        for p in glob.glob(os.path.join(repo, root, "*")):
            if os.path.isdir(p):
                labels.add(os.path.basename(p).replace("-", "_"))
    return labels


def _gold_read_schema_keys(labels):
    """For each domain/package DIRECTORY label in `labels`, the set of schema KEYS its GOLD views
    READ (every `${<key>_schema}` token under that package's gold/*.sql). Used so generator
    selection covers not just a package's own generator + its generator-declared upstreams, but
    ALSO the generators that produce the tables its GOLD layer consumes.

    Motivating bug (daily-deploy + lean gate): early-risk-detection's gold (gold_inventory_risk,
    gold_control_tower) reads ${inventory_schema}.inventory_position, but the early_risk_detection
    GENERATOR's depends_on is only {logistics, product} -- so --include early-risk-detection never
    ran the inventory generator, leaving inventory_position EMPTY -> ERD's gold was wrong and
    freshness_all_feeds_present FAILed. The generator DAG models generator<->generator data deps,
    not the gold layer's cross-domain reads; this closes that gap for every package."""
    import glob
    import os
    import re
    import sys
    here = os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0]))
    repo = os.path.abspath(os.path.join(here, "..", "..", ".."))
    norm_labels = {str(x).replace("-", "_") for x in labels}
    ref_re = re.compile(r"\$\{(\w+)_schema\}")
    keys = set()
    for root in ("canonical-core", "outcome-packages"):
        for pkg in glob.glob(os.path.join(repo, root, "*")):
            if not os.path.isdir(pkg):
                continue
            if os.path.basename(pkg).replace("-", "_") not in norm_labels:
                continue
            for f in glob.glob(os.path.join(pkg, "gold", "*.sql")):
                with open(f) as fh:
                    keys.update(ref_re.findall(fh.read()))
    return keys


def select(specs, include=""):
    """Filter to an `include` subset (comma-separated schema keys, generator names, OR
    domain/package DIRECTORY labels) plus the transitive upstream generators they depend on.
    Empty => all.

    Tokens are normalized hyphen->underscore AND resolved through the directory-label ->
    schema-key map (see _label_to_schema_keys), so a PR's changed directory label -- in ANY
    of the three forms the lean CI gate might pass (dir slug like
    `actionable-customer-understanding`, schema key like `acu`, or generator name like
    `customer_ltv`) -- selects the right generator. This lets one changed-domains list feed
    all three tools without a hand-maintained vocabulary map (design/59; AI review #108 H1).

    A token that names a REAL domain/package which simply has NO generator (e.g.
    unified-customer-view ships no synthetic-data generator) is a benign no-op for THIS token
    (nothing to generate), NOT an error -- the apply + DQ steps still cover it. Only a token
    matching no domain/package at all (a genuine typo) raises."""
    if not include:
        return list(specs)

    def _norm(t):
        return t.strip().replace("-", "_")

    label_to_key = _label_to_schema_keys()
    by_name = {s.name: s for s in specs}
    provider = {k: s.name for s in specs for k in s.provides}
    # A token is resolvable if it is a generator name, a provides key, OR a known dir label.
    matchable = {s.name for s in specs} | set(provider)
    # Known labels = every real domain/package DIRECTORY on disk (the ground truth of what a
    # PR can touch), not just those with a schema token. A planned package with no schema var
    # and no generator (agentic-commerce, ai-assisted-store-associates) is still a real,
    # no-op-if-no-generator label -- it must not raise (AI review #108 H1).
    known_labels = set(label_to_key) | _dir_labels()

    # A generator name or provides key also maps back to a package dir label (for gold reads):
    # e.g. the generator `early_risk_detection` and the key `risk` both belong to the
    # early_risk_detection package. Build key/name -> dir-label so requested_labels is populated
    # no matter WHICH form the token took.
    key_to_label = {v: k for k, v in label_to_key.items()}   # schema key -> dir label
    name_to_label = {}
    for s in specs:
        for key in s.provides:
            if key in key_to_label:
                name_to_label[s.name] = key_to_label[key]
                break

    wanted = set()
    requested_labels = set()                    # dir labels named in the request (for gold reads)
    unknown = []
    for raw in include.split(","):
        if not raw.strip():
            continue
        tok = _norm(raw)
        if tok in matchable:
            wanted.add(tok)                     # generator name or provides key directly
            # also record the package this generator/key belongs to, so its gold reads expand
            lbl = name_to_label.get(tok) or key_to_label.get(tok)
            if lbl:
                requested_labels.add(lbl)
        elif tok in label_to_key:
            wanted.add(label_to_key[tok])       # dir label -> its schema key
            requested_labels.add(tok)
        elif tok in known_labels:
            requested_labels.add(tok)           # real label, maybe no generator -> still gold-read
        else:
            unknown.append(raw.strip())
    if unknown:
        raise ValueError(
            f"--include token(s) matched no domain/package: {sorted(unknown)}. "
            f"Valid: generator names, provides keys, or directory labels {sorted(known_labels)}.")

    # A requested package's GOLD layer may read tables from OTHER domains its generator does not
    # declare as a dependency (e.g. early-risk-detection's gold reads inventory_position, but the
    # ERD generator's depends_on is only {logistics, product}). Add every schema key those gold
    # views read to `wanted`, so the closure below pulls in the generators that PRODUCE them --
    # otherwise the package's gold + its DQ checks run against empty cross-domain tables.
    for key in _gold_read_schema_keys(requested_labels):
        if key in provider:                     # only keys some generator actually produces
            wanted.add(key)

    keep, stack = set(), []
    for s in specs:
        if s.name in wanted or (s.provides & wanted):
            stack.append(s.name)
    while stack:
        name = stack.pop()
        if name in keep:
            continue
        keep.add(name)
        for dep in by_name[name].depends_on:
            if dep in provider:
                stack.append(provider[dep])
    return [s for s in specs if s.name in keep]


def _key_to_dir_label():
    """Inverse of the schema-key resolution: schema KEY -> the on-disk domain/package DIRECTORY
    label (hyphenated, as apply_model_ddl --domains matches via _domain_of). Built from
    schema_defaults() (key `<x>_schema` -> slug value) and the real dirs on disk, so a slug that
    differs from its dir (e.g. order_schema=orders but the dir is `order`) still resolves. A key
    with no matching dir is omitted (it simply won't widen the DDL set)."""
    import glob
    import os
    import sys
    here = os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0]))
    repo = os.path.abspath(os.path.join(here, "..", "..", ".."))
    dirs = {}
    for root in ("canonical-core", "outcome-packages"):
        for p in glob.glob(os.path.join(repo, root, "*")):
            if os.path.isdir(p):
                base = os.path.basename(p)
                dirs[base.replace("-", "_")] = base       # normalized -> real (hyphenated) dir
    root_tools = os.path.join(here, "..", "..", "..", "tools")
    if root_tools not in sys.path:
        sys.path.insert(0, root_tools)
    try:
        import ordm_config
        defaults = ordm_config.schema_defaults()
    except ImportError:
        defaults = {}
    out = {}
    for token, slug in defaults.items():
        key = token[:-len("_schema")] if token.endswith("_schema") else token
        norm = str(slug).replace("-", "_")
        if norm in dirs:
            out[key] = dirs[norm]
        elif key in dirs:                                 # slug!=dir (orders vs order): fall back to key
            out[key] = dirs[key]
    # Any provides key whose name IS a dir but has no schema token (safety): map it to itself.
    for norm, real in dirs.items():
        out.setdefault(norm, real)
    return out


def generator_domains(specs, include=""):
    """The set of domain/package DIRECTORY labels that the generators selected by `include`
    actually WRITE to -- i.e. every `provides` schema key of every selected generator, mapped to
    its on-disk dir label. The lean gate passes this to apply_model_ddl --domains so the DDL
    step creates EXACTLY the tables generate_all will populate (AI review #108 / daily-deploy:
    trade_promotion provides core keys that early-risk-detection depends on, but ALSO writes
    promote_with_purpose.promotion_scope -- which a narrow `--domains early-risk-detection` never
    created, so generate_all hit TABLE_OR_VIEW_NOT_FOUND). Empty include => all labels on disk
    (matches select()'s "empty => all")."""
    key_to_dir = _key_to_dir_label()
    selected = select(specs, include)
    labels = set()
    for s in selected:
        for key in s.provides:
            if key in key_to_dir:
                labels.add(key_to_dir[key])
    return labels
