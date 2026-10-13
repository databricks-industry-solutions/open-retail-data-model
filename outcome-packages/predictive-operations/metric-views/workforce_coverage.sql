-- ============================================================
-- ORDM · Outcome Package · Predictive Operations · Workforce Optimization
-- Metric View: workforce_coverage
-- Layer: outcome package (UC Metric View)
-- Version: 0.5
-- Generated: 2026-08-10
-- LLM-generated: true (maintainer-reviewed before release)
-- Last reviewed: 2026-08-10
-- ============================================================

CREATE OR REPLACE VIEW ${catalog}.${predops_schema}.mv_workforce_coverage
WITH METRICS LANGUAGE YAML AS$$
version: 1.1
comment: "Workforce coverage vs required labor hours by store, role, and business date. Coverage ratio is scheduled+recommended hours over required hours."
source: >
  SELECT store_id, role_code, department_or_zone, business_date,
         required_labor_hours, scheduled_hours, recommended_hours,
         covered_hours, shortfall_hours, coverage_pct, shortfall_severity
  FROM ${catalog}.${predops_schema}.gold_workforce_coverage_gap
fields:
  - name: store_id
    expr: store_id
    display_name: "Store"
    comment: "Durable store business key."
    synonyms: ['location', 'store', 'site']
  - name: role_code
    expr: role_code
    display_name: "Role"
    comment: "Workforce role code."
    synonyms: ['job_role', 'position', 'labor_role']
  - name: department_or_zone
    expr: department_or_zone
    display_name: "Zone"
    comment: "Department or zone within the store."
    synonyms: ['zone', 'department', 'area']
  - name: business_date
    expr: business_date
    display_name: "Business Date"
    comment: "Local business date."
    synonyms: ['date', 'trading_date', 'day']
  - name: shortfall_severity
    expr: shortfall_severity
    display_name: "Shortfall Severity"
    comment: "none / low / medium / high / critical."
    synonyms: ['severity', 'risk_tier']
measures:
  - name: required_labor_hours
    expr: SUM(required_labor_hours)
    display_name: "Required Hours"
    comment: "Sum of required labor hours."
    synonyms: ['staffing_need_hours', 'required_hours']
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
  - name: covered_hours
    expr: SUM(covered_hours)
    display_name: "Covered Hours"
    comment: "Scheduled plus recommended hours overlapping demand."
    synonyms: ['scheduled_hours', 'staffed_hours']
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
  - name: shortfall_hours
    expr: SUM(shortfall_hours)
    display_name: "Shortfall Hours"
    comment: "Unmet required hours."
    synonyms: ['gap_hours', 'unfilled_hours']
    format:
      type: number
      decimal_places:
        type: exact
        places: 1
  - name: coverage_ratio
    expr: TRY_DIVIDE(SUM(covered_hours), NULLIF(SUM(required_labor_hours), 0))
    display_name: "Coverage Ratio"
    comment: "Covered hours / required hours."
    synonyms: ['coverage_pct', 'fill_rate']
    format:
      type: percentage
$$;
