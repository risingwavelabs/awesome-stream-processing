# Continuously ingest and analyze Kafka data

This demo shows how to use RisingWave to continuously ingest data from Kafka and perform streaming analytics.

## Prerequisites

To execute this demo, the following systems must be installed:

* A RisingWave instance
* A Kafka instance

## Steps

### Produce messages to a Kafka topic

Refer to [Section 00-01](../00-get-started/01-ingest-kafka-data.md#use-kafka-to-produce-messages) to create a Kafka topic and add messages to it using a Kafka producer.

### Create a source in RisingWave

Refer to [Section 00-01](../00-get-started/01-ingest-kafka-data.md#create-a-source) to create a source in RisingWave.

### Analyze the data

By creating a source, RisingWave has been connected to the data stream. However, in order to ingest and process the data from Kafka, we need to create some [materialized views](https://docs.risingwave.com/docs/dev/key-concepts/#materialized-views). Each of these materialized views contains the results of a query, which are updated as soon as new data comes in.

The following SQL query creates a materialized view named `visits_stream_mv` based on the source `website_visits_stream`. For each `page_id`, it calculates the number of total visits, the number of unique visitors, and the timestamp when the page was most recently visited.

```sql
CREATE MATERIALIZED VIEW visits_stream_mv AS
 SELECT page_id,
 COUNT(*) AS total_visits,
 COUNT(DISTINCT user_id) AS unique_visitors,
 MAX(timestamp) AS last_visit_time
 FROM website_visits_stream
 GROUP BY page_id;
```

We can query from the materialized view to see the results.

```sql
SELECT * FROM visits_stream_mv;
```

The results will look like the following. Note that the rows do not necessarily follow this order.

```terminal
 page_id | total_visits | unique_visitors |      last_visit_time
---------+--------------+-----------------+---------------------------
 page1   |            2 |               2 | 2023-06-13 10:07:00+00:00
 page2   |            2 |               2 | 2023-06-13 10:08:00+00:00
 page3   |            1 |               1 | 2023-06-13 10:09:00+00:00
```
