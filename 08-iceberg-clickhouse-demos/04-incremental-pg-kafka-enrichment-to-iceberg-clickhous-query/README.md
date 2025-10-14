# 04: Real-time Kafka and Postgres enrichment to Iceberg via RisingWave. Use Clickhouse to query Iceberg Table.
```
Postgres CDC (streaming) join Kafka (streaming) → Enriched Iceberg Table. ClickHouse Query Iceberg.

- Prepare a postgres table `product` with continous updates (1 row/s) and a kafka topic `sales_stream` with streaming data (1 row/s)
- Use RisingWave to do streaming cdc ingestion from the postgres table
- Use RisingWave to do streaming ingestion from the kafka topic
- Use RisingWave to join the kafka `sales_stream` and the postgres `product` table for enrichment. Updates from both side will trigger incremental computation.
- Use RisingWave to do continously write the enriched results to a Iceberg Table.
- Use ClickHouse to query the Iceberg Table.

* `./client.sh watch-ch` will show "table not exists" error 
  until the Iceberg Table is created in `./client.sh ddl-rw` Step 6.
```

## Initialize the environemt
```bash
# Setup RisingWave, Iceberg with Rest Catalog, Kafka, Clickhouse via docker compose
./start.sh
```

## Prepare sample data for the demo
```bash
./prepare.sh
```

## Connect to RW / Clickhouse to run the demo SQLs in sql/
```bash
# Connect to RW using psql client. Run DDL SQL in sql/ddl_rw.sql to build the pipeline
./client.sh ddl-rw

# Watch the sql/watch_ch.sql and sql/watch_rw.sql result via Clickhouse client and psql client
./client.sh watch-ch
./client.sh watch-rw
```

## Cleanup the environment
```bash
./stop.sh
```