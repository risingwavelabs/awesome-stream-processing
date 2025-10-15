#!/usr/bin/env bash

# Run RisingWave and ClickHouse preparation SQLs
# - Executes prepare_ice.sql (create Iceberg table + seed data) via psql
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

RW_HOST=${RW_HOST:-localhost}
RW_PORT=${RW_PORT:-4566}
RW_DB=${RW_DB:-dev}
RW_USER=${RW_USER:-root}
RW_PSQL=${RW_PSQL:-psql}

SQL_KAFKA="${SCRIPT_DIR}/prepare/prepare_kafka.sql"
SQL_CK="${SCRIPT_DIR}/prepare/prepare_clickhouse.sql"


if [[ ! -f "$SQL_KAFKA" ]]; then
	echo "Error: Missing file $SQL_KAFKA" >&2
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

# 1) Prepare Kafka datagen and sink
run_sql "$SQL_KAFKA"

# 2) Prepare ClickHouse analytics table inside the container using docker compose exec
CH_USER=${CH_USER:-default}
CH_PASS=${CH_PASS:-default}
DC_CMD=${DC_CMD:-docker compose}
COMPOSE_FILE=${COMPOSE_FILE:-"${SCRIPT_DIR}/docker-compose.yml"}

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


echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════╗
║               All Preparation Steps Completed! ✓                      ║
║                                                                       ║
║  • Kafka: prepare sales-stream topic with 1 row/s sample data         ║
║  • ClickHouse: created a DB connected to iceberg rest catalog         ║
║                                                                       ║
║  Next Steps:                                                          ║
║  1. Run ./client.sh ddl-rw to start the demo to 					    ║		
║     build "Kafka → Iceberg" job                    					║
║  2. After iceberg table is created in ddl-rw Step 4,                  ║
║     run ./client.sh watch-ch to watch the changes  					║
║     in the iceberg table.                     						║
╚═══════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
