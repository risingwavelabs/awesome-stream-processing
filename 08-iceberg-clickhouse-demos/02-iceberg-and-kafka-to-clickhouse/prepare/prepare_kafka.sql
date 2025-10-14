/* 
    Populate sample data to Kafka topic.
    In the demo, we use RW to populate sample data to Kafka just for convenience.
    You can use other Kafka producer to populate sample data as well.
*/

-- This script creates a Kafka sink and uses datagen to produce example sales data
CREATE SCHEMA IF NOT EXISTS data_gen;

-- Step 1: Create a datagen source with fixed product catalog
CREATE SOURCE IF NOT EXISTS data_gen.sales_stream (
    sale_id INTEGER,
    user_id INTEGER,
    product_id INTEGER,
    product_name VARCHAR,
    sale_timestamp TIMESTAMPTZ,
    quantity INTEGER,
    unit_price INTEGER,
    total_price INTEGER,
    currency VARCHAR,
    store_id INTEGER,
    region VARCHAR,
    payment_method VARCHAR,
    discount_amount INTEGER
) WITH (
    connector = 'datagen',
    fields.sale_id.kind = 'sequence',
    fields.sale_id.start = '2000',
    fields.sale_id.end = '99999',
    
    fields.user_id.kind = 'random',
    fields.user_id.min = '200',
    fields.user_id.max = '999',
    
    fields.product_id.kind = 'random',
    fields.product_id.min = '301',
    fields.product_id.max = '320',

    fields.sale_timestamp.kind = 'random',
    fields.sale_timestamp.max_past = '0 days',
    fields.sale_timestamp.max_future = '1 days',
    
    fields.quantity.kind = 'random',
    fields.quantity.min = '1',
    fields.quantity.max = '3',
    
    fields.store_id.kind = 'random',
    fields.store_id.min = '1',
    fields.store_id.max = '5',
    
    fields.discount_amount.kind = 'random',
    fields.discount_amount.min = '0',
    fields.discount_amount.max = '99',
    
    datagen.rows.per.second = '1'
) FORMAT PLAIN ENCODE JSON;

-- Step 2: Create Kafka sink to send enriched sales data to sales-stream topic
CREATE SINK IF NOT EXISTS data_gen.sales_stream_sink AS 
SELECT 
    sale_id,
    user_id,
    product_id,
    CASE product_id 
        WHEN 301 THEN 'iPhone 15 Pro Max'
        WHEN 302 THEN 'MacBook Pro M3'
        WHEN 303 THEN 'iPad Pro 11-inch'
        WHEN 304 THEN 'AirPods Pro 2nd Gen'
        WHEN 305 THEN 'Apple Watch Ultra 2'
        WHEN 306 THEN 'Mac Mini M2'
        WHEN 307 THEN 'Studio Display'
        WHEN 308 THEN 'Magic Keyboard'
        WHEN 309 THEN 'Magic Mouse 3'
        WHEN 310 THEN 'Apple TV 4K'
        WHEN 311 THEN 'HomePod'
        WHEN 312 THEN 'AirTag'
        WHEN 313 THEN 'iPhone 15'
        WHEN 314 THEN 'MacBook Air M3'
        WHEN 315 THEN 'iPad Air'
        WHEN 316 THEN 'Apple Pencil Pro'
        WHEN 317 THEN 'MagSafe Charger'
        WHEN 318 THEN 'Lightning Cable'
        WHEN 319 THEN 'AirPods 3rd Gen'
        ELSE 'iPhone SE'
    END as product_name,
    sale_timestamp,
    quantity,
    CASE product_id 
        WHEN 301 THEN 1199
        WHEN 302 THEN 1599
        WHEN 303 THEN 799
        WHEN 304 THEN 249
        WHEN 305 THEN 799
        WHEN 306 THEN 599
        WHEN 307 THEN 1599
        WHEN 308 THEN 299
        WHEN 309 THEN 79
        WHEN 310 THEN 179
        WHEN 311 THEN 299
        WHEN 312 THEN 29
        WHEN 313 THEN 799
        WHEN 314 THEN 1099
        WHEN 315 THEN 599
        WHEN 316 THEN 129
        WHEN 317 THEN 39
        WHEN 318 THEN 19
        WHEN 319 THEN 179
        ELSE 429
    END as unit_price,
    CASE product_id 
        WHEN 301 THEN quantity * 1199 - discount_amount
        WHEN 302 THEN quantity * 1599 - discount_amount
        WHEN 303 THEN quantity * 799 - discount_amount
        WHEN 304 THEN quantity * 249 - discount_amount
        WHEN 305 THEN quantity * 799 - discount_amount
        WHEN 306 THEN quantity * 599 - discount_amount
        WHEN 307 THEN quantity * 1599 - discount_amount
        WHEN 308 THEN quantity * 299 - discount_amount
        WHEN 309 THEN quantity * 79 - discount_amount
        WHEN 310 THEN quantity * 179 - discount_amount
        WHEN 311 THEN quantity * 299 - discount_amount
        WHEN 312 THEN quantity * 29 - discount_amount
        WHEN 313 THEN quantity * 799 - discount_amount
        WHEN 314 THEN quantity * 1099 - discount_amount
        WHEN 315 THEN quantity * 599 - discount_amount
        WHEN 316 THEN quantity * 129 - discount_amount
        WHEN 317 THEN quantity * 39 - discount_amount
        WHEN 318 THEN quantity * 19 - discount_amount
        WHEN 319 THEN quantity * 179 - discount_amount
        ELSE quantity * 429 - discount_amount
    END as total_price,
    'USD' as currency,
    store_id,
    CASE (store_id % 3)
        WHEN 0 THEN 'North America'
        WHEN 1 THEN 'Europe'
        ELSE 'Asia Pacific'
    END as region,
    CASE (sale_id % 5)
        WHEN 0 THEN 'Credit Card'
        WHEN 1 THEN 'Debit Card'
        WHEN 2 THEN 'PayPal'
        WHEN 3 THEN 'Apple Pay'
        ELSE 'Bank Transfer'
    END as payment_method,
    discount_amount
FROM data_gen.sales_stream
WITH (
    connector = 'kafka',
    topic = 'sales-stream',
    properties.bootstrap.server = 'message_queue:29092',
) FORMAT PLAIN ENCODE JSON;
