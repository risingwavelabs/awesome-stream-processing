#!/bin/zsh

kafka-topics --delete \
  --bootstrap-server localhost:9092 \
  --topic network_metrics \
  --if-exists

kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic network_metrics \
  --partitions 16 \
  --replication-factor 1 \
  --if-not-exists

psql -h 0.0.0.0 -p 4566 -d dev -U root -f sql/rw.sql
