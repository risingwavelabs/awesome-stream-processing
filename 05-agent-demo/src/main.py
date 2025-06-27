import asyncio
import json
import re
from fastmcp import Client
from anthropic import Anthropic
from dotenv import load_dotenv
from tabulate import tabulate
import sys

load_dotenv()

def try_print_table(result):
    try:
        data = json.loads(result)
        
        if isinstance(data, list) and all(isinstance(row, dict) for row in data):
            print(tabulate(data, headers="keys", tablefmt="github"))
            return True
        if isinstance(data, list) and all(isinstance(row, list) for row in data):
            print(tabulate(data, tablefmt="github"))
            return True
    except Exception as e:
        if isinstance(result, list) and len(result) == 1 and hasattr(result[0], "text"):
            return True
        print(f"DEBUG: Could not parse result as table: {e}")
        print(f"DEBUG: Raw result: {result}")
    return False


def extract_table_names(query):
    return re.findall(r"(?:from|in|of|table|view|into)\\s+([a-zA-Z0-9_]+)", query, re.IGNORECASE)



class risingWaveMCPClient:
    def __init__(self, server_script_path: str):
        self.client = Client(server_script_path)
        self.anthropic = Anthropic()
        self.conversation = []
        self._tools_cache = None  # Add this

    async def list_tools(self):
        if self._tools_cache is None:
            tools = await self.client.list_tools()
            self._tools_cache = [{
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema
            } for tool in tools]
        return self._tools_cache

    async def __aenter__(self):
        await self.client.__aenter__()
        return self

    async def __aexit__(self, exc_type, exc, tb):
        await self.client.__aexit__(exc_type, exc, tb)

    async def call_tool(self, tool_name, args):
        return await self.client.call_tool(tool_name, args)

    async def fetch_schema_context(self, table_names):
        async def fetch(table):
            try:
                schema = await self.call_tool("describe_table", {"table_name": table})
                return f"Schema for table '{table}':\n{schema}"
            except Exception as e:
                return f"Could not fetch schema for table '{table}': {e}"
        return await asyncio.gather(*(fetch(table) for table in set(table_names)))

   

    async def handle_tool_use(self, content, final_text):
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
        if response.content and response.content[0].type == 'text':
            final_text.append(response.content[0].text)
            self.conversation.append({"role": "assistant", "content": response.content[0].text})

    async def process_query(self, query: str) -> str:
        self.conversation.append({"role": "user", "content": query})

        table_names = extract_table_names(query)
        schema_contexts = await self.fetch_schema_context(table_names) if table_names else []

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
                    # After handling, update messages for the next round
                    messages = self.conversation.copy()
            if not tool_used:
                break

        return "\n".join(final_text)

    async def chat_loop(self):
        print("\nContext-Aware MCP Client Started!")
        print("Type your queries or 'quit' to exit.")
        while True:
            try:
                query = input("\nQuery: ").strip()
                if query.lower() == 'quit':
                    break
                response = await self.process_query(query)
                print("\n" + response)
            except Exception as e:
                print(f"\nError: {str(e)}")

async def main():
    if len(sys.argv) < 2:
        print("Usage: python client.py <path_to_server_script>")
        sys.exit(1)
    server_script_path = sys.argv[1]
    async with risingWaveMCPClient(server_script_path) as client:
        await client.chat_loop()
        
if __name__ == "__main__":
    asyncio.run(main())
