# Marketing campaign performance analysis

Analyze and optimize marketing campaign performance in real-time.

Follow the instructions below to learn how to run this demo. 

For more details about the process and the use case, see the official documentation.

## Step 1: Install and run a RisingWave instance

See the [installation guide](/00-get-started/00-install-kafka-pg-rw.md#install-risingwave) for more details.

## Step 2: Create tables in RisingWave

Run the following three queries to set up your tables in RisingWave.

```sql
CREATE TABLE marketing_events (
    event_id varchar PRIMARY KEY,
    user_id integer,
    campaign_id varchar,
    channel_type varchar,  
    event_type varchar,    
    amount numeric,        
    utm_source varchar,
    utm_medium varchar,
    utm_campaign varchar,
    timestamp timestamptz DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE campaigns (
    campaign_id varchar PRIMARY KEY,
    campaign_name varchar,
    campaign_type varchar,  
    start_date timestamptz,
    end_date timestamptz,
    budget numeric,
    target_audience varchar
);

CREATE TABLE ab_test_variants (
    variant_id varchar PRIMARY KEY,
    campaign_id varchar,
    variant_name varchar, 
    variant_type varchar,  
    content_details varchar
);
```

## Step 3: Run the data generator

Ensure that you have a Python environment set up and have installed the psycopg2 library. Run the [data generator](02-simple-demos/e_commerce/marketing_analysis/data_generator.py).

This will start inserting mock data into the tables created above.

## Step 4: Create materialized views

Run the following queries to create materialized views to analyze the data.

```sql
CREATE MATERIALIZED VIEW campaign_performance AS
SELECT
    window_start,
    window_end,
    c.campaign_id,
    c.campaign_name,
    c.campaign_type,
    COUNT(DISTINCT CASE WHEN event_type = 'impression' THEN me.event_id END) as impressions,
    COUNT(DISTINCT CASE WHEN event_type = 'click' THEN me.event_id END) as clicks,
    COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN me.event_id END) as conversions,
    SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) as revenue,
    COUNT(DISTINCT CASE WHEN event_type = 'click' THEN me.event_id END)::float /
        NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'impression' THEN me.event_id END), 0) as ctr,
    COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN me.event_id END)::float /
        NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'click' THEN me.event_id END), 0) as conversion_rate
FROM TUMBLE(marketing_events me, timestamp, INTERVAL '1 HOUR')
JOIN campaigns c ON me.campaign_id = c.campaign_id
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
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END) as conversions,
    SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) as revenue,
    SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) /
        NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN event_id END), 0) as avg_order_value
FROM TUMBLE(marketing_events, timestamp, INTERVAL '1 HOUR')
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
    COUNT(DISTINCT CASE WHEN event_type = 'impression' THEN me.event_id END) as impressions,
    COUNT(DISTINCT CASE WHEN event_type = 'click' THEN me.event_id END) as clicks,
    COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN me.event_id END) as conversions,
    SUM(CASE WHEN event_type = 'conversion' THEN amount ELSE 0 END) as revenue,
    COUNT(DISTINCT CASE WHEN event_type = 'conversion' THEN me.event_id END)::float /
        NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'click' THEN me.event_id END), 0) as conversion_rate
FROM TUMBLE(marketing_events me, timestamp, INTERVAL '1 HOUR')
JOIN campaigns c ON me.campaign_id = c.campaign_id
JOIN ab_test_variants av ON c.campaign_id = av.campaign_id
WHERE c.campaign_type = 'ab_test'
GROUP BY
    window_start,
    window_end,
    c.campaign_id,
    c.campaign_name,
    av.variant_name,
    av.variant_type;
```