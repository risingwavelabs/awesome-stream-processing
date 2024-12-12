# Market data enhancement and transformation

Transform raw market data in real-time to provide insights into market trends, health, and trade opportunities.

Follow the instructions below to learn how to run this demo. 

For more details about the process and the use case, see the official documentation.

## Step 1: Install and run a RisingWave instance

See the [installation guide](/00-get-started/00-install-kafka-pg-rw.md#install-risingwave) for more details.

## Step 2: Create tables in RisingWave

Run the following two queries to set up your tables in RisingWave.

```sql
CREATE TABLE raw_market_data (
    asset_id INT,
    timestamp TIMESTAMPTZ,
    price NUMERIC,
    volume INT,
    bid_price NUMERIC,
    ask_price NUMERIC
);
```

```sql
CREATE TABLE enrichment_data (
    asset_id INT,
    sector VARCHAR,
    historical_volatility NUMERIC,
    sector_performance NUMERIC,
    sentiment_score NUMERIC,
    timestamp TIMESTAMPTZ
);
```

## Step 3: Run the data generator

Ensure that you have a Python environment set up and have installed the psycopg2 library. Run the [data generator](02-simple-demos/capital_markets/market_data_enrichment/data_generator.py).

This will start inserting mock data into the tables created above.

## Step 4: Create materialized views

Run the following queries to create materialized views to analyze the data.

```sql
CREATE MATERIALIZED VIEW avg_price_bid_ask_spread AS
SELECT
    asset_id,
    ROUND(AVG(price) OVER (PARTITION BY asset_id ORDER BY timestamp RANGE INTERVAL '5 MINUTES' PRECEDING), 2) AS average_price,
    ROUND(AVG(ask_price - bid_price) OVER (PARTITION BY asset_id ORDER BY timestamp RANGE INTERVAL '5 MINUTES' PRECEDING), 2) AS bid_ask_spread,
    timestamp
FROM
    raw_market_data;
```

```sql
CREATE MATERIALIZED VIEW rolling_volatility AS
SELECT
    asset_id,
    ROUND(stddev_samp(price) OVER (PARTITION BY asset_id ORDER BY timestamp RANGE INTERVAL '15 MINUTES' PRECEDING), 2) AS rolling_volatility,
    timestamp
FROM
    raw_market_data;
```

```sql
CREATE MATERIALIZED VIEW enriched_market_data AS
SELECT
    rmd.asset_id,
    avg_price_bid_ask_spread.average_price,
    (rmd.price - avg_price_bid_ask_spread.average_price) / avg_price_bid_ask_spread.average_price * 100 AS price_change,
    avg_price_bid_ask_spread.bid_ask_spread,
    rolling_volatility.rolling_volatility,
    ed.sector_performance,
    ed.sentiment_score,
    rmd.timestamp
FROM
    raw_market_data AS rmd
JOIN
    avg_price_bid_ask_spread
ON
    rmd.asset_id = avg_price_bid_ask_spread.asset_id
JOIN
    rolling_volatility
ON
    rmd.asset_id = rolling_volatility.asset_id
JOIN
    enrichment_data AS ed
ON
    rmd.asset_id = ed.asset_id
WHERE
    rmd.timestamp = avg_price_bid_ask_spread.timestamp
    AND rmd.timestamp = rolling_volatility.timestamp
    AND rmd.timestamp = ed.timestamp;
```