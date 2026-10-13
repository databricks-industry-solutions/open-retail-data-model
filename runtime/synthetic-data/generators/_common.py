# ============================================================
# ORDM · Synthetic data · shared generator helpers
# Version: 0.5
# Generated: 2026-06-09
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-06-09
# ============================================================
# Engine helpers shared by every domain/use-case generator (customer,
# trade promotion, …). Kept in one place so generators extend rather than
# fork the framework. Pure PySpark; no hardcoded catalog/schema.
# ============================================================

import os
import sys
import uuid

from pyspark.sql import functions as F
from pyspark.sql.window import Window

RECORD_SOURCE = "synthetic-generator"

# Single source of truth for the canned behavioral segment ids (m2). trade_promotion
# WRITES these definitions to marketing.audience; customer_ltv assigns segment_membership
# to them. Both import this list so the id set can never drift between the two generators
# (a mismatch would silently orphan membership rows, caught only at DQ-check time).
BEHAVIORAL_SEGMENT_IDS = [
    "SEG-HIGH-VALUE-REPEAT", "SEG-LAPSING", "SEG-CHURNED-WINBACK", "SEG-NEW-TO-BRAND",
    "SEG-DISCOUNT-DRIVEN", "SEG-FULL-PRICE-LOYAL", "SEG-VIP", "SEG-AT-RISK-HIGH-VALUE",
]

# Shelf-space response (shared by trade_promotion and balancing_margin_and_volume). The sales
# fact is written by trade_promotion BEFORE the BMV generator writes the planogram, so neither
# can read the other's output. Both derive a product x store's shelf facings from the same pure
# function of the keys, and sales units scale by (facings / reference) ** elasticity, so the
# planogram the BMV generator records is the allocation the sales actually responded to. The
# per-category elasticities are the ground truth gold_assortment_optimization.space_elasticity
# is checked against. Values sit around the 0.17 meta-analytic average (Eisend 2014, Journal of
# Retailing 90(2)), lower for staples and higher for impulse categories, as that study reports.
SHELF_SPACE_SEED = 4242
SHELF_FACINGS_MAX = 5           # facings drawn uniformly from 1..5
SHELF_FACINGS_REFERENCE = 3     # facings at which the space multiplier is 1.0
SPACE_ELASTICITY_BY_CATEGORY = {
    "beverages": 0.22, "snacks": 0.28, "dairy": 0.12,
    "bakery": 0.18, "household": 0.10, "personal_care": 0.15,
}
SPACE_ELASTICITY_DEFAULT = 0.17


def shelf_facings(product_col="product_id", store_col="store_id"):
    """Deterministic shelf facings (1..SHELF_FACINGS_MAX) for a product x store."""
    return _count_1_to_max(SHELF_FACINGS_MAX, SHELF_SPACE_SEED, "shelf_facings", product_col, store_col)


def shelf_space_multiplier(category_col="category", product_col="product_id", store_col="store_id"):
    """Units multiplier (facings / reference) ** elasticity(category) for a product x store."""
    pairs = []
    for cat, e in SPACE_ELASTICITY_BY_CATEGORY.items():
        pairs += [F.lit(cat), F.lit(float(e))]
    elasticity = F.coalesce(F.create_map(*pairs)[F.col(category_col)], F.lit(SPACE_ELASTICITY_DEFAULT))
    ratio = shelf_facings(product_col, store_col).cast("double") / F.lit(float(SHELF_FACINGS_REFERENCE))
    return F.pow(ratio, elasticity)


def _argv_param(name, default=None):
    """Read `--name value` or `--name=value` from argv (for a spark_python_task)."""
    flag = "--" + name
    argv = sys.argv[1:]
    for i, arg in enumerate(argv):
        if arg == flag and i + 1 < len(argv):
            return argv[i + 1]
        if arg.startswith(flag + "="):
            return arg[len(flag) + 1:]
    return default


def get_param(name, default=None):
    """Read a parameter in priority order: notebook widget on Databricks, else env,
    else a `--name` command-line flag (so a generator also runs as a
    spark_python_task in a DAB job), else default."""
    try:
        return dbutils.widgets.get(name)  # noqa: F821 (injected in notebooks)
    except Exception:
        pass
    if name.upper() in os.environ:
        return os.environ[name.upper()]
    return _argv_param(name, default)


def load_domain_config(domain):
    """Return the seeds.yaml config dict for a domain (volumes/fanout/seed), or {}."""
    path = os.path.join(os.path.dirname(__file__), "..", "seeds.yaml")
    try:
        import yaml
        with open(path) as fh:
            data = yaml.safe_load(fh) or {}
        return (data.get("domains", {}) or {}).get(domain, {}) or {}
    except Exception:
        return {}


# ---- deterministic helpers (order-independent: pure functions of keys+seed) ----

def _pick(arr, seed, salt, *keys):
    """Deterministically pick an element of `arr` from the given keys."""
    n = len(arr)
    idx = (F.abs(F.hash(*keys, F.lit(salt), F.lit(seed))) % F.lit(n)).cast("int")
    return F.element_at(F.array(*[F.lit(v) for v in arr]), idx + F.lit(1))


def _frac(seed, salt, *keys):
    """Deterministic pseudo-random fraction in [0,1)."""
    return (F.abs(F.hash(*keys, F.lit(salt), F.lit(seed))) % F.lit(10000)) / F.lit(10000.0)


def _count_1_to_max(maximum, seed, salt, *keys):
    """Deterministic integer in [1, maximum]."""
    return (F.abs(F.hash(*keys, F.lit(salt), F.lit(seed))) % F.lit(maximum)).cast("int") + F.lit(1)


def stamp_scd2_history(df, durable_key_cols, origin_from, seed, *,
                       multiversion_pct=0.0, max_versions=3,
                       window_start=None, window_end=None, mutate=None):
    """Turn a single-version master frame into a testable SCD2 history frame.

    The legacy `_stamp_scd2` stamps every row as one open, current version
    (effective_to_date = NULL, is_current = TRUE), so downstream `GROUP BY _sk`
    equals `GROUP BY _id`, every fact->history join is 1:1, and the whole SCD2
    defect class is invisible to CI. This helper instead gives a deterministic
    hashed fraction of entities (`multiversion_pct`) two or more contiguous
    versions:

      * the chain is HALF-OPEN and gap-free: version i is [from_i, from_{i+1}),
        the last version is [from_last, NULL) with is_current = TRUE, and exactly
        one row per entity is current;
      * version cut-points land INSIDE the fact date window
        [window_start, window_end) so a fact dated after a cut references the new
        version and a fact before it references the old one (a boundary before the
        window would produce zero fragmentation and defeat the test);
      * each new version gets its own IDENTITY `_sk` at write time (the helper
        emits the business columns only; Delta assigns `_sk`), and `mutate`
        (col -> Spark Column expression given the version index `_ver`) changes the
        attributes that must differ across versions (subcategory, list_price, ...).

    `multiversion_pct = 0.0` reproduces the legacy single-version output exactly
    (one current row per entity), so the knob is safe to default off. The fraction
    is a pure function of (durable_key_cols, seed) — order-independent and stable
    across runs. `origin_from` is the first version's effective_from_date.
    """
    from pyspark.sql import functions as F

    if not multiversion_pct or max_versions < 2:
        # legacy behaviour: a single open current version per entity. Set the
        # effective-from first, then derive the audit block from it.
        single = (df
                  .withColumn("effective_from_date", F.lit(origin_from).cast("date"))
                  .withColumn("effective_to_date", F.lit(None).cast("date"))
                  .withColumn("is_current", F.lit(True)))
        return _scd2_audit(single, "effective_from_date")

    if window_start is None or window_end is None:
        raise ValueError("stamp_scd2_history needs window_start/window_end when "
                         "multiversion_pct > 0 (cut-points must land in the fact window)")

    # How many versions this entity gets: 1 for the majority, 2..max for the
    # deterministically-selected fraction. Order-independent (hash of the key).
    frac = _frac(seed, "scd2_pick", *durable_key_cols)
    extra = _count_1_to_max(max_versions - 1, seed, "scd2_nver", *durable_key_cols)
    n_versions = F.when(frac < F.lit(float(multiversion_pct)), F.lit(1) + extra).otherwise(F.lit(1))

    ws = F.lit(window_start).cast("date")
    we = F.lit(window_end).cast("date")
    span = F.datediff(we, ws)  # window length in days; cut-points fall strictly inside

    # Explode each entity into 0..n_versions-1 rows, one per version.
    exploded = (df
                .withColumn("_n_versions", n_versions)
                .withColumn("_ver", F.explode(F.sequence(F.lit(0), F.col("_n_versions") - F.lit(1)))))

    # Version 0 starts at origin_from; versions 1..k-1 start at evenly-spaced
    # cut-points strictly inside the window: cut_i = window_start + i/n * span.
    cut = F.date_add(ws, (F.col("_ver") * span / F.col("_n_versions")).cast("int"))
    eff_from = F.when(F.col("_ver") == 0, F.lit(origin_from).cast("date")).otherwise(cut)
    # Next version's start = this version's end (exclusive); last version is open.
    next_cut = F.date_add(ws, ((F.col("_ver") + F.lit(1)) * span / F.col("_n_versions")).cast("int"))
    is_last = F.col("_ver") == (F.col("_n_versions") - F.lit(1))
    eff_to = F.when(is_last, F.lit(None).cast("date")).otherwise(next_cut)

    out = (exploded
           .withColumn("effective_from_date", eff_from)
           .withColumn("effective_to_date", eff_to)
           .withColumn("is_current", is_last))
    # Re-derive the audit block from the (now per-version) effective_from_date.
    out = _scd2_audit(out, "effective_from_date")
    if mutate:
        for col, expr in mutate.items():
            out = out.withColumn(col, expr(F.col("_ver")))
    return out.drop("_n_versions", "_ver")


def resolve_scd2_asof(fact_df, dim_history_df, event_date_col, durable_key, sk_col,
                      extra_cols=None):
    """Resolve the version-in-effect `_sk` (and optional attributes) onto a fact
    AS OF its event date, via a single broadcast half-open range join — the
    Kimball surrogate-key pipeline done once at generation time, so downstream
    gold does a plain equi-join, never a query-time range join.

    NOT YET WIRED: shipped by the prevention-scaffold PR but called by no live
    generator here; the fix-the-views PR wires it in (with the orphan/count guard
    noted below) when it flips `multiversion_pct` on. Covered now by
    tests/test_scd2_history.py so it cannot rot before then.

    For each fact row, the dimension version whose
    [effective_from_date, effective_to_date) contains `event_date_col` supplies
    `sk_col` (+ any `extra_cols`). The dimension is broadcast (conformed dims are
    small). Deterministic and non-expanding: the half-open chain guarantees at most
    one matching version per key+date. Replaces the pattern of attaching only the
    current `_sk`, which never exercises historical-version resolution.

    Pre-window behavior: this is a LEFT join, so a fact whose `event_date_col`
    precedes the earliest `effective_from_date` for its key (or matches no interval)
    gets a NULL `sk_col` — there is exactly one matching version only when the fact
    date is >= the earliest version start. When this is wired into the live
    generators (a later PR), the caller must ensure the origin version starts on or
    before the fact window and add an orphan/count guard (or an INNER join) so a
    NULL-resolved surrogate never silently drops fact rows downstream."""
    from pyspark.sql import functions as F

    cols = [durable_key, sk_col, "effective_from_date", "effective_to_date", *(extra_cols or [])]
    dim = dim_history_df.select(*dict.fromkeys(cols))  # de-dup while preserving order
    ev = F.col(f"f.{event_date_col}")
    cond = (
        (F.col(f"f.{durable_key}") == F.col(f"d.{durable_key}"))
        & (ev >= F.col("d.effective_from_date"))
        & (F.col("d.effective_to_date").isNull() | (ev < F.col("d.effective_to_date")))
    )
    picked = [F.col(f"d.{c}").alias(c) for c in [sk_col, *(extra_cols or [])]]
    return (fact_df.alias("f")
            .join(F.broadcast(dim.alias("d")), cond, "left")
            .select("f.*", *picked))


def _scd2_audit(df, eff_from_col):
    """Attach the standard SCD2 audit block, derived from the effective-from date
    (created/source-updated approximated by the version instant; load is now)."""
    from pyspark.sql import functions as F
    return (df
            .withColumn("created_timestamp", F.col(eff_from_col).cast("timestamp"))
            .withColumn("source_updated_timestamp", F.col(eff_from_col).cast("timestamp"))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def attach_random_dim(fact_df, dim_df, dim_count, salt, seed, *key_cols):
    """Attach a deterministically-chosen row of `dim_df` to each fact row via a
    BROADCAST join on a hashed dense index.

    Scales with the fact table -- no driver-side .collect() of dimension ids and
    no per-row array literal (unlike _pick). `dim_df` must be small enough to
    broadcast (true for conformed dimensions); `dim_count` is its row count
    (a cheap COUNT, not a collect). `dim_df` columns must not collide with the
    fact's columns. Deterministic for a given (key_cols, salt, seed, dim order).
    """
    indexed = dim_df.withColumn("_ord_idx", F.row_number().over(Window.orderBy(*dim_df.columns)) - F.lit(1))
    pick_idx = F.abs(F.hash(*key_cols, F.lit(salt), F.lit(seed))) % F.lit(max(1, int(dim_count)))
    return (fact_df.withColumn("_pick_idx", pick_idx)
            .join(F.broadcast(indexed), F.col("_pick_idx") == F.col("_ord_idx"), "inner")
            .drop("_pick_idx", "_ord_idx"))


def _write(spark, df, fqtn, columns, mode, merge_keys=None):
    """Write the non-identity columns to a Delta table; Delta assigns the
    IDENTITY *_sk. Modes:
      overwrite (default) - INSERT OVERWRITE (idempotent full reload)
      append              - INSERT INTO
      merge               - MERGE upsert on `merge_keys` (idempotent incremental,
                            uses deletion vectors for the row-level updates)
    """
    # A UNIQUE per-call staging view name: generators in the same dependency wave now
    # run CONCURRENTLY on the one shared SparkSession (generate_all waves), and a
    # session-global fixed name ("ordm_gen_tmp") would let two concurrent _write calls
    # clobber each other's view between createOrReplaceTempView and the INSERT..SELECT.
    # A uuid-suffixed name is unique per call, so concurrent writers never collide.
    tmp = "ordm_gen_tmp_" + uuid.uuid4().hex
    df.select(*columns).createOrReplaceTempView(tmp)
    col_list = ", ".join(columns)
    try:
        if mode == "merge":
            if not merge_keys:
                raise ValueError("mode='merge' requires merge_keys")
            on = " AND ".join(f"t.{k} = s.{k}" for k in merge_keys)
            set_clause = ", ".join(f"t.{c} = s.{c}" for c in columns)
            ins_vals = ", ".join(f"s.{c}" for c in columns)
            spark.sql(f"MERGE INTO {fqtn} t USING {tmp} s ON {on} "
                      f"WHEN MATCHED THEN UPDATE SET {set_clause} "
                      f"WHEN NOT MATCHED THEN INSERT ({col_list}) VALUES ({ins_vals})")
        elif mode == "append":
            spark.sql(f"INSERT INTO {fqtn} ({col_list}) SELECT {col_list} FROM {tmp}")
        else:
            spark.sql(f"INSERT OVERWRITE TABLE {fqtn} ({col_list}) SELECT {col_list} FROM {tmp}")
    finally:
        spark.catalog.dropTempView(tmp)
    result = spark.table(fqtn)
    # Surface the "green but empty" case: an overwrite that lands 0 rows almost
    # always means an upstream master this generator reads was unpopulated (a
    # generator-ordering problem). Warn loudly rather than pass silently; a
    # data-quality COUNT(*) check treats an empty table as PASS, so this is the
    # signal that would otherwise be lost. Use a cheap emptiness probe (LIMIT 1)
    # instead of a full result.count(): count() is a second full Spark action on
    # every overwrite (~81 writes = ~81 extra scans); DataFrame.isEmpty() (Spark
    # 3.3+) / take(1) short-circuit after the first row.
    if mode == "overwrite" and _is_empty(result):
        print(f"[ordm] WARNING: {fqtn} written EMPTY (0 rows) — an upstream master "
              "it reads is likely unpopulated; check generator ordering.")
    return result


def _is_empty(df):
    """True if `df` has no rows, WITHOUT a full count(). Prefer DataFrame.isEmpty()
    (Spark 3.3+); fall back to a LIMIT-1 take() on older runtimes. Both stop after
    the first row instead of scanning/aggregating the whole table."""
    try:
        return df.isEmpty()
    except AttributeError:
        return len(df.take(1)) == 0
