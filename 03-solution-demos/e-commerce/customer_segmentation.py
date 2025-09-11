from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from risingwave.core import RisingWave, RisingWaveConnOptions
import uvicorn

from generate_data import send_to_kafka

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

rw = RisingWave(
    RisingWaveConnOptions.from_connection_info(
        host="localhost", port=4566, user="root", password="root", database="dev"
    )
)


@app.get("/api/segmentation")
def read_data():
    data = rw.fetch(f"""
                        SELECT count(*), segment 
                        FROM customer_segmentation   
                        GROUP by segment
                        ORDER BY segment;
        """)
    result = []
    for row in data:
        result.append({
            "segment": row[1],
            "user_count": int(row[0])
        })
    return result


@app.get("/api/add")
def add_data():
    send_to_kafka(100, 1)
    send_to_kafka(1000, 2)
    send_to_kafka(300, 3)
    return 1


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
