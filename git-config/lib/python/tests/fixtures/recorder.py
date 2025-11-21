#!/usr/bin/env python3
"""
CommandMockRecorder: Records real command outputs to TOML files for test mocking.

This module provides functionality to:
1. Execute real commands (git, docker, npm, etc.) in test environments
2. Create test repositories/environments from setup scripts
3. Store command outputs in TOML files with metadata
4. Generate high-fidelity mock data for tests

Usage:
    # For Git commands
    recorder = CommandMockRecorder("git")
    repo_path = recorder.create_test_repo("churn-basic.sh")
    recorder.record_scenario(
        command=["git", "log", "--follow", "--format=%H|%an|%ai", "--", "file.txt"],
        scenario_name="basic",
        output_path=Path("log/follow.toml"),
        repo_path=repo_path
    )

    # For Docker commands
    recorder = CommandMockRecorder("docker")
    recorder.record_scenario(
        command=["docker", "ps", "-a"],
        scenario_name="all_containers",
        output_path=Path("ps/all.toml")
    )
"""

import subprocess
import tomli_w
from pathlib import Path
from typing import List, Dict, Any, Optional
import tempfile
import shutil
import os


class CommandMockRecorder:
    """Records real command outputs to TOML files for test mocking."""

    def __init__(self, command_type: str, fixtures_root: Optional[Path] = None):
        """
        Initialize recorder.

        Args:
            command_type: Command category (e.g., 'git', 'docker', 'npm')
            fixtures_root: Root directory for fixtures (defaults to fixtures/ in same dir)
        """
        if fixtures_root is None:
            fixtures_root = Path(__file__).parent
        self.fixtures_root = Path(fixtures_root)
        self.command_type = command_type
        self.mocks_dir = self.fixtures_root / "mocks" / command_type
        self.test_repos_dir = self.fixtures_root / "test-repos"

        # Ensure directories exist
        self.mocks_dir.mkdir(parents=True, exist_ok=True)
        self.test_repos_dir.mkdir(parents=True, exist_ok=True)

    def create_test_repo(self, setup_script: str) -> Path:
        """
        Create a test repository by running a setup script.

        Args:
            setup_script: Relative path to setup script (e.g., "churn-basic.sh")

        Returns:
            Path to created temporary repository

        Raises:
            FileNotFoundError: If setup script doesn't exist
            subprocess.CalledProcessError: If script execution fails
        """
        script_path = self.test_repos_dir / setup_script
        if not script_path.exists():
            raise FileNotFoundError(f"Setup script not found: {script_path}")

        # Create temporary directory for test repo
        temp_dir = Path(tempfile.mkdtemp(prefix="git_mock_record_"))

        try:
            # Make script executable and run it
            os.chmod(script_path, 0o755)
            subprocess.run(
                ["bash", str(script_path)],
                cwd=temp_dir,
                check=True,
                capture_output=True,
                text=True
            )
            return temp_dir
        except subprocess.CalledProcessError as e:
            # Cleanup on failure
            shutil.rmtree(temp_dir, ignore_errors=True)
            raise RuntimeError(
                f"Failed to run setup script {setup_script}:\n"
                f"stdout: {e.stdout}\nstderr: {e.stderr}"
            ) from e

    def record_scenario(
        self,
        command: List[str],
        scenario_name: str,
        output_path: Path,
        repo_path: Optional[Path] = None,
        description: str = "",
        template_vars: Optional[Dict[str, str]] = None,
        output_prefix: str = ""
    ) -> Dict[str, Any]:
        """
        Execute a Git command and record its output.

        Args:
            command: Git command to execute (with template placeholders)
            scenario_name: Name for this scenario (e.g., "basic", "with_since")
            output_path: Path to TOML file to append scenario to
            repo_path: Path to Git repo (if None, uses current directory)
            description: Human-readable description of scenario
            template_vars: Variables to substitute in command (e.g., {"filepath": "file.txt"})
            output_prefix: Prefix for output filename (e.g., "follow-" or "L-line-")

        Returns:
            Dictionary containing scenario data

        Raises:
            subprocess.CalledProcessError: If Git command fails unexpectedly
        """
        # Substitute template variables in command
        if template_vars:
            command = [
                part.format(**template_vars) if isinstance(part, str) else part
                for part in command
            ]

        # Execute Git command
        try:
            result = subprocess.run(
                command,
                cwd=repo_path,
                capture_output=True,
                text=True,
                check=False  # We want to capture failures too
            )
        except UnicodeDecodeError:
            # Binary output - try again without text mode
            try:
                result = subprocess.run(
                    command,
                    cwd=repo_path,
                    capture_output=True,
                    check=False
                )
                # Store binary output as error message
                result = subprocess.CompletedProcess(
                    args=result.args,
                    returncode=result.returncode if result.returncode != 0 else 128,
                    stdout="",
                    stderr="fatal: binary file cannot be processed"
                )
            except Exception as e:
                raise RuntimeError(f"Failed to execute command {command}: {e}") from e
        except Exception as e:
            raise RuntimeError(f"Failed to execute command {command}: {e}") from e

        # Determine output file path relative to TOML file location
        # output_path is relative to mocks_dir (e.g., "log/follow.toml")
        # We need to place outputs in same directory (e.g., "log/outputs/")
        toml_dir = (self.mocks_dir / output_path).parent
        outputs_dir = toml_dir / "outputs"
        outputs_dir.mkdir(parents=True, exist_ok=True)

        # Determine output file name with optional prefix to avoid collisions
        output_filename = f"{output_prefix}{scenario_name}.txt"
        output_file_path = outputs_dir / output_filename

        # Write output to separate text file
        output_file_path.write_text(result.stdout)

        # Create scenario data with output path relative to TOML file location
        scenario = {
            "name": scenario_name,
            "description": description,
            "command": command,
            "returncode": result.returncode,
            "output_file": f"outputs/{output_filename}",  # Relative to TOML file
            "stderr": result.stderr if result.stderr else "",
        }

        return scenario

    def generate_mock_file(
        self,
        scenarios: List[Dict[str, Any]],
        output_file: Path,
        metadata: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Write TOML file with multiple scenarios.

        Args:
            scenarios: List of scenario dictionaries
            output_file: Path to output TOML file (relative to mocks_dir)
            metadata: Optional metadata to include in file header
        """
        # Resolve path relative to mocks_dir if not absolute
        if not output_file.is_absolute():
            output_file = self.mocks_dir / output_file

        # Ensure parent directory exists
        output_file.parent.mkdir(parents=True, exist_ok=True)

        # Build TOML structure
        toml_data = {}

        # Add metadata if provided
        if metadata:
            toml_data["metadata"] = metadata

        # Add scenarios
        toml_data["scenario"] = scenarios

        # Write TOML file
        with open(output_file, "wb") as f:
            tomli_w.dump(toml_data, f)

    def record_multiple_scenarios(
        self,
        scenario_specs: List[Dict[str, Any]],
        output_file: Path,
        repo_setup_script: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
        output_prefix: str = ""
    ) -> None:
        """
        Record multiple scenarios at once.

        Args:
            scenario_specs: List of scenario specifications, each containing:
                - command: Git command to run
                - scenario_name: Name for scenario
                - description: Description of scenario
                - template_vars: Optional template variables
            output_file: Path to output TOML file
            repo_setup_script: Optional setup script to create test repo
            metadata: Optional metadata for TOML file
            output_prefix: Prefix for all output filenames to avoid collisions
        """
        # Create test repo if setup script provided
        repo_path = None
        if repo_setup_script:
            repo_path = self.create_test_repo(repo_setup_script)

        try:
            # Record all scenarios
            scenarios = []
            for spec in scenario_specs:
                scenario = self.record_scenario(
                    command=spec["command"],
                    scenario_name=spec["scenario_name"],
                    output_path=output_file,
                    repo_path=repo_path,
                    description=spec.get("description", ""),
                    template_vars=spec.get("template_vars"),
                    output_prefix=output_prefix
                )
                scenarios.append(scenario)

            # Add repo setup to metadata if provided
            if repo_setup_script and metadata is None:
                metadata = {}
            if repo_setup_script:
                metadata["repo_setup"] = repo_setup_script

            # Write TOML file
            self.generate_mock_file(scenarios, output_file, metadata)

        finally:
            # Cleanup temp repo
            if repo_path and repo_path.exists():
                shutil.rmtree(repo_path, ignore_errors=True)
