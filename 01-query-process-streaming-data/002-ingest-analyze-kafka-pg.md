# Continuously ingest and analyze data from Kafka and PostgreSQL

This demo shows how to use RisingWave to continuously ingest data from Kafka and PostgreSQL.

## Prerequisites

To execute this demo, the following systems must be installed:

* A RisingWave instance
* A Kafka instance
* A PostgreSQL table

## Steps

### Produce messages to a Kafka topic

Refer to [Section 00-01](../00-get-started/01-ingest-kafka-data.md#use-kafka-to-produce-messages) to create a Kafka topic and add messages to it using a Kafka producer.

### Create a source in RisingWave for the Kafka topic

Refer to [Section 00-01](../00-get-started/01-ingest-kafka-data.md#create-a-source) to create a source in RisingWave for the Kafka topic.

### Insert data into a PostgreSQL table

Refer to [Section 00-02](../00-get-started/02-ingest-pg-cdc.md#create-a-table-in-postgresql) to insert some data into a PostgreSQL table.

### Create a table in RisingWave for the PostgreSQL table

Refer to [Section 00-02](../00-get-started/02-ingest-pg-cdc.md#use-risingwave-to-process-the-data) to create a table in RisingWave for the PostgreSQL table.

### Combine two data sources into a materialized view

The following SQL creates a materialized view `website_visits_from_users` which joins the data from the Kafka topic and the PostgreSQL table by the user ID.

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS website_visits_from_users AS
 SELECT timestamp, 
  user_id,
  name AS user_name,
  age AS user_age,
  page_id,
  action
 FROM website_visits_stream INNER JOIN pg_users 
 ON website_visits_stream.user_id = pg_users.id;
```

Now, query the materialized view to see the results.

```sql
SELECT * FROM website_visits_from_users;
```

The results will look like the following. Note that the rows do not necessarily follow this order.

```terminal
         timestamp         | user_id |  user_name  | user_age | page_id | action
---------------------------+---------+-------------+----------+---------+--------
 2023-06-13 10:06:00+00:00 |       2 | Jane Smith  |       30 |       2 | scroll
 2023-06-13 10:05:00+00:00 |       1 | John Doe    |       25 |       1 | click
 2023-06-13 10:07:00+00:00 |       3 | Bob Johnson |       22 |       1 | view
(3 rows)
```

### Analyze the data

The following SQL creates another materialized view `most_visited_pages` which lists the top 3 most visited pages from users with ages lower than 35 and calculates the number of unique visitors for these pages.

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS most_visited_pages AS
 SELECT page_id,
  COUNT(DISTINCT user_id) AS total_visits
 FROM website_visits_from_users
 WHERE user_age < 35
 GROUP BY page_id
 LIMIT 3;
```

Now, query the materialized view to see the results.

```sql
SELECT * FROM most_visited_pages;
```

The results will look like the following. Note that the rows do not necessarily follow this order.

```terminal
 page_id | total_visits
---------+--------------
       1 |            2
       2 |            1
(2 rows)
```

### Optional: Clean up resources
To clean up the resources created in this section, go through the steps described in [Section 00-01](../00-get-started/01-ingest-kafka-data.md#optional-clean-up-resources) as well as [Section 00-02](../00-get-started/02-ingest-pg-cdc.md#optional-clean-up-resources). Note that these extra materialized views can also be deleted automatically upon deleting the source with the keyword `CASCADE`.
