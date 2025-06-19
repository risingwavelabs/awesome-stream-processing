#!/bin/bash

# Wait for Superset to be ready
echo "⏳ Waiting for Superset API..."
until curl -s http://localhost:8088/api/v1/ping > /dev/null; do
  sleep 5
done
echo "✅ Superset API is up!"

# Log in to Superset and get the access token
echo "🔐 Logging in to Superset..."
TOKEN=$(curl -s -X POST http://localhost:8088/api/v1/security/login \
  -H 'Content-Type: application/json' \
  -d '{"username": "admin", "password": "admin", "provider": "db"}' | jq -r '.access_token')

if [[ "$TOKEN" == "null" ]]; then
  echo "❌ Failed to authenticate with Superset."
  exit 1
fi

echo "🔑 Got access token."

# Get database ID
DB_ID=$(curl -s -X GET http://localhost:8088/api/v1/database/ \
  -H "Authorization: Bearer $TOKEN" | jq '.result[0].id')

echo "🗃️ Using database ID: $DB_ID"

# Create dataset from avg_price_sink table
echo "📊 Creating dataset for avg_price_sink..."
DATASET_ID=$(curl -s -X POST http://localhost:8088/api/v1/dataset/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "database": '"$DB_ID"',
    "schema": "public",
    "table_name": "avg_price_sink"
  }' | jq '.id')

echo "📈 Created dataset with ID: $DATASET_ID"

# Create chart: Bid-Ask Spread vs Average Price
echo "📉 Creating line chart: Bid-Ask Spread vs Average Price..."
CHART_ID=$(curl -s -X POST http://localhost:8088/api/v1/chart/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "slice_name": "Bid-Ask Spread vs Average Price",
    "viz_type": "line",
    "datasource_id": '"$DATASET_ID"',
    "datasource_type": "table",
    "params": "{\"metrics\": [\"average_price\"], \"x_axis\": \"bid_ask_spread\", \"row_limit\": 1000, \"time_range\": \"No filter\", \"show_legend\": true, \"show_markers\": true, \"rich_tooltip\": true, \"y_axis_format\": \".2f\", \"x_axis_format\": \".2f\"}"
  }' | jq '.id')

echo "📊 Created chart with ID: $CHART_ID"

# Create dashboard with chart auto-positioned
echo "🧩 Creating dashboard with auto-layout..."
DASHBOARD_PAYLOAD=$(jq -n \
  --arg chart_id "$CHART_ID" \
  --arg title "Market Enrichment Dashboard" \
  --argjson chart_id_int "$CHART_ID" \
  '{
    dashboard_title: $title,
    positions: {
      "CHART-1": {
        children: [],
        id: "CHART-1",
        meta: {
          chartId: ($chart_id_int | tonumber),
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
    },
    json_metadata: "{}",
    css: ""
  }')

DASHBOARD_ID=$(curl -s -X POST http://localhost:8088/api/v1/dashboard/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$DASHBOARD_PAYLOAD" | jq '.id')

echo "📌 Dashboard with chart created. ID: $DASHBOARD_ID"
echo "✅ Superset setup complete! Dashboard and chart are ready."
