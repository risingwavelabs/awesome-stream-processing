"""Agent implementation with Claude API and MCP tools."""

import asyncio
import osz
from contextlib import AsyncExitStack
from dataclasses import dataclass
from typing import Any, Callable

from anthropic import Anthropic
from .utils.connections import setup_mcp_connections
from .utils.history_util import MessageHistory

from fastmcp import FastMCP

@dataclass
class ModelConfig:
    """Configuration settings for Claude model parameters."""

    model: str = "claude-sonnet-4-20250514"
    max_tokens: int = 4096
    temperature: float = 1.0
    context_window_tokens: int = 180000


class Agent:
    """Claude-powered agent with MCP tool capabilities."""

    def __init__(
        self,
        name: str,
        system: str,
        mcp_servers: list[dict[str, Any]] | None = None,
        config: ModelConfig | None = None,
        verbose: bool = False,
        client: Anthropic | None = None,
        message_params: dict[str, Any] | None = None,
    ):
        """Initialize an Agent.
        
        Args:
            name: Agent identifier for logging
            system: System prompt for the agent
            mcp_servers: MCP server configurations
            config: Model configuration with defaults
            verbose: Enable detailed logging
            client: Anthropic client instance
            message_params: Additional parameters for client.messages.create().
                           These override any conflicting parameters from config.
        """
        self.name = name
        self.system = system
        self.verbose = verbose
        self.config = config or ModelConfig()
        self.mcp_servers = mcp_servers or []
        self.message_params = message_params or {}
        self.client = client or Anthropic(
            api_key=os.environ.get("ANTHROPIC_API_KEY", "")
        )
        self.history = MessageHistory(
            model=self.config.model,
            system=self.system,
            context_window_tokens=self.config.context_window_tokens,
            client=self.client,
        )

        if self.verbose:
            print(f"\n[{self.name}] Agent initialized")

    def _prepare_message_params(self, tools: list[dict[str, Any]]) -> dict[str, Any]:
        """Prepare parameters for client.messages.create() call."""
        return {
            "model": self.config.model,
            "max_tokens": self.config.max_tokens,
            "temperature": self.config.temperature,
            "system": self.system,
            "messages": self.history.format_for_api(),
            "tools": tools,
            **self.message_params,
        }

    async def _agent_loop(self, user_input: str, tools: list[dict[str, Any]], tool_functions: dict[str, Callable]) -> list[dict[str, Any]]:
        """Process user input and handle tool calls in a loop"""
        if self.verbose:
            print(f"\n[{self.name}] Received: {user_input}")
        await self.history.add_message("user", user_input, None)

        while True:
            self.history.truncate()
            params = self._prepare_message_params(tools)

            response = self.client.messages.create(**params)
            tool_calls = [
            block for block in response.content if block.type == "tool_use"
        ]           

            if self.verbose:
                for block in response.content:
                    if block.type == "text":
                        print(f"\n[{self.name}] Output: {block.text}")
                    elif block.type == "tool_use":
                        params_str = ", ".join(
                            [f"{k}={v}" for k, v in block.input.items()]
                        )
                        print(
                            f"\n[{self.name}] Tool call: "
                            f"{block.name}({params_str})"
                        )

            await self.history.add_message(
                "assistant", response.content, response.usage
            )

            if tool_calls:
                tool_results = []
                for call in tool_calls:
                    try:
                        if call.name in tool_functions:
                            result = await tool_functions[call.name](**call.input)
                            tool_results.append({
                                "type": "tool_result",
                                "tool_use_id": call.id,
                                "content": str(result)
                            })
                        else:
                            tool_results.append({
                                "type": "tool_result",
                                "tool_use_id": call.id,
                                "content": f"Tool '{call.name}' not found",
                                "is_error": True
                            })
                    except Exception as e:
                        tool_results.append({
                            "type": "tool_result",
                            "tool_use_id": call.id,
                            "content": f"Error executing tool: {str(e)}",
                            "is_error": True
                        })
                
                if self.verbose:
                    for block in tool_results:
                        print(
                            f"\n[{self.name}] Tool result: "
                            f"{block.get('content')}"
                        )
                await self.history.add_message("user", tool_results)
            else:
                return response

    async def run_async(self, user_input: str) -> list[dict[str, Any]]:
        """Run agent with MCP tools asynchronously."""
        async with AsyncExitStack() as stack:
            try:
                mcp_tools, tool_functions = await setup_mcp_connections(
                    self.mcp_servers, stack
                )
                return await self._agent_loop(user_input, mcp_tools, tool_functions)
            except Exception as e:
                print(f"Error running agent: {e}")
                return None

    def run(self, user_input: str) -> list[dict[str, Any]]:
        """Run agent synchronously"""
        return asyncio.run(self.run_async(user_input))

"""Core agent implementations."""

from .agent import Agent, ModelConfig

__all__ = ["Agent", "ModelConfig"]
