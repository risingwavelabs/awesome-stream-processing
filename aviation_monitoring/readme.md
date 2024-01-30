# Flight tracking demo

README will be adjusted once demo is finalized.

Under the Zookeeper and Metabase containers, based on your device, adjust the specified platforms as needed.

After pulling this directory onto your local device, navigate to this file and run `docker compose up -d` to start all the services. Install docker if you have not already done so. 

Kafka is exposed on `kafka:9092` for applications running internally and `localhost:29092` for applications running on your local device. `test` topic is created automatically. 

When connecting RisingWave to Metabase, use `risingwave` as the host address. Note that it takes a minute or so for Metabase to be up and running. Check the logs to keep track of its progress.

The following SQL query can be used to connect to the Kafka broker. Adjust schema as needed.

```sql
CREATE SOURCE IF NOT EXISTS s1 (
   key varchar,
   value varchar,
)
WITH (
   connector='kafka',
   topic='test',
   properties.bootstrap.server='kafka:9092'
) FORMAT PLAIN ENCODE JSON;
```