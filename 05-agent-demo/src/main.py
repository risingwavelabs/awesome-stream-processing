"""Client for interacting with RisingWave via MCP and Anthropic."""

import os
import sys
import asyncio
import json
import re
from fastmcp import Client
from anthropic import Anthropic
from tabulate import tabulate
from dotenv import load_dotenv

def try_print_table(result):
    """Try to print a result as a table if possible."""
    try:
        data = json.loads(result)
        if isinstance(data, list) and all(isinstance(row, dict) for row in data):
            print(tabulate(data, headers="keys", tablefmt="github"))
            return True
        if isinstance(data, list) and all(isinstance(row, list) for row in data):
            print(tabulate(data, tablefmt="github"))
            return True
    except (json.JSONDecodeError, TypeError):
        if isinstance(result, list) and len(result) == 1 and hasattr(result[0], "text"):
            return True
    return False


def extract_table_names(query):
    """Extract table names from a SQL query string."""
    cleaned = re.sub(r"\b(the|a|an)\b", "", query, flags=re.IGNORECASE)
    return re.findall(r"(?:from|in|of|table|view|into)\s+([a-zA-Z0-9_]+)", cleaned, re.IGNORECASE)


class RisingWaveMCPAgent:
    """Agent for interacting with RisingWave via MCP and Anthropic."""

    def __init__(self, server_script_path: str):
        """Initialize the agent and set up environment variables."""
        self.client = Client(server_script_path)
        env = {
            "RISINGWAVE_HOST": os.getenv("RISINGWAVE_HOST", "0.0.0.0"),
            "RISINGWAVE_USER": os.getenv("RISINGWAVE_USER", "root"),
            "RISINGWAVE_PASSWORD": os.getenv("RISINGWAVE_PASSWORD", "root"),
            "RISINGWAVE_PORT": os.getenv("RISINGWAVE_PORT", "4566"),
            "RISINGWAVE_DATABASE": os.getenv("RISINGWAVE_DATABASE", "dev"),
            "RISINGWAVE_SSLMODE": os.getenv("RISINGWAVE_SSLMODE", "disable")
        }
        self.client.transport.env = env
        self.anthropic = Anthropic()
        self.conversation = []
        self._tools_cache = None
        self.table_cache = set()
        self.mv_cache = set()
        self.table_descriptions = {}
        self.mv_descriptions = {}
        self._init_done = False

    async def initialize_caches(self):
        """Initialize and cache table and materialized view names and their descriptions."""
        if self._init_done:
            return
        # Get table names
        try:
            tables_result = await self.client.call_tool("show_tables", {})
            tables = json.loads(tables_result) if isinstance(tables_result, str) else tables_result
            if isinstance(tables, list):
                for t in tables:
                    name = t[0] if isinstance(t, list) else t.get("table_name") or t.get("name")
                    if name:
                        self.table_cache.add(name)
                        # Cache description
                        try:
                            desc = await self.client.call_tool(
                                "describe_table", {"table_name": name}
                            )
                            self.table_descriptions[name] = desc
                        except Exception:
                            pass
        except Exception:
            pass
        # Get materialized view names
        try:
            mvs_result = await self.client.call_tool("list_materialized_views", {})
            mvs = json.loads(mvs_result) if isinstance(mvs_result, str) else mvs_result
            if isinstance(mvs, list):
                for mv in mvs:
                    name = mv[0] if isinstance(mv, list) else mv.get("name") or mv.get("mv_name")
                    if name:
                        self.mv_cache.add(name)
                        # Cache description
                        try:
                            desc = await self.client.call_tool(
                                "describe_materialized_view", {"mv_name": name}
                            )
                            self.mv_descriptions[name] = desc
                        except Exception:
                            pass
        except Exception:
            pass
        self._init_done = True

    async def list_tools(self):
        """List available tools from the client."""
        if self._tools_cache is None:
            tools = await self.client.list_tools()
            self._tools_cache = [{
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema
            } for tool in tools]
        return self._tools_cache

    async def __aenter__(self):
        """Async context manager entry."""
        await self.client.__aenter__()
        return self

    async def __aexit__(self, exc_type, exc, tb):
        """Async context manager exit."""
        await self.client.__aexit__(exc_type, exc, tb)

    async def call_tool(self, tool_name, args):
        """Call a tool by name with arguments."""
        return await self.client.call_tool(tool_name, args)

    async def fetch_schema_context(self, table_names):
        """Fetch schema context for a list of table names."""
        async def fetch(table):
            try:
                schema = await self.call_tool("describe_table", {"table_name": table})
                return f"Schema for table '{table}':\n{schema}"
            except Exception as exc:
                return f"Could not fetch schema for table '{table}': {exc}"
        return await asyncio.gather(*(fetch(table) for table in set(table_names)))

    async def handle_tool_use(self, content, final_text):
        """Handle tool use content from the LLM."""
        tool_name = content.name
        tool_args = content.input
        result = await self.call_tool(tool_name, tool_args)
        final_text.append(f"[Calling tool {tool_name} with args {tool_args}]")
        if not try_print_table(result):
            final_text.append(result)
        self.conversation.append({"role": "user", "content": result})

        response = self.anthropic.messages.create(
            model="claude-3-5-sonnet-20241022",
            max_tokens=1000,
            messages=self.conversation,
        )
        self.handle_llm_response(response, final_text)

    def handle_llm_response(self, response, final_text):
        """Handle the LLM response and update conversation."""
        if response.content and response.content[0].type == 'text':
            final_text.append(response.content[0].text)
            self.conversation.append({"role": "assistant", "content": response.content[0].text})

    async def process_query(self, query: str) -> str:
        """Process a user query and return the response."""
        await self.initialize_caches()
        self.conversation.append({"role": "user", "content": query})

        # Use cached table/mv names for extraction
        def extract_known_names(q):
            """Extract known table or materialized view names from the query."""
            words = set(re.findall(r"\b([a-zA-Z_][a-zA-Z0-9_]*)\b", q))
            found = [w for w in words if w in self.table_cache or w in self.mv_cache]
            return found
        table_names = extract_known_names(query)
        schema_contexts = []
        for t in table_names:
            if t in self.table_descriptions:
                schema_contexts.append(
                    f"Schema for table '{t}':\n{self.table_descriptions[t]}"
                )
            elif t in self.mv_descriptions:
                schema_contexts.append(
                    f"Schema for materialized view '{t}':\n{self.mv_descriptions[t]}"
                )

        messages = self.conversation.copy()
        for schema in schema_contexts:
            messages.append({"role": "user", "content": schema})

        tools = await self.list_tools()

        final_text = []
        while True:
            response = self.anthropic.messages.create(
                model="claude-3-5-sonnet-20241022",
                max_tokens=4096,
                messages=messages,
                tools=tools
            )

            tool_used = False
            for content in response.content:
                if content.type == 'text':
                    final_text.append(content.text)
                    self.conversation.append({"role": "assistant", "content": content.text})
                elif content.type == 'tool_use':
                    tool_used = True
                    await self.handle_tool_use(content, final_text)
                    messages = self.conversation.copy()
            if not tool_used:
                break

        return "\n".join(final_text)

    async def chat_loop(self):
        """Main chat loop for user interaction."""
        print("Rising Wave MCP Client Started!")
        print("Type your queries or 'quit' to exit.")
        while True:
            try:
                query = input("\nQuery: ").strip()
                if query.lower() == 'quit':
                    break
                response = await self.process_query(query)
                print("\n" + response)
            except Exception as exc:
                print(f"\nError: {str(exc)}")


async def main():
    """Entry point for the client."""
    load_dotenv()
    if len(sys.argv) < 2:
        print("Usage: python client.py <path_to_server_script>")
        sys.exit(1)

    server_script_path = sys.argv[1]
    async with RisingWaveMCPAgent(server_script_path) as client:
        await client.chat_loop()


if __name__ == "__main__":
    asyncio.run(main())
