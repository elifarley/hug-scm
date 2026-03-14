"""Unit tests for worktree_select.py — worktree selection with Python-owned filtering."""

from git.worktree_select import (
    WorktreeFilterOptions,
    WorktreeSelectionResult,
    _bash_escape,
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
