#!/bin/zsh

kafka-topics --delete \
  --bootstrap-server localhost:9092 \
  --topic vital_signs \
  --if-exists

kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic vital_signs \
  --partitions 16 \
  --replication-factor 1 \
  --if-not-exists

mysql -u root -p -D medical_alerts < sql/mysql.sql
psql -h 0.0.0.0 -p 4566 -d dev -U root -f sql/rw.sql
