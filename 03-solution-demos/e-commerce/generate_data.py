import json
import random
import time
from datetime import datetime, timedelta
from kafka import KafkaProducer

producer = KafkaProducer(
    bootstrap_servers=['localhost:9092'],
    value_serializer=lambda x: json.dumps(x).encode('utf-8')
)

HIGH_PRICE_PRODUCTS = [
    {"id": "P001", "name": "Smartphone", "price": 6999.99, "category": "/electronics/phone"},
    {"id": "P002", "name": "Laptop", "price": 9999.99, "category": "/electronics/laptop"},
    {"id": "P003", "name": "Digital Camera", "price": 3499.99, "category": "/electronics/camera"},
    {"id": "P004", "name": "Leather Jacket", "price": 1999.99, "category": "/clothing/jacket"},
    {"id": "P005", "name": "Coffee Maker", "price": 1299.99, "category": "/home/appliance"},
    {"id": "P006", "name": "Wireless Headphones", "price": 1499.99, "category": "/electronics/audio"},
]

MEDIUM_PRICE_PRODUCTS = [
    {"id": "P007", "name": "Running Shoes", "price": 799.99, "category": "/footwear/running"},
    {"id": "P008", "name": "Sneakers", "price": 699.99, "category": "/footwear/sneakers"},
    {"id": "P009", "name": "Smart Watch", "price": 2499.99, "category": "/electronics/watch"},
    {"id": "P010", "name": "Bluetooth Speaker", "price": 899.99, "category": "/electronics/speaker"},
    {"id": "P011", "name": "Backpack", "price": 899.99, "category": "/accessories/backpack"},
]

LOW_PRICE_PRODUCTS = [
    {"id": "P012", "name": "Basic Socks", "price": 49.99, "category": "/clothing/socks"},
    {"id": "P013", "name": "Phone Case", "price": 89.99, "category": "/accessories/phone-case"},
    {"id": "P014", "name": "USB Charger", "price": 79.99, "category": "/electronics/charger"},
    {"id": "P015", "name": "Notebook", "price": 39.99, "category": "/office/notebook"},
    {"id": "P016", "name": "Pen Set", "price": 59.99, "category": "/office/pen"},
    {"id": "P017", "name": "Hair Band", "price": 29.99, "category": "/accessories/hair"},
    {"id": "P018", "name": "Keychain", "price": 19.99, "category": "/accessories/keychain"},
    {"id": "P019", "name": "Face Mask", "price": 39.99, "category": "/health/mask"},
    {"id": "P020", "name": "Hand Sanitizer", "price": 49.99, "category": "/health/sanitizer"},
    {"id": "P021", "name": "Sunglasses", "price": 199.99, "category": "/accessories/sunglasses"},
    {"id": "P022", "name": "Phone Screen Protector", "price": 59.99, "category": "/accessories/screen-protector"},
    {"id": "P023", "name": "Water Bottle", "price": 129.99, "category": "/sports/water-bottle"},
]

ORDER_STATUSES = ["completed", "cancelled"]
ORDER_PROBABILITIES = [0.90, 0.10]


def random_event_time(round):
    now = datetime.now()
    if round == 1:
        random_time = now - timedelta(seconds=random.randint(0, 10 * 24 * 60 * 60))
    elif round == 2:
        random_time = now - timedelta(seconds=random.randint(10 * 24 * 60 * 60, 60 * 24 * 60 * 60))
    else:
        random_time = now - timedelta(seconds=random.randint(60 * 24 * 60 * 60, 90 * 24 * 60 * 60))
    return random_time.strftime("%Y-%m-%d %H:%M:%S")


def random_user_id(round):
    if round == 1:
        USER_IDS = [f"U{i:05d}" for i in range(1, 501)]  # first round - user 1-500
    elif round == 2:
        USER_IDS = [f"U{i:05d}" for i in range(100, 501)]  # second round - user 100-500
    else:
        USER_IDS = [f"U{i:05d}" for i in range(100, 601)]  # third round - user 100-600
    return random.choice(USER_IDS)


def generate_user_session(round):
    user_id = random_user_id(round)

    price_category = random.choices(
        ["low", "medium", "high"],
        weights=[0.80, 0.18, 0.02],
        k=1
    )[0]

    if price_category == "low":
        product = random.choice(LOW_PRICE_PRODUCTS)
    elif price_category == "medium":
        product = random.choice(MEDIUM_PRICE_PRODUCTS)
    else:
        product = random.choice(HIGH_PRICE_PRODUCTS)

    events = []

    event_id = f"E{random.randint(10000, 99999)}"
    event_time = random_event_time(round)

    events.append({
        "user_id": user_id,
        "event_id": event_id,
        "event_type": "view",
        "page_url": product["category"],
        "product_id": product["id"],
        "price": product["price"],
        "product_name": product["name"],
        "event_time": event_time,
    })

    prev_event_type = "view"

    for _ in range(3):
        next_event_type = None

        if prev_event_type == "view":
            rand = random.random()
            if rand < 0.30:
                next_event_type = "cart"
            elif rand < 0.40:
                next_event_type = "purchase"
            else:
                break

        elif prev_event_type == "cart":
            if random.random() < 0.35:
                next_event_type = "purchase"
            else:
                break

        elif prev_event_type == "purchase":
            break

        if next_event_type:
            event_id = f"E{random.randint(10000, 99999)}"

            prev_time = datetime.strptime(event_time, "%Y-%m-%d %H:%M:%S")
            event_time = (prev_time + timedelta(seconds=random.randint(1, 300))).strftime("%Y-%m-%d %H:%M:%S")

            events.append({
                "user_id": user_id,
                "event_id": event_id,
                "event_type": next_event_type,
                "page_url": product["category"],
                "product_id": product["id"],
                "price": product["price"],
                "product_name": product["name"],
                "event_time": event_time,
            })

            prev_event_type = next_event_type

    return events


def generate_order(event):
    if event["event_type"] != "purchase":
        return None

    order_id = f"{random.randint(10000, 99999)}"

    order_status = random.choices(
        ORDER_STATUSES,
        weights=ORDER_PROBABILITIES,
        k=1
    )[0]

    order_time = event["event_time"]

    order = {
        "order_id": order_id,
        "event_id": event["event_id"],
        "user_id": event["user_id"],
        "order_status": order_status,
        "price": event["price"],
        "order_time": order_time,
    }
    return order


def send_to_kafka(num_sessions, round):
    event_topic = "click-stream"
    order_topic = "order-stream"

    for _ in range(num_sessions):
        events = generate_user_session(round)

        for event in events:
            print(event)
            producer.send(event_topic, value=event)

            if event["event_type"] == "purchase":
                order = generate_order(event)
                if order:
                    print(order)
                    producer.send(order_topic, value=order)

        time.sleep(0.001)


if __name__ == "__main__":
    print("Start generating data...")
    send_to_kafka(1000, 1)  # 第一轮生成1000个会话
    send_to_kafka(10000, 2)  # 10000 samples for round 2
    send_to_kafka(3000, 3)  # 第三轮生成3000个会话
    print("Succeed to generate data!")
