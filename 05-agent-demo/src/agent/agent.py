"""Agent implementation with Claude API and MCP tools."""

import asyncio
import os
from contextlib import AsyncExitStack
from dataclasses import dataclass
from typing import Any, Callable

from anthropic import Anthropic
from fastmcp import FastMCP

"""Message history with token tracking and prompt caching."""

from typing import Any


class MessageHistory:
    """Manages chat history with token tracking and context management."""

    def __init__(
        self,
        model: str,
        system: str,
        context_window_tokens: int,
        client: Any,
        enable_caching: bool = True,
    ):
        self.model = model
        self.system = system
        self.context_window_tokens = context_window_tokens
        self.messages: list[dict[str, Any]] = []
        self.total_tokens = 0
        self.enable_caching = enable_caching
        self.message_tokens: list[tuple[int, int]] = (
            []
        )  # List of (input_tokens, output_tokens) tuples
        self.client = client

        # set initial total tokens to system prompt
        try:
            system_token = (
                self.client.messages.count_tokens(
                    model=self.model,
                    system=self.system,
                    messages=[{"role": "user", "content": "test"}],
                ).input_tokens
                - 1
            )

        except Exception:
            system_token = len(self.system) / 4

        self.total_tokens = system_token

    async def add_message(
        self,
        role: str,
        content: str | list[dict[str, Any]],
        usage: Any | None = None,
    ):
        """Add a message to the history and track token usage."""
        if isinstance(content, str):
            content = [{"type": "text", "text": content}]

        message = {"role": role, "content": content}
        self.messages.append(message)

        if role == "assistant" and usage:
            total_input = (
                usage.input_tokens
                + getattr(usage, "cache_read_input_tokens", 0)
                + getattr(usage, "cache_creation_input_tokens", 0)
            )
            output_tokens = usage.output_tokens

            current_turn_input = total_input - self.total_tokens
            self.message_tokens.append((current_turn_input, output_tokens))
            self.total_tokens += current_turn_input + output_tokens

    def truncate(self) -> None:
        """Remove oldest messages when context window limit is exceeded."""
        if self.total_tokens <= self.context_window_tokens:
            return

        TRUNCATION_NOTICE_TOKENS = 25
        TRUNCATION_MESSAGE = {
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "text": "[Earlier history has been truncated.]",
                }
            ],
        }

        def remove_message_pair():
            self.messages.pop(0)
            self.messages.pop(0)

            if self.message_tokens:
                input_tokens, output_tokens = self.message_tokens.pop(0)
                self.total_tokens -= input_tokens + output_tokens

        while (
            self.message_tokens
            and len(self.messages) >= 2
            and self.total_tokens > self.context_window_tokens
        ):
            remove_message_pair()

            if self.messages and self.message_tokens:
                original_input_tokens, original_output_tokens = (
                    self.message_tokens[0]
                )
                self.messages[0] = TRUNCATION_MESSAGE
                self.message_tokens[0] = (
                    TRUNCATION_NOTICE_TOKENS,
                    original_output_tokens,
                )
                self.total_tokens += (
                    TRUNCATION_NOTICE_TOKENS - original_input_tokens
                )

    def format_for_api(self) -> list[dict[str, Any]]:
        """Format messages for Claude API with optional caching."""
        result = [
            {"role": m["role"], "content": m["content"]} for m in self.messages
        ]

        if self.enable_caching and self.messages:
            result[-1]["content"] = [
                {**block, "cache_control": {"type": "ephemeral"}}
                for block in self.messages[-1]["content"]
            ]
        return result


"""Connection handling for MCP servers."""

from abc import ABC, abstractmethod
from contextlib import AsyncExitStack
from typing import Any, Callable, Tuple

from mcp import ClientSession, StdioServerParameters
from mcp.client.sse import sse_client
from mcp.client.stdio import stdio_client


class MCPConnection(ABC):
    """Base class for MCP server connections."""

    def __init__(self):
        self.session = None
        self._rw_ctx = None
        self._session_ctx = None

    @abstractmethod
    async def _create_rw_context(self):
        """Create the read/write context based on connection type."""

    async def __aenter__(self):
        """Initialize MCP server connection."""
        self._rw_ctx = await self._create_rw_context()
        read_write = await self._rw_ctx.__aenter__()
        read, write = read_write
        self._session_ctx = ClientSession(read, write)
        self.session = await self._session_ctx.__aenter__()
        await self.session.initialize()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Clean up MCP server connection resources."""
        try:
            if self._session_ctx:
                await self._session_ctx.__aexit__(exc_type, exc_val, exc_tb)
            if self._rw_ctx:
                await self._rw_ctx.__aexit__(exc_type, exc_val, exc_tb)
        except Exception as e:
            print(f"Error during cleanup: {e}")
        finally:
            self.session = None
            self._session_ctx = None
            self._rw_ctx = None

    async def list_tools(self) -> Any:
        """Retrieve available tools from the MCP server."""
        response = await self.session.list_tools()
        return response.tools

    async def call_tool(
        self, tool_name: str, arguments: dict[str, Any]
    ) -> Any:
        """Call a tool on the MCP server with provided arguments."""
        return await self.session.call_tool(tool_name, arguments=arguments)


class MCPConnectionStdio(MCPConnection):
    """MCP connection using standard input/output."""

    def __init__(
        self, command: str, args: list[str] = [], env: dict[str, str] = None
    ):
        super().__init__()
        self.command = command
        self.args = args
        self.env = env

    async def _create_rw_context(self):
        return stdio_client(
            StdioServerParameters(
                command=self.command, args=self.args, env=self.env
            )
        )


class MCPConnectionSSE(MCPConnection):
    """MCP connection using Server-Sent Events."""

    def __init__(self, url: str, headers: dict[str, str] = None):
        super().__init__()
        self.url = url
        self.headers = headers or {}

    async def _create_rw_context(self):
        return sse_client(url=self.url, headers=self.headers)


def create_mcp_connection(config: dict[str, Any]) -> MCPConnection:
    """Factory function to create the appropriate MCP connection."""
    conn_type = config.get("type", "stdio").lower()

    if conn_type == "stdio":
        if not config.get("command"):
            raise ValueError("Command is required for STDIO connections")
        return MCPConnectionStdio(
            command=config["command"],
            args=config.get("args"),
            env=config.get("env"),
        )

    elif conn_type == "sse":
        if not config.get("url"):
            raise ValueError("URL is required for SSE connections")
        return MCPConnectionSSE(
            url=config["url"], headers=config.get("headers")
        )

    else:
        raise ValueError(f"Unsupported connection type: {conn_type}")


async def setup_mcp_connections(
    mcp_servers: list[dict[str, Any]] | None,
    stack: AsyncExitStack,
) -> Tuple[list[dict[str, Any]], dict[str, Callable]]:
    """Set up MCP server connections and create tool interfaces."""
    if not mcp_servers:
        return [], {}

    mcp_tools = []
    tool_functions = {}

    for config in mcp_servers:
        try:
            connection = create_mcp_connection(config)
            await stack.enter_async_context(connection)
            tool_definitions = await connection.list_tools()

            for tool_info in tool_definitions:
                # Add tool definition to tools list
                mcp_tools.append({
                    "name": tool_info.name,
                    "description": tool_info.description or f"MCP tool: {tool_info.name}",
                    "input_schema": tool_info.inputSchema,
                })
                
                # Create async wrapper for the tool function
                async def create_tool_wrapper(tool_name: str):
                    async def wrapper(**kwargs):
                        return await connection.call_tool(tool_name, kwargs)
                    return wrapper
                
                # Add tool function to dictionary
                tool_functions[tool_info.name] = await create_tool_wrapper(tool_info.name)

        except Exception as e:
            print(f"Error setting up MCP server {config}: {e}")

    print(
        f"Loaded {len(mcp_tools)} MCP tools from {len(mcp_servers)} servers."
    )
    return mcp_tools, tool_functions



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

