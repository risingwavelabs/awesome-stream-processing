#!/bin/bash
set -e
set -o pipefail

# --- Configuration ---
SUPERSET_URL="${SUPERSET_URL:-http://localhost:8088}"
SUPERSET_USERNAME="${SUPERSET_USERNAME:-admin}"
SUPERSET_PASSWORD="${SUPERSET_PASSWORD:-admin}"
DB_NAME="Postgres_Market_Data"
SQLALCHEMY_URI="risingwave://root@risingwave:4566/dev"
DATASET_TABLE_NAME="enriched_market_data"
DATASET_NAME="Enriched Market Data"
CHART_1_NAME="Price Change Over Time"
CHART_2_NAME="Average Bid Ask Spread Over Time"
CHART_3_NAME="Sentiment over Time Chart"
CHART_4_NAME="Asset Volatility Pie Chart"

DASHBOARD_TITLE="Enriched Market Analysis Dashboard"


# --- Pre-requisite Checks ---
if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
   echo "Error: 'curl' and 'jq' are required." >&2; exit 1; fi


# --- Helper Function for Idempotent Asset Creation ---
get_or_create_asset() {
   local asset_type="$1"; local asset_name="$2"; local filter_q="$3"; local create_payload="$4"; local existing_id=""
   echo "--- Managing ${asset_type^}: '$asset_name' ---" >&2
   local get_response; get_response=$(curl -s -G "$SUPERSET_URL/api/v1/$asset_type/" -H "Authorization: Bearer $TOKEN" --data-urlencode "$filter_q")
   existing_id=$(echo "$get_response" | jq -r '.result[0].id // empty')
   if [[ -n "$existing_id" ]]; then echo "${asset_type^} '$asset_name' already exists with ID: $existing_id" >&2; echo "$existing_id"; return; fi
   echo "${asset_type^} '$asset_name' not found, creating it..." >&2
   local create_response; create_response=$(curl -s -X POST "$SUPERSET_URL/api/v1/$asset_type/" -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" -H "Content-Type: application/json" -d "$create_payload")
   local new_id; new_id=$(echo "$create_response" | jq -r '.id // empty')
   if [[ -z "$new_id" ]]; then echo "Failed to create ${asset_type} '$asset_name'. Response: $create_response" >&2; exit 1; fi
   echo "${asset_type^} '$asset_name' created with ID: $new_id" >&2; echo "$new_id"
}


# --- 1. Authentication ---
echo "Waiting for Superset API..." >&2
until curl -s "$SUPERSET_URL/api/v1/ping" &> /dev/null; do sleep 1 && printf "."; done
echo -e "\nSuperset is up." >&2


echo "Waiting for Superset to fully initialize..." >&2
sleep 10


LOGIN_RESPONSE=$(curl -s -X POST "$SUPERSET_URL/api/v1/security/login" -H 'Content-Type: application/json' -d "{\"username\": \"$SUPERSET_USERNAME\", \"password\": \"$SUPERSET_PASSWORD\", \"provider\": \"db\"}")
TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token // empty')
[[ -z "$TOKEN" ]] && echo "Login failed. Response: $LOGIN_RESPONSE" >&2 && exit 1
echo "Login successful." >&2
CSRF_TOKEN=$(curl -s -H "Authorization: Bearer $TOKEN" "$SUPERSET_URL/api/v1/security/csrf_token/" | jq -r '.result // empty')
[[ -z "$CSRF_TOKEN" ]] && echo "Failed to get CSRF token." >&2 && exit 1
echo "Got CSRF token." >&2


# --- 2. Get or Create Database ---
DB_FILTER_Q="q=$(jq -n --arg name "$DB_NAME" '{filters:[{col:"database_name",opr:"eq",value:$name}]}')"
CREATE_DB_PAYLOAD=$(jq -n --arg name "$DB_NAME" --arg uri "$SQLALCHEMY_URI" '{database_name: $name, sqlalchemy_uri: $uri, expose_in_sqllab: true}')
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
   echo "Database connection test failed: $TEST_DB_RESPONSE" >&2
fi


# --- 3. Get or Create Dataset ---
DATASET_FILTER_Q="q=$(jq -n --arg name "$DATASET_TABLE_NAME" --argjson db_id "$DB_ID" '{filters:[{col:"table_name",opr:"eq",value:$name},{col:"database_id",opr:"eq",value:($db_id|tonumber)}]}')"
CREATE_DATASET_PAYLOAD=$(jq -n --argjson db_id "$DB_ID" --arg table_name "$DATASET_TABLE_NAME" '{database:($db_id|tonumber), table_name:$table_name, schema:"public", owners:[1]}')
DATASET_ID=$(get_or_create_asset "dataset" "$DATASET_NAME" "$DATASET_FILTER_Q" "$CREATE_DATASET_PAYLOAD")


#wait and set main time
echo "--- Configuring dataset properties ---" >&2
curl -s -X PUT "$SUPERSET_URL/api/v1/dataset/$DATASET_ID/refresh" -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" > /dev/null


echo "    - Waiting for Superset to discover table columns..." >&2
POLL_ATTEMPTS=0; MAX_POLL_ATTEMPTS=20; COLUMNS_COUNT=0
until [[ $COLUMNS_COUNT -gt 0 || $POLL_ATTEMPTS -ge $MAX_POLL_ATTEMPTS ]]; do
   POLL_ATTEMPTS=$((POLL_ATTEMPTS+1)); printf "      Attempt %s/%s..." "$POLL_ATTEMPTS" "$MAX_POLL_ATTEMPTS"
   QUERY_PARAM='q={"columns":["columns"]}'; set +e
   DATASET_DETAILS=$(curl -s -f -G "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" --data-urlencode "$QUERY_PARAM" -H "Authorization: Bearer $TOKEN"); CURL_EXIT_CODE=$?
   set -e; if [[ $CURL_EXIT_CODE -ne 0 ]]; then echo " Curl failed. Retrying..."; sleep 5; continue; fi
   COLUMNS_COUNT=$(echo "$DATASET_DETAILS" | jq '.result.columns | length'); if [[ $COLUMNS_COUNT -gt 0 ]]; then echo " Found $COLUMNS_COUNT columns."; else echo " No columns yet. Retrying..."; sleep 8; fi
done


if [[ $COLUMNS_COUNT -eq 0 ]]; then
   echo "ERROR: Dataset columns not found after $MAX_POLL_ATTEMPTS attempts." >&2
   echo "Dataset details response: $DATASET_DETAILS" >&2
   exit 1
fi


#check timestamp column
TIMESTAMP_COLUMN=$(echo "$DATASET_DETAILS" | jq -r '.result.columns[] | select(.column_name=="timestamp") | .column_name // empty')
if [[ -z "$TIMESTAMP_COLUMN" ]]; then
   echo "ERROR: 'timestamp' column not found in dataset. Available columns:" >&2
   echo "$DATASET_DETAILS" | jq -r '.result.columns[].column_name' >&2
   exit 1
fi


echo "    - Setting main datetime column to 'timestamp'..." >&2
UPDATE_DATASET_PAYLOAD=$(jq -n '{"main_dttm_col":"timestamp"}')
UPDATE_DATASET_RESPONSE=$(curl -s -X PUT "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" -H "Content-Type: application/json" -d "$UPDATE_DATASET_PAYLOAD")
if ! echo "$UPDATE_DATASET_RESPONSE" | jq -e '.result.main_dttm_col=="timestamp"' > /dev/null; then
   echo " Failed to set datetime column. Response: $UPDATE_DATASET_RESPONSE" >&2
   exit 1
fi
echo "Dataset configured successfully." >&2


#adding metrics
echo "--- Ensuring all metrics are present in dataset ---" >&2
DESIRED_METRICS=$(jq -n '{
   "avg_price":"AVG(average_price)",
   "avg_price_change":"AVG(price_change)",
   "sum_price_change":"SUM(price_change)",
   "avg_bid_ask_spread":"AVG(bid_ask_spread)",
   "avg_rolling_volatility":"AVG(rolling_volatility)",
   "avg_sector_performance":"AVG(sector_performance)",
   "avg_sentiment":"AVG(sentiment_score)"
}')


for metric_name in $(echo "$DESIRED_METRICS" | jq -r 'keys[]'); do
   echo "  - Checking for metric: '$metric_name'..." >&2
   EXISTING_METRICS=$(curl -s -G "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" --data-urlencode 'q={"columns":["metrics"]}' -H "Authorization: Bearer $TOKEN" | jq '.result.metrics // []')
   metric_exists=$(echo "$EXISTING_METRICS" | jq --arg name "$metric_name" 'any(.metric_name == $name)')
   if [[ "$metric_exists" == "false" ]]; then
       expression=$(jq -r --arg key "$metric_name" '.[$key]' <<<"$DESIRED_METRICS")
       verbose_name=$(echo "$metric_name"|tr '_' ' '|awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')
       new_metric_object=$(jq -n --arg name "$metric_name" --arg expr "$expression" --arg vname "$verbose_name" '{"metric_name":$name,"expression":$expr,"verbose_name":$vname}')
       metrics_to_upload=$(echo "$EXISTING_METRICS" | jq --argjson new_metric "$new_metric_object" '. + [$new_metric]')
       UPDATE_PAYLOAD=$(echo "$metrics_to_upload"|jq 'map(if .id then {id,metric_name,expression,verbose_name} else {metric_name,expression,verbose_name} end)|{metrics:.}')
       UPDATE_RESPONSE=$(curl -s -X PUT "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" -H "Content-Type: application/json" -d "$UPDATE_PAYLOAD")
       if echo "$UPDATE_RESPONSE"|jq -e '.result'>/dev/null; then
           echo "    - Added metric '$metric_name'." >&2
       else
           echo "    - Failed to add metric '$metric_name'. Response: $UPDATE_RESPONSE" >&2
       fi
   else
       echo "    - Metric already exists. Skipping." >&2
   fi
done
echo "Metrics processing complete." >&2

echo "Refreshing dataset to apply changes..."
curl -s -X PUT "$SUPERSET_URL/api/v1/dataset/$DATASET_ID/refresh" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-CSRFToken: $CSRF_TOKEN" > /dev/null
sleep 5

# --- 4. Create Charts ---
echo "--- Creating charts ---" >&2

# Chart 1 - Price Change
CHART_1_FILTER_Q="q=$(jq -n --arg name "$CHART_1_NAME" '{filters:[{col:"slice_name",opr:"eq",value:$name}]}')"
CHART_1_PARAMS=$(jq -n --argjson ds_id "$DATASET_ID" '{
   "viz_type": "line",
   "datasource": "\($ds_id)__table",
   "granularity_sqla": "timestamp",
   "time_range": "No filter",
   "metrics": ["avg_price_change", "avg_rolling_volatility"],
   "show_legend": true,
   "row_limit": 10000,
   "time_grain_sqla": "PT1S",
   "show_brush": true,
   "show_markers": false,
   "rich_tooltip": true,
   "tooltip_sort_by_metric": true,
   "color_scheme": "supersetColors",
   "show_controls": true,
   "x_axis_label": "",
   "bottom_margin": "auto",
   "x_ticks_layout": "auto",
   "y_axis_label": "",
   "left_margin": "auto",
   "y_axis_bounds": [null, null],
   "rolling_type": "None",
   "comparison_type": "values",
   "annotation_layers": []
}')
CREATE_CHART_1_PAYLOAD=$(jq -n --arg name "$CHART_1_NAME" --argjson ds_id "$DATASET_ID" --argjson params "$CHART_1_PARAMS" '{
   "slice_name": $name,
   "viz_type": "line",
   "datasource_id": $ds_id,
   "datasource_type": "table",
   "params": ($params | tostring),
   "owners": [1]
}')
CHART_1_ID=$(get_or_create_asset "chart" "$CHART_1_NAME" "$CHART_1_FILTER_Q" "$CREATE_CHART_1_PAYLOAD")


# Chart 2 - Average Bid Ask Spread
CHART_2_FILTER_Q="q=$(jq -n --arg name "$CHART_2_NAME" '{filters:[{col:"slice_name",opr:"eq",value:$name}]}')"
CHART_2_PARAMS=$(jq -n --argjson ds_id "$DATASET_ID" '{
   "viz_type": "line",
   "datasource": "\($ds_id)__table",
   "granularity_sqla": "timestamp",
   "time_range": "No filter",
   "metrics": ["avg_bid_ask_spread"],
   "groupby": ["asset_id"],
   "show_legend": true,
   "row_limit": 10000,
   "time_grain_sqla": "PT1S",
   "show_brush": true,
   "show_markers": false,
   "rich_tooltip": true,
   "tooltip_sort_by_metric": true,
   "color_scheme": "supersetColors",
   "show_controls": true,
   "x_axis_label": "",
   "bottom_margin": "auto",
   "x_ticks_layout": "auto",
   "y_axis_label": "",
   "left_margin": "auto",
   "y_axis_bounds": [null, null],
   "rolling_type": "None",
   "comparison_type": "values",
   "annotation_layers": []
}')
CREATE_CHART_2_PAYLOAD=$(jq -n --arg name "$CHART_2_NAME" --argjson ds_id "$DATASET_ID" --argjson params "$CHART_2_PARAMS" '{
   "slice_name": $name,
   "viz_type": "line",
   "datasource_id": $ds_id,
   "datasource_type": "table",
   "params": ($params | tostring),
   "owners": [1]
}')
CHART_2_ID=$(get_or_create_asset "chart" "$CHART_2_NAME" "$CHART_2_FILTER_Q" "$CREATE_CHART_2_PAYLOAD")

# Chart 3 - Sentiment Over Time
CHART_3_FILTER_Q="q=$(jq -n --arg name "$CHART_3_NAME" '{filters:[{col:"slice_name",opr:"eq",value:$name}]}')"
CHART_3_PARAMS=$(jq -n --argjson ds_id "$DATASET_ID" '{
   "viz_type": "line",
   "datasource": "\($ds_id)__table",
   "granularity_sqla": "timestamp",
   "time_range": "No filter",
   "metrics": ["avg_sentiment"],
   "show_legend": true,
   "row_limit": 10000,
   "time_grain_sqla": "PT1S",
   "show_brush": true,
   "show_markers": false,
   "rich_tooltip": true,
   "tooltip_sort_by_metric": true,
   "color_scheme": "supersetColors",
   "show_controls": true,
   "x_axis_label": "",
   "bottom_margin": "auto",
   "x_ticks_layout": "auto",
   "y_axis_label": "",
   "left_margin": "auto",
   "y_axis_bounds": [null, null],
   "rolling_type": "None",
   "comparison_type": "values",
   "annotation_layers": []
}')
CREATE_CHART_3_PAYLOAD=$(jq -n --arg name "$CHART_3_NAME" --argjson ds_id "$DATASET_ID" --argjson params "$CHART_3_PARAMS" '{
   "slice_name": $name,
   "viz_type": "line",
   "datasource_id": $ds_id,
   "datasource_type": "table",
   "params": ($params | tostring),
   "owners": [1]
}')
CHART_3_ID=$(get_or_create_asset "chart" "$CHART_3_NAME" "$CHART_3_FILTER_Q" "$CREATE_CHART_3_PAYLOAD")

# Chart 4 - Asset Volatility Pie Chart
CHART_4_FILTER_Q="q=$(jq -n --arg name "$CHART_4_NAME" '{filters:[{col:"slice_name",opr:"eq",value:$name}]}')"
CHART_4_PARAMS=$(jq -n --argjson ds_id "$DATASET_ID" '{
   "viz_type": "pie",
   "datasource": "\($ds_id)__table",
   "time_range": "No filter",
   "metric": "sum_price_change",
   "groupby": ["asset_id"],
   "row_limit": 50,
   "pie_label_type": "key_value",
   "donut": false,
   "show_labels": true,
   "labels_outside": true,
   "color_scheme": "supersetColors",
   "show_legend": true,
   "rich_tooltip": true
}')
CREATE_CHART_4_PAYLOAD=$(jq -n --arg name "$CHART_4_NAME" --argjson ds_id "$DATASET_ID" --argjson params "$CHART_4_PARAMS" '{
   "slice_name": $name,
   "viz_type": "pie",
   "datasource_id": $ds_id,
   "datasource_type": "table",
   "params": ($params | tostring),
   "owners": [1]
}')
CHART_4_ID=$(get_or_create_asset "chart" "$CHART_4_NAME" "$CHART_4_FILTER_Q" "$CREATE_CHART_4_PAYLOAD")

# dashboard creation
# --- 5. Create Dashboard ---
echo "--- Creating dashboard ---" >&2

DASHBOARD_FILTER_Q="q=$(jq -n --arg name "$DASHBOARD_TITLE" '{filters:[{col:"dashboard_title",opr:"eq",value:$name}]}')"
DASHBOARD_SLUG=$(echo "$DASHBOARD_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
CREATE_DASHBOARD_PAYLOAD=$(jq -n --arg title "$DASHBOARD_TITLE" --arg slug "$DASHBOARD_SLUG" '{
   "dashboard_title": $title,
   "slug": $slug,
   "owners": [1],
   "position_json": "{}",
   "css": "",
   "json_metadata": "{}",
   "published": false
}')

# First check if dashboard already exists
echo "Checking if dashboard '$DASHBOARD_TITLE' already exists..." >&2
DASHBOARD_GET_RESPONSE=$(curl -s -G "$SUPERSET_URL/api/v1/dashboard/" -H "Authorization: Bearer $TOKEN" --data-urlencode "$DASHBOARD_FILTER_Q")
EXISTING_DASHBOARD_ID=$(echo "$DASHBOARD_GET_RESPONSE" | jq -r '.result[0].id // empty')

if [[ -n "$EXISTING_DASHBOARD_ID" ]]; then
    echo "Dashboard '$DASHBOARD_TITLE' already exists with ID: $EXISTING_DASHBOARD_ID" >&2
    DASHBOARD_ID="$EXISTING_DASHBOARD_ID"
else
    echo "Dashboard '$DASHBOARD_TITLE' not found, creating it..." >&2
    CREATE_DASHBOARD_RESPONSE=$(curl -s -X POST "$SUPERSET_URL/api/v1/dashboard/" \
        -H "Authorization: Bearer $TOKEN" \
        -H "X-CSRFToken: $CSRF_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$CREATE_DASHBOARD_PAYLOAD")
    
    DASHBOARD_ID=$(echo "$CREATE_DASHBOARD_RESPONSE" | jq -r '.id // empty')
    if [[ -z "$DASHBOARD_ID" ]]; then
        echo "Failed to create dashboard '$DASHBOARD_TITLE'. Response: $CREATE_DASHBOARD_RESPONSE" >&2
        exit 1
    fi
    echo "Dashboard '$DASHBOARD_TITLE' created with ID: $DASHBOARD_ID" >&2
fi


echo " - Chart 1: $SUPERSET_URL/explore/?slice_id=$CHART_1_ID"
echo " - Chart 2: $SUPERSET_URL/explore/?slice_id=$CHART_2_ID"
echo " - Chart 3: $SUPERSET_URL/explore/?slice_id=$CHART_3_ID"
echo " - Chart 4: $SUPERSET_URL/explore/?slice_id=$CHART_4_ID"