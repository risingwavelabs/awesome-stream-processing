# RisingWave → Lakekeeper → Iceberg → ClickHouse

Build an open, streaming lakehouse using RisingWave, LakeKeeper, and MinIO. Stream data from RisingWave’s native tables to Apache Iceberg without creating a sink, and query those same tables in ClickHouse.

## Prerequisites

* [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/): Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
* [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/): This allows you to connect to RisingWave for stream management and queries.

## Clone the demo repo and start the stack

Clone the repo, enter the demo, and start the stack:

```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git

cd awesome-stream-processing/07-iceberg-demos/risingwave_lakekeeper_iceberg_clickhouse

docker compose up -d
```
The Compose file starts Lakekeeper at 127.0.0.1:8181, RisingWave at 127.0.0.1:4566, and MinIO (S3-compatible) at 127.0.0.1:9301.

## 1. Provision a Lakekeeper warehouse (MinIO backend)

After deploying Lakekeeper, perform an initial bootstrap using the Management API. Call the `POST /management/v1/bootstrap` endpoint, for example:

```bash
# only needed once after deploying Lakekeeper
curl -X POST http://127.0.0.1:8181/management/v1/bootstrap \
  -H 'Content-Type: application/json' \
  -d '{"accept-terms-of-use": true}'
```

Now, run this to create a warehouse:

```bash
curl -X POST http://127.0.0.1:8181/management/v1/warehouse \
  -H 'Content-Type: application/json' \
  -d '{
    "warehouse-name": "risingwave-warehouse",
    "delete-profile": { "type": "hard" },
    "storage-credential": {
      "type": "s3",
      "credential-type": "access-key",
      "aws-access-key-id": "hummockadmin",
      "aws-secret-access-key": "hummockadmin"
    },
    "storage-profile": {
      "type": "s3",
      "bucket": "hummock001",
      "region": "us-east-1",
      "flavor": "s3-compat",
      "endpoint": "http://minio-0:9301",
      "path-style-access": true,
      "sts-enabled": false,
      "key-prefix": "risingwave-lakekeeper"
    }
  }'
```

## 2. Connect RisingWave and stream to Iceberg

Connect to RisingWave:

```bash
psql -h localhost -p 4566 -d dev -U root
```

Create an Iceberg **REST catalog** connection that points at the Lakekeeper catalog and MinIO:

```sql
CREATE CONNECTION lakekeeper_catalog_conn
WITH (
    type = 'iceberg',
    catalog.type = 'rest',
    catalog.uri = 'http://lakekeeper:8181/catalog/',
    warehouse.path = 'risingwave-warehouse',
    s3.access.key = 'hummockadmin',
    s3.secret.key = 'hummockadmin',
    s3.path.style.access = 'true',
    s3.endpoint = 'http://minio-0:9301',
    s3.region = 'us-east-1'
);
```
```sql
SET iceberg_engine_connection = 'public.lakekeeper_catalog_conn';
```

Create a table for capital markets trades:

```sql
-- Capital markets trades table
CREATE TABLE market_trades (
  trade_id    INT PRIMARY KEY,        -- unique execution/trade id
  symbol      VARCHAR,                -- ticker symbol (e.g., AAPL)
  side        VARCHAR,                -- BUY or SELL
  price       DECIMAL,                -- executed price
  quantity    INT,                    -- executed shares
  currency    VARCHAR,                -- e.g., USD
  venue       VARCHAR,                -- e.g., NASDAQ, NYSE, ARCA
)
WITH (commit_checkpoint_interval = 1)
ENGINE = iceberg;
```

Insert sample rows into the capital-markets trades table:

```sql
INSERT INTO market_trades (
  trade_id, symbol, side, price, quantity, currency, venue) VALUES
  (1010000001, 'AAPL', 'BUY',  232.1400,  500, 'USD', 'NASDAQ'),
  (1010000002, 'MSFT', 'SELL', 415.7500,  300, 'USD', 'NASDAQ'),
  (1010000003, 'TSLA', 'BUY',  289.3300, 1000, 'USD', 'NASDAQ');
```

Query the table to view the results:

```sql
SELECT * FROM market_trades;
```

## 3. Query the Iceberg table from ClickHouse

Install ClickHouse:

```bash
curl https://clickhouse.com/ | sh
```
Map `minio-0` to `127.0.0.1` on the host so DuckDB (outside Compose) can reach MinIO at `http://minio-0:9301`:

```bash
echo "127.0.0.1 minio-0" | sudo tee -a /etc/hosts
```

Launch ClickHouse client:

```bash
./clickhouse
```

Enable the Iceberg catalog database and create a connection to Lakekeeper (REST) backed by MinIO:

```sql
SET allow_experimental_database_iceberg = 1;

CREATE DATABASE lakekeeper_catalog
ENGINE = DataLakeCatalog('http://127.0.0.1:8181/catalog/', 'hummockadmin', 'hummockadmin')
SETTINGS catalog_type = 'rest', storage_endpoint = 'http://127.0.0.1:9301/', warehouse = 'risingwave-warehouse';

USE lakekeeper_catalog;

-- Query your Iceberg table 
SELECT * FROM `public.market_trades`;
```

Notes: ClickHouse’s DataLakeCatalog connects to REST catalogs, such as Lakekeeper, and exposes the catalog as a database. You must enable `allow_experimental_database_iceberg` first. Backticks are required for namespaced Iceberg tables (e.g., `public.market_trades`).

## Optional: Clean up (Docker)

> ⚠️ Run only after testing.
>
> * `-v` also deletes volumes (all data).

**Full cleanup (containers, networks, volumes):**

```bash
docker compose down -v
```

## Recap

* **Provision** a Lakekeeper warehouse that stores data in MinIO.
* **Stream** data from RisingWave's native tables into Iceberg via the Lakekeeper REST catalog.
* **Query** the same tables in **ClickHouse** through the catalog, no copies, same data.
