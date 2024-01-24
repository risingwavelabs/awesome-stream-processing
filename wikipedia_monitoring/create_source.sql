CREATE SOURCE wiki_source (
  contributor VARCHAR,
  title VARCHAR,
  edit_timestamp TIMESTAMPTZ,
  registration TIMESTAMPTZ,
  gender VARCHAR,
  edit_count VARCHAR
) WITH (
    connector = 'kafka',
    topic = 'live_wiipedia_data',
    properties.bootstrap.server = 'message_queue:29092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;
