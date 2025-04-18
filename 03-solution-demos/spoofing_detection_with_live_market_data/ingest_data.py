import databento as db
from risingwave import RisingWave, RisingWaveConnOptions
import logging
import os

# --- Setup logging ---
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Global client setup ---
api_key = os.environ.get("DATABENTO_API_KEY")
if api_key is None:
    logger.error("Please set the DATABENTO_API_KEY environment variable.")
    exit(1)
hist = db.Historical()

# --- RisingWave Connection Setup ---
rw = RisingWave(
    RisingWaveConnOptions.from_connection_info(
        host="localhost", port=4566, user="root", password="", database="dev"
    )
)

# --- Action Mapping (for MBO events) ---
action_map = {
    "A": "add",
    "M": "modify",
    "C": "cancel",
    "R": "clear",
    "T": "trade",
    "F": "fill",
    "N": "none",
}

def process_market_data(dataset, symbol, start_time):
    """Process market data directly from Databento"""
    logger.info(f"Processing market data for {symbol} from {start_time}")
    
    # Fetch MBO data
    logger.info("Fetching MBO data...")
    mbo_data = hist.timeseries.get_range(
        dataset=dataset,
        schema="mbo",
        stype_in="continuous",
        symbols=[symbol],
        start=start_time,
        limit=100000,
    )
    
    # Fetch BBO data
    logger.info("Fetching BBO data...")
    bbo_data = hist.timeseries.get_range(
        dataset=dataset,
        schema="mbp-1",
        stype_in="continuous",
        symbols=[symbol],
        start=start_time,
        limit=100000,
    )
    
    # Process records directly
    with rw.getconn() as conn:
        # Process MBO records one by one
        mbo_count = 0
        for record in mbo_data:
            try:
                params = {
                    "ts_event": record.pretty_ts_event,
                    "symbol": symbol,
                    "exchange": "GLBX",
                    "side": "bid" if record.side == "B" else "ask",
                    "price": record.pretty_price,
                    "size": record.size,
                    "event_type": action_map[record.action],
                    "order_id": str(record.order_id),
                }
                conn.execute(
                    """
                    INSERT INTO market_data
                    (ts_event, symbol, exchange, side, price, size, event_type, order_id)
                    VALUES 
                    (:ts_event, :symbol, :exchange, :side, :price, :size, :event_type, :order_id)
                    """,
                    params,
                )
                mbo_count += 1
                if mbo_count % 1000 == 0:
                    logger.info(f"Processed {mbo_count} MBO records")
            except Exception as e:
                logger.error(f"Error processing MBO record: {e}")
                continue
        
        # Process BBO records one by one
        bbo_count = 0
        for record in bbo_data:
            try:
                params = {
                    "ts_event": record.pretty_ts_event,
                    "symbol": symbol,
                    "exchange": "GLBX",
                    "bid_px_00": record.levels[0].bid_px,
                    "ask_px_00": record.levels[0].ask_px
                }
                conn.execute(
                    """
                    INSERT INTO bbo 
                    (ts_event, symbol, exchange, bid_px_00, ask_px_00)
                    VALUES 
                    (:ts_event, :symbol, :exchange, :bid_px_00, :ask_px_00)
                    """,
                    params,
                )
                bbo_count += 1
                if bbo_count % 1000 == 0:
                    logger.info(f"Processed {bbo_count} BBO records")
            except Exception as e:
                logger.error(f"Error processing BBO record: {e}")
                continue
    
    logger.info(f"Data processing complete. Processed {mbo_count} MBO records and {bbo_count} BBO records")

def main():
    dataset = "GLBX.MDP3"
    symbol = "ES.n.0"
    start_time = "2024-03-19"
    
    logger.info(f"Starting data processing from {start_time}")
    process_market_data(dataset, symbol, start_time)
    logger.info("Done!")

if __name__ == "__main__":
    main()