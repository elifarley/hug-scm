"""Unit tests for worktree_select.py — worktree selection with Python-owned filtering."""

import os

import pytest

from git.worktree import WorktreeInfo
from git.worktree_select import (
    WorktreeFilterOptions,
    WorktreeSelectionResult,
    _bash_escape,
    filter_worktrees,
    format_display_rows,
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


class TestFormatDisplayRows:
    """Tests for format_display_rows() — builds plain-text rows for interactive display."""

    def test_basic_worktree(self, feature_wt):
        """A clean non-current worktree shows branch, commit and path only."""
        rows = format_display_rows([feature_wt], current_path="/other/path")
        assert len(rows) == 1
        assert "feature-1" in rows[0]
        assert "def5678" in rows[0]
        assert "→" in rows[0]

    def test_current_indicator(self, feature_wt):
        """The worktree the user is in receives a [CURRENT] prefix."""
        rows = format_display_rows([feature_wt], current_path=feature_wt.path)
        assert rows[0].startswith("[CURRENT]")

    def test_dirty_indicator(self, feature_wt):
        """A dirty worktree (is_dirty=True) shows [DIRTY] label."""
        # feature_wt fixture has is_dirty=True
        rows = format_display_rows([feature_wt], current_path="/other")
        assert "[DIRTY]" in rows[0]

    def test_locked_indicator(self, bugfix_wt):
        """A locked worktree (is_locked=True) shows [LOCKED] label."""
        # bugfix_wt fixture has is_locked=True
        rows = format_display_rows([bugfix_wt], current_path="/other")
        assert "[LOCKED]" in rows[0]

    def test_clean_unlocked_no_indicators(self, main_wt):
        """A clean, unlocked, non-current worktree has no bracket labels."""
        rows = format_display_rows([main_wt], current_path="/other/path")
        assert "[CURRENT]" not in rows[0]
        assert "[DIRTY]" not in rows[0]
        assert "[LOCKED]" not in rows[0]

    def test_all_indicators_combined(self):
        """A current + dirty + locked worktree shows all three labels."""
        wt = WorktreeInfo(
            path="/home/user/wt",
            branch="all-flags",
            commit="aabbccd",
            is_dirty=True,
            is_locked=True,
        )
        rows = format_display_rows([wt], current_path=wt.path)
        assert "[CURRENT]" in rows[0]
        assert "[DIRTY]" in rows[0]
        assert "[LOCKED]" in rows[0]

    def test_path_shortened_with_home(self):
        """Paths under $HOME are displayed as ~/... to reduce visual noise."""
        home = os.path.expanduser("~")
        wt = WorktreeInfo(
            path=f"{home}/projects/myrepo",
            branch="main",
            commit="1234567",
            is_dirty=False,
            is_locked=False,
        )
        rows = format_display_rows([wt], current_path="/other")
        assert "~/projects/myrepo" in rows[0]
        assert home not in rows[0]

    def test_path_outside_home_not_shortened(self):
        """Paths outside $HOME are shown verbatim."""
        wt = WorktreeInfo(
            path="/tmp/special-repo",
            branch="main",
            commit="1234567",
            is_dirty=False,
            is_locked=False,
        )
        rows = format_display_rows([wt], current_path="/other")
        assert "/tmp/special-repo" in rows[0]
        assert rows[0].count("~") == 0

    def test_detached_head_empty_branch(self):
        """A detached HEAD worktree displays '(detached)' instead of a branch name."""
        wt = WorktreeInfo(
            path="/home/user/repo.WT.detached",
            branch="",
            commit="deadbee",
            is_dirty=False,
            is_locked=False,
        )
        rows = format_display_rows([wt], current_path="/other")
        assert "(detached)" in rows[0]

    def test_multiple_worktrees_preserves_order(self, main_wt, feature_wt, bugfix_wt):
        """Output list length and order exactly match the input list."""
        rows = format_display_rows(
            [main_wt, feature_wt, bugfix_wt], current_path="/other"
        )
        assert len(rows) == 3
        # Each row corresponds to the same-index input worktree
        assert "main" in rows[0]
        assert "feature-1" in rows[1]
        assert "bugfix-2" in rows[2]

    def test_empty_list(self):
        """Empty input produces empty output."""
        rows = format_display_rows([], current_path="/some/path")
        assert rows == []
