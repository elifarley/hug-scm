"""Unit tests for worktree_select.py — worktree selection with Python-owned filtering."""

import pytest

from git.worktree import WorktreeInfo
from git.worktree_select import (
    WorktreeFilterOptions,
    WorktreeSelectionResult,
    _bash_escape,
    filter_worktrees,
)


# ---------------------------------------------------------------------------
# Shared fixtures for WorktreeInfo objects
# ---------------------------------------------------------------------------


@pytest.fixture
def main_wt():
    return WorktreeInfo(
        path="/home/user/repo",
        branch="main",
        commit="abc1234",
        is_dirty=False,
        is_locked=False,
    )


@pytest.fixture
def feature_wt():
    return WorktreeInfo(
        path="/home/user/repo.WT.feature-1",
        branch="feature-1",
        commit="def5678",
        is_dirty=True,
        is_locked=False,
    )


@pytest.fixture
def bugfix_wt():
    return WorktreeInfo(
        path="/home/user/repo.WT.bugfix-2",
        branch="bugfix-2",
        commit="123abcd",
        is_dirty=False,
        is_locked=True,
    )


class TestWorktreeFilterOptions:
    """Tests for WorktreeFilterOptions dataclass."""

    def test_defaults(self):
        opts = WorktreeFilterOptions()
        assert opts.include_main is True
        assert opts.exclude_current is False

    def test_custom_values(self):
        opts = WorktreeFilterOptions(include_main=False, exclude_current=True)
        assert opts.include_main is False
        assert opts.exclude_current is True


class TestWorktreeSelectionResult:
    """Tests for WorktreeSelectionResult dataclass."""

    def test_selected(self):
        result = WorktreeSelectionResult(status="selected", path="/path/to/wt")
        assert result.status == "selected"
        assert result.path == "/path/to/wt"

    def test_cancelled(self):
        result = WorktreeSelectionResult(status="cancelled", path="")
        assert result.status == "cancelled"
        assert result.path == ""

    def test_no_worktrees(self):
        result = WorktreeSelectionResult(status="no_worktrees", path="")
        assert result.status == "no_worktrees"


class TestBashEscape:
    """Tests for _bash_escape function."""

    def test_simple_string(self):
        assert _bash_escape("hello") == "'hello'"

    def test_single_quotes(self):
        result = _bash_escape("it's")
        assert result == "'it'\\''s'"

    def test_backslashes(self):
        result = _bash_escape("path\\to")
        assert result == "'path\\\\to'"

    def test_spaces_in_path(self):
        result = _bash_escape("/home/user/my repo")
        assert result == "'/home/user/my repo'"

    def test_empty_string(self):
        assert _bash_escape("") == "''"


class TestFilterWorktrees:
    """Tests for filter_worktrees() — pure filtering with no side effects."""

    def test_no_filters_returns_all(self, main_wt, feature_wt, bugfix_wt):
        """Default options (include_main=True, exclude_current=False) return all worktrees."""
        opts = WorktreeFilterOptions(include_main=True, exclude_current=False)
        result = filter_worktrees(
            [main_wt, feature_wt, bugfix_wt], opts, main_wt.path, feature_wt.path
        )
        assert result == [main_wt, feature_wt, bugfix_wt]

    def test_exclude_main(self, main_wt, feature_wt, bugfix_wt):
        """include_main=False removes the main worktree from results."""
        opts = WorktreeFilterOptions(include_main=False, exclude_current=False)
        result = filter_worktrees(
            [main_wt, feature_wt, bugfix_wt], opts, main_wt.path, bugfix_wt.path
        )
        assert main_wt not in result
        assert feature_wt in result
        assert bugfix_wt in result

    def test_exclude_current(self, main_wt, feature_wt, bugfix_wt):
        """exclude_current=True removes only the worktree the user is currently in."""
        opts = WorktreeFilterOptions(include_main=True, exclude_current=True)
        result = filter_worktrees(
            [main_wt, feature_wt, bugfix_wt], opts, main_wt.path, feature_wt.path
        )
        assert feature_wt not in result
        assert main_wt in result
        assert bugfix_wt in result

    def test_exclude_main_and_current(self, main_wt, feature_wt, bugfix_wt):
        """git-wtdel scenario: exclude main AND current (user is in feature worktree)."""
        opts = WorktreeFilterOptions(include_main=False, exclude_current=True)
        result = filter_worktrees(
            [main_wt, feature_wt, bugfix_wt], opts, main_wt.path, feature_wt.path
        )
        assert result == [bugfix_wt]

    def test_exclude_current_when_in_main(self, main_wt, feature_wt):
        """When current == main and both filters active, main is excluded only once."""
        opts = WorktreeFilterOptions(include_main=False, exclude_current=True)
        result = filter_worktrees(
            [main_wt, feature_wt], opts, main_wt.path, main_wt.path
        )
        # main excluded by include_main=False; current==main so no double-remove needed
        assert result == [feature_wt]

    def test_empty_input(self, main_wt):
        """Empty input list produces empty result regardless of options."""
        opts = WorktreeFilterOptions(include_main=False, exclude_current=True)
        result = filter_worktrees([], opts, main_wt.path, main_wt.path)
        assert result == []

    def test_all_excluded(self, main_wt):
        """When all worktrees are filtered out, returns an empty list."""
        opts = WorktreeFilterOptions(include_main=False, exclude_current=True)
        result = filter_worktrees([main_wt], opts, main_wt.path, main_wt.path)
        assert result == []

    def test_does_not_mutate_input(self, main_wt, feature_wt, bugfix_wt):
        """filter_worktrees must not modify the original list (pure function guarantee)."""
        original = [main_wt, feature_wt, bugfix_wt]
        original_copy = list(original)
        opts = WorktreeFilterOptions(include_main=False, exclude_current=True)
        filter_worktrees(original, opts, main_wt.path, feature_wt.path)
        assert original == original_copy
