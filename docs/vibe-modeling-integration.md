# Vibe Modeling Agent Integration

ORDM and the Vibe Modeling Agent are complementary — **product + factory**.

| | ORDM | Vibe Modeling Agent |
|---|---|---|
| What | Curated, reviewed reference data model | LLM-powered tool that authors/evolves models |
| Form | Schemas + semantics + synthetic data | Code-gen tool (separate OSS repo) |
| Role | The shared baseline | Adapts the baseline to a customer's reality |

## Two ways they work together

1. **Factory → product**: the agent generates candidate models; the working group curates and hardens the best into ORDM.
2. **"Meet customers where they are"**: customers rarely start clean. The agent helps adapt ORDM (and its outcome packages) to a customer's existing data landscape — their naming, source systems, custom entities — keeping what fits and customizing what doesn't.

Neither tool ingests or scans customer data as part of the open artifacts; the agent runs in the adopter's own environment.

ORDM gives you the shared, reviewed baseline; the agent helps you adapt it to your environment.
