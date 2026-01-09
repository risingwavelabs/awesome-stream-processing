# Ingest Open Telemetry Data to RisingWave


## Quick Start

### 1. Start RisingWave and Open Telemetry Collector

```shell
docker compose up -d
```

### 2. Setup RisingWave Webhook Tables

Connect to RisingWave

```shell
psql "postgres://root:@localhost:4666/dev"
```

Run the following SQL

```sql

CREATE TABLE otel_traces (data JSONB) WITH (
  connector = 'webhook',
  is_batched = true
) VALIDATE AS secure_compare('1', '1');

CREATE TABLE otel_metrics (data JSONB) WITH (
  connector = 'webhook',
  is_batched = true
) VALIDATE AS secure_compare('1', '1');

CREATE TABLE otel_logs (data JSONB) WITH (
  connector = 'webhook',
  is_batched = true
) VALIDATE AS secure_compare('1', '1');

CREATE TABLE otel_profiles (data JSONB) WITH (
  connector = 'webhook',
  is_batched = true
) VALIDATE AS secure_compare('1', '1');
```

### 3. Query the Metrics

```sql
SELECT * FROM otel_metrics;
```
