from kafka import KafkaProducer
import json

# Kafka topic to produce messages to
topic = 'test'

# Kafka producer
producer = KafkaProducer(api_version=(0, 10, 1),bootstrap_servers= ['kafka:9092'])

# Produce messages to the Kafka topic
for i in range(3):
    message = {'key': f'key-{i}', 'value': f'value-{i}'}
    message_str = json.dumps(message)

    # Produce the message to the topic asynchronously
    producer.send(topic, message_str.encode('utf-8'))
    print(message)

# Wait for any outstanding messages to be delivered and delivery reports received
producer.flush()