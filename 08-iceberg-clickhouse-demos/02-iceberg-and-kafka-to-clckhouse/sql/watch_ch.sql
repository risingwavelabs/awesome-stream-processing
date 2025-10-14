-- Query examples to verify data ingestion
SELECT data_source, COUNT(*) AS record_count 
FROM ch_sales_analytics 
GROUP BY data_source
ORDER BY record_count;

-- Check recent sales activity
SELECT * FROM ch_sales_analytics ORDER BY ingestion_time DESC LIMIT 10;
