#!/usr/bin/env python3
"""
CommandMockPlayer: Replays command mocks from TOML files for testing.

This module provides functionality to:
1. Load mock data from TOML files
2. Match commands to appropriate mocks
3. Provide mock subprocess.run functions for tests
4. Auto-generate missing mocks (if configured)

Usage:
    # For Git commands
    player = CommandMockPlayer("git")
    mock_fn = player.get_subprocess_mock("log/follow.toml", "basic")

    with patch('subprocess.run', side_effect=mock_fn):
        result = get_file_churn("file.txt")

    # For Docker commands
    player = CommandMockPlayer("docker")
    mock_fn = player.get_subprocess_mock("ps/all.toml", "basic")

    with patch('subprocess.run', side_effect=mock_fn):
        result = get_containers()
"""

import sys
from pathlib import Path
from typing import List, Dict, Any, Optional, Callable
from unittest.mock import MagicMock

# Handle TOML library import (tomli for Python < 3.11, tomllib for >= 3.11)
if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib


class CommandMockPlayer:
    """Replays command mocks from TOML files for testing."""

    def __init__(self, command_type: str, fixtures_root: Optional[Path] = None):
        """
        Initialize player.

        Args:
            command_type: Command category (e.g., 'git', 'docker', 'npm')
            fixtures_root: Root directory for fixtures (defaults to fixtures/ in same dir)
        """
        if fixtures_root is None:
            fixtures_root = Path(__file__).parent
        self.fixtures_root = Path(fixtures_root)
        self.command_type = command_type
        self.mocks_dir = self.fixtures_root / "mocks" / command_type

        # Cache loaded scenarios
        self._scenario_cache: Dict[str, Dict[str, Any]] = {}

    def load_scenarios(self, mock_file: str) -> Dict[str, Any]:
        """
        Load all scenarios from a TOML file.

        Args:
            mock_file: Relative path to TOML file (e.g., "log/follow.toml")

        Returns:
            Dictionary mapping scenario names to scenario data

        Raises:
            FileNotFoundError: If mock file doesn't exist
            ValueError: If TOML file is malformed
        """
        # Check cache first
        if mock_file in self._scenario_cache:
            return self._scenario_cache[mock_file]

        # Load TOML file
        toml_path = self.mocks_dir / mock_file
        if not toml_path.exists():
            raise FileNotFoundError(
                f"Mock file not found: {toml_path}\n"
                f"Run 'pytest --regenerate-mocks' to generate mock data."
            )

        try:
            with open(toml_path, "rb") as f:
                data = tomllib.load(f)
        except Exception as e:
            raise ValueError(f"Failed to parse TOML file {toml_path}: {e}") from e

        # Build scenario map
        scenarios = {}
        for scenario in data.get("scenario", []):
            scenario_name = scenario.get("name")
            if not scenario_name:
                raise ValueError(f"Scenario missing 'name' field in {toml_path}")

            # Load output from separate file if referenced
            if "output_file" in scenario:
                # output_file is relative to TOML file location (e.g., "outputs/basic.txt")
                output_file = scenario["output_file"]
                if output_file:  # Only try to read if output_file is not empty
                    output_path = toml_path.parent / output_file
                    if output_path.exists():
                        scenario["stdout"] = output_path.read_text()
                    else:
                        raise FileNotFoundError(
                            f"Output file not found: {output_path}\n"
                            f"Referenced in scenario '{scenario_name}' in {toml_path}"
                        )
                else:
                    # Empty output_file means no stdout content (e.g., for error scenarios)
                    scenario["stdout"] = ""
            else:
                # Inline output in TOML (fallback)
                scenario["stdout"] = scenario.get("stdout", "")

            scenarios[scenario_name] = scenario

        # Cache and return
        self._scenario_cache[mock_file] = scenarios
        return scenarios

    def get_scenario(self, mock_file: str, scenario_name: str = "basic") -> Dict[str, Any]:
        """
        Get a specific scenario from a mock file.

        Args:
            mock_file: Relative path to TOML file (e.g., "git-log/follow.toml")
            scenario_name: Name of scenario to retrieve (default: "basic")

        Returns:
            Scenario data dictionary

        Raises:
            KeyError: If scenario not found
            FileNotFoundError: If mock file doesn't exist
        """
        scenarios = self.load_scenarios(mock_file)
        if scenario_name not in scenarios:
            available = ", ".join(scenarios.keys())
            raise KeyError(
                f"Scenario '{scenario_name}' not found in {mock_file}. "
                f"Available scenarios: {available}"
            )
        return scenarios[scenario_name]

    def command_matches(
        self,
        actual_cmd: List[str],
        template_cmd: str,
        strict: bool = False
    ) -> bool:
        """
        Check if actual command matches template command.

        Args:
            actual_cmd: Command that was actually called (list of strings)
            template_cmd: Template command from mock (string, may have {placeholders})
            strict: If True, commands must match exactly (ignoring placeholders)

        Returns:
            True if commands match

        Examples:
            >>> self.command_matches(
            ...     ["git", "log", "--follow", "--", "file.txt"],
            ...     "git log --follow -- --{filepath} --"
            ... )
            True
        """
        # Handle both string and list templates
        if isinstance(template_cmd, list):
            template_parts = template_cmd
        else:
            template_parts = template_cmd.split()

        # Check if pattern contains placeholders
        has_placeholders = any(p.startswith("{") and p.endswith("}") for p in template_parts)

        # Enhanced matching: handle different orders and arguments
        if has_placeholders and not strict:
            # For templates with placeholders, check if all non-placeholder parts exist
            # and the command structure is valid (git log with required options)
            non_placeholder_parts = [p for p in template_parts if not (p.startswith("{") and p.endswith("}"))]

            # Check required parts exist
            for required_part in non_placeholder_parts:
                if required_part not in actual_cmd:
                    return False

            # Validate command structure: should be git log with follow and proper format
            required_options = ["--follow", "--pretty=format:%ad|%an"]
            for option in required_options:
                if option not in actual_cmd:
                    return False

            # Check for file path after --
            if "--" in actual_cmd and actual_cmd.index("--") < len(actual_cmd) - 1:
                # There should be a file path after --
                return True

            return False

        # Enhanced matching for activity commands with since flag
        if "--since" in actual_cmd:
            # activity.py adds --since at the end: [..., "--", "file.py", "--since", "1 day ago"]
            # Template doesn't have --since, so we need to remove it from actual_cmd for comparison
            since_index = actual_cmd.index('--since')
            # Remove --since and its value from actual command
            actual_core = actual_cmd[:since_index] + actual_cmd[since_index+2:]

            # Now compare
            if len(actual_core) != len(template_parts):
                return False
            return all(a == t for a, t in zip(actual_core, template_parts))

        # Strict matching for templates without placeholders
        if len(actual_cmd) != len(template_parts):
            return False

        for actual, template in zip(actual_cmd, template_parts):
            # Exact match
            if actual == template:
                continue

            # Template placeholder (anything in {})
            if template.startswith("{") and template.endswith("}"):
                if not strict:
                    continue  # Placeholder matches anything
                else:
                    return False  # Strict mode: no placeholders allowed

            # No match
            return False

        return True

    def get_subprocess_mock(
        self,
        mock_file: str,
        scenario_name: str = "basic",
        fallback_scenarios: Optional[List[str]] = None
    ) -> Callable:
        """
        Get a mock function for subprocess.run based on scenario.

        Args:
            mock_file: Relative path to TOML file
            scenario_name: Primary scenario to use
            fallback_scenarios: List of fallback scenario names to try

        Returns:
            Mock function compatible with patch('subprocess.run')

        Example:
            >>> player = GitMockPlayer()
            >>> mock_fn = player.get_subprocess_mock("git-log/follow.toml", "basic")
            >>> with patch('subprocess.run', side_effect=mock_fn):
            ...     result = subprocess.run(["git", "log", ...])
        """
        # Load primary scenario
        scenarios = self.load_scenarios(mock_file)
        scenario = scenarios[scenario_name]

        # Build fallback list
        all_scenarios = [scenario]
        if fallback_scenarios:
            for fallback_name in fallback_scenarios:
                if fallback_name in scenarios:
                    all_scenarios.append(scenarios[fallback_name])

        def mock_subprocess_run(*args, **kwargs):
            """Mock implementation of subprocess.run."""
            # Extract command from args
            if args and isinstance(args[0], list):
                cmd = args[0]
            else:
                cmd = kwargs.get("args", [])

            # Try to match command to one of the scenarios
            for scen in all_scenarios:
                if self.command_matches(cmd, scen["command"]):
                    result = MagicMock(
                        stdout=scen.get("stdout", ""),
                        stderr=scen.get("stderr", ""),
                        returncode=scen.get("returncode", 0)
                    )
                    # If returncode is non-zero and check=True, raise CalledProcessError
                    if scen.get("returncode", 0) != 0 and kwargs.get("check", False):
                        import subprocess
                        raise subprocess.CalledProcessError(
                            returncode=scen.get("returncode", 0),
                            cmd=cmd,
                            output=scen.get("stdout", ""),
                            stderr=scen.get("stderr", "")
                        )
                    return result

            # No match found - return default error
            return MagicMock(
                stdout="",
                stderr=f"Mock not found for command: {' '.join(cmd)}",
                returncode=1
            )

        return mock_subprocess_run

    def get_multi_scenario_mock(
        self,
        scenario_map: Dict[str, tuple]
    ) -> Callable:
        """
        Create a mock that handles multiple different commands.

        Args:
            scenario_map: Dictionary mapping command patterns to (mock_file, scenario_name) tuples

        Returns:
            Mock function that dispatches to appropriate scenario based on command

        Example:
            >>> player = GitMockPlayer()
            >>> mock_fn = player.get_multi_scenario_mock({
            ...     "git log -L": ("git-log/L-line.toml", "basic"),
            ...     "git log --follow": ("git-log/follow.toml", "basic")
            ... })
            >>> with patch('subprocess.run', side_effect=mock_fn):
            ...     result1 = subprocess.run(["git", "log", "-L", ...])
            ...     result2 = subprocess.run(["git", "log", "--follow", ...])
        """
        # Pre-load all scenarios
        loaded_scenarios = {}
        for pattern, (mock_file, scenario_name) in scenario_map.items():
            scenario = self.get_scenario(mock_file, scenario_name)
            loaded_scenarios[pattern] = scenario

        def mock_subprocess_run(*args, **kwargs):
            """Mock implementation that dispatches based on command."""
            # Extract command from args
            if args and isinstance(args[0], list):
                cmd = args[0]
            else:
                cmd = kwargs.get("args", [])

            cmd_str = " ".join(cmd)

            # Try to match against patterns
            for pattern, scenario in loaded_scenarios.items():
                if pattern in cmd_str:
                    if self.command_matches(cmd, scenario["command"]):
                        return MagicMock(
                            stdout=scenario.get("stdout", ""),
                            stderr=scenario.get("stderr", ""),
                            returncode=scenario.get("returncode", 0)
                        )

            # No match found
            return MagicMock(
                stdout="",
                stderr=f"Mock not found for command: {cmd_str}",
                returncode=1
            )

        return mock_subprocess_run

    def get_dynamic_mock(
        self,
        mock_file: str,
        command_to_scenario: Optional[Callable[[List[str]], str]] = None
    ) -> Callable:
        """
        Create a dynamic mock that determines scenario based on command analysis.

        Args:
            mock_file: TOML file containing scenarios
            command_to_scenario: Optional function that analyzes command and returns scenario name.
                                If None, uses simple pattern matching.

        Returns:
            Mock function for subprocess.run

        Example:
            >>> def choose_scenario(cmd):
            ...     if "--since" in cmd:
            ...         return "with_since_filter"
            ...     return "basic"
            >>>
            >>> mock_fn = player.get_dynamic_mock("git-log/follow.toml", choose_scenario)
        """
        scenarios = self.load_scenarios(mock_file)

        def mock_subprocess_run(*args, **kwargs):
            """Dynamic mock that chooses scenario based on command."""
            # Extract command
            if args and isinstance(args[0], list):
                cmd = args[0]
            else:
                cmd = kwargs.get("args", [])

            # Determine scenario
            if command_to_scenario:
                scenario_name = command_to_scenario(cmd)
            else:
                # Default: try to match against all scenarios
                for name, scenario in scenarios.items():
                    if self.command_matches(cmd, scenario["command"]):
                        scenario_name = name
                        break
                else:
                    scenario_name = "basic"  # fallback

            # Get scenario
            if scenario_name not in scenarios:
                return MagicMock(
                    stdout="",
                    stderr=f"Scenario '{scenario_name}' not found",
                    returncode=1
                )

            scenario = scenarios[scenario_name]
            return MagicMock(
                stdout=scenario.get("stdout", ""),
                stderr=scenario.get("stderr", ""),
                returncode=scenario.get("returncode", 0)
            )

        return mock_subprocess_run
