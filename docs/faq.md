# FAQ

**Is ORDM a tool that scans my data?**
No. ORDM is reference architecture — schemas, semantic models, synthetic data, docs. It ships no code that ingests, scans, or reaches into customer systems.

**What license?**
Published ORDM artifacts use Apache 2.0.

**Silver or gold layer?**
Both, as applicable. Canonical core ≈ silver (conformed entities); outcome packages ≈ gold + semantic. See [architecture](architecture.md).

**Do I have to adopt ORDM as-is?**
No. It's a baseline. Use the Vibe Modeling Agent to adapt it to your environment. See [vibe-modeling-integration](vibe-modeling-integration.md).

**What stays private?**
Bronze, source-aligned silver, partner accelerators, proprietary source mappings, customer-specific schemas. See the [IP boundary](architecture.md#open-vs-private-boundary).

**How do I contribute?**
We welcome issues and pull requests from the retail community. Contributions are released under the project's Apache License 2.0 (inbound = outbound); no separate CLA or DCO sign-off is required — see [CONTRIBUTING.md](../CONTRIBUTING.md).
