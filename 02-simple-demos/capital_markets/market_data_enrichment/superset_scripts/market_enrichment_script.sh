#!/bin/bash

# Exit on any error
set -e

# Wait for Superset to be ready
echo "⏳ Waiting for Superset API..."
until curl -s http://localhost:8088/api/v1/ping > /dev/null; do
  sleep 5
done
echo "✅ Superset API is up!"

# Log in to Superset and get the access token
echo "🔐 Logging in to Superset..."
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/security/login \
  -H 'Content-Type: application/json' \
  -d '{"username": "admin", "password": "admin", "provider": "db"}')

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token')

if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
  echo "❌ Failed to authenticate with Superset."
  echo "Login response: $LOGIN_RESPONSE"
  exit 1
fi

echo "🔑 Got access token."

# Check for existing databases
DB_RESPONSE=$(curl -s -X GET http://localhost:8088/api/v1/database/ \
  -H "Authorization: Bearer $TOKEN")
DB_COUNT=$(echo "$DB_RESPONSE" | jq '.count')

if [[ "$DB_COUNT" == "0" ]]; then
  echo "🗄️ Creating PostgreSQL database connection..."
  CREATE_DB_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/database/ \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "database_name": "postgres_db",
      "sqlalchemy_uri": "postgresql://pguser:pgpass@postgres:5432/pgdb"
    }')
  DB_ID=$(echo "$CREATE_DB_RESPONSE" | jq -r '.id // empty')
else
  # Use the ID of the first existing database
  DB_ID=$(echo "$DB_RESPONSE" | jq -r '.result[0].id')
fi

if [[ -z "$DB_ID" || "$DB_ID" == "null" ]]; then
  echo "❌ Failed to find or create a database ID."
  echo "Database response: $DB_RESPONSE"
  exit 1
fi

echo "🗃️ Using database ID: $DB_ID"

# --- START: Dataset Creation/Lookup ---
DATASET_NAME="avg_price_sink"
echo "📊 Checking for existing dataset '$DATASET_NAME'..."

# Construct the filter for the dataset lookup
DATASET_FILTER=$(jq -n \
  --arg db_id "$DB_ID" \
  --arg table_name "$DATASET_NAME" \
  '{ "filters": [
      { "col": "table_name", "opr": "eq", "value": $table_name },
      { "col": "database_id", "opr": "eq", "value": ($db_id | tonumber) }
    ]
  }' | jq -Rs '{"q": .}' ) # Wrap in {"q": ...} and stringify for the query parameter

GET_DATASET_RESPONSE=$(curl -s -G "http://localhost:8088/api/v1/dataset/" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "$DATASET_FILTER")

DATASET_ID=$(echo "$GET_DATASET_RESPONSE" | jq -r '.result[0].id // empty')

if [[ -z "$DATASET_ID" || "$DATASET_ID" == "null" ]]; then
  echo "➡️ Dataset '$DATASET_NAME' not found, creating it..."
  CREATE_DATASET_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/dataset/ \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "database": '"$DB_ID"',
      "schema": "public",
      "table_name": "'"$DATASET_NAME"'"
    }')
  DATASET_ID=$(echo "$CREATE_DATASET_RESPONSE" | jq -r '.id // empty')
  if [[ -z "$DATASET_ID" || "$DATASET_ID" == "null" ]]; then
    echo "❌ Failed to create dataset. Response:"
    echo "$CREATE_DATASET_RESPONSE"
    exit 1
  fi
  echo "📈 Created dataset with ID: $DATASET_ID"
else
  echo "✅ Dataset '$DATASET_NAME' already exists with ID: $DATASET_ID"
fi
# --- END: Dataset Creation/Lookup ---


# --- START: Add Metrics to Dataset ---
echo "➕ Checking and adding necessary metrics to dataset..."

# Get current dataset details including columns and existing metrics
CURRENT_DATASET_DETAILS=$(curl -s -X GET "http://localhost:8088/api/v1/dataset/$DATASET_ID" \
  -H "Authorization: Bearer $TOKEN")

# Extract existing column names
EXISTING_COLUMN_NAMES=$(echo "$CURRENT_DATASET_DETAILS" | jq -r '.result.columns[]?.column_name // empty')

# Initialize the array that will hold the *final* set of metrics to send in the PUT request
# Start with existing metrics. Default to empty array if none exist, or if metrics_dict is null.
FINAL_METRICS_PAYLOAD=$(echo "$CURRENT_DATASET_DETAILS" | jq -r '(.result.metrics_dict // {}) | to_entries | map(.value)')

METRICS_ADDED_THIS_RUN=0

# Helper function to check if a metric name already exists in the FINAL_METRICS_PAYLOAD array
metric_exists_in_final_payload() {
  local metric_name_to_check="$1"
  # Use -e flag for jq to return non-zero exit code if no match is found
  echo "$FINAL_METRICS_PAYLOAD" | jq -e ".[] | select(.metric_name == \"$metric_name_to_check\")" > /dev/null
}

# Helper function to check if a column exists in the dataset
column_exists_in_dataset() {
  local column_name_to_check="$1"
  echo "$EXISTING_COLUMN_NAMES" | grep -q "^$column_name_to_check$"
}

# Check and add 'average_price' metric
if column_exists_in_dataset "average_price"; then
  if ! metric_exists_in_final_payload "average_price"; then
    echo "    - 'average_price' metric not found, adding it."
    FINAL_METRICS_PAYLOAD=$(echo "$FINAL_METRICS_PAYLOAD" | jq '. + [{"metric_name": "average_price", "expression": "AVG(average_price)", "verbose_name": "Average Price"}]')
    METRICS_ADDED_THIS_RUN=$((METRICS_ADDED_THIS_RUN + 1))
  else
    echo "    - 'average_price' metric already exists."
  fi
else
  echo "    ⚠️ Warning: Column 'average_price' not found in dataset. Skipping 'average_price' metric creation."
fi

# Check and add 'bid_ask_spread' metric
if column_exists_in_dataset "bid_ask_spread"; then
  if ! metric_exists_in_final_payload "bid_ask_spread"; then
    echo "    - 'bid_ask_spread' metric not found, adding it (as SUM for flexibility)."
    FINAL_METRICS_PAYLOAD=$(echo "$FINAL_METRICS_PAYLOAD" | jq '. + [{"metric_name": "bid_ask_spread", "expression": "SUM(bid_ask_spread)", "verbose_name": "Bid Ask Spread Sum"}]')
    METRICS_ADDED_THIS_RUN=$((METRICS_ADDED_THIS_RUN + 1))
  else
    echo "    - 'bid_ask_spread' metric already exists."
  fi
else
  echo "    ⚠️ Warning: Column 'bid_ask_spread' not found in dataset. Skipping 'bid_ask_spread' metric creation."
fi

# Check and add 'count' metric (COUNT(*))
if ! metric_exists_in_final_payload "count"; then
  echo "    - 'count' metric not found, adding it."
  FINAL_METRICS_PAYLOAD=$(echo "$FINAL_METRICS_PAYLOAD" | jq '. + [{"metric_name": "count", "expression": "COUNT(*)", "verbose_name": "Count"}]')
  METRICS_ADDED_THIS_RUN=$((METRICS_ADDED_THIS_RUN + 1))
else
  echo "    - 'count' metric already exists."
fi

# Prepare the payload to update the dataset with the *complete and de-duplicated* list of metrics
UPDATE_DATASET_PAYLOAD=$(jq -n \
  --argjson metrics "$FINAL_METRICS_PAYLOAD" \
  '{ metrics: $metrics }')

# Only send update request if new metrics were identified to add in this run,
# or if it's the first run and we're setting up the initial metrics.
# This prevents unnecessary PUT requests if metrics are already correctly set.
if [[ "$METRICS_ADDED_THIS_RUN" -gt 0 || $(echo "$CURRENT_DATASET_DETAILS" | jq -r '.result.metrics_dict // {} | length') == 0 ]]; then
  echo "Attempting to update dataset with merged metrics payload..."
  UPDATE_DATASET_RESPONSE=$(curl -s -X PUT "http://localhost:8088/api/v1/dataset/$DATASET_ID" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$UPDATE_DATASET_PAYLOAD")

  if echo "$UPDATE_DATASET_RESPONSE" | jq -e '.id' > /dev/null; then
    echo "✅ Dataset updated successfully with new metrics."
  else
    echo "❌ Failed to update dataset with metrics. Response:"
    echo "$UPDATE_DATASET_RESPONSE"
    exit 1
  fi
else
  echo "ℹ️ No new metrics were identified to add to the dataset in this run, and existing metrics are present."
fi
# --- END: Add Metrics to Dataset ---


# First, let's get the dataset columns to identify the datetime column
echo "🔍 Fetching dataset columns..."
COLUMNS_RESPONSE=$(curl -s -X GET "http://localhost:8088/api/v1/dataset/$DATASET_ID" \
  -H "Authorization: Bearer $TOKEN")

# Extract datetime column (common names: timestamp, created_at, updated_at, time, date)
DATETIME_COLUMN=$(echo "$COLUMNS_RESPONSE" | jq -r '
  .result.columns[]? |
  select(.type_generic == 2 or (.column_name // "" | test("timestamp|time|date|created_at|updated_at"; "i"))) |
  .column_name // empty' | head -1)

# Determine chart type and parameters based on datetime column existence
if [[ -z "$DATETIME_COLUMN" || "$DATETIME_COLUMN" == "null" ]]; then
  echo "⚠️ No datetime column found. Using bar chart instead of line chart..."
  VIZ_TYPE="dist_bar"
  # Construct the JSON object for params directly
  CHART_PARAMS_OBJECT='{"metrics": ["average_price"], "groupby": ["bid_ask_spread"], "adhoc_filters": []}'
  CHART_NAME="Bid-Ask Spread vs Average Price (Bar Chart)"
else
  echo "📅 Found datetime column: $DATETIME_COLUMN"
  VIZ_TYPE="line"
  # Construct the JSON object for params, using jq's --argjson for variables
  CHART_PARAMS_OBJECT=$(jq -n \
    --arg dt_col "$DATETIME_COLUMN" \
    '{"metrics": ["average_price"], "groupby": [$dt_col], "adhoc_filters": [], "time_range": "No filter", "granularity_sqla": $dt_col}')
  CHART_NAME="Average Price Over Time"
fi

# --- START: Chart 1 Creation/Lookup ---
echo "📉 Checking for existing chart '$CHART_NAME'..."
CHART_1_FILTER=$(jq -n \
  --arg slice_name "$CHART_NAME" \
  --argjson ds_id "$DATASET_ID" \
  '{ "filters": [
      { "col": "slice_name", "opr": "eq", "value": $slice_name },
      { "col": "datasource_id", "opr": "eq", "value": $ds_id },
      { "col": "datasource_type", "opr": "eq", "value": "table" }
    ]
  }' | jq -Rs '{"q": .}' )

GET_CHART_1_RESPONSE=$(curl -s -G "http://localhost:8088/api/v1/chart/" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "$CHART_1_FILTER")

CHART_ID=$(echo "$GET_CHART_1_RESPONSE" | jq -r '.result[0].id // empty')

if [[ -z "$CHART_ID" || "$CHART_ID" == "null" ]]; then
  echo "➡️ Chart '$CHART_NAME' not found, creating it..."
  CHART_PAYLOAD=$(jq -n \
    --arg slice_name "$CHART_NAME" \
    --arg viz_type "$VIZ_TYPE" \
    --argjson datasource_id "$DATASET_ID" \
    --argjson params_obj "$CHART_PARAMS_OBJECT" \
    '{
      slice_name: $slice_name,
      viz_type: $viz_type,
      datasource_id: $datasource_id,
      datasource_type: "table",
      params: ($params_obj | tostring)
    }')
  CHART_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/chart/ \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CHART_PAYLOAD")
  CHART_ID=$(echo "$CHART_RESPONSE" | jq -r '.id // empty')

  if [[ -z "$CHART_ID" || "$CHART_ID" == "null" ]]; then
    echo "❌ Failed to create chart. Response:"
    echo "$CHART_RESPONSE"
    exit 1
  fi
  echo "📊 Created chart with ID: $CHART_ID"
else
  echo "✅ Chart '$CHART_NAME' already exists with ID: $CHART_ID"
fi
# --- END: Chart 1 Creation/Lookup ---

# --- START: Chart 2 Creation/Lookup ---
SPREAD_CHART_NAME="Bid-Ask Spread Distribution"
echo "📊 Checking for existing chart '$SPREAD_CHART_NAME'..."

CHART_2_FILTER=$(jq -n \
  --arg slice_name "$SPREAD_CHART_NAME" \
  --argjson ds_id "$DATASET_ID" \
  '{ "filters": [
      { "col": "slice_name", "opr": "eq", "value": $slice_name },
      { "col": "datasource_id", "opr": "eq", "value": $ds_id },
      { "col": "datasource_type", "opr": "eq", "value": "table" }
    ]
  }' | jq -Rs '{"q": .}' )

GET_CHART_2_RESPONSE=$(curl -s -G "http://localhost:8088/api/v1/chart/" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "$CHART_2_FILTER")

SPREAD_CHART_ID=$(echo "$GET_CHART_2_RESPONSE" | jq -r '.result[0].id // empty')

if [[ -z "$SPREAD_CHART_ID" || "$SPREAD_CHART_ID" == "null" ]]; then
  echo "➡️ Chart '$SPREAD_CHART_NAME' not found, creating it..."
  SPREAD_CHART_PAYLOAD=$(jq -n \
    --argjson datasource_id "$DATASET_ID" \
    '{
      slice_name: "Bid-Ask Spread Distribution",
      viz_type: "dist_bar",
      datasource_id: $datasource_id,
      datasource_type: "table",
      params: ("{\"metrics\": [\"count\"], \"groupby\": [\"bid_ask_spread\"], \"adhoc_filters\": []}" | fromjson | tostring)
    }')

  SPREAD_CHART_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/chart/ \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SPREAD_CHART_PAYLOAD")
  SPREAD_CHART_ID=$(echo "$SPREAD_CHART_RESPONSE" | jq -r '.id // empty')

  if [[ -z "$SPREAD_CHART_ID" || "$SPREAD_CHART_ID" == "null" ]]; then
    echo "❌ Failed to create spread chart. Response:"
    echo "$SPREAD_CHART_RESPONSE"
    exit 1
  fi
  echo "📊 Created spread chart with ID: $SPREAD_CHART_ID"
else
  echo "✅ Chart '$SPREAD_CHART_NAME' already exists with ID: $SPREAD_CHART_ID"
fi
# --- END: Chart 2 Creation/Lookup ---

# --- START: Dashboard Creation/Lookup ---
DASHBOARD_TITLE="Market Enrichment Dashboard"
echo "🧩 Checking for existing dashboard '$DASHBOARD_TITLE'..."

DASHBOARD_FILTER=$(jq -n \
  --arg title "$DASHBOARD_TITLE" \
  '{ "filters": [ { "col": "dashboard_title", "opr": "eq", "value": $title } ] }' \
  | jq -Rs '{"q": .}')

GET_DASHBOARD_RESPONSE=$(curl -s -G "http://localhost:8088/api/v1/dashboard/" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "$DASHBOARD_FILTER")

DASHBOARD_ID=$(echo "$GET_DASHBOARD_RESPONSE" | jq -r '.result[0].id // empty')

if [[ -z "$DASHBOARD_ID" || "$DASHBOARD_ID" == "null" ]]; then
  echo "➡️ Dashboard '$DASHBOARD_TITLE' not found, creating it..."
  DASHBOARD_PAYLOAD=$(jq -n \
    --arg chart_id "$CHART_ID" \
    --arg spread_chart_id "$SPREAD_CHART_ID" \
    --arg chart_name "$CHART_NAME" \
    --arg title "$DASHBOARD_TITLE" \
    '
    {
      dashboard_title: $title,
      position_json: (
        {
          "CHART-1": {
            children: [],
            id: "CHART-1",
            meta: {
              chartId: ($chart_id | tonumber),
              height: 50,
              sliceName: $chart_name,
              uuid: "chart-1-uuid",
              width: 6
            },
            parents: ["ROOT_ID", "GRID_ID", "ROW_ID"],
            type: "CHART"
          },
          "CHART-2": {
            children: [],
            id: "CHART-2",
            meta: {
              chartId: ($spread_chart_id | tonumber),
              height: 50,
              sliceName: "Bid-Ask Spread Distribution",
              uuid: "chart-2-uuid",
              width: 6
            },
            parents: ["ROOT_ID", "GRID_ID", "ROW_ID"],
            type: "CHART"
          },
          "GRID_ID": {
            children: ["ROW_ID"],
            id: "GRID_ID",
            meta: {},
            type: "GRID",
            parents: ["ROOT_ID"]
          },
          "ROOT_ID": {
            children: ["GRID_ID"],
            id: "ROOT_ID",
            meta: {},
            type: "ROOT",
            parents: []
          },
          "ROW_ID": {
            children: ["CHART-1", "CHART-2"],
            id: "ROW_ID",
            meta: {
              background: "BACKGROUND_TRANSPARENT"
            },
            type: "ROW",
            parents: ["ROOT_ID", "GRID_ID"]
          }
        } | tostring
      ),
      json_metadata: "{}",
      css: ""
    }')

  DASHBOARD_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/dashboard/ \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$DASHBOARD_PAYLOAD")
  DASHBOARD_ID=$(echo "$DASHBOARD_RESPONSE" | jq -r '.id // empty')

  if [[ -z "$DASHBOARD_ID" || "$DASHBOARD_ID" == "null" ]]; then
    echo "❌ Failed to create dashboard. Response:"
    echo "$DASHBOARD_RESPONSE"
    exit 1
  fi
  echo "🎉 Created dashboard with ID: $DASHBOARD_ID"
else
  echo "✅ Dashboard '$DASHBOARD_TITLE' already exists with ID: $DASHBOARD_ID"
fi
# --- END: Dashboard Creation/Lookup ---


# Attach charts to dashboard (this is an idempotent operation - setting dashboards array)
echo "🔗 Attaching charts to dashboard..."
PATCH_RESPONSE1=$(curl -s -X PUT http://localhost:8088/api/v1/chart/$CHART_ID \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "dashboards": ['"$DASHBOARD_ID"']
  }')

PATCH_RESPONSE2=$(curl -s -X PUT http://localhost:8088/api/v1/chart/$SPREAD_CHART_ID \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "dashboards": ['"$DASHBOARD_ID"']
  }')

if echo "$PATCH_RESPONSE1" | jq -e '.id' > /dev/null && echo "$PATCH_RESPONSE2" | jq -e '.id' > /dev/null; then
  echo "✅ Charts successfully attached to dashboard!"
else
  echo "❌ Failed to attach charts. Responses:"
  echo "Chart 1: $PATCH_RESPONSE1"
  echo "Chart 2: $PATCH_RESPONSE2"
fi

echo ""
echo "🎉 SUCCESS! Setup complete!"
echo "📌 Dashboard created with ID: $DASHBOARD_ID"
echo "📊 Main chart created with ID: $CHART_ID"
echo "📊 Spread chart created with ID: $SPREAD_CHART_ID"
echo "📈 Dataset created with ID: $DATASET_ID"
echo "🗃️ Database ID: $DB_ID"
echo ""
echo "🌐 Visit your dashboard:"
echo "   http://localhost:8088/superset/dashboard/$DASHBOARD_ID/"
