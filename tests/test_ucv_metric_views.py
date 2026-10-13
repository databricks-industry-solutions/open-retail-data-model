"""Static tests for the unified-customer-view UC Metric View overlay and the Customer
Lifetime Value metric view (in actionable-customer-understanding, next to
gold_customer_ltv; UCV's CLV use case maps to that view across packages).

Checks: each view parses as version 1.1; it carries the glossary metrics for its use
case; no person-level field (profile_id) is exposed as a dimension; and no measure
averages a per-row ratio or uses a window function. Column existence for every metric
view is covered by tests/test_metric_view_sources.py. No Spark required.
"""
import os
import re

import pytest
import yaml

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
UCV_MV = os.path.join(REPO, "outcome-packages", "unified-customer-view", "metric-views")
ACU_MV = os.path.join(REPO, "outcome-packages", "actionable-customer-understanding", "metric-views")

# view file -> glossary metrics it must carry (UCV glossary "Metrics (definitions)";
# ACU glossary for CLV). Names follow the glossary; contactable_rate is per channel.
REQUIRED = {
    os.path.join(UCV_MV, "customer_360.sql"): {
        "active_customer_count", "avg_identity_confidence", "identity_coverage_rate",
        "consent_marketing_rate", "email_contactable_rate", "sms_contactable_rate",
        "household_coverage", "avg_reachability_score", "avg_profile_completeness",
    },
    os.path.join(UCV_MV, "cdp_activation_eligibility.sql"): {
        "consent_granted_rate_by_purpose", "eligible_rate", "suppression_rate",
    },
    os.path.join(UCV_MV, "cdp_activation_jobs.sql"): {
        "activation_export_rate", "activation_block_rate", "activation_match_rate",
    },
    os.path.join(UCV_MV, "cdp_campaign_touch.sql"): {
        "campaign_touch_count", "campaign_reach",
    },
    os.path.join(ACU_MV, "customer_lifetime_value.sql"): {
        "customer_count", "total_historical_clv", "avg_historical_clv",
        "avg_predicted_clv", "avg_order_value", "churn_risk_rate",
    },
}


def _doc(path):
    m = re.search(r"WITH\s+METRICS\s+LANGUAGE\s+YAML\s+AS\s*\$\$(.*?)\$\$", open(path).read(), re.I | re.S)
    assert m, f"{os.path.basename(path)} has no metric-view YAML body"
    return yaml.safe_load(m.group(1))


def _ids(path):
    return os.path.relpath(path, REPO)


@pytest.mark.parametrize("path", REQUIRED, ids=_ids)
def test_parses_as_version_1_1_with_header(path):
    text = open(path).read()
    assert _doc(path).get("version") == 1.1
    for line in ("-- Generated:", "-- LLM-generated:", "-- Last reviewed:"):
        assert line in text, f"{_ids(path)} header misses {line!r}"


@pytest.mark.parametrize("path", REQUIRED, ids=_ids)
def test_carries_the_glossary_metrics(path):
    names = {m["name"] for m in _doc(path)["measures"]}
    missing = REQUIRED[path] - names
    assert not missing, f"{_ids(path)} misses measures {sorted(missing)}"


@pytest.mark.parametrize("path", REQUIRED, ids=_ids)
def test_no_person_level_dimension(path):
    fields = {f["name"] for f in _doc(path).get("fields", [])}
    assert not fields & {"profile_id", "profile_sk", "customer_id"}, f"{_ids(path)} exposes a person-level field"


@pytest.mark.parametrize("path", REQUIRED, ids=_ids)
def test_measures_roll_up_safely(path):
    for m in _doc(path)["measures"]:
        expr = m["expr"].upper()
        assert " OVER" not in expr, f"{m['name']} uses a window function"
        # AVG is only allowed over a raw per-row value or a 0/1 indicator (a share of
        # rows); an AVG of a column that is itself a ratio would not pool correctly.
        for arg in re.findall(r"AVG\((.*?)\)\s*$", expr):
            assert "/" not in arg, f"{m['name']} averages a ratio: {m['expr']}"


def test_cdp_eligibility_and_jobs_are_separate_grains():
    # The eligibility gate (customer x purpose x channel) and the publish runs
    # (audience x destination x run) must not be joined into one source: any join
    # between them multiplies rows and corrupts both sets of rates.
    for name in ("cdp_activation_eligibility.sql", "cdp_activation_jobs.sql"):
        source = _doc(os.path.join(UCV_MV, name))["source"].upper()
        assert " JOIN " not in source, f"{name} joins another grain into its source"


def test_customer_lifetime_value_avg_order_value_is_ratio_of_sums():
    expr = {m["name"]: m["expr"] for m in _doc(os.path.join(ACU_MV, "customer_lifetime_value.sql"))["measures"]}
    assert expr["avg_order_value"].replace(" ", "") == "SUM(total_spend)/NULLIF(SUM(frequency),0)"
