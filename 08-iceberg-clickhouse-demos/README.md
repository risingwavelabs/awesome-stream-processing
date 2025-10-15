# Prerequisites
- Install psql client
```bash
# MacOs
brew install postgresql

# Ubuntu
sudo apt install postgresql-client
```

- Install Docker Desktop
```bash
# MacOs
https://docs.docker.com/desktop/setup/install/mac-install/

# Ubuntu
https://docs.docker.com/desktop/setup/install/linux/
```

- There are more than 4 cores, 10GB memory avavilable in your docker environment.

# Demo

## 01: Continuous Iceberg Ingestion and Delivery to ClickHouse with RisingWave
Follow [01-iceberg-to-clickhouse/README.md](01-iceberg-to-clickhouse/README.md)

## 02: One-time Iceberg Backfill and Continuous Kafka Streaming to ClickHouse via RisingWave
Follow [02-iceberg-and-kafka-to-clickhouse/README.md](02-iceberg-and-kafka-to-clickhouse/README.md)

## 03: Continuous Kafka Streaming to Iceberg via RisingWave. Use Clickhouse to query Iceberg Table.
Follow [03-kafka-to-iceberg-clickhouse-query/README.md](03-kafka-to-iceberg-clickhouse-query/README.md)

## 04: Real-time Kafka and Postgres enrichment to Iceberg via RisingWave. Use Clickhouse to query Iceberg Table.
Follow [04-incremental-pg-kafka-enrichment-to-iceberg-clickhouse-query/README.md](04-incremental-pg-kafka-enrichment-to-iceberg-clickhouse-query/README.md)

## 05: Real-time Kafka and Postgres enrichment and Deliver to Clickhouse with RisingWave.
Follow [05-incremental-pg-kafka-enrichment-to-clickhouse/README.md](05-incremental-pg-kafka-enrichment-to-clickhouse/README.md)
