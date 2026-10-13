# ADR 0011 — Key-stem naming by grain/role, not strict table-name match

**Status:** Accepted (2026-07-06)

## Context
The standard stated the key contract literally as `<table>_sk` / `<table>_id` (§4, §D), and the `NAMING-CONSTRAINTS` rule (warn/planned) implied the surrogate stem must equal the physical table name. But that strict table-name match is a **house default, not an industry rule**: Kimball, the dbt Labs style guide, Data Vault, and the SQL style guide all name keys by the entity's **grain/role**, applied **consistently** wherever the entity is joined — none require the stem to be a character-for-character copy of the table name. Kimball additionally exempts the date dimension outright and names dimension keys by role (`product_key`, `customer_key`).

Several ORDM tables legitimately deviate from a naive `<table>_sk` reading, and each kept getting re-flagged as a naming defect by the advisory reviewer: the calendar dimension keys on the date grain (`date_sk`/`date_id`, landing in #46, rather than a table-matching `fiscal_calendar_sk`); code sets are carried on their natural ISO codes; the customer domain is split into role tables (`profile` person / `account` organization); and every fact carries a uniform surrogate PK rather than a Kimball composite/degenerate key.

## Decision
Generalize the key-naming rule: the `<stem>` in `<stem>_sk` / `<stem>_id` names the entity's **grain or role**, applied **consistently** across joins; it **defaults to the table name but need not equal it**. Record the deliberate, industry-standard deviations as **documented, intentional conventions (not defects)** in the naming section of `docs/data-model-standards.md`:
1. **Date/calendar dimension** keys on `date` (`date_sk`/`date_id`/`date_key`), per Kimball's date-dimension exemption and TPC-DS `d_date_sk`.
2. **Reference/code tables** key on the natural ISO/standard code where practical (currently inline `*_code` columns).
3. **Role-named dimensions** key on the role (`profile`/`account` under the customer domain; a party supertype remains open working-group work).
4. **Facts carry a uniform `<stem>_sk` surrogate** — an intentional ORDM house convention (one uniform key shape for generators, the Lakebase enforced PK/FK binding, and downstream joins), diverging from the classic Kimball composite/degenerate-key fact PK; the grain is still asserted by FK columns + a DQ uniqueness check, and the operational identifier is retained as a degenerate `*_id`.

## Consequences
- The date-stemmed calendar keys (`date_sk`/`date_id`, PR #46) are authorized by this ADR rather than being an un-sanctioned per-table special-case.
- Reviewers (human and automated) verify that a stem is used **consistently** wherever its entity is joined, not that it equals the physical table name; the four cases above are explicitly out of scope for a "stem ≠ table" flag.
- No CI or code change: the enforced `PK-CONTRACT` check already only requires an `_sk`-suffixed IDENTITY column + `pk_<table>` (not stem = table); `NAMING-CONSTRAINTS` stays warn/planned. This is a documentation/standard clarification.
- Mass renaming is explicitly **not** undertaken; the point is to make the existing intentional conventions explicit. Genuinely inconsistent stems (e.g. a table whose stem varies across its own joins) remain fair review targets.

## References (public)
- [Kimball Group — Dimension Surrogate Keys](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/kimball-techniques/dimensional-modeling-techniques/dimension-surrogate-key/) (date-dimension exemption)
- [Kimball Group — Fact Table Surrogate Key (Design Tip #81)](https://www.kimballgroup.com/2006/07/design-tip-81-fact-table-surrogate-key/) (fact PK is the dimension-FK composite; surrogate is an optional ETL convenience)
- [dbt Labs — How we style our dbt models](https://docs.getdbt.com/best-practices/how-we-style/1-how-we-style-our-dbt-models) (key on the object/role, consistently)
- [SQL Style Guide (sqlstyle.guide)](https://www.sqlstyle.guide/) ("do not add a column with the same name as its table")
- TPC-DS `store_sales` composite PK `(ss_item_sk, ss_ticket_number)`; `date_dim` key `d_date_sk`.
