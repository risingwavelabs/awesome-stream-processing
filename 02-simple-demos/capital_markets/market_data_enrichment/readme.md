# Market data enhancement and transformation

Transform raw market data in real-time to provide insights into market trends, health, and trade opportunities.

Follow the instructions below to learn how to run this demo. 

For more details about the process and the use case, see the [official documentation](https://docs.risingwave.com/demos/market-data-enrichment). (Note: Automated Gitpod Setup at end of page)

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

Ensure that you have a Python environment set up and have installed the psycopg2 library. Run the data generator.

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
    ap.average_price,
    (rmd.price - ap.average_price) / ap.average_price * 100 AS price_change,
    ap.bid_ask_spread,
    rv.rolling_volatility,
    ed.sector_performance,
    ed.sentiment_score,
    rmd.timestamp
FROM
    raw_market_data AS rmd
JOIN 
    avg_price_bid_ask_spread AS ap ON rmd.asset_id = ap.asset_id
    AND rmd.timestamp BETWEEN ap.timestamp - INTERVAL '2 seconds' AND ap.timestamp + INTERVAL '2 seconds'
JOIN 
    rolling_volatility AS rv ON rmd.asset_id = rv.asset_id
    AND rmd.timestamp BETWEEN rv.timestamp - INTERVAL '2 seconds' AND rv.timestamp + INTERVAL '2 seconds'
JOIN 
    enrichment_data AS ed ON rmd.asset_id = ed.asset_id
    AND rmd.timestamp BETWEEN ed.timestamp - INTERVAL '2 seconds' AND ed.timestamp + INTERVAL '2 seconds';
```
## Step 5: Visualization using Superset (optional)

See the [Official Superset Quickstart guide](https://superset.apache.org/docs/quickstart/) for Superset installation and start up.

## Step 6: Connect PostgreSQL to database

```terminal
# on Ubuntu
psql -h localhost -p 5432 -d postgres -U postgres

# on Mac the default user is the installing user
psql -h localhost -p 5432 -d postgres -U $(whoami)
```

## Step 7: Create PostgreSQL Tables
Run the following queries in PostgreSQL to create target tables for RisingWave to write to.

```sql
CREATE TABLE avg_price_sink (
  asset_id INT,
  average_price NUMERIC,
  bid_ask_spread NUMERIC,
  timestamp TIMESTAMPTZ
);
```

```sql
CREATE TABLE rolling_volatility_sink (
  asset_id INT,
  rolling_volatility NUMERIC,
  timestamp TIMESTAMPTZ
);
```

```sql
CREATE TABLE enriched_market_data_sink (
  asset_id INT,
  average_price NUMERIC,
  price_change NUMERIC,
  bid_ask_spread NUMERIC,
  rolling_volatility NUMERIC,
  sector_performance NUMERIC,
  sentiment_score NUMERIC,
  timestamp TIMESTAMPTZ
);
```

## Step 8: Create Sinks in RisingWave 
Navigate back to RisingWave terminal and run these queries to create the sinks. (Note: Some parameters need to be changed depending on Operating System.)

```sql
# on Ubuntu
user = 'postgres'

# on Mac - set to macOS Username
user = '$(whoami)'
```

```sql
# password = set password / remove line if no password set
```

```sql
CREATE SINK sink_avg_price
FROM avg_price_bid_ask_spread
WITH (
  connector = 'postgres',
  type = 'append-only',
  force_append_only = 'true',
  host = 'localhost',
  port = 5432,
  user = 'postgres', 
  password = 'pgpass',
  database = 'postgres',
  table = 'avg_price_sink'
);
```

```sql
CREATE SINK sink_rolling_volatility
FROM rolling_volatility
WITH (
  connector = 'postgres',
  type = 'append-only',
  force_append_only = 'true',
  host = 'localhost',
  port = 5432,
  user = 'postgres',
  password = 'pgpass',
  database = 'postgres',
  table = 'rolling_volatility_sink'
);
```

```sql
CREATE SINK sink_enriched
FROM enriched_market_data
WITH (
  connector = 'postgres',
  type = 'append-only',
  force_append_only = 'true',
  host = 'localhost',
  port = 5432,
  user = 'postgres',
  password = 'pgpass',
  database = 'postgres',
  table = 'enriched_market_data_sink'
);
```

## Step 9: Using Superset

launch superset at [http://localhost:8088](http://localhost:8088).

if prompted,
```terminal
username = admin
password = admin
```

Next, follow Data -> Databases -> +Databases and use the SQLAlchemy URI replacing pguser and pgpass with your corresponding inputs. 
If there is no password, remove ":pgpass". On Mac, replace pguser with MacOS username.
```terminal
postgresql://pguser:pgpass@host.docker.internal:5432/postgres
```
Click test connection to ensure that the database can connect to Superset, and then click conenct. 

Now Superset is ready for chart creation. 

## Step 10: Example Chart Creation 

From the home page, head to Data -> Create Dataset.

Select
```terminal
Database: postgres #or whatever chosen name for the database created in last step.
Schema: public
Table: avg_price_sink
```
Then, Click Add. 

go to: Charts -> +Chart and select "Line Chart"
in Chart Editor: 
```terminal
x axis = Timestamp: Seconds
Metric: AVG(average_price) under simple
```
Click "Update Chart" and the Chart will generate. 

## Gitpod Alternative:
Using the link below, the demo is automated with scripts in a cloud development environment and example charts are ready for viewing.
[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/tinytimcodes/awesome-stream-processing/tree/main/02-simple-demos/capital_markets/market_data_enrichment)


















