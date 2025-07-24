#!/usr/bin/env bash
set -e
set -o pipefail

# --- Configuration ---
SUPERSET_URL="${SUPERSET_URL:-http://localhost:8088}"
SUPERSET_USERNAME="${SUPERSET_USERNAME:-admin}"
SUPERSET_PASSWORD="${SUPERSET_PASSWORD:-admin}"
DB_NAME="Marketing_Events"
SQLALCHEMY_URI="risingwave://root@risingwave:4566/dev"

# --- Pre-requisites ---
for cmd in curl jq; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: '$cmd' is required." >&2
    exit 1
  fi
done

# Helper for idempotent asset creation
get_or_create_asset() {
  local type="$1" name="$2" filter_q="$3" payload="$4"
  local res id
  res=$(curl -s -G "$SUPERSET_URL/api/v1/$type/" \
    -H "Authorization: Bearer $TOKEN" --data-urlencode "$filter_q")
  id=$(echo "$res" | jq -r '.result[0].id // empty')
  if [[ -n "$id" ]]; then
    echo "$type '$name' exists (ID=$id)" >&2
    echo "$id"; return
  fi
  echo "Creating $type '$name'..." >&2
  res=$(curl -s -X POST "$SUPERSET_URL/api/v1/$type/" \
    -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" \
    -H "Content-Type: application/json" -d "$payload")
  echo "$res" >&2
  echo "$res" | jq -r '.id'
}

# 1) Authenticate
until curl -s "$SUPERSET_URL/api/v1/ping" &> /dev/null; do sleep 1; done
LOGIN=$(curl -s -X POST "$SUPERSET_URL/api/v1/security/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$SUPERSET_USERNAME\",\"password\":\"$SUPERSET_PASSWORD\",\"provider\":\"db\"}")
TOKEN=$(echo "$LOGIN" | jq -r '.access_token')
CSRF_TOKEN=$(curl -s -H "Authorization: Bearer $TOKEN" "$SUPERSET_URL/api/v1/security/csrf_token/" | jq -r '.result')

# 2) Add/Retrieve Database
DB_FILTER="q=$(jq -n --arg name "$DB_NAME" '{filters:[{col:"database_name",opr:"eq",value:$name}]}')"
DB_PAYLOAD=$(jq -n --arg name "$DB_NAME" --arg uri "$SQLALCHEMY_URI" --argjson expose true --arg extra '{"show_views":true}' \
  '{database_name:$name,sqlalchemy_uri:$uri,expose_in_sqllab:$expose,extra:$extra}')
DB_ID=$(get_or_create_asset database "$DB_NAME" "$DB_FILTER" "$DB_PAYLOAD")
# Ensure views are exposed and refresh
curl -s -X PUT "$SUPERSET_URL/api/v1/database/$DB_ID" -H "Authorization: Bearer $TOKEN" \
  -H "X-CSRFToken: $CSRF_TOKEN" -H "Content-Type: application/json" \
  -d '{"extra":{"show_views":true}}' >/dev/null
curl -s -X POST "$SUPERSET_URL/api/v1/database/$DB_ID/refresh" \
  -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" >/dev/null

for ds in marketing_events campaign_performance channel_attribution ab_test_results; do
  FILTER="q=$(jq -n --arg tn "$ds" '{filters:[{col:"table_name",opr:"eq",value:$tn}]}')"
  PAYLOAD=$(jq -n --arg db "$DB_ID" --arg tn "$ds" --arg schema "public" \
    '{database:($db|tonumber),table_name:$tn,schema:$schema,owners:[1]}')
  ID_VAR="\${ds^^}_DS_ID"
  eval "${ds^^}_DS_ID=$(get_or_create_asset dataset "$ds" "$FILTER" "$PAYLOAD")"
  curl -s -X PUT "$SUPERSET_URL/api/v1/dataset/\${!ID_VAR}/refresh" \
    -H "Authorization: Bearer $TOKEN" -H "X-CSRFToken: $CSRF_TOKEN" >/dev/null
    
done
echo
echo "Dataset IDs:"
echo "  MARKETING_EVENTS_DS_ID= $MARKETING_EVENTS_DS_ID"
echo "  CAMPAIGN_PERFORMANCE_DS_ID= $CAMPAIGN_PERFORMANCE_DS_ID"
echo "  CHANNEL_ATTRIBUTION_DS_ID= $CHANNEL_ATTRIBUTION_DS_ID"
echo "  AB_TEST_RESULTS_DS_ID= $AB_TEST_RESULTS_DS_ID"
echo
# 4) Create Charts
# 4.1 Events Over Time
CH_NAME="Events Over Time"
CH_FILTER="q=$(jq -n --arg name "$CH_NAME" '{filters:[{col:"slice_name",opr:"eq",value:$name}]}')"
CH_PARAMS=$(jq -n --argjson ds_id "$MARKETING_EVENTS_DS_ID" '{
  viz_type:"line",
  datasource:"\($ds_id)__table",
  granularity_sqla:"timestamp",
  time_range:"No filter",
  metrics: [
    {
      label: "Total Events",
      expressionType: "SQL",
      sqlExpression: "COUNT(event_id)"
    }
  ],
  groupby:["event_type"],
  time_grain_sqla:"PT1M",
  row_limit:10000,
  show_legend:true
}')
CH_PAYLOAD=$(jq -n --arg name "$CH_NAME" --argjson ds_id "$MARKETING_EVENTS_DS_ID" --argjson params "$CH_PARAMS" \
  '{slice_name:$name,viz_type:"line",datasource_id:$ds_id,datasource_type:"table",params:($params|tostring),owners:[1]}')
CH_1_ID=$(get_or_create_asset chart "$CH_NAME" "$CH_FILTER" "$CH_PAYLOAD")

# 4.2 Revenue Over Time
CH_NAME="Revenue Over Time"
CH_FILTER="q=$(jq -n --arg name "$CH_NAME" '{filters:[{col:"slice_name",opr:"eq",value:$name}]}')"
CH_PARAMS=$(jq -n --argjson ds_id "$CAMPAIGN_PERFORMANCE_DS_ID" '{
  viz_type:"line",datasource:"\($ds_id)__table",
  granularity_sqla:"window_start",time_range:"No filter",
  metrics: [
    {
      label: "Revenue over Time",
      expressionType: "SQL",
      sqlExpression: "SUM(revenue)"
    }
  ],
  groupby:["campaign_id"],
  time_grain_sqla:"PT1M",
  row_limit:10000,
  show_legend:true
}')
CH_PAYLOAD=$(jq -n --arg name "$CH_NAME" --argjson ds_id "$CAMPAIGN_PERFORMANCE_DS_ID" --argjson params "$CH_PARAMS" \
  '{slice_name:$name,viz_type:"line",datasource_id:$ds_id,datasource_type:"table",params:($params|tostring),owners:[1]}')
CH_2_ID=$(get_or_create_asset chart "$CH_NAME" "$CH_FILTER" "$CH_PAYLOAD")

# 4.3 Channel Attribution
CH_NAME="Channel Attribution"
CH_FILTER="q=$(jq -n --arg name "$CH_NAME" '{filters:[{col:"slice_name",opr:"eq",value:$name}]}')"
CH_PARAMS=$(jq -n --argjson ds_id "$CHANNEL_ATTRIBUTION_DS_ID" '{
  viz_type:"bar",
  datasource:"\($ds_id)__table",
  granularity_sqla:"window_start",
  time_range:"No filter",
  metrics: [
    {
      label: "Revenue by Channel",
      expressionType: "SQL",
      sqlExpression: "SUM(revenue)"
    }
  ],
  groupby:["channel_type"],
  time_grain_sqla:"PT1H",
  row_limit:10000,
  show_legend:true
}')
CH_PAYLOAD=$(jq -n --arg name "$CH_NAME" --argjson ds_id "$CHANNEL_ATTRIBUTION_DS_ID" --argjson params "$CH_PARAMS" \
  '{slice_name:$name,
  viz_type:"bar",
  datasource_id:$ds_id,
  datasource_type:"table",
  params:($params|tostring),
  owners:[1]}')
CH_3_ID=$(get_or_create_asset chart "$CH_NAME" "$CH_FILTER" "$CH_PAYLOAD")

# 4.4 A/B Test Comparison
CH_NAME="AB Test Variant Comparison"
CH_FILTER="q=$(jq -n --arg name "$CH_NAME" '{filters:[{col:"slice_name",opr:"eq",value:$name}]}')"
CH_PARAMS=$(jq -n --argjson ds_id "$AB_TEST_RESULTS_DS_ID" '{
  viz_type:"bar",
  datasource:"\($ds_id)__table",
  granularity_sqla:"window_start",
  time_range:"No filter",
  metrics: [
    {
      label: "Total Events",
      expressionType: "SQL",
      sqlExpression: "AVG(conversion_rate)"
    }
  ],
  groupby:["variant_name"],
  row_limit:10000,
  show_legend:true
}')
CH_PAYLOAD=$(jq -n --arg name "$CH_NAME" --argjson ds_id "$AB_TEST_RESULTS_DS_ID" --argjson params "$CH_PARAMS" \
  '{slice_name:$name,viz_type:"bar",datasource_id:$ds_id,datasource_type:"table",params:($params|tostring),owners:[1]}')
CH_4_ID=$(get_or_create_asset chart "$CH_NAME" "$CH_FILTER" "$CH_PAYLOAD")

cat <<EOF
Superset charts created:
- Events Over Time:        $SUPERSET_URL/explore/?slice_id=$CH_1_ID
- Revenue Over Time:       $SUPERSET_URL/explore/?slice_id=$CH_2_ID
- Channel Attribution:     $SUPERSET_URL/explore/?slice_id=$CH_3_ID
- A/B Test Comparison:     $SUPERSET_URL/explore/?slice_id=$CH_4_ID
EOF
