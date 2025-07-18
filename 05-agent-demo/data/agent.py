#!/usr/bin/env python3
"""
Plan-and-Execute Agent using LangGraph

This script implements a plan-and-execute pattern agent using LangGraph.
Inspired by the Plan-and-Solve paper and Baby-AGI project.
"""

import os
import getpass
import operator
import asyncio
from typing import Annotated, List, Tuple, Union
from typing_extensions import TypedDict

from pydantic import BaseModel, Field
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.tools import StructuredTool
from langchain_openai import ChatOpenAI
from langchain_mcp_adapters.client import MultiServerMCPClient
from langgraph.prebuilt import create_react_agent
from langgraph.graph import StateGraph, START, END
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# MCP Client setup
client = MultiServerMCPClient(
    {
        "risingwave": {
            "command": "python",
            "args": ["risingwave-mcp/src/main.py"],
            "transport": "stdio",
            "env": {
                "RISINGWAVE_HOST": "0.0.0.0",
                "RISINGWAVE_USER": "root",
                "RISINGWAVE_PASSWORD": "root",
                "RISINGWAVE_PORT": "4566",
                "RISINGWAVE_DATABASE": "dev",
                "RISINGWAVE_SSLMODE": "disable",
                "RISINGWAVE_TIMEOUT": "30"
            }
        },
        "kafka": {
            "command": "mcp-kafka/bin/mcp-kafka-darwin-arm64",
            "args": [
                "--bootstrap-servers=localhost:9092",
                "--consumer-group-id=mcp-kafka-consumer-group",
                "--username=",
                "--password="
            ],
            "transport": "stdio",
            "env": {}
        }
    }
)

def _set_env(var: str):
    """Set environment variable if not already set."""
    if not os.environ.get(var):
        os.environ[var] = getpass.getpass(f"{var}: ")

def setup_environment():
    """Setup required API keys."""
    print("Setting up environment variables...")
    _set_env("OPENAI_API_KEY")
    print("Environment setup complete!")

# Define State
class PlanExecute(TypedDict):
    """State for the plan-and-execute agent."""
    input: str
    plan: List[str]
    past_steps: Annotated[List[Tuple], operator.add]
    response: str

# Define Pydantic Models
class Plan(BaseModel):
    """Plan to follow in future."""
    steps: List[str] = Field(
        description="different steps to follow, should be in sorted order"
    )

class Response(BaseModel):
    """Response to user."""
    response: str

class Act(BaseModel):
    """Action to perform."""
    action: Union[Response, Plan] = Field(
        description="Action to perform. If you want to respond to user, use Response. "
        "If you need to further use tools to get the answer, use Plan."
    )
    
    @classmethod
    def parse_raw_response(cls, raw_response):
        """Parse raw response from LLM into proper Act format."""
        if isinstance(raw_response, dict):
            # Handle {'Response': 'text'} format
            if 'Response' in raw_response:
                return cls(action=Response(response=raw_response['Response']))
            # Handle {'Plan': ['step1', 'step2']} format
            elif 'Plan' in raw_response:
                return cls(action=Plan(steps=raw_response['Plan']))
            # Handle proper format {'action': {...}}
            elif 'action' in raw_response:
                return cls(**raw_response)
        return raw_response

async def setup_tools():
    """Setup the tools for the agent using MCP client."""
    tools = await client.get_tools()

    sync_tools = []
    for mcp_tool in tools:
        def create_sync_wrapper(async_tool):
            def sync_wrapper(**kwargs):
                """Sync wrapper for async MCP tool"""
                try:
                    try:
                        loop = asyncio.get_event_loop()
                        if loop.is_running():
                            import concurrent.futures
                            with concurrent.futures.ThreadPoolExecutor() as executor:
                                future = executor.submit(asyncio.run, async_tool.ainvoke(kwargs))
                                return future.result()
                        else:
                            return loop.run_until_complete(async_tool.ainvoke(kwargs))
                    except RuntimeError:
                        return asyncio.run(async_tool.ainvoke(kwargs))
                except Exception as e:
                    return f"Error: {e}"

            sync_tool = StructuredTool.from_function(
                func=sync_wrapper,
                name=async_tool.name,
                description=async_tool.description,
                args_schema=async_tool.args_schema if hasattr(async_tool, 'args_schema') else None
            )
            return sync_tool
        sync_tools.append(create_sync_wrapper(mcp_tool))
    
    return sync_tools

async def setup_execution_agent():
    """Create the execution agent."""
    llm = ChatOpenAI(model="gpt-4o-mini", temperature=0)
    tools = await setup_tools()
    prompt = "You are a direct, efficient assistant. Use the available tools immediately to complete tasks. Be concise in your responses. If a tool gives you the answer, simply return that answer without additional explanation."
    agent_executor = create_react_agent(llm, tools, prompt=prompt)
    return agent_executor

async def setup_planner():
    """Create the planner."""
    # Get the available tools to include in the prompt
    tools = await setup_tools()
    tool_names = [tool.name for tool in tools]
    # Escape curly braces in tool descriptions to avoid template variable conflicts
    tool_descriptions = [f"- {tool.name}: {tool.description.replace('{', '{{').replace('}', '}}')}" for tool in tools]
    
    planner_prompt = ChatPromptTemplate.from_messages([
        (
            "system",
            f"""Using this list of available tools, determine if the user's request requires tool use:

{chr(10).join(tool_descriptions)}

If the user's request matches one of these tools, create a 1-step plan to use that specific tool.
If the user's request is conversational ("yes", "no", "ok", "thanks", etc.) or doesn't require any tools, create a 1-step plan: "Respond conversationally to the user"

Examples:
- "get db version" → "Use get_database_version tool"
- "show tables" → "Use show_tables tool"
- "list topics" → "Use list_topics tool"
- "yes" → "Respond conversationally to the user"
- "thanks" → "Respond conversationally to the user"

ALWAYS create the simplest possible plan. Use tools only when the request clearly matches a tool's purpose.""",
        ),
        ("placeholder", "{{messages}}"),
    ])
    
    planner = planner_prompt | ChatOpenAI(
        model="gpt-4o-mini", temperature=0
    ).with_structured_output(Plan)
    
    return planner

def setup_replanner():
    """Create the replanner."""
    replanner_prompt = ChatPromptTemplate.from_template(
        """For the given objective, decide if you need to continue with more steps or if you can provide the final answer.

Your objective was this:
{input}

Your original plan was this:
{plan}

You have currently done the follow steps:
{past_steps}

If the task is complete and you have the answer, return a Response with the final answer.
If you need more steps, return a Plan with the remaining steps.
"""
    )
    
    replanner = replanner_prompt | ChatOpenAI(
        model="gpt-4o-mini", temperature=0
    ).with_structured_output(Act)
    
    return replanner

async def create_plan_execute_graph():
    """Create the main plan-and-execute graph."""
    # Setup components
    agent_executor = await setup_execution_agent()
    planner = await setup_planner()
    replanner = setup_replanner()
    
    # Define node functions
    async def execute_step(state: PlanExecute):
        """Execute the current step in the plan."""
        plan = state["plan"]
        
        # Handle empty plan
        if not plan:
            return {"response": "Task completed successfully!"}
        
        plan_str = "\n".join(f"{i+1}. {step}" for i, step in enumerate(plan))
        task = plan[0]
        task_formatted = f"""For the following plan:
{plan_str}

You are tasked with executing step 1: {task}."""
        
        agent_response = await agent_executor.ainvoke(
            {"messages": [("user", task_formatted)]}
        )
        
        # Remove the completed step from the plan
        remaining_plan = plan[1:] if len(plan) > 1 else []
        
        return {
            "past_steps": [(task, agent_response["messages"][-1].content)],
            "plan": remaining_plan
        }
    
    async def plan_step(state: PlanExecute):
        """Create initial plan."""
        plan = await planner.ainvoke({"messages": [("user", state["input"])]})
        return {"plan": plan.steps}
    
    async def replan_step(state: PlanExecute):
        """Replan based on current state."""
        try:
            raw_output = await replanner.ainvoke(state)
            # Try to parse the output using our custom parser
            if hasattr(raw_output, 'action'):
                output = raw_output
            else:
                # If it's a raw dict, try to parse it
                output = Act.parse_raw_response(raw_output)
            
            if isinstance(output.action, Response):
                return {"response": output.action.response}
            else:
                return {"plan": output.action.steps}
        except Exception as e:
            print(f"Replan error: {e}")
            # If replanning fails, assume we're done
            return {"response": "Task completed."}
    
    def should_end(state: PlanExecute):
        """Determine if the process should end."""
        if "response" in state and state["response"]:
            return END
        elif "plan" in state and not state["plan"]:
            # If plan is empty, we should end
            return END
        else:
            return "agent"
    
    # Create the graph
    workflow = StateGraph(PlanExecute)
    
    # Add nodes
    workflow.add_node("planner", plan_step)
    workflow.add_node("agent", execute_step)
    workflow.add_node("replan", replan_step)
    
    # Add edges
    workflow.add_edge(START, "planner")
    workflow.add_edge("planner", "agent")
    workflow.add_edge("agent", "replan")
    workflow.add_conditional_edges(
        "replan",
        should_end,
        ["agent", END],
    )
    
    # Compile the graph
    app = workflow.compile()
    return app

async def run_plan_execute_agent_interactive(query: str, recursion_limit: int = 50):
    """Run the plan-and-execute agent with a given query in interactive mode."""
    app = await create_plan_execute_graph()
    config = {"recursion_limit": recursion_limit}
    inputs = {"input": query, "plan": [], "past_steps": []}
    
    agent_responses = []
    final_response = None
    
    async for event in app.astream(inputs, config=config):
        for k, v in event.items():
            if k != "__end__":
                # Extract and collect agent responses
                if k == "agent" and "past_steps" in v:
                    for step_name, step_response in v["past_steps"]:
                        agent_responses.append(step_response)
           
                elif k == "replan":
                    if "response" in v:
                        final_response = v["response"]
    
    # Display the most relevant response
    if final_response:
        print(f"\n🤖 Agent: {final_response}")
    elif agent_responses:
        # Show the last agent response
        print(f"\n🤖 Agent: {agent_responses[-1]}")
    else:
        print("\n🤖 Agent: I've completed the task!")
    
    return

async def interactive_chatbot():
    """Run the agent in interactive chatbot mode."""
    print("\n" + "="*60)
    print("PLAN-AND-EXECUTE CHATBOT")
    print("="*60)
    print("Type 'exit' or 'quit' to end the conversation")
    print("Type 'help' for available commands")
    print("-" * 60)
    
    while True:
        try:
            user_input = input("\nYou: ").strip()
            
            if user_input.lower() in ['exit', 'quit']:
                print("Goodbye!")
                break
            
            if user_input.lower() == 'help':
                print("""
Available commands:
- exit/quit: End the conversation
- help: Show this help message
- Any other text: Query the plan-and-execute agent

The agent will create a plan for your query and execute it step by step.
                """)
                continue
            
            if not user_input:
                print("Please enter a query or command.")
                continue
            
            print(f"\nAgent: Processing your query...")
            await run_plan_execute_agent_interactive(user_input)
            
        except KeyboardInterrupt:
            print("\n\nGoodbye!")
            break
        except Exception as e:
            print(f"\nError: {e}")
            print("Please try again.")

async def main():
    """Main function to demonstrate the plan-and-execute agent."""
    import sys
    setup_environment()
    await interactive_chatbot()

if __name__ == "__main__":
    asyncio.run(main())
