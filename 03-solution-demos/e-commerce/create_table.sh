#!/bin/zsh

kafka-topics --delete \
  --bootstrap-server localhost:9092 \
  --topic click-stream \
  --if-exists
kafka-topics --delete \
  --bootstrap-server localhost:9092 \
  --topic order-stream \
  --if-exists

kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic click-stream \
  --partitions 1 \
  --replication-factor 1 \
  --if-not-exists
kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic order-stream \
  --partitions 1 \
  --replication-factor 1 \
  --if-not-exists

psql -h 0.0.0.0 -p 4566 -d dev -U root -f sql/customer_segmentation.sql
