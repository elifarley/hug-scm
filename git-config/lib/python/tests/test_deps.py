"""Unit tests for deps.py - commit dependency graph analysis.

These tests cover pure logic that does not require a git repository, keeping the
suite fast and deterministic. Repository-dependent behavior is exercised by the
BATS tests in tests/unit/test_analyze_deps*.bats.
"""

import pytest

import deps


class TestDetectRepositorySize:
    """Tests for detect_repository_size function."""

    @pytest.mark.parametrize(
        ("commit_count", "expected"),
        [
            (0, "small"),
            (1, "small"),
            (50, "small"),
            (99, "small"),
            (100, "medium"),
            (500, "medium"),
            (999, "medium"),
            (1000, "large"),
            (5000, "large"),
            (9999, "large"),
            (10000, "massive"),
            (100000, "massive"),
        ],
    )
    def test_detect_repository_size_boundary(self, commit_count, expected):
        """Should classify repository size based on commit count boundaries."""
        commits = [f"commit{i}" for i in range(commit_count)]
        assert deps.detect_repository_size(commits) == expected

    def test_detect_repository_size_accepts_any_sequence(self):
        """Should work with any iterable/list of commit identifiers."""
        assert deps.detect_repository_size([]) == "small"
        assert deps.detect_repository_size(["a"]) == "small"
        assert deps.detect_repository_size(["a"] * 1000) == "large"
