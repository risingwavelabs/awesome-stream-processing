# Ingest data from Kafka into RisingWave

Now that you have the necessary systems installed for stream processing, let us use RisingWave to consume and analyze data from Kafka. If you need help setting these systems up, refer to [Install Kafka, PostgreSQL and RisingWave](00-install-kafka-pg-rw.md).

## Use Kafka to produce messages

First, ensure you have downloaded and started the Kafka environment. For more information, check the [installation guide for Kafka](00-install-kafka-pg-rw.md#install-kafka).

On Mac you can start the Kafka environment via 

```terminal 
brew services start zookeeper 
brew services start kafka
# ensure that both services are running
brew services list
# ensure that kafka is reachable at 9092
lsof -i :9092
```

Then, you will need to create a topic to store your streaming events. The following line of code creates a topic named `test`.

```terminal
# On Ubuntu
bin/kafka-topics.sh --create --topic test --bootstrap-server localhost:9092

# On Mac 
/opt/homebrew/opt/kafka/bin/kafka-topics --create --topic test --bootstrap-server localhost:9092
```

Next, start the producer program in another terminal so that we can send messages to the topic. If you named your topic something different, be sure to adjust it accordingly. 

```terminal
# On Ubuntu
bin/kafka-console-producer.sh --topic test --bootstrap-server localhost:9092

# On Mac
/opt/homebrew/opt/kafka/bin/kafka-console-producer --topic test --bootstrap-server localhost:9092
```

Once the `>` symbol appears, we can enter the message. To facilitate data consumption in RisingWave, we input data in JSON format.

```terminal
{"timestamp": "2023-06-13T10:05:00Z", "user_id": 1, "page_id": 1, "action": "click"}
{"timestamp": "2023-06-13T10:06:00Z", "user_id": 2, "page_id": 2, "action": "scroll"}
{"timestamp": "2023-06-13T10:07:00Z", "user_id": 3, "page_id": 1, "action": "view"}
{"timestamp": "2023-06-13T10:08:00Z", "user_id": 4, "page_id": 2, "action": "view"}
{"timestamp": "2023-06-13T10:09:00Z", "user_id": 5, "page_id": 3, "action": "view"}
```

You may also start a consumer program in another terminal to view the messages for verification.

```terminal
# On Ubuntu
bin/kafka-console-consumer.sh --topic test --from-beginning --bootstrap-server localhost:9092

# On Mac
/opt/homebrew/opt/kafka/bin/kafka-console-consumer --topic test --from-beginning --bootstrap-server localhost:9092
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
 user_id integer,
 page_id integer,
 action varchar
 )
WITH (
 connector='kafka',
 topic='test',
 properties.bootstrap.server='localhost:9092',
 scan.startup.mode='earliest'
) FORMAT PLAIN ENCODE JSON;
```

By creating a source, RisingWave has been connected to the Kafka. However, to ingest the data from Kafka, we need to create some materialized views. Using the following SQL, you can create a materialized view to grab all existing data from the source and continuously capture newly inserted events from the kafka. 
```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS verify_website_visits AS
  SELECT * FROM website_visits_stream;
```

By running `SELECT * FROM verify_website_visits;`, you should see the outputs as follows.
```terminal
         timestamp         | user_id | page_id | action
---------------------------+---------+---------+--------
 2023-06-13 10:05:00+00:00 |       1 |       1 | click
 2023-06-13 10:06:00+00:00 |       2 |       2 | scroll
 2023-06-13 10:07:00+00:00 |       3 |       1 | view
 2023-06-13 10:08:00+00:00 |       4 |       2 | view
 2023-06-13 10:09:00+00:00 |       5 |       3 | view
(5 rows)
```

Additionally, we can go to the Kafka producer terminal and add one more data to the Kafka topic:
```terminal
{"timestamp": "2023-06-13T10:10:00Z", "user_id": 6, "page_id": 4, "action": "click"}
```

Then, in the RisingWave terminal, run `SELECT * FROM verify_website_visits;` again. You can check from the following outputs that the materialized view we created has been updated to include this new row.
```terminal
         timestamp         | user_id | page_id | action
---------------------------+---------+---------+--------
 2023-06-13 10:05:00+00:00 |       1 |       1 | click
 2023-06-13 10:06:00+00:00 |       2 |       2 | scroll
 2023-06-13 10:07:00+00:00 |       3 |       1 | view
 2023-06-13 10:08:00+00:00 |       4 |       2 | view
 2023-06-13 10:09:00+00:00 |       5 |       3 | view
 2023-06-13 10:10:00+00:00 |       6 |       4 | click
(6 rows)
```

To learn more about the `CREATE SOURCE` command, check [`CREATE SOURCE`](https://docs.risingwave.com/docs/current/sql-create-source/) from the offical RisingWave documentation.

To further perform some basic analysis on the data from the created source, check [Section 00-01](../01-query-process-streaming-data/001-ingest-analyze-kafka.md#analyze-the-data).

### Create a table

You can also create a table to connect to the Kafka topic. Compared to creating a source, a table persists the data from the stream by default. In this way, you can still query the table data even after the Kafka environment has been shut down.

The following SQL query creates a table named `website_visits_table`, using the `CREATE TABLE` command.
```sql
CREATE TABLE IF NOT EXISTS website_visits_table (
 timestamp timestamptz,
 user_id integer,
 page_id integer,
 action varchar
 )
WITH (
 connector='kafka',
 topic='test',
 properties.bootstrap.server='localhost:9092',
 scan.startup.mode='earliest'
) FORMAT PLAIN ENCODE JSON;
```

For verification, run `SELECT * FROM website_visits_table;` and you should see the same outputs with selecting from the materialized view created above.

To learn more about the `CREATE TABLE` command, check [`CREATE TABLE`](https://docs.risingwave.com/docs/current/sql-create-table/) from the offical RisingWave documentation.

To learn more about how to consume data from Kafka, check [Ingest data from Kafka](https://docs.risingwave.com/docs/current/ingest-from-kafka/) from the official documentation.

## Optional: Clean up resources
To clean up the resources created in this section, go through the steps described in this part.

First, delete the created source as well as the materialized views in RisingWave. It can be accomplished in one single SQL by deleting the source with the `CASCADE` keyword. Delete the created table as well, if any.

```sql
DROP SOURCE IF EXISTS website_visits_stream CASCADE;
DROP TABLE IF EXISTS website_visits_table;
```

Next, stop the Kafka producer and delete the Kafka topic.

```terminal
# Ubuntu
bin/kafka-topics.sh --delete --topic test --bootstrap-server localhost:9092

# Mac 
/opt/homebrew/opt/kafka/bin/kafka-topics --delete --topic test --bootstrap-server localhost:9092
```
