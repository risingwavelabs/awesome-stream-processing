CREATE TABLE user_profiles (
    user_id INT,
    username VARCHAR,
    preferred_league VARCHAR,
    avg_bet_size FLOAT,
    risk_tolerance VARCHAR
);

CREATE TABLE betting_history (
    user_id INT,
    position_id INT,
    bet_amount FLOAT,
    result VARCHAR,
    profit_loss FLOAT, 
    timestamp TIMESTAMPTZ
);

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

CREATE MATERIALIZED VIEW real_time_user_exposure AS
SELECT
    user_id,
    SUM(stake_amount) AS total_exposure,
    COUNT(*) AS active_positions
FROM
    positions
GROUP BY
    user_id;

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

