---
title: Usage
---

# Usage Guide

This guide explains how to use the Hug SCM MCP Server with various MCP clients.

## Prerequisites

1. **Hug SCM** must be installed and available in your PATH
2. **Python 3.10+** is required
3. The MCP server package must be installed

## Installation

```bash
cd hug-scm-mcp-server
pip install -e .
```

## Configuration

### Claude Desktop

Add the following to your Claude Desktop configuration file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
**Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "hug-scm": {
      "command": "hug-scm-mcp-server",
      "args": [],
      "env": {
        "HUG_HOME": "/path/to/hug-scm"
      }
    }
  }
}
```

### Other MCP Clients

For other MCP clients, use the stdio transport:

```bash
hug-scm-mcp-server
```

The server reads JSON-RPC messages from stdin and writes responses to stdout.

## Available Tools

### 1. hug_h_files

Preview files and line change statistics touched by commits.

**Parameters:**
- `count` (optional, integer): Number of commits to look back (default: 1)
- `commit` (optional, string): Specific commit to compare against HEAD
- `upstream` (optional, boolean): Show files in local-only commits (default: false)
- `temporal` (optional, string): Time-based filter (e.g., "3 days ago", "1 week ago")
- `show_patch` (optional, boolean): Show full diff before stats (default: false)
- `cwd` (optional, string): Working directory

**Example usage in AI conversations:**

```
User: "What files changed in the last 3 commits?"
Assistant: [Uses hug_h_files with count=3]

User: "Show me all files modified in the last week"
Assistant: [Uses hug_h_files with temporal="1 week ago"]

User: "What files haven't been pushed yet?"
Assistant: [Uses hug_h_files with upstream=true]
```

### 2. hug_status

Get repository status showing modified, staged, and untracked files.

**Parameters:**
- `format` (optional, string): Status format - "short" or "long" (default: "short")
- `cwd` (optional, string): Working directory

**Example usage:**

```
User: "What's the current state of the repository?"
Assistant: [Uses hug_status with format="short"]

User: "Give me a detailed status"
Assistant: [Uses hug_status with format="long"]
```

### 3. hug_log

View commit history with various filters.

**Parameters:**
- `count` (optional, integer): Number of commits to show (default: 10)
- `file` (optional, string): Show commits that modified this file
- `search` (optional, string): Search for commits containing text
- `oneline` (optional, boolean): Show one line per commit (default: false)
- `cwd` (optional, string): Working directory

**Example usage:**

```
User: "Show me the last 5 commits"
Assistant: [Uses hug_log with count=5]

User: "Find commits that mention 'bug fix'"
Assistant: [Uses hug_log with search="bug fix"]

User: "What commits changed main.py?"
Assistant: [Uses hug_log with file="main.py"]
```

### 4. hug_branch_list

List branches in the repository.

**Parameters:**
- `all` (optional, boolean): Include remote branches (default: false)
- `verbose` (optional, boolean): Show more details (default: false)
- `cwd` (optional, string): Working directory

**Example usage:**

```
User: "What branches exist?"
Assistant: [Uses hug_branch_list]

User: "Show all branches including remotes"
Assistant: [Uses hug_branch_list with all=true]

User: "List branches with their last commits"
Assistant: [Uses hug_branch_list with verbose=true]
```

### 5. hug_h_steps

Find how many steps (commits) back from HEAD to the last change in a file.

**Parameters:**
- `file` (required, string): File path to check
- `raw` (optional, boolean): Show raw step count only (default: false)
- `cwd` (optional, string): Working directory

**Example usage:**

```
User: "When was server.py last modified?"
Assistant: [Uses hug_h_steps with file="server.py"]

User: "How many commits since utils.js changed?"
Assistant: [Uses hug_h_steps with file="utils.js", raw=true]
```

### 6. hug_show_diff

Show changes in the working directory or between commits.

**Parameters:**
- `staged` (optional, boolean): Show staged changes (default: false for unstaged)
- `file` (optional, string): Show diff for specific file only
- `commit1` (optional, string): First commit for comparison
- `commit2` (optional, string): Second commit for comparison
- `stat` (optional, boolean): Show only statistics (default: false)
- `cwd` (optional, string): Working directory

**Example usage:**

```
User: "What changes haven't been staged?"
Assistant: [Uses hug_show_diff with staged=false]

User: "Show me what's staged for commit"
Assistant: [Uses hug_show_diff with staged=true]

User: "What changed in config.json?"
Assistant: [Uses hug_show_diff with file="config.json"]

User: "Compare HEAD with previous commit"
Assistant: [Uses hug_show_diff with commit1="HEAD~1", commit2="HEAD"]
```

## Common AI Assistant Workflows

### Understanding a New Repository

```
1. Check repository status: hug_status
2. View recent history: hug_log (count=20)
3. List branches: hug_branch_list (all=true, verbose=true)
4. Check uncommitted changes: hug_show_diff
```

### Investigating a Bug

```
1. Find when file was last changed: hug_h_steps (file="problem_file.py")
2. View commits for that file: hug_log (file="problem_file.py", count=10)
3. Check what files changed together: hug_h_files (count=N)
4. Review the actual changes: hug_show_diff (commit1="COMMIT_HASH")
```

### Pre-commit Review

```
1. Check status: hug_status (format="long")
2. Review unstaged changes: hug_show_diff (staged=false)
3. Review staged changes: hug_show_diff (staged=true)
4. Verify files affected: hug_h_files (count=1, show_patch=true)
```

### Branch Analysis

```
1. List all branches: hug_branch_list (all=true, verbose=true)
2. Check local-only commits: hug_h_files (upstream=true)
3. View commits in current branch: hug_log (count=50)
```

## Tips and Best Practices

### 1. Start with Status

Always start by checking the repository status to understand the current state:

```
hug_status (format="short")
```

### 2. Use Time-Based Queries

For recent activity analysis, use temporal filters:

```
hug_h_files (temporal="3 days ago")
hug_log (count=100)  # Review last 100 commits
```

### 3. Investigate File History

To understand a file's evolution:

```
1. hug_h_steps (file="path/to/file")
2. hug_log (file="path/to/file")
3. hug_show_diff (file="path/to/file")
```

### 4. Check Before Push

Before pushing commits:

```
1. hug_h_files (upstream=true)  # See what will be pushed
2. hug_log (count=N)  # Review commit messages
```

### 5. Combine Tools

The tools work best when combined in a workflow:

```
Status → Log → Files → Diff → Steps
```

## Troubleshooting

### Server Not Starting

**Problem**: Server fails to start

**Solution**:
1. Verify Hug is installed: `which hug`
2. Check Python version: `python --version` (must be 3.10+)
3. Reinstall the package: `pip install -e .`

### Command Timeout

**Problem**: Commands timeout after 30 seconds

**Solution**:
- This is a safety feature for long-running operations
- If needed, break the query into smaller pieces
- Check if the repository is very large

### Hug Command Not Found

**Problem**: Error says "Hug command not found"

**Solution**:
1. Install Hug SCM: Follow [installation guide]
2. Add Hug to PATH: `export PATH="$PATH:/path/to/hug-scm/bin"`
3. Verify: `hug --version`

### No Output

**Problem**: Commands return empty output

**Solution**:
- This may be expected (e.g., clean working directory)
- Check the `cwd` parameter is correct
- Verify you're in a Git repository

## Security Considerations

### Read-Only Operations

All exposed tools are read-only operations:
- They don't modify the repository
- They don't create/delete files
- They only inspect the current state

### Safe for AI Assistants

The MCP server is designed to be safe for AI assistants:
- No destructive operations exposed
- Commands timeout after 30 seconds
- File paths are validated
- No shell injection possible

## Advanced Usage

### Custom Working Directory

Specify a different repository:

```json
{
  "cwd": "/path/to/other/repository"
}
```

### Performance Optimization

For large repositories:
1. Limit commit counts: `count=10` instead of `count=100`
2. Use specific file filters when possible
3. Avoid `show_patch=true` for many commits

### Integration with Other Tools

The MCP server can be used alongside:
- Git command-line tools
- GitHub CLI (gh)
- GitLab CLI (glab)
- Other version control tools

## Example Session

Here's a complete example of an AI assistant helping investigate a repository:

```
User: "I need to understand this repository"
