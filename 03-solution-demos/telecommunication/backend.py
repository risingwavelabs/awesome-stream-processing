from __future__ import annotations

import os
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
from typing import Optional, List, Dict, Any

import pandas as pd
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

from pyiceberg.catalog import load_catalog

import uvicorn


# -----------------------------
# Config (edit to match yours)
# -----------------------------
REST_URI = os.getenv("ICEBERG_REST_URI", "http://localhost:8181/catalog")
WAREHOUSE = os.getenv("ICEBERG_WAREHOUSE", "rw_iceberg")

# S3 / MinIO (pyiceberg uses these for file IO)
S3_ENDPOINT = os.getenv("S3_ENDPOINT", "http://localhost:9000")
S3_ACCESS_KEY = os.getenv("S3_ACCESS_KEY", "minioadmin")
S3_SECRET_KEY = os.getenv("S3_SECRET_KEY", "minioadmin")
S3_REGION = os.getenv("S3_REGION", "us-east-1")

# IMPORTANT for MinIO: path-style access
S3_PATH_STYLE = os.getenv("S3_PATH_STYLE", "true").lower() == "true"

ICEBERG_NAMESPACE = os.getenv("ICEBERG_NAMESPACE", "public")
ICEBERG_TABLE = os.getenv("ICEBERG_TABLE", "network_anomalies_history")

# Timezone handling
# RisingWave/Iceberg often stores TIMESTAMP WITHOUT TIME ZONE; we treat those as local time.
LOCAL_TZ_NAME = os.getenv("LOCAL_TZ", "Asia/Singapore")
LOCAL_TZ = ZoneInfo(LOCAL_TZ_NAME)


def parse_iso(ts: Optional[str]) -> Optional[datetime]:
    """Parse incoming query timestamps.

    The frontend may send:
      - ISO with timezone (e.g. 2026-01-27T12:34:56Z or +08:00)
      - datetime-local style without timezone (e.g. 2026-01-27T12:34)

    For timezone-naive inputs we assume LOCAL_TZ, then convert to UTC.
    """
    if not ts:
        return None

    s = ts.strip()

    # Normalize trailing Z
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"

    dt = datetime.fromisoformat(s)

    # If naive, assume local tz
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=LOCAL_TZ)

    return dt.astimezone(timezone.utc)


def ws_to_dt(ws: str) -> datetime:
    """Convert window_start string to UTC datetime.

    Iceberg/RisingWave commonly use TIMESTAMP WITHOUT TIME ZONE for window_start.
    We interpret those values as LOCAL_TZ, then convert to UTC for consistent filtering.

    Accepts strings like:
      - "YYYY-MM-DD HH:mm:ss"
      - "YYYY-MM-DDTHH:mm:ss"
      - with optional fractional seconds
    """
    s = (ws or "").strip()
    if not s:
        # fallback; should not happen
        return datetime.fromtimestamp(0, tz=timezone.utc)

    # Make it ISO-like for fromisoformat
    if " " in s and "T" not in s:
        s = s.replace(" ", "T", 1)

    dt = datetime.fromisoformat(s)

    # If naive, assume local tz
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=LOCAL_TZ)

    return dt.astimezone(timezone.utc)


def get_catalog():
    # REST catalog config + MinIO file IO config
    return load_catalog(
        **{
            "type": "rest",
            "uri": REST_URI,
            "warehouse": WAREHOUSE,

            # S3 IO
            "s3.endpoint": S3_ENDPOINT,
            "s3.access-key-id": S3_ACCESS_KEY,
            "s3.secret-access-key": S3_SECRET_KEY,
            "s3.region": S3_REGION,
            "s3.path-style-access": str(S3_PATH_STYLE).lower(),
        },
    )


app = FastAPI(title="Network Anomalies Demo API")

# allow your static HTML to call this API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # demo only
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health():
    return {"ok": True}


@app.get("/api/anomalies")
def anomalies(
    q: Optional[str] = Query(default=None, description="keyword on device_id or window_start"),
    from_: Optional[str] = Query(default=None, alias="from", description="ISO timestamp"),
    to: Optional[str] = Query(default=None, description="ISO timestamp"),
    types: Optional[str] = Query(default=None, description="comma-separated: latency,loss,bandwidth"),
    sort: str = Query(default="time_desc", pattern="^(time_desc|time_asc)$"),
    limit: int = Query(default=15, ge=1, le=2000),
    offset: int = Query(default=0, ge=0),
) -> Dict[str, Any]:
    """Returns rows for dashboard. Filtering is done here so the frontend is thin."""

    from_dt = parse_iso(from_)
    to_dt = parse_iso(to)

    selected_types: List[str] = []
    if types:
        selected_types = [t.strip().lower() for t in types.split(",") if t.strip()]

    # Load Iceberg
    catalog = get_catalog()
    table = catalog.load_table((ICEBERG_NAMESPACE, ICEBERG_TABLE))

    # Demo approach: scan full and filter in pandas.
    df = table.scan().to_pandas()

    # normalize columns
    if "window_start" in df.columns:
        df["__ws_dt"] = df["window_start"].astype(str).apply(ws_to_dt)
    else:
        df["__ws_dt"] = pd.NaT

    # Ensure dtype is datetime64[ns, UTC] for correct comparisons
    df["__ws_dt"] = pd.to_datetime(df["__ws_dt"], utc=True, errors="coerce")

    # keyword filter
    if q:
        qq = q.strip().lower()
        df = df[
            df["device_id"].astype(str).str.lower().str.contains(qq, na=False)
            | df["window_start"].astype(str).str.lower().str.contains(qq, na=False)
        ]

    # time range
    df = df[df["__ws_dt"].notna()]
    if from_dt is not None:
        df = df[df["__ws_dt"] >= from_dt]
    if to_dt is not None:
        df = df[df["__ws_dt"] <= to_dt]

    # anomaly type OR filter
    if selected_types:
        mask = False
        if "latency" in selected_types and "is_high_latency" in df.columns:
            mask = mask | df["is_high_latency"].fillna(False)
        if "loss" in selected_types and "is_high_packet_loss" in df.columns:
            mask = mask | df["is_high_packet_loss"].fillna(False)
        if "bandwidth" in selected_types and "is_high_bandwidth_saturation" in df.columns:
            mask = mask | df["is_high_bandwidth_saturation"].fillna(False)
        # Backward-compat if old column name exists
        if "bandwidth" in selected_types and "is_bandwidth_saturation" in df.columns:
            mask = mask | df["is_bandwidth_saturation"].fillna(False)
        df = df[mask]
    else:
        # if user unchecks all, return empty
        df = df.iloc[0:0]

    total = int(df.shape[0])

    # sort
    asc = sort == "time_asc"
    df = df.sort_values("__ws_dt", ascending=asc)

    # page
    df = df.iloc[offset : offset + limit]

    cols = [
        "device_id",
        "window_start",
        "window_end",
        "avg_latency_ms",
        "avg_packet_loss_rate",
        "avg_bandwidth_usage",
        "is_high_latency",
        "is_high_packet_loss",
        "is_high_bandwidth_saturation",
        "is_bandwidth_saturation",
    ]

    # Ensure stable output schema (frontend expects 9 columns; keep the old 9 too)
    output_cols = [
        "device_id",
        "window_start",
        "window_end",
        "avg_latency_ms",
        "avg_packet_loss_rate",
        "avg_bandwidth_usage",
        "is_high_latency",
        "is_high_packet_loss",
        "is_bandwidth_saturation",
    ]

    for c in cols:
        if c not in df.columns:
            df[c] = None

    # Prefer `is_high_bandwidth_saturation` if present, else fallback
    if "is_high_bandwidth_saturation" in df.columns and df["is_high_bandwidth_saturation"].notna().any():
        df["is_bandwidth_saturation"] = df["is_high_bandwidth_saturation"].fillna(False)

    rows = df[output_cols].to_dict(orient="records")
    return {"total": total, "limit": limit, "offset": offset, "rows": rows}


if __name__ == "__main__":
    uvicorn.run(
        "backend:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
    )
