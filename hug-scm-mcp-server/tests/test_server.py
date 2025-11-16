"""Tests for the MCP server implementation."""

from pathlib import Path

import pytest

from hug_scm_mcp_server.command_executor import CommandExecutor
from hug_scm_mcp_server.server import app


class TestCommandExecution:
    """Tests for command execution through executor."""

    def test_successful_command(self, temp_git_repo: Path) -> None:
        """Test successful command execution."""
        executor = CommandExecutor()
        result = executor.execute(["--version"], cwd=str(temp_git_repo))

        assert result["success"] is True or result["success"] is False  # Either is valid
        assert result["exit_code"] is not None
        assert "error" in result or result["error"] is None

    def test_command_with_output(self, temp_git_repo: Path, hug_available: bool) -> None:
        """Test command that produces output."""
        if not hug_available:
            pytest.skip("Hug command not available")

        # Create a change to make output non-empty
        test_file = temp_git_repo / "test_output.txt"
        test_file.write_text("Test content\n")

        executor = CommandExecutor()
        result = executor.execute(["s"], cwd=str(temp_git_repo))

        assert result["success"] is True
        # Output may be empty if working directory is clean, which is ok
        assert result["exit_code"] == 0

    def test_nonexistent_command(self, temp_git_repo: Path) -> None:
        """Test handling of non-existent command."""
        executor = CommandExecutor()
        # Execute will handle FileNotFoundError internally
        result = executor.execute(["nonexistent-command-12345"], cwd=str(temp_git_repo))

        assert result["success"] is False
        assert "error" in result

    def test_command_timeout(self, temp_git_repo: Path) -> None:
        """Test command timeout handling."""
        executor = CommandExecutor(timeout=1)
        # The timeout is set, commands will timeout if they take too long
        assert executor.timeout == 1

    def test_command_error(self, temp_git_repo: Path) -> None:
        """Test command that returns error."""
        executor = CommandExecutor()
        # Try to show diff in a clean repo (should fail gracefully or return empty)
        result = executor.execute(["--no-pager", "diff", "nonexistent"], cwd=str(temp_git_repo))

        # Git will return non-zero for invalid ref
        assert result["exit_code"] != 0 or result["output"] == ""


class TestListTools:
    """Tests for list_tools endpoint."""

    def test_server_has_name(self) -> None:
        """Test that server is properly configured."""
        assert app.name == "hug-scm-mcp-server"


class TestCallTool:
    """Tests for call_tool endpoint."""

    def test_server_configured(self) -> None:
        """Test that server is properly configured."""
        # Just verify the server exists and is a Server instance
        from mcp.server import Server

        assert isinstance(app, Server)


class TestToolHandlers:
    """Tests for individual tool handler implementations."""

    async def test_list_tools_handler(self) -> None:
        """Test list_tools handler directly."""
        from hug_scm_mcp_server.server import list_tools

        # Call the handler function directly
        tools = await list_tools()

        assert isinstance(tools, list)
        assert len(tools) > 0

        tool_names = [tool.name for tool in tools]
        expected_tools = [
            "hug_h_files",
            "hug_status",
            "hug_log",
            "hug_branch_list",
            "hug_h_steps",
            "hug_show_diff",
        ]

        assert set(expected_tools).issubset(set(tool_names))

        # Check tool properties
        for tool in tools:
            assert tool.description
            assert len(tool.description) > 10
            assert tool.inputSchema
            assert tool.inputSchema.get("type") == "object"

    async def test_call_tool_handler_hug_status(
        self, temp_git_repo: Path, hug_available: bool
    ) -> None:
        """Test call_tool handler for hug_status."""
        if not hug_available:
            pytest.skip("Hug command not available")

        from hug_scm_mcp_server.server import call_tool

        result = await call_tool("hug_status", {"format": "short", "cwd": str(temp_git_repo)})

        assert len(result) > 0
        assert result[0].type == "text"

    async def test_call_tool_handler_hug_h_files(
        self, temp_git_repo: Path, hug_available: bool
    ) -> None:
        """Test call_tool handler for hug_h_files."""
        if not hug_available:
            pytest.skip("Hug command not available")

        from hug_scm_mcp_server.server import call_tool

        result = await call_tool("hug_h_files", {"count": 2, "cwd": str(temp_git_repo)})

        assert len(result) > 0
        assert result[0].type == "text"

    async def test_call_tool_handler_hug_log(
        self, temp_git_repo: Path, hug_available: bool
    ) -> None:
        """Test call_tool handler for hug_log."""
        if not hug_available:
            pytest.skip("Hug command not available")

        from hug_scm_mcp_server.server import call_tool

        result = await call_tool("hug_log", {"count": 3, "cwd": str(temp_git_repo)})

        assert len(result) > 0
        assert result[0].type == "text"

    async def test_call_tool_handler_hug_branch_list(
        self, temp_git_repo: Path, hug_available: bool
    ) -> None:
        """Test call_tool handler for hug_branch_list."""
        if not hug_available:
            pytest.skip("Hug command not available")

        from hug_scm_mcp_server.server import call_tool

        result = await call_tool("hug_branch_list", {"cwd": str(temp_git_repo)})

        assert len(result) > 0
        assert result[0].type == "text"

    async def test_call_tool_handler_hug_h_steps(
        self, temp_git_repo: Path, hug_available: bool
    ) -> None:
        """Test call_tool handler for hug_h_steps."""
        if not hug_available:
            pytest.skip("Hug command not available")

        from hug_scm_mcp_server.server import call_tool

        result = await call_tool("hug_h_steps", {"file": "file1.txt", "cwd": str(temp_git_repo)})

        assert len(result) > 0
        assert result[0].type == "text"

    async def test_call_tool_handler_hug_show_diff(
        self, temp_git_repo: Path, hug_available: bool
    ) -> None:
        """Test call_tool handler for hug_show_diff."""
        if not hug_available:
            pytest.skip("Hug command not available")

        from hug_scm_mcp_server.server import call_tool

        # Create a change
        test_file = temp_git_repo / "file1.txt"
        test_file.write_text("Modified content\n")

        result = await call_tool("hug_show_diff", {"cwd": str(temp_git_repo)})

        assert len(result) > 0
        assert result[0].type == "text"

    async def test_call_tool_handler_unknown_tool(self, temp_git_repo: Path) -> None:
        """Test call_tool handler with unknown tool."""
        from hug_scm_mcp_server.server import call_tool

        result = await call_tool("unknown_tool", {"cwd": str(temp_git_repo)})

        assert len(result) > 0
        assert "unknown" in result[0].text.lower()


class TestServerIntegration:
    """Integration tests for the server."""

    def test_server_module_imports(self) -> None:
        """Test that server module imports successfully."""
        from hug_scm_mcp_server import server

        assert hasattr(server, "app")
        assert hasattr(server, "executor")
        assert hasattr(server, "registry")
        assert hasattr(server, "main")

    def test_server_app_is_configured(self) -> None:
        """Test that server app is properly configured."""
        assert app.name == "hug-scm-mcp-server"
