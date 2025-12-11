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
topic = 'web_clicks'

kafka_config = {
    'bootstrap_servers': ['kafka:9092']
}

# Kafka producer
producer = KafkaProducer(**kafka_config)

fake = Faker()

# Same product list as other producers (keep IDs aligned)
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

# Normalize popularity to probabilities and create weighted choices
total_popularity = sum(p["popularity"] for p in products)
for p in products:
    p["popularity"] /= total_popularity

product_choices = [p for p in products for _ in range(int(p["popularity"] * 1000))]

# Clickstream event distribution (heavier on 'view')
EVENT_TYPES = ["view", "add_to_cart", "remove_from_cart"]
EVENT_WEIGHTS = [0.82, 0.15, 0.03]

def generate_click_event():
    product = random.choice(product_choices)
    event_type = random.choices(EVENT_TYPES, weights=EVENT_WEIGHTS, k=1)[0]

    event = {
        "event_time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%SZ"),
        "product_id": product["product_id"],
        "event_type": event_type
    }
    return json.dumps(event)

if __name__ == "__main__":
    try:
        # Simulate bursts: short sleeps most of the time, occasional spikes
        while is_broker_available():
            payload = generate_click_event().encode("utf-8")
            producer.send(topic, payload)

            # Mostly fast clicks; sometimes a micro pause
            if random.random() < 0.90:
                time.sleep(random.uniform(0.1, 0.5))
            else:
                time.sleep(random.uniform(0.5, 1.5))

    finally:
        print("Producer closed")
        producer.flush()
        producer.close()
