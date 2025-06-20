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

# Check if database exists first
echo "🔍 Checking for existing databases..."
DB_RESPONSE=$(curl -s -X GET http://localhost:8088/api/v1/database/ \
  -H "Authorization: Bearer $TOKEN")

DB_COUNT=$(echo "$DB_RESPONSE" | jq '.count')
echo "Found $DB_COUNT existing databases."

if [[ "$DB_COUNT" == "0" ]]; then
  echo "🗄️ No databases found. Creating PostgreSQL database connection..."
  
  # Create database connection (adjust these settings for your database)
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
    echo "Response: $CREATE_DB_RESPONSE"
    echo ""
    echo "📝 Please check your database connection details:"
    echo "   - Host: postgres"
    echo "   - Port: 5432" 
    echo "   - Database: pgdb"
    echo "   - Username: pguser"
    echo "   - Password: pgpass"
    echo ""
    echo "💡 You may need to:"
    echo "   1. Start your PostgreSQL database"
    echo "   2. Update the connection string in this script"
    echo "   3. Or create the database connection manually via Superset UI"
    exit 1
  fi
  
  echo "✅ Created database connection with ID: $DB_ID"
else
  # Use existing database
  DB_ID=$(echo "$DB_RESPONSE" | jq -r '.result[0].id')
  DB_NAME=$(echo "$DB_RESPONSE" | jq -r '.result[0].database_name')
  echo "🗃️ Using existing database: $DB_NAME (ID: $DB_ID)"
fi

# Test database connection
echo "🔌 Testing database connection..."
TEST_RESPONSE=$(curl -s -X POST http://localhost:8088/api/v1/database/test_connection \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "database_name": "test",
    "sqlalchemy_uri": "postgresql://pguser:pgpass@postgres:5432/pgdb"
  }')

# Handle potential JSON parsing issues
if echo "$TEST_RESPONSE" | jq empty 2>/dev/null; then
  CONNECTION_OK=$(echo "$TEST_RESPONSE" | jq -r '.message // empty')
  if [[ "$CONNECTION_OK" != "OK" ]]; then
    echo "⚠️ Database connection test failed: $TEST_RESPONSE"
    echo "Continuing anyway - the connection might still work..."
  else
    echo "✅ Database connection test passed!"
  fi
else
  echo "⚠️ Database connection test returned invalid JSON: $TEST_RESPONSE"
  echo "Continuing anyway - the connection might still work..."
fi

# Check if table exists
echo "📋 Checking if avg_price_sink table exists..."
TABLE_CHECK=$(curl -s -X GET "http://localhost:8088/api/v1/database/$DB_ID/table/avg_price_sink/public/" \
  -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo '{"error": "not found"}')

if echo "$TABLE_CHECK" | jq -e '.error' > /dev/null; then
  echo "⚠️ Table 'avg_price_sink' not found. You may need to:"
  echo "   1. Create the table in your database"
  echo "   2. Insert some sample data"
  echo "   3. Or change the table name in this script"
  echo ""
  echo "🔄 Continuing with script - you can create the dataset manually later..."
else
  echo "✅ Table 'avg_price_sink' found!"
fi

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
  echo ""
  echo "🛠️ This might be because:"
  echo "   1. The table doesn't exist in the database"
  echo "   2. The database connection isn't working"
  echo "   3. Permission issues"
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

CHART_ID=$(echo "$CHART_RESPONSE" | jq -r '.id // empty')

if [[ -z "$CHART_ID" ]]; then
  echo "❌ Failed to create chart."
  echo "Chart response: $CHART_RESPONSE"
  exit 1
fi

echo "📊 Created chart with ID: $CHART_ID"

# Create dashboard with chart auto-positioned
echo "🧩 Creating dashboard with auto-layout..."

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

echo ""
echo "🎉 SUCCESS! Setup complete!"
echo "📌 Dashboard created with ID: $DASHBOARD_ID"
echo "📊 Chart created with ID: $CHART_ID"
echo "📈 Dataset created with ID: $DATASET_ID"
echo "🗃️ Database ID: $DB_ID"
echo ""
echo "🌐 Access your dashboard at:"
echo "   http://localhost:8088/superset/dashboard/$DASHBOARD_ID/"
echo ""
echo "🔍 Other useful URLs:"
echo "   Superset Home: http://localhost:8088/"
echo "   Charts List: http://localhost:8088/chart/list/"
echo "   Dashboards List: http://localhost:8088/dashboard/list/"