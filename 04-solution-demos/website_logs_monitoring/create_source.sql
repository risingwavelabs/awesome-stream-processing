-- This query creates a source named website_logs_source to ingest data from the Kafka topic website_logs in JSON format.
CREATE SOURCE website_logs_source (
    request_timestamp TIMESTAMP,
    ip_address VARCHAR,
    user_agent TEXT,
    url TEXT,
    http_method VARCHAR,
    status_code INTEGER,
    response_time INTEGER,
    referrer TEXT,
    user_id VARCHAR,
    username VARCHAR,
    user_action VARCHAR,
    security_level VARCHAR
)WITH (
  connector='kafka',
  topic = 'website_logs', 
  properties.bootstrap.server = 'message_queue:29092',
  scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;
