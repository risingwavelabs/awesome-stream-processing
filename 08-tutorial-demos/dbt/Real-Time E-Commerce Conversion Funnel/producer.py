import json
import time
import random
from datetime import datetime
from kafka import KafkaProducer

# 配置 Kafka (假设运行在本地默认端口)
producer = KafkaProducer(
    bootstrap_servers=['localhost:9092'],
    value_serializer=lambda x: json.dumps(x).encode('utf-8')
)

TOPICS = ['page_views', 'cart_events', 'purchases']

def get_timestamp():
    return datetime.now().strftime('%Y-%m-%d %H:%M:%S')

print("Starting data generation... Press Ctrl+C to stop.")

try:
    while True:
        user_id = random.randint(1, 100)
        current_time = get_timestamp()

        # 1. 产生浏览数据 (频率最高)
        view_data = {
            "user_id": user_id,
            "page_id": f"page_{random.randint(1, 20)}",
            "event_time": current_time
        }
        producer.send('page_views', value=view_data)

        # 2. 产生加购数据 (约 30% 概率)
        if random.random() < 0.3:
            cart_data = {
                "user_id": user_id,
                "item_id": f"item_{random.randint(100, 200)}",
                "event_time": current_time
            }
            producer.send('cart_events', value=cart_data)

        # 3. 产生购买数据 (约 10% 概率)
        if random.random() < 0.1:
            purchase_data = {
                "user_id": user_id,
                "amount": round(random.uniform(10, 500), 2),
                "event_time": current_time
            }
            producer.send('purchases', value=purchase_data)

        print(f"Sent events for User {user_id} at {current_time}")
        time.sleep(1) # 每秒发送一次批次

except KeyboardInterrupt:
    print("\nStopping data generation.")
    producer.close()