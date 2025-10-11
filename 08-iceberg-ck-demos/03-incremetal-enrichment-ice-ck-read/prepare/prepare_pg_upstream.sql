CREATE TABLE IF NOT EXISTS public.product (
		product_id    INTEGER PRIMARY KEY,
		product_name  VARCHAR,
		category      VARCHAR,
		list_price    INTEGER,
		currency      VARCHAR,
		active        BOOLEAN,
		updated_at    TIMESTAMPTZ
);