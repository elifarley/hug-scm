#!/usr/bin/env python3
"""
pytest plugin for command mock fixture framework.

Provides:
1. --regenerate-mocks flag to record fresh mock data
2. --command-type flag to specify command category
3. command_mock fixture for use in tests
4. Automatic mock generation when missing
"""

import pytest
import sys
from pathlib import Path

# Add fixtures directory to path so we can import recorder/player modules
fixtures_dir = Path(__file__).parent
if str(fixtures_dir) not in sys.path:
    sys.path.insert(0, str(fixtures_dir))

from recorder import CommandMockRecorder
from player import CommandMockPlayer


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
    return request.config.getoption("--command-type")


@pytest.fixture(scope="session")
def regenerate_mocks(request):
    """Session-scoped fixture indicating if mocks should be regenerated."""
    return request.config.getoption("--regenerate-mocks")


@pytest.fixture
def command_mock(command_type, regenerate_mocks):
    """
    Fixture providing command mock player or recorder.

    Returns CommandMockRecorder if --regenerate-mocks is set,
    otherwise CommandMockPlayer.

    Usage in tests:
        def test_something(command_mock):
            # In normal test runs, command_mock is a CommandMockPlayer
            mock_fn = command_mock.get_subprocess_mock("log/follow.toml", "basic")

            with patch('subprocess.run', side_effect=mock_fn):
                result = some_function()

        # Run with: pytest --regenerate-mocks
        # command_mock becomes CommandMockRecorder and regenerates all mock data

        # Test with different command type:
        # pytest --command-type=docker
    """
    fixtures_root = Path(__file__).parent

    if regenerate_mocks:
        return CommandMockRecorder(command_type, fixtures_root)
    else:
        return CommandMockPlayer(command_type, fixtures_root)
