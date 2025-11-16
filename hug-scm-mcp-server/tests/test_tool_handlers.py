"""Tests for tool handlers module."""

from pathlib import Path

import pytest

from hug_scm_mcp_server.command_executor import CommandExecutor
from hug_scm_mcp_server.tool_handlers import (
    HugBranchListHandler,
    HugHFilesHandler,
    HugHStepsHandler,
    HugLogHandler,
    HugShowDiffHandler,
    HugStatusHandler,
    ToolRegistry,
)


class TestToolHandlers:
    """Tests for individual tool handlers."""

    def test_hug_status_handler(self, temp_git_repo: Path, hug_available: bool) -> None:
        """Test HugStatusHandler."""
        if not hug_available:
            pytest.skip("Hug command not available")

        executor = CommandExecutor()
        handler = HugStatusHandler(executor)

        result = handler.handle({"format": "short", "cwd": str(temp_git_repo)})
        assert "success" in result
        assert "output" in result

    def test_hug_h_files_handler(self, temp_git_repo: Path, hug_available: bool) -> None:
        """Test HugHFilesHandler."""
        if not hug_available:
            pytest.skip("Hug command not available")

        executor = CommandExecutor()
        handler = HugHFilesHandler(executor)

        result = handler.handle({"count": 2, "cwd": str(temp_git_repo)})
        assert "success" in result
        assert "output" in result

    def test_hug_log_handler(self, temp_git_repo: Path, hug_available: bool) -> None:
        """Test HugLogHandler."""
        if not hug_available:
            pytest.skip("Hug command not available")

        executor = CommandExecutor()
        handler = HugLogHandler(executor)

        result = handler.handle({"count": 3, "cwd": str(temp_git_repo)})
        assert "success" in result
        assert "output" in result

    def test_hug_branch_list_handler(self, temp_git_repo: Path, hug_available: bool) -> None:
        """Test HugBranchListHandler."""
        if not hug_available:
            pytest.skip("Hug command not available")

        executor = CommandExecutor()
        handler = HugBranchListHandler(executor)

        result = handler.handle({"cwd": str(temp_git_repo)})
        assert "success" in result
        assert "output" in result

    def test_hug_h_steps_handler_missing_file(
        self, temp_git_repo: Path, hug_available: bool
    ) -> None:
        """Test HugHStepsHandler with missing file parameter."""
        executor = CommandExecutor()
        handler = HugHStepsHandler(executor)

        result = handler.handle({"cwd": str(temp_git_repo)})
        assert result["success"] is False
        assert "required" in result["error"]

    def test_hug_h_steps_handler_with_file(self, temp_git_repo: Path, hug_available: bool) -> None:
        """Test HugHStepsHandler with file parameter."""
        if not hug_available:
            pytest.skip("Hug command not available")

        executor = CommandExecutor()
        handler = HugHStepsHandler(executor)

        result = handler.handle({"file": "file1.txt", "cwd": str(temp_git_repo)})
        assert "success" in result

    def test_hug_show_diff_handler(self, temp_git_repo: Path, hug_available: bool) -> None:
        """Test HugShowDiffHandler."""
        if not hug_available:
            pytest.skip("Hug command not available")

        executor = CommandExecutor()
        handler = HugShowDiffHandler(executor)

        result = handler.handle({"cwd": str(temp_git_repo)})
        assert "success" in result
        assert "output" in result


class TestToolRegistry:
    """Tests for ToolRegistry class."""

    def test_registry_initialization(self) -> None:
        """Test registry initialization."""
        executor = CommandExecutor()
        registry = ToolRegistry(executor)

        # Check that default handlers are registered
        tools = registry.list_tools()
        assert "hug_h_files" in tools
        assert "hug_status" in tools
        assert "hug_log" in tools
        assert "hug_branch_list" in tools
        assert "hug_h_steps" in tools
        assert "hug_show_diff" in tools

    def test_get_handler(self) -> None:
        """Test getting a handler by name."""
        executor = CommandExecutor()
        registry = ToolRegistry(executor)

        handler = registry.get_handler("hug_status")
        assert handler is not None
        assert isinstance(handler, HugStatusHandler)

    def test_get_nonexistent_handler(self) -> None:
        """Test getting a nonexistent handler."""
        executor = CommandExecutor()
        registry = ToolRegistry(executor)

        handler = registry.get_handler("nonexistent")
        assert handler is None

    def test_register_custom_handler(self) -> None:
        """Test registering a custom handler."""
        executor = CommandExecutor()
        registry = ToolRegistry(executor)

        # Create a custom handler
        custom_handler = HugStatusHandler(executor)
        registry.register("custom_tool", custom_handler)

        # Verify it was registered
        handler = registry.get_handler("custom_tool")
        assert handler is not None
        assert "custom_tool" in registry.list_tools()
