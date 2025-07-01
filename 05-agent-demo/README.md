# 📊 Use Agents to Analyze Data Ingested into RisingWave

## Overview

In this tutorial, you'll learn how to implement a custom Anthropic agent and integrate it with RisingWave MCP to perform simple stream processing tasks on live data.

For a reference implementation, check out [this repository](https://github.com/risingwavelabs/awesome-stream-processing/).

---

## Prerequisites

- Install and run **RisingWave**. See the [Quick Start Guide](https://docs.risingwave.com/get-started/quickstart/).
- Acquire an [Anthropic API key](https://console.anthropic.com/settings/keys).
- Ensure `psql` (PostgreSQL interactive terminal) is installed. [Download here](https://www.postgresql.org/download/).
- Clone [RisingWave MCP](https://github.com/risingwavelabs/risingwave-mcp.git).

---

## Setup

### Install Dependencies  
Make sure you have the following Python packages installed:
```bash
pip install anthropic fastmcp python-dotenv tabulate
```
### Create .env File
Create a .env file in your project directory with:
```env
ANTHROPIC_API_KEY=<YOUR-API-KEY-HERE>
RISINGWAVE_HOST=0.0.0.0
RISINGWAVE_USER=root
RISINGWAVE_PASSWORD=root
RISINGWAVE_PORT=4566
RISINGWAVE_DATABASE=dev
RISINGWAVE_SSLMODE=disable
RISINGWAVE_TIMEOUT=30
```
#Generate Test Data in RisingWave
Use this command inside psql to set up a streaming data table:
```
```psql
CREATE TABLE users (
  id int,
  risk int,
  cost int,
  time timestamp
)
WITH (
  connector = 'datagen',
  fields.id.length = '1',
  fields.id.kind = 'sequence',
  fields.id.start = '1000',
  fields.risk.length = '1',
  fields.risk.kind = 'random',
  fields.risk.min = '0',
  fields.risk.max = '10',
  fields.risk.seed = '5',
  fields.cost.length = '1',
  fields.cost.kind = 'random',
  fields.cost.min = '1',
  fields.cost.max = '10000',
  fields.cost.seed = '8',
  fields.time.kind = 'random',
  fields.time.max_past = '5h',
  fields.time.max_past_mode = 'relative',
  datagen.rows.per.second = '10'
)
FORMAT PLAIN ENCODE JSON;
```
Running the Agent

Start your agent by running:

python client.py risingwave-mcp/src/main.py
Example Queries

Here are some example queries you can run once the agent is active:

Get Database Version
Give me the database version
Show Users Table Structure
Show me the users table structure
Track Highest Risk Scores
Track the highest risk scores
Sort Materialized View by Highest Spending
Sort that mv by highest spending and display
