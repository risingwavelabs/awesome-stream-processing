import json
import random
import time
from kafka import KafkaProducer
from datetime import datetime

# Initialize Kafka producer
producer = KafkaProducer(
    bootstrap_servers=['localhost:9092'],
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

# Simulated device IDs, protocols, and IP prefixes
DEVICE_IDS = ['router-01', 'router-02', 'server-01', 'server-02', 'switch-01']
PROTOCOLS = ['TCP', 'UDP', 'ICMP', 'HTTP', 'HTTPS']
IP_PREFIXES = ['192.168.1.', '10.0.0.', '172.16.0.']

def generate_netflow_data():
    """Generate single NetFlow/sFlow record (includes normal and abnormal data)"""
    device_id = random.choice(DEVICE_IDS)
    # 10% chance to generate abnormal data (for testing anomaly detection)
    is_abnormal = random.random() < 0.1
    if is_abnormal:
        latency = random.uniform(100, 200)  # Abnormal: Latency > 100ms
        packet_loss_rate = random.uniform(5, 15)  # Abnormal: Packet loss > 5%
        bandwidth_usage = random.uniform(90, 100)  # Abnormal: Bandwidth usage > 90%
    else:
        latency = random.uniform(10, 50)  # Normal: Latency 10-50ms
        packet_loss_rate = random.uniform(0, 2)  # Normal: Packet loss 0-2%
        bandwidth_usage = random.uniform(30, 70)  # Normal: Bandwidth usage 30-70%

    return {
        "device_id": device_id,
        "timestamp": datetime.now().isoformat(),  # Timestamp
        "src_ip": f"{random.choice(IP_PREFIXES)}{random.randint(1, 254)}",
        "dst_ip": f"{random.choice(IP_PREFIXES)}{random.randint(1, 254)}",
        "protocol": random.choice(PROTOCOLS),
        "latency_ms": round(latency, 2),  # Network latency (ms)
        "packet_loss_rate": round(packet_loss_rate, 2),  # Packet loss rate (%)
        "bandwidth_usage_percent": round(bandwidth_usage, 2),  # Bandwidth usage (%)
        "flow_bytes": random.randint(1024, 1048576)  # Traffic bytes
    }

if __name__ == "__main__":
    print("Starting NetFlow data generation (press Ctrl+C to stop)...")
    try:
        while True:
            data = generate_netflow_data()
            producer.send('network_metrics', value=data)
            print(f"Sent data: {data}")
            time.sleep(1)  # Send 1 record per second (adjustable)
    except KeyboardInterrupt:
        print("\nStopped data generation")
        producer.close()
