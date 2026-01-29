FROM python:3.11-slim

# Faster, cleaner logs + no .pyc
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install deps
RUN pip install --no-cache-dir requests Faker

# Copy producer code
COPY datagen.py /app/datagen.py
COPY send_events.py /app/send_events.py

# Run the producer
CMD ["python", "send_events.py"]
