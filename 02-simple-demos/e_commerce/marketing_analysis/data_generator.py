import json
import random
import time
import uuid
from datetime import datetime, timedelta, timezone
from kafka import KafkaProducer

producer = KafkaProducer(
    bootstrap_servers='localhost:29092',
    value_serializer=lambda v: json.dumps(v).encode('utf-8'),
    acks='all',
    retries=3,
    max_in_flight_requests_per_connection=1
)

NUM_CAMPAIGNS       = 10
EVENTS_PER_BATCH    = 50
BATCH_INTERVAL_SEC  = 2

CHANNELS     = ['email', 'social', 'search', 'display']
EVENT_TYPES  = ['impression', 'click', 'conversion']
UTM_SOURCES  = ['google', 'facebook', 'instagram', 'email', 'linkedin']
UTM_MEDIUMS  = ['cpc', 'organic', 'social', 'email', 'display']
CAMPAIGN_TYPES = ['regular', 'ab_test']
VARIANT_TYPES  = ['subject_line', 'creative', 'landing_page']

TOPIC_CAMPAIGNS        = 'campaigns'
TOPIC_VARIANTS         = 'ab_test_variants'
TOPIC_MARKETING_EVENTS = 'marketing_events'

campaign_info = {}
variant_info = {}

def now_ts():
    return datetime.now(timezone.utc).isoformat().replace('+00:00','Z')

def seed_campaigns(num_campaigns=NUM_CAMPAIGNS):
    """Emit campaigns (and AB variants) into Kafka once at startup."""
    ids = []
    for i in range(num_campaigns):
        cid = f"camp_{uuid.uuid4().hex[:8]}"
        ctype = random.choice(CAMPAIGN_TYPES)
        campaign = {
            "campaign_id":   cid,
            "campaign_name": f"Campaign {i+1}",
            "campaign_type": ctype,
            "start_date":    now_ts(),
            "end_date":      (datetime.now(timezone.utc) + timedelta(days=random.randint(1,30)))
                                .isoformat().replace('+00:00','Z'),
            "budget":        round(random.uniform(1000,10000),2),
            "target_audience": random.choice(['new_customers','existing_customers','all'])
        }
        producer.send(TOPIC_CAMPAIGNS, campaign)
        
        # Store campaign info
        campaign_info[cid] = ctype
        variant_info[cid] = []

        if ctype == 'ab_test':
            for variant in ['A','B','Control']:
                vid = str(uuid.uuid4())
                var = {
                    "variant_id":     vid,
                    "campaign_id":    cid,
                    "variant_name":   variant,
                    "variant_type":   random.choice(VARIANT_TYPES),
                    "content_details": f"Content for variant {variant}"
                }
                producer.send(TOPIC_VARIANTS, var)
                variant_info[cid].append(vid)

        ids.append(cid)

    producer.flush()
    print(f"Seeded {len(ids)} campaigns + variants")
    return ids

def generate_event(campaign_ids):
    """Build and send a single marketing event."""
    cid = random.choice(campaign_ids)
    et  = random.choices(
        population=['impression', 'click', 'conversion'],
        weights=[0.6, 0.3, 0.1],
        k=1
    )[0]
    
    # For A/B test campaigns, assign a variant_id
    variant_id = None
    if campaign_info.get(cid) == 'ab_test' and variant_info.get(cid):
        variant_id = random.choice(variant_info[cid])
    
    ev = {
        "event_id":     str(uuid.uuid4()),
        "user_id":      random.randint(1,1000),
        "campaign_id":  cid,
        "channel_type": random.choice(CHANNELS),
        "event_type":   et,
        "amount":       round(random.uniform(50,500),2) if et=='conversion' else 0,
        "utm_source":   random.choice(UTM_SOURCES),
        "utm_medium":   random.choice(UTM_MEDIUMS),
        "utm_campaign": cid,
        "variant_id":   variant_id,  # NEW: Add variant_id for A/B test events
        "timestamp":    now_ts()
    }
    producer.send(TOPIC_MARKETING_EVENTS, ev)

if __name__ == "__main__":
    # Seed campaigns
    campaign_ids = seed_campaigns()

    print("Starting marketing event stream...")
    try:
        while True:
            for _ in range(EVENTS_PER_BATCH):
                generate_event(campaign_ids)
            producer.flush()
            time.sleep(BATCH_INTERVAL_SEC)

    except KeyboardInterrupt:
        print("\nData generation stopped by user.")

    finally:
        producer.flush()
        producer.close()
        print("Kafka producer closed.")