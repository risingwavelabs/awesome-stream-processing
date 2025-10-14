#!/usr/bin/env bash

# ============================================================================
# Interactive Spark SQL Demo Script
# ============================================================================
# This script runs DML operations on Iceberg tables step-by-step
# Press ENTER after each step to continue
#
# It reads SQL steps from an external file (default: sql/dml_spark.sql).
# Steps are delimited by comment lines starting with "-- Step".
# Example delimiter:  -- Step 4: Insert initial data
# ============================================================================

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
DC_CMD=${DC_CMD:-docker compose}
COMPOSE_FILE=${COMPOSE_FILE:-"${SCRIPT_DIR}/docker-compose.yml"}
# SQL file containing the demo steps. You can also pass it as the first argument.
DML_FILE=${DML_FILE:-"${SCRIPT_DIR}/sql/dml_spark.sql"}
if [[ $# -ge 1 ]]; then
	DML_FILE="$1"
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
	echo "Error: docker-compose.yml not found at $COMPOSE_FILE" >&2
	exit 1
fi

if [[ ! -f "$DML_FILE" ]]; then
	echo "Error: SQL file not found at $DML_FILE" >&2
	exit 1
fi

# Colors for better visibility
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pause_for_user() {
	echo ""
	echo -e "${YELLOW}Press ENTER to continue to the next step...${NC}"
	read -r
}

run_sql() {
	local step="$1"
	local sql="$2"

	# Trim leading/trailing whitespace from SQL chunk
	sql="$(echo -e "$sql" | sed -e '/^[[:space:]]*$/d')"
	if [[ -z "$sql" ]]; then
		return 0
    fi

	echo -e "${GREEN}=== $step ===${NC}"
	echo -e "${BLUE}SQL:${NC}"
	echo "$sql"
	echo ""

	# Write SQL to a temporary file and execute via spark-sql
	local temp_sql_file="/tmp/step_$(date +%s)_$$.sql"
	
	# Create temp file with the SQL content
	echo -e "$sql" | $DC_CMD -f "$COMPOSE_FILE" exec -T spark-iceberg bash -c "cat > $temp_sql_file"
	
	# Execute the SQL file (filter out WARN messages for cleaner output)
	$DC_CMD -f "$COMPOSE_FILE" exec -T spark-iceberg spark-sql \
		--conf spark.sql.cli.print.header=true \
		-f "$temp_sql_file" 2>&1 | grep -v WARN
	
	# Clean up temp file
	$DC_CMD -f "$COMPOSE_FILE" exec -T spark-iceberg rm -f "$temp_sql_file"

	pause_for_user
}

# Parse the DML file into steps.
# We consider any line that starts with "-- Step" as a new step delimiter.
parse_and_run_steps() {
	local current_title="Intro"
	local current_sql=""
	local saw_first_step=false

	# Use file descriptor 3 to avoid interfering with stdin for user input
	exec 3< "$DML_FILE"
	while IFS= read -r line <&3 || [[ -n "$line" ]]; do
		if [[ "$line" =~ ^--[[:space:]]*Step[[:space:]] ]]; then
			# When encountering a new step header
			if [[ "$saw_first_step" == true ]]; then
				run_sql "$current_title" "$current_sql"
				current_sql=""
			fi
			current_title="$(echo "$line" | sed -E 's/^--[[:space:]]*//')"
			saw_first_step=true
		else
			# Accumulate SQL lines after the first step header only
			if [[ "$saw_first_step" == true ]]; then
				current_sql+="$line\n"
			fi
		fi
	done
	exec 3<&-  # Close file descriptor 3

	# Run the last accumulated chunk
	if [[ "$saw_first_step" == true ]]; then
		run_sql "$current_title" "$current_sql"
	else
		echo "Warning: No steps found in $DML_FILE (expected lines starting with '-- Step')." >&2
	fi
}

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════╗
║   Mutate the Iceberg Table Using Copy-on-Write mode                   ║
║   Make sure you have run ./prepare.sh to set up the environment       ║
╚═══════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
pause_for_user

# Inform which SQL file is being used for the demo
echo -e "${BLUE}Using SQL steps from:${NC} $DML_FILE"
echo -e "Override with: DML_FILE=/path/to/file.sql ./demo_spark.sh or ./demo_spark.sh /path/to/file.sql"
pause_for_user

# Run all steps by parsing the external SQL file
parse_and_run_steps

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════╗
║                         Demo Complete! ✓                              ║
║  DML operations executed successfully                                 ║
║  using Copy-on-Write mode with Iceberg                                ║
║                                                                       ║
║  Remember to run ./stop.sh before continuing onto the next demo       ║
╚═══════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
