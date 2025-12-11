import time
import random
import datetime
import psycopg2
from faker import Faker


PG_HOST = "postgres"
PG_PORT = 5433      
PG_DB   = "mydb"
PG_USER = "myuser"
PG_PASS = "123456"

fake = Faker()
products = list(range(1, 21))  # product_ids 1..20

DDL_PRODUCT_INVENTORY = """
CREATE TABLE IF NOT EXISTS public.product_inventory (
  product_id        SERIAL PRIMARY KEY,
  product_name      VARCHAR(200) NOT NULL,
  stock_level       INT NOT NULL CHECK (stock_level >= 0),
  reorder_threshold INT NOT NULL CHECK (reorder_threshold >= 0),
  supplier          VARCHAR(200) NOT NULL,
  base_price        NUMERIC(10,2) NOT NULL CHECK (base_price > 0)
);

-- Ensure full-row images for logical decoding (CDC)
ALTER TABLE public.product_inventory REPLICA IDENTITY FULL;

-- Seed product master with stable IDs 1..20
INSERT INTO public.product_inventory
  (product_id, product_name, stock_level, reorder_threshold, supplier, base_price)
VALUES
  ( 1, 'Wireless Mouse',               150, 50, 'TechSupplies Inc.',        19.99),
  ( 2, 'Mechanical Keyboard',           80, 30, 'TechSupplies Inc.',        79.99),
  ( 3, '27-inch Monitor',               40, 15, 'ScreenMakers Ltd.',       229.99),
  ( 4, 'USB-C Hub',                    120, 40, 'ConnectPro',               34.99),
  ( 5, 'External SSD 1TB',              60, 20, 'DataSafe Solutions',       99.99),
  ( 6, 'Gaming Headset',                70, 25, 'AudioMax',                 59.99),
  ( 7, 'Office Chair',                  25, 10, 'ErgoFurniture Co.',       149.99),
  ( 8, 'Laptop Stand',                  90, 30, 'WorkEase Ltd.',            24.99),
  ( 9, 'Portable Projector',            35, 10, 'VisionTech',              299.99),
  (10, 'Smartphone Tripod',            100, 35, 'CaptureGear',              17.99),
  (11, 'Bluetooth Speaker',             85, 30, 'AudioMax',                 49.99),
  (12, '4K Webcam',                     50, 20, 'VisionTech',               89.99),
  (13, 'Portable Power Bank',          120, 40, 'ChargeUp',                 29.99),
  (14, 'Wireless Earbuds',              75, 25, 'AudioMax',                 59.99),
  (15, 'Smartwatch',                    40, 15, 'WearableTech',            179.99),
  (16, 'Graphic Tablet',                30, 10, 'DesignPro',               139.99),
  (17, 'Electric Standing Desk',        20,  5, 'ErgoFurniture Co.',       349.99),
  (18, 'Noise-Canceling Headphones',    55, 20, 'AudioMax',                199.99),
  (19, 'HDMI to USB-C Adapter',        110, 40, 'ConnectPro',               14.99),
  (20, 'Dual Monitor Arm',              45, 15, 'ErgoFurniture Co.',        89.99)
ON CONFLICT (product_id) DO NOTHING;
"""

DDL_ORDERS = """
CREATE TABLE IF NOT EXISTS public.orders (
  order_id      SERIAL PRIMARY KEY,
  order_time    timestamptz      NOT NULL,
  product_id    int              NOT NULL,
  quantity      int              NOT NULL,
  customer_id   varchar(64)      NOT NULL
);
ALTER TABLE public.orders REPLICA IDENTITY FULL;
"""

def main():
    conn = psycopg2.connect(
        host=PG_HOST,
        port=PG_PORT,
        dbname=PG_DB,
        user=PG_USER,
        password=PG_PASS,
    )
    cur = conn.cursor()

    # Ensure product_inventory + seed data exist
    cur.execute(DDL_PRODUCT_INVENTORY)
    # Ensure orders table exists & is CDC-friendly
    cur.execute(DDL_ORDERS)
    conn.commit()

    try:
        while True:
            product_id = random.choice(products)
            qty = random.choices(
                [1, 2, 3, 5, 10],
                weights=[60, 20, 10, 7, 3]
            )[0]
            customer_id = fake.pystr_format()
            order_time = datetime.datetime.utcnow()

            cur.execute(
                """
                INSERT INTO public.orders (order_time, product_id, quantity, customer_id)
                VALUES (%s, %s, %s, %s)
                """,
                (order_time, product_id, qty, customer_id),
            )
            conn.commit()

            time.sleep(random.uniform(0.5, 1.5))
    except KeyboardInterrupt:
        pass
    finally:
        cur.close()
        conn.close()

if __name__ == "__main__":
    main()
