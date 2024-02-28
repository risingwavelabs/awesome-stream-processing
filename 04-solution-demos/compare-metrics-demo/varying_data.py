import json
import random
import string
import datetime

from kafka import KafkaProducer

# Function to generate a random order ID
def generate_order_id():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))

# Function to generate a random customer ID
def generate_customer_id():
    return ''.join(random.choices(string.digits, k=5))

# Function to generate a random product ID
def generate_product_id():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))

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

# Kafka configuration, use localhost:29092 if running on your local device separately
kafka_config = {
    'bootstrap_servers': ['localhost:9092']
}

# Kafka producer
producer = KafkaProducer(**kafka_config)

def is_broker_available():
    global producer
    try:
        producer.close()
        return True
    except Exception as e:
        print(f"Broker not available: {e}")
        return False

print(is_broker_available())