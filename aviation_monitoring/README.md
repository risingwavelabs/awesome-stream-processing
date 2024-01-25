# Flight tracking demo

README will be adjusted once demo is finalized and running properly.

Under the Zookeeper and Metabase containers, based on your device, adjust the specified platforms as needed.

When connecting Metabase to RisingWave, use `risingwave` as the host address. Note that it takes a minute or so for Metabase to be up and running. Check the logs to keep track of its progress.

Kafka is exposed on `kafka:9092` for applications running internally and `localhost:29092` for applications running on your local device. 

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