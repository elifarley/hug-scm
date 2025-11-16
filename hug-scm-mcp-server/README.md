# Hug SCM MCP Server

A Model Context Protocol (MCP) server that provides AI assistants with access to [Hug SCM](https://github.com/elifarley/hug-scm) commands for investigating and understanding Git repositories.

## Overview

This MCP server exposes a curated set of Hug SCM commands as tools that AI assistants can use to:
- Understand repository structure and history
- Preview changes before operations
- Analyze file modifications over time
- Navigate repository state safely

## Features

### Available Tools

- **hug_h_files**: Preview files and stats touched by commits in a range
  - See what files were changed in the last N commits
  - Check local-only commits (not pushed to upstream)
  - Filter commits by time periods

- **hug_status**: Get repository status with beautiful output
  - Short status overview
  - Long detailed status

- **hug_log**: View commit history
  - Recent commits
  - Commits for specific files
  - Search commits by message

- **hug_branch_list**: List and inspect branches
  - All branches
  - Current branch
  - Remote branches

- **hug_h_steps**: Find how many steps back to a file's last change
  - Useful for precise navigation
  - Helps understand when a file was modified

- **hug_show_diff**: Show changes in working directory or commits
  - Unstaged changes
  - Staged changes
  - Diff between commits

## Installation

### Prerequisites

- Python 3.10 or higher
- [Hug SCM](https://github.com/elifarley/hug-scm) installed and in PATH

### Install from source

```bash
cd hug-scm-mcp-server
pip install -e ".[dev]"
```

### Using the Makefile

```bash
# Install package and dependencies
make install

# Install for development (with dev dependencies)
make install-dev

# Run tests
make test

# Run linter
make lint

# Format code
make format
```

## Usage

### As an MCP Server

Configure your MCP client (like Claude Desktop) to use this server:

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

### Command Line

You can also run the server directly for testing:

```bash
hug-scm-mcp-server
```

### Using stdio transport

The server uses stdio transport by default, suitable for MCP clients:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | hug-scm-mcp-server
```

## Development

### Running Tests

```bash
# Run all tests
make test

# Run tests with coverage report
pytest --cov=hug_scm_mcp_server --cov-report=html

# Run specific test file
pytest tests/test_server.py
```

### Code Quality

```bash
# Format code
make format

# Lint code
make lint

# Type check
make type-check
```

## Architecture

The server is built using:
- **MCP SDK**: For protocol implementation
- **asyncio**: For async operations
- **subprocess**: For executing Hug commands
- **pytest**: For comprehensive testing

## Examples

### Example: Check what files changed in last 3 commits

```python
# AI assistant can call:
hug_h_files(count=3)

# This executes: hug h files 3
# Returns: List of files with line change statistics
```

### Example: View repository status

```python
# AI assistant can call:
hug_status(format="short")

# This executes: hug sl
# Returns: Repository status with modified/staged/untracked files
```

### Example: Find when a file was last changed

```python
# AI assistant can call:
hug_h_steps(file="src/main.py")

# This executes: hug h steps src/main.py
# Returns: Number of commits since file was last modified
```

## Security

- All commands run with the permissions of the user running the server
- Commands are read-only by default (status, log, diff operations)
- No destructive operations are exposed
- File paths are validated and resolved to absolute paths to prevent directory traversal
- Working directory paths are verified to exist and be directories before command execution

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - See LICENSE file in the root of the Hug SCM repository.

## Related Projects

- [Hug SCM](https://github.com/elifarley/hug-scm) - The humane interface for Git and Mercurial
- [Model Context Protocol](https://modelcontextprotocol.io/) - Protocol for AI-tool integration

## Support

For issues and questions:
- Open an issue on [GitHub](https://github.com/elifarley/hug-scm/issues)
- Check the [Hug SCM documentation](https://elifarley.github.io/hug-scm/)
