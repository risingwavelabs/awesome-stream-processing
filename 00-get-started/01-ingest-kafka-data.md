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

### Connect to RisingWave

Run the following code to connect to RisingWave.

```terminal
psql -h localhost -p 4566 -d dev -U root
```

### Create a source

To connect to the data stream we just created in Kafka, we need to create a source using the `CREATE SOURCE` command. Once the connection is established, RisingWave will be able to read any new messages from Kafka in real time. 

The following SQL query creates a source named `website_visits_stream`. We also define a schema here to map fields from the JSON data to the streaming data. 

```sql
CREATE SOURCE IF NOT EXISTS website_visits_stream (
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

Optionally, for verification, you can create a materialized view to grab all existing data from the source, using the following SQL.
```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS verify_website_visits AS
  SELECT * FROM website_visits_stream;
```

By running `SELECT * FROM verify_website_visits;`, you should see the outputs as follows.
```terminal
         timestamp         | user_id | page_id | action
---------------------------+---------+---------+--------
 2023-06-13 10:05:00+00:00 | user1   | page1   | click
 2023-06-13 10:06:00+00:00 | user2   | page2   | scroll
 2023-06-13 10:07:00+00:00 | user3   | page1   | view
 2023-06-13 10:08:00+00:00 | user4   | page2   | view
 2023-06-13 10:09:00+00:00 | user5   | page3   | view
(5 rows)
```

To learn more about the `CREATE SOURCE` command, check [`CREATE SOURCE`](https://docs.risingwave.com/docs/current/sql-create-source/) from the offical RisingWave documentation.

To further perform some basic analysis on the data from the created source, check [Section 00-01](../01-query-process-streaming-data/001-ingest-analyze-kafka.md#analyze-the-data).

### Create a table

You can also create a table to connect to the Kafka topic. Compared to creating a source, a table persists the data from the stream by default. In this way, you can still query the table data even after the Kafka environment has been shut down.

The following SQL query creates a table named `website_visits_table`, using the `CREATE TABLE` command.
```sql
CREATE TABLE IF NOT EXISTS website_visits_table (
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

For verification, run `SELECT * FROM website_visits_table;` and you should see the same outputs in the [`Create a source` part](#create-a-source).

To learn more about the `CREATE TABLE` command, check [`CREATE TABLE`](https://docs.risingwave.com/docs/current/sql-create-table/) from the offical RisingWave documentation.

To learn more about how to consume data from Kafka, check [Ingest data from Kafka](https://docs.risingwave.com/docs/current/ingest-from-kafka/) from the official documentation.
