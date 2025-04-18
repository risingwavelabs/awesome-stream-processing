        CREATE TABLE IF NOT EXISTS market_data (
            ts_event TIMESTAMPTZ,
            symbol VARCHAR,
            exchange VARCHAR,
            side VARCHAR,
            price DOUBLE PRECISION,
            size INTEGER,
            event_type VARCHAR,
            order_id VARCHAR
        );


    CREATE TABLE IF NOT EXISTS bbo (
            ts_event TIMESTAMP WITH TIME ZONE,
            symbol VARCHAR,
            exchange VARCHAR,
            bid_px_00 DOUBLE PRECISION,
            ask_px_00 DOUBLE PRECISION
        );
        
