#!/bin/zsh

kafka-topics --delete \
  --bootstrap-server localhost:9092 \
  --topic gps_stream \
  --if-exists
kafka-topics --delete \
  --bootstrap-server localhost:9092 \
  --topic traffic_stream \
  --if-exists
kafka-topics --delete \
  --bootstrap-server localhost:9092 \
  --topic order_stream \
  --if-exists

kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic gps_stream \
  --partitions 16 \
  --replication-factor 1 \
  --if-not-exists
kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic traffic_stream \
  --partitions 16 \
  --replication-factor 1 \
  --if-not-exists
kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic order_stream \
  --partitions 16 \
  --replication-factor 1 \
  --if-not-exists


psql -h 0.0.0.0 -p 4566 -d dev -U root -f sql/rw.sql

npm install
