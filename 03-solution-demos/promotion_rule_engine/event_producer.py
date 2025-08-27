#!/usr/bin/env python3
"""
Casino Real-time Promotion System - Kafka Producer
Generates sample casino events at 20 QPS (20 events per second)
"""

import json
import random
import time
from datetime import datetime
from confluent_kafka import Producer
import uuid
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class CasinoKafkaProducer:
    def __init__(self, bootstrap_servers='localhost:9092', topic='casino_events'):
        self.topic = topic
        self.config = {
            'bootstrap.servers': bootstrap_servers,
            'client.id': 'casino-producer',
            'batch.num.messages': 1000,
            'linger.ms': 100,
            'acks': 1,
            'compression.type': 'snappy'
        }
        
        # Member profiles for realistic data
        self.member_profiles = [
            {
                'member_id': 100000001,
                'card_tier': 'Platinum',
                'adt': 2000.00,
                'odt': 1800.00,
                'lodger': 500.00,
                'preferred_area': 'Pit01'
            },
            {
                'member_id': 100000002,
                'card_tier': 'Gold',
                'adt': 1500.00,
                'odt': 1200.00,
                'lodger': 200.00,
                'preferred_area': 'Pit02'
            },
            {
                'member_id': 100000003,
                'card_tier': 'Silver',
                'adt': 800.00,
                'odt': 750.00,
                'lodger': 100.00,
                'preferred_area': 'Slot01'
            },
            {
                'member_id': 100000004,
                'card_tier': 'Bronze',
                'adt': 300.00,
                'odt': 280.00,
                'lodger': 50.00,
                'preferred_area': 'Slot02'
            },
            {
                'member_id': 100000005,
                'card_tier': 'Platinum',
                'adt': 3500.00,
                'odt': 3200.00,
                'lodger': 800.00,
                'preferred_area': 'Pit01'
            },
            {
                'member_id': 100000006,
                'card_tier': 'Gold',
                'adt': 1200.00,
                'odt': 1100.00,
                'lodger': 150.00,
                'preferred_area': 'Pit03'
            },
            {
                'member_id': 100000007,
                'card_tier': 'Silver',
                'adt': 600.00,
                'odt': 550.00,
                'lodger': 75.00,
                'preferred_area': 'Slot02'
            },
            {
                'member_id': 100000008,
                'card_tier': 'Bronze',
                'adt': 450.00,
                'odt': 420.00,
                'lodger': 25.00,
                'preferred_area': 'Slot01'
            }
        ]
        
        self.areas = ['Pit01', 'Pit02', 'Pit03', 'Slot01', 'Slot02']
        self.event_types = ['signup', 'gaming', 'rating_update']
        
        # Initialize producer
        self.producer = Producer(self.config)
        
        # Event counters
        self.events_sent = 0
        self.start_time = time.time()

    def generate_signup_event(self, member):
        """Generate a new user signup event"""
        return {
            'event_id': int(uuid.uuid4().int & 0x7FFFFFFFFFFFFFFF),
            'member_id': member['member_id'],
            'event_type': 'signup',
            'event_dt': datetime.utcnow().isoformat() + 'Z',
            'area': member['preferred_area'],
            'gaming_value': 0.0,
            'rating_points': 0,
            'metadata': {
                'signup_method': random.choice(['mobile', 'web', 'kiosk']),
                'initial_tier': member['card_tier'],
                'source_campaign': f"CAMPAIGN_{random.randint(1, 5)}"
            }
        }

    def generate_gaming_event(self, member):
        """Generate a gaming event with realistic values"""
        # Gaming value based on member profile
        base_bet = member['adt'] * random.uniform(0.05, 0.15)
        gaming_value = round(base_bet * random.uniform(0.8, 1.2), 2)
        
        # Ensure gaming value is realistic
        gaming_value = max(50.0, min(gaming_value, member['adt'] * 0.5))
        
        return {
            'event_id': int(uuid.uuid4().int & 0x7FFFFFFFFFFFFFFF),
            'member_id': member['member_id'],
            'event_type': 'gaming',
            'event_dt': datetime.utcnow().isoformat() + 'Z',
            'area': random.choice(self.areas),
            'gaming_value': gaming_value,
            'rating_points': 0,
            'metadata': {
                'game_type': random.choice(['slots', 'blackjack', 'roulette', 'poker']),
                'session_duration_minutes': random.randint(15, 180),
                'device_type': random.choice(['mobile', 'desktop', 'terminal'])
            }
        }

    def generate_rating_update_event(self, member):
        """Generate a rating update event"""
        # Points based on member tier and activity
        base_points = {
            'Platinum': random.randint(50, 200),
            'Gold': random.randint(30, 120),
            'Silver': random.randint(15, 60),
            'Bronze': random.randint(5, 25)
        }
        
        rating_points = base_points[member['card_tier']]
        
        return {
            'event_id': int(uuid.uuid4().int & 0x7FFFFFFFFFFFFFFF),
            'member_id': member['member_id'],
            'event_type': 'rating_update',
            'event_dt': datetime.utcnow().isoformat() + 'Z',
            'area': member['preferred_area'],
            'gaming_value': 0.0,
            'rating_points': rating_points,
            'metadata': {
                'tier_change': random.choice(['upgrade', 'maintain', 'downgrade']),
                'points_source': random.choice(['gaming', 'promotion', 'loyalty']),
                'new_tier': member['card_tier']  # Could be different in real scenario
            }
        }

    def generate_event(self):
        """Generate a single casino event based on realistic probabilities"""
        member = random.choice(self.member_profiles)
        
        # Weighted event probabilities
        event_weights = {
            'signup': 0.05,      # 5% new signups
            'gaming': 0.85,      # 85% gaming events
            'rating_update': 0.10  # 10% rating updates
        }
        
        event_type = random.choices(
            list(event_weights.keys()),
            weights=list(event_weights.values())
        )[0]
        
        if event_type == 'signup':
            return self.generate_signup_event(member)
        elif event_type == 'gaming':
            return self.generate_gaming_event(member)
        else:  # rating_update
            return self.generate_rating_update_event(member)

    def delivery_report(self, err, msg):
        """Called once for each message produced to indicate delivery result"""
        if err is not None:
            logger.error(f'Message delivery failed: {err}')
        else:
            logger.debug(f'Message delivered to {msg.topic()} [{msg.partition()}]')

    def produce_events(self, target_qps=20):
        """Produce events at the specified QPS"""
        logger.info(f"Starting casino event producer at {target_qps} QPS")
        
        # Calculate sleep interval for target QPS
        sleep_interval = 1.0 / target_qps
        
        try:
            while True:
                event = self.generate_event()
                
                # Serialize to JSON
                message = json.dumps(event, ensure_ascii=False)
                
                # Produce to Kafka
                self.producer.produce(
                    topic=self.topic,
                    value=message.encode('utf-8'),
                    callback=self.delivery_report
                )
                
                self.events_sent += 1
                
                # Flush periodically to ensure delivery
                if self.events_sent % 100 == 0:
                    self.producer.flush()
                    logger.info(f"Sent {self.events_sent} events")
                
                # Poll to handle delivery reports
                self.producer.poll(0)
                
                # Sleep to maintain QPS
                time.sleep(sleep_interval)
                
        except KeyboardInterrupt:
            logger.info("Producer stopped by user")
        except Exception as e:
            logger.error(f"Producer error: {e}")
        finally:
            # Flush remaining messages
            self.producer.flush()
            
            elapsed = time.time() - self.start_time
            actual_qps = self.events_sent / elapsed if elapsed > 0 else 0
            
            logger.info(f"Producer finished. Sent {self.events_sent} events in {elapsed:.2f}s")
            logger.info(f"Actual QPS: {actual_qps:.2f}")

    def produce_batch(self, num_events=1000):
        """Produce a batch of events for testing"""
        logger.info(f"Producing {num_events} test events...")
        
        for i in range(num_events):
            event = self.generate_event()
            message = json.dumps(event, ensure_ascii=False)
            
            self.producer.produce(
                topic=self.topic,
                value=message.encode('utf-8'),
                callback=self.delivery_report
            )
            
            if i % 100 == 0:
                self.producer.flush()
                logger.info(f"Sent {i+1} events")
        
        self.producer.flush()
        logger.info(f"Batch complete: {num_events} events sent")

def main():
    """Main function to run the producer"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Casino Kafka Event Producer')
    parser.add_argument('--qps', type=int, default=20, help='Events per second (default: 20)')
    parser.add_argument('--bootstrap-servers', default='localhost:9092', help='Kafka bootstrap servers')
    parser.add_argument('--topic', default='casino_events', help='Kafka topic name')
    parser.add_argument('--batch', type=int, default=0, help='Send batch instead of continuous stream')
    
    args = parser.parse_args()
    
    producer = CasinoKafkaProducer(
        bootstrap_servers=args.bootstrap_servers,
        topic=args.topic
    )
    
    if args.batch > 0:
        producer.produce_batch(args.batch)
    else:
        producer.produce_events(target_qps=args.qps)

if __name__ == '__main__':
    main()
