import random
import json
import datetime
import time
import string
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

# Generate a random order ID
def generate_order_id():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))

# Generate a random customer ID
def generate_customer_id():
    return ''.join(random.choices(string.digits, k=3))

# Generate a random product ID
def generate_product_id():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=2))

# Generate random purchase event
def generate_purchase_event():
    order_id = generate_order_id()
    customer_id = generate_customer_id()
    product = generate_product_id()
    quantity = random.randint(1,5)
    timestamp = datetime.datetime.now().isoformat()
    total_amount = round(random.uniform(10, 100) * quantity, 2)  # Random total amount
    return {
        "order_id": order_id,
        "customer_id": customer_id,
        "prod": product,
        "quant_in": quantity,
        "ts": timestamp,
        "tot_amnt_in": total_amount
    }

# Kafka topic to produce messages to
topic = 'purchase_constant'

kafka_config = {
    'bootstrap_servers': ['kafka:29093']
}
time.sleep(3)
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