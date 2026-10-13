# Consent & communication preferences — design notes

Design rationale for how ORDM models consent and communication preferences, and why they are **two
separate concepts**. The canonical core keeps [`consent`](../../../canonical-core/customer/tables/consent.sql)
as the single source of truth for legal permissions and adds
[`channel_preference`](../../../canonical-core/customer/tables/channel_preference.sql) for soft comms
preferences. This note captures the regulatory grounding that shapes both.

## Regulatory grounding

Privacy regulation makes the consent model non-negotiable and drives its grain:

- **GDPR Article 25** — privacy by design and by default.
- **GDPR Article 7** — where consent is the lawful basis, the organization must be able to *demonstrate*
  consent, and withdrawal must be as easy as granting.
- **GDPR Article 17** — right to erasure; deletion must propagate through bronze/silver/gold.
- **GDPR Article 21** — right to object to direct-marketing processing.
- **CCPA / CPRA** — rights to know, delete, correct, limit use of sensitive personal information, and opt out
  of sale/sharing — including via **Global Privacy Control (GPC)**, which must be honored as a valid opt-out.
- **ICO guidance** — pseudonymized data remains personal data in context and still requires protection.

Design consequences: consent must be stored at **purpose / channel / jurisdiction** scope; opt-outs must
override activation; deletion must propagate; and a legal-grade record of *when* and *how* each decision was
captured must be retained.

## Consent model (the single source of truth)

Per ORDM principle #5, opt-ins and processing permissions live **only** in `consent` — never as flags on
`profile`, `account`, or `contact`. The research models consent as a purpose×channel×jurisdiction ledger.
The conformed core `consent` table captures the durable spine of that ledger:

- `consent_type` (what is governed: marketing_email/sms/phone/postal, data_processing, third_party_sharing,
  profiling, cookies), `consent_status` (granted/withdrawn/pending/expired), `legal_basis`, `capture_channel`,
  `disclosure_version`, and `decision_timestamp` (the legal-grade instant).
- **`jurisdiction_code`** (added in this slice) — the region/law scope (e.g. GDPR-EU vs CCPA-CA), so the same
  customer can hold different consent states per jurisdiction. Current-state uniqueness is therefore
  `(profile, consent_type, jurisdiction_code)`.

### Deferred to the outcome layer / restricted domain

The richer governance signals from the research are **not** in the thin core and belong to a future
identity-resolution / activation package or a restricted governance domain:

- GPC-derived and do-not-sell/share flags, deletion-requested visibility, proof/receipt references.
- The **suppression ledger** (delete / opt-out / do-not-sell / GPC / global scopes with
  suppress-activation / suppress-personalization / suppress-measurement switches) — see
  [identity-resolution-notes](identity-resolution-notes.md).

  > **Superseded in part by [ADR 0027](../../../governance/decisions/0027-consent-suppression-overlay.md).**
  > For v1, do-not-contact **suppression is modeled as an overlay on the `customer.consent` master**
  > (`suppression_indicator` + `suppression_reason_code`), not as a separate enforcement projection — the
  > reference brief models suppression on the consent-state dimension, and there is only one consumer today
  > (the UCV activation gate). The *standalone, erasure-surviving, identifier-hash-keyed* ledger described
  > here (with the personalization/measurement scope switches and GPC/do-not-sell breadth) remains the
  > **deferred promote target**: build it when a second consumer or an erasure-survival requirement makes a
  > minimal separate store necessary (the same promote-on-second-consumer path as `audience`, ADR 0022).
  > So suppression is now *both* a governed attribute on consent (v1) *and*, in its fuller form, a future
  > restricted-domain ledger — this note is retained as the design rationale for that eventual promotion.

## The consent vs. channel_preference boundary

These are deliberately distinct and must not overlap:

| | `consent` | `channel_preference` |
|---|---|---|
| **Answers** | "Am I legally permitted to process / contact?" | "How does the customer *prefer* to be contacted?" |
| **Governs** | lawful basis, opt-in/opt-out, regulatory scope | frequency caps, topic subscriptions, format, preferred channel |
| **Source of truth for** | all legal permissions (principle #5) | soft communication preferences only |
| **Overrides** | activation (a withdrawn consent blocks contact) | ranking/selection within what consent already allows |

Rule of thumb: if a signal has legal weight (it can make contact unlawful), it is `consent`. If it only
expresses taste within already-permitted contact (prefers email over SMS, max 2/week, opted into "recipes"
topic), it is `channel_preference`. A frequency cap never grants permission that consent withheld.
