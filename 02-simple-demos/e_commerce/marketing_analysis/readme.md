# Marketing campaign performance analysis

Analyze and optimize marketing campaign performance in real-time.

Follow the instructions below to learn how to run this demo. 

For more details about the process and the use case, see the official documentation.

## Step 1: Launch Gitpod

Click the link below to open the Gitpod development environment and wait for environment set up.

[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/risingwavelabs/awesome-stream-processing)

## Step 2: Create topics in Kafka

Run the following commands in the terminal to create the kafka topics.

```terminal
docker exec kafka \
            kafka-topics.sh \
              --bootstrap-server kafka:9092 \
              --create \
              --topic marketing_events \
              --partitions 1 \
              --replication-factor 1

          docker exec kafka \
            kafka-topics.sh \
              --bootstrap-server kafka:9092 \
              --create \
              --topic campaigns \
              --partitions 1 \
              --replication-factor 1
          
          docker exec kafka \
            kafka-topics.sh \
              --bootstrap-server kafka:9092 \
              --create \
              --topic ab_test_variants \
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
CREATE SOURCE marketing_events (
  event_id       VARCHAR,
  user_id        INT,
  campaign_id    VARCHAR,
  channel_type   VARCHAR,
  event_type     VARCHAR,
  amount         NUMERIC,
  utm_source     VARCHAR,
  utm_medium     VARCHAR,
  utm_campaign   VARCHAR,
  variant_id     VARCHAR,
  timestamp      TIMESTAMPTZ
) WITH (
  connector                   = 'kafka',
  topic                       = 'marketing_events',
  properties.bootstrap.server = 'kafka:9092',
  scan.startup.mode           = 'earliest'
) FORMAT PLAIN ENCODE JSON;
```

```sql
CREATE SOURCE campaigns (
    campaign_id varchar,
    campaign_name varchar,
    campaign_type varchar,  
    start_date timestamptz,
    end_date timestamptz,
    budget numeric,
    target_audience varchar
) WITH (
  connector                   = 'kafka',
  topic                       = 'campaigns',
  properties.bootstrap.server = 'kafka:9092',
  scan.startup.mode           = 'earliest'
) FORMAT PLAIN ENCODE JSON;
```

```sql
CREATE SOURCE ab_test_variants (
    variant_id varchar,
    campaign_id varchar,
    variant_name varchar, 
    variant_type varchar,  
    content_details varchar
) WITH (
  connector = 'kafka',
  topic = 'ab_test_variants',
  properties.bootstrap.server = 'kafka:9092',
  scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;
```


## Step 4: Run the data generator

Navigate to the market_data_enrichment directory and Run the [data generator](02-simple-demos/e_commerce/marketing_analysis/data_generator.py).

This will start inserting mock data into the tables created above.



## Step 5: Create materialized views

Run the following queries to create materialized views to analyze the data.

```sql
CREATE MATERIALIZED VIEW campaign_performance AS
SELECT
  window_start,
  window_end,
  c.campaign_id,
  c.campaign_name,
  c.campaign_type,
  COUNT(DISTINCT CASE WHEN event_type = 'impression' THEN event_id END) AS impressions,
  COUNT(DISTINCT CASE WHEN event_type = 'click' THEN event_id END) AS clicks,
  COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END) AS conversions,
  SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) AS revenue,
  COUNT(DISTINCT CASE WHEN event_type = 'click' THEN event_id END)::FLOAT /
    NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'impression' THEN event_id END), 0) AS ctr,
  COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END)::FLOAT /
    NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'click' THEN event_id END), 0) AS conversion_rate
FROM TUMBLE(marketing_events, timestamp, INTERVAL '5 MINUTES')
JOIN campaigns c ON marketing_events.campaign_id = c.campaign_id
GROUP BY
  window_start,
  window_end,
  c.campaign_id,
  c.campaign_name,
  c.campaign_type;
```

```sql
CREATE MATERIALIZED VIEW channel_attribution AS
SELECT
  window_start,
  window_end,
  channel_type,
  utm_source,
  utm_medium,
  COUNT(DISTINCT user_id) AS unique_users,
  COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END) AS conversions,
  SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) AS revenue,
  SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) /
    NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END), 0) AS avg_order_value
FROM TUMBLE(marketing_events, timestamp, INTERVAL '5 MINUTES')
GROUP BY
  window_start,
  window_end,
  channel_type,
  utm_source,
  utm_medium;
```

```sql
CREATE MATERIALIZED VIEW ab_test_results AS
SELECT
  window_start,
  window_end,
  c.campaign_id,
  c.campaign_name,
  av.variant_name,
  av.variant_type,
  COUNT(DISTINCT CASE WHEN event_type = 'impression' THEN event_id END) AS impressions,
  COUNT(DISTINCT CASE WHEN event_type = 'click' THEN event_id END) AS clicks,
  COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END) AS conversions,
  SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) AS revenue,
  COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END)::FLOAT /
    NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'click' THEN event_id END), 0) AS conversion_rate
FROM TUMBLE(marketing_events, timestamp, INTERVAL '5 MINUTES')
JOIN campaigns c ON marketing_events.campaign_id = c.campaign_id
JOIN ab_test_variants av ON marketing_events.variant_id = av.variant_id
WHERE c.campaign_type = 'ab_test' 
  AND marketing_events.variant_id IS NOT NULL
GROUP BY
  window_start,
  window_end,
  c.campaign_id,
  c.campaign_name,
  av.variant_name,
  av.variant_type;
```

## Step 6: Visualization using Superset

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
Table: market_data
```
Then, Click Add. 

Go to: Charts -> +Chart and select "Line Chart"
In Chart Editor: 
```terminal
Time Column = Timestamp
Time Grain = Minutes
Metrics (simple):
Column = event_id
Aggregate = COUNT
Group by = event_type
```
Click "Update Chart" and the chart will generate. 

## Gitpod Alternative:
Using the link below, the demo is automated with scripts in a cloud development environment and example charts are ready for viewing.
[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/new/#https://github.com/risingwavelabs/awesome-stream-processing/tree/main/02-simple-demos/e_commerce/marketing_analysis)
