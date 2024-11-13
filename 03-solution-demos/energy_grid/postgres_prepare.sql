create table customers (
  "customer_id" SERIAL PRIMARY KEY,
  "meter_id" int,
  "address" varchar(200),
  "price_plan" varchar(200)
);

ALTER TABLE
  public.customers REPLICA IDENTITY FULL;

INSERT INTO customers (meter_id, address, price_plan)
VALUES
    (1, '123 Elm Street, Springfield, USA', 'tier'),
    (2, '456 Oak Avenue, Shelbyville, USA', 'time of use'),
    (3, '789 Pine Road, Ogdenville, USA', 'tier'),
    (4, '321 Maple Street, Capital City, USA', 'time of use'),
    (5, '654 Cedar Avenue, North Haverbrook, USA', 'tier'),
    (6, '987 Birch Lane, Springfield, USA', 'time of use'),
    (7, '432 Walnut Street, Shelbyville, USA', 'tier'),
    (8, '876 Chestnut Avenue, Ogdenville, USA', 'time of use'),
    (9, '543 Ash Road, Capital City, USA', 'tier'),
    (10, '109 Willow Street, North Haverbrook, USA', 'time of use'),
    (11, '222 Elm Street, Springfield, USA', 'tier'),
    (12, '333 Oak Avenue, Shelbyville, USA', 'time of use'),
    (13, '444 Pine Road, Ogdenville, USA', 'tier'),
    (14, '555 Maple Street, Capital City, USA', 'time of use'),
    (15, '666 Cedar Avenue, North Haverbrook, USA', 'tier'),
    (16, '912 Magnolia Plaza, North Haverbrook, USA', 'time of use'),
    (17, '777 Birch Lane, Springfield, USA', 'tier'),
    (18, '888 Walnut Street, Shelbyville, USA', 'time of use'),
    (19, '999 Chestnut Avenue, Ogdenville, USA', 'time of use'),
    (20, '101 Ash Road, Capital City, USA', 'tier');
