{{ config(materialized='source') }}

CREATE SOURCE {{ this }} (
    user_id int,
    item_id varchar,
    event_time timestamp
) WITH (
    connector = 'kafka',
    topic = 'cart_events',
    properties.bootstrap.server = 'localhost:9092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON