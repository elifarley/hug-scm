#!/usr/bin/env python3
"""MCP Server for Hug SCM commands."""

import asyncio
import os
import subprocess
from collections.abc import Sequence
from typing import Any

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool

# Initialize the MCP server
app = Server("hug-scm-mcp-server")


def run_hug_command(args: Sequence[str], cwd: str | None = None) -> dict[str, Any]:
    """
    Execute a hug command and return the result.

    Args:
        args: Command arguments (e.g., ['h', 'files', '3'])
        cwd: Working directory for the command

    Returns:
        Dictionary with 'success', 'output', and optionally 'error'
    """
    try:
        # Ensure hug is in PATH
        cmd = ["hug"] + list(args)

        result = subprocess.run(
            cmd,
            cwd=cwd or os.getcwd(),
            capture_output=True,
            text=True,
            timeout=30,
        )

        return {
            "success": result.returncode == 0,
            "output": result.stdout,
            "error": result.stderr if result.returncode != 0 else None,
            "exit_code": result.returncode,
        }
    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "output": "",
            "error": "Command timed out after 30 seconds",
            "exit_code": -1,
        }
    except FileNotFoundError:
        return {
            "success": False,
            "output": "",
            "error": "Hug command not found. Please ensure Hug SCM is installed and in PATH.",
            "exit_code": -1,
        }
    except Exception as e:
        return {
            "success": False,
            "output": "",
            "error": f"Error executing command: {str(e)}",
            "exit_code": -1,
        }


@app.list_tools()
async def list_tools() -> list[Tool]:
    """List available Hug SCM tools."""
    return [
        Tool(
            name="hug_h_files",
            description=(
                "Preview files and line change stats touched by commits. "
                "Useful for understanding what files were modified in recent commits "
                "or in local-only commits not yet pushed."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "count": {
                        "type": "integer",
                        "description": "Number of commits to look back (default: 1)",
                        "minimum": 1,
                    },
                    "commit": {
                        "type": "string",
                        "description": "Specific commit to compare against HEAD",
                    },
                    "upstream": {
                        "type": "boolean",
                        "description": "Show files in local-only commits (not pushed)",
                        "default": False,
                    },
                    "temporal": {
                        "type": "string",
                        "description": (
                            "Time-based filter (e.g., '3 days ago', '1 week ago', '2024-01-15')"
                        ),
                    },
                    "show_patch": {
                        "type": "boolean",
                        "description": "Show full diff before stats",
                        "default": False,
                    },
                    "cwd": {
                        "type": "string",
                        "description": "Working directory (defaults to current directory)",
                    },
                },
            },
        ),
        Tool(
            name="hug_status",
            description=(
                "Get repository status showing modified, staged, and untracked files. "
                "Provides a clear overview of the current state of the working directory."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "format": {
                        "type": "string",
                        "enum": ["short", "long"],
                        "description": "Status format: 'short' (sl) or 'long' (s)",
                        "default": "short",
                    },
                    "cwd": {
                        "type": "string",
                        "description": "Working directory (defaults to current directory)",
                    },
                },
            },
        ),
        Tool(
            name="hug_log",
            description=(
                "View commit history with various filters. "
                "Shows commit messages, authors, and dates."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "count": {
                        "type": "integer",
                        "description": "Number of commits to show (default: 10)",
                        "minimum": 1,
                        "default": 10,
                    },
                    "file": {
                        "type": "string",
                        "description": "Show commits that modified this file",
                    },
                    "search": {
                        "type": "string",
                        "description": "Search for commits containing this text in message",
                    },
                    "oneline": {
                        "type": "boolean",
                        "description": "Show one line per commit",
                        "default": False,
                    },
                    "cwd": {
                        "type": "string",
                        "description": "Working directory (defaults to current directory)",
                    },
                },
            },
        ),
        Tool(
            name="hug_branch_list",
            description=(
                "List branches in the repository. "
                "Shows all branches with indication of current branch."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "all": {
                        "type": "boolean",
                        "description": "Include remote branches",
                        "default": False,
                    },
                    "verbose": {
                        "type": "boolean",
                        "description": "Show more details (last commit info)",
                        "default": False,
                    },
                    "cwd": {
                        "type": "string",
                        "description": "Working directory (defaults to current directory)",
                    },
                },
            },
        ),
        Tool(
            name="hug_h_steps",
            description=(
                "Find how many steps (commits) back from HEAD to the last change in a file. "
                "Useful for understanding when a file was last modified."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "file": {
                        "type": "string",
                        "description": "File path to check",
                    },
                    "raw": {
                        "type": "boolean",
                        "description": "Show raw step count only",
                        "default": False,
                    },
                    "cwd": {
                        "type": "string",
                        "description": "Working directory (defaults to current directory)",
                    },
                },
                "required": ["file"],
            },
        ),
        Tool(
            name="hug_show_diff",
            description=(
                "Show changes in the working directory or between commits. "
                "Can show unstaged changes, staged changes, or diff between commits."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "staged": {
                        "type": "boolean",
                        "description": "Show staged changes (default: show unstaged)",
                        "default": False,
                    },
                    "file": {
                        "type": "string",
                        "description": "Show diff for specific file only",
                    },
                    "commit1": {
                        "type": "string",
                        "description": "First commit for comparison",
                    },
                    "commit2": {
                        "type": "string",
                        "description": "Second commit for comparison (default: HEAD)",
                    },
                    "stat": {
                        "type": "boolean",
                        "description": "Show only statistics, not full diff",
                        "default": False,
                    },
                    "cwd": {
                        "type": "string",
                        "description": "Working directory (defaults to current directory)",
                    },
                },
            },
        ),
    ]


@app.call_tool()
async def call_tool(name: str, arguments: Any) -> Sequence[TextContent]:
    """Handle tool execution requests."""

    cwd = arguments.get("cwd")

    try:
        if name == "hug_h_files":
            args = ["h", "files"]

            if arguments.get("upstream"):
                args.append("-u")
            elif arguments.get("temporal"):
                args.extend(["-t", arguments["temporal"]])
            elif arguments.get("commit"):
                args.append(arguments["commit"])
            elif arguments.get("count"):
                args.append(str(arguments["count"]))

            if arguments.get("show_patch"):
                args.append("-p")

            result = run_hug_command(args, cwd)

        elif name == "hug_status":
            format_type = arguments.get("format", "short")
            args = ["sl" if format_type == "short" else "s"]
            result = run_hug_command(args, cwd)

        elif name == "hug_log":
            args = ["l"]

            count = arguments.get("count", 10)
            args.extend(["-n", str(count)])

            if arguments.get("oneline"):
                args.append("--oneline")

            if arguments.get("search"):
                args.extend(["--grep", arguments["search"]])

            if arguments.get("file"):
                args.extend(["--", arguments["file"]])

            result = run_hug_command(args, cwd)

        elif name == "hug_branch_list":
            args = ["b"]

            if arguments.get("all"):
                args.append("-a")

            if arguments.get("verbose"):
                args.append("-v")

            result = run_hug_command(args, cwd)

        elif name == "hug_h_steps":
            file = arguments.get("file")
            if not file:
                return [TextContent(type="text", text="Error: file parameter is required")]

            args = ["h", "steps", file]

            if arguments.get("raw"):
                args.append("--raw")

            result = run_hug_command(args, cwd)

        elif name == "hug_show_diff":
            # Determine the type of diff to show
            if arguments.get("commit1"):
                # Diff between commits
                args = ["--no-pager", "diff"]
                if arguments.get("stat"):
                    args.append("--stat")
                args.append(arguments["commit1"])
                if arguments.get("commit2"):
                    args.append(arguments["commit2"])
                if arguments.get("file"):
                    args.extend(["--", arguments["file"]])
                # Use git directly for commit diffs
                result = run_hug_command(args, cwd)
            elif arguments.get("staged"):
                # Staged changes
                args = ["ss"]
                if arguments.get("file"):
                    args.append(arguments["file"])
                result = run_hug_command(args, cwd)
            else:
                # Unstaged changes (default)
                args = ["sw"]
                if arguments.get("file"):
                    args.append(arguments["file"])
                result = run_hug_command(args, cwd)
        else:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]

        # Format the response
        if result["success"]:
            return [
                TextContent(
                    type="text", text=result["output"] if result["output"] else "(No output)"
                )
            ]
        else:
            error_msg = result.get("error", "Unknown error")
            output_text = result.get("output", "")
            return [
                TextContent(
                    type="text",
                    text=f"Error executing command:\n{error_msg}\n\nOutput:\n{output_text}",
                )
            ]

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
