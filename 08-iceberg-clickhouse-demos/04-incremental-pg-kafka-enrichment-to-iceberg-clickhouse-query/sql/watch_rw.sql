\pset pager off
\set ECHO queries

SET iceberg_engine_connection = 'public.lakekeeper_catalog_conn';;

-- Verify historical data ingestion
SELECT COUNT(*) AS record_count 
FROM enriched_sales_iceberg;

-- Check recent sales activity
SELECT * FROM enriched_sales_iceberg ORDER BY kafka_ingestion_time DESC,product_last_updated DESC LIMIT 10;
