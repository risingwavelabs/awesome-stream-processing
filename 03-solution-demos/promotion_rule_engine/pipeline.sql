-- =============================================================================
-- Casino Real-time Promotion System - RisingWave SQL Implementation
-- =============================================================================
-- This script implements a real-time promotion system using RisingWave
-- Optimized for streaming queries
-- =============================================================================

-- =============================================================================
-- 1. SOURCE TABLES CREATION
-- =============================================================================

-- Event stream table from Kafka
CREATE TABLE IF NOT EXISTS events (
    event_id BIGINT,
    member_id BIGINT,
    event_type VARCHAR,        -- 'signup', 'gaming', 'rating_update'
    event_dt TIMESTAMPTZ as proctime(),
    area VARCHAR,              -- 'Pit01', 'Pit02', 'Pit03', 'Slot01', 'Slot02'
    gaming_value decimal, -- Game amount for gaming events
    rating_points INT,          -- Points for rating_update events
    metadata JSONB
) WITH (
    connector = 'kafka',
    topic = 'user_events',
    properties.bootstrap.server = 'localhost:9092',
    scan.startup.mode = 'latest'
) FORMAT PLAIN ENCODE JSON;

-- Member profile dimension table
CREATE TABLE IF NOT EXISTS member_profile (
    member_id BIGINT PRIMARY KEY,
    card_tier VARCHAR,           -- 'Bronze', 'Silver', 'Gold', 'Platinum'
    adt decimal,          -- Average Daily Theoretical: 200-5000
    odt decimal,          -- Observed Daily Theoretical: 150-4500
    lodger decimal,       -- Lodging expenses: 0-1000
    status VARCHAR,             -- 'Active', 'Inactive', 'VIP'
    preferred_area VARCHAR,     
    signup_date DATE,
    last_activity_date DATE,
    total_points INT
);

-- Promotion rules configuration table
CREATE TABLE IF NOT EXISTS promotion_rules (
    rule_id INT PRIMARY KEY,
    rule_name VARCHAR,          -- 'NewSignup', 'VIPGaming', 'SlotPromo'
    trigger_type VARCHAR,       -- 'signup', 'gaming', 'rating_update'
    promotion_from DATE,        -- Promotion start date
    promotion_to DATE,          -- Promotion end date
    earning_type VARCHAR,       -- 'Daily', 'Weekly', 'Specific'
    earning_days INT,           -- Valid days
    criteria_adt_min decimal,  -- ADT minimum
    criteria_adt_max decimal,  -- ADT maximum
    criteria_odt_min decimal,  -- ODT minimum
    criteria_odt_max decimal,  -- ODT maximum
    criteria_lodger_min decimal, -- Lodger minimum
    areas VARCHAR[],            -- Applicable areas array
    reward_value decimal, -- Base reward amount
    reward_max decimal,   -- Maximum reward limit
    status VARCHAR DEFAULT 'ACTIVE'  -- 'ACTIVE', 'INACTIVE'
);

-- =============================================================================
-- 2. SAMPLE DATA INSERTION
-- =============================================================================

-- Sample member profiles
INSERT INTO member_profile VALUES
(100000001, 'Platinum', 2000.00, 1800.00, 500.00, 'Active', 'Pit01', '2024-01-15', '2025-07-20', 15000),
(100000002, 'Gold', 1500.00, 1200.00, 200.00, 'Active', 'Pit02', '2024-03-20', '2025-07-19', 8500),
(100000003, 'Silver', 800.00, 750.00, 100.00, 'Active', 'Slot01', '2024-06-10', '2025-07-18', 4200),
(100000004, 'Bronze', 300.00, 280.00, 50.00, 'Active', 'Slot02', '2025-01-01', '2025-07-17', 1800),
(100000005, 'Gold', 1200.00, 1100.00, 150.00, 'Active', 'Pit01', '2024-02-10', '2025-07-21', 7200),
(100000006, 'Silver', 600.00, 550.00, 80.00, 'Active', 'Slot01', '2024-05-15', '2025-07-16', 3800),
(100000007, 'Platinum', 2500.00, 2200.00, 600.00, 'Active', 'Pit03', '2023-12-01', '2025-07-22', 18000),
(100000008, 'Bronze', 400.00, 380.00, 60.00, 'Active', 'Slot02', '2024-08-20', '2025-07-15', 2200);

-- Sample promotion rules with extended valid periods
INSERT INTO promotion_rules VALUES
(1001, 'NewSignup', 'signup', '2025-01-01', '2025-12-31', 'Daily', 2, 1000.00, 9999.00, 200.00, 9999.00, 0.00, ARRAY['Pit01', 'Pit02'], 38.00, 5.00, 'ACTIVE'),
(1002, 'VIPGaming', 'gaming', '2025-01-01', '2025-12-31', 'Specific', 1, 1500.00, 9999.00, 1000.00, 9999.00, 200.00, ARRAY['Pit01'], 50.00, 10.00, 'ACTIVE'),
(1003, 'SlotPromo', 'gaming', '2025-01-01', '2025-12-31', 'Daily', 7, 500.00, 1499.00, 400.00, 1499.00, 0.00, ARRAY['Slot01', 'Slot02'], 25.00, 3.00, 'ACTIVE');

-- =============================================================================
-- 3. MATERIALIZED VIEWS - DATA PREPROCESSING
-- =============================================================================

-- Filter recent events (last 24 hours)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_recent_events AS
SELECT 
    event_id,
    member_id,
    event_type,
    event_dt,
    area,
    gaming_value,
    rating_points,
    metadata
FROM events
WHERE event_dt >= NOW() - INTERVAL '24 HOURS';

-- All active promotion rules (simplified for streaming mode)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_active_rules AS
SELECT 
    rule_id,
    rule_name,
    trigger_type,
    promotion_from,
    promotion_to,
    earning_type,
    earning_days,
    criteria_adt_min,
    criteria_adt_max,
    criteria_odt_min,
    criteria_odt_max,
    criteria_lodger_min,
    areas,
    reward_value,
    reward_max,
    status
FROM promotion_rules
WHERE status = 'ACTIVE';

-- Enhanced member profiles with calculated fields
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_member_enhanced AS
SELECT 
    member_id,
    card_tier,
    adt,
    odt,
    lodger,
    status,
    preferred_area,
    signup_date,
    last_activity_date,
    total_points,
    -- Add tier ranking for easier filtering
    CASE 
        WHEN card_tier = 'Platinum' THEN 4
        WHEN card_tier = 'Gold' THEN 3
        WHEN card_tier = 'Silver' THEN 2
        ELSE 1
    END AS tier_rank
FROM member_profile
WHERE status = 'Active';

-- =============================================================================
-- 4. RULE MATCHING ENGINE
-- =============================================================================

-- Step 1: Expand promotion rules areas to avoid array operations
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_rule_areas_expanded AS
SELECT 
    rule_id,
    rule_name,
    trigger_type,
    promotion_from,
    promotion_to,
    earning_type,
    earning_days,
    criteria_adt_min,
    criteria_adt_max,
    criteria_odt_min,
    criteria_odt_max,
    criteria_lodger_min,
    areas,
    reward_value,
    reward_max,
    unnest(areas) AS area
FROM mv_active_rules;

-- Step 2: Event-rule matching with criteria validation
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_event_rule_matches AS
SELECT 
    re.event_id,
    re.member_id,
    re.event_type,
    re.event_dt,
    re.area,
    re.gaming_value,
    re.rating_points,
    ra.rule_id,
    ra.rule_name,
    ra.reward_value,
    ra.reward_max,
    ra.criteria_adt_min,
    ra.criteria_adt_max,
    ra.criteria_odt_min,
    ra.criteria_odt_max,
    ra.criteria_lodger_min,
    -- Match status indicators
    CASE 
        WHEN re.event_type = ra.trigger_type THEN 1 ELSE 0
    END AS type_match,
    CASE 
        WHEN re.area = ra.area THEN 1 ELSE 0
    END AS area_match
FROM mv_recent_events re
JOIN mv_rule_areas_expanded ra ON re.event_type = ra.trigger_type
    AND re.area = ra.area;

-- Step 3: Member profile matching
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_complete_rule_matches AS
SELECT 
    erm.*,
    me.card_tier,
    me.adt,
    me.odt,
    me.lodger,
    -- Profile criteria matching
    CASE 
        WHEN me.adt >= erm.criteria_adt_min AND me.adt <= erm.criteria_adt_max THEN 1 ELSE 0
    END AS adt_match,
    CASE 
        WHEN me.odt >= erm.criteria_odt_min AND me.odt <= erm.criteria_odt_max THEN 1 ELSE 0
    END AS odt_match,
    CASE 
        WHEN me.lodger >= erm.criteria_lodger_min THEN 1 ELSE 0
    END AS lodger_match,
    -- Overall match status
    CASE 
        WHEN erm.type_match = 1 AND erm.area_match = 1 
            AND me.adt >= erm.criteria_adt_min AND me.adt <= erm.criteria_adt_max
            AND me.odt >= erm.criteria_odt_min AND me.odt <= erm.criteria_odt_max
            AND me.lodger >= erm.criteria_lodger_min
        THEN 'MATCHED'
        ELSE 'NOT_MATCHED'
    END AS match_status
FROM mv_event_rule_matches erm
JOIN mv_member_enhanced me ON erm.member_id = me.member_id;

-- =============================================================================
-- 5. REWARD CALCULATION ENGINE
-- =============================================================================

-- Calculate dynamic multipliers and final rewards
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_reward_calculations AS
SELECT 
    event_id,
    member_id,
    event_type,
    event_dt,
    area,
    gaming_value,
    rating_points,
    rule_id,
    rule_name,
    reward_value,
    reward_max,
    card_tier,
    adt,
    odt,
    lodger,
    -- Dynamic multiplier calculation
    CASE 
        WHEN event_type = 'signup' THEN 1.0
        WHEN event_type = 'gaming' THEN 
            CASE 
                WHEN gaming_value > 0 THEN GREATEST(gaming_value / 100.0, 1.0)
                ELSE 1.0
            END
        WHEN event_type = 'rating_update' THEN 
            CASE 
                WHEN rating_points > 0 THEN GREATEST(rating_points / 50.0, 1.0)
                ELSE 1.0
            END
        ELSE 1.0
    END AS dynamic_multiplier,
    -- Calculate raw reward
    reward_value * 
    CASE 
        WHEN event_type = 'signup' THEN 1.0
        WHEN event_type = 'gaming' THEN 
            CASE 
                WHEN gaming_value > 0 THEN GREATEST(gaming_value / 100.0, 1.0)
                ELSE 1.0
            END
        WHEN event_type = 'rating_update' THEN 
            CASE 
                WHEN rating_points > 0 THEN GREATEST(rating_points / 50.0, 1.0)
                ELSE 1.0
            END
        ELSE 1.0
    END AS raw_reward,
    -- Final reward with cap
    LEAST(
        reward_value * 
        CASE 
            WHEN event_type = 'signup' THEN 1.0
            WHEN event_type = 'gaming' THEN 
                CASE 
                    WHEN gaming_value > 0 THEN GREATEST(gaming_value / 100.0, 1.0)
                    ELSE 1.0
                END
            WHEN event_type = 'rating_update' THEN 
                CASE 
                    WHEN rating_points > 0 THEN GREATEST(rating_points / 50.0, 1.0)
                    ELSE 1.0
                END
            ELSE 1.0
        END,
        reward_max
    ) AS final_reward
FROM mv_complete_rule_matches
WHERE match_status = 'MATCHED';

-- =============================================================================
-- 6. FINAL OUTPUT AND MONITORING
-- =============================================================================

-- Final promotion results view
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_promotion_results AS
SELECT 
    event_id,
    member_id,
    event_type,
    event_dt,
    area,
    gaming_value,
    rating_points,
    rule_id,
    rule_name,
    card_tier,
    adt,
    odt,
    lodger,
    dynamic_multiplier,
    final_reward,
    -- Additional metadata for tracking
    CONCAT('PROMO_', rule_name, '_', event_id) AS promotion_code
FROM mv_reward_calculations
WHERE final_reward > 0;

-- Real-time monitoring statistics (fixed for streaming mode)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_promotion_stats AS
SELECT 
    rule_name,
    event_type,
    COUNT(*) AS total_matches,
    COUNT(CASE WHEN final_reward > 0 THEN 1 END) AS successful_promotions,
    AVG(final_reward) AS avg_reward,
    SUM(final_reward) AS total_reward_value,
    MIN(final_reward) AS min_reward,
    MAX(final_reward) AS max_reward
FROM mv_promotion_results
GROUP BY rule_name, event_type;

-- Member-wise promotion summary
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_member_promotion_summary AS
SELECT 
    member_id,
    card_tier,
    COUNT(*) AS total_promotions,
    SUM(final_reward) AS total_reward_received,
    AVG(final_reward) AS avg_reward_per_promotion,
    MAX(event_dt) AS last_promotion_dt,
    STRING_AGG(DISTINCT rule_name, ', ') AS promotion_rules_received
FROM mv_promotion_results
GROUP BY member_id, card_tier;
