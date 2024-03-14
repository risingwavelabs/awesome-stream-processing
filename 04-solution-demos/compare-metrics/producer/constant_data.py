import random
import json
import datetime
import time
import string
from confluent_kafka.admin import AdminClient, NewTopic
from confluent_kafka import Producer

rate_per_second = 5

kafka_config = {
    'bootstrap.servers': 'localhost:9092'
}

# Kafka producer
producer = Producer(kafka_config)

admin_client = AdminClient(kafka_config)

# Kafka topic to produce messages to
topic = 'purchase_constant'
partitions = 1
replication_factor = 1

# Create NewTopic object
new_topic = NewTopic(topic, num_partitions=partitions, replication_factor=replication_factor)

# Create topic
admin_client.create_topics([new_topic])

# Check if broker is available
def is_broker_available():
    global producer
    try:
        return True
    except Exception as e:
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

if __name__ == "__main__":

    try:
    # Produce messages to the Kafka topic
        while is_broker_available():

            message = generate_purchase_event()
            message_str = json.dumps(message)

            producer.produce(topic, message_str)

            time.sleep(1/rate_per_second)

    finally:

        print('Producer closed')

        # Wait for any outstanding messages to be delivered and delivery reports received
        producer.flush() 