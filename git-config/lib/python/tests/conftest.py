"""
Pytest configuration and shared fixtures for Hug SCM Python helpers.

This module provides common test fixtures and configuration following
Google's Python testing best practices.
"""

import sys
from pathlib import Path

import pytest

# Add parent directory to Python path for module imports
PYTHON_LIB_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(PYTHON_LIB_DIR))

# Import command mock framework from installed library
from command_mock.recorder import CommandMockRecorder
from command_mock.player import CommandMockPlayer


def pytest_addoption(parser):
    """Add custom command line options."""
    parser.addoption(
        "--regenerate-mocks",
        action="store_true",
        default=False,
        help="Regenerate mock data from real command calls"
    )
    parser.addoption(
        "--command-type",
        default="git",
        help="Command type for mocks (default: git). Examples: git, docker, npm"
    )


@pytest.fixture(scope="session")
def command_type(request):
    """Get command type from CLI or test parameter."""
    try:
        return request.config.getoption("--command-type")
    except ValueError:
        # Default to git when option not provided
        return "git"


@pytest.fixture(scope="session")
def regenerate_mocks(request):
    """Session-scoped fixture indicating if mocks should be regenerated."""
    try:
        return request.config.getoption("--regenerate-mocks")
    except ValueError:
        return False


@pytest.fixture
def command_mock(command_type, regenerate_mocks):
    """
    Fixture providing command mock player or recorder.

    Returns CommandMockRecorder if --regenerate-mocks is set,
    otherwise CommandMockPlayer.

    Points to LOCAL fixtures directory in this project, allowing hug-scm
    to maintain its own test data while using the framework library.
    """
    # CRITICAL: Point to LOCAL fixtures directory with hug-scm-specific mocks
    local_fixtures_root = Path(__file__).parent / 'fixtures'

    if regenerate_mocks:
        return CommandMockRecorder(command_type, fixtures_root=local_fixtures_root)
    else:
        return CommandMockPlayer(command_type, fixtures_root=local_fixtures_root)


@pytest.fixture
def sample_git_log_co_changes():
    """
    Sample git log output for co-changes analysis.

    Format: commit hash followed by file names.
    """
    return """abc1234567890123456789012345678901234567
file_a.py
file_b.py

def4567890123456789012345678901234567890
file_a.py
file_c.py

ghi7890123456789012345678901234567890123
file_a.py
file_b.py
file_c.py

jkl0123456789012345678901234567890123456
file_b.py
file_c.py

mno3456789012345678901234567890123456789
file_a.py
file_b.py
"""


@pytest.fixture
def sample_git_log_activity():
    """
    Sample git log output for activity analysis.

    Format: timestamp|author
    """
    return """2024-11-17 09:30:15 -0500|Alice Smith
2024-11-17 10:45:22 -0500|Bob Johnson
2024-11-17 14:15:33 -0500|Alice Smith
2024-11-16 09:20:11 -0500|Charlie Brown
2024-11-16 15:30:45 -0500|Bob Johnson
2024-11-15 22:15:30 -0500|Alice Smith
2024-11-15 02:30:15 -0500|Bob Johnson
2024-11-13 10:00:00 -0500|Alice Smith
"""


@pytest.fixture
def sample_git_log_ownership_file():
    """
    Sample git log output for file ownership analysis.

    Format: hash|author|date
    """
    return """abc1234|Alice Smith|2024-11-17 09:30:15 -0500
def5678|Bob Johnson|2024-11-10 14:20:30 -0500
ghi9012|Alice Smith|2024-11-09 11:15:45 -0500
jkl3456|Alice Smith|2024-11-01 16:30:22 -0500
mno7890|Charlie Brown|2024-10-15 09:45:10 -0500
pqr1234|Bob Johnson|2024-09-20 13:20:15 -0500
stu5678|Alice Smith|2024-08-10 10:30:45 -0500
"""


@pytest.fixture
def sample_git_log_ownership_author():
    """
    Sample git log output for author expertise analysis.

    Format: hash followed by file names, for specific author.
    """
    return """abc1234567890123456789012345678901234567
src/auth/login.py
src/auth/session.py

def4567890123456789012345678901234567890
src/auth/login.py
tests/auth/test_login.py

ghi7890123456789012345678901234567890123
src/api/users.py
src/models/user.py

jkl0123456789012345678901234567890123456
src/auth/session.py
src/auth/middleware.py
"""


@pytest.fixture
def mock_git_log_minimal():
    """Minimal git log output for edge case testing."""
    return """abc1234567890123456789012345678901234567
single_file.py
"""


@pytest.fixture
def empty_git_log():
    """Empty git log output for error case testing."""
    return ""
