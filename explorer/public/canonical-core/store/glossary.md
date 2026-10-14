# Store Domain — Business Glossary

> Status: ✅ Published (0.5)

| Term | Definition |
|---|---|
| **Store** (`store`) | Conformed store / location master (SCD2). One selling location, versioned over time. |
| **GLN** | GS1 Global Location Number identifying the store location. A store business key. |
| **Store format** | Operating format of the location. Allowed values: `hypermarket`, `supermarket`, `convenience`, `drugstore`, `online`. |
| **Region / district** | Geographic roll-up attributes used to scope analytics. |

Surrogate `store_sk` is the join/FK target; `store_id` is the durable business key. `country_code` is ISO 3166-1 alpha-2.
