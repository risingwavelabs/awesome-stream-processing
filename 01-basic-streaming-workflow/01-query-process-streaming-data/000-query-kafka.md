# Directly query Kafka data

This demo shows how to use RisingWave to directly execute ad-hoc queries on Kafka.

## Prerequisites

To execute this demo, the following systems must be installed:

* A RisingWave instance
* A Kafka instance

## Steps

### Produce messages to a Kafka topic

Refer to [here](../../00-get-started/01-ingest-kafka-data.md#use-kafka-to-produce-messages) to create a Kafka topic and add messages to it using a Kafka producer.

### Create a source in RisingWave

Refer to [here](../../00-get-started/01-ingest-kafka-data.md#create-a-source) to create a source in RisingWave.

### Analyze the data

The following SQL query directly scans data from the kafka topic and calculates, for each `page_id`, the number of total visits, the number of unique visitors, and the timestamp when the page was most recently visited.

```sql
SELECT page_id,
 COUNT(*) AS total_visits,
 COUNT(DISTINCT user_id) AS unique_visitors,
 MAX(timestamp) AS last_visit_time
FROM website_visits_stream
GROUP BY page_id;
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

In the real-world scenario, one Kafka topic may contain a massive amount of history data, most of which is not needed by the query. To avoid the overhead of scanning these data, the built-in `_rw_kafka_timestamp` column is commonly utilized to filter the data by their insertion timestamps. More information can be found in the [official documentation](https://docs.risingwave.com/docs/current/ingest-from-kafka/#query-kafka-timestamp). 

Please note that `_rw_kafka_timestamp` denotes the time at which the event was inserted into Kafka. Even though you may have inserted an event like `{"timestamp": "2023-06-13T10:05:00Z", "user_id": 1, "page_id": 1, "action": "click"}`, `_rw_kafka_timestamp` will hold a different timestamp value, e.g.

```sql 
SELECT _rw_kafka_timestamp FROM website_visits_stream LIMIT 1;
# result
      _rw_kafka_timestamp
-------------------------------
 2024-04-05 09:48:02.827+00:00
(1 row)
```

### Optional: Clean up resources
To clean up the resources created in this section, go through the steps described in [here](../../00-get-started/01-ingest-kafka-data.md#optional-clean-up-resources).
