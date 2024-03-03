# Ingest data from Kafka into RisingWave

Now that you have the necessary systems installed for stream processing, let us use RisingWave to consume and analyze data from Kafka. If you need help setting these systems up, refer to [Install Kafka, PostgreSQL and RisingWave](00-install-kafka-pg-rw.md).

## Use Kafka to produce messages

First, ensure you have downloaded and started the Kafka environment. For more information, check the [installation guide for Kafka](00-install-kafka-pg-rw.md#install-kafka).

Then, you will need to create a topic to store your streaming events. The following line of code creates a topic named `test`.

```terminal
bin/kafka-topics.sh --create --topic test --bootstrap-server localhost:9092
```

Next, start the producer program in another terminal so that we can send messages to the topic. If you named your topic something different, be sure to adjust it accordingly. 

```terminal
bin/kafka-console-producer.sh --topic test --bootstrap-server localhost:9092
```

Once the `>` symbol appears, we can enter the message. To facilitate data consumption in RisingWave, we input data in JSON format.

```terminal
{"timestamp": "2023-06-13T10:05:00Z", "user_id": "user1", "page_id": "page1", "action": "click"}
{"timestamp": "2023-06-13T10:06:00Z", "user_id": "user2", "page_id": "page2", "action": "scroll"}
{"timestamp": "2023-06-13T10:07:00Z", "user_id": "user3", "page_id": "page1", "action": "view"}
{"timestamp": "2023-06-13T10:08:00Z", "user_id": "user4", "page_id": "page2", "action": "view"}
{"timestamp": "2023-06-13T10:09:00Z", "user_id": "user5", "page_id": "page3", "action": "view"}
```

You may also start a consumer program in another terminal to view the messages for verification.

```terminal
bin/kafka-console-consumer.sh --topic test --from-beginning --bootstrap-server localhost:9092
```

## Use RisingWave to process the data

Ensure that you have RisingWave up and running. For more information, check the [installation guide for RisingWave](00-install-kafka-pg-rw.md#install-risingwave).

### Create a source

To connect to the data stream we just created in Kafka, we need to create a source using the `CREATE SOURCE` or `CREATE TABLE` command. Once the connection is established, RisingWave will be able to read any new messages from Kafka in real time. 

The following SQL query creates a source named `website_visits_stream`. We also define a schema here to map fields from the JSON data to the streaming data. 

```sql
CREATE source IF NOT EXISTS website_visits_stream (
 timestamp timestamptz,
 user_id VARCHAR,
 page_id VARCHAR,
 action VARCHAR
 )
WITH (
 connector='kafka',
 topic='test',
 properties.bootstrap.server='localhost:9092',
 scan.startup.mode='earliest'
) FORMAT PLAIN ENCODE JSON;
```

To learn more about the `CREATE SOURCE` command, check [`CREATE SOURCE`](https://docs.risingwave.com/docs/current/sql-create-source/) from the offical RisingWave documentation.

### Analyze the data

By creating a source, RisingWave has been connected to the data stream. However, in order to ingest and process the data from Kafka, we need to create some materialized views. Each of these materialized views contains the results of a query, which are updated as soon as new data comes in.

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

To learn more about how to consume data from Kafka, check [Ingest data from Kafka](https://docs.risingwave.com/docs/current/ingest-from-kafka/) from the official documentation.
