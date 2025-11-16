"""Pytest configuration and fixtures."""

import subprocess
import tempfile
from collections.abc import Generator
from pathlib import Path

import pytest


@pytest.fixture
def temp_git_repo() -> Generator[Path, None, None]:
    """Create a temporary git repository for testing."""
    with tempfile.TemporaryDirectory() as tmpdir:
        repo_path = Path(tmpdir)

        # Initialize git repo
        subprocess.run(["git", "init"], cwd=repo_path, check=True, capture_output=True)
        subprocess.run(
            ["git", "config", "user.email", "test@example.com"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Test User"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )

        # Create initial commit
        readme = repo_path / "README.md"
        readme.write_text("# Test Repository\n")
        subprocess.run(["git", "add", "README.md"], cwd=repo_path, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "Initial commit"],
            cwd=repo_path,
            check=True,
            capture_output=True,
        )

        # Create a few more commits for testing
        for i in range(1, 4):
            test_file = repo_path / f"file{i}.txt"
            test_file.write_text(f"Content {i}\n")
            subprocess.run(
                ["git", "add", f"file{i}.txt"], cwd=repo_path, check=True, capture_output=True
            )
            subprocess.run(
                ["git", "commit", "-m", f"Add file{i}.txt"],
                cwd=repo_path,
                check=True,
                capture_output=True,
            )

        yield repo_path


@pytest.fixture
def hug_available() -> bool:
    """Check if hug command is available."""
    try:
        result = subprocess.run(
            ["which", "hug"],
            capture_output=True,
            text=True,
        )
        return result.returncode == 0
    except Exception:
        return False
