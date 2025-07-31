# Market data enhancement and transformation

Transform raw market data in real-time to provide insights into market trends, health, and trade opportunities.

Follow the instructions below to learn how to run this demo. 

For more details about the process and the use case, see the [official documentation](https://docs.risingwave.com/demos/market-data-enrichment). (Note: Automated Gitpod Setup at end of page)

## Step 1: Launch Gitpod
Click the link below to open the Gitpod development environment and wait for environment set up.

[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/risingwavelabs/awesome-stream-processing)


## Step 2: Create topics in Kafka

Run the following commands in the terminal to create the kafka topics.

```terminal
docker-compose exec kafka kafka-topics.sh \
  --create \
  --topic raw_market_data \
  --bootstrap-server localhost:9092 \
  --partitions 1 \
  --replication-factor 1
```

```terminal
docker-compose exec kafka kafka-topics.sh \
  --create \
  --topic enrichment_data \
  --bootstrap-server localhost:9092 \
  --partitions 1 \
  --replication-factor 1
```


## Step 3: Create Sources in RisingWave

In a seperate terminal, load the sources in RisingWave.

```terminal
docker-compose exec postgres psql \
  -h risingwave -p 4566 -U root -d dev
```

```sql
CREATE SOURCE raw_market_data (
 asset_id     INT,
 timestamp    TIMESTAMPTZ,
 price        DOUBLE,
 volume       INT,
 bid_price    DOUBLE,
 ask_price    DOUBLE
) WITH (
 connector                   = 'kafka',
 topic                       = 'raw_market_data',
 properties.bootstrap.server = 'kafka:9092',
 scan.startup.mode           = 'earliest'
) FORMAT PLAIN ENCODE JSON;
```

```sql
CREATE SOURCE enrichment_data (
 asset_id              INT,
 sector                VARCHAR,
 historical_volatility DOUBLE,
 sector_performance    DOUBLE,
 sentiment_score       DOUBLE,
 timestamp             TIMESTAMPTZ
) WITH (
 connector                   = 'kafka',
 topic                       = 'enrichment_data',
 properties.bootstrap.server = 'kafka:9092',
 scan.startup.mode           = 'earliest'
) FORMAT PLAIN ENCODE JSON;
```

## Step 4: Run the Data Generator

Navigate to the market_data_enrichment directory and run the data generator.
```terminal
python3 data_generator.py
```
This will start inserting mock data into the tables created above.

## Step 5: Create Materialized Views

Run the following queries to create materialized views to analyze the data.

```sql
CREATE MATERIALIZED VIEW avg_price_bid_ask_spread AS
SELECT
  asset_id,
  timestamp,
  ROUND(
    AVG(price) OVER (
      PARTITION BY asset_id
      ORDER BY timestamp
      RANGE BETWEEN INTERVAL '3 seconds' PRECEDING AND CURRENT ROW
    )::NUMERIC, 2
  ) AS average_price,
  ROUND(
    AVG(ask_price - bid_price) OVER (
      PARTITION BY asset_id
      ORDER BY timestamp
      RANGE BETWEEN INTERVAL '3 seconds' PRECEDING AND CURRENT ROW
    )::NUMERIC, 2
  ) AS bid_ask_spread
FROM raw_market_data;
```

```sql
CREATE MATERIALIZED VIEW rolling_volatility AS
SELECT
  asset_id,
  timestamp,
  ROUND(
    stddev_samp(price) OVER (
      PARTITION BY asset_id
      ORDER BY timestamp
      RANGE BETWEEN INTERVAL '3 seconds' PRECEDING AND CURRENT ROW
    )::NUMERIC, 2
  ) AS rolling_volatility
FROM raw_market_data;
```

```sql
CREATE MATERIALIZED VIEW enriched_market_data AS
SELECT
  r.asset_id,
  ap.average_price,
  (r.price - ap.average_price) / ap.average_price * 100 AS price_change,
  ap.bid_ask_spread,
  rv.rolling_volatility,
  e.sector_performance,
  e.sentiment_score,
  r.timestamp
FROM raw_market_data AS r
JOIN avg_price_bid_ask_spread AS ap
  ON r.asset_id = ap.asset_id
 AND r.timestamp BETWEEN ap.timestamp - INTERVAL '3 seconds'
                     AND ap.timestamp + INTERVAL '3 seconds'
JOIN rolling_volatility AS rv
  ON r.asset_id = rv.asset_id
 AND r.timestamp BETWEEN rv.timestamp - INTERVAL '3 seconds'
                     AND rv.timestamp + INTERVAL '3 seconds'
JOIN enrichment_data AS e
  ON r.asset_id = e.asset_id
 AND r.timestamp BETWEEN e.timestamp - INTERVAL '3 seconds'
                     AND e.timestamp + INTERVAL '3 seconds';
```

## Step 6: Visualization using Superset (optional)

Using the preloaded window that opened at the beginning of the demo, enter the username and password below:
```terminal
username = admin
password = admin
```

Next, follow Data -> Databases -> +Databases and use the SQLAlchemy URI:
```terminal
risingwave://root@risingwave:4566/dev
```
Click test connection to ensure that the database can connect to Superset, and then click connect. 

Now Superset is ready for chart creation. 

## Step 7: Example Chart Creation 

From the home page, head to Data -> Create Dataset.

Select
```terminal
Database: RisingWave #or whatever chosen name for the database created in last step.
Schema: public
Table: enriched_market_data
```
Then, Click Add. 

Go to: Charts -> +Chart and select "Line Chart"
In Chart Editor: 
```terminal
Time Column = Timestamp
Time Grain = Seconds
Metrics (simple):
Column = average_price
Aggregate = AVG
```
Click "Update Chart" and the chart will generate. 

## Gitpod Alternative:
Using the link below, the demo is automated with scripts in a cloud development environment and example charts are ready for viewing.
[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/risingwavelabs/awesome-stream-processing/tree/main/02-simple-demos/capital_markets/market_data_enrichment)
