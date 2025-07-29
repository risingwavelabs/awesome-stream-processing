import json
import time
import random
from datetime import datetime, timedelta
from kafka import KafkaProducer
from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import TopicAlreadyExistsError

class ProductSalesGenerator:
    def __init__(self, kafka_bootstrap_servers='localhost:9092'):
        self.kafka_bootstrap_servers = kafka_bootstrap_servers
        
        # Create topic first
        self.create_topic()
        
        self.kafka_producer = KafkaProducer(
            bootstrap_servers=[kafka_bootstrap_servers],
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            key_serializer=lambda v: v.encode('utf-8') if v else None
        )
        
        # Product catalog
        self.products = {
            "LAPTOP001": {"name": "MacBook Pro M3", "category": "Electronics", "price": 1999.99, "cost": 1200.00},
            "PHONE002": {"name": "iPhone 15 Pro", "category": "Electronics", "price": 999.99, "cost": 600.00},
            "HEADPHONE003": {"name": "AirPods Pro", "category": "Electronics", "price": 249.99, "cost": 150.00},
            "BOOK004": {"name": "Data Engineering Book", "category": "Books", "price": 49.99, "cost": 15.00},
            "SHIRT005": {"name": "Cotton T-Shirt", "category": "Clothing", "price": 29.99, "cost": 8.00},
            "SHOES006": {"name": "Running Shoes", "category": "Clothing", "price": 129.99, "cost": 40.00},
            "COFFEE007": {"name": "Premium Coffee Beans", "category": "Food", "price": 24.99, "cost": 8.00},
            "MONITOR008": {"name": "4K Monitor", "category": "Electronics", "price": 599.99, "cost": 300.00},
            "KEYBOARD009": {"name": "Mechanical Keyboard", "category": "Electronics", "price": 149.99, "cost": 60.00},
            "MOUSE010": {"name": "Wireless Mouse", "category": "Electronics", "price": 79.99, "cost": 25.00}
        }
        
        # Customer segments
        self.customer_segments = ["Premium", "Regular", "Budget", "Enterprise"]
         
        # Geographic regions
        self.regions = ["North America", "Europe", "Asia Pacific", "Latin America", "Middle East"]
        
        # Sales channels
        self.channels = ["Online", "Retail Store", "Mobile App", "Partner"]
        
        # Payment methods
        self.payment_methods = ["Credit Card", "PayPal", "Apple Pay", "Bank Transfer", "Cash"]
        
    def create_topic(self):
        """Create the product_sales Kafka topic"""
        admin_client = KafkaAdminClient(
            bootstrap_servers=self.kafka_bootstrap_servers,
            client_id='product_sales_generator'
        )
        
        topic = NewTopic(name='product_sales', num_partitions=3, replication_factor=1)
        
        try:
            admin_client.create_topics([topic])
            print(f"✅ Created topic: {topic.name}")
        except TopicAlreadyExistsError:
            print(f"ℹ️ Topic {topic.name} already exists")
        except Exception as e:
            print(f"❌ Error creating topic {topic.name}: {e}")
        
        admin_client.close()
    
    def generate_sales_record(self):
        """Generate a realistic sales transaction"""
        # Select random product
        product_id = random.choice(list(self.products.keys()))
        product = self.products[product_id]
        
        # Generate transaction details
        quantity = random.choices([1, 2, 3, 4, 5], weights=[50, 25, 15, 7, 3])[0]
        
        # Apply random discount
        discount_pct = random.choices([0, 0.05, 0.10, 0.15, 0.20], weights=[60, 20, 10, 7, 3])[0]
        unit_price = product["price"] * (1 - discount_pct)
        
        # Calculate totals
        subtotal = unit_price * quantity
        tax_rate = 0.08  # 8% tax
        tax_amount = subtotal * tax_rate
        total_amount = subtotal + tax_amount
        
        # Generate customer info
        customer_id = f"CUST{random.randint(10000, 99999)}"
        customer_segment = random.choice(self.customer_segments)
        
        # Generate transaction metadata
        transaction_id = f"TXN{random.randint(1000000, 9999999)}"
        channel = random.choice(self.channels)
        region = random.choice(self.regions)
        payment_method = random.choice(self.payment_methods)
        
        # Simulate processing time
        processing_time_ms = random.randint(100, 2000)
        
        # Generate timestamps
        current_time = datetime.now()
        
        sales_record = {
            "transaction_id": transaction_id,
            "product_id": product_id,
            "product_name": product["name"],
            "product_category": product["category"],
            "customer_id": customer_id,
            "customer_segment": customer_segment,
            "quantity": quantity,
            "unit_price": round(unit_price, 2),
            "discount_percent": discount_pct,
            "subtotal": round(subtotal, 2),
            "tax_amount": round(tax_amount, 2),
            "total_amount": round(total_amount, 2),
            "cost_amount": round(product["cost"] * quantity, 2),
            "profit_amount": round(total_amount - (product["cost"] * quantity), 2),
            "sales_channel": channel,
            "region": region,
            "payment_method": payment_method,
            "processing_time_ms": processing_time_ms,
            "timestamp": current_time.isoformat(),
            "date": current_time.strftime("%Y-%m-%d"),
            "hour": current_time.hour,
            "day_of_week": current_time.strftime("%A"),
            "month": current_time.strftime("%B"),
            "quarter": f"Q{((current_time.month - 1) // 3) + 1}",
            "year": current_time.year,
            "source": "product_sales_generator"
        }
        
        return sales_record
    
    def generate_batch_sales(self, num_records=10):
        """Generate and send a batch of sales records"""
        print(f"📊 Generating {num_records} sales records at {datetime.now().strftime('%H:%M:%S')}")
        
        for i in range(num_records):
            sales_record = self.generate_sales_record()
            self.kafka_producer.send('product_sales', value=sales_record, key=sales_record['transaction_id'])
            
            # Small delay to spread out timestamps
            time.sleep(0.01)
        
        print(f"✅ Sent {num_records} sales records")
    
    def start_continuous_generation(self):
        """Start continuous sales data generation"""
        print("🚀 Starting Product Sales Data Generator")
        print("=" * 50)
        print(f"📊 Simulating sales for {len(self.products)} products")
        print(f"🔄 Generating sales records every 5 seconds")
        print(f"💰 Realistic transaction data with pricing and profit")
        print("=" * 50)
        
        try:
            while True:
                # Generate 5-15 sales records every 5 seconds
                num_records = random.randint(5, 15)
                self.generate_batch_sales(num_records)
                time.sleep(5)
        except KeyboardInterrupt:
            print("\n🛑 Stopping sales generator...")
            self.close()
    
    def close(self):
        """Close the Kafka producer"""
        self.kafka_producer.close()
        print("✅ Sales generator stopped")

if __name__ == "__main__":
    generator = ProductSalesGenerator()
    
    try:
        generator.start_continuous_generation()
    except KeyboardInterrupt:
        generator.close()
