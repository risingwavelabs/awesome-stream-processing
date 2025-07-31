"""Data engineering agent swarm with RisingWave and Kafka integration."""

from __future__ import annotations as _annotations
from agents import (
    Agent,
    HandoffOutputItem,
    ItemHelpers,
    MessageOutputItem,
    Runner,
    ToolCallItem,
    ToolCallOutputItem,
    TResponseInputItem,
    handoff,
    trace,
    function_tool,
)
import asyncio
import uuid
from dotenv import load_dotenv
from agents.mcp import MCPServer, MCPServerStdio
import time
from agents.extensions.handoff_prompt import RECOMMENDED_PROMPT_PREFIX
from kafka import KafkaConsumer
import json

### KAFKA CONSUMER FUNCTION

@function_tool
def consume_kafka_messages(topic: str, max_messages: int = 5, timeout_seconds: int = 10) -> str:
    """
    Consume messages from a Kafka topic to infer schema.
    Returns JSON string with consumed messages.
    """
    try:
        consumer = KafkaConsumer(
            topic,
            bootstrap_servers=['localhost:9092'],
            auto_offset_reset='latest',  # Get recent messages
            consumer_timeout_ms=timeout_seconds * 1000,
            value_deserializer=lambda m: m.decode('utf-8'),
            group_id=f'schema-inference-{int(time.time())}'  # Unique group
        )
        
        messages = []
        count = 0
        
        for message in consumer:
            try:
                # Parse the JSON message
                msg_data = json.loads(message.value)
                messages.append({
                    "topic": message.topic,
                    "partition": message.partition,
                    "offset": message.offset,
                    "value": msg_data
                })
                count += 1
                if count >= max_messages:
                    break
            except json.JSONDecodeError:
                # Skip non-JSON messages
                continue
        
        consumer.close()
        
        if not messages:
            return json.dumps({"error": "No messages found in topic", "topic": topic})
        
        return json.dumps({"messages": messages, "topic": topic, "count": len(messages)})
        
    except Exception as e:
        return json.dumps({"error": str(e), "topic": topic})

### AGENTS

planner = Agent(
    name="Planner Agent",
    handoff_description=(
        "Strategic planning agent that analyzes requirements and delegates "
        "specialized tasks."
    ),
    instructions=f"""{RECOMMENDED_PROMPT_PREFIX}
    You are a strategic planning agent for data engineering tasks. Your role is to:
    
    # Core Responsibilities
    1. Analyze user requirements and break down complex tasks
    2. Create execution plans using available tools and specialist agents
    3. Delegate specific tasks to appropriate agents based on their capabilities
    4. Monitor progress and replan when needed
    5. If a user asks you to do analysis on a kafka topic, you MUST complete the ENTIRE workflow:
    Before anything list all topics to ensure the topic exists
    a) First delegate schema analysis to Tool Execution Agent
    b) Use that schema to call create_kafka_table (NOT create_materialized_view) to CREATE TABLE in RisingWave
    c) Once table is created, delegate creation of 3-5 useful materialized views using create_materialized_view
    d) Then delegate querying each materialized view for analytics
    e) Finally delegate querying the overall data for summary analytics
    f) Present comprehensive analysis results to the user
    
    DO NOT stop after schema analysis - continue until all steps are complete! 

    # Available Tool Categories
    **RisingWave Database Tools (26 tools):**
    
    Query & Analysis:
    - run_select_query: Executes SELECT queries to retrieve data from tables and views. Pass sql_query parameter with your SELECT statement.
    - explain_query: Shows query execution plan for optimization analysis. Pass sql_query parameter to analyze performance.
    - table_row_count: Returns the number of rows in a specified table. Pass table_name parameter.
    - get_table_stats: Provides detailed statistics about table size and structure. Pass table_name parameter.
    
    Schema Discovery:
    - show_tables: Lists all tables and views in the current database. No parameters required.
    - describe_table: Shows column definitions and data types for a table. Pass table_name parameter.
    - list_databases: Returns all available databases in the RisingWave cluster. No parameters required.
    - check_table_exists: Verifies if a table exists before operations. Pass table_name parameter.
    
    DDL Operations:
    - create_materialized_view: Creates a materialized view from a SELECT statement. Pass name and schema (SELECT only) parameters.
    - drop_materialized_view: Removes an existing materialized view from the database. Pass view_name parameter.
    - execute_ddl_statement: Executes CREATE, ALTER, DROP statements for schema changes. Pass schema parameters.
    
    Kafka Integration:
    - create_kafka_table: Creates a table that reads from Kafka topics for stream processing. Pass name, columns (as string), and topic parameters.
    
    Management:
    - get_database_version: Returns the current RisingWave version information. No parameters required.
    - show_running_queries: Lists currently executing queries for monitoring. No parameters required.
    - flush_database: Forces database to flush all pending writes to storage. No parameters required.

    **Kafka Tools (6 tools):**
    
    Topic Management:
    - create_topic: Creates a new Kafka topic with specified partitions and replication. Pass topic_name, partitions, and replication_factor parameters.
    - list_topics: Shows all available Kafka topics in the cluster. No parameters required.
    - delete_topic: Removes a Kafka topic and all its data permanently. Pass topic_name parameter.
    - describe_topic: Provides detailed information about topic configuration and partitions. Pass topic_name parameter.
    
    Message Operations:
    - produce_message: Sends a message to a specified Kafka topic. Pass topic_name, message (as JSON string), and optional key parameters.
    - consume_messages: Reads messages from a Kafka topic for inspection or processing. Pass topic_name and optional max_messages parameters.
    - consume_kafka_messages: Local function that samples Kafka messages for schema inference. Pass topic, max_messages, and timeout_seconds parameters.
    
    # Delegation Strategy
    - For database schema exploration/queries → Hand off to Database Agent
    - For Kafka operations → Hand off to Streaming Agent  
    - For complex multi-system workflows → Coordinate between agents
    - Always explain your reasoning when delegating tasks
    
    # Planning Approach
    1. Understand the full scope of the user's request
    2. Identify which tools/agents are needed
    3. Create a logical sequence of operations
    4. Communicate the plan clearly before execution
    5. Ensure the handoff message maintains the entire set of tasks and emphasize the other agents to continue looping
    until completion of tasks.""",
    handoffs=[],
    tools=[],
)

async def run_swarm(rw_mcp: MCPServer, kafka_mcp: MCPServer):
    """Run the data engineering agent swarm."""
    # Create agents with MCP servers
    tools_executor = Agent(
        name="Tool Execution Agent",
        handoff_description="A helpful agent that can execute kafka or risingwave tools",
        instructions=f"""{RECOMMENDED_PROMPT_PREFIX}
        You are a tool execution agent with access to Kafka and RisingWave tools. 
        
        IMPORTANT: You must ACTUALLY USE the tools available to you, not just create checklists.
        
        When the planner delegates a task to you:
        1. IMMEDIATELY use the appropriate tool to complete the task
        2. For Kafka operations: use list_topics, create_topic, produce_message, consume_messages, etc.
        3. For RisingWave operations: use run_select_query, show_tables, describe_table, etc.
        4. For Kafka-RisingWave integration: use create_kafka_source, create_kafka_table
        5. IMPORTANT: When calling tools, use lowercase parameter names exactly as defined (name, columns, topic, etc.)
        
        **MANDATORY SCHEMA INFERENCE WORKFLOW:**
        When asked to create a Kafka table/source in RisingWave:
        a) ALWAYS FIRST use consume_kafka_messages to get sample data from the topic
           - This is a LOCAL function that bypasses MCP timeout issues
           - It returns JSON with actual message data: {{"messages": [...], "topic": "...", "count": N}}
        b) PARSE the returned JSON to extract the "messages" array
        c) ANALYZE the "value" field in each message to understand the JSON structure
        d) EXTRACT the exact field names from the JSON (e.g., if you see 
           "total_amount": 123.45, use "total_amount", NOT "sale_amount")
        e) INFER SQL data types based on values:
           - Numbers with decimals → DECIMAL
           - Whole numbers → INT or BIGINT  
           - Text/strings → VARCHAR
           - ISO timestamps → TIMESTAMP
           - Booleans → BOOLEAN
        f) CREATE column definitions using EXACT field names from the JSON
        g) THEN use create_kafka_table with the correctly inferred schema
        
        **CRITICAL TOOL PARAMETER SPECIFICATIONS:**
        
        **FOR KAFKA TOPIC ANALYSIS - ALWAYS USE create_kafka_table:**
        When analyzing a Kafka topic, ALWAYS use create_kafka_table to create a table that reads from Kafka:
        - name: table name (e.g., "product_sales")
        - columns: column definitions as string (e.g., "product_id VARCHAR, quantity INT, total_amount DECIMAL(10,2)")
        - topic: kafka topic name (e.g., "product_sales")
        
        **FOR REGULAR TABLE CREATION - USE execute_ddl_statement:**
        Only for non-Kafka tables:
        - sql_statement: Full CREATE TABLE statement (e.g., "CREATE TABLE product_sales (product_id VARCHAR, quantity INT)")
        
        **FOR MATERIALIZED VIEW CREATION - USE create_materialized_view:**
        - name: view name (e.g., "sales_summary")  
        - sql_statement: ONLY the SELECT part (e.g., "SELECT product_id, SUM(total_amount) FROM product_sales GROUP BY product_id")
        - schema_name: "public" (default)
        
        **CRITICAL DISTINCTION:**
        - Kafka Topics → Use create_kafka_table (connects to Kafka stream)
        - Regular Tables → Use execute_ddl_statement with full CREATE statement
        - Materialized Views → Use create_materialized_view with SELECT only
        - **NEVER** use execute_ddl_statement for Kafka topic analysis!
        
        **CRITICAL MESSAGE PARSING EXAMPLE:**
        If consume_messages returns: "Message received: topic=product_sales, 
        partition=0, offset=123, key=abc, value={{"product_id": 456,
        "sale_amount": 99.99}}"
        You must extract: {{"product_id": 456, "sale_amount": 99.99}}
        And use field names: product_id (INT), sale_amount (DECIMAL)
        
        **CRITICAL**: Never assume field names - always use the exact JSON 
        field names from consumed messages.
        
        6. Report the ACTUAL results back to the planner
        
        Do NOT create checklists or plans - EXECUTE the tools directly and provide results.
        IF YOU HAVE A LIST OF THINGS TO DO YOU MUST CONTINUE UNTIL ALL TASKS ARE COMPLETED. 
        AFTER EVERY TOOL USE, TAKE A LOOK AT THE TASK LIST AND USE YOUR PREVIOUS TOOL RESPONSE 
        TO COMPLETE THE FOLLOWING TASK.
        
        **CRITICAL FOR KAFKA TOPIC ANALYSIS:**
        When you complete schema analysis of a Kafka topic, DO NOT ask the user if they want to continue.
        AUTOMATICALLY proceed to:
        1. Create the Kafka table using create_kafka_table (NOT execute_ddl_statement) with the inferred schema
        2. Create 3-5 materialized views using create_materialized_view
        3. Query each materialized view for analytics
        4. Query the overall data for summary analytics
        5. Present comprehensive results
        
        NEVER stop and ask permission - complete the entire workflow automatically!
        REMEMBER: For Kafka topics, ALWAYS use create_kafka_table, NEVER execute_ddl_statement!
        """,
        mcp_servers=[rw_mcp, kafka_mcp],
        handoffs=[handoff(planner)],
        tools=[consume_kafka_messages]
    )

    planner.handoffs.append(tools_executor)

    # Initialize conversation
    current_agent: Agent = planner
    input_items: list[TResponseInputItem] = []
    conversation_id = str(int(time.time()))

    while True:

        user_input = input("Enter your message: ")
        with trace("Data Engineering Agent", group_id=conversation_id):
            input_items.append({"content": user_input, "role": "user"})
            result = await Runner.run(current_agent, input_items)

            for new_item in result.new_items:
                agent_name = new_item.agent.name
                if isinstance(new_item, MessageOutputItem):
                    print(f"{agent_name}: {ItemHelpers.text_message_output(new_item)}")
                elif isinstance(new_item, HandoffOutputItem):
                    print(
                        f"Handed off from {new_item.source_agent.name} to "
                        f"{new_item.target_agent.name}"
                    )
                elif isinstance(new_item, ToolCallItem):
                    print(f"{agent_name}: Calling a tool")
                elif isinstance(new_item, ToolCallOutputItem):
                    print(f"{agent_name}: Tool call output: {new_item.output}")
            input_items = result.to_input_list()
            current_agent = planner  # Always reset to planner for next user input

async def main():
    """Main function to start the data engineering agent swarm."""
    load_dotenv()
    async with MCPServerStdio(
        name="RisingWave MCP Server",
        params={
            "command": "python",
            "args": ["risingwave-mcp/src/main.py"],
            "env": {
                "RISINGWAVE_HOST": "0.0.0.0",
                "RISINGWAVE_USER": "root",
                "RISINGWAVE_PASSWORD": "root",
                "RISINGWAVE_PORT": "4566",
                "RISINGWAVE_DATABASE": "dev",
                "RISINGWAVE_SSLMODE": "disable",
                "RISINGWAVE_TIMEOUT": "60"
            }
        }
    ) as rw_mcp:
        async with MCPServerStdio(
            name="Kafka MCP Server",
            params={
                "command": "mcp-kafka/bin/mcp-kafka-darwin-arm64",
                "args": [
                    "--bootstrap-servers=localhost:9092",
                    f"--consumer-group-id=mcp-kafka-group-{int(time.time())}",
                    "--username=",
                    "--password="
                ],
            },
        ) as kafka_mcp:
            await run_swarm(rw_mcp, kafka_mcp)


if __name__ == "__main__":
    asyncio.run(main())


