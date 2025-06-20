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

# Create dataset from avg_price_sink
echo "📊 Creating dataset for avg_price_sink..."
DATASET_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/dataset/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "database": '"$DB_ID"',
    "schema": "public",
    "table_name": "avg_price_sink"
  }')
DATASET_ID=$(echo "$DATASET_RESPONSE" | jq -r '.id // empty')

if [[ -z "$DATASET_ID" || "$DATASET_ID" == "null" ]]; then
  echo "❌ Failed to create dataset. Response:"
  echo "$DATASET_RESPONSE"
  exit 1
fi

echo "📈 Created dataset with ID: $DATASET_ID"


# --- START: Add Metrics to Dataset ---
echo "➕ Checking and adding necessary metrics to dataset..."

# Get current dataset details to check existing metrics
CURRENT_DATASET_DETAILS=$(curl -s -X GET "http://localhost:8088/api/v1/dataset/$DATASET_ID" \
  -H "Authorization: Bearer $TOKEN")

# Initialize an array for metrics to update
METRICS_TO_ADD='[]'

# Check for 'average_price' metric
if ! echo "$CURRENT_DATASET_DETAILS" | jq -e '.result.metrics_dict.average_price' > /dev/null; then
  echo "    - 'average_price' metric not found, adding it."
  METRICS_TO_ADD=$(echo "$METRICS_TO_ADD" | jq '. + [{"metric_name": "average_price", "expression": "AVG(average_price)", "verbose_name": "Average Price"}]')
else
  echo "    - 'average_price' metric already exists."
fi

# Check for 'bid_ask_spread' metric (though it's usually used as a dimension, sometimes needed as metric for specific charts)
# For simplicity, let's also add it as a "SUM" metric, although it's primarily a dimension.
# If bid_ask_spread is truly a dimension/groupby field, this specific metric might not be strictly necessary,
# but it won't hurt to have it for flexibility.
if ! echo "$CURRENT_DATASET_DETAILS" | jq -e '.result.metrics_dict.bid_ask_spread' > /dev/null; then
  echo "    - 'bid_ask_spread' metric not found, adding it (as SUM for flexibility)."
  METRICS_TO_ADD=$(echo "$METRICS_TO_ADD" | jq '. + [{"metric_name": "bid_ask_spread", "expression": "SUM(bid_ask_spread)", "verbose_name": "Bid Ask Spread Sum"}]')
else
  echo "    - 'bid_ask_spread' metric already exists."
fi


# Check for 'count' metric (COUNT(*))
if ! echo "$CURRENT_DATASET_DETAILS" | jq -e '.result.metrics_dict.count' > /dev/null; then
  echo "    - 'count' metric not found, adding it."
  METRICS_TO_ADD=$(echo "$METRICS_TO_ADD" | jq '. + [{"metric_name": "count", "expression": "COUNT(*)", "verbose_name": "Count"}]')
else
  echo "    - 'count' metric already exists."
fi

# Prepare the payload to update the dataset with new metrics
# We need to get existing metrics and merge with new ones
EXISTING_METRICS=$(echo "$CURRENT_DATASET_DETAILS" | jq -r '.result.metrics_dict | to_entries | map(.value)')

# Merge existing metrics with new ones, ensuring no duplicates on metric_name
MERGED_METRICS=$(echo "$EXISTING_METRICS $METRICS_TO_ADD" | jq -s 'flatten | unique_by(.metric_name)')

UPDATE_DATASET_PAYLOAD=$(jq -n \
  --argjson metrics "$MERGED_METRICS" \
  '{ metrics: $metrics }')

# Only send update request if there are metrics to add or update
if [[ $(echo "$METRICS_TO_ADD" | jq 'length') -gt 0 ]]; then
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
  echo "ℹ️ No new metrics to add or update for the dataset."
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

# Create chart with proper datetime configuration
# Construct the entire chart payload using jq to ensure correct stringification of 'params'
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

echo "📉 Creating chart: $CHART_NAME..."
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

# Create a second chart for bid-ask spread analysis
# Construct the entire spread chart payload using jq
SPREAD_CHART_PAYLOAD=$(jq -n \
  --argjson datasource_id "$DATASET_ID" \
  '{
    slice_name: "Bid-Ask Spread Distribution",
    viz_type: "dist_bar",
    datasource_id: $datasource_id,
    datasource_type: "table",
    # Ensure params are stringified JSON. Here, we directly use fromjson to parse the string
    # and then tostring to turn it back into a JSON string for the 'params' field.
    params: ("{\"metrics\": [\"count\"], \"groupby\": [\"bid_ask_spread\"], \"adhoc_filters\": []}" | fromjson | tostring)
  }')

echo "📊 Creating additional chart for bid-ask spread analysis..."
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

# Create dashboard with both charts
echo "🧩 Creating dashboard with auto-layout..."
DASHBOARD_PAYLOAD=$(jq -n \
  --arg chart_id "$CHART_ID" \
  --arg spread_chart_id "$SPREAD_CHART_ID" \
  --arg chart_name "$CHART_NAME" \
  --arg title "Market Enrichment Dashboard" \
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

# Attach charts to dashboard
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
