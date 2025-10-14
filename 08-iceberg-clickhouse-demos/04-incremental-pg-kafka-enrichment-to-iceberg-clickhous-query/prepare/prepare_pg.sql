/*
  Populate an OLTP Postgres product table using a RisingWave datagen source.

  What this does:
  - Generates a finite product catalog (IDs 301..320) using datagen.
  - Maps each product_id to a deterministic product_name, category.
  - Streams the result into the OLTP Postgres database via a JDBC sink.

  Target database (from docker-compose):
	host=oltp, port=5432, db=mydb, user=myuser, password=123456
*/

-- Use a dedicated schema for this prep
CREATE SCHEMA IF NOT EXISTS data_gen;

-- Step 1: Finite datagen source for product ids 301..320
CREATE TABLE IF NOT EXISTS data_gen.product_gen (
	product_id INTEGER PRIMARY KEY,
    list_price INTEGER,
    active INTEGER,
    updated_at TIMESTAMPTZ as proctime()
) WITH (
	connector = 'datagen',
	fields.product_id.kind = 'random',
	fields.product_id.min = '301',
	fields.product_id.max = '320',
    fields.list_price.kind = 'random',
    fields.list_price.min = '1000',
    fields.list_price.max = '5000',
    fields.active.kind = 'random',
	fields.active.min = '0',
	fields.active.max = '1',
	datagen.rows.per.second = '1'
);

-- Step 2: Deterministic mapping to name/category/price and extra attributes
-- This view will emit exactly 20 rows, one per product_id in the sequence above.
CREATE SINK IF NOT EXISTS data_gen.pg_product_sink AS
SELECT
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
	END AS product_name,
	CASE product_id 
		WHEN 301 THEN 'Phones'
		WHEN 302 THEN 'Laptops'
		WHEN 303 THEN 'Tablets'
		WHEN 304 THEN 'Audio'
		WHEN 305 THEN 'Wearables'
		WHEN 306 THEN 'Desktops'
		WHEN 307 THEN 'Displays'
		WHEN 308 THEN 'Accessories'
		WHEN 309 THEN 'Accessories'
		WHEN 310 THEN 'Streaming'
		WHEN 311 THEN 'Audio'
		WHEN 312 THEN 'Accessories'
		WHEN 313 THEN 'Phones'
		WHEN 314 THEN 'Laptops'
		WHEN 315 THEN 'Tablets'
		WHEN 316 THEN 'Accessories'
		WHEN 317 THEN 'Accessories'
		WHEN 318 THEN 'Accessories'
		WHEN 319 THEN 'Audio'
		ELSE 'Phones'
	END AS category,
	list_price,
	'USD'::VARCHAR AS currency,
    CASE active
        WHEN 1 THEN true
        ELSE false
    END AS active,
	updated_at
FROM data_gen.product_gen
WITH (
	connector = 'jdbc',
	jdbc.url = 'jdbc:postgresql://oltp:5432/mydb',
	user = 'myuser',
	password = '123456',
	table.name = 'product',
	type = 'upsert',
	primary_key = 'product_id'
);

