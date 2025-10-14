# 01: Continuous Iceberg Ingestion and Delivery to ClickHouse with RisingWave
```
Iceberg (streaming) → ClickHouse Table

- Use Spark to create and mutate `sales_history` iceberg table
- Use RisingWave to do streaming ingestion from `sales_history` iceberg table and deliver CDC to ClickHouse
- Use ClickHouse to query the results
```

## Initialize the environemt
```bash
## Setup RisingWave, Iceberg with Rest Catalog, Clickhouse via docker compose
./start.sh
```

## Prepare sample data for the demo
```bash
./prepare.sh
```

## Connect to RW / Clickhouse / SPARK to run the demo SQLs in sql/
```bash
## Run the following two commands in two terminals at the same time.

# Terminal 1: Use spark sql to run DML in sql/spark_dml.sql interactively
./client.sh dml-spark

# Terminal 2: Watch the sql/ch.sql result via Clickhouse client
./client.sh watch-ch
```

## Cleanup the environment
```bash
./stop.sh
```