import random
import time
import json
import paho.mqtt.client as mqtt

def generate_value(normal_range, normal_percentage, abnormal_multiplier=1.5, integer=False):
    if random.random() < (1 - normal_percentage):
        value = random.uniform(normal_range[1], normal_range[1] * abnormal_multiplier)
    else:
        deviation_percentage = random.uniform(-0.03, 0.03)
        value = normal_range[0] + (normal_range[1] - normal_range[0]) * (1 + deviation_percentage)
    return round(value, 2) if not integer else int(value)

def generate_machine_data(machine_id, normal_percentage=0.9):
    data = {
        "machine_id": f"machine_{machine_id}",
        "winding_temperature": generate_value((50, 80), normal_percentage, abnormal_multiplier=1.25, integer=True),
        "ambient_temperature": generate_value((30, 40), normal_percentage, abnormal_multiplier=1.25, integer=True),
        "vibration_level": generate_value((0.1, 2), normal_percentage, abnormal_multiplier=1.5),
        "current_draw": generate_value((1.9, 14.4), normal_percentage, abnormal_multiplier=1.5),
        "voltage_level": generate_value((45.6, 50.4), normal_percentage, abnormal_multiplier=1.25),
        "nominal_speed": generate_value((3800, 4200), normal_percentage, abnormal_multiplier=1.25),
        "power_consumption": generate_value((586, 645), normal_percentage, abnormal_multiplier=1.25),
        "efficiency": generate_value((75, 83), normal_percentage, abnormal_multiplier=0.5),
        "ts": time.strftime('%Y-%m-%d %H:%M:%S')
    }
    return data

def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print("Connected to MQTT Broker!")
    else:
        print(f"Failed to connect, return code {rc}")

def monitor_machines(machine_count, mqtt_broker, mqtt_port, normal_percentage=0.9, interval=2):
    client = mqtt.Client()
    client.on_connect = on_connect
    client.connect(mqtt_broker, mqtt_port, 60)
    client.loop_start()
    while True:
        for machine_id in range(1, machine_count + 1):
            data = generate_machine_data(machine_id, normal_percentage)
            client.publish(f"factory/machine_data", json.dumps(data))
            print(f"Published data for Machine {machine_id}: {data}")

        time.sleep(interval)

if __name__ == "__main__":

    # Parameters
    MACHINE_COUNT = 5  # Number of machines
    MQTT_BROKER = "mqtt-server"  # Broker address
    MQTT_PORT = 1883
    NORMAL_PERCENTAGE = 0.9  # Percentage of normal values
    INTERVAL = 5  # Interval in seconds

    monitor_machines(MACHINE_COUNT, MQTT_BROKER, MQTT_PORT, NORMAL_PERCENTAGE, INTERVAL)
