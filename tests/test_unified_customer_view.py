"""Tests for the Unified Customer View outcome package.

Static contract tests (gold views parse; NO raw PII in any gold output; the
no-PII DQ guard and checks are well-formed; engine-neutral — no UC Metric View
files) plus a Spark fixture (the Databricks engine) running the REAL
activation-eligibility view across all four eligibility branches.
"""

import os
import re

import pytest
import sqlglot
import sqlglot.expressions as E

from tools.ordm_config import resolve, view_select_body

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PKG = os.path.join(REPO, "outcome-packages", "unified-customer-view")
V360 = os.path.join(PKG, "gold", "gold_unified_customer_360_current.sql")
VELIG = os.path.join(PKG, "gold", "gold_customer_activation_eligibility_current.sql")
SNAP = os.path.join(PKG, "tables", "customer_profile_snapshot.sql")
CHECKS = os.path.join(PKG, "checks.sql")

# CDP activation layer (ADR 0026): (path, table stem, expected dbx_data_type)
RAD = os.path.join(PKG, "tables", "activation_destination.sql")
AJOB = os.path.join(PKG, "tables", "activation_job.sql")
CTOUCH = os.path.join(PKG, "tables", "campaign_touch.sql")
ACTIVATION_TABLES = [
    (RAD, "activation_destination", "reference"),
    (AJOB, "activation_job", "transactional"),
    (CTOUCH, "campaign_touch", "transactional"),
]

PII_COLUMNS = {"loyalty_id", "household_id", "first_name", "middle_name", "last_name",
               "date_of_birth", "name_prefix", "name_suffix", "contact_value",
               "identifier_value_hash"}


def _outputs(path):
    # Parse the whole CREATE VIEW and read the view query's output names (robust to
    # WITH/CTE prefixes, plain or materialized view forms).
    stmt = sqlglot.parse_one(resolve(open(path).read(), "c"), read="databricks", error_level="ignore")
    sel = stmt.expression if isinstance(stmt, E.Create) else stmt
    return set(sel.named_selects)


# ---------- static ----------

@pytest.mark.parametrize("path", [V360, VELIG])
def test_gold_view_parses_and_keys_on_surrogate(path):
    assert _outputs(path), f"{os.path.basename(path)} did not parse to a SELECT"
    outs = _outputs(path)
    assert {"profile_sk", "profile_id"} <= outs, "gold view must carry the customer surrogate + durable key"


@pytest.mark.parametrize("path", [V360, VELIG])
def test_no_raw_pii_in_gold_outputs(path):
    leaked = PII_COLUMNS & _outputs(path)
    assert not leaked, f"{os.path.basename(path)} exposes raw PII: {sorted(leaked)}"


def test_snapshot_table_contract():
    txt = resolve(open(SNAP).read(), "c")
    creates = [s for s in sqlglot.parse(txt, read="databricks", error_level="ignore") if isinstance(s, E.Create)]
    assert len(creates) == 1, "extension table must be exactly one CREATE"
    cols = {c.name for c in creates[0].find_all(E.ColumnDef)}
    assert "customer_profile_snapshot_sk" in cols and "customer_profile_snapshot_id" in cols
    assert "CONSTRAINT pk_customer_profile_snapshot PRIMARY KEY" in open(SNAP).read()
    assert "SET TAGS ('dbx_data_type' = 'transactional')" in open(SNAP).read()
    assert not PII_COLUMNS & cols, "snapshot fact must not carry raw PII columns"


@pytest.mark.parametrize("path,stem,dtype", ACTIVATION_TABLES)
def test_activation_table_contract(path, stem, dtype):
    raw = open(path).read()
    txt = resolve(raw, "c")
    creates = [s for s in sqlglot.parse(txt, read="databricks", error_level="ignore") if isinstance(s, E.Create)]
    assert len(creates) == 1, f"{stem}: extension table must be exactly one CREATE"
    cols = {c.name for c in creates[0].find_all(E.ColumnDef)}
    assert f"{stem}_sk" in cols and f"{stem}_id" in cols, f"{stem}: missing _sk/_id key pair"
    assert f"CONSTRAINT pk_{stem} PRIMARY KEY" in raw, f"{stem}: missing pk_{stem}"
    assert f"SET TAGS ('dbx_data_type' = '{dtype}')" in raw, f"{stem}: wrong/missing dbx_data_type tag"
    assert not PII_COLUMNS & cols, f"{stem}: activation fact must not carry raw PII columns"


@pytest.mark.parametrize("path,stem,dtype", ACTIVATION_TABLES)
def test_activation_table_has_checks(path, stem, dtype):
    # Every activation table is referenced by at least one DQ check (grain/orphan/domain).
    assert f"${{catalog}}.${{ucv_schema}}.{stem}" in open(CHECKS).read(), \
        f"{stem}: no DQ check references the table"


def test_checks_have_pii_guard():
    txt = open(CHECKS).read()
    assert "ucv_no_raw_pii" in txt, "missing the no-raw-PII guard check"
    # the guard must bar every PII column name from the gold views
    for col in ("household_id", "loyalty_id", "first_name", "last_name",
                "date_of_birth", "contact_value", "identifier_value_hash"):
        assert col in txt, f"PII guard does not ban {col}"


def test_checks_well_formed():
    txt = open(CHECKS).read()
    header = re.compile(r"^--\s*check:\s*(\w+)\s*\|\s*severity:\s*(error|metric)\s*$", re.I | re.M)
    names = header.findall(txt)
    assert len(names) >= 8, f"expected a meaningful suite, found {len(names)}"
    assert len({n for n, _ in names}) == len(names), "duplicate check names"
    assert "${catalog}.${ucv_schema}." in txt


def test_no_banned_or_hardcoded():
    for path in (V360, VELIG, SNAP, CHECKS):
        txt = open(path).read()
        assert not re.search(r"GROUP\s+BY\s+ALL|\b1\s*=\s*1\b", txt, re.I), f"banned SQL in {path}"
        assert not re.search(r"https?://[\w.-]*databricks|retail_prod|retail_dev|Copyright|SPDX|Licensed under",
                             txt, re.I), f"hardcoded/licence in {path}"


def test_glossary_metrics_ship_as_metric_views():
    # The glossary stays the engine-neutral definition of the KPIs; metric-views/ is the
    # Databricks-native materialization of those same metrics (README Design notes).
    # Their content is checked in tests/test_ucv_metric_views.py.
    mv = os.path.join(PKG, "metric-views")
    files = sorted(f for f in os.listdir(mv) if f.endswith(".sql"))
    assert files == ["cdp_activation_eligibility.sql", "cdp_activation_jobs.sql",
                     "cdp_campaign_touch.sql", "customer_360.sql"], files


# ---------- engine: Spark fixture running the real eligibility view ----------

_SUBS = [
    ("${catalog}.${customer_schema}.consent", "consent"),
    ("${catalog}.${customer_schema}.channel_preference", "channel_preference"),
    ("${catalog}.${customer_schema}.contact", "contact"),
    ("${catalog}.${customer_schema}.address", "address"),
    # ADR 0028: the gate now sources the person-level do-not-target set from a shared view
    # instead of an inline CTE. Register it as a temp view built from the same consent data.
    ("${catalog}.${ucv_schema}.gold_person_do_not_target_current", "gdnt"),
]

VDNT = os.path.join(PKG, "gold", "gold_person_do_not_target_current.sql")


def _sub(body):
    for a, b in _SUBS:
        body = body.replace(a, b)
    return body


def _elig_body():
    return _sub(view_select_body(open(VELIG).read()))


def _dnt_body():
    return _sub(view_select_body(open(VDNT).read()))


def _build_elig(spark):
    # P1 granted+email+no-optout -> eligible; P2 withdrawn; P3 granted+email+optout;
    # P4 granted but no email identifier; P5 NULL consent_status (review M2: must
    # fail CLOSED to consent_denied, not vanish from both populations);
    # P6 granted+email+no-optout but CHANNEL-suppressed (hard_bounce) -> email blocked;
    # P7 has a PERSON-level suppression (deceased) on its EMAIL row and a clean, granted,
    # reachable SMS row -> BOTH channels must block (review H1: person-level suppression
    # propagates across scopes; the SMS row must not leak eligible).
    consent = [(1, "P1", "marketing_email", "granted",   "US", True,  False, None),
               (2, "P2", "marketing_email", "withdrawn", "US", True,  False, None),
               (3, "P3", "marketing_email", "granted",   "US", True,  False, None),
               (4, "P4", "marketing_email", "granted",   "US", True,  False, None),
               (5, "P5", "marketing_email", None,        "US", True,  False, None),
               (6, "P6", "marketing_email", "granted",   "US", True,  True,  "hard_bounce"),
               (7, "P7", "marketing_email", "granted",   "US", True,  True,  "deceased"),
               (8, "P7", "marketing_sms",   "granted",   "US", True,  False, None),
               # P8 (ADR 0028): a non-marketing, channel-agnostic purpose. third_party_sharing
               # granted -> a retail_media row with channel_code NULL and has_identifier TRUE
               # (reachability resolves at the reverse-ETL boundary) -> eligible.
               (9, "P8", "third_party_sharing", "granted", "US", True, False, None),
               # P9 (ADR 0028): a PERSON-level suppression recorded on a NON-marketing scope
               # must still block every plane via the do-not-target view (legal_objection).
               (10, "P9", "third_party_sharing", "granted", "US", True, True, "legal_objection"),
               # P10 (ADR 0028): data_sale (CCPA do-not-SELL) is a DISTINCT purpose from
               # third_party_sharing (do-not-SHARE) -> its own channel-agnostic gate row
               # (purpose_code='data_sale', channel NULL, eligible), not folded into retail_media.
               (11, "P10", "data_sale", "granted", "US", True, False, None)]
    spark.createDataFrame(
        consent, "profile_sk int, profile_id string, consent_type string, "
                 "consent_status string, jurisdiction_code string, is_current boolean, "
                 "suppression_indicator boolean, suppression_reason_code string"
    ).createOrReplaceTempView("consent")
    prefs = [
        # P3: a CHANNEL-level opt-out (channel-scoped preference) -> blocks email.
        ("P3", "email", "contact_frequency", False, True),
        # P1: a TOPIC-level unsubscribe -> must NOT drop the channel (review H1).
        ("P1", "email", "topic_subscription", False, True),
    ]
    spark.createDataFrame(
        prefs, "profile_id string, channel string, preference_type string, "
               "is_subscribed boolean, is_current boolean"
    ).createOrReplaceTempView("channel_preference")
    contacts = [("P1", "email", "active"), ("P2", "email", "active"),
                ("P3", "email", "active"), ("P5", "email", "active"),
                ("P6", "email", "active"),  # P4 has none; P6 fully reachable but suppressed
                # P7 reachable on BOTH channels (email + mobile for SMS) — proves person-level
                # suppression blocks the clean SMS row, not just the flagged email row.
                ("P7", "email", "active"), ("P7", "mobile_phone", "active")]
    spark.createDataFrame(
        contacts, "profile_id string, contact_type string, contact_status string"
    ).createOrReplaceTempView("contact")
    spark.createDataFrame(
        [], "profile_id string, address_status string, country_code string, is_current boolean"
    ).createOrReplaceTempView("address")
    # ADR 0028: build the shared do-not-target view first (the gate reads it), from consent.
    spark.sql("CREATE OR REPLACE TEMP VIEW gdnt AS " + _dnt_body())
    spark.sql("CREATE OR REPLACE TEMP VIEW gelig AS " + _elig_body())


def test_eligibility_branches(spark):
    _build_elig(spark)
    rows = {r.profile_id: r for r in spark.sql(
        "SELECT profile_id, eligible_flag, blocking_reason_code, is_suppressed_flag FROM gelig").collect()}
    # P1 stays eligible despite a topic_subscription unsubscribe (H1: a topic-level
    # opt-out narrows targeting, it does NOT drop the whole channel).
    assert rows["P1"].eligible_flag is True and rows["P1"].blocking_reason_code is None
    assert rows["P2"].eligible_flag is False and rows["P2"].blocking_reason_code == "withdrawn"
    # P3's channel-level opt-out still blocks.
    assert rows["P3"].eligible_flag is False and rows["P3"].blocking_reason_code == "preference_opt_out"
    assert rows["P4"].eligible_flag is False and rows["P4"].blocking_reason_code == "no_identifier"
    # P5: NULL consent_status fails CLOSED — it must appear as blocked (consent_denied),
    # never drop out with a NULL eligible_flag (review M2 fail-open fix).
    assert "P5" in rows, "NULL-consent row vanished (fail-open regression)"
    assert rows["P5"].eligible_flag is False and rows["P5"].blocking_reason_code == "consent_denied"
    # P6: granted + reachable + no opt-out, but CHANNEL-suppressed (hard_bounce) — suppression
    # overrides consent, so it blocks with the highest-priority reason and is NOT eligible.
    assert rows["P6"].eligible_flag is False and rows["P6"].blocking_reason_code == "suppressed"
    assert rows["P6"].is_suppressed_flag is True
    # P7 (review H1): a PERSON-level reason (deceased) sits only on the email row, but it must
    # block EVERY channel. The clean, granted, reachable SMS row must NOT leak eligible.
    p7 = {r.channel_code: r for r in spark.sql(
        "SELECT channel_code, eligible_flag, blocking_reason_code, is_suppressed_flag "
        "FROM gelig WHERE profile_id = 'P7'").collect()}
    assert p7["email"].eligible_flag is False and p7["email"].blocking_reason_code == "suppressed"
    assert p7["sms"].eligible_flag is False and p7["sms"].blocking_reason_code == "suppressed", \
        "person-level suppression leaked an un-suppressed sibling channel (H1)"
    assert p7["sms"].is_suppressed_flag is True
    # P8 (ADR 0028): a non-marketing consent (third_party_sharing) is now gate-producible as a
    # channel-agnostic retail_media row — eligible, with NULL channel and reachability vacuously
    # TRUE (resolved at the reverse-ETL boundary, not on an owned channel).
    p8 = {r.purpose_code: r for r in spark.sql(
        "SELECT purpose_code, channel_code, eligible_flag, has_identifier_flag "
        "FROM gelig WHERE profile_id = 'P8'").collect()}
    assert "retail_media" in p8, "non-marketing purpose is not gate-producible (multi-purpose regression)"
    assert p8["retail_media"].channel_code is None
    assert p8["retail_media"].eligible_flag is True and p8["retail_media"].has_identifier_flag is True
    # P9 (ADR 0028): a PERSON-level reason (legal_objection) recorded on a NON-marketing scope
    # must still block, proving the do-not-target view is purpose-agnostic across every plane.
    assert rows["P9"].eligible_flag is False and rows["P9"].blocking_reason_code == "suppressed"
    assert rows["P9"].is_suppressed_flag is True
    # P10 (ADR 0028): data_sale (CCPA do-not-SELL) maps to its OWN channel-agnostic purpose,
    # distinct from third_party_sharing -> retail_media (do-not-SHARE). One eligible row with
    # purpose_code='data_sale' and NULL channel; it must NOT collapse into retail_media.
    p10 = {r.purpose_code: r for r in spark.sql(
        "SELECT purpose_code, channel_code, eligible_flag, has_identifier_flag "
        "FROM gelig WHERE profile_id = 'P10'").collect()}
    assert set(p10) == {"data_sale"}, f"data_sale purpose wrong/folded: {set(p10)}"
    assert p10["data_sale"].channel_code is None
    assert p10["data_sale"].eligible_flag is True and p10["data_sale"].has_identifier_flag is True


def test_person_do_not_target_view(spark):
    # The shared do-not-target view (ADR 0028) surfaces exactly the person-level-suppressed
    # profiles, keyed on profile_id, regardless of the consent scope the reason sits on.
    _build_elig(spark)
    dnt = {r.profile_id: r.do_not_target_reason_code for r in spark.sql(
        "SELECT profile_id, do_not_target_reason_code FROM gdnt").collect()}
    assert set(dnt) == {"P7", "P9"}, f"do-not-target set wrong: {set(dnt)}"
    assert dnt["P7"] == "deceased" and dnt["P9"] == "legal_objection"
