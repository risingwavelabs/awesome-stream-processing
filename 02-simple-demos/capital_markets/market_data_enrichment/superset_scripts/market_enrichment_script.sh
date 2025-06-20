#!/bin/bash

set -e

# --- Configuration ---
SUPERSET_URL="${SUPERSET_URL:-http://localhost:8088}"
SUPERSET_USERNAME="${SUPERSET_USERNAME:-admin}"
SUPERSET_PASSWORD="${SUPERSET_PASSWORD:-admin}"

DB_NAME="Postgres_Market_Data"
SQLALCHEMY_URI="postgresql://pguser:pgpass@postgres:5432/pgdb"

DATASET_TABLE_NAME="avg_price_bid_ask_spread" # Your materialized view name
DATASET_NAME="Avg Price Bid Ask Spread Data" # Friendly name for Superset Dataset

CHART_1_NAME="Average Price and Bid-Ask Spread Over Time" # Line chart
CHART_2_NAME="Bid-Ask Spread Distribution" # Bar chart

DASHBOARD_TITLE="Market Data Analysis Dashboard"

# --- Pre-requisite Checks ---
if ! command -v curl &> /dev/null; then
    echo "Error: 'curl' is not installed. Please install it to run this script."
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed. Please install it to run this script (e.g., sudo apt-get install jq)."
    exit 1
fi

# --- 1. Wait for Superset to be ready ---
echo "⏳ Waiting for Superset API to be responsive at $SUPERSET_URL..."
until curl -s "$SUPERSET_URL/api/v1/ping" &> /dev/null; do
  printf "."
  sleep 5
done
echo -e "\n✅ Superset API is up!"

# --- 2. Log in to Superset and get the access token and CSRF token ---
echo "🔐 Logging in to Superset as $SUPERSET_USERNAME..."
LOGIN_RESPONSE=$(curl -s -X POST "$SUPERSET_URL/api/v1/security/login" \
  -H 'Content-Type: application/json' \
  -d '{
    "username": "'"$SUPERSET_USERNAME"'",
    "password": "'"$SUPERSET_PASSWORD"'",
    "provider": "db"
  }')

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token // empty')

if [[ -z "$TOKEN" ]]; then
  echo "❌ Failed to authenticate with Superset."
  echo "Login response: $LOGIN_RESPONSE"
  exit 1
fi
echo "🔑 Successfully logged in and got access token."

# Get CSRF token for subsequent POST/PUT requests
echo "🔑 Getting CSRF token..."
CSRF_RESPONSE=$(curl -s "$SUPERSET_URL/api/v1/security/csrf_token/" \
  -H "Authorization: Bearer $TOKEN")
CSRF_TOKEN=$(echo "$CSRF_RESPONSE" | jq -r '.result // empty')

if [[ -z "$CSRF_TOKEN" ]]; then
  echo "❌ Failed to get CSRF token."
  echo "CSRF response: $CSRF_RESPONSE"
  exit 1
fi
echo "✅ Got CSRF token."


# --- 3. Add/Get Database Connection ---
echo "--- Managing Database Connection ---"
DB_ID=""
DATABASES_RESPONSE=$(curl -s -X GET "$SUPERSET_URL/api/v1/database/" \
  -H "Authorization: Bearer $TOKEN")

# Check if the database already exists
DB_ID=$(echo "$DATABASES_RESPONSE" | jq -r '.result[] | select(.database_name == "'"$DB_NAME"'") | .id // empty')

if [[ -z "$DB_ID" ]]; then
  echo "🗄️ Database '$DB_NAME' not found. Creating it..."
  CREATE_DB_RESPONSE=$(curl -s -X POST "$SUPERSET_URL/api/v1/database/" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-CSRFToken: $CSRF_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "database_name": "'"$DB_NAME"'",
      "sqlalchemy_uri": "'"$SQLALCHEMY_URI"'",
      "expose_in_sqllab": true,
      "allow_run_as_db_user": false,
      "allow_ctas": false,
      "allow_cvas": false,
      "extra": "{\"engine_params\": {\"connect_args\": {\"options\": \"-csearch_path=public\"}}}"
    }')
  DB_ID=$(echo "$CREATE_DB_RESPONSE" | jq -r '.id // empty')
  if [[ -z "$DB_ID" ]]; then
    echo "❌ Failed to create database '$DB_NAME'. Response: $CREATE_DB_RESPONSE"
    exit 1
  fi
  echo "✅ Database '$DB_NAME' created with ID: $DB_ID"
else
  echo "✅ Database '$DB_NAME' already exists with ID: $DB_ID"
fi

# --- 4. Add/Get Dataset ---
echo "--- Managing Dataset '$DATASET_NAME' ---"
DATASET_ID=""
# Filter query for dataset lookup
DATASET_FILTER_Q=$(jq -n \
  --arg table_name "$DATASET_TABLE_NAME" \
  --argjson db_id "$DB_ID" \
  '{ "filters": [
      { "col": "table_name", "opr": "eq", "value": $table_name },
      { "col": "database_id", "opr": "eq", "value": ($db_id | tonumber) }
    ]
  }' | jq -Rs '{"q": .}' ) # Wrap in {"q": ...} and stringify for the query parameter

GET_DATASET_RESPONSE=$(curl -s -G "$SUPERSET_URL/api/v1/dataset/" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "$DATASET_FILTER_Q")

DATASET_ID=$(echo "$GET_DATASET_RESPONSE" | jq -r '.result[0].id // empty')

if [[ -z "$DATASET_ID" ]]; then
  echo "➡️ Dataset '$DATASET_NAME' not found, creating it..."
  CREATE_DATASET_PAYLOAD=$(jq -n \
    --argjson db_id "$DB_ID" \
    --arg table_name "$DATASET_TABLE_NAME" \
    '{
      database_id: ($db_id | tonumber),
      table_name: $table_name,
      schema: "public",
      explore: false,
      owners: [1] # Assuming admin user ID is 1
    }')
  CREATE_DATASET_RESPONSE=$(curl -s -X POST "$SUPERSET_URL/api/v1/dataset/" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-CSRFToken: $CSRF_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CREATE_DATASET_PAYLOAD")
  DATASET_ID=$(echo "$CREATE_DATASET_RESPONSE" | jq -r '.id // empty')
  if [[ -z "$DATASET_ID" ]]; then
    echo "❌ Failed to create dataset '$DATASET_NAME'. Response: $CREATE_DATASET_RESPONSE"
    exit 1
  fi
  echo "✅ Dataset '$DATASET_NAME' created with ID: $DATASET_ID"
else
  echo "✅ Dataset '$DATASET_NAME' already exists with ID: $DATASET_ID"
fi

# --- 5. Add Metrics to Dataset ---
echo "--- Checking and adding necessary metrics to dataset '$DATASET_NAME' ---"

CURRENT_DATASET_DETAILS=$(curl -s -X GET "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" \
  -H "Authorization: Bearer $TOKEN")

# Extract existing column names
EXISTING_COLUMN_NAMES=$(echo "$CURRENT_DATASET_DETAILS" | jq -r '.result.columns[]?.column_name // empty' | tr '\n' ' ')

# Initialize the array that will hold the *final* set of metrics
FINAL_METRICS_PAYLOAD=$(echo "$CURRENT_DATASET_DETAILS" | jq -r '(.result.metrics_dict // {}) | to_entries | map(.value)')
METRICS_ADDED_THIS_RUN=0

# Helper function to check if a column exists
column_exists() {
  local col_name="$1"
  [[ " $EXISTING_COLUMN_NAMES " =~ " $col_name " ]]
}

# Helper function to check if a metric exists in the current payload
metric_exists_in_payload() {
  local metric_name_to_check="$1"
  echo "$FINAL_METRICS_PAYLOAD" | jq -e ".[] | select(.metric_name == \"$metric_name_to_check\")" &> /dev/null
}

# Define desired metrics and add if missing
declare -A DESIRED_METRICS
DESIRED_METRICS["average_price"]="AVG(average_price)"
DESIRED_METRICS["bid_ask_spread"]="AVG(bid_ask_spread)" # Changed to AVG for consistency in comparison
DESIRED_METRICS["count"]="COUNT(*)" # Default 'count' metric

for metric_name in "${!DESIRED_METRICS[@]}"; do
  metric_expression="${DESIRED_METRICS[$metric_name]}"
  
  if ! column_exists "$metric_name" && [[ "$metric_name" != "count" ]]; then
    echo "    ⚠️ Warning: Column '$metric_name' not found in dataset. Skipping '$metric_name' metric creation."
    continue
  fi

  if ! metric_exists_in_payload "$metric_name"; then
    echo "    - Metric '$metric_name' not found, adding it."
    # Use a case statement or if-elif for verbose_name if needed, otherwise default to metric_name
    local_verbose_name=""
    if [[ "$metric_name" == "average_price" ]]; then
        local_verbose_name="Average Price"
    elif [[ "$metric_name" == "bid_ask_spread" ]]; then
        local_verbose_name="Bid Ask Spread"
    elif [[ "$metric_name" == "count" ]]; then
        local_verbose_name="Count"
    fi

    FINAL_METRICS_PAYLOAD=$(echo "$FINAL_METRICS_PAYLOAD" | jq \
      --arg name "$metric_name" \
      --arg expr "$metric_expression" \
      --arg vname "$local_verbose_name" \
      '. + [{"metric_name": $name, "expression": $expr, "verbose_name": $vname}]')
    METRICS_ADDED_THIS_RUN=$((METRICS_ADDED_THIS_RUN + 1))
  else
    echo "    - Metric '$metric_name' already exists."
  fi
done

# Only send update request if new metrics were added or if it's the initial setup
if [[ "$METRICS_ADDED_THIS_RUN" -gt 0 || $(echo "$CURRENT_DATASET_DETAILS" | jq -r '.result.metrics_dict // {} | length') == 0 ]]; then
  echo "Attempting to update dataset with merged metrics payload..."
  UPDATE_DATASET_PAYLOAD=$(jq -n \
    --argjson metrics "$FINAL_METRICS_PAYLOAD" \
    '{ metrics: $metrics }')

  UPDATE_DATASET_RESPONSE=$(curl -s -X PUT "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-CSRFToken: $CSRF_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$UPDATE_DATASET_PAYLOAD")

  if echo "$UPDATE_DATASET_RESPONSE" | jq -e '.id' &> /dev/null; then
    echo "✅ Dataset updated successfully with new metrics."
  else
    echo "❌ Failed to update dataset with metrics. Response: $UPDATE_DATASET_RESPONSE"
    exit 1
  fi
else
  echo "ℹ️ No new metrics were identified to add to the dataset, or existing metrics are present."
fi


# --- 6. Prepare for Chart Creation: Determine Datetime Column ---
echo "--- Preparing Charts ---"
DATETIME_COLUMN=""
COLUMNS_RESPONSE=$(curl -s -X GET "$SUPERSET_URL/api/v1/dataset/$DATASET_ID" \
  -H "Authorization: Bearer $TOKEN")

DATETIME_COLUMN=$(echo "$COLUMNS_RESPONSE" | jq -r '
  .result.columns[]? |
  select(.type_generic == 2 or (.column_name // "" | test("timestamp|time|date|created_at|updated_at"; "i"))) |
  .column_name // empty' | head -1)

if [[ -z "$DATETIME_COLUMN" || "$DATETIME_COLUMN" == "null" ]]; then
  echo "⚠️ No suitable datetime column found. Line chart might not function correctly without it."
  echo "   Using 'timestamp' as a fallback, ensure it's a valid datetime type in your database."
  DATETIME_COLUMN="timestamp" # Fallback
else
  echo "✅ Found datetime column: '$DATETIME_COLUMN'"
fi


# --- 7. Add/Get Chart 1 (Line Chart: Average Price and Bid-Ask Spread) ---
echo "--- Managing Chart 1: '$CHART_1_NAME' ---"
CHART_1_ID=""
CHART_1_FILTER_Q=$(jq -n \
  --arg slice_name "$CHART_1_NAME" \
  --argjson ds_id "$DATASET_ID" \
  '{ "filters": [
      { "col": "slice_name", "opr": "eq", "value": $slice_name },
      { "col": "datasource_id", "opr": "eq", "value": $ds_id },
      { "col": "datasource_type", "opr": "eq", "value": "table" }
    ]
  }' | jq -Rs '{"q": .}')

GET_CHART_1_RESPONSE=$(curl -s -G "$SUPERSET_URL/api/v1/chart/" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "$CHART_1_FILTER_Q")

CHART_1_ID=$(echo "$GET_CHART_1_RESPONSE" | jq -r '.result[0].id // empty')

if [[ -z "$CHART_1_ID" ]]; then
  echo "➡️ Chart '$CHART_1_NAME' not found, creating it..."
  # Construct the form_data JSON for the line chart
  CHART_1_FORM_DATA=$(jq -n \
    --arg dt_col "$DATETIME_COLUMN" \
    '{
      "viz_type": "line",
      "datasource": "'"$DATASET_ID"'__table", # Superset expects this format
      "granularity_sqla": $dt_col,
      "time_range": "No filter",
      "metrics": ["average_price", "bid_ask_spread"], # Use the metric names defined above
      "groupby": ["asset_id"], # Group by asset_id to show separate lines for each asset
      "line_interpolation": "linear",
      "y_axis_format": ".2f",
      "x_axis_label": "Timestamp",
      "y_axis_label": "Value",
      "show_brush": "on",
      "show_legend": true,
      "zoomable": true,
      "stack": false,
      "row_limit": 10000,
      "url_params": {},
      "extra_form_data": {}
    }' | tostring) # Must be a string for 'params' field

  CHART_1_PAYLOAD=$(jq -n \
    --arg slice_name "$CHART_1_NAME" \
    --arg viz_type "line" \
    --argjson datasource_id "$DATASET_ID" \
    --arg params_str "$CHART_1_FORM_DATA" \
    '{
      slice_name: $slice_name,
      viz_type: $viz_type,
      datasource_id: $datasource_id,
      datasource_type: "table",
      params: $params_str,
      owners: [1]
    }')
  
  CREATE_CHART_1_RESPONSE=$(curl -s -X POST "$SUPERSET_URL/api/v1/chart/" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-CSRFToken: $CSRF_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CHART_1_PAYLOAD")
  
  CHART_1_ID=$(echo "$CREATE_CHART_1_RESPONSE" | jq -r '.id // empty')
  if [[ -z "$CHART_1_ID" ]]; then
    echo "❌ Failed to create chart '$CHART_1_NAME'. Response: $CREATE_CHART_1_RESPONSE"
    exit 1
  fi
  echo "✅ Chart '$CHART_1_NAME' created with ID: $CHART_1_ID"
else
  echo "✅ Chart '$CHART_1_NAME' already exists with ID: $CHART_1_ID"
fi


# --- 8. Add/Get Chart 2 (Bar Chart: Bid-Ask Spread Distribution) ---
echo "--- Managing Chart 2: '$CHART_2_NAME' ---"
CHART_2_ID=""
CHART_2_FILTER_Q=$(jq -n \
  --arg slice_name "$CHART_2_NAME" \
  --argjson ds_id "$DATASET_ID" \
  '{ "filters": [
      { "col": "slice_name", "opr": "eq", "value": $slice_name },
      { "col": "datasource_id", "opr": "eq", "value": $ds_id },
      { "col": "datasource_type", "opr": "eq", "value": "table" }
    ]
  }' | jq -Rs '{"q": .}')

GET_CHART_2_RESPONSE=$(curl -s -G "$SUPERSET_URL/api/v1/chart/" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "$CHART_2_FILTER_Q")

CHART_2_ID=$(echo "$GET_CHART_2_RESPONSE" | jq -r '.result[0].id // empty')

if [[ -z "$CHART_2_ID" ]]; then
  echo "➡️ Chart '$CHART_2_NAME' not found, creating it..."
  # Construct the form_data JSON for the bar chart
  CHART_2_FORM_DATA=$(jq -n \
    '{
      "viz_type": "dist_bar",
      "datasource": "'"$DATASET_ID"'__table",
      "metrics": ["count"], # Using the 'count' metric
      "groupby": ["bid_ask_spread"], # Group by bid_ask_spread for distribution
      "x_axis_label": "Bid-Ask Spread",
      "y_axis_label": "Count of Records",
      "show_legend": false,
      "row_limit": 50,
      "url_params": {},
      "extra_form_data": {}
    }' | tostring) # Must be a string for 'params' field

  CHART_2_PAYLOAD=$(jq -n \
    --arg slice_name "$CHART_2_NAME" \
    --arg viz_type "dist_bar" \
    --argjson datasource_id "$DATASET_ID" \
    --arg params_str "$CHART_2_FORM_DATA" \
    '{
      slice_name: $slice_name,
      viz_type: $viz_type,
      datasource_id: $datasource_id,
      datasource_type: "table",
      params: $params_str,
      owners: [1]
    }')
  
  CREATE_CHART_2_RESPONSE=$(curl -s -X POST "$SUPERSET_URL/api/v1/chart/" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-CSRFToken: $CSRF_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CHART_2_PAYLOAD")
  
  CHART_2_ID=$(echo "$CREATE_CHART_2_RESPONSE" | jq -r '.id // empty')
  if [[ -z "$CHART_2_ID" ]]; then
    echo "❌ Failed to create chart '$CHART_2_NAME'. Response: $CREATE_CHART_2_RESPONSE"
    exit 1
  fi
  echo "✅ Chart '$CHART_2_NAME' created with ID: $CHART_2_ID"
else
  echo "✅ Chart '$CHART_2_NAME' already exists with ID: $CHART_2_ID"
fi


# --- 9. Add/Get Dashboard and Add Charts to it ---
echo "--- Managing Dashboard '$DASHBOARD_TITLE' ---"
DASHBOARD_ID=""
DASHBOARD_FILTER_Q=$(jq -n \
  --arg title "$DASHBOARD_TITLE" \
  '{ "filters": [ { "col": "dashboard_title", "opr": "eq", "value": $title } ] }' \
  | jq -Rs '{"q": .}')

GET_DASHBOARD_RESPONSE=$(curl -s -G "$SUPERSET_URL/api/v1/dashboard/" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "$DASHBOARD_FILTER_Q")

DASHBOARD_ID=$(echo "$GET_DASHBOARD_RESPONSE" | jq -r '.result[0].id // empty')

if [[ -z "$DASHBOARD_ID" ]]; then
  echo "➡️ Dashboard '$DASHBOARD_TITLE' not found, creating it..."
  DASHBOARD_PAYLOAD=$(jq -n \
    --arg chart_1_id "$CHART_1_ID" \
    --arg chart_2_id "$CHART_2_ID" \
    --arg chart_1_name "$CHART_1_NAME" \
    --arg chart_2_name "$CHART_2_NAME" \
    --arg title "$DASHBOARD_TITLE" \
    '
    {
      dashboard_title: $title,
      position_json: (
        {
          "CHART-'"$CHART_1_ID"'": {
            children: [],
            id: "CHART-'"$CHART_1_ID"'",
            meta: {
              chartId: ($chart_1_id | tonumber),
              height: 50,
              sliceName: $chart_1_name,
              uuid: "chart-1-uuid",
              width: 6
            },
            parents: ["ROOT_ID", "GRID_ID", "ROW_ID_1"],
            type: "CHART"
          },
          "CHART-'"$CHART_2_ID"'": {
            children: [],
            id: "CHART-'"$CHART_2_ID"'",
            meta: {
              chartId: ($chart_2_id | tonumber),
              height: 50,
              sliceName: $chart_2_name,
              uuid: "chart-2-uuid",
              width: 6
            },
            parents: ["ROOT_ID", "GRID_ID", "ROW_ID_1"],
            type: "CHART"
          },
          "GRID_ID": {
            children: ["HEADER_ID", "ROW_ID_1"],
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
          "ROW_ID_1": {
            children: ["CHART-'"$CHART_1_ID"'", "CHART-'"$CHART_2_ID"'"],
            id: "ROW_ID_1",
            meta: {
              background: "BACKGROUND_TRANSPARENT"
            },
            type: "ROW",
            parents: ["ROOT_ID", "GRID_ID"]
          },
          "HEADER_ID": {
             children: [],
             id: "HEADER_ID",
             meta: {
                text: $title
             },
             type: "HEADER",
             parents: ["ROOT_ID", "GRID_ID"]
          }
        } | tostring
      ),
      json_metadata: "{}",
      css: "",
      published: true,
      owners: [1]
    }')
  
  CREATE_DASHBOARD_RESPONSE=$(curl -s -X POST "$SUPERSET_URL/api/v1/dashboard/" \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-CSRFToken: $CSRF_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$DASHBOARD_PAYLOAD")
  
  DASHBOARD_ID=$(echo "$CREATE_DASHBOARD_RESPONSE" | jq -r '.id // empty')
  if [[ -z "$DASHBOARD_ID" ]]; then
    echo "❌ Failed to create dashboard '$DASHBOARD_TITLE'. Response: $CREATE_DASHBOARD_RESPONSE"
    exit 1
  fi
  echo "✅ Created dashboard with ID: $DASHBOARD_ID"
else
  echo "✅ Dashboard '$DASHBOARD_TITLE' already exists with ID: $DASHBOARD_ID"
fi

# --- 10. Attach Charts to Dashboard (Idempotent: update chart's dashboards array) ---
echo "--- Attaching charts to dashboard ---"
PATCH_RESPONSE_CHART_1=$(curl -s -X PUT "$SUPERSET_URL/api/v1/chart/$CHART_1_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-CSRFToken: $CSRF_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "dashboards": ['"$DASHBOARD_ID"'] }')

PATCH_RESPONSE_CHART_2=$(curl -s -X PUT "$SUPERSET_URL/api/v1/chart/$CHART_2_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-CSRFToken: $CSRF_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "dashboards": ['"$DASHBOARD_ID"'] }')

if echo "$PATCH_RESPONSE_CHART_1" | jq -e '.id' &> /dev/null && \
   echo "$PATCH_RESPONSE_CHART_2" | jq -e '.id' &> /dev/null; then
  echo "✅ Charts successfully attached to dashboard!"
else
  echo "❌ Failed to attach charts. Responses:"
  echo "Chart 1: $PATCH_RESPONSE_CHART_1"
  echo "Chart 2: $PATCH_RESPONSE_CHART_2"
  exit 1
fi

echo ""
echo "🎉 SUCCESS! Superset setup complete!"
echo "📌 Dashboard created with ID: $DASHBOARD_ID"
echo "📊 Line Chart (Average Price & Bid-Ask Spread) ID: $CHART_1_ID"
echo "📊 Bar Chart (Bid-Ask Spread Distribution) ID: $CHART_2_ID"
echo "📈 Dataset ID: $DATASET_ID"
echo "🗃️ Database ID: $DB_ID"
echo ""
echo "🌐 Visit your new dashboard:"
echo "   $SUPERSET_URL/superset/dashboard/$DASHBOARD_ID/"
