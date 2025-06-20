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
  DB_ID=$(echo "$DB_RESPONSE" | jq -r '.result[0].id')
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
CHART_ID=$(echo "$CHART_RESPONSE" | jq -r '.id // empty')

echo "📊 Created chart with ID: $CHART_ID"

# Create dashboard
echo "🧩 Creating dashboard with auto-layout..."
DASHBOARD_PAYLOAD=$(jq -n \
  --arg chart_id "$CHART_ID" \
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

# Attach chart to dashboard
echo "🔗 Attaching chart to dashboard..."
PATCH_RESPONSE=$(curl -s -X PUT http://localhost:8088/api/v1/chart/$CHART_ID \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "dashboards": ['"$DASHBOARD_ID"']
  }')

if echo "$PATCH_RESPONSE" | jq -e '.id' > /dev/null; then
  echo "✅ Chart successfully attached to dashboard!"
else
  echo "❌ Failed to attach chart. Response:"
  echo "$PATCH_RESPONSE"
fi


echo ""
echo "🎉 SUCCESS! Setup complete!"
echo "📌 Dashboard created with ID: $DASHBOARD_ID"
echo "📊 Chart created with ID: $CHART_ID"
echo "📈 Dataset created with ID: $DATASET_ID"
echo "🗃️ Database ID: $DB_ID"
echo ""
echo "🌐 Visit your dashboard:"
echo "   http://localhost:8088/superset/dashboard/$DASHBOARD_ID/"
