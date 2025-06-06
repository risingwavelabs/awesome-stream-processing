from kafka import KafkaProducer
from faker import Faker
import random
import json
import time
from datetime import datetime, timedelta

fake = Faker()
producer = KafkaProducer(
    bootstrap_servers='localhost:9092',
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)


def generate_sensor_data(speed, road_id):
    entry_time = datetime.now()
    occupancy = random.randint(300, 1000)
    return {
        "timestamp_entry": entry_time.isoformat(),
        "timestamp_exit": (entry_time + timedelta(milliseconds=occupancy / 1000)).isoformat(),
        "sensor_id": f"SEN{road_id}",
        "road_id": f"R{road_id}",
        "vehicle_speed_kph": speed,
    }

def generate_camera_data(speed, road_id):
    return {
        "timestamp": datetime.now().isoformat(),
        "device_id": f"CAM{road_id}",
        "road_id": f"R{road_id}",
        "vehicle_type": random.choice(["sedan", "truck", "bus", "motorcycle"]),
        "license_plate": fake.license_plate(),
        "vehicle_speed_kph": speed
    }

while True:
    speed = round(random.uniform(20, 80), 1)
    road_id = random.randint(1, 4)

    sensor_data = generate_sensor_data(speed, road_id)
    camera_data = generate_camera_data(speed, road_id)
    producer.send('sensor-data', sensor_data)
    producer.send('camera-data', camera_data)
    print("Produced:", sensor_data)
    print("Produced:", camera_data)
    time.sleep(0.5)
