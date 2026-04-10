"""Unit tests for worktree_select.py — worktree selection with Python-owned filtering."""

import os
from unittest.mock import MagicMock, patch

import pytest

from git.selection_core import bash_escape
from git.worktree import WorktreeInfo
from git.worktree_select import (
    WorktreeFilterOptions,
    WorktreeSelectionResult,
    _load_worktrees,
    _run_git,
    filter_worktrees,
    format_display_rows,
    selection_to_bash_declare,
    worktrees_to_bash_declare,
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
    """Tests for bash_escape (imported from selection_core — shared infrastructure)."""

    def test_simple_string(self):
        assert bash_escape("hello") == "'hello'"

    def test_single_quotes(self):
        result = bash_escape("it's")
        assert result == "'it'\\''s'"

    def test_backslashes(self):
        result = bash_escape("path\\to")
        assert result == "'path\\\\to'"

    def test_spaces_in_path(self):
        result = bash_escape("/home/user/my repo")
        assert result == "'/home/user/my repo'"

    def test_empty_string(self):
        assert bash_escape("") == "''"


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
        result = filter_worktrees([main_wt, feature_wt], opts, main_wt.path, main_wt.path)
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
        rows = format_display_rows([main_wt, feature_wt, bugfix_wt], current_path="/other")
        assert len(rows) == 3
        # Each row corresponds to the same-index input worktree
        assert "main" in rows[0]
        assert "feature-1" in rows[1]
        assert "bugfix-2" in rows[2]

    def test_empty_list(self):
        """Empty input produces empty output."""
        rows = format_display_rows([], current_path="/some/path")
        assert rows == []


class TestWorktreesToBashDeclare:
    """Tests for worktrees_to_bash_declare() — serialises worktrees for bash eval."""

    def test_normal_output(self, main_wt, feature_wt):
        """Normal case: paths and formatted rows appear in the output."""
        rows = ["main (abc1234) → /home/user/repo", "feature-1 (def5678) → ~/feature"]
        output = worktrees_to_bash_declare([main_wt, feature_wt], rows)
        assert "declare -a worktree_paths=" in output
        assert "declare -a formatted_options=" in output
        assert "/home/user/repo" in output
        # BashDeclareBuilder emits 'declare name=value' for scalars
        assert "declare selection_status='ready'" in output
        # BashDeclareBuilder emits 'declare -i name=value' for integers
        assert "declare -i worktree_count=2" in output

    def test_empty_no_worktrees(self):
        """Empty worktrees list produces empty arrays and no_worktrees status."""
        output = worktrees_to_bash_declare([], [])
        assert "declare -a worktree_paths=()" in output
        assert "declare -a formatted_options=()" in output
        assert "declare selection_status='no_worktrees'" in output
        assert "declare -i worktree_count=0" in output

    def test_empty_with_custom_status(self):
        """Empty list with a custom status string uses that status."""
        output = worktrees_to_bash_declare([], [], status="error")
        assert "declare selection_status='error'" in output

    def test_paths_with_spaces_escaped(self):
        """Paths containing spaces are safely single-quoted for bash eval."""
        wt = WorktreeInfo(
            path="/home/user/my projects/repo",
            branch="main",
            commit="abc1234",
            is_dirty=False,
            is_locked=False,
        )
        output = worktrees_to_bash_declare([wt], ["main (abc1234) → ~/my projects/repo"])
        # Space inside the path must be inside single quotes, not bare
        assert "'/home/user/my projects/repo'" in output


class TestSelectionToBashDeclare:
    """Tests for selection_to_bash_declare() — serialises a WorktreeSelectionResult."""

    def test_selected(self):
        """A 'selected' result emits the path and 'selected' status."""
        result = WorktreeSelectionResult(status="selected", path="/home/user/repo")
        output = selection_to_bash_declare(result)
        # BashDeclareBuilder emits 'declare name=value' for scalars
        assert "declare _sel_path='/home/user/repo'" in output
        assert "declare selection_status='selected'" in output

    def test_cancelled(self):
        """A 'cancelled' result emits an empty path and 'cancelled' status."""
        result = WorktreeSelectionResult(status="cancelled", path="")
        output = selection_to_bash_declare(result)
        assert "declare _sel_path=''" in output
        assert "declare selection_status='cancelled'" in output

    def test_no_worktrees(self):
        """A 'no_worktrees' result emits an empty path and 'no_worktrees' status."""
        result = WorktreeSelectionResult(status="no_worktrees", path="")
        output = selection_to_bash_declare(result)
        assert "declare _sel_path=''" in output
        assert "declare selection_status='no_worktrees'" in output


# ---------------------------------------------------------------------------
# Porcelain output used across Task 5 tests
# ---------------------------------------------------------------------------

_PORCELAIN_TWO_WORKTREES = """\
worktree /home/user/repo
HEAD abc1234567890abcdef
branch refs/heads/main

worktree /home/user/repo.WT.feature-1
HEAD def567890abcdef1234
branch refs/heads/feature-1
"""


class TestRunGit:
    """Tests for _run_git() — thin subprocess wrapper with failure-safe returns."""

    def test_returns_stdout_stripped(self):
        """Successful commands return stdout with leading/trailing whitespace removed."""
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = "  /home/user/repo  \n"
        with patch("git.worktree_select.subprocess.run", return_value=mock_result):
            assert _run_git(["rev-parse", "--show-toplevel"]) == "/home/user/repo"

    def test_returns_empty_on_failure(self):
        """Non-zero exit codes return empty string (never raise)."""
        mock_result = MagicMock()
        mock_result.returncode = 128
        mock_result.stdout = "fatal: not a git repository\n"
        with patch("git.worktree_select.subprocess.run", return_value=mock_result):
            assert _run_git(["rev-parse", "--show-toplevel"]) == ""

    def test_returns_empty_on_timeout(self):
        """TimeoutExpired exceptions are swallowed and return empty string."""
        import subprocess

        with patch(
            "git.worktree_select.subprocess.run",
            side_effect=subprocess.TimeoutExpired(cmd="git", timeout=10),
        ):
            assert _run_git(["worktree", "list", "--porcelain"]) == ""


class TestLoadWorktrees:
    """Tests for _load_worktrees() — git integration that discovers paths and parses output."""

    def _make_run_git_side_effect(self, toplevel: str, common_dir: str, porcelain: str):
        """Build a side_effect function that returns canned responses per args."""

        def side_effect(args: list[str]) -> str:
            if "--show-toplevel" in args:
                return toplevel
            if "--git-common-dir" in args:
                return common_dir
            if "worktree" in args and "--porcelain" in args:
                return porcelain
            return ""

        return side_effect

    def test_returns_worktrees_and_paths(self):
        """Happy path: returns parsed worktrees plus main and current paths."""
        side_effect = self._make_run_git_side_effect(
            toplevel="/home/user/repo.WT.feature-1",
            common_dir="/home/user/repo/.git",
            porcelain=_PORCELAIN_TWO_WORKTREES,
        )
        with (
            patch("git.worktree_select._run_git", side_effect=side_effect),
            patch("git.worktree_select.parse_worktree_list") as mock_parse,
        ):
            mock_wts = [
                WorktreeInfo("/home/user/repo", "main", "abc1234", False, False),
                WorktreeInfo("/home/user/repo.WT.feature-1", "feature-1", "def5678", False, False),
            ]
            mock_parse.return_value = mock_wts
            wts, main_path, current_path = _load_worktrees()

        assert wts == mock_wts
        assert main_path == "/home/user/repo"
        assert current_path == "/home/user/repo.WT.feature-1"
        # parse_worktree_list called with include_main=True so filtering is deferred
        mock_parse.assert_called_once_with(
            _PORCELAIN_TWO_WORKTREES, "/home/user/repo", include_main=True
        )

    def test_returns_empty_when_not_in_repo(self):
        """When not inside a git repo, returns three empty values without crashing."""
        with patch("git.worktree_select._run_git", return_value=""):
            wts, main_path, current_path = _load_worktrees()
        assert wts == []
        assert main_path == ""
        assert current_path == ""

    def test_detects_worktree_vs_main(self):
        """main_path is derived from --git-common-dir, not --show-toplevel."""
        # Simulate being in main repo: --git-common-dir returns ".git" (relative)
        side_effect_main = self._make_run_git_side_effect(
            toplevel="/home/user/repo",
            common_dir=".git",
            porcelain=_PORCELAIN_TWO_WORKTREES,
        )
        with (
            patch("git.worktree_select._run_git", side_effect=side_effect_main),
            patch("git.worktree_select.parse_worktree_list", return_value=[]),
        ):
            _, main_path, current_path = _load_worktrees()
        # When common_dir == ".git", main_path must equal current_path (we're in main)
        assert main_path == "/home/user/repo"
        assert current_path == "/home/user/repo"


# ---------------------------------------------------------------------------
# Helpers shared by Task 6 tests
# ---------------------------------------------------------------------------

#: Minimal single-worktree tuple returned by a mocked _load_worktrees()
_ONE_WORKTREE = WorktreeInfo(
    path="/home/user/repo.WT.feature-1",
    branch="feature-1",
    commit="def5678",
    is_dirty=False,
    is_locked=False,
)

_TWO_WORKTREES = [
    WorktreeInfo(
        path="/home/user/repo.WT.feature-1",
        branch="feature-1",
        commit="def5678",
        is_dirty=False,
        is_locked=False,
    ),
    WorktreeInfo(
        path="/home/user/repo.WT.bugfix-2",
        branch="bugfix-2",
        commit="123abcd",
        is_dirty=False,
        is_locked=False,
    ),
]

#: Default load result: one linked worktree, main is the main repo
_LOAD_RESULT_ONE = ([_ONE_WORKTREE], "/home/user/repo", "/home/user/repo")


# ---------------------------------------------------------------------------
# Import the new CLI functions (these will fail until implemented)
# ---------------------------------------------------------------------------

from git.worktree_select import _cmd_prepare, _cmd_select, main  # noqa: E402


class TestCmdPrepare:
    """Tests for _cmd_prepare() — the gum / interactive-picker preparation path.

    _cmd_prepare() calls _load_worktrees(), filters with filter_worktrees(),
    formats with format_display_rows(), and serialises to bash declare output
    via worktrees_to_bash_declare().  All git I/O is exercised through the
    _load_worktrees mock so tests remain hermetic.
    """

    def test_normal_output(self):
        """One available worktree produces declare output with path and formatted row."""
        opts = WorktreeFilterOptions(include_main=True, exclude_current=False)
        with patch("git.worktree_select._load_worktrees", return_value=_LOAD_RESULT_ONE):
            output = _cmd_prepare(opts)
        # Core structural markers
        assert "declare -a worktree_paths=" in output
        assert "declare -a formatted_options=" in output
        # The real worktree path must appear verbatim
        assert "/home/user/repo.WT.feature-1" in output
        # The formatted row must reference the branch name
        assert "feature-1" in output
        # BashDeclareBuilder emits 'declare name=value' for scalars
        assert "declare selection_status='ready'" in output
        # BashDeclareBuilder emits 'declare -i name=value' for integers
        assert "declare -i worktree_count=1" in output

    def test_no_worktrees_when_load_fails(self):
        """When _load_worktrees returns nothing, output carries no_worktrees status."""
        opts = WorktreeFilterOptions()
        with patch("git.worktree_select._load_worktrees", return_value=([], "", "")):
            output = _cmd_prepare(opts)
        assert "declare selection_status='no_worktrees'" in output
        assert "declare -a worktree_paths=()" in output
        assert "declare -i worktree_count=0" in output

    def test_all_filtered_out_gives_no_worktrees(self):
        """When all loaded worktrees are removed by filters, status is no_worktrees."""
        # Only the main worktree exists; include_main=False removes it
        main_only = WorktreeInfo(
            path="/home/user/repo",
            branch="main",
            commit="abc1234",
            is_dirty=False,
            is_locked=False,
        )
        opts = WorktreeFilterOptions(include_main=False, exclude_current=False)
        with patch(
            "git.worktree_select._load_worktrees",
            return_value=([main_only], "/home/user/repo", "/home/user/repo"),
        ):
            output = _cmd_prepare(opts)
        assert "declare selection_status='no_worktrees'" in output
        assert "declare -i worktree_count=0" in output


class TestCmdSelect:
    """Tests for _cmd_select() — the numbered-list interactive selection path.

    _cmd_select() prints a numbered menu to stderr, reads one line from stdin,
    and serialises the outcome via selection_to_bash_declare().  All git I/O
    and user input are mocked so tests are fully hermetic and non-interactive.
    """

    def test_valid_selection(self):
        """Entering '1' for a single-item list selects that worktree."""
        opts = WorktreeFilterOptions()
        with patch("git.worktree_select._load_worktrees", return_value=_LOAD_RESULT_ONE):
            with patch("builtins.input", return_value="1"):
                output = _cmd_select(opts, prompt="Pick worktree")
        # BashDeclareBuilder emits 'declare name=value' for scalars
        assert "declare selection_status='selected'" in output
        assert "/home/user/repo.WT.feature-1" in output

    def test_valid_selection_via_test_selection_arg(self):
        """test_selection kwarg injects a selection without touching builtins.input."""
        opts = WorktreeFilterOptions()
        with patch("git.worktree_select._load_worktrees", return_value=_LOAD_RESULT_ONE):
            output = _cmd_select(opts, prompt="Pick worktree", test_selection="1")
        assert "declare selection_status='selected'" in output
        assert "/home/user/repo.WT.feature-1" in output

    def test_cancelled_on_empty_input(self):
        """Pressing Enter (empty string) cancels the selection."""
        opts = WorktreeFilterOptions()
        with patch("git.worktree_select._load_worktrees", return_value=_LOAD_RESULT_ONE):
            with patch("builtins.input", return_value=""):
                output = _cmd_select(opts, prompt="Pick worktree")
        assert "declare selection_status='cancelled'" in output
        assert "declare _sel_path=''" in output

    def test_invalid_number_cancels(self):
        """An out-of-range number (e.g. '99') cancels without raising."""
        opts = WorktreeFilterOptions()
        with patch("git.worktree_select._load_worktrees", return_value=_LOAD_RESULT_ONE):
            with patch("builtins.input", return_value="99"):
                output = _cmd_select(opts, prompt="Pick worktree")
        assert "declare selection_status='cancelled'" in output

    def test_non_numeric_input_cancels(self):
        """Non-numeric text (e.g. 'abc') cancels without raising."""
        opts = WorktreeFilterOptions()
        with patch("git.worktree_select._load_worktrees", return_value=_LOAD_RESULT_ONE):
            with patch("builtins.input", return_value="abc"):
                output = _cmd_select(opts, prompt="Pick worktree")
        assert "declare selection_status='cancelled'" in output

    def test_eof_on_input_cancels(self):
        """EOFError (Ctrl-D / piped /dev/null) cancels gracefully."""
        opts = WorktreeFilterOptions()
        with patch("git.worktree_select._load_worktrees", return_value=_LOAD_RESULT_ONE):
            with patch("builtins.input", side_effect=EOFError):
                output = _cmd_select(opts, prompt="Pick worktree")
        assert "declare selection_status='cancelled'" in output

    def test_no_worktrees_when_load_fails(self):
        """When _load_worktrees returns nothing, status is no_worktrees (no prompt)."""
        opts = WorktreeFilterOptions()
        with patch("git.worktree_select._load_worktrees", return_value=([], "", "")):
            # input() must NOT be called — no prompt to show
            with patch("builtins.input", side_effect=AssertionError("input called unexpectedly")):
                output = _cmd_select(opts, prompt="Pick worktree")
        assert "declare selection_status='no_worktrees'" in output

    def test_selects_second_item(self):
        """Entering '2' with a two-item list selects the second worktree path."""
        opts = WorktreeFilterOptions()
        load_result = (_TWO_WORKTREES, "/home/user/repo", "/home/user/repo")
        with patch("git.worktree_select._load_worktrees", return_value=load_result):
            with patch("builtins.input", return_value="2"):
                output = _cmd_select(opts, prompt="Pick worktree")
        assert "declare selection_status='selected'" in output
        assert "/home/user/repo.WT.bugfix-2" in output


class TestMain:
    """Tests for main() — argparse CLI entry point.

    main() wires together argparse, WorktreeFilterOptions construction, and
    dispatching to _cmd_prepare / _cmd_select.  Tests mock at the _cmd_prepare
    / _cmd_select boundary so we only verify the wiring, not the inner logic.
    """

    def test_prepare_command_dispatches(self, capsys):
        """'prepare' sub-command calls _cmd_prepare and prints its output."""
        sentinel = "declare -a worktree_paths=()\nselection_status='no_worktrees'\nworktree_count=0"
        with patch("git.worktree_select._cmd_prepare", return_value=sentinel) as mock_prep:
            main(["prepare"])
        captured = capsys.readouterr()
        assert sentinel in captured.out
        mock_prep.assert_called_once()

    def test_select_command_dispatches(self, capsys):
        """'select' sub-command calls _cmd_select and prints its output."""
        sentinel = "_sel_path=''\nselection_status='cancelled'"
        with patch("git.worktree_select._cmd_select", return_value=sentinel) as mock_sel:
            main(["select"])
        captured = capsys.readouterr()
        assert sentinel in captured.out
        mock_sel.assert_called_once()

    def test_include_main_flag(self):
        """--include-main sets include_main=True on the filter options passed to _cmd_prepare."""
        with patch("git.worktree_select._cmd_prepare", return_value="") as mock_prep:
            main(["prepare", "--include-main"])
        opts_used: WorktreeFilterOptions = mock_prep.call_args[0][0]
        assert opts_used.include_main is True

    def test_exclude_main_flag(self):
        """Without --include-main, include_main defaults to False (safer for switching)."""
        with patch("git.worktree_select._cmd_prepare", return_value="") as mock_prep:
            main(["prepare"])
        opts_used: WorktreeFilterOptions = mock_prep.call_args[0][0]
        assert opts_used.include_main is False

    def test_exclude_current_flag(self):
        """--exclude-current sets exclude_current=True on the filter options."""
        with patch("git.worktree_select._cmd_prepare", return_value="") as mock_prep:
            main(["prepare", "--exclude-current"])
        opts_used: WorktreeFilterOptions = mock_prep.call_args[0][0]
        assert opts_used.exclude_current is True

    def test_prompt_passed_to_select(self):
        """--prompt value is forwarded to _cmd_select as the second argument."""
        with patch("git.worktree_select._cmd_select", return_value="") as mock_sel:
            main(["select", "--prompt", "Choose a worktree"])
        _opts, prompt = mock_sel.call_args[0]
        assert prompt == "Choose a worktree"

    def test_default_prompt_for_select(self):
        """When --prompt is omitted, _cmd_select receives a sensible default string."""
        with patch("git.worktree_select._cmd_select", return_value="") as mock_sel:
            main(["select"])
        _opts, prompt = mock_sel.call_args[0]
        # Non-empty; specific wording is an implementation detail
        assert isinstance(prompt, str) and len(prompt) > 0

    def test_exception_exits_nonzero(self, capsys):
        """Unhandled exceptions in _cmd_prepare cause exit code 1 and stderr message."""
        with patch("git.worktree_select._cmd_prepare", side_effect=RuntimeError("boom")):
            with pytest.raises(SystemExit) as exc_info:
                main(["prepare"])
        assert exc_info.value.code == 1
        captured = capsys.readouterr()
        assert "boom" in captured.err
