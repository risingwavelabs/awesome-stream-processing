# Data Engineering Agent Swarm

A multi-agent system for data engineering tasks with RisingWave and Kafka integration.

## Prerequisites

- Python 3.8+
- RisingWave database running (default: localhost:4566)
- Kafka cluster running (default: localhost:9092)

## Setup

1. **Clone the required MCP servers:**
   ```bash
   # Clone RisingWave MCP server:
   git clone https://github.com/risingwavelabs/risingwave-mcp.git
   
   # Clone Kafka MCP server:
   git clone https://github.com/kanapuli/mcp-kafka
   # Make sure you run:
   make build
   ```

   

2. **Install Python dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

3. **Set up environment variables:**
   Create a `.env` file with your credentials:
   ```
   OPENAI_API_KEY=<your_api_key_here>
   RISINGWAVE_HOST=0.0.0.0
   RISINGWAVE_USER=root
   RISINGWAVE_PASSWORD=root
   RISINGWAVE_PORT=4566
   RISINGWAVE_DATABASE=dev
   ```

## Usage

Run the data engineering agent swarm:

```bash
python swarm.py
```

The system will start with a planner agent that can delegate tasks to specialized agents for:
- Database operations (RisingWave)
- Stream processing (Kafka)
- Data pipeline orchestration

## Features

- **Multi-agent architecture** with strategic planning and task delegation
- **RisingWave integration** for real-time analytics
- **Kafka integration** for stream processing
- **Automatic schema inference** from Kafka messages
- **Interactive chat interface**

## Example Usage

Once running, you can ask the system to:
- Create Kafka topics and produce test data
- Set up RisingWave tables and materialized views
- Build real-time data pipelines
- Analyze streaming data

## Tools Included

- **ProductSalesGenerator** (`productsalesgen.py`): Generates realistic sales data to Kafka topics for testing
