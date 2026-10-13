# ADR 0022 — Promote the `audience` segment-definition dimension to silver `marketing`

**Status:** Accepted (2026-07-21)

Amends [ADR 0021](0021-retail-media-entities-are-gold-not-silver.md) (amendment 2) and completes the promotion path it named; relates to [ADR 0020](0020-broaden-marketing-shared-dimensions.md) (which had originally placed `audience` in silver on a premise that was later found not to hold).

## Context

ADR 0021 amendment 2 moved the `audience` segment/targeting-definition dimension **into** the gold `commerce-media-networks` (CMN) package, because at that time retail-media ad delivery was its **only** real consumer (the earlier trade-promotion link was a dead nullable FK). The CMN package README recorded the exit condition verbatim:

> Single-outcome `audience` (same flag): `audience` is gold here because retail-media ad delivery is its only current consumer. **If a future customer-intelligence / actionable-customer-understanding outcome needs the same segment definitions, `audience` should promote back to silver `marketing`** as a shared conformed dimension rather than being redefined per package (one source of truth for a segment).

Behavioral Segmentation (in the Actionable Customer Understanding package) is now that second consumer: it needs the same named, governed **segment definitions** to compute per-customer membership and to expose activatable audiences through the Unified Customer View activation gate. The ≥2-outcome promotion test in CONTRIBUTING §6 is therefore met, and the CMN README's own condition triggers.

Defining `audience` twice — once in CMN gold and again in ACU gold — would create two sources of truth for the same concept (a segment/audience definition), which the promotion rule exists to prevent.

## Decision

**Promote the `audience` dimension from `commerce-media-networks` gold to the silver `marketing` canonical-core domain**, as a shared conformed SCD2 dimension consumed by both retail-media ad delivery (CMN) and customer-intelligence segmentation (ACU + UCV).

1. **Move + extend, do not rename.** The table stays named `audience` with its existing surrogate/durable keys (`audience_sk` / `audience_id`) and its existing columns (`audience_name`, `audience_type` [enum already includes `behavioral`], `audience_origin`, `definition_description`, `size_estimate`, `is_addressable_flag`, SCD2 + audit block). Keeping the name and keys means CMN's foreign keys (`ad_group.audience_sk`, `media_event.audience_sk`, `campaign_day.audience_sk`) only change their **schema qualifier** (`cmn` → `marketing`), never a column, so no CMN reporting SQL breaks.

2. **Extend for the definition/behavioral role.** Add the columns behavioral segmentation needs to make `audience` a full segment-**definition** catalog (all optional / additive, so existing CMN rows are unaffected):
   - `segmentation_basis` — behavioral / value_rfm / lifecycle / demographic / geographic / predictive / lookalike / contextual (the axis the definition is built on).
   - `definition_origin` — how the row was authored: `canned` (curated standard), `custom` (adopter-defined), `agent_generated`.
   - `definition_method` — `rule` / `ml_score` / `imported`.
   - `criteria_expression` — portable, vendor-neutral predicate/SQL text describing the membership rule (no PII, no member lists).
   - `evaluation_mode` — `batch` / `streaming` / `edge` (latency is an attribute of the definition, not a schema fork).
   - `iab_taxonomy_code` — optional IAB Audience Taxonomy tier code for interoperability.
   All new columns are governed by `ALTER TABLE … ADD CONSTRAINT … CHECK` enums per NO-INLINE-CHECK; `dbx_data_type='master'` is unchanged.

3. **No metrics on the definition master** (standard #9). Size/counts remain the point-in-time `size_estimate` attribute; live membership counts live in the ACU membership table and metric views, never on this dimension.

4. **Layering.** `marketing` already holds the conformed `promotion` dimension; `audience` joins it as a second conformed dimension. Gold packages (CMN, ACU, UCV) reference it via gold→silver FKs (LAYER-INTEGRITY allows gold→silver). This restores the placement ADR 0020 originally intended, but now on a real ≥2-outcome basis rather than a dead FK.

## Consequences

- **Single source of truth** for a segment/audience definition across retail media and customer intelligence.
- CMN's three FK constraints re-target the silver table (schema-qualifier change only); CMN checks/relationships/README updated in the same change; the CMN README "single-outcome `audience`" note is replaced with a "consumes the shared `marketing.audience`" note.
- ACU behavioral segmentation and the UCV activation-gate join both reference `marketing.audience` by durable `audience_id`.
- `marketing` domain README scope note (ADR 0021) is updated: `marketing` now holds `promotion` **and** `audience`.
- Generated artifacts (model.json, ODCS, ER diagrams) regenerate to show `audience` under `marketing` with the new columns.

## Alternatives considered

- **ACU-local gold `segment_definition`.** Rejected: duplicates a concept CMN already ships and the promotion rule explicitly says to promote, creating two definitions of one thing.
- **Rename to `segment_definition` on promotion.** Rejected: forces renaming `audience_sk`/`audience_id` FK columns across three CMN tables and their reporting SQL for no semantic gain; "audience" is the industry-standard term and the enum already carries `behavioral`.
