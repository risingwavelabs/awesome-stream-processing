import json
import time
import random
from datetime import datetime
from kafka import KafkaProducer

# Kafka connection configuration
KAFKA_BOOTSTRAP_SERVERS = 'localhost:9092'
TOPIC_NAME = 'vital_signs'

# Initialize Kafka producer with JSON serialization
producer = KafkaProducer(
    bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

# Test patient/device identifiers
PATIENTS = ['P001', 'P002', 'P003']
DEVICES = ['D001', 'D002', 'D003']

# Global counter for simulating deteriorating vital sign trends
trend_counter = 0

def generate_vital_signs(patient_id):
    """Generate vital sign data (including normal/abnormal values)"""
    # Current time with millisecond precision (trim microseconds to 3 decimal places)
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]

    # Base normal values
    heart_rate = random.randint(60, 100)          # Normal: 60-100 bpm
    blood_oxygen = round(random.uniform(95, 98), 2) # Normal: 95-98%
    blood_glucose = round(random.uniform(4.5, 6.5), 2) # Normal: 4.5-6.5 mmol/L

    # Simulate abnormal values for different patients
    # P001: Blood glucose abnormality (1 in 10 readings) - diabetic patient
    if patient_id == 'P001' and random.randint(1, 10) == 5:
        blood_glucose = round(random.uniform(11.0, 13.0), 2)  # Abnormal: 11.0-13.0 mmol/L
    # P002: Heart rate abnormality (1 in 15 readings) - tachycardia
    elif patient_id == 'P002' and random.randint(1, 15) == 8:
        heart_rate = random.randint(125, 140)  # Abnormal: 125-140 bpm
    # P003: Blood oxygen abnormality (1 in 20 readings) - hypoxemia
    elif patient_id == 'P003' and random.randint(1, 20) == 10:
        blood_oxygen = round(random.uniform(88, 92), 2)  # Abnormal: 88-92%

    # Simulate deteriorating trend for P001 (5 consecutive readings: increasing HR, decreasing SpO2)
    global trend_counter
    if patient_id == 'P001' and 0 < trend_counter < 5:
        heart_rate += trend_counter * 5
        blood_oxygen -= trend_counter * 1.5
        trend_counter += 1
    elif trend_counter >= 5:
        trend_counter = 0  # Reset trend counter after 5 readings

    return {
        "patient_id": patient_id,
        "device_id": random.choice(DEVICES),
        "measure_time": now,
        "heart_rate": heart_rate,
        "blood_oxygen": blood_oxygen,
        "blood_glucose": blood_glucose,
    }

if __name__ == '__main__':
    try:
        # Continuously generate and send vital sign data
        while True:
            for patient in PATIENTS:
                vital_data = generate_vital_signs(patient)
                # Send data to Kafka topic
                producer.send(TOPIC_NAME, value=vital_data)
                # Print sent data (formatted for readability)
                print(f"Sent data: {json.dumps(vital_data, ensure_ascii=False)}")
            # Wait 1 second between batches (simulate real-time monitoring)
            time.sleep(1)
    except KeyboardInterrupt:
        # Gracefully close producer on Ctrl+C
        print("\nStopping producer...")
        producer.close()
        print("Producer closed successfully.")
