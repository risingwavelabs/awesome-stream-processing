FROM python:3.8

RUN pip install kafka-python  

# Create a directory for the Python files
WORKDIR /app

# Copy Python file into the container
COPY data-producers/run-producers.py .

# Run the Python script
CMD ["python", "run-producers.py"]
