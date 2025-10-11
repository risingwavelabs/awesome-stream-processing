# Prequsites
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


# DEMO

## 01: One-time Iceberg Backfill and Continuous Kafka Streaming to ClickHouse via RisingWave
Follow [01-ice-and-kafka-to-ck/README.md](01-ice-and-kafka-to-ck/README.md)

## 02: Continuous Kafka Streaming to Iceberg via RisingWave. Use Clickhouse to query Iceberg Table.
Follow [02-kafka-to-ice-ck-read/README.md](02-kafka-to-ice-ck-read/README.md)

## 03: Real-time Kafka and Postgres enrichment to Iceberg via RisingWave. Use Clickhouse to query Iceberg Table.
Follow [03-incremetal-enrichment-ice-ck-read/README.md](03-incremetal-enrichment-ice-ck-read/README.md)