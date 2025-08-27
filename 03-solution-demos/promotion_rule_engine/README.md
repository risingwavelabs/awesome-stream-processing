## Real-time Promotion Rule Engine (RisingWave-based)

A real-time promotion rule engine for membership and loyalty use cases, built on RisingWave streaming with Kafka events. When members perform actions such as signup, activity, or points updates, the engine matches against configurable promotion rules using member profiles, computes capped rewards, and exposes queryable results and analytics views.

- **Real-time events**: Kafka event stream (aligned with the script configuration)
- **Member profile**: `member_profile` dimension table
- **Rule configuration**: `promotion_rules` table (supports areas/event types/thresholds)
- **Rule engine**: a pipeline of materialized views for matching and reward calculation
- **Outputs**: `mv_promotion_results`, `mv_promotion_stats`, `mv_member_promotion_summary`

### Use cases
- **Welcome/acquisition**: rewards triggered on member signup
- **Activity incentives**: rewards driven by area and activity intensity/spend
- **Tier benefits**: promotions gated by card tier, ADT/ODT, lodging spend

## Architecture and data flow
1. Kafka produces member events; RisingWave consumes them via source table `user_events`
2. `member_profile` and `promotion_rules` provide profile and rule configuration
3. Materialized views perform: recent event filter → active rules + area expansion → event–rule matching → profile validation → reward calculation and capping → results and stats aggregation

## Data model (core tables)
- **`user_events`**: event stream (Kafka source)
  - `event_type`: `signup` | `gaming` | `rating_update`
  - `event_dt`: processing time (`proctime()`)
  - `area`: `Pit01/02/03`, `Slot01/02`
  - `gaming_value`, `rating_points`, `metadata`

- **`member_profile`**: member profile dimension table
  - `card_tier`: `Bronze/Silver/Gold/Platinum`
  - `adt/odt/lodger`: theoretical/observed daily metrics and lodging spend
  - `preferred_area`, `status`, points, etc.

- **`promotion_rules`**: promotion rule configuration
  - `trigger_type`: event trigger type (aligned with `events.event_type`)
  - `promotion_from/to`: campaign start/end dates
  - `earning_type/earning_days`: accounting semantics and valid days (model placeholders)
  - `criteria_*`: profile thresholds (ADT/ODT/lodging)
  - `areas`: applicable areas array
  - `reward_value/reward_max`: base reward and cap
  - `status`: `ACTIVE/INACTIVE`

## Rule engine pipeline (materialized views)
- **`mv_recent_events`**: keep only last 24 hours of events to reduce noise
- **`mv_active_rules`**: filter `ACTIVE` rules
- **`mv_rule_areas_expanded`**: unnest `areas` for efficient matching
- **`mv_event_rule_matches`**: match by trigger type and area
- **`mv_complete_rule_matches`**: join member profile and validate thresholds
- **`mv_reward_calculations`**: compute dynamic multipliers and capped rewards
- **`mv_promotion_results`**: final promotions and `promotion_code`
- **`mv_promotion_stats`**: aggregated stats by rule and event type
- **`mv_member_promotion_summary`**: member-level promotion summary

### Reward calculation highlights
- Dynamic multiplier by event type:
  - `signup`: 1.0
  - `gaming`: `max(gaming_value/100, 1.0)`
  - `rating_update`: `max(rating_points/50, 1.0)`
- Final reward: `final_reward = min(reward_value * multiplier, reward_max)`

## Quick start
### Prerequisites
- Kafka is deployed and the topic name matches the script configuration
- RisingWave (or a compatible streaming database) is available with SQL access

### Deploy the SQL
Import the script into the database (example with `psql`):
```bash
psql -h <host> -p <port> -U <user> -d <database> -f pipeline.sql
```

### Ingest events (sample JSON)
Write JSON events to the Kafka topic (aligned with the `events` source):
```json
{"event_id":1,"member_id":100000001,"event_type":"signup","area":"Pit01","gaming_value":0,"rating_points":0,"metadata":{}}
```
```json
{"event_id":2,"member_id":100000005,"event_type":"gaming","area":"Pit01","gaming_value":420,"rating_points":0,"metadata":{"activity":"typeA"}}
```
```json
{"event_id":3,"member_id":100000003,"event_type":"rating_update","area":"Slot01","gaming_value":0,"rating_points":120,"metadata":{}}
```

> Note: `user_events.event_dt` uses `proctime()`, so no event timestamp is required.

### Validate queries
After importing sample data, validate directly via SQL:
```sql
-- Matches
SELECT * FROM mv_promotion_results ORDER BY event_dt DESC LIMIT 20;

-- Rule stats
SELECT * FROM mv_promotion_stats ORDER BY total_matches DESC;

-- Member summary
SELECT * FROM mv_member_promotion_summary ORDER BY total_promotions DESC LIMIT 20;
```

## How to extend
- **Add a new promotion rule**: insert into `promotion_rules` with `trigger_type`, `areas`, thresholds/rewards
- **Add a new area**: include the area string in `areas`; `mv_rule_areas_expanded` will unnest it
- **Add a new event type**:
  - Use the new type in `user_events.event_type` and `promotion_rules.trigger_type`
  - Extend the CASE logic in `mv_reward_calculations` for multiplier and reward
- **Change the time window**: adjust `NOW() - INTERVAL '24 HOURS'` in `mv_recent_events`

## Design constraints and trade-offs
- Only last 24 hours of events participate in matching to keep it real-time
- Rule activation via `status='ACTIVE'` allows hot toggling
- `areas` as array + unnest balances flexibility and performance
- Numeric fields use `decimal`; consider precision vs. performance per engine

## Directory structure
- `pipeline.sql`: complete DDL/DML and materialized views implementing the rule engine
