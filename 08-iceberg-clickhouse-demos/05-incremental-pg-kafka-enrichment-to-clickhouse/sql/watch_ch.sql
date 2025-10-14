SELECT COUNT(*) AS record_count FROM ch_enriched_sales_analytics FINAL;

SELECT * FROM ch_enriched_sales_analytics FINAL ORDER BY kafka_ingestion_time DESC, product_last_updated DESC LIMIT 10;

