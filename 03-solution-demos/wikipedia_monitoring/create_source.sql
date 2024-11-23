-- This SQL query creates a Kafka source "wiki_source" for live Wikipedia data, extracting specified columns in JSON format from the 'live_wikipedia_data' Kafka topic.

CREATE SOURCE wiki_source (
  contributor VARCHAR,
  title VARCHAR,
  edit_timestamp TIMESTAMPTZ,
  registration TIMESTAMPTZ,
  gender VARCHAR,
  edit_count VARCHAR
) WITH (
    connector = 'kafka',
    topic = 'live_wikipedia_data',
    properties.bootstrap.server = 'kafka:9092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;
