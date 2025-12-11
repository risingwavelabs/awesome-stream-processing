import json
import datetime
import time
import random
from faker import Faker
from kafka import KafkaProducer

# Check if broker is available
def is_broker_available():
    global producer
    try:
        return True
    except Exception as e:
        print(f"Broker not available: {e}")
        return False

# Kafka topic to produce messages to
topic = 'purchases'

kafka_config = {
    'bootstrap_servers': ['kafka:9092']
}

# Kafka producer
producer = KafkaProducer(**kafka_config)

fake = Faker()

# Define product inventory with varying demand levels
products = [
    {"product_id": 1, "product_name": "Wireless Mouse", "popularity": 0.08},
    {"product_id": 2, "product_name": "Mechanical Keyboard", "popularity": 0.05},
    {"product_id": 3, "product_name": "27-inch Monitor", "popularity": 0.03},
    {"product_id": 4, "product_name": "USB-C Hub", "popularity": 0.10},
    {"product_id": 5, "product_name": "External SSD 1TB", "popularity": 0.07},
    {"product_id": 6, "product_name": "Gaming Headset", "popularity": 0.06},
    {"product_id": 7, "product_name": "Office Chair", "popularity": 0.02},
    {"product_id": 8, "product_name": "Laptop Stand", "popularity": 0.09},
    {"product_id": 9, "product_name": "Portable Projector", "popularity": 0.01},
    {"product_id": 10, "product_name": "Smartphone Tripod", "popularity": 0.11},
    {"product_id": 11, "product_name": "Bluetooth Speaker", "popularity": 0.07},
    {"product_id": 12, "product_name": "4K Webcam", "popularity": 0.05},
    {"product_id": 13, "product_name": "Portable Power Bank", "popularity": 0.12},
    {"product_id": 14, "product_name": "Wireless Earbuds", "popularity": 0.08},
    {"product_id": 15, "product_name": "Smartwatch", "popularity": 0.04},
    {"product_id": 16, "product_name": "Graphic Tablet", "popularity": 0.03},
    {"product_id": 17, "product_name": "Electric Standing Desk", "popularity": 0.02},
    {"product_id": 18, "product_name": "Noise-Canceling Headphones", "popularity": 0.06},
    {"product_id": 19, "product_name": "HDMI to USB-C Adapter", "popularity": 0.10},
    {"product_id": 20, "product_name": "Dual Monitor Arm", "popularity": 0.05},
]

# Normalize popularity values
total_popularity = sum(p["popularity"] for p in products)
for product in products:
    product["popularity"] /= total_popularity  # Convert to probability distribution

# Generate weighted list of product choices based on popularity
product_choices = [p for p in products for _ in range(int(p["popularity"] * 1000))]

def generate_purchase_event():
    product = random.choice(product_choices)  # Weighted random selection
    quantity = random.choices([1, 2, 3, 5, 10], weights=[60, 20, 10, 7, 3])[0]  # Skewed towards smaller quantities

    event = {
        "purchase_time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%SZ"),
        "product_id": product["product_id"],
        "quantity_purchased": quantity,
        "customer_id": fake.pystr_format()
    }
    
    return json.dumps(event)

if __name__ == "__main__":

    try:
        while is_broker_available():
            data = generate_purchase_event()
            message_str = data.encode('utf-8')
            producer.send(topic, message_str)
            time.sleep(1)

    finally:
        print('Producer closed')

        # Wait for any outstanding messages to be delivered and delivery reports received
        producer.flush() 
        producer.close()
