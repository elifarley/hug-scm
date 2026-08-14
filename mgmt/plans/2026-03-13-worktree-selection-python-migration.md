# Worktree Selection Python Migration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Consolidate triplicated worktree selection logic from git-wt, git-wtdel, git-wtsh into a single Python module with a shared Bash adapter.

**Architecture:** `worktree_select.py` imports `WorktreeInfo` and `parse_worktree_list` from `worktree.py`, adds filtering, formatting, and selection. Two CLI modes (`prepare`/`select`). Shared `select_worktree()` function in `hug-git-worktree` replaces ~300 lines of duplicated Bash.

**Tech Stack:** Python 3 (dataclasses, argparse, subprocess), Bash, pytest, BATS

---

### Task 0: Baseline — verify all tests pass

**Step 1: Run full test suite**

Run: `make test`
Expected: All BATS and pytest tests pass.

**Step 2: Commit baseline (no changes expected)**

No commit needed — this is a verification step only.

---

### Task 1: Data model and _bash_escape

**Files:**
- Create: `git-config/lib/python/git/worktree_select.py`
- Test: `git-config/lib/python/tests/test_worktree_select.py`

**Step 1: Write failing tests for dataclasses and _bash_escape**

```python
"""Unit tests for worktree_select.py — worktree selection with Python-owned filtering."""

import os
from unittest.mock import patch

import pytest

from git.worktree import WorktreeInfo
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
```

**Step 2: Run tests to verify they fail**

Run: `cd git-config/lib/python && python3 -m pytest tests/test_worktree_select.py -v`
Expected: FAIL — `worktree_select` module not found.

**Step 3: Write minimal implementation**

```python
#!/usr/bin/env python3
"""
Hug Git Worktree Select Library — Python implementation

Consolidates worktree selection logic from three Bash scripts (git-wt, git-wtdel,
git-wtsh) into a single module with filtering, formatting, and interactive selection.

Key design decisions:
- Imports WorktreeInfo from worktree.py (DRY — first cross-module import in git/).
- Reuses worktree.py's parse_worktree_list() for git interaction.
- Two CLI modes: 'prepare' (gum path) and 'select' (numbered-list path).
- Single-select only (all three callers select one worktree at a time).

Exit codes: 0 always (status communicated through bash variables).
Non-zero only for genuine Python failures.
"""

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass

from git.worktree import WorktreeInfo, parse_worktree_list


@dataclass
class WorktreeFilterOptions:
    """Filtering criteria for worktree selection.

    Attributes:
        include_main: If True, include the main repository worktree.
            False for git-wt (switching) and git-wtdel (can't delete main).
            True for git-wtsh (show details of any worktree).
        exclude_current: If True, exclude the worktree the user is currently in.
            True for git-wt (can't switch to self) and git-wtdel (can't delete self).
            False for git-wtsh (may want to show current worktree details).
    """

    include_main: bool = True
    exclude_current: bool = False


@dataclass
class WorktreeSelectionResult:
    """Explicit outcome of a worktree selection operation.

    Attributes:
        status: One of:
            "selected"      — user picked a worktree; path is populated
            "cancelled"     — user pressed Enter / gave empty input
            "no_worktrees"  — no worktrees match the filters
            "error"         — unexpected failure
        path: Selected worktree path; non-empty only when status == "selected"
    """

    status: str
    path: str


def _bash_escape(s: str) -> str:
    """Escape a string for safe use inside bash declare statements.

    Strategy: wrap in single quotes, using the '\\'' idiom for embedded
    single quotes. Backslashes doubled first so bash doesn't interpret them.
    """
    s = s.replace("\\", "\\\\")
    s = s.replace("'", "'\\''")
    return f"'{s}'"
```

**Step 4: Run tests to verify they pass**

Run: `cd git-config/lib/python && python3 -m pytest tests/test_worktree_select.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add git-config/lib/python/git/worktree_select.py git-config/lib/python/tests/test_worktree_select.py
git commit -m "feat: add worktree selection data model with cross-module import"
```

---

### Task 2: filter_worktrees() pure filtering logic

**Files:**
- Modify: `git-config/lib/python/git/worktree_select.py`
- Modify: `git-config/lib/python/tests/test_worktree_select.py`

**Step 1: Write failing tests**

```python
from git.worktree_select import filter_worktrees


# Helper fixtures
@pytest.fixture
def main_wt():
    return WorktreeInfo(
        path="/home/user/repo", branch="main", commit="abc1234",
        is_dirty=False, is_locked=False,
    )

@pytest.fixture
def feature_wt():
    return WorktreeInfo(
        path="/home/user/repo.WT.feature-1", branch="feature-1", commit="def5678",
        is_dirty=True, is_locked=False,
    )

@pytest.fixture
def bugfix_wt():
    return WorktreeInfo(
        path="/home/user/repo.WT.bugfix-2", branch="bugfix-2", commit="123abcd",
        is_dirty=False, is_locked=True,
    )


class TestFilterWorktrees:
    """Tests for filter_worktrees() pure filtering."""

    def test_no_filters_returns_all(self, main_wt, feature_wt, bugfix_wt):
        result = filter_worktrees(
            [main_wt, feature_wt, bugfix_wt],
            WorktreeFilterOptions(),
            main_path="/home/user/repo",
            current_path="/home/user/repo",
        )
        assert len(result) == 3

    def test_exclude_main(self, main_wt, feature_wt, bugfix_wt):
        result = filter_worktrees(
            [main_wt, feature_wt, bugfix_wt],
            WorktreeFilterOptions(include_main=False),
            main_path="/home/user/repo",
            current_path="/home/user/repo",
        )
        assert len(result) == 2
        assert all(w.path != "/home/user/repo" for w in result)

    def test_exclude_current(self, main_wt, feature_wt, bugfix_wt):
        result = filter_worktrees(
            [main_wt, feature_wt, bugfix_wt],
            WorktreeFilterOptions(exclude_current=True),
            main_path="/home/user/repo",
            current_path="/home/user/repo.WT.feature-1",
        )
        assert len(result) == 2
        assert all(w.path != "/home/user/repo.WT.feature-1" for w in result)

    def test_exclude_main_and_current(self, main_wt, feature_wt, bugfix_wt):
        """git-wtdel scenario: exclude both main and current."""
        result = filter_worktrees(
            [main_wt, feature_wt, bugfix_wt],
            WorktreeFilterOptions(include_main=False, exclude_current=True),
            main_path="/home/user/repo",
            current_path="/home/user/repo.WT.feature-1",
        )
        assert len(result) == 1
        assert result[0].path == "/home/user/repo.WT.bugfix-2"

    def test_exclude_current_when_in_main(self, main_wt, feature_wt):
        """When current IS main, both filters overlap correctly."""
        result = filter_worktrees(
            [main_wt, feature_wt],
            WorktreeFilterOptions(include_main=False, exclude_current=True),
            main_path="/home/user/repo",
            current_path="/home/user/repo",
        )
        assert len(result) == 1
        assert result[0].path == "/home/user/repo.WT.feature-1"

    def test_empty_input(self):
        result = filter_worktrees(
            [],
            WorktreeFilterOptions(),
            main_path="/home/user/repo",
            current_path="/home/user/repo",
        )
        assert result == []

    def test_all_excluded(self, main_wt):
        """When only main exists and we exclude it."""
        result = filter_worktrees(
            [main_wt],
            WorktreeFilterOptions(include_main=False),
            main_path="/home/user/repo",
            current_path="/home/user/repo",
        )
        assert result == []

    def test_does_not_mutate_input(self, main_wt, feature_wt):
        original = [main_wt, feature_wt]
        original_len = len(original)
        filter_worktrees(
            original,
            WorktreeFilterOptions(include_main=False),
            main_path="/home/user/repo",
            current_path="/home/user/repo",
        )
        assert len(original) == original_len
```

**Step 2: Run tests to verify they fail**

Run: `cd git-config/lib/python && python3 -m pytest tests/test_worktree_select.py::TestFilterWorktrees -v`
Expected: FAIL — `filter_worktrees` not found.

**Step 3: Write implementation**

```python
def filter_worktrees(
    worktrees: list[WorktreeInfo],
    options: WorktreeFilterOptions,
    main_path: str,
    current_path: str,
) -> list[WorktreeInfo]:
    """Apply inclusion/exclusion filters to a list of worktrees.

    Pure function — no side effects, no git calls. The caller provides
    main_path and current_path so this function needs no subprocess access.

    Args:
        worktrees: Input worktree records; not mutated.
        options: Filtering criteria.
        main_path: Absolute path to the main repository worktree.
        current_path: Absolute path to the worktree the user is currently in.

    Returns:
        New list containing only worktrees that pass all active filters,
        preserving original ordering.
    """
    result = list(worktrees)

    if not options.include_main:
        result = [w for w in result if w.path != main_path]

    if options.exclude_current:
        result = [w for w in result if w.path != current_path]

    return result
```

**Step 4: Run tests to verify they pass**

Run: `cd git-config/lib/python && python3 -m pytest tests/test_worktree_select.py::TestFilterWorktrees -v`
Expected: PASS

**Step 5: Commit**

```bash
git add git-config/lib/python/git/worktree_select.py git-config/lib/python/tests/test_worktree_select.py
git commit -m "feat: add filter_worktrees() pure filtering for worktree selection"
```

---

### Task 3: format_display_rows() display construction

**Files:**
- Modify: `git-config/lib/python/git/worktree_select.py`
- Modify: `git-config/lib/python/tests/test_worktree_select.py`

**Step 1: Write failing tests**

```python
from git.worktree_select import format_display_rows


class TestFormatDisplayRows:
    """Tests for format_display_rows() display formatting."""

    def test_basic_worktree(self, feature_wt):
        rows = format_display_rows([feature_wt], current_path="/other")
        assert len(rows) == 1
        assert "feature-1" in rows[0]
        assert "def5678" in rows[0]

    def test_current_indicator(self, feature_wt):
        rows = format_display_rows(
            [feature_wt], current_path="/home/user/repo.WT.feature-1"
        )
        assert "[CURRENT]" in rows[0]

    def test_dirty_indicator(self, feature_wt):
        rows = format_display_rows([feature_wt], current_path="/other")
        assert "[DIRTY]" in rows[0]

    def test_locked_indicator(self, bugfix_wt):
        rows = format_display_rows([bugfix_wt], current_path="/other")
        assert "[LOCKED]" in rows[0]

    def test_clean_unlocked_no_indicators(self, main_wt):
        rows = format_display_rows([main_wt], current_path="/other")
        assert "[CURRENT]" not in rows[0]
        assert "[DIRTY]" not in rows[0]
        assert "[LOCKED]" not in rows[0]

    def test_all_indicators_combined(self):
        wt = WorktreeInfo(
            path="/home/user/repo.WT.x", branch="x", commit="aaa1111",
            is_dirty=True, is_locked=True,
        )
        rows = format_display_rows([wt], current_path="/home/user/repo.WT.x")
        assert "[CURRENT]" in rows[0]
        assert "[DIRTY]" in rows[0]
        assert "[LOCKED]" in rows[0]

    def test_path_shortened_with_home(self):
        home = os.path.expanduser("~")
        wt = WorktreeInfo(
            path=f"{home}/projects/repo.WT.feat", branch="feat", commit="bbb2222",
            is_dirty=False, is_locked=False,
        )
        rows = format_display_rows([wt], current_path="/other")
        assert "~/projects/repo.WT.feat" in rows[0]

    def test_path_outside_home_not_shortened(self):
        wt = WorktreeInfo(
            path="/tmp/repo.WT.feat", branch="feat", commit="ccc3333",
            is_dirty=False, is_locked=False,
        )
        rows = format_display_rows([wt], current_path="/other")
        assert "/tmp/repo.WT.feat" in rows[0]

    def test_detached_head_empty_branch(self):
        wt = WorktreeInfo(
            path="/home/user/repo", branch="", commit="ddd4444",
            is_dirty=False, is_locked=False,
        )
        rows = format_display_rows([wt], current_path="/other")
        assert "(detached)" in rows[0] or "ddd4444" in rows[0]

    def test_multiple_worktrees_preserves_order(self, main_wt, feature_wt, bugfix_wt):
        rows = format_display_rows(
            [main_wt, feature_wt, bugfix_wt], current_path="/other"
        )
        assert len(rows) == 3
        assert "main" in rows[0]
        assert "feature-1" in rows[1]
        assert "bugfix-2" in rows[2]

    def test_empty_list(self):
        rows = format_display_rows([], current_path="/other")
        assert rows == []
```

**Step 2: Run tests to verify they fail**

Run: `cd git-config/lib/python && python3 -m pytest tests/test_worktree_select.py::TestFormatDisplayRows -v`
Expected: FAIL

**Step 3: Write implementation**

```python
def format_display_rows(worktrees: list[WorktreeInfo], current_path: str) -> list[str]:
    """Build formatted selection rows for interactive display.

    Produces the same visual layout as the Bash menu_items[] construction
    that was triplicated across git-wt, git-wtdel, and git-wtsh:
        "[CURRENT] [DIRTY] [LOCKED] branch (commit) → ~/path"

    Plain text (no ANSI) — gum handles its own styling, and numbered-list
    mode prints to stderr where colors aren't needed.

    Args:
        worktrees: Worktree records to format; not mutated.
        current_path: Current worktree path, for [CURRENT] indicator.

    Returns:
        List of formatted strings, one per worktree, in same order.
    """
    home = os.path.expanduser("~")
    rows: list[str] = []

    for wt in worktrees:
        parts: list[str] = []

        # Status indicators — same order as Bash: CURRENT, DIRTY, LOCKED
        if wt.path == current_path:
            parts.append("[CURRENT]")
        if wt.is_dirty:
            parts.append("[DIRTY]")
        if wt.is_locked:
            parts.append("[LOCKED]")

        # Branch name (or "detached" for detached HEAD)
        branch_display = wt.branch if wt.branch else "(detached)"
        parts.append(f"{branch_display} ({wt.commit})")

        # Path, shortened with ~ for home directory
        display_path = wt.path
        if display_path.startswith(home):
            display_path = "~" + display_path[len(home):]

        parts.append(f"\u2192 {display_path}")

        rows.append(" ".join(parts))

    return rows
```

**Step 4: Run tests to verify they pass**

Run: `cd git-config/lib/python && python3 -m pytest tests/test_worktree_select.py::TestFormatDisplayRows -v`
Expected: PASS

**Step 5: Commit**

```bash
git add git-config/lib/python/git/worktree_select.py git-config/lib/python/tests/test_worktree_select.py
git commit -m "feat: add format_display_rows() for worktree selection display"
```

---

### Task 4: Bash declare output functions

**Files:**
- Modify: `git-config/lib/python/git/worktree_select.py`
- Modify: `git-config/lib/python/tests/test_worktree_select.py`

**Step 1: Write failing tests**

```python
from git.worktree_select import worktrees_to_bash_declare, selection_to_bash_declare


class TestWorktreesToBashDeclare:
    """Tests for worktrees_to_bash_declare() — prepare mode output."""

    def test_normal_output(self, feature_wt, bugfix_wt):
        formatted = ["feature-1 (def5678) → ~/repo.WT.feature-1",
                      "bugfix-2 (123abcd) → ~/repo.WT.bugfix-2"]
        output = worktrees_to_bash_declare([feature_wt, bugfix_wt], formatted)
        assert "declare -a worktree_paths=(" in output
        assert "declare -a formatted_options=(" in output
        assert "selection_status='ready'" in output
        assert "worktree_count=2" in output

    def test_empty_no_worktrees(self):
        output = worktrees_to_bash_declare([], [])
        assert "declare -a worktree_paths=()" in output
        assert "declare -a formatted_options=()" in output
        assert "selection_status='no_worktrees'" in output
        assert "worktree_count=0" in output

    def test_empty_with_custom_status(self):
        output = worktrees_to_bash_declare([], [], status="no_worktrees")
        assert "selection_status='no_worktrees'" in output

    def test_paths_with_spaces_escaped(self):
        wt = WorktreeInfo(
            path="/home/user/my repo.WT.feat", branch="feat", commit="aaa1111",
            is_dirty=False, is_locked=False,
        )
        output = worktrees_to_bash_declare([wt], ["feat (aaa1111)"])
        assert "/home/user/my repo.WT.feat" in output


class TestSelectionToBashDeclare:
    """Tests for selection_to_bash_declare() — select mode output."""

    def test_selected(self):
        result = WorktreeSelectionResult(status="selected", path="/path/to/wt")
        output = selection_to_bash_declare(result)
        assert "selected_path='/path/to/wt'" in output
        assert "selection_status='selected'" in output

    def test_cancelled(self):
        result = WorktreeSelectionResult(status="cancelled", path="")
        output = selection_to_bash_declare(result)
        assert "selected_path=''" in output
        assert "selection_status='cancelled'" in output

    def test_no_worktrees(self):
        result = WorktreeSelectionResult(status="no_worktrees", path="")
        output = selection_to_bash_declare(result)
        assert "selection_status='no_worktrees'" in output
```

**Step 2: Run tests to verify they fail**

Run: `cd git-config/lib/python && python3 -m pytest tests/test_worktree_select.py -k "BashDeclare" -v`
Expected: FAIL

**Step 3: Write implementation**

```python
def worktrees_to_bash_declare(
    worktrees: list[WorktreeInfo],
    formatted: list[str],
    status: str = "no_worktrees",
) -> str:
    """Serialize worktrees and display rows to bash declare statements.

    Used by the 'prepare' CLI command (gum path). The Bash adapter evals
    the output to get worktree_paths[] and formatted_options[] for
    gum_filter_by_index.

    Args:
        worktrees: Filtered WorktreeInfo records.
        formatted: Display rows parallel to worktrees (same length).
        status: Status for the empty case (default "no_worktrees").

    Returns:
        Multi-line string of bash variable declarations.
    """
    if not worktrees:
        return (
            "declare -a worktree_paths=()\n"
            "declare -a formatted_options=()\n"
            f"selection_status={_bash_escape(status)}\n"
            "worktree_count=0"
        )

    lines: list[str] = []
    paths_arr = " ".join(_bash_escape(w.path) for w in worktrees)
    lines.append(f"declare -a worktree_paths=({paths_arr})")

    opts_arr = " ".join(_bash_escape(f) for f in formatted)
    lines.append(f"declare -a formatted_options=({opts_arr})")

    lines.append("selection_status='ready'")
    lines.append(f"worktree_count={len(worktrees)}")

    return "\n".join(lines)


def selection_to_bash_declare(result: WorktreeSelectionResult) -> str:
    """Serialize a WorktreeSelectionResult to bash declare statements.

    Used by the 'select' CLI command (numbered-list path).

    Args:
        result: Selection outcome to serialize.

    Returns:
        Multi-line string of bash variable declarations.
    """
    lines: list[str] = []
    lines.append(f"selected_path={_bash_escape(result.path)}")
    lines.append(f"selection_status={_bash_escape(result.status)}")
    return "\n".join(lines)
```

**Step 4: Run tests to verify they pass**

Run: `cd git-config/lib/python && python3 -m pytest tests/test_worktree_select.py -k "BashDeclare" -v`
Expected: PASS

**Step 5: Commit**

```bash
git add git-config/lib/python/git/worktree_select.py git-config/lib/python/tests/test_worktree_select.py
git commit -m "feat: add bash declare output functions for worktree selection"
```

---

### Task 5: Git integration — _load_worktrees()

**Files:**
- Modify: `git-config/lib/python/git/worktree_select.py`
- Modify: `git-config/lib/python/tests/test_worktree_select.py`

**Step 1: Write failing tests**

```python
from git.worktree_select import _run_git, _load_worktrees


class TestRunGit:
    """Tests for _run_git() subprocess helper."""

    @patch("git.worktree_select.subprocess.run")
    def test_returns_stdout_stripped(self, mock_run):
        mock_run.return_value = subprocess.CompletedProcess(
            args=[], returncode=0, stdout="  output  \n", stderr=""
        )
        assert _run_git(["status"]) == "output"

    @patch("git.worktree_select.subprocess.run")
    def test_returns_empty_on_failure(self, mock_run):
        mock_run.return_value = subprocess.CompletedProcess(
            args=[], returncode=1, stdout="", stderr="error"
        )
        assert _run_git(["bad-command"]) == ""

    @patch("git.worktree_select.subprocess.run")
    def test_returns_empty_on_timeout(self, mock_run):
        mock_run.side_effect = subprocess.TimeoutExpired(cmd="git", timeout=10)
        assert _run_git(["slow-command"]) == ""


class TestLoadWorktrees:
    """Tests for _load_worktrees() git integration."""

    @patch("git.worktree_select._run_git")
    @patch("git.worktree_select.parse_worktree_list")
    def test_returns_worktrees_and_paths(self, mock_parse, mock_git):
        mock_git.side_effect = lambda args: {
            ("rev-parse", "--show-toplevel"): "/home/user/repo",
            ("rev-parse", "--git-common-dir"): ".git",
        }.get(tuple(args), "porcelain output")

        mock_parse.return_value = [
            WorktreeInfo("/home/user/repo", "main", "abc1234", False, False),
        ]

        worktrees, main_path, current_path = _load_worktrees()
        assert len(worktrees) == 1
        assert main_path == "/home/user/repo"
        assert current_path == "/home/user/repo"

    @patch("git.worktree_select._run_git")
    def test_returns_empty_when_not_in_repo(self, mock_git):
        mock_git.return_value = ""
        worktrees, main_path, current_path = _load_worktrees()
        assert worktrees == []

    @patch("git.worktree_select._run_git")
    @patch("git.worktree_select.parse_worktree_list")
    def test_detects_worktree_vs_main(self, mock_parse, mock_git):
        """When in a worktree, main_path differs from current_path."""
        mock_git.side_effect = lambda args: {
            ("rev-parse", "--show-toplevel"): "/home/user/repo.WT.feat",
            ("rev-parse", "--git-common-dir"): "/home/user/repo/.git",
        }.get(tuple(args), "porcelain output")

        mock_parse.return_value = []

        _, main_path, current_path = _load_worktrees()
        assert main_path == "/home/user/repo"
        assert current_path == "/home/user/repo.WT.feat"
```

**Step 2: Run tests to verify they fail**

Run: `cd git-config/lib/python && python3 -m pytest tests/test_worktree_select.py -k "RunGit or LoadWorktrees" -v`
Expected: FAIL

**Step 3: Write implementation**

```python
def _run_git(args: list[str]) -> str:
    """Run a git command and return stripped stdout; empty string on failure.

    Uses 'git --no-pager' to prevent interactive pager in non-TTY contexts.
    """
    try:
        result = subprocess.run(
            ["git", "--no-pager"] + args,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return ""
        return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def _load_worktrees() -> tuple[list[WorktreeInfo], str, str]:
    """Load all worktrees from git and detect main/current paths.

    Returns:
        Tuple of (all_worktrees, main_repo_path, current_worktree_path).
        On failure, returns ([], "", "").

    Detection logic:
    - current_path: git rev-parse --show-toplevel (current worktree root)
    - main_path: derived from git rev-parse --git-common-dir
      - ".git" means we're in the main repo (main_path == current_path)
      - Otherwise it's the main repo's .git dir; strip the /.git suffix

    All worktrees are loaded with include_main=True so that filter_worktrees()
    can make its own inclusion/exclusion decisions.
    """
    current_path = _run_git(["rev-parse", "--show-toplevel"])
    if not current_path:
        return [], "", ""

    # Detect main repo path: --git-common-dir returns ".git" when in main repo,
    # or "/path/to/main/.git" when in a worktree.
    git_common_dir = _run_git(["rev-parse", "--git-common-dir"])
    if git_common_dir == ".git":
        main_path = current_path
    elif git_common_dir:
        # Strip trailing /.git to get the main repo directory
        main_path = git_common_dir.removesuffix("/.git")
    else:
        main_path = current_path

    # Get porcelain output
    porcelain = _run_git(["worktree", "list", "--porcelain"])
    if not porcelain:
        return [], main_path, current_path

    worktrees = parse_worktree_list(porcelain, main_path, include_main=True)
    return worktrees, main_path, current_path
```

**Step 4: Run tests to verify they pass**

Run: `cd git-config/lib/python && python3 -m pytest tests/test_worktree_select.py -k "RunGit or LoadWorktrees" -v`
Expected: PASS

**Step 5: Commit**

```bash
git add git-config/lib/python/git/worktree_select.py git-config/lib/python/tests/test_worktree_select.py
git commit -m "feat: add _load_worktrees() git integration for worktree selection"
```

---

### Task 6: CLI entry point — prepare and select commands

**Files:**
- Modify: `git-config/lib/python/git/worktree_select.py`
- Modify: `git-config/lib/python/tests/test_worktree_select.py`

**Step 1: Write failing tests**

```python
from git.worktree_select import _cmd_prepare, _cmd_select


class TestCmdPrepare:
    """Tests for _cmd_prepare() — gum path."""

    @patch("git.worktree_select._load_worktrees")
    def test_normal_output(self, mock_load):
        mock_load.return_value = (
            [WorktreeInfo("/home/user/repo.WT.feat", "feat", "abc1234", False, False)],
            "/home/user/repo",
            "/home/user/repo",
        )
        output = _cmd_prepare(
            WorktreeFilterOptions(include_main=False, exclude_current=False)
        )
        assert "declare -a worktree_paths=(" in output
        assert "declare -a formatted_options=(" in output
        assert "selection_status='ready'" in output
        assert "worktree_count=1" in output

    @patch("git.worktree_select._load_worktrees")
    def test_no_worktrees(self, mock_load):
        mock_load.return_value = ([], "/repo", "/repo")
        output = _cmd_prepare(WorktreeFilterOptions())
        assert "selection_status='no_worktrees'" in output
        assert "worktree_count=0" in output

    @patch("git.worktree_select._load_worktrees")
    def test_all_filtered_out(self, mock_load):
        mock_load.return_value = (
            [WorktreeInfo("/home/user/repo", "main", "abc1234", False, False)],
            "/home/user/repo",
            "/home/user/repo",
        )
        # Exclude main, and main is the only worktree
        output = _cmd_prepare(
            WorktreeFilterOptions(include_main=False, exclude_current=False)
        )
        assert "selection_status='no_worktrees'" in output


class TestCmdSelect:
    """Tests for _cmd_select() — numbered-list path."""

    @patch("builtins.input", return_value="1")
    @patch("git.worktree_select._load_worktrees")
    def test_valid_selection(self, mock_load, mock_input):
        mock_load.return_value = (
            [WorktreeInfo("/home/user/repo.WT.feat", "feat", "abc1234", False, False)],
            "/home/user/repo",
            "/home/user/repo",
        )
        output = _cmd_select(
            WorktreeFilterOptions(include_main=False),
            prompt="Select worktree",
        )
        assert "selected_path='/home/user/repo.WT.feat'" in output
        assert "selection_status='selected'" in output

    @patch("builtins.input", return_value="")
    @patch("git.worktree_select._load_worktrees")
    def test_cancelled(self, mock_load, mock_input):
        mock_load.return_value = (
            [WorktreeInfo("/home/user/repo.WT.feat", "feat", "abc1234", False, False)],
            "/home/user/repo",
            "/home/user/repo",
        )
        output = _cmd_select(
            WorktreeFilterOptions(include_main=False),
            prompt="Select worktree",
        )
        assert "selection_status='cancelled'" in output

    @patch("builtins.input", return_value="99")
    @patch("git.worktree_select._load_worktrees")
    def test_invalid_number(self, mock_load, mock_input):
        mock_load.return_value = (
            [WorktreeInfo("/home/user/repo.WT.feat", "feat", "abc1234", False, False)],
            "/home/user/repo",
            "/home/user/repo",
        )
        output = _cmd_select(
            WorktreeFilterOptions(include_main=False),
            prompt="Select worktree",
        )
        assert "selection_status='cancelled'" in output

    @patch("builtins.input", return_value="abc")
    @patch("git.worktree_select._load_worktrees")
    def test_non_numeric_input(self, mock_load, mock_input):
        mock_load.return_value = (
            [WorktreeInfo("/home/user/repo.WT.feat", "feat", "abc1234", False, False)],
            "/home/user/repo",
            "/home/user/repo",
        )
        output = _cmd_select(
            WorktreeFilterOptions(include_main=False),
            prompt="Select worktree",
        )
        assert "selection_status='cancelled'" in output

    @patch("builtins.input", side_effect=EOFError)
    @patch("git.worktree_select._load_worktrees")
    def test_eof_on_input(self, mock_load, mock_input):
        mock_load.return_value = (
            [WorktreeInfo("/home/user/repo.WT.feat", "feat", "abc1234", False, False)],
            "/home/user/repo",
            "/home/user/repo",
        )
        output = _cmd_select(
            WorktreeFilterOptions(include_main=False),
            prompt="Select worktree",
        )
        assert "selection_status='cancelled'" in output

    @patch("git.worktree_select._load_worktrees")
    def test_no_worktrees(self, mock_load):
        mock_load.return_value = ([], "/repo", "/repo")
        output = _cmd_select(WorktreeFilterOptions(), prompt="Select worktree")
        assert "selection_status='no_worktrees'" in output

    @patch("builtins.input", return_value="2")
    @patch("git.worktree_select._load_worktrees")
    def test_selects_second_item(self, mock_load, mock_input):
        mock_load.return_value = (
            [
                WorktreeInfo("/home/user/repo.WT.feat", "feat", "abc1234", False, False),
                WorktreeInfo("/home/user/repo.WT.fix", "fix", "def5678", False, False),
            ],
            "/home/user/repo",
            "/home/user/repo",
        )
        output = _cmd_select(
            WorktreeFilterOptions(include_main=False),
            prompt="Select worktree",
        )
        assert "selected_path='/home/user/repo.WT.fix'" in output
```

**Step 2: Run tests to verify they fail**

Run: `cd git-config/lib/python && python3 -m pytest tests/test_worktree_select.py -k "CmdPrepare or CmdSelect" -v`
Expected: FAIL

**Step 3: Write implementation**

```python
def _cmd_prepare(options: WorktreeFilterOptions) -> str:
    """Execute the 'prepare' CLI command (gum path).

    Loads worktrees, applies filters, formats display rows, and returns
    bash declare statements for gum_filter_by_index.
    """
    worktrees, main_path, current_path = _load_worktrees()
    if not worktrees:
        return worktrees_to_bash_declare([], [])

    filtered = filter_worktrees(worktrees, options, main_path, current_path)
    if not filtered:
        return worktrees_to_bash_declare([], [])

    formatted = format_display_rows(filtered, current_path)
    return worktrees_to_bash_declare(filtered, formatted)


def _cmd_select(options: WorktreeFilterOptions, prompt: str) -> str:
    """Execute the 'select' CLI command (numbered-list path).

    Loads worktrees, applies filters, presents a numbered list on stderr,
    reads user input, and returns bash declare statements with the result.

    Printing to stderr ensures that eval "$(python3 worktree_select.py select ...)"
    works correctly — eval only processes stdout.
    """
    worktrees, main_path, current_path = _load_worktrees()
    if not worktrees:
        return selection_to_bash_declare(
            WorktreeSelectionResult(status="no_worktrees", path="")
        )

    filtered = filter_worktrees(worktrees, options, main_path, current_path)
    if not filtered:
        return selection_to_bash_declare(
            WorktreeSelectionResult(status="no_worktrees", path="")
        )

    formatted = format_display_rows(filtered, current_path)

    # Display numbered list to stderr (stdout reserved for declare output)
    print(f"\n{prompt}:\n", file=sys.stderr)
    for i, row in enumerate(formatted):
        print(f"  {i + 1:2d}) {row}", file=sys.stderr)
    print(file=sys.stderr)

    # Read user selection
    try:
        user_input = input("Enter number (or press Enter to cancel): ").strip()
    except EOFError:
        user_input = ""

    if not user_input:
        return selection_to_bash_declare(
            WorktreeSelectionResult(status="cancelled", path="")
        )

    # Parse and validate selection
    try:
        idx = int(user_input) - 1  # Convert 1-based to 0-based
        if 0 <= idx < len(filtered):
            return selection_to_bash_declare(
                WorktreeSelectionResult(status="selected", path=filtered[idx].path)
            )
    except ValueError:
        pass

    # Invalid input
    return selection_to_bash_declare(
        WorktreeSelectionResult(status="cancelled", path="")
    )


def main() -> None:
    """CLI entry point for bash wrapper calls.

    Commands:
        prepare   Load + filter + format; output bash declares for gum path.
        select    Load + filter + numbered-list interaction; output bash declares.

    Both commands exit 0 and communicate outcomes via bash variables.
    Non-zero exits are reserved for genuine Python-level failures.
    """
    parser = argparse.ArgumentParser(
        description="Worktree selection for Hug SCM — consolidated from three Bash scripts"
    )
    parser.add_argument(
        "command",
        choices=["prepare", "select"],
        help="'prepare' for gum path; 'select' for numbered-list path",
    )
    parser.add_argument(
        "--include-main",
        action="store_true",
        default=False,
        help="Include main repository worktree in selection",
    )
    parser.add_argument(
        "--exclude-current",
        action="store_true",
        default=False,
        help="Exclude the current worktree from selection",
    )
    parser.add_argument(
        "--prompt",
        default="Select a worktree",
        help="Prompt text (select command only)",
    )

    args = parser.parse_args()

    options = WorktreeFilterOptions(
        include_main=args.include_main,
        exclude_current=args.exclude_current,
    )

    try:
        if args.command == "prepare":
            output = _cmd_prepare(options)
        else:
            output = _cmd_select(options, prompt=args.prompt)
        print(output)

    except Exception as exc:
        print(f"worktree_select: unexpected error: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
```

**Step 4: Run tests to verify they pass**

Run: `cd git-config/lib/python && python3 -m pytest tests/test_worktree_select.py -v`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add git-config/lib/python/git/worktree_select.py git-config/lib/python/tests/test_worktree_select.py
git commit -m "feat: add CLI entry point with prepare/select commands for worktree selection"
```

---

### Task 7: Bash adapter — select_worktree() in hug-git-worktree

**Files:**
- Modify: `git-config/lib/hug-git-worktree`

**Step 1: Add select_worktree() function**

Add this function after the existing `get_all_worktrees_including_main()` function
(after line 146). This is the shared adapter that replaces triplicated selection
logic in the three command scripts.

```bash
################################################################################
# Worktree Interactive Selection — Python-backed adapter
################################################################################

# Universal worktree selection function — delegates to Python worktree_select.py
# Usage: select_worktree selected_path_var [options]
# Parameters:
#   $1 - Name of variable to receive selected worktree path (nameref)
# Options:
#   --include-main      Include the main repository worktree in the list
#   --exclude-current   Exclude the current worktree from the list
#   --prompt TEXT        Custom prompt text for selection
# Returns:
#   0 if a worktree was selected (path stored in $1)
#   1 if selection was cancelled by the user
#   2 if no worktrees available, or an error occurred
#
# WHY: This function consolidates ~300 lines of triplicated menu-building and
# gum-selection code from git-wt, git-wtdel, and git-wtsh into a single adapter.
# Python handles filtering, formatting, and numbered-list interaction; Bash keeps
# gum integration via the existing gum_filter_by_index API.
select_worktree() {
    local -n _sw_result_ref="$1"
    shift

    local prompt="Select a worktree"
    local -a python_args=()

    # Parse options — build python_args for passthrough to Python CLI
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --include-main)
                python_args+=(--include-main)
                shift
                ;;
            --exclude-current)
                python_args+=(--exclude-current)
                shift
                ;;
            --prompt)
                prompt="$2"
                python_args+=(--prompt "$2")
                shift 2
                ;;
            *)
                error "Unknown option for select_worktree: $1"
                return 2
                ;;
        esac
    done

    local worktree_select_py="$HUG_HOME/git-config/lib/python/git/worktree_select.py"

    # Gum path: Python prepares data, Bash handles gum via gum_filter_by_index
    if gum_available; then
        # shellcheck disable=SC2034  # variables set by eval from Python output
        local -a worktree_paths=() formatted_options=()
        local selection_status="" worktree_count=0

        if ! eval "$(python3 "$worktree_select_py" prepare "${python_args[@]}")"; then
            return 2
        fi

        # Check for no-data states
        if [[ "$selection_status" != "ready" ]]; then
            _sw_result_ref=""
            return 2
        fi

        # Use gum for >= 10 items, numbered list otherwise
        if [[ $worktree_count -ge 10 ]]; then
            local selection_output=""
            if ! selection_output=$(gum_filter_by_index formatted_options "$prompt"); then
                _sw_result_ref=""
                return 1
            fi

            # Map gum's returned index to worktree path
            local selected_index
            selected_index=$(head -1 <<< "$selection_output")
            _sw_result_ref="${worktree_paths[$selected_index]}"
            return 0
        fi

        # < 10 items with gum available: fall through to select mode below
    fi

    # Non-gum path (or < 10 items): Python handles numbered-list interaction
    # shellcheck disable=SC2034  # variables set by eval from Python output
    local selected_path=""
    local selection_status=""

    if ! eval "$(python3 "$worktree_select_py" select "${python_args[@]}")"; then
        return 2
    fi

    case "$selection_status" in
        selected)
            _sw_result_ref="$selected_path"
            return 0
            ;;
        cancelled)
            _sw_result_ref=""
            return 1
            ;;
        *)
            _sw_result_ref=""
            return 2
            ;;
    esac
}
```

**Step 2: Commit**

```bash
git add git-config/lib/hug-git-worktree
git commit -m "feat: add select_worktree() Python-backed adapter in hug-git-worktree"
```

---

### Task 8: Refactor git-wt, git-wtdel, git-wtsh

**Files:**
- Modify: `git-config/bin/git-wt`
- Modify: `git-config/bin/git-wtdel`
- Modify: `git-config/bin/git-wtsh`

**Step 1: Refactor git-wt interactive selection block**

Replace lines 207–335 (the entire "No path argument provided" block) with:

```bash
# No path argument provided - show interactive menu
selected_path=""
if ! select_worktree selected_path --exclude-current --prompt "Select worktree to switch to"; then
  select_rc=$?
  if [[ $select_rc -eq 2 ]]; then
    info "No worktrees found. Use 'hug wtc <branch>' to create one."
    info "Example: hug wtc feature-auth"
  fi
  # rc=1 means user cancelled (select_worktree already set selected_path="")
  exit 0
fi

# Check if it's the current worktree (defensive — should be excluded by filter)
current_worktree=$(get_current_worktree_path)
if [[ "$selected_path" == "$current_worktree" ]]; then
  info "Already in worktree: $selected_path"
  current_branch=$(git branch --show-current 2> /dev/null || echo "detached")
  info "Current branch: $current_branch"
  exit 0
fi

switch_to_worktree "$selected_path"
exit $?
```

**Step 2: Refactor git-wtdel interactive selection**

Replace the `show_interactive_removal_menu()` function (lines 53–185) with:

```bash
show_interactive_removal_menu() {
  local selected_path=""
  if ! select_worktree selected_path --exclude-current --prompt "Select worktree to remove"; then
    local select_rc=$?
    if [[ $select_rc -eq 2 ]]; then
      info "No removable worktrees found."
    fi
    return 1
  fi
  printf '%s' "$selected_path"
  return 0
}
```

**Step 3: Refactor git-wtsh interactive selection**

Replace the `interactive_worktree_selection()` function (lines 78–146) with:

```bash
interactive_worktree_selection() {
  local current_worktree="$1"

  local selected_path=""
  if ! select_worktree selected_path --include-main --prompt "Select worktree to show details"; then
    local select_rc=$?
    if [[ $select_rc -eq 2 ]]; then
      error "No worktrees found for interactive selection"
    fi
    return $select_rc
  fi

  show_worktree_details "$current_worktree" "$selected_path"
  return 0
}
```

Note: The `gum_available` check and hard error in the original git-wtsh is
REMOVED — `select_worktree` handles both gum and non-gum paths transparently,
giving git-wtsh the numbered-list fallback it never had.

**Step 4: Commit**

```bash
git add git-config/bin/git-wt git-config/bin/git-wtdel git-config/bin/git-wtsh
git commit -m "refactor: replace worktree selection with Python-backed select_worktree()"
```

---

### Task 9: BATS regression validation

**Step 1: Run full test suite**

Run: `make test`
Expected: ALL BATS and pytest tests pass.

**Step 2: Run worktree-specific tests if any exist**

Run: `make test-bash TEST_FILTER="worktree\|wt"`
Expected: All worktree-related tests pass.

**Step 3: Run Python tests with coverage**

Run: `make test-lib-py TEST_FILTER="test_worktree"`
Expected: All worktree_select tests pass.

**Step 4: Commit (no changes expected — this is validation only)**

No commit needed unless test fixes are required.

---

### Task 10: Final cleanup and documentation

**Files:**
- Modify: `git-config/lib/python/README.md`

**Step 1: Update Python helper documentation**

Add `worktree_select.py` to the "Bash-to-Python Migration Modules" section:

```markdown
- ✅ `git/worktree_select.py` - Worktree selection with cross-module import (NNN lines, NN tests ✓)
```

**Step 2: Commit**

```bash
git add git-config/lib/python/README.md
git commit -m "docs: add worktree_select.py to Python helper documentation"
```

**Step 3: Update task persistence file**

Write `docs/plans/2026-03-13-worktree-selection-python-migration.md.tasks.json`
with all tasks marked as completed.
