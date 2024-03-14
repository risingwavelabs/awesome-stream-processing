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

### Analyze the data with materialized views

By creating a source, RisingWave has been connected to the data stream. However, in order to ingest, process, and persist the data from Kafka, we need to create some [materialized views](https://docs.risingwave.com/docs/dev/key-concepts/#materialized-views). Each of these materialized views contains the results of a query, which are updated as soon as new data comes in.

The following SQL query creates a materialized view named `visits_stream_mv` based on the source `website_visits_stream`. The inner SQL query is the same as the one demonstrated in [Section 01-000](000-query-kafka.md#analyze-the-data). For each `page_id`, it calculates the number of total visits, the number of unique visitors, and the timestamp when the page was most recently visited. 

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS visits_stream_mv AS
 SELECT page_id,
  COUNT(*) AS total_visits,
  COUNT(DISTINCT user_id) AS unique_visitors,
  MAX(timestamp) AS last_visit_time
 FROM website_visits_stream
 GROUP BY page_id;
```

Now, query the materialized view to see the results.

```sql
SELECT * FROM visits_stream_mv;
```

The results will look like the following. Note that the rows do not necessarily follow this order.

```terminal
 page_id | total_visits | unique_visitors |      last_visit_time
---------+--------------+-----------------+---------------------------
       1 |            2 |               2 | 2023-06-13 10:07:00+00:00
       2 |            2 |               2 | 2023-06-13 10:08:00+00:00
       3 |            1 |               1 | 2023-06-13 10:09:00+00:00
(3 rows)
```

Compared to directly querying the data source, the created materialized view possesses the following benefits:

1. it persists the processed data even after the Kafka topic is removed;
2. it is far more efficient to query the materialized view rather than executing the inner SQL query, owing to the fact that the results in the materialized view are updated once new data is written to the Kafka topic.

Additionally, if you add one more data to the Kafka topic as described in [Section 00-01](../00-get-started/01-ingest-kafka-data.md#create-a-source), using the Kafka producer, you can also verify the updated version of this materialized view. The new data is as follow.
```terminal
{"timestamp": "2023-06-13T10:10:00Z", "user_id": 6, "page_id": 4, "action": "click"}
```

Now run `SELECT * FROM visits_stream_mv;` again, and you will see the following outputs.
```terminal
 page_id | total_visits | unique_visitors |      last_visit_time
---------+--------------+-----------------+---------------------------
       1 |            2 |               2 | 2023-06-13 10:07:00+00:00
       2 |            2 |               2 | 2023-06-13 10:08:00+00:00
       3 |            1 |               1 | 2023-06-13 10:09:00+00:00
       4 |            1 |               1 | 2023-06-13 10:10:00+00:00
(4 rows)
```

> In the real-world scenario, one Kafka topic may contain a massive amount of history data, most of which is no longer needed. To avoid the overhead of querying these data, the built-in `_rw_kafka_timestamp` column is commonly utilized to filter the data by their insertion timestamps. More information can be found in the [official documentation](https://docs.risingwave.com/docs/current/ingest-from-kafka/#query-kafka-timestamp).

### Optional: Clean up resources
To clean up the resources created in this section, go through the steps described in [Section 00-01](../00-get-started/01-ingest-kafka-data.md#optional-clean-up-resources). Note that these extra materialized views can also be deleted automatically upon deleting the source with the keyword `CASCADE`.
