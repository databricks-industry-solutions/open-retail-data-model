# ADR 0031 — `sensing_deployment` is a first-class governance dimension

**Status:** Accepted (2026-07-31) — all four scopes in the corrective-review approval record are signed off (CSS owner, CMN owner, Maintainers, Privacy).

## Context

Whether a given footfall row is lawful to hold depends almost entirely on facts that are *not* in the
measurement: which sensing technology produced it, in which jurisdiction, under which lawful basis,
whether a DPIA was completed, whether signage was posted, whether a works council was consulted, and
how long it may be retained. The same `footfall_count = 47` is unremarkable from a thermal counter in
one jurisdiction and unlawful from a Wi-Fi probe in another.

ADR 0027 established a consent/suppression overlay for customer data, but it addresses *consented
individuals* in the customer domain. In-store sensing has a different shape: there is usually no
identified individual to attach consent to, the obligations attach to the **deployment** — the
sensor-in-a-place-for-a-purpose — and several of them (DPIA, signage, works-council consultation)
are properties of the installation rather than of any data subject.

The Databricks Retail Data Ontology already anticipates this: its Consumer domain defines a
five-category consent framework that explicitly includes **"physical observation"**.

Two further findings made a dedicated entity necessary rather than a set of columns on
`sensor_device`:

1. **Employee observation is a separate regime.** Staff exclusion — needed for analytic correctness,
   since a staff member walking the door inflates footfall — requires identifying staff. Badge/BLE
   exclusion produces a per-employee presence-and-movement log; biometric exclusion produces Art. 9
   biometric processing of employees. Art. 29 WP Opinion 2/2017 holds that employment power imbalance
   makes consent rarely valid, and Art. 88 GDPR lets Member States add rules with real teeth: German
   **BetrVG §87(1)** co-determination *before* introducing monitoring devices, French works-council
   consultation, Italian **Statuto dei Lavoratori Art. 4**, Polish **Labour Code Art. 22²** (closed
   purpose list, two weeks' notice, 3-month video retention). In **AEPD / Mercadona** (€2.52M, July
   2021) the facial-recognition deployment was penalised partly because the DPIA **did not account for
   risks to the supermarket's own employees**. The consultation evidence therefore has to be a governed
   artefact, not a wiki page.
2. **Retention has one ceiling and several floors, and they attach to different data.** The EDPB expects
   erasure of video-derived personal data "after a few days", and "the longer the storage period set
   (especially when beyond 72 hours), the more argumentation … has to be provided"; France caps
   vidéoprotection recordings at **one month** (CSI Art. L.252-3). Meanwhile FSMA 204 requires 2 years,
   21 CFR 117.315 2 years, and CDC/VFC calibration certificates 3 years — none of which are personal
   data. Retention is therefore a **per-deployment** attribute, not a global setting.

## Decision

Introduce **`sensing_deployment`** as a `master`-tagged SCD2 dimension in CSS gold, and make every
`sensor_device` reference it by FK.

It records, per deployment, at minimum:

- `sensing_method_code` — the technology, since the legal analysis differs per method.
- `lawful_basis_code` and `jurisdiction_code`.
- `dpia_completed_flag`, `dpia_reference`, and — per Mercadona — whether the DPIA covered employees.
- `signage_posted_flag` and the AI Act Art. 50(3) notice status (the deployer duty to inform persons
  exposed to emotion recognition or biometric categorisation, applicable **2026-08-02**).
- `works_council_consulted_flag` and `consultation_reference`, as first-class evidence.
- `consent_required_flag` — TRUE for Wi-Fi/BLE, which remains personal data (Art. 29 WP Opinion
  05/2014 on hashing as pseudonymisation; EDPB Guidelines 01/2025 confirming pseudonymised data is
  still personal data; CNIL's October 2018 guidance requiring an operable opt-out both before and
  after collection).
- `retention_days_max` — per deployment, for the reasons above.
- `staff_exclusion_method` and `staff_exclusion_stage`, linking the analytic requirement to its
  governance consequence.

Prohibited inferences are modelled as **values the schema rejects**, not as gated options: emotion
recognition in a workplace is prohibited outright by AI Act Art. 5(1)(f) (in force 2025-02-02), and
biometric categorisation to deduce protected characteristics by Art. 5(1)(g). A store is the
associates' workplace, so these are bans rather than high-risk classifications. Note the Digital
Omnibus (Reg. (EU) 2026/1744, in force 2026-07-27) postponed **Annex III high-risk** obligations to
2027-12-02 but did **not** postpone the prohibitions or the Art. 50(3) notice.

## Consequences

- Every sensing measurement is joinable to its governance record, so "may we hold this?" is a query
  rather than an investigation. This is the main benefit and the reason it is a dimension rather than
  documentation.
- The dimension is SCD2 because deployments change: a DPIA is revised, signage is added, a lawful basis
  changes. The governance record that applied *at the time of measurement* is what an audit asks for.
- It is a `master`-tagged dimension inside a gold package, which precedent allows
  (`balancing-margin-and-volume/tables/competitor.sql`) and ADR 0021 supports — `PK-CONTRACT` and
  `FK-COMPLETENESS` are canonical-core-only gates.
- Modelled once and reused by all four CSS use cases, so IoT, RFID, and Smart Shelf inherit the
  governance layer rather than each re-deriving it.
- Overlaps ADR 0027's consent overlay in spirit but not in scope. If a future package needs both,
  reconcile then; premature unification would force person-level consent semantics onto deployments
  that have no identified individual.
- Populating it honestly requires input from privacy counsel per deployment. That is a real adoption
  cost, and stating it is preferable to shipping a model that implies the analysis is unnecessary.
