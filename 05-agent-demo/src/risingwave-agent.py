from agents.agent import Agent
import os
from dotenv import load_dotenv


load_dotenv()


risingwave_env = {
    "RISINGWAVE_HOST": os.getenv("RISINGWAVE_HOST", "0.0.0.0"),
    "RISINGWAVE_PORT": os.getenv("RISINGWAVE_PORT", "4566"),
    "RISINGWAVE_USER": os.getenv("RISINGWAVE_USER", "root"),
    "RISINGWAVE_PASSWORD": os.getenv("RISINGWAVE_PASSWORD", "root"),
    "RISINGWAVE_SSLMODE": os.getenv("RISINGWAVE_SSLMODE", "disable"),
    "RISINGWAVE_TIMEOUT": os.getenv("RISINGWAVE_TIMEOUT", "30")
}

agent = Agent(
    name="RisingWave Agent",
    system="""You are an assistant to a Rising Wave MCP. Follow these rules:
    1. Only use SELECT queries with LIMIT clauses (max 10 rows)
    2. Keep responses under 100 words
    3. Only show essential data
    4. Avoid using unsupported functions (like STDDEV)
    5. If an error occurs, try a simpler query
    6. Focus on answering the user's specific question
    7. Format tables in a clean, readable way:
       - Use simple column names
       - Align columns properly
       - Include only necessary data
    8. Never repeat the same information
    9. If showing a table, show it only once with all needed data
    10. Keep the final response concise and focused on the key information
    11. Only give the response not the output
    12. Make one comprehensive query instead of multiple smaller ones
    13. Format numbers with proper currency symbols and decimal places
    14. Use markdown tables for better readability
    15. Skip intermediate steps and show only the final result
    16. Keep tool calls visible but minimize other debug output""",
    
    mcp_servers=[
        {
            "type": "stdio",
            "command": "python",
            "args": ["risingwave-mcp/src/main.py"],
            "env": risingwave_env  # Pass environment variables to MCP server
        },
    ],
    verbose=False  # Disable verbose mode to reduce noise
)

print("\nRisingWave Agent Interactive Mode")
print("Type 'exit' or 'quit' to end the session")
print("----------------------------------------")

while True:
    try:
        # Get user input
        user_input = input("\nEnter your query: ").strip()
        
        # Check for exit command
        if user_input.lower() in ['exit', 'quit']:
            print("\nEnding session. Goodbye!")
            break
            
        # Skip empty inputs
        if not user_input:
            continue
            
        # Get response from agent
        response = agent.run(user_input)
        
        # Clean up the response format
        if hasattr(response, 'content'):
            # Extract just the text content
            clean_response = response.content[0].text if isinstance(response.content, list) else response.content
            print("\n", clean_response)
        else:
            print("\n", response)
            
    except KeyboardInterrupt:
        print("\n\nSession interrupted. Goodbye!")
        break
    except Exception as e:
        print(f"\nAn error occurred: {str(e)}")
        print("Please try again with a different query.")
