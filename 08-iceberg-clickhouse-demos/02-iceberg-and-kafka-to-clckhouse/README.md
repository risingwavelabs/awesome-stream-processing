# Initialize the environemt
```bash
# Setup RisingWave, Iceberg with Rest Catalog, Kafka, Clickhouse via docker compose
./start.sh
```

# Prepare sample data for the demo
```bash
./prepare.sh
```

# Connect to RW / Clickhouse to run the demo SQLs in sql/
```bash
# Connect to RW using psql client. Run DDL SQL in sql/ddl_rw.sql to build the pipeline
./client.sh ddl-rw

# Watch the sql/ch.sql result via Clickhouse client
./client.sh watch-ch
```

# Cleanup the environment
```bash
./stop.sh
```