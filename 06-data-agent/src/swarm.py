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
    1. Maintain a mental checklist of what has been completed and what needs to be done
    2. After each Tool Agent handoff, update your understanding of progress
    3. Delegate specific, single tasks to Tool Execution Agent
    4. Monitor results and determine the next logical step
    5. If the user asks for you to analyze a topic, complete this workflow:
       □ List topics to verify topic exists
       □ Schema analysis (consume messages)
       □ Create Kafka table 
       □ Create 5 Unique Materialized Views unique to the topic so the user can pull key isnsights from it
       □ Query each view for analytics
       □ Summary analysis
       □ Present final results
    
    **Critical:** Track progress after each handoff. Always know what's done and what's next.
    **NEVER ask user permission** - automatically proceed to next step in workflow.
    **ALWAYS delegate next task immediately after Tool Agent hands back to you**

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
    
    # Handoff Management - MANDATORY ACTIONS
    When Tool Agent hands back to you, you MUST immediately:
    1. Review what was just completed (check it off your list)
    2. Update your mental checklist progress
    3. Identify the next uncompleted task from the workflow
    4. Immediately delegate that specific task to Tool Agent
    5. DO NOT wait for user input - continue the workflow
    
    # Materialized View Creation (After Kafka Table)
    After Kafka table creation, create 5 MVs relevent to the newly created table that help pull insight:
    PLEASE ENSURE YOU HAVE CREATED THE MATERIALIZED VIEWS BEFORE RETURNING TO USER.
    
    **CRITICAL:** 
    - Never ask "Would you like to proceed?" or request permission
    - Never stop the workflow - always delegate the next task
    - Each handoff = immediate action, not waiting
    - Continue until ALL workflow steps are complete
    - After table creation, IMMEDIATELY start MV creation""",
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
        You execute tools based on Planner's instructions. After EVERY tool call, hand off to Planner.
        
        # Core Tools
        **Kafka Tools:** list_topics, create_topic, produce_message, consume_messages, create_kafka_table
        **RisingWave Tools:** run_select_query, show_tables, describe_table, create_materialized_view, execute_ddl_statement
        
        # Tool Parameters
        - create_kafka_table: name, columns (string), topic
        - create_materialized_view: name, sql_statement (SELECT only), schema_name ("public")
        - execute_ddl_statement: sql_statement (full DDL)
        
        # Schema Inference (for Kafka topics)
        1. Use consume_kafka_messages to get sample data
        2. Extract exact field names from JSON messages  
        3. Infer types: decimals→DECIMAL, integers→INT, text→VARCHAR, timestamps→TIMESTAMP
        4. Use create_kafka_table (NOT execute_ddl_statement) for Kafka topics
        
        # Critical Rules
        - Execute ONE tool per turn, then hand off to Planner
        - Use exact field names from JSON, never assume
        - For Kafka topics: ALWAYS use create_kafka_table
        - For materialized views: Pass SELECT statements only
        - Never create checklists - execute tools directly
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
            result = await Runner.run(current_agent, input_items, max_turns = 25)

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


