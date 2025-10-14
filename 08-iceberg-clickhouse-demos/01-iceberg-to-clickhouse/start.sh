#!/bin/bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
COMPOSE_FILE=${COMPOSE_FILE:-"${SCRIPT_DIR}/docker-compose.yml"}

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check if other demos are running by looking for common service containers
echo "Checking for running demo containers..."

# Common services used across demos
COMMON_SERVICES=("compactor-0" "compute-node-0" "frontend-node-0" "meta-node-0" "risingwave-standalone" "clickhouse-server" "minio-0" "lakekeeper" "message_queue")

RUNNING_CONTAINERS=()
for service in "${COMMON_SERVICES[@]}"; do
    if docker ps --filter "name=${service}" --filter "status=running" --format "{{.Names}}" | grep -q "${service}"; then
        RUNNING_CONTAINERS+=("$service")
    fi
done

if [ ${#RUNNING_CONTAINERS[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: Found running containers from other demos:${NC}"
    for container in "${RUNNING_CONTAINERS[@]}"; do
        echo -e "${YELLOW}   - ${container}${NC}"
    done
    echo
    echo -e "${RED}This may cause port conflicts or resource issues.${NC}"
    echo -e "${YELLOW}Please go to the other demo folders and run ${GREEN}./stop.sh${YELLOW} first:${NC}"
    echo
    echo -e "Demo folders:"
    echo -e "  ${GREEN}../01-iceberg-to-clickhouse/${NC}"
    echo -e "  ${GREEN}../02-iceberg-and-kafka-to-clckhouse/${NC}"
    echo -e "  ${GREEN}../03-kafka-to-iceberg-clickhouse-query/${NC}"
    echo -e "  ${GREEN}../04-incremental-pg-kafka-enrichment-to-iceberg-clickhous-query/${NC}"
    echo
    echo "Aborting startup. Please stop other demos first."
    exit 1
fi

echo "Starting demo containers..."
docker compose -f "$COMPOSE_FILE" up -d