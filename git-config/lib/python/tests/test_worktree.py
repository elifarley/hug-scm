"""Unit tests for worktree.py - Worktree parsing with type safety.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions
- Mock subprocess calls to avoid external dependencies
"""

from unittest.mock import patch

import pytest

from git.worktree import (
    WorktreeInfo,
    WorktreeList,
    _bash_escape,
    parse_worktree_list,
    to_worktree_list,
)

################################################################################
# Test Fixtures
################################################################################


@pytest.fixture
def sample_porcelain_main_only():
    """Sample porcelain output with only main worktree."""
    return """worktree /home/user/repo
branch refs/heads/main
commit abc1234def5678"""


@pytest.fixture
def sample_porcelain_with_worktrees():
    """Sample porcelain output with main and additional worktrees."""
    return """worktree /home/user/repo
branch refs/heads/main
commit abc1234def5678

worktree /home/user/repo-worktrees/feature-1
branch refs/heads/feature-1
commit def5678901234
locked

worktree /home/user/repo-worktrees/bugfix-2
branch refs/heads/bugfix-2
commit 123456789abcd"""


@pytest.fixture
def sample_porcelain_detached_head():
    """Sample porcelain output with detached HEAD (no branch line)."""
    return """worktree /home/user/repo
HEAD abc1234def5678

worktree /home/user/repo-worktrees/feature-1
branch refs/heads/feature-1
commit def5678901234"""


@pytest.fixture
def sample_porcelain_empty():
    """Empty porcelain output."""
    return ""


@pytest.fixture
def sample_porcelain_with_spaces():
    """Sample porcelain output with spaces in path."""
    return """worktree /home/user/my repo
branch refs/heads/main
commit abc1234def5678"""


@pytest.fixture
def sample_porcelain_missing_commit():
    """Sample porcelain output with missing commit line."""
    return """worktree /home/user/repo
branch refs/heads/main"""


@pytest.fixture
def main_repo_path():
    """Main repository path for testing."""
    return "/home/user/repo"


@pytest.fixture
def worktree_info_main():
    """Sample WorktreeInfo for main repo."""
    return WorktreeInfo(
        path="/home/user/repo",
        branch="main",
        commit="abc1234",
        is_dirty=False,
        is_locked=False,
    )


@pytest.fixture
def worktree_info_feature():
    """Sample WorktreeInfo for feature branch."""
    return WorktreeInfo(
        path="/home/user/repo-worktrees/feature-1",
        branch="feature-1",
        commit="def5678",
        is_dirty=False,
        is_locked=True,
    )


################################################################################
# TestBashEscape
################################################################################


class TestBashEscape:
    """Tests for _bash_escape function."""

    def test_escapes_single_quotes(self):
        """Should escape single quotes correctly."""
        result = _bash_escape("it's a test")
        assert "'\\''" in result

    def test_escapes_backslashes(self):
        """Should escape backslashes correctly."""
        result = _bash_escape(r"back\slash")
        assert "\\\\" in result

    def test_handles_simple_string(self):
        """Should handle simple alphanumeric string."""
        result = _bash_escape("simple-test")
        assert result == "'simple-test'"

    def test_handles_special_characters(self):
        """Should handle various special characters."""
        result = _bash_escape("test: value! [tag]")
        assert "test:" in result
        assert "value!" in result
        assert "[tag]" in result


################################################################################
# TestWorktreeInfo
################################################################################


class TestWorktreeInfo:
    """Tests for WorktreeInfo dataclass."""

    def test_initialization(self):
        """Should initialize with all fields."""
        info = WorktreeInfo(
            path="/path/to/worktree",
            branch="feature",
            commit="abc1234",
            is_dirty=True,
            is_locked=False,
        )
        assert info.path == "/path/to/worktree"
        assert info.branch == "feature"
        assert info.commit == "abc1234"
        assert info.is_dirty is True
        assert info.is_locked is False

    def test_empty_fields_allowed(self):
        """Should allow empty strings for optional fields."""
        info = WorktreeInfo(
            path="/path/to/worktree",
            branch="",
            commit="",
            is_dirty=False,
            is_locked=False,
        )
        assert info.path == "/path/to/worktree"
        assert info.branch == ""
        assert info.commit == ""


################################################################################
# TestWorktreeList
################################################################################


class TestWorktreeList:
    """Tests for WorktreeList dataclass."""

    def test_initialization(self):
        """Should initialize with parallel arrays."""
        result = WorktreeList(
            paths=["/path1", "/path2"],
            branches=["main", "feature"],
            commits=["abc123", "def456"],
            dirty_status=["false", "true"],
            locked_status=["false", "true"],
        )
        assert len(result.paths) == 2
        assert len(result.branches) == 2
        assert len(result.commits) == 2
        assert len(result.dirty_status) == 2
        assert len(result.locked_status) == 2

    def test_to_bash_declare(self):
        """Should output bash declare statements."""
        result = WorktreeList(
            paths=["/path/to/worktree"],
            branches=["feature"],
            commits=["abc1234"],
            dirty_status=["false"],
            locked_status=["false"],
        )
        output = result.to_bash_declare()
        assert "declare -a _wt_paths=('/path/to/worktree')" in output
        assert "declare -a _wt_branches=('feature')" in output
        assert "declare -a _wt_commits=('abc1234')" in output
        assert "declare -a _wt_dirty_status=('false')" in output
        assert "declare -a _wt_locked_status=('false')" in output

    def test_to_bash_declare_escapes_special_chars(self):
        """Should escape special characters in bash output."""
        result = WorktreeList(
            paths=["/path/it's a test"],
            branches=["feature"],
            commits=["abc1234"],
            dirty_status=["false"],
            locked_status=["false"],
        )
        output = result.to_bash_declare()
        assert "'\\''" in output

    def test_to_bash_declare_empty_arrays(self):
        """Should handle empty arrays."""
        result = WorktreeList(
            paths=[],
            branches=[],
            commits=[],
            dirty_status=[],
            locked_status=[],
        )
        output = result.to_bash_declare()
        assert "declare -a _wt_paths=()" in output
        assert "declare -a _wt_branches=()" in output


################################################################################
# TestParseWorktreeList - State Machine Parser
################################################################################


class TestParseWorktreeList:
    """Tests for parse_worktree_list state machine parser."""

    @patch("git.worktree._check_worktree_dirty")
    def test_empty_input_returns_empty_list(self, mock_check_dirty):
        """Should return empty list for empty input."""
        mock_check_dirty.return_value = False
        result = parse_worktree_list("", "/main/path", include_main=False)
        assert result == []

    @patch("git.worktree._check_worktree_dirty")
    def test_single_worktree_main_only_excluded(self, mock_check_dirty):
        """Should exclude main worktree when include_main=False."""
        mock_check_dirty.return_value = False
        porcelain = """worktree /home/user/repo
branch refs/heads/main
commit abc1234def5678"""
        result = parse_worktree_list(porcelain, "/home/user/repo", include_main=False)
        assert result == []

    @patch("git.worktree._check_worktree_dirty")
    def test_single_worktree_main_only_included(self, mock_check_dirty):
        """Should include main worktree when include_main=True."""
        mock_check_dirty.return_value = False
        porcelain = """worktree /home/user/repo
branch refs/heads/main
commit abc1234def5678"""
        result = parse_worktree_list(porcelain, "/home/user/repo", include_main=True)
        assert len(result) == 1
        assert result[0].path == "/home/user/repo"
        assert result[0].branch == "main"
        assert result[0].commit == "abc1234"
        assert result[0].is_locked is False

    @patch("git.worktree._check_worktree_dirty")
    def test_multiple_worktrees_excludes_main(self, mock_check_dirty):
        """Should return only additional worktrees when include_main=False."""
        mock_check_dirty.return_value = False
        porcelain = """worktree /home/user/repo
branch refs/heads/main
commit abc1234def5678

worktree /home/user/repo-worktrees/feature-1
branch refs/heads/feature-1
commit def5678901234

worktree /home/user/repo-worktrees/bugfix-2
branch refs/heads/bugfix-2
commit 123456789abcd"""
        result = parse_worktree_list(porcelain, "/home/user/repo", include_main=False)
        assert len(result) == 2
        assert result[0].branch == "feature-1"
        assert result[1].branch == "bugfix-2"

    @patch("git.worktree._check_worktree_dirty")
    def test_multiple_worktrees_includes_main(self, mock_check_dirty):
        """Should return all worktrees when include_main=True."""
        mock_check_dirty.return_value = False
        porcelain = """worktree /home/user/repo
branch refs/heads/main
commit abc1234def5678

worktree /home/user/repo-worktrees/feature-1
branch refs/heads/feature-1
commit def5678901234"""
        result = parse_worktree_list(porcelain, "/home/user/repo", include_main=True)
        assert len(result) == 2
        assert result[0].branch == "main"
        assert result[1].branch == "feature-1"

    @patch("git.worktree._check_worktree_dirty")
    def test_detached_head_no_branch_line(self, mock_check_dirty):
        """Should handle detached HEAD (no branch line)."""
        mock_check_dirty.return_value = False
        porcelain = """worktree /home/user/repo
HEAD abc1234def5678"""
        result = parse_worktree_list(porcelain, "/home/user/repo", include_main=True)
        assert len(result) == 1
        assert result[0].branch == ""  # Empty for detached HEAD

    @patch("git.worktree._check_worktree_dirty")
    def test_locked_worktree_detected(self, mock_check_dirty):
        """Should detect locked worktrees."""
        mock_check_dirty.return_value = False
        porcelain = """worktree /home/user/repo-worktrees/feature-1
branch refs/heads/feature-1
commit def5678901234
locked"""
        result = parse_worktree_list(porcelain, "/home/user/repo", include_main=False)
        assert len(result) == 1
        assert result[0].is_locked is True

    @patch("git.worktree._check_worktree_dirty")
    def test_commit_hash_shortened_to_7_chars(self, mock_check_dirty):
        """Should shorten commit hash to 7 characters."""
        mock_check_dirty.return_value = False
        porcelain = """worktree /home/user/repo
branch refs/heads/main
commit abc1234def5678"""
        result = parse_worktree_list(porcelain, "/home/user/repo", include_main=True)
        assert result[0].commit == "abc1234"

    @patch("git.worktree._check_worktree_dirty")
    def test_worktree_with_spaces_in_path(self, mock_check_dirty):
        """Should handle worktrees with spaces in path."""
        mock_check_dirty.return_value = False
        porcelain = """worktree /home/user/my repo
branch refs/heads/main
commit abc1234def5678"""
        result = parse_worktree_list(porcelain, "/home/user/my repo", include_main=True)
        assert len(result) == 1
        assert result[0].path == "/home/user/my repo"

    @patch("git.worktree._check_worktree_dirty")
    def test_missing_commit_line(self, mock_check_dirty):
        """Should handle missing commit line gracefully."""
        mock_check_dirty.return_value = False
        porcelain = """worktree /home/user/repo
branch refs/heads/main"""
        result = parse_worktree_list(porcelain, "/home/user/repo", include_main=True)
        assert len(result) == 1
        assert result[0].commit == ""  # Empty when no commit line

    @patch("git.worktree._check_worktree_dirty")
    def test_dirty_status_checked(self, mock_check_dirty):
        """Should call _check_worktree_dirty for each worktree."""
        mock_check_dirty.return_value = True  # Worktree is dirty
        porcelain = """worktree /home/user/repo
branch refs/heads/main
commit abc1234def5678"""
        result = parse_worktree_list(porcelain, "/home/user/repo", include_main=True)
        mock_check_dirty.assert_called_once_with("/home/user/repo")
        assert result[0].is_dirty is True


################################################################################
# TestToWorktreeList
################################################################################


class TestToWorktreeList:
    """Tests for to_worktree_list converter function."""

    def test_converts_empty_list(self):
        """Should handle empty list."""
        worktrees = []
        result = to_worktree_list(worktrees)
        assert result.paths == []
        assert result.branches == []
        assert result.commits == []
        assert result.dirty_status == []
        assert result.locked_status == []

    def test_converts_single_worktree(self):
        """Should convert single worktree to parallel arrays."""
        worktrees = [
            WorktreeInfo(
                path="/path/to/wt",
                branch="feature",
                commit="abc1234",
                is_dirty=True,
                is_locked=False,
            )
        ]
        result = to_worktree_list(worktrees)
        assert result.paths == ["/path/to/wt"]
        assert result.branches == ["feature"]
        assert result.commits == ["abc1234"]
        assert result.dirty_status == ["true"]
        assert result.locked_status == ["false"]

    def test_converts_multiple_worktrees(self):
        """Should convert multiple worktrees to parallel arrays."""
        worktrees = [
            WorktreeInfo(
                path="/path1",
                branch="main",
                commit="abc1234",
                is_dirty=False,
                is_locked=False,
            ),
            WorktreeInfo(
                path="/path2",
                branch="feature",
                commit="def5678",
                is_dirty=True,
                is_locked=True,
            ),
        ]
        result = to_worktree_list(worktrees)
        assert len(result.paths) == 2
        assert result.paths == ["/path1", "/path2"]
        assert result.branches == ["main", "feature"]
        assert result.commits == ["abc1234", "def5678"]
        assert result.dirty_status == ["false", "true"]
        assert result.locked_status == ["false", "true"]

    def test_parallel_arrays_consistent_length(self):
        """Should maintain consistent array lengths."""
        worktrees = [
            WorktreeInfo(
                path=f"/path{i}",
                branch=f"branch{i}",
                commit=f"hash{i}",
                is_dirty=False,
                is_locked=False,
            )
            for i in range(5)
        ]
        result = to_worktree_list(worktrees)
        assert len(result.paths) == len(result.branches)
        assert len(result.paths) == len(result.commits)
        assert len(result.paths) == len(result.dirty_status)
        assert len(result.paths) == len(result.locked_status)

    def test_parallel_arrays_index_alignment(self):
        """Should maintain index alignment across arrays."""
        worktrees = [
            WorktreeInfo(
                path="/path1", branch="main", commit="hash1", is_dirty=False, is_locked=False
            ),
            WorktreeInfo(
                path="/path2", branch="feature", commit="hash2", is_dirty=True, is_locked=True
            ),
        ]
        result = to_worktree_list(worktrees)
        # Index 0 should be main worktree
        assert result.paths[0] == "/path1"
        assert result.branches[0] == "main"
        assert result.commits[0] == "hash1"
        assert result.dirty_status[0] == "false"
        assert result.locked_status[0] == "false"
        # Index 1 should be feature worktree
        assert result.paths[1] == "/path2"
        assert result.branches[1] == "feature"
        assert result.commits[1] == "hash2"
        assert result.dirty_status[1] == "true"
        assert result.locked_status[1] == "true"


################################################################################
# TestMainFunction - CLI Integration
################################################################################


class TestMainFunction:
    """Tests for main() CLI entry point."""

    @patch("git.worktree._get_worktree_porcelain")
    @patch("git.worktree._get_main_repo_path")
    def test_list_command_with_include_main_flag(self, mock_get_main, mock_get_porcelain, capsys):
        """Should handle list command with --include-main flag."""
        mock_get_main.return_value = "/home/user/repo"
        mock_get_porcelain.return_value = """worktree /home/user/repo
branch refs/heads/main
commit abc1234def5678"""
        # Simulate command line arguments
        import sys

        original_argv = sys.argv
        try:
            sys.argv = ["worktree.py", "list", "--include-main"]
            # Import and run main
            from git.worktree import main

            main()
            captured = capsys.readouterr()
            assert "declare -a _wt_paths=('/home/user/repo')" in captured.out
            assert "declare -a _wt_branches=('main')" in captured.out
        finally:
            sys.argv = original_argv

    @patch("git.worktree._get_worktree_porcelain")
    @patch("git.worktree._get_main_repo_path")
    def test_list_command_without_include_main(self, mock_get_main, mock_get_porcelain, capsys):
        """Should exclude main when --include-main not specified."""
        mock_get_main.return_value = "/home/user/repo"
        mock_get_porcelain.return_value = """worktree /home/user/repo
branch refs/heads/main
commit abc1234def5678"""
        import sys

        original_argv = sys.argv
        try:
            sys.argv = ["worktree.py", "list"]
            from git.worktree import main

            main()
            captured = capsys.readouterr()
            assert "declare -a _wt_paths=()" in captured.out  # Empty
        finally:
            sys.argv = original_argv

    @patch("git.worktree._get_worktree_porcelain")
    @patch("git.worktree._get_main_repo_path")
    def test_list_command_empty_porcelain(self, mock_get_main, mock_get_porcelain, capsys):
        """Should output empty arrays when porcelain output is empty."""
        mock_get_main.return_value = "/home/user/repo"
        mock_get_porcelain.return_value = ""
        import sys

        original_argv = sys.argv
        try:
            sys.argv = ["worktree.py", "list"]
            from git.worktree import main

            main()
            captured = capsys.readouterr()
            assert "declare -a _wt_paths=()" in captured.out
        finally:
            sys.argv = original_argv

    @patch("git.worktree._get_main_repo_path")
    def test_list_command_not_in_git_repo(self, mock_get_main, capsys):
        """Should error when not in a git repository."""
        mock_get_main.return_value = ""  # Empty = not in git repo
        import sys

        original_argv = sys.argv
        try:
            sys.argv = ["worktree.py", "list"]
            from git.worktree import main

            with pytest.raises(SystemExit) as exc_info:
                main()
            assert exc_info.value.code == 1
            captured = capsys.readouterr()
            assert "Error: Not in a git repository" in captured.err
        finally:
            sys.argv = original_argv
