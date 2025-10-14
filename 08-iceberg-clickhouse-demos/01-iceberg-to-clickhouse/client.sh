#!/usr/bin/env bash

# Quick client helper for this demo
# - rw: opens psql to RisingWave
# - ch: opens clickhouse client inside the clickhouse-server container
# - spark: opens spark-sql CLI inside the spark-iceberg container
#
# Env overrides:
#   RW_HOST (default: localhost)
#   RW_PORT (default: 4566)
#   RW_DB   (default: dev)
#   RW_USER (default: root)
#   RW_PSQL (default: psql)
#   DC_CMD  (default: docker compose)
#   COMPOSE_FILE (default: parent folder docker-compose.yml)

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

usage() {
	cat <<EOF
Usage: $(basename "$0") [rw|ch|spark|ddl-rw|watch-rw|watch-ch]

Commands:
	rw         Open a psql session to RisingWave
	ch         Open a clickhouse client session inside the clickhouse-server container
	spark      Open a spark-sql session inside the spark-iceberg container
	ddl-rw     Execute SQL file (sql/ddl_rw.sql) against RisingWave once
	watch-rw   Execute SQL file (sql/watch_rw.sql) against RisingWave every WATCH_INTERVAL seconds
	watch-ch   Execute SQL file (sql/watch_ch.sql) against ClickHouse every WATCH_INTERVAL seconds

Examples:
	$(basename "$0") rw
	$(basename "$0") spark
	$(basename "$0") watch-rw
	$(basename "$0") watch-ch

Environment variables:
	RW_HOST, RW_PORT, RW_DB, RW_USER, RW_PSQL
	WATCH_INTERVAL (default: 2 seconds)
	WATCH_RW_SQL_FILE (default: ${SCRIPT_DIR}/sql/watch_rw.sql)
	WATCH_CH_SQL_FILE (default: ${SCRIPT_DIR}/sql/watch_ch.sql)
	DC_CMD, COMPOSE_FILE
EOF
}

cmd=${1:-}
if [[ -z "$cmd" ]]; then
	usage
	exit 1
fi

RW_HOST=${RW_HOST:-localhost}
RW_PORT=${RW_PORT:-4566}
RW_DB=${RW_DB:-dev}
RW_USER=${RW_USER:-root}
RW_PSQL=${RW_PSQL:-psql}

DC_CMD=${DC_CMD:-docker compose}
COMPOSE_FILE=${COMPOSE_FILE:-"${SCRIPT_DIR}/docker-compose.yml"}

WATCH_INTERVAL=${WATCH_INTERVAL:-2}
WATCH_RW_SQL_FILE=${WATCH_RW_SQL_FILE:-"${SCRIPT_DIR}/sql/watch_rw.sql"}
WATCH_CH_SQL_FILE=${WATCH_CH_SQL_FILE:-"${SCRIPT_DIR}/sql/watch_ch.sql"}
DML_SCRIPT=${DML_SCRIPT:-"${SCRIPT_DIR}/dml_spark.sh"}

case "$cmd" in
	rw)
		echo "Connecting to RisingWave: host=$RW_HOST port=$RW_PORT db=$RW_DB user=$RW_USER"
		exec "$RW_PSQL" -h "$RW_HOST" -p "$RW_PORT" -d "$RW_DB" -U "$RW_USER"
		;;
	ch)
		if [[ ! -f "$COMPOSE_FILE" ]]; then
			echo "Error: compose file not found at $COMPOSE_FILE" >&2
			exit 1
		fi
		echo "Opening ClickHouse client inside container (service: clickhouse-server)"
		exec $DC_CMD -f "$COMPOSE_FILE" exec clickhouse-server clickhouse client
		;;
	spark)
		if [[ ! -f "$COMPOSE_FILE" ]]; then
			echo "Error: compose file not found at $COMPOSE_FILE" >&2
			exit 1
		fi
		echo "Opening Spark SQL client inside container (service: spark-iceberg)"
		echo "Catalog 'lake' is pre-configured for Iceberg with Lakekeeper REST catalog"
		echo ""
		echo "Quick commands:"
		echo "  SHOW NAMESPACES IN lake;"
		echo "  USE lake.sales_db;"
		echo "  SHOW TABLES;"
		echo "  SELECT * FROM sales_history LIMIT 10;"
		echo ""
		exec $DC_CMD -f "$COMPOSE_FILE" exec spark-iceberg spark-sql
		;;
	dml-spark)
		if [[ ! -f "$DML_SCRIPT" ]]; then
			echo "Error: Spark DML script not found: $DML_SCRIPT" >&2
			exit 1
		fi
		echo "Executing Spark DML script: $DML_SCRIPT"
		bash "$DML_SCRIPT"
		echo "DML script completed."
		;;
	watch-rw)
		if [[ ! -f "$WATCH_RW_SQL_FILE" ]]; then
			echo "Error: RisingWave watch SQL file not found: $WATCH_RW_SQL_FILE" >&2
			exit 1
		fi
		echo "Watching RisingWave SQL file every ${WATCH_INTERVAL}s: $WATCH_RW_SQL_FILE"
		echo "Press Ctrl+C to stop..."
		while true; do
			echo "=== $(date) ==="
			echo "File: $WATCH_RW_SQL_FILE"
			echo "=== Results ==="
			"$RW_PSQL" -h "$RW_HOST" -p "$RW_PORT" -d "$RW_DB" -U "$RW_USER" \
				--set=ON_ERROR_STOP=1 -f "$WATCH_RW_SQL_FILE" 2>/dev/null || echo "Query failed"
			sleep "$WATCH_INTERVAL"
			clear
		done
		;;
	watch-ch)
		if [[ ! -f "$COMPOSE_FILE" ]]; then
			echo "Error: compose file not found at $COMPOSE_FILE" >&2
			exit 1
		fi
		if [[ ! -f "$WATCH_CH_SQL_FILE" ]]; then
			echo "Error: ClickHouse watch SQL file not found: $WATCH_CH_SQL_FILE" >&2
			exit 1
		fi
		echo "Watching ClickHouse SQL file every ${WATCH_INTERVAL}s: $WATCH_CH_SQL_FILE"
		echo "Press Ctrl+C to stop..."
		while true; do
			echo "=== $(date) ==="
			echo "File: $WATCH_CH_SQL_FILE"
			echo "=== Results ==="
			$DC_CMD -f "$COMPOSE_FILE" exec -T clickhouse-server clickhouse client --format Pretty --echo --multiquery < "$WATCH_CH_SQL_FILE"
			sleep "$WATCH_INTERVAL"
			clear
		done
		;;
	*)
		usage
		exit 1
		;;
esac

