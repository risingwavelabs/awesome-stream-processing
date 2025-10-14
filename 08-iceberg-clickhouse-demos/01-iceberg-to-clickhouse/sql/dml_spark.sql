-- ============================================================================
-- Spark SQL Demo: Iceberg DML Operations (INSERT, UPDATE, DELETE)
-- ============================================================================
-- This demo shows how to perform DML operations on Iceberg tables via Spark SQL
-- The 'lake' catalog is pre-configured to use Lakekeeper REST catalog
-- 
-- NOTE: This file is designed to be run step-by-step interactively.
-- Use the companion script: ./demo_spark.sh
-- Or run manually in spark-sql CLI, executing one section at a time.
-- ============================================================================

-- Step 1: Display table schema
DESCRIBE EXTENDED lake.public.sales_history;

-- Step 2: Insert sample historical data (batch 1, sales_id 1001-1009)
INSERT INTO lake.public.sales_history VALUES
(1001, 101, 201, 'iPhone 15 Pro', CAST('2024-01-15 10:30:00' AS TIMESTAMP), 1, 999, 999, 'USD', 1, 'North America', 'Credit Card', 0),
(1002, 102, 202, 'MacBook Air M3', CAST('2024-01-15 11:45:00' AS TIMESTAMP), 1, 1299, 1169, 'USD', 1, 'North America', 'Debit Card', 129),
(1003, 103, 203, 'AirPods Pro', CAST('2024-01-16 09:15:00' AS TIMESTAMP), 2, 249, 498, 'USD', 2, 'Europe', 'PayPal', 0),
(1004, 104, 204, 'iPad Pro 12.9', CAST('2024-01-16 14:20:00' AS TIMESTAMP), 1, 1099, 1044, 'USD', 3, 'Asia Pacific', 'Credit Card', 54),
(1005, 105, 205, 'Apple Watch Series 9', CAST('2024-01-17 16:30:00' AS TIMESTAMP), 1, 399, 379, 'USD', 1, 'North America', 'Apple Pay', 19),
(1006, 106, 201, 'iPhone 15 Pro', CAST('2024-01-17 13:45:00' AS TIMESTAMP), 1, 999, 899, 'USD', 2, 'Europe', 'Credit Card', 99),
(1007, 107, 206, 'Mac Studio M2', CAST('2024-01-18 10:00:00' AS TIMESTAMP), 1, 1999, 1999, 'USD', 4, 'North America', 'Wire Transfer', 0),
(1008, 108, 207, 'Magic Keyboard', CAST('2024-01-18 15:15:00' AS TIMESTAMP), 3, 129, 387, 'USD', 2, 'Europe', 'Credit Card', 0),
(1009, 109, 208, 'Magic Mouse', CAST('2024-01-19 11:30:00' AS TIMESTAMP), 2, 79, 142, 'USD', 3, 'Asia Pacific', 'Debit Card', 15);


-- Step 3: Insert additional sales records (batch 2, sales_id 1010-1015)
INSERT INTO lake.public.sales_history VALUES
(1010, 110, 209, 'Apple TV 4K', CAST('2024-01-19 17:45:00' AS TIMESTAMP), 1, 179, 161, 'USD', 1, 'North America', 'Apple Pay', 17),
(1011, 111, 210, 'HomePod mini', CAST('2024-01-20 12:00:00' AS TIMESTAMP), 2, 99, 188, 'USD', 4, 'Europe', 'PayPal', 9),
(1012, 112, 202, 'MacBook Air M3', CAST('2024-01-20 14:30:00' AS TIMESTAMP), 1, 1299, 1234, 'USD', 3, 'Asia Pacific', 'Credit Card', 64),
(1013, 113, 211, 'AirTag 4-pack', CAST('2024-01-21 09:45:00' AS TIMESTAMP), 1, 99, 94, 'USD', 1, 'North America', 'Debit Card', 4),
(1014, 114, 212, 'iPhone 15', CAST('2024-01-21 16:15:00' AS TIMESTAMP), 1, 799, 719, 'USD', 2, 'Europe', 'Credit Card', 79),
(1015, 115, 213, 'iPad Air', CAST('2024-01-22 13:20:00' AS TIMESTAMP), 1, 599, 569, 'USD', 4, 'Asia Pacific', 'Apple Pay', 29);


-- Step 4: Insert one more sales record (batch 3, sales_id 1016)
INSERT INTO lake.public.sales_history VALUES
(1016, 116, 214, 'iPad Air', CAST('2024-01-22 13:20:00' AS TIMESTAMP), 1, 599, 569, 'USD', 4, 'Asia Pacific', 'Apple Pay', 29);


-- Step 5: Show total count after INSERTs (should be 16 records)
SELECT COUNT(*) as total_records FROM lake.public.sales_history;

-- Step 6: Point update (single record, sale_id 1014, product_name changed to '**UPDATED PRODUCT NAME**')
UPDATE lake.public.sales_history set product_name='**UPDATED PRODUCT NAME**' where sale_id=1014;

-- Step 7: Bulk update (multiple records, sale_id 1001-1005, product_name changed to '**MORE UPDATED PRODUCT NAME**')
UPDATE lake.public.sales_history set product_name='**MORE UPDATED PRODUCT NAME**' where sale_id<=1005;
