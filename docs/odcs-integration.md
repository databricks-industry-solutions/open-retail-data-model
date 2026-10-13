# ODCS data contracts (optional integration)

This explains how ORDM can emit [Open Data Contract Standard](https://bitol.io/) (ODCS) v3.1.0 data contracts, and how contract-driven tools can consume them. It is written as something an adopter **may** use, not a dependency: ORDM's source of truth stays the committed DDL, `checks.sql`, `relationships.sql` and `glossary.md`, and the model deploys and is fully usable without ever touching ODCS.

## Why this is optional

ODCS (Bitol, a Linux Foundation project) is an open, vendor-neutral YAML standard for describing a dataset's schema, quality rules, relationships, ownership and classification. It is a good fit for ORDM because every field an ODCS contract wants already exists in ORDM as a structured artifact. But ODCS adoption is still relatively niche, and requiring it would add friction for the majority of adopters who do not use it. So ORDM offers a **generator** that derives contracts from what is already committed. The deploy (`tools/apply_model_ddl.py`) and data-quality run (`runtime/data-quality/run_checks.py`) do not depend on them, but CI diffs the contracts to catch schema drift, tests validate their structure, and the model explorer links them to the tables they describe. If you do not want ODCS, ignore this page.

There is no native Unity Catalog data-contract object; ODCS contracts are authored outside UC and projected onto UC objects (tables, tags, constraints, lineage) by whatever tool you point at them.

## What it maps to

`tools/generate_odcs.py` reads the committed artifacts and emits one ODCS v3.1.0 `DataContract` YAML per canonical-core domain and per outcome package. The mapping is direct:

| ORDM artifact | ODCS v3.1.0 |
|---|---|
| `tables/*.sql` `CREATE TABLE`, `gold/*.sql` view | one `schema[]` object (`physicalType: table` / `view`) |
| columns + SQL type + `NOT NULL` | `schema[].properties[]` with `logicalType` / `physicalType` / `required` |
| `CONSTRAINT ... PRIMARY KEY (col)` | property `primaryKey` / `primaryKeyPosition` |
| column `COMMENT '...'` and `comments.sql` | property `description` |
| `dbx_pii*` column tags | property `classification: restricted` + `tags` (the originating tag names, preserved) |
| `dbx_data_type` table tag | object `tags` (the layer/role, e.g. `master`) |
| `relationships.sql` `FOREIGN KEY` | property-level `relationships[]` (`type: foreignKey`); composite keys go object-level. UC FKs are informational, so `enforced: false` is recorded |
| `relationships.sql` enum `CHECK` | a property-level `quality` rule (`type: text`, `dimension: validity`) listing the allowed values |
| `checks.sql` `-- check: <name> \| severity:` + `SELECT` | an object-level `quality` rule (`type: sql`), carrying the check's SQL as `query` with `mustBe: 0` (ORDM checks select the violating rows, so a passing contract returns none) |
| `README.md` / `glossary.md` / `docs/data-model-standards.md` | `authoritativeDefinitions[]` (repo-relative links back to the true source) |
| `metric-views/*.sql` (UC metric views) | `schema[]` view object tagged `metric-view`. Columns are read from the `WITH METRICS LANGUAGE YAML` body (sqlglot cannot parse it): `fields` then `measures` become `properties[]` with a `logicalType` and the YAML `comment` as `description`. The type is inferred from the metric view's `source:` by the same sqlglot annotation used for gold views (so a date dimension is `date` and a `COUNT` is `integer`); where that cannot resolve, an explicit `format.type` applies, else a measure defaults to `number` and a field is left without a `logicalType` (as an unresolvable gold-view column is), rather than guessed. Each column's `display_name` becomes the property `businessName` and its `synonyms` a `synonyms` entry in `customProperties`, so a Genie-style consumer can resolve the same terms. They are computed, so no `physicalType` is emitted. The YAML top-level `comment:` is the object `description`. |

The catalog and schema are never hardcoded. As everywhere else in the repo, tokens (`${catalog}`, `${<domain>_schema}`) resolve through the shared resolver `tools/ordm_config.py`, which reads `databricks.yml`. `--catalog` sets the catalog in each object's `physicalName`; schema names come from the `variables` defaults and can be overridden per token.

Because the generated files are deterministic (stable ids, insertion-ordered keys), they are committed as a lockfile: re-running `generate_odcs.py` and checking `git diff --exit-code` catches any schema change not reflected in the contracts. This drift check is wired into CI via `make check-odcs`, gated on push to `main` and on fork PRs; on same-repo PRs, `regen-artifacts` regenerates and auto-commits them instead.

## Running the generator

Pure Python plus PyYAML, no Spark and no workspace, so it runs anywhere:

```sh
pip install -r requirements.txt          # PyYAML

# All domains and packages -> contracts/odcs/<name>.odcs.yaml
python tools/generate_odcs.py --catalog retail_prod

# A subset
python tools/generate_odcs.py --include customer,product --catalog retail_prod

# A single unit to stdout (no files written)
python tools/generate_odcs.py --domain customer --out -

# Override a schema name for one token (same flags as the deploy)
python tools/generate_odcs.py --domain store --store_schema retail_store --catalog retail_prod
```

Placeholder packages that have no DDL yet are skipped. Omitting `--catalog` produces `schema.table` physical names (catalog-agnostic).

## Optional downstream consumers

Once a contract exists, several tools can execute or enforce it. All of them consume ORDM's own artifacts and none is a dependency; each is an opt-in overlay an adopter can add.

- **DQX** ([`databrickslabs/dqx`](https://github.com/databrickslabs/dqx)) can run the contract's data-quality rules as runtime checks on Databricks. This is the natural complement to ORDM's own `runtime/data-quality/run_checks.py`, which executes the `checks.sql` assertions. The ODCS `quality` rules carry that SQL, mapping severity faithfully: `error`/`warn` checks become row-count assertions (`mustBe: 0`, since the SELECT returns violating rows), while `metric` checks are carried as **informational** (`severity: info`, no `mustBe`) because they report an aggregate, not violations. A check whose SELECT targets another schema or `information_schema` (so it maps to no single object) is **logged and omitted** rather than mis-attached — so the contract mirrors `checks.sql` for every object-scoped assertion, and the generator surfaces any it could not attach.
- **Lockstep** can synchronize an ODCS contract with Unity Catalog, projecting the contract's descriptions, tags, classifications and constraints onto the physical UC objects.
- **Ontos** ([`databrickslabs/ontos`](https://github.com/databrickslabs/ontos), Databricks Labs, community-supported / AS-IS) is a Business Catalog app for UC that can register the contracts as governed data products (it imports ODCS v3.1.0 and can round-trip it). ORDM tables presented as data products with their contracts is one way to organize a deployed model, separate from the deploy itself.

These are named as factual, vendor-neutral integration points. Support and licensing terms are each project's own; evaluate them independently. ORDM stays deployable and consumable with none of them present.

## Pushing contracts to Ontos

`tools/push_contracts_to_ontos.py` is an optional convenience that uploads the generated contracts into a running Ontos deployment via its REST API, so they appear as Ontos data contracts without hand copy-paste. Like everything here it is opt-in: ORDM does not depend on it, and it only *sends* the contracts the generator already produced — it changes nothing in the model.

```bash
# a subset, authenticating via a Databricks CLI profile
python tools/push_contracts_to_ontos.py --app-url <ONTOS_APP_URL> --profile <PROFILE> --include store,customer

# every contract (explicit opt-in), or preview with --dry-run
python tools/push_contracts_to_ontos.py --app-url <ONTOS_APP_URL> --profile <PROFILE> --all
python tools/push_contracts_to_ontos.py --app-url <ONTOS_APP_URL> --all --dry-run

# CI: supply a bearer token via an env var instead of a CLI profile
python tools/push_contracts_to_ontos.py --app-url <ONTOS_APP_URL> --token-env ONTOS_TOKEN --all
```

Notes:

- **Selection is explicit.** With no `--include`, `--contracts-glob`, or `--all`, the tool pushes nothing and prints how to select — so a bare run can never fire every contract at a live deployment.
- **Auth** is a user (or service-principal) OAuth bearer token. Ontos runs as a Databricks App behind on-behalf-of auth and accepts that token as the caller; the tool mints it via `databricks auth token` (or reads `--token-env`) and never stores or logs it.
- **TLS** verification is always on. Behind corporate TLS interception, install `truststore` (the tool then uses the OS trust store automatically) or set `SSL_CERT_FILE` to your proxy CA bundle. Stdlib-only otherwise.
- **Fidelity caveat.** At the time of writing, Ontos's ODCS importer preserves schema, columns, descriptions, domain, and authoritative-definition links, but does **not** yet persist primary keys or object-level quality rules on import. This is an Ontos-side limitation, not a property of the contracts (which carry both); the tool transmits the full contract, so fidelity improves automatically once Ontos is updated. Re-uploading also creates a new contract rather than updating the existing one (no upsert on the contract's stable id yet), so treat repeated pushes accordingly.

**From a Databricks notebook.** `runtime/examples/notebooks/push_contracts_to_ontos.ipynb` runs the same tool from inside a workspace: it derives the repo root from its own path, puts the sibling `tools/` on `sys.path`, and calls the tool's importable functions (`find_contracts`, `push_paths`), so no logic is duplicated. It takes its inputs as notebook widgets (contracts folder, app URL, a blank-means-all contracts filter, dry-run). Because Ontos sits behind a Databricks Apps OAuth proxy, the notebook authenticates with an OAuth token: **`current_user`** (default) looks up the app's OAuth client id (`WorkspaceClient().apps.get(...).oauth2_app_client_id`) and exchanges the notebook's token at the workspace `/oidc/v1/token` endpoint for an app-audience-scoped token the proxy accepts; **`secret`** reads a pre-minted bearer from a secret scope (service principal or another workspace). The command-line entry point is unchanged and remains fully standalone.

## Where this sits relative to the rest of the model

The generator is deliberately downstream of everything else. It reads the committed DDL, relationships, checks and glossary; it never writes to them, and the deploy, the DQ run and the tests do not read the generated contracts. That keeps the source of truth singular and lets ODCS come and go without touching the model. See [`data-model-standards.md`](data-model-standards.md) for the standard the DDL follows and [`testing.md`](testing.md) for how the committed artifacts are validated.
