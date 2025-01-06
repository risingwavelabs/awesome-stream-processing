# User betting behavior analysis

Identify high-risk and high-value users by analyzing and identifying trends in user betting patterns.

Follow the instructions below to learn how to run this demo. 

For more details about the process and the use case, see the [official documentation](https://docs.risingwave.com/demos/betting-behavior-analysis).

## Step 1: Install and run a RisingWave instance

See the [installation guide](/00-get-started/00-install-kafka-pg-rw.md#install-risingwave) for more details.

## Step 2: Create tables in RisingWave

Run the following two queries to set up your tables in RisingWave.

```sql
CREATE TABLE user_profiles (
    user_id INT,
    username VARCHAR,
    preferred_league VARCHAR,
    avg_bet_size FLOAT,
    risk_tolerance VARCHAR
);
```

```sql
CREATE TABLE betting_history (
    user_id INT,
    position_id INT,
    bet_amount FLOAT,
    result VARCHAR,
    profit_loss FLOAT, 
    timestamp TIMESTAMPTZ
);
```

```sql
CREATE TABLE positions (
    position_id INT,
    position_name VARCHAR,
    user_id INT,
    league VARCHAR,
    stake_amount FLOAT,
    expected_return FLOAT,
    current_odds FLOAT,
    profit_loss FLOAT,
    timestamp TIMESTAMPTZ
);
```

## Step 3: Run the data generator

Ensure that you have a Python environment set up and have installed the psycopg2 library. Run the data generator.

This will start inserting mock data into the tables created above.

## Step 4: Create materialized views

Run the following queries to create materialized views to analyze the data.

```sql
CREATE MATERIALIZED VIEW user_betting_patterns AS
SELECT
    user_id,
    COUNT(*) AS total_bets,
    SUM(CASE WHEN result = 'Win' THEN 1 ELSE 0 END) AS wins,
    SUM(CASE WHEN result = 'Loss' THEN 1 ELSE 0 END) AS losses,
    AVG(profit_loss) AS avg_profit_loss,
    SUM(profit_loss) AS total_profit_loss
FROM
    betting_history
GROUP BY
    user_id;
```

```sql
CREATE MATERIALIZED VIEW real_time_user_exposure AS
SELECT
    user_id,
    SUM(stake_amount) AS total_exposure,
    COUNT(*) AS active_positions
FROM
    positions
GROUP BY
    user_id;
```

```sql
CREATE MATERIALIZED VIEW high_risk_users AS
SELECT
    u.user_id,
    u.username,
    u.risk_tolerance,
    p.total_exposure,
    b.total_bets,
    b.avg_profit_loss,
    b.total_profit_loss
FROM
    user_profiles AS u
JOIN
    real_time_user_exposure AS p
ON
    u.user_id = p.user_id
JOIN
    user_betting_patterns AS b
ON
    u.user_id = b.user_id
WHERE
    p.total_exposure > u.avg_bet_size * 5
    AND b.avg_profit_loss < 0;
```