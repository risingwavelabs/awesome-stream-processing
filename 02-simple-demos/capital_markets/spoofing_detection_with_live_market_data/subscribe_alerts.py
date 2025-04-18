from risingwave import RisingWave, RisingWaveConnOptions, OutputFormat
import pandas as pd
import signal
import sys
import threading
import logging
import os

# --- Setup logging ---
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- RisingWave Connection Setup ---
rw = RisingWave(
    RisingWaveConnOptions.from_connection_info(
        host="localhost", port=4566, user="root", password="", database="dev"
    )
)

def signal_handler(sig, frame):
    """Handle graceful shutdown."""
    logger.info('Shutting down...')
    sys.exit(0)

def handle_spoofing_alerts(event_df: pd.DataFrame) -> None:
    """Handles spoofing alerts and logs them."""
    try:
        event_df = event_df[event_df["op"].isin(["Insert", "UpdateInsert"])]
        if event_df.empty:
            return
        event_df = event_df.drop(["op", "rw_timestamp"], axis=1)
        logger.info("\nSpoofing Alert:")
        logger.info(event_df)

    except Exception as e:
        logger.error(f"Error processing alert: {e}", exc_info=True)
        # Consider adding a retry mechanism here for transient errors

def main():
    """Main function to subscribe to alerts."""
    signal.signal(signal.SIGINT, signal_handler)  # Handle Ctrl+C gracefully

    # Check if the materialized view exists before subscribing
    with rw.getconn() as conn:
        result = conn.execute("SHOW MATERIALIZED VIEWS;")
        mviews = [row[0] for row in result]
        if "spoofing_alerts" not in mviews:
            logger.error("Materialized view 'spoofing_alerts' does not exist.  Run spoofing_alerts.sql first.")
            sys.exit(1)
    # Subscribe to alerts in a separate thread.
    threading.Thread(
        target=lambda: rw.on_change(
            subscribe_from="spoofing_alerts",
            handler=handle_spoofing_alerts,
            output_format=OutputFormat.DATAFRAME,
        ),
        daemon=True  # Allow the thread to exit when the main thread exits
    ).start()

    logger.info("Subscribed to spoofing_alerts.  Waiting for events...")
    signal.pause() # Wait for a signal (like Ctrl+C)


if __name__ == "__main__":
    main()