# Tools

Shared infrastructure for the repository.

The generators and checks that `make regen` / `make check` run live here as scripts (see the
[Makefile](../Makefile)). `release.py` checks that every version stamp agrees with the
[`VERSION`](../VERSION) file and cuts a release; see [docs/releasing.md](../docs/releasing.md).

The static conformance checks run via `pytest tests/standards` (see [../docs/testing.md](../docs/testing.md)).
