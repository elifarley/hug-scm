"""Command execution module for running Hug SCM commands safely."""

import os
import subprocess
from collections.abc import Sequence
from pathlib import Path
from typing import Any


class CommandExecutor:
    """Execute Hug SCM commands with safety checks and error handling."""

    def __init__(self, timeout: int = 30) -> None:
        """
        Initialize the command executor.

        Args:
            timeout: Maximum execution time in seconds
        """
        self.timeout = timeout

    def validate_path(self, path: str) -> str:
        """
        Validate and normalize a file path to prevent directory traversal.

        Args:
            path: The path to validate

        Returns:
            The validated absolute path

        Raises:
            ValueError: If the path is invalid or attempts directory traversal
        """
        if not path:
            return os.getcwd()

        # Convert to absolute path and resolve any ../ or symlinks
        abs_path = Path(path).resolve()

        # Check if path exists
        if not abs_path.exists():
            raise ValueError(f"Path does not exist: {path}")

        # Ensure it's a directory for cwd parameter
        if not abs_path.is_dir():
            raise ValueError(f"Path is not a directory: {path}")

        return str(abs_path)

    def execute(self, args: Sequence[str], cwd: str | None = None) -> dict[str, Any]:
        """
        Execute a hug command and return the result.

        Args:
            args: Command arguments (e.g., ['h', 'files', '3'])
            cwd: Working directory for the command

        Returns:
            Dictionary with 'success', 'output', 'error', and 'exit_code'
        """
        try:
            # Validate working directory if provided
            validated_cwd = self.validate_path(cwd) if cwd else os.getcwd()

            # Build command
            cmd = ["hug"] + list(args)

            result = subprocess.run(
                cmd,
                cwd=validated_cwd,
                capture_output=True,
                text=True,
                timeout=self.timeout,
            )

            return {
                "success": result.returncode == 0,
                "output": result.stdout,
                "error": result.stderr if result.returncode != 0 else None,
                "exit_code": result.returncode,
            }

        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "output": "",
                "error": f"Command timed out after {self.timeout} seconds",
                "exit_code": -1,
            }
        except FileNotFoundError:
            return {
                "success": False,
                "output": "",
                "error": "Hug command not found. Please ensure Hug SCM is installed and in PATH.",
                "exit_code": -1,
            }
        except ValueError as e:
            return {
                "success": False,
                "output": "",
                "error": f"Invalid path: {str(e)}",
                "exit_code": -1,
            }
        except Exception as e:
            return {
                "success": False,
                "output": "",
                "error": f"Error executing command: {str(e)}",
                "exit_code": -1,
            }
