import json
import datetime
import time
from kafka import KafkaProducer
import random

# Check if broker is available
def is_broker_available():
    global producer
    try:
        return True
    except Exception as e:
        print(f"Broker not available: {e}")
        return False

def simulate_energy_consumption(date: datetime.datetime) -> float:

    # Time of day factors
    hour = date.hour
    minute = date.minute
    
    # Basic curve for energy consumption based on time of day
    if 6 <= hour < 9:  # Morning peak (6 AM to 9 AM)
        time_factor = 1.4
    elif 17 <= hour < 21:  # Evening peak (5 PM to 9 PM)
        time_factor = 1.7
    elif 9 <= hour < 17:  # Daytime (9 AM to 5 PM)
        time_factor = 1.2
    elif 21 <= hour or hour < 6:  # Nighttime (9 PM to 6 AM)
        time_factor = 0.7
    else:
        time_factor = 0.5  # Default factor for any edge cases

    fluctuation = random.uniform(0.9, 1.1)

    base_consumption = 0.025 

    consumption = base_consumption * time_factor * fluctuation
    
    return round(consumption, 3)

# Kafka topic to produce messages to
topic = 'energy_consumed'

kafka_config = {
    'bootstrap_servers': ['kafka:9092']
}

"""current_time = datetime.datetime(1997, 5, 29, 0, 0, 0)
for meter_id in range(1, 4):
    for meter_id in range(1, 6):
        energy_consumed = simulate_energy_consumption(current_time)
        data = {
            "production_time": current_time.strftime('%Y-%m-%dT%H:%M:%SZ'),
            "meter_id": meter_id,
            "energy_consumed": energy_consumed
        }
        print(data)
    current_time += datetime.timedelta(minutes=1)"""

"""start = datetime.datetime.now()
print(start.day)"""

# Kafka producer
producer = KafkaProducer(**kafka_config)

if __name__ == "__main__":

    try:
    # Produce messages to the Kafka topic
        start = datetime.datetime.now()
        current_time = datetime.datetime(1997, 5, 1, 0, 0, 0)
        energy_consumed = simulate_energy_consumption(current_time)
        while is_broker_available():
            for meter_id in range(1, 21):
                data = {
                    "consumption_time": current_time.strftime('%Y-%m-%dT%H:%M:%SZ'),
                    "meter_id": meter_id,
                    "energy_consumed": energy_consumed
                }
                message_str = json.dumps(data).encode('utf-8')
                producer.send(topic, message_str)
            current_time += datetime.timedelta(minutes=1)
            if current_time.day != 1:
                time.sleep(0.8)

    finally:
        print('Producer closed')

        # Wait for any outstanding messages to be delivered and delivery reports received
        producer.flush() 
        producer.close()