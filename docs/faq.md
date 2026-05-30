# FAQ

**Is ORDM a tool that scans my data?**
No. ORDM is reference architecture — schemas, semantic models, synthetic data, docs. It ships no code that ingests, scans, or reaches into customer systems.

**What license?**
Published ORDM artifacts use Apache 2.0. This staging repo is not licensed for distribution until publication.

**Silver or gold layer?**
Both, as applicable. Canonical core ≈ silver (conformed entities); outcome packages ≈ gold + semantic. See [architecture](architecture.md).

**Do I have to adopt ORDM as-is?**
No. It's a baseline. Use the Vibe Modeling Agent to adapt it to your environment. See [vibe-modeling-integration](vibe-modeling-integration.md).

**What stays private?**
Bronze, source-aligned silver, partner accelerators, proprietary source mappings, customer-specific schemas. See the [IP boundary](architecture.md#open-vs-private-boundary).

**How do I contribute?**
We welcome issues and pull requests from the retail community. Accepted contributions may require signing a Contributor License Agreement (CLA) — see the Contributing section in the [README](../README.md#contributing).
