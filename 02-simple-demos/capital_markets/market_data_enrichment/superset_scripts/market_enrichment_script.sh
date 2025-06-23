#!/bin/bash

set -e
set -o pipefail

# --- Configuration ---
SUPERSET_URL="${SUPERSET_URL:-http://localhost:8088}"
SUPERSET_USERNAME="${SUPERSET_USERNAME:-admin}"
SUPERSET_PASSWORD="${SUPERSET_PASSWORD:-admin}"

# --- Database Configuration (Should not need to change) ---
DB_NAME="Postgres_Market_Data"
SQLALCHEMY_URI="postgresql://pguser:pgpass@postgres:5432/pgdb"

# --- NEW: Data & Dashboard Configuration ---
# This is the main table we will use from your PostgreSQL SINKs
DATASET_TABLE_NAME="enriched_market_data_sink"
DATASET_NAME="Enriched Market Data"

# We will create two charts for our dashboard
CHART_1_NAME="Price Change and Volatility Over Time"
CHART_2_NAME="Sentiment and Sector Performance"

# The title for the final dashboard
DASHBOARD_TITLE="Enriched Market Analysis Dashboard"


# --- Pre-requisite Checks ---
if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
    echo "Error: 'curl' and 'jq' are required. Please install them to run this script." >&2
    exit 1
fi

# --- Helper Function for Idempotent Asset Creation ---
# All logging (echo) is redirected to stderr (>&2) to keep stdout clean for return values.
get_or_create_asset() {
    local asset_type="$1"
    local asset_name="$2"
    local filter_q="$3"
    local create_payload="$4"
    local existing_id=""

    echo "--- Managing ${asset_type^}: '$asset_name' ---" >&2

    local get_response
    get_response=$(curl -s -G "$SUPERSET_URL/api/v1/$asset_type/" -H "Authorization: Bearer $TOKEN" --data-urlencode "$filter_q")
    existing_id=$(echo "$get_response" | jq -r '.result[0].id // empty')

    if [[ -n "$existing_id" ]]; then
        echo "✅ ${asset_type^} '$asset_name' already exists with ID: $existing_id" >&2
        echo "$existing_id"
        return
    fi

    echo "➡️ ${asset_type^} '$asset_name' not found, creating it..." >&2
    local create_response
    create_response=$(curl -s -X POST "$SUPERSET_URL/api/v1/$asset_type/" -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" -H "Content-Type: application/json" -d "$create_payload")
    local new_id
    new_id=$(echo "$create_response" | jq -r '.id // empty')

    if [[ -z "$new_id" ]]; then
        echo "❌ Failed to create ${asset_type} '$asset_name'. Response: $create_response" >&2
        exit 1
    fi
    
    echo "✅ ${asset_type^} '$asset_name' created with ID: $new_id" >&2
    echo "$new_id"
}

# --- 1. Authentication ---
echo "⏳ Waiting for Superset API..." >&2
until curl -s "$SUPERSET_URL/api/v1/ping" &> /dev/null; do sleep 1 && printf "."; done
echo -e "\n✅ Superset is up." >&2

echo "🔐 Logging in to Superset..." >&2
LOGIN_RESPONSE=$(curl -s -X POST "$SUPERSET_URL/api/v1/security/login" -H 'Content-Type: application/json' -d "{\"username\": \"$SUPERSET_USERNAME\", \"password\": \"$SUPERSET_PASSWORD\", \"provider\": \"db\"}")
TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token // empty')
[[ -z "$TOKEN" ]] && echo "❌ Login failed. Response: $LOGIN_RESPONSE" >&2 && exit 1
echo "🔑 Login successful." >&2

CSRF_TOKEN=$(curl -s -H "Authorization: Bearer $TOKEN" "$SUPERSET_URL/api/v1/security/csrf_token/" | jq -r '.result // empty')
[[ -z "$CSRF_TOKEN" ]] && echo "❌ Failed to get CSRF token." >&2 && exit 1
echo "✅ Got CSRF token." >&2

# --- 2. Get or Create Database ---
DB_FILTER_Q="q=$(jq -n --arg name "$DB_NAME" '{filters:[{col:"database_name",opr:"eq",value:$name}]}')"
CREATE_DB_PAYLOAD=$(jq -n --arg name "$DB_NAME" --arg uri "$SQLALCHEMY_URI" '{database_name: $name, sqlalchemy_uri: $uri, expose_in_sqllab: true}')
DB_ID=$(get_or_create_asset "database" "$DB_NAME" "$DB_FILTER_Q" "$CREATE_DB_PAYLOAD")

# --- 3. Get or Create Dataset ---
DATASET_FILTER_Q="q=$(jq -n --arg name "$DATASET_TABLE_NAME" --argjson db_id "$DB_ID" '{filters:[{col:"table_name",opr:"eq",value:$name},{col:"database_id",opr:"eq",value:($db_id | tonumber)}] }')"
CREATE_DATASET_PAYLOAD=$(jq -n --argjson db_id "$DB_ID" --arg table_name "$DATASET_TABLE_NAME" '{database: ($db_id | tonumber), table_name: $table_name, schema: "public", owners: [1]}')
DATASET_ID=$(get_or_create_asset "dataset" "$DATASET_NAME" "$DATASET_FILTER_Q" "$CREATE_DATASET_PAYLOAD")

# --- 4. Add Metrics to Dataset (FINAL DEFINITIVE VERSION) ---
echo "--- Synchronizing columns and metrics for dataset '$DATASET_NAME' ---" >&2

# Trigger the refresh and then poll until columns are available.
echo "    - Triggering column refresh..." >&2
curl -s -X PUT "$SUPERSET_URL/api/v1/dataset/$DATASET_ID/refresh" -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" > /dev/null

echo "    - Waiting for Superset to discover table columns..." >&2
POLL_ATTEMPTS=0
MAX_POLL_ATTEMPTS=12
COLUMNS_COUNT=0
until [[ $COLUMNS_COUNT -gt 0 || $POLL_ATTEMPTS -ge $MAX_POLL_ATTEMPTS ]]; do
    POLL_ATTEMPTS=$((POLL_ATTEMPTS + 1))
    printf "      Attempt %s/%s..." "$POLL_ATTEMPTS" "$MAX_POLL_ATTEMPTS"
    QUERY_PARAM='q={"columns":["columns"]}'
    set +e
    DATASET_DETAILS=$(curl -s -f -G "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" --data-urlencode "$QUERY_PARAM" -H "Authorization: Bearer $TOKEN")
    CURL_EXIT_CODE=$?
    set -e
    if [[ $CURL_EXIT_CODE -ne 0 ]]; then echo " Curl command failed with exit code $CURL_EXIT_CODE. Retrying in 5 seconds."; sleep 5; continue; fi
    COLUMNS_COUNT=$(echo "$DATASET_DETAILS" | jq '.result.columns | length')
    if [[ $COLUMNS_COUNT -gt 0 ]]; then echo " Found $COLUMNS_COUNT columns."; else echo " No columns found yet in response. Retrying in 5 seconds."; sleep 5; fi
done
if [[ $COLUMNS_COUNT -eq 0 ]]; then echo "❌ ERROR: Dataset columns were not found after waiting." >&2; exit 1; fi
echo "✅ Columns discovered successfully." >&2


# --- ADD METRICS ONE BY ONE WITH CORRECT PAYLOAD LOGIC ---
echo "--- Ensuring all metrics are present in dataset ---" >&2
DESIRED_METRICS=$(jq -n '{"avg_price":"AVG(average_price)","avg_price_change":"AVG(price_change)","avg_bid_ask_spread":"AVG(bid_ask_spread)","avg_rolling_volatility":"AVG(rolling_volatility)","avg_sector_performance":"AVG(sector_performance)","avg_sentiment":"AVG(sentiment_score)"}')

for metric_name in $(echo "$DESIRED_METRICS" | jq -r 'keys[]'); do
    echo "  - Checking for metric: '$metric_name'..." >&2
    
    EXISTING_METRICS=$(curl -s -G "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" --data-urlencode 'q={"columns":["metrics"]}' -H "Authorization: Bearer $TOKEN" | jq '.result.metrics // []')
    metric_exists=$(echo "$EXISTING_METRICS" | jq --arg name "$metric_name" 'any(.metric_name == $name)')

    if [[ "$metric_exists" == "false" ]]; then
        echo "    - Metric not found. Adding it now..." >&2
        
        expression=$(echo "$DESIRED_METRICS" | jq -r ".${metric_name}")
        verbose_name=$(echo "$metric_name" | tr '_' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')
        new_metric_object=$(jq -n --arg name "$metric_name" --arg expr "$expression" --arg vname "$verbose_name" '{"metric_name": $name, "expression": $expr, "verbose_name": $vname}')
        
        metrics_to_upload=$(echo "$EXISTING_METRICS" | jq --argjson new_metric "$new_metric_object" '. + [$new_metric]')
        
        # THE FINAL FIX: This jq command now conditionally includes the 'id' field
        # ONLY if it exists in the source, otherwise it is omitted entirely.
        # This creates the exact payload structure the API requires.
        UPDATE_PAYLOAD=$(echo "$metrics_to_upload" | jq '
          map(
            if .id then {id, metric_name, expression, verbose_name} 
            else {metric_name, expression, verbose_name} 
            end
          ) | {metrics: .}
        ')
        
        UPDATE_RESPONSE=$(curl -s -X PUT "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" -H "Content-Type: application/json" -d "$UPDATE_PAYLOAD")
        
        if echo "$UPDATE_RESPONSE" | jq -e '.result' > /dev/null; then
            echo "    ✅ Successfully added metric '$metric_name'." >&2
        else
            echo "    ❌ Failed to add metric '$metric_name'. Response: $UPDATE_RESPONSE" >&2
            exit 1
        fi
    else
        echo "    - Metric already exists. Skipping." >&2
    fi
done

echo "✅ All required metrics are present in the dataset." >&2
# --- 5. Create Charts ---
# Chart 1: Price Change and Volatility
CHART_1_FILTER_Q="q=$(jq -n --arg name "$CHART_1_NAME" --argjson ds_id "$DATASET_ID" '{filters:[{col:"slice_name",opr:"eq",value:$name}]}')"
CHART_1_PARAMS=$(jq -n '{viz_type:"line", datasource:($ARGS.positional[0]+"__table"), granularity_sqla:"timestamp", time_range:"No filter", metrics:["avg_price_change","avg_rolling_volatility"], groupby:["asset_id"], show_legend:true, row_limit:10000}' --args "$DATASET_ID" | jq -c . | jq -Rs .)
CREATE_CHART_1_PAYLOAD=$(jq -n --arg name "$CHART_1_NAME" --argjson ds_id "$DATASET_ID" --arg params "$CHART_1_PARAMS" '{slice_name:$name, viz_type:"line", datasource_id:$ds_id, datasource_type:"table", params:$params, owners:[1]}')
CHART_1_ID=$(get_or_create_asset "chart" "$CHART_1_NAME" "$CHART_1_FILTER_Q" "$CREATE_CHART_1_PAYLOAD")

# Chart 2: Sentiment and Sector Performance
CHART_2_FILTER_Q="q=$(jq -n --arg name "$CHART_2_NAME" --argjson ds_id "$DATASET_ID" '{filters:[{col:"slice_name",opr:"eq",value:$name}]}')"
CHART_2_PARAMS=$(jq -n '{viz_type:"line", datasource:($ARGS.positional[0]+"__table"), granularity_sqla:"timestamp", time_range:"No filter", metrics:["avg_sentiment","avg_sector_performance"], groupby:["asset_id"], show_legend:true, row_limit:10000}' --args "$DATASET_ID" | jq -c . | jq -Rs .)
CREATE_CHART_2_PAYLOAD=$(jq -n --arg name "$CHART_2_NAME" --argjson ds_id "$DATASET_ID" --arg params "$CHART_2_PARAMS" '{slice_name:$name, viz_type:"line", datasource_id:$ds_id, datasource_type:"table", params:$params, owners:[1]}')
CHART_2_ID=$(get_or_create_asset "chart" "$CHART_2_NAME" "$CHART_2_FILTER_Q" "$CREATE_CHART_2_PAYLOAD")

# --- 6. Create Dashboard and Add Charts ---
echo "--- Managing Dashboard: '$DASHBOARD_TITLE' ---" >&2

DASHBOARD_FILTER_Q="q=$(jq -n --arg title "$DASHBOARD_TITLE" '{filters:[{col:"dashboard_title",opr:"eq",value:$title}]}')"
POSITION_JSON=$(jq -n --argjson c1_id "$CHART_1_ID" --argjson c2_id "$CHART_2_ID" --arg title "$DASHBOARD_TITLE" '
{
    "uuid-root": { "type": "ROOT", "id": "uuid-root", "children": ["uuid-grid"] },
    "uuid-grid": { "type": "GRID", "id": "uuid-grid", "children": ["uuid-header", "uuid-row-1"], "meta": {} },
    "uuid-header": { "type": "HEADER", "id": "uuid-header", "meta": { "text": $title } },
    "uuid-row-1": { "type": "ROW", "id": "uuid-row-1", "children": ["uuid-chart-1", "uuid-chart-2"], "meta": { "background": "BACKGROUND_TRANSPARENT" } },
    "uuid-chart-1": { "type": "CHART", "id": "uuid-chart-1", "children": [], "meta": { "width": 6, "height": 50, "chartId": $c1_id } },
    "uuid-chart-2": { "type": "CHART", "id": "uuid-chart-2", "children": [], "meta": { "width": 6, "height": 50, "chartId": $c2_id } }
}' | jq -c . | jq -Rs .)

# THE FINAL FIX: The "charts" key has been removed from the payload, as it is not allowed on creation.
# The charts are already included correctly in the position_json above.
CREATE_DASHBOARD_PAYLOAD=$(jq -n \
    --arg title "$DASHBOARD_TITLE" \
    --arg position "$POSITION_JSON" \
    '{dashboard_title: $title, position_json: $position, published: true, owners: [1]}')

DASHBOARD_ID=$(get_or_create_asset "dashboard" "$DASHBOARD_TITLE" "$DASHBOARD_FILTER_Q" "$CREATE_DASHBOARD_PAYLOAD")

# --- Final ---
echo ""
echo "🎉 SUCCESS! Superset setup complete!"
echo "🌐 Visit your new dashboard: $SUPERSET_URL/superset/dashboard/$DASHBOARD_ID/"