from datetime import datetime, timedelta
from faker import Faker
import datagen
import random
import json
import time
from kafka import KafkaProducer

# Check if broker is available
def is_broker_available():
    global producer
    try:
        return True
    except Exception as e:
        print(f"Broker not available: {e}")
        return False

kafka_config = {
    'bootstrap_servers': ['message_queue:29092']
}

#kafka_topics = ['trucks', 'drivers', 'shipments', 'warehouses', 'route', 'fuel', 'maint']

faker = Faker("en_US")

producer = KafkaProducer(**kafka_config)

if __name__ == "__main__":

    try:
    # Produce messages to the Kafka topic
        while is_broker_available():

                truck_id = random.randint(1000, 99999)
                driver_id = random.randint(1000, 99999)
                warehouse_loc = faker.city()

                time.sleep(0.1)

                start_date = datetime.now() - timedelta(days=365)
                random_date = start_date + timedelta(days=random.randint(0, 365))

                time.sleep(0.1)

                truck = datagen.gen_truck(truck_id, driver_id)
                message_str = json.dumps(truck).encode('utf-8')
                producer.send('trucks', message_str)

                time.sleep(0.1)

                driver = datagen.gen_driver(driver_id, truck_id)
                message_str = json.dumps(driver).encode('utf-8')
                producer.send('drivers', message_str)

                time.sleep(0.1)

                shipments = datagen.gen_shipments(warehouse_loc, truck_id)
                message_str = json.dumps(shipments).encode('utf-8')
                producer.send('shipments', message_str)

                time.sleep(0.1)

                warehouse = datagen.gen_warehouses(warehouse_loc)
                message_str = json.dumps(warehouse).encode('utf-8')
                producer.send('warehouses', message_str)

                time.sleep(0.1)

                route = datagen.gen_route(truck_id, driver_id, random_date)
                message_str = json.dumps(route).encode('utf-8')
                producer.send('route', message_str)

                time.sleep(0.1)

                fuel = datagen.gen_fuel(truck_id, random_date)
                message_str = json.dumps(fuel).encode('utf-8')
                producer.send('fuel', message_str)

                time.sleep(0.1)

                maintenance = datagen.gen_maintenance(truck_id, random_date)
                message_str = json.dumps(maintenance).encode('utf-8')
                producer.send('maint', message_str)

                time.sleep(0.7)

    finally:
        print('Producer closed')

        # Wait for any outstanding messages to be delivered and delivery reports received
        producer.flush() 
        producer.close()
