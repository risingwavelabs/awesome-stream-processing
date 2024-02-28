import random
import json
import datetime
import time
import string
from kafka import KafkaProducer

rate_per_second = 20

kafka_config = {
    'bootstrap_servers': ['localhost:9092']
}

# Kafka producer
producer = KafkaProducer(**kafka_config)

# Check if broker is available
def is_broker_available():
    global producer
    try:
        return True
    except Exception as e:
        print(f"Broker not available: {e}")
        return False
    
# pause producer 
def wait_until():
    current_time = datetime.datetime.now().second
    
    if current_time <= 30:
        wait = 30 - current_time
    elif current_time < 60:
        wait = 60 - current_time

    print(current_time, wait)
    # Otherwise, wait until the target time is reached
    time.sleep(wait)

# Generate a random order ID
def generate_order_id():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))

# Generate a random customer ID
def generate_customer_id():
    return ''.join(random.choices(string.digits, k=5))

# Generate a random product ID
def generate_product_id():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))

# Generate random purchase event
def generate_purchase_event():
    order_id = generate_order_id()
    customer_id = generate_customer_id()
    products = {"product_id": generate_product_id(), "quantity": random.randint(1, 5)}
    timestamp = datetime.datetime.now().isoformat()
    total_amount = round(sum([random.uniform(10, 100) for _ in range(len(products))]), 2)  # Random total amount
    return {
        "order_id": order_id,
        "customer_id": customer_id,
        "products": products,
        "timestamp": timestamp,
        "total_amount": total_amount
    }

# Kafka topic to produce messages to
topic = 'purchase_varying'

if __name__ == "__main__":

    # Produce messages to the Kafka topic
    while is_broker_available():

        if 0 <= datetime.datetime.now().second < 15 or 30 <= datetime.datetime.now().second < 45:

            message = generate_purchase_event()
            message_str = json.dumps(message).encode('utf-8')
            # Produce the message to the topic asynchronously
            producer.send(topic, message_str)
            time.sleep(1/rate_per_second)

        else:
            wait_until()

    print('Producer closed')

    # Wait for any outstanding messages to be delivered and delivery reports received
    producer.flush() 
    producer.close()
