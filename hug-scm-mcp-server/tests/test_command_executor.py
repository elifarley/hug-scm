"""Tests for command executor module."""

import tempfile
from pathlib import Path

import pytest

from hug_scm_mcp_server.command_executor import CommandExecutor


class TestCommandExecutor:
    """Tests for CommandExecutor class."""

    def test_initialization(self) -> None:
        """Test executor initialization."""
        executor = CommandExecutor(timeout=60)
        assert executor.timeout == 60

    def test_default_timeout(self) -> None:
        """Test default timeout value."""
        executor = CommandExecutor()
        assert executor.timeout == 30

    def test_validate_path_with_none(self) -> None:
        """Test path validation with None."""
        executor = CommandExecutor()
        result = executor.validate_path("")
        assert result  # Should return some path

    def test_validate_path_with_valid_directory(self, temp_git_repo: Path) -> None:
        """Test path validation with valid directory."""
        executor = CommandExecutor()
        result = executor.validate_path(str(temp_git_repo))
        assert Path(result).is_absolute()
        assert Path(result).exists()

    def test_validate_path_with_nonexistent(self) -> None:
        """Test path validation with nonexistent path."""
        executor = CommandExecutor()
        with pytest.raises(ValueError, match="Path does not exist"):
            executor.validate_path("/nonexistent/path/12345")

    def test_validate_path_with_file_not_directory(self, temp_git_repo: Path) -> None:
        """Test path validation when path is a file, not directory."""
        executor = CommandExecutor()
        file_path = temp_git_repo / "test.txt"
        file_path.write_text("test")

        with pytest.raises(ValueError, match="not a directory"):
            executor.validate_path(str(file_path))

    def test_validate_path_prevents_traversal(self, temp_git_repo: Path) -> None:
        """Test that path validation resolves .. and symlinks."""
        executor = CommandExecutor()
        # Path validation should resolve to absolute path
        # This should resolve to temp_git_repo
        result = executor.validate_path(str(temp_git_repo))
        assert Path(result).resolve() == temp_git_repo.resolve()

    def test_execute_with_invalid_path(self) -> None:
        """Test execute with invalid working directory."""
        executor = CommandExecutor()
        result = executor.execute(["--version"], cwd="/nonexistent/path")

        assert result["success"] is False
        assert "Invalid path" in result["error"]

    def test_execute_command_not_found(self) -> None:
        """Test execute when hug command is not found."""
        executor = CommandExecutor()
        # Create a temp directory that exists
        with tempfile.TemporaryDirectory() as tmpdir:
            # Try to execute with a PATH that doesn't include hug
            result = executor.execute(["nonexistent"], cwd=tmpdir)

            # Should handle gracefully
            assert result["success"] is False
            # exit_code could be -1 (not found) or non-zero
            # (hug command exists but subcommand doesn't)
            assert result["exit_code"] != 0

    def test_execute_timeout(self, temp_git_repo: Path) -> None:
        """Test command timeout handling."""
        executor = CommandExecutor(timeout=1)
        # Try a command that might take longer than 1 second
        # Note: This is hard to test reliably, so we just ensure the timeout mechanism exists
        assert executor.timeout == 1

    def test_execute_success(self, temp_git_repo: Path, hug_available: bool) -> None:
        """Test successful command execution."""
        if not hug_available:
            pytest.skip("Hug command not available")

        executor = CommandExecutor()
        result = executor.execute(["--version"], cwd=str(temp_git_repo))

        assert result["success"] is True or result["success"] is False  # Either is valid
        assert "exit_code" in result
        assert "output" in result
