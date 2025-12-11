FROM python:3.8

RUN pip install kafka-python faker psycopg2-binary

# Create a directory for the Python files
WORKDIR /app

# Copy Python files into the container
COPY data-producers/run-producers.py .
COPY data-producers/restocks.py .
COPY data-producers/purchases.py .
COPY data-producers/web_clicks.py .
COPY data-producers/competitor_prices.py .
COPY data-producers/pg_seed.py .

# Run the Python script
CMD ["python", "run-producers.py"]
