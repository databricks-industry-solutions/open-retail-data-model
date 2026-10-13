# ODCS data contracts (generated, optional)

These `*.odcs.yaml` files are **generated** by `tools/generate_odcs.py` from ORDM's committed source of truth (the DDL, `relationships.sql`, `checks.sql`, `comments.sql` and `glossary.md`). They are an [Open Data Contract Standard](https://bitol.io/) v3.1.0 rendering of the model — one contract per canonical-core domain and per outcome package.

**This is an optional integration.** ORDM does not depend on these files: the deploy, the data-quality run, the tests and CI all read the SQL, never these YAMLs. If you do not use ODCS, ignore this directory. See [`docs/odcs-integration.md`](../../docs/odcs-integration.md) for the full mapping, how to run the generator, and the optional downstream consumers (DQX, Lockstep, Ontos).

## Do not edit by hand

Regenerate instead, so the contracts never drift from the model:

```sh
python tools/generate_odcs.py --catalog <your_catalog>
```

The committed copies here use a catalog-agnostic `schema.table` physical name (no `--catalog`); pass `--catalog` to bind them to a specific Unity Catalog.
