-- Creates a 'users' table with columns for user_id, username, email, registration_date, last_login, and address.
CREATE TABLE users (
    user_id INTEGER PRIMARY KEY,
    username VARCHAR,
    email VARCHAR,
    registration_date DATE,
    last_login TIMESTAMP,
    address VARCHAR
)
FROM postgres_source TABLE 'public.users';

-- Creates a 'products' table with columns for product_id, product_name, brand, category, price, and stock_quantity.
CREATE TABLE products (
    product_id INTEGER PRIMARY KEY,
    product_name VARCHAR,
    brand VARCHAR,
    category VARCHAR,
    price NUMERIC,
    stock_quantity INTEGER
)
FROM postgres_source TABLE 'public.products';

-- Creates a 'sales' table with columns for sale_id, user_id, product_id, sale_date, quantity, and total_price.
CREATE TABLE sales (
    sale_id INTEGER PRIMARY KEY,
    user_id INTEGER,
    product_id INTEGER,
    sale_date DATE,
    quantity INTEGER,
    total_price NUMERIC   
)
FROM postgres_source TABLE 'public.sales';
