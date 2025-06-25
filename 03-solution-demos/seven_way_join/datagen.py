import random
from datetime import datetime, timedelta
from faker import Faker

faker = Faker("en_US")

def gen_truck(truck_id, driver_id):
    global faker

    truck_data = [
    {"model": "Freightliner Cascadia", "capacity_tons": 18, "manufacture_year": 2020},
    {"model": "Kenworth T680", "capacity_tons": 20, "manufacture_year": 2019},
    {"model": "Volvo VNL", "capacity_tons": 22, "manufacture_year": 2021},
    {"model": "Peterbilt 579", "capacity_tons": 19, "manufacture_year": 2018},
    {"model": "International LT", "capacity_tons": 21, "manufacture_year": 2020},
    {"model": "Mack Anthem", "capacity_tons": 23, "manufacture_year": 2022},
    {"model": "Western Star 5700XE", "capacity_tons": 24, "manufacture_year": 2019},
    {"model": "Hino XL Series", "capacity_tons": 15, "manufacture_year": 2021},
    {"model": "Isuzu F-Series", "capacity_tons": 14, "manufacture_year": 2020}
    ]

    truck = random.choice(truck_data)
    return {
        "truck_id": truck_id,
        "truck_model": truck['model'],
        "capacity_tons": truck['capacity_tons'],
        "manufacture_year": truck['manufacture_year'],
        "current_location": faker.city()
    }

def gen_driver(driver_id, truck_id):
    return {
        "driver_id": driver_id,
        "driver_name": faker.name(),
        "license_number": faker.bothify(text="??#####"),
        "assigned_truck_id": truck_id
    }

def gen_shipments(warehouse_loc, truck_id):
    return {
        "shipment_id": faker.bothify(text="SHIP-####-??"),
        "origin": faker.city(),
        "destination": warehouse_loc,
        "shipment_weight": random.randint(10, 20),
        "truck_id": truck_id
    }

def gen_warehouses(warehouse_loc):
    return {
        "warehouse_id": faker.bothify(text="WH-##"),
        "location": warehouse_loc,
        "capacity_tons": random.randint(500, 1000)
    }

def gen_route(truck_id, driver_id, random_date):
    extra_time = timedelta(hours=random.randint(12, 9 * 24))
    return {
        "route_id": faker.bothify(text = "RT-####"),
        "truck_id": truck_id,
        "driver_id": driver_id,
        "estimated_departure_time": random_date.strftime('%Y-%m-%dT%H:%M:%SZ'),
        "estimated_arrival_time": (random_date + extra_time).strftime('%Y-%m-%dT%H:%M:%SZ'),
        "distance_km": random.randint(589, 8910)
    }

def gen_fuel(truck_id, random_date):
    fuel_date = random_date + timedelta(hours=random.randint(6, 43))
    return {
        "fuel_log_id": faker.bothify(text = "FL-####"),
        "truck_id": truck_id,
        "fuel_date": fuel_date.strftime('%Y-%m-%dT%H:%M:%SZ'),
        "liters_filled": random.randint(300, 570),
        "fuel_station": faker.city()
    }

def gen_maintenance(truck_id, random_date):
    maint_date = random_date - timedelta(days=random.randint(21, 219))
    return {
        "maintenance_id": faker.bothify(text = "MT-####"),
        "truck_id": truck_id,
        "maintenance_date": maint_date.strftime('%Y-%m-%dT%H:%M:%SZ'),
        "cost_usd": random.randint(358, 2854)
    }
