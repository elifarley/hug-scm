#!/usr/bin/env python3
"""
Example test showing how to use the Command Mock Framework.

This demonstrates:
1. Using command_mock fixture
2. Loading scenarios from TOML files
3. Creating subprocess mocks for tests
4. Testing both success and error cases
"""

import pytest
from unittest.mock import patch, mock_open


def dummy_git_function():
    """Dummy function that calls git log --follow."""
    import subprocess

    result = subprocess.run(
        ["git", "log", "--follow", "--format=%H|%an|%ai", "--", "project.py"],
        capture_output=True,
        text=True,
        check=True,
    )

    # Parse output
    commits = []
    for line in result.stdout.strip().split("\n"):
        if line:
            hash_val, author, date = line.split("|", 2)
            commits.append({"hash": hash_val, "author": author, "date": date})

    return commits


class TestCommandMockFrameworkExample:
    """Example tests using the command_mock fixture."""

    def test_basic_scenario(self, command_mock):
        """Test using basic scenario from TOML file."""
        # Arrange
        mock_fn = command_mock.get_subprocess_mock("log/follow.toml", "basic")

        # Act
        with patch("subprocess.run", side_effect=mock_fn):
            result = dummy_git_function()

        # Assert
        assert len(result) == 5  # 5 commits in basic scenario (from churn-with-since.sh)
        assert result[0]["author"] in ["Alice Smith", "Bob Johnson"]

    def test_with_since_filter_scenario(self, command_mock):
        """Test using scenario with --since filter."""
        # Arrange - load scenario with date filter
        mock_fn = command_mock.get_subprocess_mock("log/follow.toml", "with_since_filter")

        def dummy_with_since():
            import subprocess

            result = subprocess.run(
                [
                    "git",
                    "log",
                    "--follow",
                    "--format=%H|%an|%ai",
                    "--since=2 months ago",
                    "--",
                    "project.py",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            return len(result.stdout.strip().split("\n"))

        # Act
        with patch("subprocess.run", side_effect=mock_fn):
            commit_count = dummy_with_since()

        # Assert
        assert commit_count >= 1  # At least one commit in filtered results

    def test_binary_file_error(self, command_mock):
        """Test error handling for binary files."""
        # Arrange
        mock_fn = command_mock.get_subprocess_mock("log/binary-errors.toml", "binary_file")

        def dummy_binary_check():
            import subprocess

            result = subprocess.run(
                ["git", "log", "-L", "1,1:image.png", "--oneline"],
                capture_output=True,
                text=True,
                check=False,
            )
            return result.returncode

        # Act
        with patch("subprocess.run", side_effect=mock_fn):
            returncode = dummy_binary_check()

        # Assert
        assert returncode == 128  # Git error code for binary file


class TestMultiScenarioMocking:
    """Example of handling multiple different commands in one test."""

    def test_multiple_commands(self, command_mock):
        """Test function that calls multiple Git commands."""
        # Arrange - create mock that handles both commands
        mock_fn = command_mock.get_multi_scenario_mock(
            {
                "git log --follow": ("log/follow.toml", "basic"),
                "git log -L": ("log/L-line.toml", "basic"),
            }
        )

        def dummy_multi_git():
            import subprocess

            # First command: git log --follow
            r1 = subprocess.run(
                ["git", "log", "--follow", "--format=%H|%an|%ai", "--", "project.py"],
                capture_output=True,
                text=True,
                check=True,
            )

            # Second command: git log -L
            r2 = subprocess.run(
                ["git", "log", "-L", "2,2:file.txt", "--oneline"],
                capture_output=True,
                text=True,
                check=False,
            )

            return len(r1.stdout.split("\n")), len(r2.stdout.split("\n"))

        # Act
        with patch("subprocess.run", side_effect=mock_fn):
            follow_lines, L_lines = dummy_multi_git()

        # Assert
        assert follow_lines > 0
        assert L_lines > 0


class TestDynamicScenarioSelection:
    """Example of dynamic scenario selection based on command."""

    def test_dynamic_scenario(self, command_mock):
        """Test with dynamic scenario selection."""

        # Arrange - scenario chosen based on command inspection
        def choose_scenario(cmd):
            if "--since" in cmd:
                return "with_since_filter"
            return "basic"

        mock_fn = command_mock.get_dynamic_mock("log/follow.toml", choose_scenario)

        def dummy_conditional(use_since: bool):
            import subprocess

            cmd = ["git", "log", "--follow", "--format=%H|%an|%ai", "--", "project.py"]
            if use_since:
                cmd.insert(2, "--since=2 months ago")

            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return result.stdout

        # Act & Assert - different scenarios based on parameter
        with patch("subprocess.run", side_effect=mock_fn):
            # Without --since: uses "basic" scenario
            output1 = dummy_conditional(use_since=False)
            assert len(output1) > 0

            # With --since: uses "with_since_filter" scenario
            output2 = dummy_conditional(use_since=True)
            assert len(output2) > 0
