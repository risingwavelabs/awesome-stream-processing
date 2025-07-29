"""Data engineering agent swarm with RisingWave and Kafka integration."""

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
)
import asyncio
import uuid
from dotenv import load_dotenv
from __future__ import annotations as _annotations
from agents.mcp import MCPServer, MCPServerStdio
from agents.extensions.handoff_prompt import RECOMMENDED_PROMPT_PREFIX

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
    
    # Available Tool Categories
    **RisingWave Database Tools (26 tools):**
    - Query & Analysis: run_select_query, explain_query, table_row_count, get_table_stats
    - Schema Discovery: show_tables, describe_table, list_databases, check_table_exists
    - DDL Operations: create_materialized_view, drop_materialized_view, execute_ddl_statement
    - Kafka Integration: create_kafka_table
    - Management: get_database_version, show_running_queries, flush_database
    -

    **Kafka Tools (6 tools):**
    - Topic Management: create_topic, list_topics, delete_topic, describe_topic
    - Message Operations: produce_message, consume_messages
    
    # Delegation Strategy
    - For database schema exploration/queries → Hand off to Database Agent
    - For Kafka operations → Hand off to Streaming Agent  
    - For complex multi-system workflows → Coordinate between agents
    - Always explain your reasoning when delegating tasks
    
    # Planning Approach
    1. Understand the full scope of the user's request
    2. Identify which tools/agents are needed
    3. Create a logical sequence of operations
    4. Communicate the plan clearly before execution""",
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
        a) ALWAYS FIRST use consume_messages to get sample data from the topic
           - IMPORTANT: Set consumer_timeout parameter to at least 15 seconds to 
             ensure messages are captured
           - The consume_messages tool returns verbose debug strings in format:
             "Message received: topic=X, partition=Y, offset=Z, key=K, value={{JSON}}"
        b) PARSE the consumed message strings to EXTRACT only the JSON value part after "value="
           - Look for the pattern "value=" and extract everything after it
           - This extracted part contains the actual JSON message data
        c) CAREFULLY ANALYZE the actual JSON structure in the extracted message values
        d) EXTRACT the exact field names from the JSON (e.g., if you see 
           "total_amount": 123.45, use "total_amount", NOT "sale_amount")
        e) INFER SQL data types based on values:
           - Numbers with decimals → DECIMAL or NUMERIC
           - Whole numbers → INT or BIGINT  
           - Text/strings → VARCHAR
           - ISO timestamps → TIMESTAMP
           - Booleans → BOOLEAN
        f) CREATE column definitions using EXACT field names from the JSON
        g) THEN use create_kafka_table with the correctly inferred schema
        
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
        """,
        mcp_servers=[rw_mcp, kafka_mcp],
        handoffs=[handoff(planner)]
    )

    planner.handoffs.append(tools_executor)

    # Initialize conversation
    current_agent: Agent = planner
    input_items: list[TResponseInputItem] = []
    conversation_id = uuid.uuid4().hex[:16]

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
                    "--consumer-group-id=mcp-kafka-test-group",
                    "--username=",
                    "--password="
                ],
            },
        ) as kafka_mcp:
            await run_swarm(rw_mcp, kafka_mcp)


if __name__ == "__main__":
    asyncio.run(main())
