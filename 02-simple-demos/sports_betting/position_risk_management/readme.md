# Risk and position analysis in sports betting

Manage your sports betting or trading positions in real-time by using RisingWave to monitor exposure and risk.

Follow the instructions below to learn how to run this demo. 

For more details about the process and the use case, see the [official documentation](https://docs.risingwave.com/demos/sports-risk-profit-analysis).

## Step 1: Install and run a RisingWave instance

See the [installation guide](/00-get-started/00-install-kafka-pg-rw.md#install-risingwave) for more details.

## Step 2: Create tables in RisingWave

Run the following two queries to set up your tables in RisingWave.

```sql
CREATE TABLE positions (
    position_id INT,
    league VARCHAR,
    position_name VARCHAR,
    timestamp TIMESTAMPTZ,
    stake_amount FLOAT,
    expected_return FLOAT,
    max_risk FLOAT,
    fair_value FLOAT,
    current_odds FLOAT,
    profit_loss FLOAT,
    exposure FLOAT
);
```

```sql
CREATE TABLE market_data (
    position_id INT,
    bookmaker VARCHAR,
    market_price FLOAT,
    volume INT,
    timestamp TIMESTAMPTZ
);
```

## Step 3: Run the data generator

Ensure that you have a Python environment set up and have installed the psycopg2 library. Run the data generator.

This will start inserting mock data into the tables created above.

## Step 4: Create materialized views

Run the following queries to create materialized views to analyze the data.

```sql
CREATE MATERIALIZED VIEW position_overview AS
SELECT
    p.position_id,
    p.position_name,
    p.league,
    p.stake_amount,
    p.max_risk,
    p.fair_value,
    m.market_price,
    (m.market_price - p.fair_value) * p.stake_amount AS profit_loss,
    CASE
        WHEN (m.market_price - p.fair_value) * p.stake_amount > p.max_risk THEN 'High'
        WHEN (m.market_price - p.fair_value) * p.stake_amount BETWEEN p.max_risk * 0.5 AND p.max_risk THEN 'Medium'
        ELSE 'Low'
    END AS risk_level,
    m.timestamp AS last_update
FROM
    positions AS p
JOIN
    (SELECT position_id, market_price, timestamp,
            ROW_NUMBER() OVER (PARTITION BY position_id ORDER BY timestamp DESC) AS row_num
     FROM market_data) AS m
ON p.position_id = m.position_id
WHERE m.row_num = 1;
```

```sql
CREATE MATERIALIZED VIEW risk_summary AS
SELECT
    risk_level,
    COUNT(*) AS position_count
FROM
    position_overview
GROUP BY
    risk_level;
```

```sql
CREATE MATERIALIZED VIEW market_summary AS
SELECT
    p.position_id,
    p.position_name,
    p.league,
    m.bookmaker,
    m.market_price,
    m.timestamp AS last_update
FROM
    positions AS p
JOIN
    (SELECT position_id, bookmaker, market_price, timestamp,
            ROW_NUMBER() OVER (PARTITION BY position_id, bookmaker ORDER BY timestamp DESC) AS row_num
     FROM market_data) AS m
ON p.position_id = m.position_id
WHERE m.row_num = 1;
```