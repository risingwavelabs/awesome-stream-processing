# 📊 RisingWave + Anthropic Agent: Stream Processing Demo

This project demonstrates how to build a Claude-powered AI agent that connects to a RisingWave MCP server for simple stream processing and database querying.

---

## 📦 Requirements

- [RisingWave](https://docs.risingwave.com/get-started/quickstart/)
- [Anthropic API key](https://console.anthropic.com/settings/keys)
- [PostgreSQL CLI (`psql`)](https://www.postgresql.org/download/)
- Python environment with:

  ```bash
  pip install anthropic fastmcp psycopg2 python-dotenv
  ```

---

## 📂 Project Structure

```
project/
├── agents/
│   ├── __init__.py
│   └── agent.py
├── risingwave-agent.py
├── .env
```

---

## ⚙️ Setup

### 1️⃣ Configure `.env`

Create a `.env` file in the project root and add:

```env
ANTHROPIC_API_KEY=your-api-key
RISINGWAVE_HOST=0.0.0.0
RISINGWAVE_PORT=4566
RISINGWAVE_USER=root
RISINGWAVE_PASSWORD=root
RISINGWAVE_SSLMODE=disable
RISINGWAVE_TIMEOUT=30
```

---

### 2️⃣ Agent Code

- `agents/agent.py` → Implements the Claude agent and RisingWave MCP tool integration.
- `risingwave-agent.py` → Interactive CLI agent to process queries.

---

## 🚀 Run the Agent

Start your RisingWave MCP server (e.g. `python risingwave-mcp/src/main.py`) in a terminal.

In another terminal, run:

```bash
python risingwave-agent.py
```

You’ll enter an interactive prompt:

```
RisingWave Agent Interactive Mode
Type 'exit' or 'quit' to end the session
```

---

## 📝 Example Prompts

Try entering:

```
Give me the database version
Show me the s1 table structure and create an mv for tracking highest values
Display that newly created mv
```

---

## 📊 Optional: Load Test Data

Use RisingWave’s [Load Generator tutorial](https://docs.risingwave.com/ingestion/advanced/generate-test-data) to ingest sample data for analysis.

Or test the agent with any of the [available RisingWave demos](https://docs.risingwave.com/demos/overview).

---

## ✅ Cleanup

To reset your test environment:
- Drop any test tables or materialized views via the agent
- Or simply exit the terminal session

---

## 📖 Reference

For a complete implementation and more advanced stream processing demos, check out [awesome-stream-processing](https://github.com/risingwavelabs/awesome-stream-processing/).

---
