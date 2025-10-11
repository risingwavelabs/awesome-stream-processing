SET allow_experimental_database_iceberg = 1;

USE lakekeeper_catalog;

SELECT COUNT(*) AS record_count FROM `public.enriched_sales_iceberg`;

SELECT * FROM `public.enriched_sales_iceberg` ORDER BY kafka_ingestion_time DESC,product_last_updated DESC LIMIT 10;

