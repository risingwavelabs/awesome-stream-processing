# Build Real-Time Player Analytics with RisingWave
Create a streaming table in RisingWave that ingests data from a Kafka topic, run windowed KPIs, and surface leaders & spikes — all in SQL, all in real time.

## Prerequisites
- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/): Docker Compose is included with Docker Desktop for Windows and macOS. Ensure Docker Desktop is running if you're using it.
- [PostgreSQL interactive terminal (psql)](https://www.postgresql.org/download/): This will allow you to connect to RisingWave for stream management and queries.

## Launch the demo cluster

### Clone the repo

```bash
git clone https://github.com/risingwavelabs/awesome-stream-processing.git
cd awesome-stream-processing/03-solution-demos/streaming-game-analytics
```

### Start the Stack

Run the Docker Compose file to set up all services, that start the data generator, which creates game data and publishes it to the Kafka topic `player_stats`. RisingWave ingests this data to create a source table.

```bash
docker compose up -d
```

The sample data that the data generator creates and sends to a Kafka topic, and that RisingWave ingests using the Kafka connector, is as follows:

```json
{
  "ts": "2025-09-11 06:53:44",
  "match_id": 4,
  "player_name": "Taylor Wilson",
  "mental_state": "tired",
  "eliminations": 5,
  "assists": 1,
  "headshot_kills": 3,
  "damage_dealt": 954,
  "damage_taken": 82,
  "healing_done": 944,
  "accuracy": 59.19,
  "time_survived": 1320,
  "player_rank": 33
}
```

## Connect with RisingWave via psql

```bash
psql -h localhost -p 4566 -d dev -U root
```

## 1. Create the streaming table

**Define schema for incoming match stats**

```sql
CREATE TABLE player_match_stats (
  ts             TIMESTAMP,
  match_id       INT,
  player_name    TEXT,
  mental_state   TEXT,
  eliminations   INT,
  assists        INT,
  headshot_kills INT,
  damage_dealt   INT,
  damage_taken   INT,
  healing_done   INT,
  accuracy       DOUBLE PRECISION,
  time_survived  INT,
  player_rank    INT
) WITH (
    connector = 'kafka',
    topic = 'player_stats',
    properties.bootstrap.server = 'kafka:9092'
) FORMAT PLAIN ENCODE JSON;
```

## 2. Team KPIs over time windows

**10-minute team KPIs (kills, headshot rate, DPM, sustain, accuracy)**

```sql
SELECT
  window_start,
  window_end,
  SUM(eliminations) AS total_kills,
  ROUND( (100::numeric * SUM(headshot_kills)) / NULLIF(SUM(eliminations), 0), 2) AS headshot_rate_pct,
  ROUND( (SUM(damage_dealt)::numeric) / NULLIF(SUM(time_survived)::numeric / 60, 0), 2) AS team_dpm,
  ROUND( (SUM(healing_done)::numeric) / NULLIF(SUM(damage_taken)::numeric, 0), 2) AS sustain_ratio,
  ROUND( AVG(accuracy)::numeric, 2) AS avg_accuracy_pct
FROM TUMBLE(player_match_stats, ts, INTERVAL '10' MINUTE)
GROUP BY window_start, window_end
ORDER BY window_start;
```

**15-minute mental-state breakdown (accuracy, HS/kill, avg survival, placement)**

```sql
SELECT
  window_start,
  window_end,
  mental_state,
  COUNT(*) AS samples,
  SUM(eliminations) AS kills,
  ROUND(AVG(accuracy)::numeric, 2) AS avg_accuracy_pct,
  ROUND(
    (SUM(headshot_kills)::numeric) / NULLIF(SUM(eliminations)::numeric, 0),
    2
  ) AS hs_per_kill,
  -- average survival per record, in minutes
  ROUND(
    (SUM(time_survived)::numeric) / 60 / NULLIF(COUNT(*)::numeric, 0),
    2
  ) AS avg_survival_min,
  ROUND(AVG(player_rank)::numeric, 2) AS avg_placement
FROM TUMBLE(player_match_stats, ts, INTERVAL '15' MINUTE)
GROUP BY window_start, window_end, mental_state
ORDER BY window_start, mental_state;
```

## 3. Leaders & spikes (HOP windows + analytics)

**Top 3 players per 20-minute sliding window (custom impact score)**

```sql
 WITH hop AS (
  SELECT
    window_start,
    window_end,
    player_name,
    SUM(eliminations)     AS elims,
    SUM(assists)          AS ast,
    SUM(headshot_kills)   AS hs,
    SUM(damage_dealt)     AS dmg,
    SUM(time_survived)    AS time_sec
  FROM HOP(player_match_stats, ts, INTERVAL '5' MINUTE, INTERVAL '20' MINUTE)
  GROUP BY window_start, window_end, player_name
),
ranked AS (
  SELECT
    window_start, window_end, player_name,
    elims, ast, hs, dmg,
    /* customizable impact formula */
    (elims * 2 + ast + hs * 0.5 + dmg / 1000.0) AS impact_score,
    ROW_NUMBER() OVER (
      PARTITION BY window_start, window_end
      ORDER BY (elims * 2 + ast + hs * 0.5 + dmg / 1000.0) DESC
    ) AS rn
  FROM hop
)
SELECT *
FROM ranked
WHERE rn <= 3
ORDER BY window_start, rn;
```

**Spike detection: ≥50% jump in kills or damage vs prior 15-minute window**

```sql
WITH w AS (
  SELECT
    window_start,
    window_end,
    player_name,
    SUM(eliminations)   AS elims,
    SUM(damage_dealt)   AS dmg,
    SUM(headshot_kills) AS hs
  FROM HOP(player_match_stats, ts, INTERVAL '5' MINUTE, INTERVAL '15' MINUTE)
  GROUP BY window_start, window_end, player_name
),
diff AS (
  SELECT
    *,
    LAG(elims) OVER (PARTITION BY player_name ORDER BY window_end) AS prev_elims,
    LAG(dmg)   OVER (PARTITION BY player_name ORDER BY window_end) AS prev_dmg
  FROM w
)
SELECT
  window_start,
  window_end,
  player_name,
  elims,
  prev_elims,
  dmg,
  prev_dmg,
  ROUND( ((elims - prev_elims)::numeric) / NULLIF(prev_elims::numeric, 0), 2 ) AS kill_jump_ratio,
  ROUND( ((dmg   - prev_dmg  )::numeric) / NULLIF(prev_dmg::numeric,   0), 2 ) AS dmg_jump_ratio
FROM diff
WHERE prev_elims IS NOT NULL
  AND (elims >= prev_elims * 1.5 OR dmg >= prev_dmg * 1.5)
ORDER BY window_end, player_name;
```

**Top-5 per match in each 10-minute window (tie-break by dmg, assists)**

```sql
WITH win AS (
  SELECT
    window_start,
    window_end,
    match_id,
    player_name,
    SUM(eliminations) AS elims,
    SUM(damage_dealt) AS dmg,
    SUM(assists)      AS ast
  FROM TUMBLE(player_match_stats, ts, INTERVAL '10' MINUTE)
  GROUP BY window_start, window_end, match_id, player_name
),
ranked AS (
  SELECT
    window_start, match_id, player_name, elims, dmg, ast,
    ROW_NUMBER() OVER (
      PARTITION BY window_start, match_id
      ORDER BY elims DESC, dmg DESC, ast DESC
    ) AS rk
  FROM win
)
SELECT *
FROM ranked
WHERE rk <= 5
ORDER BY window_start, match_id, rk;
```

## Optional: Clean up (Docker)

```bash
docker compose down -v
```

## Recap

- **Create** a compact stream table for match stats.
- **Measure** KPIs with `TUMBLE` and drill down by mental state.
- **Highlight** leaders and detect performance spikes with `HOP`, window functions, and rankings.
