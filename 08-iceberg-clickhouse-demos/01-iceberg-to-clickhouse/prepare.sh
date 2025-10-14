#!/usr/bin/env bash

# Run Spark, RisingWave, and ClickHouse preparation SQLs
# - Executes prepare_spark.sql (create Iceberg table + seed data via Spark SQL)
# - Executes prepare_rw.sql (create Iceberg table + seed data) via psql
# - Executes prepare_kafka.sql (create datagen + Kafka sink) via psql
# - Executes prepare_clickhouse.sql (create ClickHouse analytics table) via clickhouse client
#
# Configurable via env vars with sensible defaults for this demo stack:
#   RW_HOST (default: localhost)
#   RW_PORT (default: 4566)
#   RW_DB   (default: dev)
#   RW_USER (default: root)
#   RW_PSQL (default: psql)
#   CH_HOST (default: localhost)
#   CH_PORT (default: 8123)
#   CH_USER (default: default)
#   CH_PASS (default: default)
#   DC_CMD (default: "docker compose")
#   COMPOSE_FILE (default: parent folder's docker-compose.yml)
#
# Usage:
#   chmod +x prepare.sh
#   ./prepare.sh

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Docker Compose configuration (used for Spark and ClickHouse steps)
DC_CMD=${DC_CMD:-docker compose}
COMPOSE_FILE=${COMPOSE_FILE:-"${SCRIPT_DIR}/docker-compose.yml"}
if [[ ! -f "$COMPOSE_FILE" ]]; then
	echo "Error: docker-compose.yml not found at $COMPOSE_FILE" >&2
	exit 1
fi

RW_HOST=${RW_HOST:-localhost}
RW_PORT=${RW_PORT:-4566}
RW_DB=${RW_DB:-dev}
RW_USER=${RW_USER:-root}
RW_PSQL=${RW_PSQL:-psql}

SQL_SPARK="${SCRIPT_DIR}/prepare/prepare_spark.sql"
SQL_RW="${SCRIPT_DIR}/prepare/prepare_rw.sql"
SQL_CK="${SCRIPT_DIR}/prepare/prepare_clickhouse.sql"


if [[ ! -f "$SQL_SPARK" ]]; then
  echo "Error: Missing file $SQL_SPARK" >&2
  exit 1
fi

if [[ ! -f "$SQL_RW" ]]; then
	echo "Error: Missing file $SQL_RW" >&2
	exit 1
fi

if [[ ! -f "$SQL_CK" ]]; then
	echo "Error: Missing file $SQL_CK" >&2
	exit 1
fi

echo "Connecting to RisingWave: host=$RW_HOST port=$RW_PORT db=$RW_DB user=$RW_USER"

PSQL_CONN=("$RW_PSQL" -h "$RW_HOST" -p "$RW_PORT" -d "$RW_DB" -U "$RW_USER" \
	--set=ON_ERROR_STOP=1 --no-align --tuples-only)

run_sql() {
	local file="$1"
	echo "\n=== Running: $(basename "$file") ==="
	"${PSQL_CONN[@]}" -f "$file"
	echo "=== Done: $(basename "$file") ==="
}

# 0) Prepare Iceberg table via Spark (Lakekeeper REST catalog)
echo "Running prepare_spark.sql inside spark-iceberg container via: $DC_CMD -f $COMPOSE_FILE exec -T spark-iceberg spark-sql"

# Copy SQL into container and execute
set +e
$DC_CMD -f "$COMPOSE_FILE" cp "$SQL_SPARK" spark-iceberg:/tmp/prepare_spark.sql
$DC_CMD -f "$COMPOSE_FILE" exec -T spark-iceberg \
	spark-sql -f /tmp/prepare_spark.sql
SPARK_STATUS=$?
set -e

if [[ $SPARK_STATUS -ne 0 ]]; then
	echo "Error: Spark prepare script failed with status $SPARK_STATUS" >&2
	exit $SPARK_STATUS
fi

echo "=== Done: $(basename "$SQL_SPARK") ==="


# 1) Prepare ClickHouse sales table inside the container using docker compose exec
CH_USER=${CH_USER:-default}
CH_PASS=${CH_PASS:-default}

if [[ ! -f "$COMPOSE_FILE" ]]; then
	echo "Error: docker-compose.yml not found at $COMPOSE_FILE" >&2
	exit 1
fi

echo "Running prepare_clickhouse.sql inside clickhouse-server container via: $DC_CMD -f $COMPOSE_FILE exec -T clickhouse-server clickhouse client"

# Use -T to disable TTY so stdin redirection works reliably
set +e
$DC_CMD -f "$COMPOSE_FILE" exec -T clickhouse-server \
	clickhouse client --user="$CH_USER" --password="$CH_PASS" --multiquery < "$SQL_CK"
CH_STATUS=$?
set -e

if [[ $CH_STATUS -ne 0 ]]; then
	echo "Error: ClickHouse prepare script failed with status $CH_STATUS" >&2
	exit $CH_STATUS
fi
echo "=== Done: $(basename "$SQL_CK") ==="

# 2) Prepare iceberg cdc and clickhouse sink via RisingWave
run_sql "$SQL_RW"




echo "All preparation steps completed successfully."
