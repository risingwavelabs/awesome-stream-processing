#!/bin/bash

set -e

echo "⏳ Waiting for Superset API..."
until curl -s http://localhost:8088/api/v1/ping > /dev/null; do
  sleep 5
done
echo "✅ Superset API is up!"

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

echo "🔍 Checking for existing databases..."
DB_RESPONSE=$(curl -s -X GET http://localhost:8088/api/v1/database/ \
  -H "Authorization: Bearer $TOKEN")

DB_COUNT=$(echo "$DB_RESPONSE" | jq '.count')
if [[ "$DB_COUNT" == "0" ]]; then
  echo "🗄️ No databases found. Creating PostgreSQL database connection..."
  CREATE_DB_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/database/ \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "database_name": "postgres_db",
      "sqlalchemy_uri": "postgresql://pguser:pgpass@postgres:5432/pgdb"
    }')
  DB_ID=$(echo "$CREATE_DB_RESPONSE" | jq -r '.id // empty')
  if [[ -z "$DB_ID" ]]; then
    echo "❌ Failed to create database connection."
    exit 1
  fi
else
  DB_ID=$(echo "$DB_RESPONSE" | jq -r '.result[0].id')
fi
echo "🗃️ Using database ID: $DB_ID"

echo "📊 Creating dataset for avg_price_sink with timestamp..."
DATASET_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/dataset/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "database": '"$DB_ID"',
    "schema": "public",
    "table_name": "avg_price_sink",
    "columns": [
      {
        "column_name": "timestamp",
        "is_dttm": true
      }
    ]
  }')

DATASET_ID=$(echo "$DATASET_RESPONSE" | jq -r '.id // empty')
if [[ -z "$DATASET_ID" ]]; then
  echo "❌ Failed to create dataset."
  echo "Response: $DATASET_RESPONSE"
  exit 1
fi
echo "📈 Created dataset with ID: $DATASET_ID"

echo "📉 Creating line chart..."
CHART_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/chart/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "slice_name": "Bid-Ask Spread vs Average Price",
    "viz_type": "line",
    "datasource_id": '"$DATASET_ID"',
    "datasource_type": "table",
    "params": "{\\"metrics\\": [\\"average_price\\"], \\"groupby\\": [\\"bid_ask_spread\\"], \\"granularity_sqla\\": \\"timestamp\\", \\"time_range\\": \\"No filter\\"}"
  }')

CHART_ID=$(echo "$CHART_RESPONSE" | jq -r '.id // empty')
if [[ -z "$CHART_ID" ]]; then
  echo "❌ Failed to create chart."
  echo "Response: $CHART_RESPONSE"
  exit 1
fi
echo "📊 Created chart with ID: $CHART_ID"

echo "🧩 Creating dashboard with chart..."
DASHBOARD_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/dashboard/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard_title": "Market Enrichment Dashboard",
    "position_json": "{}",
    "json_metadata": "{}"
  }')

DASHBOARD_ID=$(echo "$DASHBOARD_RESPONSE" | jq -r '.id // empty')
if [[ -z "$DASHBOARD_ID" ]]; then
  echo "❌ Failed to create dashboard."
  echo "Response: $DASHBOARD_RESPONSE"
  exit 1
fi

echo ""
echo "🎉 SUCCESS! Superset setup complete!"
echo "📌 Dashboard created with ID: $DASHBOARD_ID"
echo "📊 Chart created with ID: $CHART_ID"
echo "📈 Dataset created with ID: $DATASET_ID"
echo ""
echo "🌐 Access your dashboard at:"
echo "   http://localhost:8088/superset/dashboard/$DASHBOARD_ID/"
