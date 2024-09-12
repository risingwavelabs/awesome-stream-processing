import json
import datetime
from kafka import KafkaProducer
import time
import random

# Check if broker is available
def is_broker_available():
    global producer
    try:
        return True
    except Exception as e:
        print(f"Broker not available: {e}")
        return False

def simulate_energy_production(date: datetime.datetime) -> float:

    hour = date.hour
    minute = date.minute
    
    # Basic curve for solar production based on time of day (higher at noon)
    if 6 <= hour <= 18:  # Solar production only between 6 AM and 6 PM
        # Calculate time factor based on proximity to noon
        time_factor = max(0, 1 - abs(12 - (hour + minute / 60)) / 6)
    else:
        time_factor = 0  # No production at night

    month = date.month
    
    if month in [12, 1, 2]:  # Winter
        season_factor = 0.3
    elif month in [3, 4, 5]:  # Spring
        season_factor = 0.5
    elif month in [6, 7, 8]:  # Summer
        season_factor = 0.8
    elif month in [9, 10, 11]:  # Autumn
        season_factor = 0.6

    base_production = 0.05  

    fluctuation = random.uniform(0.6, 1.0)

    # Calculate the final production for the minute
    production = base_production * time_factor * season_factor * fluctuation
    
    return round(production, 3)

#current_time = datetime.datetime(1997, 5, 29, 12, 0, 0)
#print(simulate_energy_production(current_time))

# Kafka topic to produce messages to
topic = 'energy_produced'

kafka_config = {
    'bootstrap_servers': ['kafka:9092']
}
# Kafka producer
producer = KafkaProducer(**kafka_config)

if __name__ == "__main__":

    try:
    # Produce messages to the Kafka topic
        start = datetime.datetime.now()
        current_time = datetime.datetime(1997, 5, 1, 0, 0, 0)
        while is_broker_available():
            for meter_id in range(1, 21):
                energy_produced = simulate_energy_production(current_time)
                data = {
                    "production_time": current_time.strftime('%Y-%m-%dT%H:%M:%SZ'),
                    "meter_id": meter_id,
                    "energy_produced": energy_produced
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