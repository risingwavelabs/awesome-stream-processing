from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import pymysql
from datetime import datetime, timedelta
import uvicorn

app = FastAPI()

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -------------------------- Database Configuration --------------------------
# MySQL connection configuration (replace with your actual info)
MYSQL_CONFIG = {
    "host": "localhost",
    "port": 3306,
    "user": "root",
    "password": "root",
    "database": "medical_alerts",
    "charset": "utf8mb4"
}

# -------------------------- Utility Functions --------------------------
def get_mysql_conn():
    """Get MySQL connection (auto-reconnect)"""
    try:
        conn = pymysql.connect(**MYSQL_CONFIG)
        conn.autocommit = True
        return conn
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"MySQL connection failed: {str(e)}")

def get_time_range_condition(time_range: str) -> str:
    """Convert frontend time range to MySQL time condition"""
    now = datetime.now()
    time_mapping = {
        "1h": now - timedelta(hours=1),
        "6h": now - timedelta(hours=6),
        "12h": now - timedelta(hours=12),
        "24h": now - timedelta(hours=24),
        "7d": now - timedelta(days=7)
    }
    start_time = time_mapping.get(time_range, now - timedelta(hours=12))
    return f"alert_time >= '{start_time.strftime('%Y-%m-%d %H:%M:%S')}'"

# -------------------------- Data Models --------------------------
class AlertStatusUpdate(BaseModel):
    alertId: str  # Frontend parameter: alertId (camelCase)
    status: str   # confirmed/resolved

# -------------------------- API 1: Get Alert Statistics --------------------------
@app.get("/api/alert/stats")
def get_alert_stats(time_range: str = Query("12h", enum=["1h", "6h", "12h", "24h", "7d"], alias="timeRange")):
    time_cond = get_time_range_condition(time_range)

    # Statistics SQL
    stats_sql = f"""
        SELECT
            COUNT(DISTINCT alert_id) AS total_alerts,
            SUM(CASE WHEN alert_level = 'level1' THEN 1 ELSE 0 END) AS level1_count,
            SUM(CASE WHEN alert_level = 'level2' THEN 1 ELSE 0 END) AS level2_count,
            SUM(CASE WHEN handle_status = 'pending' THEN 1 ELSE 0 END) AS pending_count,
            SUM(CASE WHEN handle_status = 'confirmed' THEN 1 ELSE 0 END) AS confirmed_count,
            SUM(CASE WHEN handle_status = 'resolved' THEN 1 ELSE 0 END) AS resolved_count
        FROM alerts
        WHERE {time_cond};
    """

    # Pending alerts count 10 minutes ago (for trend calculation)
    trend_sql = f"""
        SELECT COUNT(DISTINCT alert_id) AS pending_10min_ago
        FROM alerts
        WHERE {time_cond}
          AND handle_status = 'pending'
          AND alert_time <= DATE_SUB(NOW(), INTERVAL 10 MINUTE);
    """

    try:
        conn = get_mysql_conn()
        with conn.cursor(pymysql.cursors.DictCursor) as cur:
            # Basic statistics
            cur.execute(stats_sql)
            stats = cur.fetchone()
            total_alerts = stats['total_alerts'] or 0
            level1_count = stats['level1_count'] or 0
            level2_count = stats['level2_count'] or 0
            pending_count = stats['pending_count'] or 0
            confirmed_count = stats['confirmed_count'] or 0
            resolved_count = stats['resolved_count'] or 0

            # Trend statistics
            cur.execute(trend_sql)
            trend = cur.fetchone()
            pending_10min_ago = trend['pending_10min_ago'] or 0
            pending_trend = f"+{pending_count - pending_10min_ago}" if (pending_count - pending_10min_ago) >=0 else f"{pending_count - pending_10min_ago}"

            # Calculate rates (avoid division by zero)
            confirmed_rate = round((confirmed_count / (total_alerts - resolved_count) * 100), 1) if (total_alerts - resolved_count) > 0 else 0
            resolved_rate = round((resolved_count / total_alerts * 100), 1) if total_alerts > 0 else 0

            return {
                "code": 200,
                "data": {
                    "total_alerts": total_alerts,
                    "level1_count": level1_count,
                    "level2_count": level2_count,
                    "pending_count": pending_count,
                    "confirmed_count": confirmed_count,
                    "resolved_count": resolved_count,
                    "confirmed_rate": confirmed_rate,
                    "resolved_rate": resolved_rate,
                    "pending_trend": pending_trend
                },
                "msg": "success"
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Statistics query failed: {str(e)}")

# -------------------------- API 2: Get Alert List (with filters) --------------------------
@app.get("/api/alert/list")
def get_alert_list(
        level: str = Query("all", enum=["all", "level1", "level2"]),
        status: str = Query("all", enum=["all", "pending", "confirmed", "resolved"]),
        time_range: str = Query("12h", enum=["1h", "6h", "12h", "24h", "7d"], alias="timeRange")
):
    time_cond = get_time_range_condition(time_range)
    level_cond = "1=1" if level == "all" else f"alert_level = '{level}'"
    status_cond = "1=1" if status == "all" else f"handle_status = '{status}'"

    # Total count SQL
    count_sql = f"""
        SELECT COUNT(DISTINCT alert_id) AS total_count
        FROM alerts
        WHERE {time_cond} AND {level_cond} AND {status_cond};
    """

    # List SQL
    list_sql = f"""
        SELECT
            patient_id,
            alert_time,
            alert_type,
            alert_detail,
            alert_level,
            alert_id,
            handle_status,
            handle_time,
            -- Text mapping for frontend (avoid hardcoding in frontend)
            CASE alert_type
                WHEN 'heart_rate' THEN 'Heart Rate Abnormality'
                WHEN 'blood_oxygen' THEN 'Blood Oxygen Abnormality'
                WHEN 'blood_glucose' THEN 'Blood Glucose Abnormality'
                WHEN 'multi_vital_signs_deterioration' THEN 'Multi-index Deterioration'
                ELSE 'Unknown'
            END AS alert_type_text,
            CASE alert_level
                WHEN 'level1' THEN 'Level 1 (Warning)'
                WHEN 'level2' THEN 'Level 2 (Critical)'
                ELSE 'Unknown'
            END AS alert_level_text,
            CASE handle_status
                WHEN 'pending' THEN 'Pending'
                WHEN 'confirmed' THEN 'Confirmed'
                WHEN 'resolved' THEN 'Resolved'
                ELSE 'Pending'
            END AS handle_status_text
        FROM alerts
        WHERE {time_cond} AND {level_cond} AND {status_cond}
        ORDER BY alert_time DESC;
    """

    try:
        conn = get_mysql_conn()
        with conn.cursor(pymysql.cursors.DictCursor) as cur:
            # Total count
            cur.execute(count_sql)
            count = cur.fetchone()['total_count'] or 0

            # List data
            cur.execute(list_sql)
            rows = cur.fetchall()
            alert_list = []

            for row in rows:
                alert_list.append({
                    "patientId": row['patient_id'],
                    "alertTime": row['alert_time'],
                    "alertType": row['alert_type'],
                    "alertDetail": row['alert_detail'],
                    "alertLevel": row['alert_level'],
                    "alertId": row['alert_id'],
                    "handleStatus": row['handle_status'],
                    "handleTime": row['handle_time'],
                    "alertTypeText": row['alert_type_text'],
                    "alertLevelText": row['alert_level_text'],
                    "handleStatusText": row['handle_status_text']
                })

            return {
                "code": 200,
                "data": {
                    "list": alert_list,
                    "count": count
                },
                "msg": "success"
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"List query failed: {str(e)}")

# -------------------------- API 3: Update Alert Status --------------------------
@app.post("/api/alert/update-status")
def update_alert_status(data: AlertStatusUpdate):
    if data.status not in ["confirmed", "resolved"]:
        raise HTTPException(status_code=400, detail="Status can only be 'confirmed' or 'resolved'")

    # Check if alert_id exists
    check_sql = f"SELECT 1 FROM alerts WHERE alert_id = '{data.alertId}';"
    # Update status (include handling time)
    update_sql = f"""
        UPDATE alerts
        SET handle_status = '{data.status}',
            handle_time = NOW()
        WHERE alert_id = '{data.alertId}';
    """

    try:
        conn = get_mysql_conn()
        with conn.cursor() as cur:
            # Check if alert exists
            cur.execute(check_sql)
            if not cur.fetchone():
                raise HTTPException(status_code=404, detail=f"Alert {data.alertId} does not exist")

            # Update status
            cur.execute(update_sql)
            if cur.rowcount == 0:
                raise HTTPException(status_code=500, detail="Failed to update status")
            conn.commit()

            return {"code": 200, "msg": f"Alert {data.alertId} marked as {data.status} successfully"}
    except HTTPException as e:
        raise e
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Status update failed: {str(e)}")


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
