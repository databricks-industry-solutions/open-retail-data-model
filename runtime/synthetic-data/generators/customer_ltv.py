# ============================================================
# ORDM · Synthetic data · Customer Lifetime Value generator
# Version: 0.5
# Generated: 2026-06-09
# LLM-generated: true (maintainer-reviewed before release)
# Last reviewed: 2026-07-17 by @alexxx-db
# ============================================================
# Populates the canonical-core customer_order_line fact with a realistic,
# SKEWED value distribution: most customers have few orders (long low-value
# tail), a few have many (high-value head), so CLV tiers and RFM quintiles
# populate meaningfully. Orders/customer ~ max * u^value_skew (configurable).
#
# Beyond order lines it emits the payment fact (the tender/settlement side of
# each order) across the FULL lifecycle — every payment_type (sale / refund /
# adjustment / chargeback) and every payment_status (authorized / captured /
# settled / declined / refunded / voided) — and behavioral-segment membership.
#
# Reuses the customer profile dimension (run the customer generator first) and
# product / store / fiscal_calendar (run the trade_promotion generator first).
# Shared helpers come from _common (extended, not forked).
# ============================================================

import os
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

try:
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _frac, _pick, _write,
                         attach_random_dim, BEHAVIORAL_SEGMENT_IDS)
    from _market_analysis import generate_market_analysis
except ImportError:  # ensure sibling modules are importable when run as a notebook
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__ if "__file__" in globals() else sys.argv[0])))
    from _common import (RECORD_SOURCE, get_param, load_domain_config, _frac, _pick, _write,
                         attach_random_dim, BEHAVIORAL_SEGMENT_IDS)
    from _market_analysis import generate_market_analysis

# Column contracts — MUST match the DDL (minus IDENTITY *_sk).
# Verified against the DDL by tests/test_customer_ltv.py.
CUSTOMER_ORDER_LINE_COLUMNS = [
    "order_line_id", "order_id", "profile_sk", "profile_id", "product_sk",
    "product_id", "store_sk", "store_id", "order_date", "event_timestamp", "units",
    "gross_amount", "net_amount", "currency_code", "transaction_currency_code",
    "record_source", "load_timestamp",
]
PAYMENT_COLUMNS = [
    "payment_id", "order_id", "profile_sk", "profile_id", "payment_type",
    "payment_method", "payment_status", "amount", "currency_code",
    "transaction_currency_code", "event_timestamp", "record_source", "load_timestamp",
]
PAYMENT_METHODS = ["card", "cash", "wallet", "bank_transfer", "gift_card", "voucher"]
SEGMENT_MEMBERSHIP_COLUMNS = [
    "segment_membership_id", "profile_id", "audience_id", "as_of_date",
    "membership_status", "membership_score", "assignment_method", "model_version",
    # append-only event-log audit block (§8): record_source + load_timestamp only.
    "record_source", "load_timestamp",
]
# BEHAVIORAL_SEGMENT_IDS (the canned segment_definition ids seeded in marketing.audience by
# the trade_promotion generator) is imported from _common — single source of truth (m2), so
# the membership assignment here can never drift from the definitions written there.


def load_config():
    c = load_domain_config("customer_ltv")
    vols = c.get("volumes", {}) or {}
    return {
        "seed": c.get("seed", 4004),
        "max_orders": vols.get("max_orders_per_customer", 40),
        "value_skew": vols.get("value_skew", 4.0),
        "lines_per_order_max": vols.get("lines_per_order_max", 4),
        # Product Affinity co-purchase seeding (see build_order_lines). Fallback DISABLED (0):
        # only an explicit seeds.yaml entry turns it on, so the shared order fact stays neutral
        # unless a maintainer opts in.
        "affinity_copurchase_denom": vols.get("affinity_copurchase_denom", 0),
        "affinity_pair_count": vols.get("affinity_pair_count", AFFINITY_PAIR_COUNT),
        # Payment-event rates (share of orders). Defaults chosen so seeds.yaml
        # needs no change; override under domains.customer_ltv.volumes if desired.
        "refund_rate": vols.get("refund_rate", 0.12),
        "declined_rate": vols.get("declined_rate", 0.04),
        "voided_rate": vols.get("voided_rate", 0.02),
        "adjustment_rate": vols.get("adjustment_rate", 0.03),
        "chargeback_rate": vols.get("chargeback_rate", 0.015),
    }


# Light, seed-deterministic co-purchase seeding for the Product Affinity demo — OPT-IN and
# SCOPED. ORDM's baskets are otherwise uniform-random, so gold_product_affinity_pairwise
# ("frequently bought together") would be empty. When ENABLED (affinity_denom > 0, set via
# seeds.yaml domains.customer_ltv.volumes.affinity_copurchase_denom), ~1-in-affinity_denom
# MULTI-LINE baskets have their first two lines forced to a fixed, seeded product pair (a stable
# anchor/partner per pair id), seeding real co-occurrence so the surface populates. DISABLED by default
# (affinity_denom = 0): the shared core order fact is then byte-for-byte a pure uniform draw, so
# CLV / Behavioral Segmentation / Market Analysis see neutral demo data unless a maintainer
# explicitly turns the seeding on in config. This keeps a Product-Affinity demo need from
# silently reshaping unrelated packages' synthetic data.
AFFINITY_PAIR_COUNT = 8   # default number of distinct seeded pairs (capped at n_products // 2)

# Store refund tier: deterministic allocation of stores into tiers with multipliers
# applied to the base refund_rate to inject realistic store-level variance into payment leakage.
# Shares sum to 1.0 by construction; multipliers scale the refund probability.
REFUND_STORE_TIER_SHARES = {
    "HIGH": 0.20,      # 20% of stores: high refund propensity
    "NORMAL": 0.60,    # 60% of stores: baseline
    "LOW": 0.20,       # 20% of stores: low refund propensity
}
REFUND_STORE_TIER_MULTIPLIER = {
    "HIGH": 2.0,       # 2x baseline refund_rate
    "NORMAL": 1.0,     # 1x baseline refund_rate
    "LOW": 0.5,        # 0.5x baseline refund_rate
}

# Adjustments orphan share: deterministic fraction of adjustments that carry NULL order_id
# (the warn-path in payment_order_orphan check). The rest carry a valid order_id.
ADJUSTMENT_ORPHAN_SHARE = 0.2  # 20% orphaned, 80% linked to orders


def refund_store_multiplier(store_col):
    """Deterministic refund-rate multiplier for a store, based on tier assignment.

    Tiers are assigned by hash(store_id) so every store consistently maps to the same
    tier across runs. Returns the multiplier to apply to the base refund_rate.

    Args:
        store_col: A Spark Column expression for store_id (typically F.col("store_id")).

    Returns:
        A Spark Column expression with the tier multiplier (HIGH: 2.0, NORMAL: 1.0, LOW: 0.5).
    """
    # Determine tier by hash: cumulative fractions of REFUND_STORE_TIER_SHARES
    # HIGH: [0.0, 0.20), NORMAL: [0.20, 0.80), LOW: [0.80, 1.0)
    # Fixed seed (not the configured payment seed) on purpose: a store keeps its tier when seeds.yaml
    # changes, so the known-truth tier table stays stable for tests and demos.
    tier_frac = _frac(4004, "store_tier", store_col)
    return (
        F.when(tier_frac < F.lit(REFUND_STORE_TIER_SHARES["HIGH"]),
               F.lit(REFUND_STORE_TIER_MULTIPLIER["HIGH"]))
         .when(tier_frac < F.lit(REFUND_STORE_TIER_SHARES["HIGH"] + REFUND_STORE_TIER_SHARES["NORMAL"]),
               F.lit(REFUND_STORE_TIER_MULTIPLIER["NORMAL"]))
         .otherwise(F.lit(REFUND_STORE_TIER_MULTIPLIER["LOW"]))
    )


def build_order_lines(spark, profiles_current, products_current, stores_current,
                      start_date, n_days, seed, max_orders, value_skew, lines_per_order_max,
                      base_currency, affinity_denom=0, affinity_pair_count=AFFINITY_PAIR_COUNT):
    start = F.lit(start_date)
    prod_dim = products_current.select("product_sk", "product_id", "list_price")
    store_dim = stores_current.select("store_sk", "store_id")
    n_products, n_stores = prod_dim.count(), store_dim.count()

    # orders per customer from a skewed draw: most low, a few high.
    customers = (profiles_current.select("profile_sk", "profile_id")
                 .withColumn("_u", _frac(seed, "vol", "profile_id"))
                 .withColumn("orders_count",
                             F.greatest(F.ceil(F.lit(float(max_orders))
                                               * F.pow(F.col("_u"), F.lit(float(value_skew)))).cast("int"),
                                        F.lit(1))))

    orders = (customers
              .withColumn("order_idx", F.explode(F.expr("sequence(1, orders_count)")))
              .withColumn("order_id", F.concat_ws("-", F.lit("ORD"), F.col("profile_id"), F.col("order_idx")))
              .withColumn("_oh", F.abs(F.hash("profile_id", "order_idx", F.lit(seed))))
              .withColumn("order_date", F.date_add(start, (F.col("_oh") % F.lit(max(1, n_days))).cast("int")))
              .withColumn("n_lines", (F.col("_oh") % F.lit(max(1, lines_per_order_max)) + F.lit(1)).cast("int")))
    # ship-to store per order via broadcast join (no driver collect / array literal)
    orders = attach_random_dim(orders, store_dim, n_stores, "store", seed, "profile_id", "order_idx")

    lines = (orders
             .withColumn("line_idx", F.explode(F.expr("sequence(1, n_lines)")))
             .withColumn("units",
                         (F.abs(F.hash("profile_id", "order_idx", "line_idx", F.lit(seed))) % F.lit(5) + F.lit(1)).cast("int")))
    # product per line. When co-purchase seeding is DISABLED (affinity_denom <= 0) this is the
    # plain uniform pick — identical to the historic behaviour, so the core fact is neutral. When
    # ENABLED, non-themed lines still use that exact pick (same hash + same dim index), and only
    # the first two lines of themed multi-line baskets are forced to a seeded affinity pair,
    # populating gold_product_affinity_pairwise in the demo.
    # Neutral base pick for EVERY line — the plain uniform, deterministic pick (identical to the
    # historic behaviour, so with seeding off the core fact is byte-for-byte unchanged).
    lines = attach_random_dim(lines, prod_dim, n_products, "prod", seed, "profile_id", "order_idx", "line_idx")
    if affinity_denom and affinity_denom > 0:
        # Seeding ON: override ONLY the first two lines of themed multi-line baskets with a stable
        # (anchor, partner) product pair, so those pairs co-occur and gold_product_affinity_pairwise
        # populates. The pair products are picked by ROUTING THROUGH attach_random_dim again (the
        # same broadcast-join helper as the base pick — no bespoke global window), keyed per
        # (role, pair_id) so each pair_id maps to one stable anchor and one stable partner.
        num_pairs = max(1, min(affinity_pair_count, n_products // 2))
        themed = (F.abs(F.hash("profile_id", "order_idx", F.lit("affinity"), F.lit(seed)))
                  % F.lit(int(affinity_denom))) == F.lit(0)
        pair_id = F.abs(F.hash("profile_id", "order_idx", F.lit("pair"), F.lit(seed))) % F.lit(num_pairs)
        is_pair_line = themed & (F.col("n_lines") >= F.lit(2)) & F.col("line_idx").isin(1, 2)
        # role|pair for the two seeded lines; a per-line-unique key otherwise (that pick is unused).
        lines = lines.withColumn(
            "_aff_key",
            F.when(is_pair_line & (F.col("line_idx") == F.lit(1)),
                   F.concat(F.lit("anchor|"), pair_id.cast("string")))
             .when(is_pair_line & (F.col("line_idx") == F.lit(2)),
                   F.concat(F.lit("partner|"), pair_id.cast("string")))
             .otherwise(F.concat_ws("|", F.lit("_"), F.col("profile_id"),
                                    F.col("order_idx").cast("string"), F.col("line_idx").cast("string"))))
        # Alias the dim columns so the second attach doesn't collide with the base product columns;
        # the ordering (and thus the pick per key) matches the base pick's dimension index.
        aff_dim = prod_dim.selectExpr("product_sk AS _aff_sk", "product_id AS _aff_id", "list_price AS _aff_price")
        lines = attach_random_dim(lines, aff_dim, n_products, "aff", seed, "_aff_key")
        lines = (lines
                 .withColumn("product_sk", F.when(is_pair_line, F.col("_aff_sk")).otherwise(F.col("product_sk")))
                 .withColumn("product_id", F.when(is_pair_line, F.col("_aff_id")).otherwise(F.col("product_id")))
                 .withColumn("list_price", F.when(is_pair_line, F.col("_aff_price")).otherwise(F.col("list_price")))
                 .drop("_aff_key", "_aff_sk", "_aff_id", "_aff_price"))
    lines = (lines
             .withColumn("gross_amount", F.round(F.col("units") * F.col("list_price"), 2))
             # net = gross less a 0-20% discount draw
             .withColumn("net_amount",
                         F.round(F.col("gross_amount")
                                 * (F.lit(1.0) - _frac(seed, "disc", "profile_id", "order_idx", "line_idx") * F.lit(0.2)), 2))
             # Amounts are in the reporting/base currency; consumer orders are
             # transacted in the home market (= base).
             .withColumn("currency_code", F.lit(base_currency))
             .withColumn("transaction_currency_code", F.lit(base_currency))
             .withColumn("order_line_id",
                         F.concat_ws("-", F.lit("ORDL"), F.col("profile_id"), F.col("order_idx"), F.col("line_idx")))
             # Event-time (UTC): the order date plus a deterministic intraday hour.
             .withColumn("event_timestamp",
                         F.expr("cast(order_date as timestamp) + make_interval(0, 0, 0, 0, "
                                "cast(abs(hash(profile_id, order_idx, line_idx)) % 24 as int))"))
             .withColumn("record_source", F.lit(RECORD_SOURCE))
             .withColumn("load_timestamp", F.current_timestamp()))
    return lines


def build_payments(spark, order_lines, base_currency, seed, cfg):
    """Emit the payment fact across the FULL lifecycle so every value in the
    payment_type and payment_status CHECK domains is exercised on seed data:

      * a successful sale on every order, its settlement status mixed across
        captured (70%) / settled (20%) / authorized (10%);
      * a small share of declined and voided sale attempts (failed tenders);
      * partial refunds at a rate modulated by store refund tier (HIGH: 2x, NORMAL: 1x, LOW: 0.5x),
        30% of the order amount, a couple of days later;
      * post-sale adjustments: 80% carry a valid order_id, 20% carry NULL order_id to exercise
        the documented warn-path of payment_order_orphan;
      * card-only chargebacks weeks later.

    Refunds, adjustments and chargebacks are drawn only from orders whose sale was captured
    or settled (money actually taken); a full chargeback never lands on an order that was already
    partially refunded, and no adjustment lands on a charged-back order, so no order is reversed
    beyond what was collected. The expected
    refund share of a store's settled sales is refund_rate x its tier multiplier x 0.3.

    Rates are seed-stable (hash-salted _frac, no rand()) and come from config
    with safe defaults; the per-order payment_method is drawn once and shared
    across every event of that order. Refund rate is multiplied by a deterministic
    store-tier factor for realistic leakage variance. Amounts stay non-negative magnitudes;
    direction is carried by payment_type (matches payment_amount_nonnegative)."""
    refund_rate = cfg.get("refund_rate", 0.12)
    declined_rate = cfg.get("declined_rate", 0.04)
    voided_rate = cfg.get("voided_rate", 0.02)
    adjustment_rate = cfg.get("adjustment_rate", 0.03)
    chargeback_rate = cfg.get("chargeback_rate", 0.015)

    # Aggregate order_lines to order grain: one store per order (build_order_lines
    # attaches store_sk/store_id per order, so MAX returns the single value).
    orders = (order_lines.groupBy("order_id", "profile_sk", "profile_id", "store_sk", "store_id")
              .agg(F.round(F.sum("net_amount"), 2).alias("amount"),
                   F.max("event_timestamp").alias("event_timestamp"))
              # one tender per order, shared across all of its payment events.
              .withColumn("payment_method", _pick(PAYMENT_METHODS, seed, "pm", "order_id")))

    # 1) Successful sale on every order (100%); settlement status mixed so
    #    captured / settled / authorized all appear (thresholds 0.70 / 0.90).
    sale_status = (
        F.when(_frac(seed, "paystat", "order_id") < F.lit(0.70), F.lit("captured"))
         .when(_frac(seed, "paystat", "order_id") < F.lit(0.90), F.lit("settled"))
         .otherwise(F.lit("authorized"))
    )
    # Money was actually taken only on captured / settled sales. Reversals (refunds, chargebacks,
    # adjustments) are drawn from those orders only: an authorization that was never captured has
    # nothing to refund, and a reversal on it would drive realized revenue below zero.
    is_collected = _frac(seed, "paystat", "order_id") < F.lit(0.90)
    sale = (orders
            .withColumn("payment_type", F.lit("sale"))
            .withColumn("payment_status", sale_status)
            .withColumn("payment_id", F.concat_ws("-", F.lit("PAY"), F.col("order_id"))))

    # 2) Declined first attempt (~4%), one hour before the successful sale.
    declined = (orders
                .where(_frac(seed, "decl", "order_id") < F.lit(declined_rate))
                .withColumn("payment_type", F.lit("sale"))
                .withColumn("payment_status", F.lit("declined"))
                .withColumn("event_timestamp",
                            F.col("event_timestamp") - F.expr("make_interval(0, 0, 0, 0, 1)"))
                .withColumn("payment_id", F.concat_ws("-", F.lit("PAYD"), F.col("order_id"))))

    # 3) Voided attempt (~2%), two hours before.
    voided = (orders
              .where(_frac(seed, "void", "order_id") < F.lit(voided_rate))
              .withColumn("payment_type", F.lit("sale"))
              .withColumn("payment_status", F.lit("voided"))
              .withColumn("event_timestamp",
                          F.col("event_timestamp") - F.expr("make_interval(0, 0, 0, 0, 2)"))
              .withColumn("payment_id", F.concat_ws("-", F.lit("PAYV"), F.col("order_id"))))

    # 4) Partial refund, deterministically tiered by store (HIGH: 2x, NORMAL: 1x, LOW: 0.5x
    # the base refund_rate), 30% of the order amount, a couple of days later.
    # Compute the store-tier adjusted refund rate for this order.
    refund_rate_adjusted = (F.lit(refund_rate) * refund_store_multiplier(F.col("store_id")))
    is_refunded = is_collected & (_frac(seed, "refund", "order_id") < refund_rate_adjusted)
    refund = (orders
              .where(is_refunded)
              .withColumn("amount", F.round(F.col("amount") * F.lit(0.3), 2))
              .withColumn("payment_type", F.lit("refund"))
              .withColumn("payment_status", F.lit("refunded"))
              .withColumn("event_timestamp",
                          F.col("event_timestamp") + F.expr("make_interval(0, 0, 0, 2)"))
              .withColumn("payment_id", F.concat_ws("-", F.lit("PAYR"), F.col("order_id"))))

    # a chargeback reverses the full order, so it is not drawn on an order that was already
    # partially refunded, and adjustments are not drawn on a charged-back order: either pairing would
    # reverse more than was ever collected.
    is_chargeback = (is_collected & ~is_refunded
                     & (_frac(seed, "cbk", "order_id") < F.lit(chargeback_rate))
                     & (F.col("payment_method") == F.lit("card")))

    # 5) Post-sale adjustment (~3%), 5% of the order. ADJUSTMENT_ORPHAN_SHARE (20%) carry NULL
    # order_id (the warn-path in payment_order_orphan), the rest (80%) link to the order.
    adjustment = (orders
                  .where(is_collected & ~is_chargeback
                         & (_frac(seed, "adj", "order_id") < F.lit(adjustment_rate)))
                  .withColumn("amount", F.round(F.col("amount") * F.lit(0.05), 2))
                  .withColumn("payment_type", F.lit("adjustment"))
                  .withColumn("payment_status", F.lit("settled"))
                  .withColumn("event_timestamp",
                              F.col("event_timestamp") + F.expr("make_interval(0, 0, 0, 5)"))
                  .withColumn("payment_id", F.concat_ws("-", F.lit("PAYA"), F.col("order_id")))
                  # Deterministically orphan ADJUSTMENT_ORPHAN_SHARE of adjustments (NULL order_id);
                  # the rest keep the order_id (linked).
                  .withColumn("order_id",
                              F.when(_frac(seed, "adj_orphan", "order_id") < F.lit(ADJUSTMENT_ORPHAN_SHARE),
                                     F.lit(None).cast("string"))
                               .otherwise(F.col("order_id"))))

    # 6) Chargeback (~1.5%), card tenders only, weeks later.
    chargeback = (orders
                  .where(is_chargeback)
                  .withColumn("payment_type", F.lit("chargeback"))
                  .withColumn("payment_status", F.lit("settled"))
                  .withColumn("event_timestamp",
                              F.col("event_timestamp") + F.expr("make_interval(0, 0, 0, 20)"))
                  .withColumn("payment_id", F.concat_ws("-", F.lit("PAYC"), F.col("order_id"))))

    events = (sale.unionByName(declined).unionByName(voided)
              .unionByName(refund).unionByName(adjustment).unionByName(chargeback))
    return (events
            .withColumn("currency_code", F.lit(base_currency))
            .withColumn("transaction_currency_code", F.lit(base_currency))
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def build_segment_membership(spark, order_lines, products_current, calendar_df, seed):
    """Behavioral-segment membership as-of snapshot, seeded so a member of a
    rule-based segment ACTUALLY satisfies that segment's criteria_expression in the
    trait surface (M1: previously a blind hash of profile_id, which put non-lapsing
    customers in 'Lapsing' etc. — the Genie demo returned semantically inconsistent
    members). Derives the same per-customer signals the trait/LTV gold views compute
    (frequency, historical_clv, promo_purchase_share_ratio, recency/cadence ->
    lifecycle_stage, value_tier, churn_risk_proxy) from the order-line fact, then
    applies each canned segment's predicate. Kept intentionally aligned with the
    gold-view formulas (docs/behavioral-segmentation); it is seed realism, not a
    second source of truth. All rows dated one as_of_date (append-only)."""
    # period_index per order date, matching the gold view's (fiscal_year*12+period).
    cal = calendar_df.select("date_key",
                             (F.col("fiscal_year") * F.lit(12) + F.col("fiscal_period")).alias("period_index"))
    # unit_cost per product, to compute realized margin the same way gold_customer_ltv
    # does (line_margin = net_amount - units*unit_cost) — value_tier tiers on this
    # historical_clv (margin), NOT on net spend (H1: a spend-based proxy misclassifies).
    prod_cost = products_current.select("product_sk", "unit_cost")
    o = (order_lines.join(F.broadcast(cal), order_lines["order_date"] == cal["date_key"], "left")
         .join(F.broadcast(prod_cost), "product_sk", "left")
         .select("profile_id", "order_id", "period_index", "units", "gross_amount", "net_amount",
                 (F.col("net_amount") - F.col("units") * F.col("unit_cost")).alias("line_margin")))
    cur_period = o.agg(F.max("period_index")).first()[0]

    per_cust = (o.groupBy("profile_id").agg(
        F.countDistinct("order_id").alias("frequency"),
        F.sum("line_margin").alias("historical_clv"),
        F.max("period_index").alias("last_period"),
        F.min("period_index").alias("first_period"),
        # promo share: net-below-gross line spend / total (the gold view's proxy).
        (F.sum(F.when(F.col("net_amount") < F.col("gross_amount"), F.col("net_amount")).otherwise(F.lit(0)))
         / F.when(F.sum("net_amount") == 0, F.lit(None)).otherwise(F.sum("net_amount"))).alias("promo_purchase_share_ratio"),
    ))
    lit_cur = F.lit(cur_period)
    cadence = (lit_cur - F.col("first_period") + F.lit(1)) / F.when(F.col("frequency") == 0, F.lit(None)).otherwise(F.col("frequency"))
    recency = lit_cur - F.col("last_period")
    traits = per_cust.select(
        "profile_id", "frequency", "promo_purchase_share_ratio",
        recency.alias("recency_periods"),
        # value_tier: gold_customer_ltv stable thresholds on realized MARGIN (historical_clv),
        # matching gold_customer_ltv.value_tier exactly so a seeded VIP/GOLD is really one.
        F.when(F.col("historical_clv") >= F.lit(2500), F.lit("PLATINUM"))
         .when(F.col("historical_clv") >= F.lit(1000), F.lit("GOLD"))
         .when(F.col("historical_clv") >= F.lit(250), F.lit("SILVER"))
         .otherwise(F.lit("BRONZE")).alias("value_tier"),
        # lifecycle_stage: recency vs the customer's own cadence + tenure (gold view logic).
        F.when((lit_cur - F.col("first_period")) == 0, F.lit("new"))
         .when((recency > F.lit(2) * cadence) & (recency > F.lit(3)), F.lit("churned"))
         .when(recency > cadence, F.lit("lapsing"))
         .otherwise(F.lit("active")).alias("lifecycle_stage"),
        # churn_risk_proxy: recency > 2.0x average cadence (the gold view's CHURN_MULT heuristic).
        (recency > F.lit(2.0) * cadence).alias("churn_risk_proxy"),
    )

    # Apply each canned segment's real predicate. Kept in lockstep with CANNED_SEGMENTS
    # criteria_expression (trade_promotion.py); a membership guard test asserts coverage.
    seg_predicates = {
        "SEG-HIGH-VALUE-REPEAT": (F.col("value_tier").isin("PLATINUM", "GOLD")) & (F.col("frequency") >= F.lit(4)),
        "SEG-LAPSING": F.col("lifecycle_stage") == F.lit("lapsing"),
        "SEG-CHURNED-WINBACK": F.col("lifecycle_stage") == F.lit("churned"),
        "SEG-NEW-TO-BRAND": F.col("lifecycle_stage") == F.lit("new"),
        "SEG-DISCOUNT-DRIVEN": F.col("promo_purchase_share_ratio") >= F.lit(0.5),
        "SEG-FULL-PRICE-LOYAL": (F.col("promo_purchase_share_ratio") < F.lit(0.1)) & (F.col("frequency") >= F.lit(3)),
        "SEG-VIP": F.col("value_tier") == F.lit("PLATINUM"),
        "SEG-AT-RISK-HIGH-VALUE": (F.col("churn_risk_proxy")) & (F.col("value_tier").isin("PLATINUM", "GOLD")),
    }
    # Drift guard: a predicate must exist for every shared canned segment id (so a
    # new BEHAVIORAL_SEGMENT_IDS entry can't silently ship with zero seeded members).
    assert set(seg_predicates) == set(BEHAVIORAL_SEGMENT_IDS), \
        "seg_predicates drifted from _common.BEHAVIORAL_SEGMENT_IDS"
    parts = [traits.where(pred).select("profile_id", F.lit(sid).alias("audience_id"))
             for sid, pred in seg_predicates.items()]
    from functools import reduce
    members = reduce(lambda a, b: a.unionByName(b), parts).dropDuplicates(["profile_id", "audience_id"])
    return (members
            .withColumn("as_of_date", F.expr("date'2024-12-31'"))
            .withColumn("segment_membership_id",
                        F.concat_ws("-", F.col("profile_id"), F.col("audience_id"), F.date_format(F.col("as_of_date"), "yyyyMMdd")))
            # Mostly 'existing'; a deterministic ~5% slice is 'exited' (m3) so the
            # exclusion path (UCV gate filter + metric-view reach) is exercised on seed data,
            # not just documented. 'realized' stays reserved for a future entered/exited feed.
            .withColumn("membership_status",
                        F.when(F.abs(F.hash(F.col("segment_membership_id"), F.lit("status"))) % F.lit(20) == F.lit(0),
                               F.lit("exited")).otherwise(F.lit("existing")))
            .withColumn("membership_score", F.lit(None).cast("decimal(8,4)"))
            .withColumn("assignment_method", F.lit("rule"))
            .withColumn("model_version", F.lit("behavioral-v1"))
            # append-only event-log audit block (§8): record_source + load_timestamp only.
            .withColumn("record_source", F.lit(RECORD_SOURCE))
            .withColumn("load_timestamp", F.current_timestamp()))


def generate(spark, catalog, schemas, cfg, mode, base_currency="USD"):
    if not catalog:
        raise ValueError("`catalog` parameter is required (guardrail #1: no hardcoded catalog).")

    def fq(schema, table):
        return f"{catalog}.{schemas[schema]}.{table}"

    seed = cfg["seed"]
    print(f"[ordm] generating Customer LTV orders into {catalog} "
          f"(max_orders={cfg['max_orders']}, value_skew={cfg['value_skew']}, seed={seed}, mode={mode})")

    profiles_current = spark.table(fq("customer", "profile")).where("is_current = true")
    products_current = spark.table(fq("product", "product")).where("is_current = true")
    stores_current = spark.table(fq("store", "store")).where("is_current = true")
    calendar_tbl = spark.table(fq("calendar", "fiscal_calendar"))
    cal = calendar_tbl.agg(F.min("date_key").alias("mn"), F.count(F.lit(1)).alias("cnt")).first()
    start_date, n_days = cal["mn"], int(cal["cnt"])

    lines = build_order_lines(spark, profiles_current, products_current, stores_current,
                              start_date, n_days, seed, cfg["max_orders"], cfg["value_skew"],
                              cfg["lines_per_order_max"], base_currency,
                              affinity_denom=cfg["affinity_copurchase_denom"],
                              affinity_pair_count=cfg["affinity_pair_count"])
    _write(spark, lines, fq("order", "customer_order_line"), CUSTOMER_ORDER_LINE_COLUMNS, mode)

    # Payment events (tender/settlement side of the orders): the full lifecycle —
    # sales (captured/settled/authorized), declines, voids, refunds, adjustments
    # (NULL order_id warn-path), and card-only chargebacks.
    payments = build_payments(spark, lines, base_currency, seed, cfg)
    _write(spark, payments, fq("payment", "payment"), PAYMENT_COLUMNS, mode)

    # Behavioral-segment membership (append-only as-of snapshot). Assigns each customer to a
    # deterministic subset of the canned behavioral segments seeded in marketing.audience —
    # the narrow (customer x segment) surface the CDP activates against (ADR 0022). Membership
    # carries NO consent/preference flags; the activation gate is applied only in UCV.
    membership = build_segment_membership(spark, lines, products_current, calendar_tbl, seed)
    _write(spark, membership, fq("acu", "segment_membership"), SEGMENT_MEMBERSHIP_COLUMNS, mode)

    # Market Analysis is an ACU capability, so this helper writes its four source
    # interfaces under the same sole `acu` provider. The registry declares `bmv`
    # upstream because competitor identity remains BMV-owned (ADR 0042).
    generate_market_analysis(spark, catalog, schemas, seed, base_currency, mode)
    print("[ordm] Customer LTV generation complete.")


def run(ctx):
    cfg = load_config()
    generate(ctx.spark, ctx.catalog, ctx.schemas, cfg, ctx.mode, ctx.base_currency)


def main():
    from _context import DeployContext
    run(DeployContext.from_params(SparkSession.builder.getOrCreate()))


if __name__ == "__main__":
    main()
