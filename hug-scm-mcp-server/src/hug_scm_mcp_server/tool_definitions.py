"""Tool definitions and schemas for MCP tools."""

from mcp.types import Tool


def get_tool_definitions() -> list[Tool]:
    """
    Get all tool definitions with their schemas.

    Returns:
        List of Tool objects
    """
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
