# Market and trade activity surveillance

Detect suspicious patterns, compliance breaches, and anomalies from trading activities in real-time.

Follow the instructions below to learn how to run this demo. 

For more details about the process and the use case, see the official documentation.

## Step 1: Install and run a RisingWave instance

See the [installation guide](/00-get-started/00-install-kafka-pg-rw.md#install-risingwave) for more details.

## Step 2: Create tables in RisingWave

Run the following two queries to set up your tables in RisingWave.

```sql
CREATE TABLE trade_data (
    trade_id INT,
    asset_id INT,
    timestamp TIMESTAMP,
    price FLOAT,
    volume INT,
    buyer_id INT,
    seller_id INT
);
```

```sql
CREATE TABLE market_data (
    asset_id INT,
    timestamp TIMESTAMP,
    bid_price FLOAT,
    ask_price FLOAT,
    price FLOAT,
    rolling_volume INT
);
```

## Step 3: Run the data generator

Ensure that you have a Python environment set up and have installed the psycopg2 library. Run the [data generator](02-simple-demos/capital_markets/market_surveillance/data_generator.py).

This will start inserting mock data into the tables created above.

## Step 4: Create materialized views

Run the following queries to create materialized views to analyze the data.

```sql
CREATE MATERIALIZED VIEW unusual_volume AS
SELECT
    trade_id,
    asset_id,
    volume,
    CASE WHEN volume > AVG(volume) OVER (PARTITION BY asset_id ORDER BY timestamp RANGE INTERVAL '10 MINUTES' PRECEDING) * 1.5
         THEN TRUE ELSE FALSE END AS unusual_volume,
    timestamp
FROM
    trade_data;
```

```sql
CREATE MATERIALIZED VIEW price_spike AS
SELECT
    asset_id,
    (MAX(price) OVER (PARTITION BY asset_id ORDER BY timestamp 
                      RANGE INTERVAL '5 MINUTES' PRECEDING) -
     MIN(price) OVER (PARTITION BY asset_id ORDER BY timestamp 
                      RANGE INTERVAL '5 MINUTES' PRECEDING)) /
     MIN(price) OVER (PARTITION BY asset_id ORDER BY timestamp 
                      RANGE INTERVAL '5 MINUTES' PRECEDING) AS percent_change,
    CASE 
        WHEN 
            (MAX(price) OVER (PARTITION BY asset_id ORDER BY timestamp 
                              RANGE INTERVAL '5 MINUTES' PRECEDING) -
             MIN(price) OVER (PARTITION BY asset_id ORDER BY timestamp 
                              RANGE INTERVAL '5 MINUTES' PRECEDING)) /
             MIN(price) OVER (PARTITION BY asset_id ORDER BY timestamp 
                              RANGE INTERVAL '5 MINUTES' PRECEDING) * 100 > 5 
        THEN TRUE 
        ELSE FALSE 
    END AS if_price_spike,
    timestamp
FROM
    market_data;
```

```sql
CREATE MATERIALIZED VIEW spoofing_detection AS
SELECT
    m.asset_id,
    m.timestamp,
    CASE WHEN ABS(m.bid_price - m.ask_price) < 0.2 AND rolling_volume < AVG(rolling_volume) OVER (PARTITION BY asset_id ORDER BY timestamp RANGE INTERVAL '10 MINUTES' PRECEDING) * 0.8
         THEN TRUE ELSE FALSE END AS potential_spoofing
FROM
    market_data AS m;
```