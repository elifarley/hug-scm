#!/usr/bin/env python3
"""MCP Server for Hug SCM commands - Refactored for modularity."""

import asyncio
from collections.abc import Sequence
from typing import Any

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool

from .command_executor import CommandExecutor
from .tool_definitions import get_tool_definitions
from .tool_handlers import ToolRegistry

# Initialize the MCP server
app = Server("hug-scm-mcp-server")

# Initialize command executor and tool registry
executor = CommandExecutor(timeout=30)
registry = ToolRegistry(executor)


@app.list_tools()
async def list_tools() -> list[Tool]:
    """
    List available Hug SCM tools.

    Returns:
        List of available MCP tools with their definitions
    """
    return get_tool_definitions()


@app.call_tool()
async def call_tool(name: str, arguments: Any) -> Sequence[TextContent]:
    """
    Handle tool execution requests.

    Args:
        name: Tool name to execute
        arguments: Tool arguments

    Returns:
        Sequence of text content with results or errors
    """
    try:
        # Get the handler for the requested tool
        handler = registry.get_handler(name)

        if not handler:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]

        # Execute the tool
        result = handler.handle(arguments)

        # Format the response
        if result["success"]:
            output = result["output"] if result["output"] else "(No output)"
            return [TextContent(type="text", text=output)]
        else:
            error_msg = result.get("error", "Unknown error")
            output_text = result.get("output", "")
            error_text = f"Error executing command:\n{error_msg}"
            if output_text:
                error_text += f"\n\nOutput:\n{output_text}"
            return [TextContent(type="text", text=error_text)]

    except Exception as e:
        return [TextContent(type="text", text=f"Error: {str(e)}")]


async def run_server() -> None:
    """Run the MCP server using stdio transport."""
    async with stdio_server() as (read_stream, write_stream):
        await app.run(read_stream, write_stream, app.create_initialization_options())


def main() -> None:
    """Main entry point for the server."""
    asyncio.run(run_server())


if __name__ == "__main__":
    main()
