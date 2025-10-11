#!/usr/bin/env bash

# Quick client helper for this demo
# - rw: opens psql to RisingWave
# - ck: opens clickhouse client inside the clickhouse-server container
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
Usage: $(basename "$0") [rw|ck|pg|create|watch-rw|watch-ck]

Commands:
	rw         Open a psql session to RisingWave
	ck         Open a clickhouse client session inside the clickhouse-server container
	pg         Open a psql session to OLTP Postgres inside the oltp container
	create     Execute SQL file (sql/create_rw.sql) against RisingWave once
	watch-rw   Execute SQL file (sql/watch_rw.sql) against RisingWave every WATCH_INTERVAL seconds
	watch-ck   Execute SQL file (sql/watch_ck.sql) against ClickHouse every WATCH_INTERVAL seconds

Examples:
	$(basename "$0") rw
	$(basename "$0") create
	$(basename "$0") watch-rw
	$(basename "$0") watch-ck

Environment variables:
	RW_HOST, RW_PORT, RW_DB, RW_USER, RW_PSQL
	WATCH_INTERVAL (default: 2 seconds)
	WATCH_RW_SQL_FILE (default: ${SCRIPT_DIR}/sql/watch_rw.sql)
	WATCH_CK_SQL_FILE (default: ${SCRIPT_DIR}/sql/watch_ck.sql)
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

WATCH_INTERVAL=${WATCH_INTERVAL:-5}
WATCH_RW_SQL_FILE=${WATCH_RW_SQL_FILE:-"${SCRIPT_DIR}/sql/watch_rw.sql"}
WATCH_CK_SQL_FILE=${WATCH_CK_SQL_FILE:-"${SCRIPT_DIR}/sql/watch_ck.sql"}
CREATE_RW_SQL_FILE=${CREATE_RW_SQL_FILE:-"${SCRIPT_DIR}/sql/create_rw.sql"}

case "$cmd" in
	rw)
		echo "Connecting to RisingWave: host=$RW_HOST port=$RW_PORT db=$RW_DB user=$RW_USER"
		exec "$RW_PSQL" -h "$RW_HOST" -p "$RW_PORT" -d "$RW_DB" -U "$RW_USER"
		;;
	ck)
		if [[ ! -f "$COMPOSE_FILE" ]]; then
			echo "Error: compose file not found at $COMPOSE_FILE" >&2
			exit 1
		fi
		echo "Opening ClickHouse client inside container (service: clickhouse-server)"
		exec $DC_CMD -f "$COMPOSE_FILE" exec clickhouse-server clickhouse client
		;;
	pg)
		if [[ ! -f "$COMPOSE_FILE" ]]; then
			echo "Error: compose file not found at $COMPOSE_FILE" >&2
			exit 1
		fi
		echo "Opening OLTP Postgres client inside container (service: oltp)"
		exec $DC_CMD -f "$COMPOSE_FILE" exec oltp psql -U myuser -d mydb
		;;
	create)
		if [[ ! -f "$CREATE_RW_SQL_FILE" ]]; then
			echo "Error: RisingWave create SQL file not found: $CREATE_RW_SQL_FILE" >&2
			exit 1
		fi
		echo "Executing RisingWave create script: $CREATE_RW_SQL_FILE"
		"$RW_PSQL" -h "$RW_HOST" -p "$RW_PORT" -d "$RW_DB" -U "$RW_USER" \
			--set=ON_ERROR_STOP=1 -f "$CREATE_RW_SQL_FILE"
		echo "Create script completed."
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
	watch-ck)
		if [[ ! -f "$COMPOSE_FILE" ]]; then
			echo "Error: compose file not found at $COMPOSE_FILE" >&2
			exit 1
		fi
		if [[ ! -f "$WATCH_CK_SQL_FILE" ]]; then
			echo "Error: ClickHouse watch SQL file not found: $WATCH_CK_SQL_FILE" >&2
			exit 1
		fi
		echo "Watching ClickHouse SQL file every ${WATCH_INTERVAL}s: $WATCH_CK_SQL_FILE"
		echo "Press Ctrl+C to stop..."
		while true; do
			echo "=== $(date) ==="
			echo "File: $WATCH_CK_SQL_FILE"
			echo "=== Results ==="
			$DC_CMD -f "$COMPOSE_FILE" exec -T clickhouse-server clickhouse client --format Pretty --echo --multiquery < "$WATCH_CK_SQL_FILE"
			sleep "$WATCH_INTERVAL"
			clear
		done
		;;
	*)
		usage
		exit 1
		;;
esac

