  # zookeeper
  zookeeper:
    platform: linux/amd64
    image: wurstmeister/zookeeper
    container_name: zookeeper
    ports:
      - "2181:2181"
    networks:
      - kafka-net

  # kafka
  kafka:
    image: confluentinc/cp-kafka:latest
    container_name: kafka
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
      - "29092:29092"
    expose:
      - "9092"
      - "29092"
    environment:
      KAFKA_ADVERTISED_LISTENERS: LISTENER_DOCKER_INTERNAL://kafka:9092, LISTENER_DOCKER_EXTERNAL://localhost:29092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: LISTENER_DOCKER_INTERNAL:PLAINTEXT, LISTENER_DOCKER_EXTERNAL:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: LISTENER_DOCKER_INTERNAL
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: 'true'
      KAFKA_CREATE_TOPICS: "flights_tracking"
    volumes:
     - /var/run/docker.sock:/var/run/docker.sock
    networks:
     - kafka-net

  # kafka producer
  #kafka-producer:
   # build:
    #  context: .
     # dockerfile: Dockerfile
  #  depends_on:
   #  - kafka
    #environment:
     # KAFKA_BOOTSTRAP_SERVERS: LISTENER_DOCKER_INTERNAL://kafka:9092
  #  networks:
   #  - kafka-net

  # risingwave
  risingwave:
    image: risingwavelabs/risingwave:v1.6.0
    ports:
    - 5690:5690
    - 5691:5691
    - 4566:4566
    entrypoint:
    - /risingwave/bin/risingwave
    - playground
    networks:
     - kafka-net


networks:
  kafka-net:
    driver: bridge
    name: kafka-net

CREATE SOURCE prometheus (
    labels STRUCT < __name__ VARCHAR,
    instance VARCHAR,
    job VARCHAR >,
    name VARCHAR,
    timestamp TIMESTAMPTZ,
    value VARCHAR
) WITH (
    connector = 'kafka',
    topic = 'prometheus',
    properties.bootstrap.server = 'kafka:9092',
    scan.startup.mode = 'earliest'
) FORMAT PLAIN ENCODE JSON;

create source t (
  order_id varchar,
  customer_id varchar,
  products STRUCT <product_id VARCHAR, quantity integer>,
  total_amount double precision,
  timestamp varchar
) with (
  connector = 'kafka',
  topic = 'purchase',
  properties.bootstrap.server = 'message_queue:29092'
) FORMAT PLAIN ENCODE JSON;

create materialized view mv as select * from t;