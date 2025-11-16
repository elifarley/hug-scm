# Architecture Documentation

## Overview

The Hug SCM MCP Server follows a modular, layered architecture that separates concerns and promotes maintainability, extensibility, and testability.

## Design Principles

### 1. Separation of Concerns
Each module has a single, well-defined responsibility:
- **Command Execution** - Safe execution of external commands
- **Tool Handling** - Business logic for individual MCP tools
- **Tool Definitions** - MCP protocol schemas
- **Server Orchestration** - MCP protocol implementation

### 2. Dependency Injection
The `CommandExecutor` is injected into tool handlers, making them:
- Easier to test (can mock the executor)
- More flexible (can swap implementations)
- Decoupled from execution details

### 3. Registry Pattern
The `ToolRegistry` allows dynamic tool registration:
- Easy to add new tools
- Extensible by users
- Clear tool discovery mechanism

### 4. Fail-Safe Design
All operations are designed to fail gracefully:
- Command timeouts prevent hangs
- Path validation prevents security issues
- Error messages are user-friendly
- No exceptions bubble up to MCP layer

## Module Architecture

```
┌─────────────────────────────────────────────────────┐
│                  MCP Protocol Layer                  │
│                    (stdio transport)                 │
└────────────────────────┬────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│                    server.py                         │
│  ┌──────────────┐  ┌──────────────┐                │
│  │ list_tools() │  │ call_tool()  │                │
│  └──────┬───────┘  └───────┬──────┘                │
│         │                   │                        │
│         │                   ▼                        │
│         │          ┌─────────────────┐              │
│         │          │  ToolRegistry   │              │
│         │          └────────┬────────┘              │
│         │                   │                        │
│         ▼                   ▼                        │
│  ┌──────────────┐  ┌──────────────┐                │
│  │tool_         │  │tool_         │                │
│  │definitions   │  │handlers      │                │
│  │              │  │              │                │
│  │ - Schemas    │  │ - Logic      │                │
│  └──────────────┘  └──────┬───────┘                │
│                            │                        │
│                            ▼                        │
│                   ┌──────────────┐                 │
│                   │CommandExecutor│                │
│                   │              │                 │
│                   │ - Validation │                 │
│                   │ - Execution  │                 │
│                   └──────┬───────┘                 │
└──────────────────────────┼─────────────────────────┘
                           │
                           ▼
                   ┌──────────────┐
                   │ subprocess   │
                   │              │
                   │ Hug Commands │
                   └──────────────┘
```

## Module Descriptions

### command_executor.py

**Purpose:** Safe execution of Hug SCM commands with security and error handling.

**Key Components:**
- `CommandExecutor` - Main execution class
  - `validate_path()` - Path security validation
  - `execute()` - Command execution with timeouts

**Security Features:**
- Path resolution to absolute paths
- Directory traversal prevention
- Existence verification
- Type checking (must be directory)

**Error Handling:**
- Timeout protection (default 30s)
- Command not found
- Invalid paths
- Generic exceptions

**Example:**
```python
executor = CommandExecutor(timeout=60)
result = executor.execute(["h", "files", "3"], cwd="/path/to/repo")
# result = {"success": bool, "output": str, "error": str?, "exit_code": int}
```

### tool_handlers.py

**Purpose:** Business logic for each MCP tool, organized by responsibility.

**Key Components:**
- `ToolHandler` - Abstract base class
- Individual handlers (e.g., `HugHFilesHandler`, `HugStatusHandler`)
- `ToolRegistry` - Handler registration and discovery

**Handler Pattern:**
```python
class CustomToolHandler(ToolHandler):
    def handle(self, arguments: dict) -> dict:
        # Extract arguments
        # Build command
        # Execute via executor
        # Return result
```

**Registry Usage:**
```python
registry = ToolRegistry(executor)
handler = registry.get_handler("hug_status")
result = handler.handle({"format": "short"})
```

### tool_definitions.py

**Purpose:** MCP protocol schemas for all tools.

**Structure:**
- Pure data - no business logic
- JSON Schema compliant
- Complete parameter documentation
- Validation rules

**Benefits:**
- Separates API contract from implementation
- Easy to review and update
- Can be generated automatically
- Supports tool discovery

### server.py

**Purpose:** MCP protocol implementation and server orchestration.

**Responsibilities:**
- MCP protocol compliance
- Tool registration
- Request routing
- Response formatting

**Kept Minimal:**
- Only 86 lines (was 397)
- No business logic
- Pure orchestration
- Clean async/await

## Data Flow

### Tool Execution Flow

```
1. MCP Client Request
   ↓
2. server.call_tool(name, arguments)
   ↓
3. registry.get_handler(name)
   ↓
4. handler.handle(arguments)
   ↓
5. executor.validate_path(cwd)
   ↓
6. executor.execute(args, cwd)
   ↓
7. subprocess.run(["hug", ...])
   ↓
8. Return result dict
   ↓
9. Format as TextContent
   ↓
10. MCP Client Response
```

### Error Flow

```
Error occurs anywhere in chain
   ↓
Catch at appropriate level
   ↓
Return error dict/TextContent
   ↓
MCP client receives readable error
```

## Extensibility

### Adding a New Tool

**Step 1:** Create handler in `tool_handlers.py`
```python
class HugNewToolHandler(ToolHandler):
    """Handler for new_tool."""
    
    def handle(self, arguments: dict[str, Any]) -> dict[str, Any]:
        # Your logic here
        args = ["command", "args"]
        cwd = arguments.get("cwd")
        return self.executor.execute(args, cwd)
```

**Step 2:** Register in `ToolRegistry._register_default_handlers()`
```python
self.register("hug_new_tool", HugNewToolHandler(self.executor))
```

**Step 3:** Add schema to `tool_definitions.py`
```python
Tool(
    name="hug_new_tool",
    description="What this tool does",
    inputSchema={
        "type": "object",
        "properties": {
            "param": {"type": "string", "description": "Parameter"},
            "cwd": {"type": "string", "description": "Working directory"},
        },
    },
)
```

**Step 4:** Add tests in `tests/test_tool_handlers.py`
```python
def test_new_tool_handler(self, temp_git_repo):
    executor = CommandExecutor()
    handler = HugNewToolHandler(executor)
    result = handler.handle({"cwd": str(temp_git_repo)})
    assert result["success"] is True
```

### Customizing Command Execution

Extend `CommandExecutor` for custom behavior:
```python
class CustomExecutor(CommandExecutor):
    def execute(self, args, cwd):
        # Add logging
        logger.info(f"Executing: {args}")
        result = super().execute(args, cwd)
        # Add metrics
        metrics.record(result)
        return result

# Use custom executor
executor = CustomExecutor(timeout=60)
registry = ToolRegistry(executor)
```

### External Tool Registration

Users can register their own tools:
```python
from hug_scm_mcp_server.tool_handlers import ToolHandler, ToolRegistry
from hug_scm_mcp_server.command_executor import CommandExecutor

class MyCustomHandler(ToolHandler):
    def handle(self, arguments):
        # Custom logic
        pass

executor = CommandExecutor()
registry = ToolRegistry(executor)
registry.register("my_custom_tool", MyCustomHandler(executor))
```

## Testing Strategy

### Unit Tests
- **test_command_executor.py** - Executor logic, path validation
- **test_tool_handlers.py** - Handler logic, registry
- **test_server.py** - Server integration

### Test Organization
```
tests/
├── conftest.py           # Shared fixtures
├── test_command_executor.py    # 14 tests
├── test_tool_handlers.py       # 13 tests
└── test_server.py              # 12 tests
```

### Coverage Targets
- command_executor: 87% (critical path)
- tool_handlers: 77% (business logic)
- server: 85% (integration)
- Overall: 81%

## Performance Considerations

### Command Timeout
- Default: 30 seconds
- Configurable per executor
- Prevents hung processes

### Path Validation
- Minimal overhead (~1ms)
- Critical security check
- Cached by OS

### Test Execution
- Isolated temp directories
- Parallel-safe
- Fast cleanup (3.7s total)

## Security Architecture

### Defense in Depth

**Layer 1: Input Validation**
- Parameter type checking via JSON Schema
- Required field enforcement

**Layer 2: Path Validation**
- Absolute path resolution
- Symlink resolution
- Existence verification
- Type checking

**Layer 3: Command Execution**
- Subprocess with timeout
- No shell injection (list args)
- Captured output only
- Error containment

**Layer 4: Error Handling**
- Graceful degradation
- No sensitive data in errors
- User-friendly messages

### Threat Model

**Mitigated:**
- Directory traversal ✅
- Command injection ✅
- Denial of service (timeout) ✅
- Information disclosure ✅

**Not Mitigated:**
- User permission escalation (by design - runs as user)
- Repository-level attacks (Hug/Git responsibility)

## Future Enhancements

### Planned Improvements

1. **Caching Layer**
   - Cache command results
   - Invalidate on repository changes
   - Configurable TTL

2. **Metrics & Observability**
   - Command execution times
   - Error rates
   - Tool usage statistics

3. **Async Optimization**
   - Parallel command execution
   - Streaming results
   - Progressive updates

4. **Plugin System**
   - Dynamic tool loading
   - Third-party tools
   - Tool marketplace

## Comparison: Before vs After

### Before Refactoring
```
server.py (397 lines)
├── Everything mixed together
├── Hard to test
├── No path validation
└── Difficult to extend
```

### After Refactoring
```
src/hug_scm_mcp_server/
├── command_executor.py (113 lines) - Execution + Security
├── tool_handlers.py (230 lines)    - Business Logic
├── tool_definitions.py (205 lines) - API Schemas
├── server.py (86 lines)            - Orchestration
└── __init__.py (2 lines)           - Package

Benefits:
✅ 81% test coverage (+12%)
✅ 5 focused modules (was 1)
✅ Path validation implemented
✅ 22 new tests
✅ Easy to extend
✅ Clear separation of concerns
```

## Contributing Guidelines

When contributing to this architecture:

1. **Maintain Separation** - Don't mix concerns
2. **Add Tests** - 80%+ coverage required
3. **Document Changes** - Update this file
4. **Follow Patterns** - Use existing handlers as templates
5. **Security First** - Validate inputs, handle errors

## References

- [MCP Protocol Specification](https://modelcontextprotocol.io/)
- [Python asyncio](https://docs.python.org/3/library/asyncio.html)
- [Subprocess Security](https://docs.python.org/3/library/subprocess.html#security-considerations)
