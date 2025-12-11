import json
import datetime
import time
import random
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
topic = 'competitor_prices'

kafka_config = {
    'bootstrap_servers': ['kafka:9092']
}

# Kafka producer
producer = KafkaProducer(**kafka_config)

# Same products; attach a plausible base price (USD) for each
products = [
    {"product_id": 1, "product_name": "Wireless Mouse", "base_price": 19.99},
    {"product_id": 2, "product_name": "Mechanical Keyboard", "base_price": 79.99},
    {"product_id": 3, "product_name": "27-inch Monitor", "base_price": 229.99},
    {"product_id": 4, "product_name": "USB-C Hub", "base_price": 34.99},
    {"product_id": 5, "product_name": "External SSD 1TB", "base_price": 99.99},
    {"product_id": 6, "product_name": "Gaming Headset", "base_price": 59.99},
    {"product_id": 7, "product_name": "Office Chair", "base_price": 149.99},
    {"product_id": 8, "product_name": "Laptop Stand", "base_price": 24.99},
    {"product_id": 9, "product_name": "Portable Projector", "base_price": 299.99},
    {"product_id": 10, "product_name": "Smartphone Tripod", "base_price": 17.99},
    {"product_id": 11, "product_name": "Bluetooth Speaker", "base_price": 49.99},
    {"product_id": 12, "product_name": "4K Webcam", "base_price": 89.99},
    {"product_id": 13, "product_name": "Portable Power Bank", "base_price": 29.99},
    {"product_id": 14, "product_name": "Wireless Earbuds", "base_price": 59.99},
    {"product_id": 15, "product_name": "Smartwatch", "base_price": 179.99},
    {"product_id": 16, "product_name": "Graphic Tablet", "base_price": 139.99},
    {"product_id": 17, "product_name": "Electric Standing Desk", "base_price": 349.99},
    {"product_id": 18, "product_name": "Noise-Canceling Headphones", "base_price": 199.99},
    {"product_id": 19, "product_name": "HDMI to USB-C Adapter", "base_price": 14.99},
    {"product_id": 20, "product_name": "Dual Monitor Arm", "base_price": 89.99},
]

# A few competitor names
competitors = ["ShopA", "ShopB", "ShopC", "ShopD"]

# Maintain last price per (competitor, product) for a gentle random walk
last_prices = {}
for c in competitors:
    for p in products:
        # Initialize around base_price with small jitter
        jitter = random.uniform(-0.05, 0.05)  # ±5%
        last_prices[(c, p["product_id"])] = round(p["base_price"] * (1 + jitter), 2)

def next_price(prev, base):
    """
    Small random walk around previous price with slight pull toward base.
    Occasional larger shocks to mimic promos/surges.
    """
    # Mean-revert gently toward base price
    pull = 0.1 * (base - prev)
    step = random.uniform(-0.01, 0.01) * prev  # ±1%
    price = prev + pull + step

    # Occasional promo/surge
    if random.random() < 0.03:
        price *= random.choice([0.9, 1.1])  # ±10%

    # Clamp to a sensible band relative to base
    lower = 0.6 * base
    upper = 1.4 * base
    price = min(max(price, lower), upper)
    return round(price, 2)

def generate_competitor_event():
    comp = random.choice(competitors)
    prod = random.choice(products)
    key = (comp, prod["product_id"])
    new_p = next_price(last_prices[key], prod["base_price"])
    last_prices[key] = new_p

    event = {
        "ts": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%SZ"),
        "product_id": prod["product_id"],
        "competitor": comp,
        "competitor_price": new_p
    }
    return json.dumps(event)

if __name__ == "__main__":
    try:
        while is_broker_available():
            payload = generate_competitor_event().encode("utf-8")
            producer.send(topic, payload)

            # Competitor feeds update more slowly than clicks
            time.sleep(random.uniform(2.0, 6.0))

    finally:
        print("Producer closed")
        producer.flush()
        producer.close()
