-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Associate context event ingest — adopter SDP / Auto Loader template
-- MAGIC
-- MAGIC ORDM · Outcome Package · AI-Assisted Store Associates · Version 0.5
-- MAGIC
-- MAGIC Makes the **≤ 5 min inventory overlay** claim operationally real by documenting
-- MAGIC (not shipping) a Lakeflow path into `associate_context_event`.
-- MAGIC
-- MAGIC ORDM does **not** own ingestion (CONTRIBUTING §2). Adapt this notebook in the
-- MAGIC adopter workspace: point Auto Loader at your landing volume, map source fields
-- MAGIC onto the package contract, MERGE on `associate_context_event_id`, then refresh
-- MAGIC the inventory / order materialized views.
-- MAGIC
-- MAGIC Parameters: `${catalog}`, `${aasa_schema}`, and a landing path widget.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 0. Widgets / landing path
-- MAGIC Replace the volume path with your bronze landing zone for inventory/OMS CDC JSON.

-- COMMAND ----------

-- Example widgets (set in the notebook UI or job params):
-- catalog, aasa_schema, landing_path
-- CREATE WIDGET TEXT landing_path DEFAULT '/Volumes/<catalog>/<schema>/associate_events/landing'

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Streaming bronze (Auto Loader)
-- MAGIC Incremental file ingest. Keep identity columns out of the landing schema —
-- MAGIC `associate_context_event_sk` is GENERATED ALWAYS on the package table.

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE ${catalog}.${aasa_schema}.stg_associate_context_event_landing
COMMENT 'Adopter staging only — not part of the published ORDM contract. Drop or rename in your workspace.'
AS SELECT
  associate_context_event_id,
  event_domain,
  event_type,
  store_id,
  product_id,
  order_id,
  promo_id,
  equipment_id,
  CAST(quantity_on_hand AS DECIMAL(12,3)) AS quantity_on_hand,
  CAST(quantity_available AS DECIMAL(12,3)) AS quantity_available,
  CAST(quantity_reserved AS DECIMAL(12,3)) AS quantity_reserved,
  CAST(quantity_in_transit AS DECIMAL(12,3)) AS quantity_in_transit,
  CAST(unit_price_amount AS DECIMAL(18,4)) AS unit_price_amount,
  currency_code,
  status_code,
  location_code,
  event_payload_summary,
  source_system,
  CAST(event_timestamp AS TIMESTAMP) AS event_timestamp,
  CAST(ingest_timestamp AS TIMESTAMP) AS ingest_timestamp,
  _metadata.file_path AS _source_file
FROM STREAM read_files(
  -- Replace with widget / job param in the adopter job:
  '/Volumes/${catalog}/${aasa_schema}/associate_events/landing',
  format => 'json',
  schemaHints => '''
    associate_context_event_id STRING,
    event_domain STRING,
    event_type STRING,
    store_id STRING,
    product_id STRING,
    order_id STRING,
    promo_id STRING,
    equipment_id STRING,
    quantity_on_hand DOUBLE,
    quantity_available DOUBLE,
    quantity_reserved DOUBLE,
    quantity_in_transit DOUBLE,
    unit_price_amount DOUBLE,
    currency_code STRING,
    status_code STRING,
    location_code STRING,
    event_payload_summary STRING,
    source_system STRING,
    event_timestamp TIMESTAMP,
    ingest_timestamp TIMESTAMP
  '''
);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Idempotent merge into the package contract
-- MAGIC Deduplicate on durable `associate_context_event_id`. Late / out-of-order events
-- MAGIC are retained when they are new ids; re-delivery of the same id is a no-op /
-- MAGIC update of mutable payload fields only.

-- COMMAND ----------

MERGE INTO ${catalog}.${aasa_schema}.associate_context_event AS tgt
USING (
  SELECT *
  FROM ${catalog}.${aasa_schema}.stg_associate_context_event_landing
  WHERE associate_context_event_id IS NOT NULL
    AND event_domain IN ('inventory', 'price', 'promotion', 'order', 'operations')
    AND event_timestamp IS NOT NULL
) AS src
ON tgt.associate_context_event_id = src.associate_context_event_id
WHEN MATCHED THEN UPDATE SET
  tgt.quantity_on_hand = src.quantity_on_hand,
  tgt.quantity_available = src.quantity_available,
  tgt.quantity_reserved = src.quantity_reserved,
  tgt.quantity_in_transit = src.quantity_in_transit,
  tgt.unit_price_amount = src.unit_price_amount,
  tgt.status_code = src.status_code,
  tgt.location_code = src.location_code,
  tgt.event_payload_summary = src.event_payload_summary,
  tgt.ingest_timestamp = COALESCE(src.ingest_timestamp, current_timestamp()),
  tgt.processed_timestamp = current_timestamp(),
  tgt.latency_seconds = CAST(
    unix_timestamp(COALESCE(src.ingest_timestamp, current_timestamp()))
    - unix_timestamp(src.event_timestamp) AS INT
  ),
  tgt.load_timestamp = current_timestamp()
WHEN NOT MATCHED THEN INSERT (
  associate_context_event_id,
  event_domain,
  event_type,
  store_id,
  product_id,
  order_id,
  promo_id,
  equipment_id,
  quantity_on_hand,
  quantity_available,
  quantity_reserved,
  quantity_in_transit,
  unit_price_amount,
  currency_code,
  status_code,
  location_code,
  event_payload_summary,
  source_system,
  event_timestamp,
  ingest_timestamp,
  processed_timestamp,
  latency_seconds,
  record_source,
  load_timestamp
) VALUES (
  src.associate_context_event_id,
  src.event_domain,
  src.event_type,
  src.store_id,
  src.product_id,
  src.order_id,
  src.promo_id,
  src.equipment_id,
  src.quantity_on_hand,
  src.quantity_available,
  src.quantity_reserved,
  src.quantity_in_transit,
  src.unit_price_amount,
  COALESCE(src.currency_code, 'USD'),
  src.status_code,
  src.location_code,
  src.event_payload_summary,
  src.source_system,
  src.event_timestamp,
  COALESCE(src.ingest_timestamp, current_timestamp()),
  current_timestamp(),
  CAST(
    unix_timestamp(COALESCE(src.ingest_timestamp, current_timestamp()))
    - unix_timestamp(src.event_timestamp) AS INT
  ),
  'adopter_autoloader',
  current_timestamp()
);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Refresh associate serving MVs
-- MAGIC After a successful merge, refresh the point-lookup surfaces (no-op when demoted).

-- COMMAND ----------

REFRESH MATERIALIZED VIEW ${catalog}.${aasa_schema}.gold_associate_product_inventory_current;
REFRESH MATERIALIZED VIEW ${catalog}.${aasa_schema}.gold_associate_order_status_current;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Freshness smoke check
-- MAGIC Expect inventory overlays with `inventory_basis = event_overlay` and lag within SLA
-- MAGIC when the landing path is catching up.

-- COMMAND ----------

SELECT feed_name, store_id, freshness_status, freshness_lag_minutes, sla_state
FROM ${catalog}.${aasa_schema}.gold_associate_data_freshness
ORDER BY freshness_lag_minutes DESC NULLS LAST
LIMIT 50;
