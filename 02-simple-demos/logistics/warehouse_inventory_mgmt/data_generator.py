import psycopg2
import random
from datetime import datetime, timedelta
import time

# Connection parameters
conn_params = {
    "dbname": "dev",
    "user": "root",
    "password": "",
    "host": "localhost",
    "port": "4566"
}

# Connect to RisingWave
conn = psycopg2.connect(**conn_params)
cursor = conn.cursor()

# Inventory and sales data details
num_warehouses = 5
num_products = 10

try:
    while True:
        # Simulate inventory updates
        for warehouse_id in range(1, num_warehouses + 1):
            for product_id in range(1, num_products + 1):
                timestamp = datetime.now()
                stock_level = random.randint(50, 500)
                reorder_point = 100
                location = f"Warehouse {warehouse_id}"

                cursor.execute(
                    """
                    INSERT INTO inventory (warehouse_id, product_id, timestamp, stock_level, reorder_point, location)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    """,
                    (warehouse_id, product_id, timestamp, stock_level, reorder_point, location)
                )

        conn.commit()

        # Simulate sales
        for _ in range(20):
            sale_id = random.randint(1, 10000)
            warehouse_id = random.randint(1, num_warehouses)
            product_id = random.randint(1, num_products)
            quantity_sold = random.randint(1, 10)
            timestamp = datetime.now()

            cursor.execute(
                """
                INSERT INTO sales (sale_id, warehouse_id, product_id, quantity_sold, timestamp)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (sale_id, warehouse_id, product_id, quantity_sold, timestamp)
            )

        conn.commit()
        time.sleep(5)

except KeyboardInterrupt:
    print("Data insertion stopped.")
finally:
    cursor.close()
    conn.close()
    print("Connection closed.")
