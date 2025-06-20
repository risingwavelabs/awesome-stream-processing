create table product_inventory (
  "product_id" SERIAL PRIMARY KEY,
  "product_name" varchar(200),
  "stock_level" int,
  "reorder_threshold" int,
  "supplier" varchar(200),
  "base_price" decimal
);

ALTER TABLE
  public.product_inventory REPLICA IDENTITY FULL;

INSERT INTO product_inventory (product_name, stock_level, reorder_threshold, supplier, base_price) VALUES
('Wireless Mouse', 150, 50, 'TechSupplies Inc.', 19.99),
('Mechanical Keyboard', 80, 30, 'TechSupplies Inc.', 79.99),
('27-inch Monitor', 40, 15, 'ScreenMakers Ltd.', 229.99),
('USB-C Hub', 120, 40, 'ConnectPro', 34.99),
('External SSD 1TB', 60, 20, 'DataSafe Solutions', 119.99),
('Gaming Headset', 70, 25, 'AudioMax', 59.99),
('Office Chair', 25, 10, 'ErgoFurniture Co.', 199.99),
('Laptop Stand', 90, 30, 'WorkEase Ltd.', 39.99),
('Portable Projector', 35, 10, 'VisionTech', 299.99),
('Smartphone Tripod', 100, 35, 'CaptureGear', 24.99),
('Bluetooth Speaker', 85, 30, 'AudioMax', 49.99),
('4K Webcam', 50, 20, 'VisionTech', 99.99),
('Portable Power Bank', 120, 40, 'ChargeUp', 29.99),
('Wireless Earbuds', 75, 25, 'AudioMax', 69.99),
('Smartwatch', 40, 15, 'WearableTech', 199.99),
('Graphic Tablet', 30, 10, 'DesignPro', 149.99),
('Electric Standing Desk', 20, 5, 'ErgoFurniture Co.', 399.99),
('Noise-Canceling Headphones', 55, 20, 'AudioMax', 149.99),
('HDMI to USB-C Adapter', 110, 40, 'ConnectPro', 19.99),
('Dual Monitor Arm', 45, 15, 'ErgoFurniture Co.', 89.99);
