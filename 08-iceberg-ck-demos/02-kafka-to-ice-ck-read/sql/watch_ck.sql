USE lakekeeper_catalog;

SELECT COUNT(*) AS record_count FROM `public.iceberg_sales`;

SELECT * FROM `public.iceberg_sales` ORDER BY ingestion_time DESC LIMIT 10;

