import random
from datetime import datetime, timedelta, timezone
from faker import Faker

faker = Faker("en_US")

COUNTRIES = ["US", "DE", "PK", "GB", "AE", "CA"]
CITIES = ["Karachi", "Lahore", "Berlin", "London", "Dubai", "Toronto", "New York", "Munich"]
REGIONS = ["Sindh", "Punjab", "Berlin", "England", "Dubai", "Ontario", "NY", "Bavaria"]

DEVICE_TYPES = ["desktop", "mobile", "tablet"]
OS_LIST = ["Windows", "macOS", "Linux", "Android", "iOS"]
BROWSERS = ["Chrome", "Safari", "Firefox", "Edge"]

SOURCES = [
  ("google", "cpc"),
  ("twitter", "social"),
  ("newsletter", "email"),
  ("reddit", "social"),
  ("direct", "none"),
]
CAMPAIGNS = ["winter_sale", "onboarding", "flash_deal", "content_push", "retargeting"]
CONTENTS = ["banner_a", "banner_b", "cta_blue", "cta_orange"]
TERMS = ["running_shoes", "laptop_deals", "phone_discount", "streaming_sql", "none"]

PRODUCTS = [
  ("P-1001", "electronics", "/products/laptop"),
  ("P-1002", "electronics", "/products/phone"),
  ("P-2001", "apparel", "/products/shoes"),
  ("P-3001", "home", "/products/coffee-maker"),
]

STATIC_PAGES = [
  ("/", "home"),
  ("/search", "search"),
  ("/blog/streaming", "blog"),
  ("/cart", "cart"),
  ("/checkout", "checkout"),
]

def now_utc():
    return datetime.now(timezone.utc)

def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def gen_user(user_id: int):
    signup = now_utc() - timedelta(days=random.randint(1, 365))
    return {
        "user_id": user_id,
        "full_name": faker.name(),
        "email": faker.email(),
        "country": random.choice(COUNTRIES),
        "signup_time": iso(signup),
        "marketing_opt_in": random.random() < 0.55,
        "ingested_at": iso(now_utc()),
    }

def gen_device():
    device_id = faker.bothify(text="DEV-########")
    dt = random.choice(DEVICE_TYPES)
    os_ = random.choice(OS_LIST)
    br = random.choice(BROWSERS)
    ua = f"{br}/{random.randint(90,130)} ({os_}; {dt})"
    return device_id, {
        "device_id": device_id,
        "device_type": dt,
        "os": os_,
        "browser": br,
        "user_agent": ua,
        "ingested_at": iso(now_utc()),
    }

def gen_campaign():
    campaign_id = faker.bothify(text="CMP-######")
    source, medium = random.choice(SOURCES)
    return campaign_id, {
        "campaign_id": campaign_id,
        "source": source,
        "medium": medium,
        "campaign": random.choice(CAMPAIGNS),
        "content": random.choice(CONTENTS),
        "term": random.choice(TERMS),
        "ingested_at": iso(now_utc()),
    }

def gen_session(session_id: str, user_id: int, device_id: str):
    start = now_utc() - timedelta(seconds=random.randint(0, 600))
    i = random.randrange(len(CITIES))
    return {
        "session_id": session_id,
        "user_id": user_id,
        "device_id": device_id,
        "session_start": iso(start),
        "ip_address": faker.ipv4_public(),
        "geo_city": CITIES[i],
        "geo_region": REGIONS[i],
        "ingested_at": iso(now_utc()),
    }

def gen_page_catalog_records():
    # produce a small static catalog: home/search/blog/cart/checkout + product pages
    records = []
    for url, cat in STATIC_PAGES:
        records.append({
            "page_url": url,
            "page_category": cat,
            "product_id": None,
            "product_category": None,
            "ingested_at": iso(now_utc()),
        })
    for pid, pcat, url in PRODUCTS:
        records.append({
            "page_url": url,
            "page_category": "product",
            "product_id": pid,
            "product_category": pcat,
            "ingested_at": iso(now_utc()),
        })
    return records

def _event(event_id: str, user_id: int, session_id: str, event_type: str, page_url: str,
           event_time: datetime, campaign_id: str, referrer: str, element_id: str, revenue: float):
    return {
        "event_id": event_id,
        "user_id": user_id,
        "session_id": session_id,
        "event_type": event_type,
        "page_url": page_url,
        "element_id": element_id,
        "event_time": iso(event_time),
        "referrer": referrer,
        "campaign_id": campaign_id,
        "revenue_usd": revenue,
        "ingested_at": iso(now_utc()),
    }

def gen_session_journey(user_id: int, session_id: str, campaign_id: str):
    """
    A realistic journey:
      - land on home/search/blog
      - view 1-4 products
      - click(s), maybe add_to_cart, maybe checkout, sometimes purchase
    Includes dwell time and occasional late/out-of-order timestamps.
    """
    t0 = now_utc() - timedelta(seconds=random.randint(0, 15))
    ref = faker.url() if random.random() < 0.65 else ""
    events = []

    # landing page
    landing_url, _ = random.choice(STATIC_PAGES[:3])  # home/search/blog
    events.append(_event(
        event_id=faker.bothify("EVT-########"),
        user_id=user_id,
        session_id=session_id,
        event_type="page_view",
        page_url=landing_url,
        event_time=t0,
        campaign_id=campaign_id,
        referrer=ref,
        element_id="",
        revenue=0.0
    ))

    # browse 1-4 products
    n_products = random.randint(1, 4)
    product_choices = random.sample(PRODUCTS, k=n_products)
    current = t0

    for pid, pcat, url in product_choices:
        current += timedelta(seconds=random.randint(3, 25))
        events.append(_event(
            faker.bothify("EVT-########"), user_id, session_id, "page_view",
            url, current, campaign_id, "", "", 0.0
        ))

        # click on CTA
        if random.random() < 0.75:
            current += timedelta(seconds=random.randint(1, 10))
            events.append(_event(
                faker.bothify("EVT-########"), user_id, session_id, "click",
                url, current, campaign_id, "", random.choice(["cta_add_to_cart", "cta_details", "cta_buy_now"]), 0.0
            ))

        # maybe add to cart (higher probability on product page)
        if random.random() < 0.35:
            current += timedelta(seconds=random.randint(1, 8))
            events.append(_event(
                faker.bothify("EVT-########"), user_id, session_id, "add_to_cart",
                "/cart", current, campaign_id, "", f"add_{pid}", 0.0
            ))

            # maybe checkout
            if random.random() < 0.45:
                current += timedelta(seconds=random.randint(2, 15))
                events.append(_event(
                    faker.bothify("EVT-########"), user_id, session_id, "checkout_start",
                    "/checkout", current, campaign_id, "", "checkout_start", 0.0
                ))

                # sometimes purchase
                if random.random() < 0.35:
                    current += timedelta(seconds=random.randint(5, 30))
                    revenue = round(random.uniform(15, 650), 2)
                    events.append(_event(
                        faker.bothify("EVT-########"), user_id, session_id, "purchase",
                        "/checkout", current, campaign_id, "", "purchase_confirm", revenue
                    ))

    # add a small chance of "late events" (client clock / network delays)
    if random.random() < 0.08 and len(events) >= 3:
        # pick one mid event and push its event_time earlier, simulating out-of-order arrival
        idx = random.randint(1, len(events)-2)
        dt = faker.random_int(min=10, max=90)
        # parse event_time by shifting the stored string is annoying; just rebuild it:
        # We approximate by subtracting seconds from current timestamp baseline.
        # This keeps demo simple.
        # (We change only event_time; ingested_at still "now".)
        # WARNING: event_time becomes earlier than neighbors.
        # Recreate with shifted time:
        # We'll just modify the ISO string directly:
        # (Keep it simple: set it to t0 + small delta)
        shifted = t0 + timedelta(seconds=random.randint(1, 5))
        events[idx]["event_time"] = iso(shifted)

    return events
