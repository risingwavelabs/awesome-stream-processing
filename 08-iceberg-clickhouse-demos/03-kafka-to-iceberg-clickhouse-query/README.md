# 03: Continuous Kafka Streaming to Iceberg via RisingWave. Use Clickhouse to query Iceberg Table.
```
Kafka (Streaming) → Iceberg. ClickHouse Query Iceberg.

- Prepare a kafka topic with streaming data (1 row/s)
- Use RisingWave to do streaming ingestion from the kafka topic
- Use RisingWave to do streaming write to Iceberg Table
- Use ClickHouse to query Iceberg Table

* `./client.sh watch-ch` will show "table not exists" error 
  until the Iceberg Table is created in `./client.sh ddl-rw` Step 4.
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

# Watch the sql/ch.sql result via Clickhouse client
./client.sh watch-ch
```

## Cleanup the environment
```bash
./stop.sh
```