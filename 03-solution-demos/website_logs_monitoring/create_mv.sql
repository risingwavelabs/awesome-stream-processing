-- Mv for per-minute user activity metrics: request counts, response times, error/login/logout counts, and unique IPs.
CREATE MATERIALIZED VIEW website_user_metrics AS  
WITH UserActivityStats AS (
    SELECT  
        username,
        COUNT(username) AS total_requests,
        window_start,
        window_end,
        MIN(response_time) AS min_response_time,
        MAX(response_time) AS max_response_time,
        AVG(response_time) AS avg_response_time,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY response_time) AS median_response_time,
        SUM(CASE WHEN status_code >= 400 THEN 1 ELSE 0 END) AS total_errors,
        SUM(CASE WHEN user_action = 'login' THEN 1 ELSE 0 END) AS login_count,
        SUM(CASE WHEN user_action = 'logout' THEN 1 ELSE 0 END) AS logout_count,
        COUNT(DISTINCT ip_address) AS unique_ips
    FROM TUMBLE (website_logs_source, request_timestamp, INTERVAL '1 MINUTES')
    GROUP BY username, window_start, window_end
)

SELECT
    username,
    total_requests,
    min_response_time,
    max_response_time,
    avg_response_time,
    median_response_time,
    total_errors,
    login_count,
    logout_count,
    unique_ips,
    window_start,
    window_end
FROM UserActivityStats;

-- MV for top three user actions per minute, with action names, counts, and time windows.
CREATE MATERIALIZED VIEW top_user_actions AS
WITH ranked_user_actions AS (
    SELECT  
        user_action,
        COUNT(user_action) AS count_user_activity,
        window_start,
        window_end,
        ROW_NUMBER() OVER (PARTITION BY window_start, window_end ORDER BY COUNT(user_action) DESC) AS action_rank
    FROM TUMBLE (website_logs_source, request_timestamp, INTERVAL '1 MINUTES')
    GROUP BY user_action, window_start, window_end
)
SELECT
    user_action,
    count_user_activity,
    window_start,
    window_end
FROM ranked_user_actions
WHERE action_rank <= 5
ORDER BY window_start, action_rank;

-- MV for per-minute HTTP status code distribution, showing counts, average response times, and cumulative percentages.
CREATE MATERIALIZED VIEW referrer_activity_summary AS
SELECT
    referrer,
    COUNT(referrer) AS referrer_visit_count,
    SUM(CASE WHEN user_action IN ('view_page', 'navigate_page') THEN 1 ELSE 0 END) AS page_visits,
    SUM(CASE WHEN user_action IN ('submit_form', 'login', 'logout') THEN 1 ELSE 0 END) AS interactions,
    SUM(CASE WHEN user_action IN ('scroll_page', 'download_file', 'upload_file') THEN 1 ELSE 0 END) AS content_interactions,
    SUM(CASE WHEN user_action IN ('close_window', 'open_new_tab') THEN 1 ELSE 0 END) AS window_interactions,
    window_start,
    window_end
FROM TUMBLE(website_logs_source, request_timestamp, INTERVAL '1 MINUTES')     
GROUP BY referrer, window_start, window_end;


-- MV for per-minute security level metrics: counts, average response times, and median counts.
CREATE MATERIALIZED VIEW status_code_analysis_summary 
WITH Status_Code_Analysis AS (
    SELECT  
        status_code,
        COUNT(status_code) AS count_status_code,
        AVG(response_time) AS avg_response_time,
        SUM(COUNT(status_code)) OVER (PARTITION BY window_start, window_end ORDER BY status_code) AS cumulative_count,
        100.0 * SUM(COUNT(status_code)) OVER (PARTITION BY window_start, window_end ORDER BY status_code) / SUM(COUNT(status_code)) OVER (PARTITION BY window_start, window_end) AS cumulative_percentage,
        window_start,
        window_end
    FROM TUMBLE (website_logs_source, request_timestamp, INTERVAL '1 MINUTES')
    GROUP BY status_code, window_start, window_end
)

SELECT  
    status_code,
    count_status_code,
    avg_response_time,
    cumulative_count,
    cumulative_percentage,
    window_start,
    window_end
FROM Status_Code_Analysis
ORDER BY window_start DESC, status_code;
