-- ============================================================
-- ORDM · Outcome Package · Commerce Media Networks · PII column masks
-- Version: 0.5 · Generated: 2026-07-13 · LLM-generated: true · Reviewed: 2026-07-13
-- ENFORCES the dbx_pii_identifier tags on the person-level facts: the hashed
-- customer/household/assignment identifiers are masked by default; only members
-- of the `pii_readers` group (e.g. a clean-room service principal) see raw
-- token values. Run AFTER the fact tables exist. The gold views never expose
-- these columns; this protects the facts themselves (defence in depth).
-- ============================================================

CREATE OR REPLACE FUNCTION ${catalog}.${cmn_schema}.mask_pii_text(val STRING)
  RETURNS STRING
  RETURN CASE WHEN is_account_group_member('pii_readers') THEN val ELSE '***' END;

ALTER TABLE ${catalog}.${cmn_schema}.media_event ALTER COLUMN customer_key_hash  SET MASK ${catalog}.${cmn_schema}.mask_pii_text;
ALTER TABLE ${catalog}.${cmn_schema}.media_event ALTER COLUMN household_key_hash SET MASK ${catalog}.${cmn_schema}.mask_pii_text;
ALTER TABLE ${catalog}.${cmn_schema}.conversion_event ALTER COLUMN customer_key_hash SET MASK ${catalog}.${cmn_schema}.mask_pii_text;
ALTER TABLE ${catalog}.${cmn_schema}.attributed_outcome ALTER COLUMN customer_key_hash SET MASK ${catalog}.${cmn_schema}.mask_pii_text;
ALTER TABLE ${catalog}.${cmn_schema}.experiment_assignment_bridge ALTER COLUMN assignment_unit_key_hash SET MASK ${catalog}.${cmn_schema}.mask_pii_text;
