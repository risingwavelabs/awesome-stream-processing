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

# Get database ID
echo "🗃️ Getting database ID..."
DB_RESPONSE=$(curl -s -X GET http://localhost:8088/api/v1/database/ \
  -H "Authorization: Bearer $TOKEN")

DB_ID=$(echo "$DB_RESPONSE" | jq -r '.result[0].id // empty')

if [[ -z "$DB_ID" ]]; then
  echo "❌ Failed to get database ID."
  echo "Database response: $DB_RESPONSE"
  exit 1
fi

echo "🗃️ Using database ID: $DB_ID"

# Create dataset from avg_price_sink table
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

if [[ -z "$DATASET_ID" ]]; then
  echo "❌ Failed to create dataset."
  echo "Dataset response: $DATASET_RESPONSE"
  exit 1
fi

echo "📈 Created dataset with ID: $DATASET_ID"

# Create chart: Bid-Ask Spread vs Average Price
echo "📉 Creating line chart: Bid-Ask Spread vs Average Price..."
CHART_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/chart/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "slice_name": "Bid-Ask Spread vs Average Price",
    "viz_type": "line",
    "datasource_id": '"$DATASET_ID"',
    "datasource_type": "table",
    "params": "{\"metrics\": [\"average_price\"], \"groupby\": [\"bid_ask_spread\"]}"
  }')

echo "Chart creation response:"
echo "$CHART_RESPONSE"

CHART_ID=$(echo "$CHART_RESPONSE" | jq -r '.id // empty')

if [[ -z "$CHART_ID" ]]; then
  echo "❌ Failed to create chart. Response above shows the error."
  exit 1
fi

echo "📊 Created chart with ID: $CHART_ID"

# Create dashboard with chart auto-positioned
echo "🧩 Creating dashboard with auto-layout..."

# Validate CHART_ID is a number before using it
if ! [[ "$CHART_ID" =~ ^[0-9]+$ ]]; then
  echo "❌ Chart ID is not a valid number: $CHART_ID"
  exit 1
fi

DASHBOARD_PAYLOAD=$(jq -n \
  --arg chart_id "$CHART_ID" \
  --arg title "Market Enrichment Dashboard" \
  --argjson chart_id_int "$CHART_ID" \
  '{
    dashboard_title: $title,
    position_json: ({
      "CHART-1": {
        children: [],
        id: "CHART-1",
        meta: {
          chartId: $chart_id_int,
          height: 50,
          sliceName: "Bid-Ask Spread vs Average Price",
          uuid: "chart-1-uuid",
          width: 12
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
        children: ["CHART-1"],
        id: "ROW_ID",
        meta: {
          background: "BACKGROUND_TRANSPARENT"
        },
        type: "ROW",
        parents: ["ROOT_ID", "GRID_ID"]
      }
    } | tostring),
    json_metadata: "{}",
    css: ""
  }')

DASHBOARD_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/dashboard/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$DASHBOARD_PAYLOAD")

DASHBOARD_ID=$(echo "$DASHBOARD_RESPONSE" | jq -r '.id // empty')

if [[ -z "$DASHBOARD_ID" ]]; then
  echo "❌ Failed to create dashboard."
  echo "Dashboard response: $DASHBOARD_RESPONSE"
  exit 1
fi

echo "📌 Dashboard with chart created. ID: $DASHBOARD_ID"
echo "✅ Superset setup complete! Dashboard and chart are ready."
echo "🌐 Access your dashboard at: http://localhost:8088/superset/dashboard/$DASHBOARD_ID/"