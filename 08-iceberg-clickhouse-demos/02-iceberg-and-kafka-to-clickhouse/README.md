# 02: One-time Iceberg Backfill and Continuous Kafka Streaming to ClickHouse via RisingWave
Iceberg (one-time) + Kafka (streaming) → ClickHouse Table

- Prepare a iceberg table with historical data and a kafka topic with incremental data (1 row/s)
- Use RisingWave to do one-time ingestion from the iceberg table
- Use RisingWave to do streaming ingestion from the kafka topic
- Use RisingWave to combine historical and increnmental data into one table and deliver to ClickHouse
- Use ClickHouse to query the results

## Initialize the environemt
- Make sure you have there are more than **4 cores, 10GB** memory avavilable in your docker environment.
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