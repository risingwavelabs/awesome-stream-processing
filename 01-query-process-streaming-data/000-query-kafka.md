# Directly query Kafka data

This demo shows how to use RisingWave to directly execute ad-hoc queries on Kafka.

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

The following SQL query calculates, for each `page_id`, the number of total visits, the number of unique visitors, and the timestamp when the page was most recently visited.

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

### Optional: Clean up resources
To clean up the resources created in this section, go through the steps described in [Section 00-01](../00-get-started/01-ingest-kafka-data.md#optional-clean-up-resources).
