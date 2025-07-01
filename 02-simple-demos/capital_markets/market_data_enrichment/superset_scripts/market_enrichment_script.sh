#!/bin/bash

set -e
set -o pipefail

# --- Configuration ---
SUPERSET_URL="${SUPERSET_URL:-http://localhost:8088}"
SUPERSET_USERNAME="${SUPERSET_USERNAME:-admin}"
SUPERSET_PASSWORD="${SUPERSET_PASSWORD:-admin}"
DB_NAME="Postgres_Market_Data"
SQLALCHEMY_URI="postgresql://pguser:pgpass@postgres:5432/pgdb"
DATASET_TABLE_NAME="enriched_market_data_sink"
DATASET_NAME="Enriched Market Data"
CHART_1_NAME="Price Change and Volatility Over Time"
CHART_2_NAME="Average Bid Ask Spread Over Time"
DASHBOARD_TITLE="Enriched Market Analysis Dashboard"

# --- Pre-requisite Checks ---
if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
    echo "Error: 'curl' and 'jq' are required." >&2; exit 1; fi

# --- Helper Function for Idempotent Asset Creation ---
get_or_create_asset() {
    local asset_type="$1"; local asset_name="$2"; local filter_q="$3"; local create_payload="$4"; local existing_id=""
    echo "--- Managing ${asset_type^}: '$asset_name' ---" >&2
    local get_response; get_response=$(curl -s -G "$SUPERSET_URL/api/v1/$asset_type/" \
      -H "Authorization: Bearer $TOKEN" --data-urlencode "$filter_q")
    existing_id=$(echo "$get_response" | jq -r '.result[0].id // empty')
    if [[ -n "$existing_id" ]]; then echo "$existing_id"; return; fi
    local create_response; create_response=$(curl -s -X POST "$SUPERSET_URL/api/v1/$asset_type/" \
      -H "Authorization: Bearer $TOKEN" \
      -H "X-CSRFToken: $CSRF_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$create_payload")
    local new_id; new_id=$(echo "$create_response" | jq -r '.id // empty')
    if [[ -z "$new_id" ]]; then echo "Failed to create $asset_type '$asset_name'. Response: $create_response" >&2; exit 1; fi
    echo "$new_id"
}

# --- 1. Authentication ---
echo "Waiting for Superset API..." >&2
until curl -s "$SUPERSET_URL/api/v1/ping" &> /dev/null; do sleep 1; done
echo "Superset is up." >&2

echo "Waiting for Superset to fully initialize..." >&2
sleep 10

LOGIN_RESPONSE=$(curl -s -X POST "$SUPERSET_URL/api/v1/security/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\": \"$SUPERSET_USERNAME\", \"password\": \"$SUPERSET_PASSWORD\", \"provider\": \"db\"}")
TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token // empty')
[[ -z "$TOKEN" ]] && echo "Login failed. Response: $LOGIN_RESPONSE" >&2 && exit 1
echo "Login successful." >&2
CSRF_TOKEN=$(curl -s -H "Authorization: Bearer $TOKEN" "$SUPERSET_URL/api/v1/security/csrf_token/" | jq -r '.result // empty')
[[ -z "$CSRF_TOKEN" ]] && echo "Failed to get CSRF token." >&2 && exit 1
echo "Got CSRF token." >&2

# --- 2. Database ---
DB_FILTER_Q="q=$(jq -n --arg name "$DB_NAME" '{filters:[{col:"database_name",opr:"eq",value:$name}]}')"
CREATE_DB_PAYLOAD=$(jq -n --arg name "$DB_NAME" --arg uri "$SQLALCHEMY_URI" '{database_name:$name,sqlalchemy_uri:$uri,expose_in_sqllab:true}')
DB_ID=$(get_or_create_asset "database" "$DB_NAME" "$DB_FILTER_Q" "$CREATE_DB_PAYLOAD")

echo "Testing database connection..." >&2
TEST_DB_RESPONSE=$(curl -s -X POST "$SUPERSET_URL/api/v1/database/test_connection" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-CSRFToken: $CSRF_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"sqlalchemy_uri\": \"$SQLALCHEMY_URI\", \"database_name\": \"$DB_NAME\"}")
if echo "$TEST_DB_RESPONSE" | jq -e '.message // empty' | grep -q "OK"; then
    echo "Database connection successful." >&2
else
    echo "Database connection failed: $TEST_DB_RESPONSE" >&2
    exit 1
fi

# --- 3. Dataset ---
DATASET_FILTER_Q="q=$(jq -n --arg name "$DATASET_TABLE_NAME" --argjson db_id "$DB_ID" '{filters:[{col:"table_name",opr:"eq",value:$name},{col:"database_id",opr:"eq",value:($db_id|tonumber)}]}')"
CREATE_DATASET_PAYLOAD=$(jq -n --argjson db_id "$DB_ID" --arg table_name "$DATASET_TABLE_NAME" '{database:($db_id|tonumber),table_name:$table_name,schema:"public",owners:[1]}')
DATASET_ID=$(get_or_create_asset "dataset" "$DATASET_NAME" "$DATASET_FILTER_Q" "$CREATE_DATASET_PAYLOAD")

# Refresh & configure dataset
echo "Refreshing dataset and waiting for columns..." >&2
curl -s -X PUT "$SUPERSET_URL/api/v1/dataset/$DATASET_ID/refresh" \
  -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" > /dev/null

# Poll until columns are discovered
POLL=0; MAX=20; COUNT=0
while [[ $COUNT -eq 0 && $POLL -lt $MAX ]]; do
  POLL=$((POLL+1))
  DETAILS=$(curl -s -G "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" --data-urlencode 'q={"columns":["columns"]}' -H "Authorization: Bearer $TOKEN")
  COUNT=$(echo "$DETAILS" | jq '.result.columns|length')
  sleep 5
done
[[ $COUNT -eq 0 ]] && echo "Dataset columns not found." >&2 && exit 1

# Set timestamp column
UPDATE_PAYLOAD='{"main_dttm_col":"timestamp"}'
curl -s -X PUT "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" \
  -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" \
  -H "Content-Type: application/json" -d "$UPDATE_PAYLOAD" >/dev/null

echo "Dataset configured." >&2

# --- 4. Metrics ---
echo "Adding metrics..." >&2
METRICS_JSON=$(jq -n '{"avg_price":"AVG(average_price)","avg_price_change":"AVG(price_change)","avg_bid_ask_spread":"AVG(bid_ask_spread)","avg_rolling_volatility":"AVG(rolling_volatility)"}')
EXISTING_METRICS=$(curl -s -G "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" --data-urlencode 'q={"columns":["metrics"]}' -H "Authorization: Bearer $TOKEN" | jq '.result.metrics')
for name in $(echo "$METRICS_JSON" | jq -r 'keys[]'); do
  if ! echo "$EXISTING_METRICS" | jq -e --arg n "$name" 'any(.metric_name==$n)'; then
    expr=$(echo "$METRICS_JSON" | jq -r ".[$name]")
    vname=$(echo "$name" | sed -E 's/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
    OBJ=$(jq -n --arg m "$name" --arg e "$expr" --arg v "$vname" '{metric_name:$m,expression:$e,verbose_name:$v}')
    UPDATED=$(echo "$EXISTING_METRICS" | jq --argjson o "$OBJ" '. + [$o]')
    curl -s -X PUT "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" \
      -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --argjson m "$UPDATED" '{metrics:$m}')" >/dev/null
  fi
done
echo "Metrics ready." >&2

# --- 5. Charts ---
echo "Creating charts..." >&2
# Chart 1
CH1_FILTER="q=$(jq -n --arg n "$CHART_1_NAME" '{filters:[{col:"slice_name",opr:"eq",value:$n}]}')"
CH1_PARAMS=$(jq -n --argjson ds "$DATASET_ID" '{viz_type:"line",datasource:"\($ds)__table",granularity_sqla:"timestamp",time_range:"No filter",metrics:["avg_price_change","avg_rolling_volatility"],show_legend:true,row_limit:10000,time_grain_sqla:"PT1S",show_brush:"auto",show_markers:false,rich_tooltip:true,tooltip_sort_by_metric:true,show_controls:true}')
CH1_PAYLOAD=$(jq -n --arg n "$CHART_1_NAME" --argjson ds "$DATASET_ID" --argjson p "$CH1_PARAMS" '{slice_name:$n,viz_type:"line",datasource_id:$ds,datasource_type:"table",params:( $p|tostring ),owners:[1]}')
CHART_1_ID=$(get_or_create_asset "chart" "$CHART_1_NAME" "$CH1_FILTER" "$CH1_PAYLOAD")
# Chart 2
CH2_FILTER="q=$(jq -n --arg n "$CHART_2_NAME" '{filters:[{col:"slice_name",opr:"eq",value:$n}]}')"
CH2_PARAMS=$(jq -n --argjson ds "$DATASET_ID" '{viz_type:"line",datasource:"\($ds)__table",granularity_sqla:"timestamp",time_range:"No filter",metrics:["avg_bid_ask_spread"],show_legend:true,row_limit:10000,time_grain_sqla:"PT1S",show_brush:"auto",show_markers:false,rich_tooltip:true,tooltip_sort_by_metric:true,show_controls:true}')
CH2_PAYLOAD=$(jq -n --arg n "$CHART_2_NAME" --argjson ds "$DATASET_ID" --argjson p "$CH2_PARAMS" '{slice_name:$n,viz_type:"line",datasource_id:$ds,datasource_type:"table",params:( $p|tostring ),owners:[1]}')
CHART_2_ID=$(get_or_create_asset "chart" "$CHART_2_NAME" "$CH2_FILTER" "$CH2_PAYLOAD")
echo "Charts created: $CHART_1_ID, $CHART_2_ID." >&2

# --- 6. Dashboard ---
echo "Creating dashboard..." >&2
DBD_FILTER="q=$(jq -n --arg t "$DASHBOARD_TITLE" '{filters:[{col:"dashboard_title",opr:"eq",value:$t}]}')"
DBD_PAYLOAD=$(jq -n --arg t "$DASHBOARD_TITLE" '{dashboard_title:$t,owners:[1],published:true}')
DASHBOARD_ID=$(get_or_create_asset "dashboard" "$DASHBOARD_TITLE" "$DBD_FILTER" "$DBD_PAYLOAD")

# Layout JSON
POSITIONS=$(jq -n --arg c1 "$CHART_1_ID" --arg c2 "$CHART_2_ID" '{
  DASHBOARD_VERSION_KEY:"v2",
  ROOT_ID:{type:"ROOT",id:"ROOT_ID",children:["GRID_ID"]},
  GRID_ID:{type:"GRID",id:"GRID_ID",children:["ROW_ID_1","ROW_ID_2"]},
  ROW_ID_1:{type:"ROW",id:"ROW_ID_1",children:["CHART_ID_1"]},
  CHART_ID_1:{type:"CHART",id:"CHART_ID_1",meta:{sliceId:(\$c1|tonumber)}},
  ROW_ID_2:{type:"ROW",id:"ROW_ID_2",children:["CHART_ID_2"]},
  CHART_ID_2:{type:"CHART",id:"CHART_ID_2",meta:{sliceId:(\$c2|tonumber)}}
}')

curl -s -X PUT "$SUPERSET_URL/api/v1/dashboard/$DASHBOARD_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-CSRFToken: $CSRF_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"positions\":$POSITIONS}" >/dev/null

echo "Dashboard created: $SUPERSET_URL/superset/dashboard/$DASHBOARD_ID/" >&2

echo "SUCCESS! Superset setup complete."
