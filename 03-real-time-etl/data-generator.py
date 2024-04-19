import random
import json
from datetime import datetime, timezone
import time
from kafka import KafkaProducer

rate_per_second = 5

# Check if broker is available
def is_broker_available():
    global producer
    try:
        return True
    except Exception as e:
        print(f"Broker not available: {e}")
        return False

# Generate a random product ID
def generate_action():
    actions = ['click', 'scroll', 'view']
    return random.choice(actions)

# Generate random purchase event
def generate_purchase_event():
    action = generate_action()
    user_id = random.randint(1,10)
    page_id = random.randint(1,15)
    current_time_utc = datetime.now(timezone.utc)
    action_time = current_time_utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    return {
        "page_id": page_id,
        "user_id": user_id,
        "action": action,
        "action_time": action_time,
    }

# Kafka topic to produce messages to
topic = 'website_visits'

kafka_config = {
    'bootstrap_servers': ['localhost:9092']
}

# Kafka producer
producer = KafkaProducer(**kafka_config)

if __name__ == "__main__":

    try:
    # Produce messages to the Kafka topic
        while is_broker_available():

            message = generate_purchase_event()
            message_str = json.dumps(message).encode('utf-8')

            producer.send(topic, message_str)

            time.sleep(1/rate_per_second)

    finally:

        print('Producer closed')

        # Wait for any outstanding messages to be delivered and delivery reports received
        producer.flush() 
        producer.close() 