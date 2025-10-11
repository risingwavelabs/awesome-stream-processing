# Initialize the environemt
```bash
# Setup RisingWave, Iceberg with Lakekeepr Catalog, Kafka, Clickhouse via docker compose
./start.sh
```

# Prepare sample data for the demo
```bash
./prepare.sh
```

# Connect to RW / CK to run the demo SQLs in sql/
```bash
# Connect to RW using psql client. Run DDL SQL in sql/create_rw.sql to build the pipeline
./client.sh create

# Watch the sql/watch_ck.sql and sql/watch_rw.sql result via CK client and psql client
./client.sh watch-ck
./client.sh watch-rw

# You can conncect to the console for rw and clickhouse to run interactive SQL queries using the following scripts
./client.sh rw
./client.sh ck
```

# Cleanup the environment
```bash
./stop.sh
```