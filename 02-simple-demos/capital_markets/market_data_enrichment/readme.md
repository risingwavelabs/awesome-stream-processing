# Market data enhancement and transformation

Transform raw market data in real-time to provide insights into market trends, health, and trade opportunities.

Follow the instructions below to learn how to run this demo. 

For more details about the process and the use case, see the [official documentation](https://docs.risingwave.com/demos/market-data-enrichment). (Note: Automated Gitpod Setup at end of page)

## Step 1: Install and run a RisingWave nstance and Kafka instance

See the [installation guide](/00-get-started/00-install-kafka-pg-rw.md#install-risingwave) for more details.

## Step 2: Create topics in Kafka

Run the following commands in kafka to create two kafka topics.

```terminal
# On Ubuntu
bin/kafka-topics.sh --create --topic raw_market_data --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1

bin/kafka-topics.sh --create --topic enrichment_data --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1

# On Mac 
/opt/homebrew/opt/kafka/bin/kafka-topics --create --topic raw_market_data --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1

/opt/homebrew/opt/kafka/bin/kafka-topics --create --topic enrichment_data --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1
```

Next, start the producer program in another terminal so that we can send messages to the topic. If you named your topic something different, be sure to adjust it accordingly.

```terminal
# Note: Run each command in a seperate terminal window. 

# On Ubuntu
bin/kafka-console-producer.sh --topic raw_market_data --bootstrap-server localhost:9092

bin/kafka-console-producer.sh --topic enrichment_data --bootstrap-server localhost:9092

# On Mac
/opt/homebrew/opt/kafka/bin/kafka-console-producer --topic raw_market_data --bootstrap-server localhost:9092

/opt/homebrew/opt/kafka/bin/kafka-console-producer --topic enrichment_data --bootstrap-server localhost:9092
```



## Step 2: Create sources in RisingWave

Run the following two queries to set up your tables in RisingWave.

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
  properties.bootstrap.server = 'localhost:9092',
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
  properties.bootstrap.server = 'localhost:9092',
  scan.startup.mode           = 'earliest'
) FORMAT PLAIN ENCODE JSON;
```

## Step 3: Run the data generator

Ensure that you have a Python environment set up and have installed the psycopg2 library. Run the data generator.
```terminal
# Note: Replace line 8 with
bootstrap_servers='localhost:9092',
```

This will start inserting mock data into the tables created above.

## Step 4: Create materialized views

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

## Step 5: Visualization using Superset (optional)

See the [Official Superset Quickstart guide](https://superset.apache.org/docs/quickstart/) for Superset installation and start up.

## Step 6: Using Superset

Launch superset at [http://localhost:8088](http://localhost:8088).

If prompted,
```terminal
username = admin
password = admin
```

Next, follow Data -> Databases -> +Databases and use the SQLAlchemy URI:
```terminal
risingwave://root@host.docker.internal:4566/dev
```
Click test connection to ensure that the database can connect to Superset, and then click connect. 

Now Superset is ready for chart creation. 

## Step 7: Example Chart Creation 

From the home page, head to Data -> Create Dataset.

Select
```terminal
Database: RisingWave #or whatever chosen name for the database created in last step.
Schema: public
Table: avg_price_bid_ask_spread_table
```
Then, Click Add. 

Go to: Charts -> +Chart and select "Line Chart"
In Chart Editor: 
```terminal
x axis = Timestamp: Seconds
Metric: AVG(average_price) under simple
```
Click "Update Chart" and the chart will generate. 

## Gitpod Alternative:
Using the link below, the demo is automated with scripts in a cloud development environment and example charts are ready for viewing.
[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/tinytimcodes/awesome-stream-processing/tree/main/02-simple-demos/capital_markets/market_data_enrichment)
