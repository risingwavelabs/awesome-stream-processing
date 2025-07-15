# 📊 Use Agents to Analyze Data Ingested into RisingWave

## Overview

This agent is a client application that connects RisingWave’s MCP (Managed Control Plane) with Anthropic’s LLM to process natural language queries, call data tools, and return clean, readable results to users. It features components for handling table extraction from SQL-like queries, dynamically fetching table schemas, invoking MCP tools, parsing and formatting results (like tables), and managing a chat loop that coordinates between RisingWave tool calls and Anthropic-generated responses — iterating until the user's query is fully handled.

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
### Generate Test Data in RisingWave
Use this command inside psql to set up a streaming data table:
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
### Running the Agent

Start your agent by running:
```bash
python client.py risingwave-mcp/src/main.py
```
### Example Queries

Here are some example queries you can run once the agent is active:

- Get Database Version
```bash
I'll help you check the RisingWave database version using the `get_database_version` function.
[Calling tool get_database_version with args {}]
Based on the output, you're using:
- RisingWave version 2.2.0
- It's built on PostgreSQL 13.14.0
- This appears to be the Homebrew installation version
```

- List all tables

```bash
I'll help you list all the tables in the database using the `show_tables` function.
[Calling tool show_tables with args {}]
Here are all the tables in the database:
1. users
2. _risingwave_py_version (this appears to be a system table)


Let me get more details about the 'users' table since that's likely the main table you're interested in.
[Calling tool describe_table with args {'table_name': 'users'}]
Let me break down the structure of the 'users' table:

Main Columns:
1. id (integer)
2. risk (integer)
3. cost (integer)
4. time (timestamp without time zone)

System Columns:
5. _row_id (serial) - Primary Key
6. _rw_timestamp (timestamp with time zone)

Additional Information:
- Primary Key: _row_id
- Distribution Key: _row_id
- Table Name: users

This appears to be a table tracking user information with their associated risk, cost, and timestamp data.


Let me know if you'd like to:
1. See the actual data in this table
2. Get row count statistics
3. Or perform any other operations on this table
```

- Show me data from the users table

```bash
I'll help you see the data from the users table using the run_select_query function.
[Calling tool run_select_query with args {'query': 'SELECT id, risk, cost, time FROM users;'}]
The users table contains 31,768 rows with 4 columns. Here's a breakdown:

First 5 rows:
1. ID: 21970, Risk: 2, Cost: 9594, Time: 2025-06-27 13:39:00
2. ID: 21971, Risk: 10, Cost: 6808, Time: 2025-06-27 13:38:28
3. ID: 21972, Risk: 8, Cost: 8763, Time: 2025-06-27 13:19:21
4. ID: 21973, Risk: 5, Cost: 6721, Time: 2025-06-27 13:26:52
5. ID: 21974, Risk: 5, Cost: 7152, Time: 2025-06-27 11:20:54

Last 5 rows:
1. ID: 21828, Risk: 0, Cost: 697, Time: 2025-06-27 15:22:02
2. ID: 21860, Risk: 10, Cost: 915, Time: 2025-06-27 15:16:05
3. ID: 21892, Risk: 1, Cost: 7698, Time: 2025-06-27 10:42:33
4. ID: 21924, Risk: 5, Cost: 9479, Time: 2025-06-27 14:04:30
5. ID: 21956, Risk: 0, Cost: 6663, Time: 2025-06-27 14:52:16

Column details:
- id: Unique identifier for each user
- risk: Risk score (ranges from 0 to 10)
- cost: Transaction cost (ranges from 697 to 9594)
- time: Timestamp of the transaction (all on June 27, 2025)
```

- Describe the users table

```bash
Table Properties:
- Primary Key: _row_id
- Distribution Key: _row_id
- Table Name: users

The table appears to be designed to track user-related data with associated risk scores, costs, and timestamps.


Each row in the table has:
- A user ID
- A risk value (as an integer)
- A cost value (as an integer)
- A timestamp for when the record was created/updated
- System-managed columns for internal use (_row_id and _rw_timestamp)
```

- Track the highest risk scores in users

```bash
I'll help you create a materialized view to track the highest risk scores from the users table. This will continuously maintain the maximum risk scores as new data comes in.
[Calling tool create_materialized_view with args {'name': 'highest_risks', 'sql_statement': 'SELECT id, risk, time \nFROM users \nWHERE risk = (SELECT MAX(risk) FROM users)'}]
Great! The materialized view 'highest_risks' has been created successfully. You can now query this view to see the highest risk scores from the users table. The view will maintain an up-to-date list of the highest risk values, making it efficient to monitor high-risk cases.
```

- Display the top rows of that materialized view

```bash

I'll query the materialized view 'risk_by_spending' to show the top rows:
[Calling tool run_select_query with args {'query': 'SELECT * FROM risk_by_spending LIMIT 10;'}]
Looking at the materialized view data, here's a summary of the highest total costs:

1. Risk Level 4: $14,777,992 (highest total cost)
2. Risk Level 8: $14,661,035
3. Risk Level 7: $14,565,086
4. Risk Level 9: $14,547,682
5. Risk Level 10: $14,550,576

Some interesting observations:
- Risk Level 4 has the highest total cost despite not having the highest count
- Risk Level 5 has the highest average cost per transaction (about $5,045)
- The counts range from 2,823 to 2,952 transactions across risk levels
- All risk levels (0-10) show similar patterns in terms of total costs, suggesting relatively even distribution

Would you like me to analyze any specific aspect of this data in more detail?
```

Once you are done just query 'quit' to exit the program.
