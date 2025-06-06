kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic sensor-data \
  --partitions 1 \
  --replication-factor 1
kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic camera-data \
  --partitions 1 \
  --replication-factor 1
kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic traffic-flow \
  --partitions 1 \
  --replication-factor 1
kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic data-display \
  --partitions 1 \
  --replication-factor 1
