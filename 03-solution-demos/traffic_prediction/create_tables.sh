#!/bin/zsh

kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic sensor-data \
  --partitions 1 \
  --replication-factor 1 \
  --if-not-exists
kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic camera-data \
  --partitions 1 \
  --replication-factor 1 \
  --if-not-exists
kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic traffic-flow \
  --partitions 1 \
  --replication-factor 1 \
  --if-not-exists
kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic data-display \
  --partitions 1 \
  --replication-factor 1 \
  --if-not-exists

psql -h 0.0.0.0 -p 4566 -d dev -U root -f sql/traffic_feature.sql
