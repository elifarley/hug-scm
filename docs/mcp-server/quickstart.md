---
title: Quick Start
---

# Quick Start Guide

Get up and running with the Hug SCM MCP Server in 5 minutes.

## Prerequisites

✅ **Python 3.10+** installed
✅ **Hug SCM** installed and in PATH
✅ **pip** package manager

## Installation (30 seconds)

```bash
cd hug-scm-mcp-server
pip install -e .
```

## Verify Installation (10 seconds)

```bash
hug-scm-mcp-server --help
# or
which hug-scm-mcp-server
```

## Configure Claude Desktop (2 minutes)

### Step 1: Find your config file

- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
- **Linux**: `~/.config/Claude/claude_desktop_config.json`

### Step 2: Add the server

Edit the config file and add:

```json
{
  "mcpServers": {
    "hug-scm": {
      "command": "hug-scm-mcp-server",
      "args": []
    }
  }
}
```

### Step 3: Restart Claude Desktop

Close and reopen Claude Desktop to load the new server.

## Test It Out (2 minutes)

Open Claude Desktop and try these prompts:

### Basic Repository Status

```
"What's the current status of this repository?"
```

Claude will use `hug_status` to show you modified, staged, and untracked files.

### Recent Changes

```
"What files changed in the last 5 commits?"
```

Claude will use `hug_h_files` to show you the file changes and statistics.

### Commit History

```
"Show me the last 10 commits"
```

Claude will use `hug_log` to display recent commit history.

### Branch Information

```
"What branches exist in this project?"
```

Claude will use `hug_branch_list` to show all branches.

## Common First Questions

### "What can this MCP server do?"

The Hug SCM MCP Server gives AI assistants the ability to:
- Check repository status
- View commit history
- See file changes over time
- List branches
- Show diffs
- Find when files were last modified

All operations are **read-only** and **safe** for AI assistants to use.

### "Where should I run these commands?"

The commands work in any directory. You can specify the repository path:

```
"Check the status of /path/to/my/repo"
```

Or work in your current directory:

```
"What's the status here?"
```

### "What if something goes wrong?"

The server is designed to be safe:
- No destructive operations
- Commands timeout after 30 seconds
- All operations are read-only
- File paths are validated

If you encounter issues:
1. Check Hug is installed: `which hug`
2. Verify Python version: `python --version`
3. Reinstall if needed: `pip install -e .`

## Next Steps

✨ **Explore**: Try different prompts to see what the server can do
📖 **Learn**: Read [USAGE.md](USAGE.md) for detailed tool documentation
🎯 **Examples**: Check [EXAMPLES.md](EXAMPLES.md) for real-world scenarios

## Useful Prompts to Try

### Investigation
- "What files were changed in the last week?"
- "Show me commits that mention 'bug fix'"
- "When was server.py last modified?"

### Status Checks
- "Are there any uncommitted changes?"
- "What commits haven't been pushed yet?"
- "Show me what's staged for commit"

### History
- "What's the commit history for config.json?"
- "Show me the last 20 commits"
- "Find commits from last month"

### Comparison
- "What changed between HEAD and HEAD~5?"
- "Show me the diff for main.py"
- "Compare current branch with main"

## Troubleshooting

### "Command not found: hug"

**Solution**: Install Hug SCM from https://github.com/elifarley/hug-scm

```bash
# Clone and install Hug
git clone https://github.com/elifarley/hug-scm.git
cd hug-scm
./install.sh
source ~/.bashrc  # or ~/.zshrc
```

### "Server not responding"

**Solution**: Check the Claude Desktop logs or restart the application

1. Close Claude Desktop completely
2. Reopen it
3. Try your command again

### "Permission denied"

**Solution**: Make sure you have read access to the repository

```bash
ls -la /path/to/repository
```

## Development Mode

If you're developing or testing the server:

```bash
# Run tests
make test

# Format code
make format

# Lint code
make lint

# All checks
make check
```

## Getting Help

- 📚 **Documentation**: See [README.md](README.md)
- 🐛 **Issues**: Report at https://github.com/elifarley/hug-scm/issues
- 💬 **Discussions**: Join at https://github.com/elifarley/hug-scm/discussions

## Success!

If you can ask Claude questions about your repository and get answers, you're all set! 🎉

The MCP server is now enabling Claude to understand your code repository through Hug SCM commands.
